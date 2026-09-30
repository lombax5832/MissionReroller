-- Controlled read-only search checkpoint: fixed filter, no UI or publication.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
-- hooks: bind_constellations, on_existing_match, on_search_match, and
-- validate_search_request, which the assembler adds once the dialog exists.
local M,emit,read,u,snapshot,config=host.M,host.emit,host.read,host.u,host.snapshot,host.config
local reroll_session=host.reroll_session
local Search,composition_factory=lib.Search,lib.composition_factory
local candidate_factory,make_search_job=lib.candidate_factory,lib.make_search_job
local bind_constellations,on_existing_match,on_search_match=hooks.bind_constellations,hooks.on_existing_match,hooks.on_search_match
local api,game,ffi,kernel
host.when_initialized(function(n)api,game,ffi,kernel=n.api,n.game,n.ffi,n.kernel end)
local on_prediction_ready,advance_prediction_search
local current_search,search_started,last_progress,max_slice
local slices,step_time,context_time
local wait_started,wait_total,last_wait_poll
local default_limit=1000000
-- The last range searched without a match, so an unchanged request continues
-- after it instead of repeating it.
local resume
local precise
local function search_clock()
    if precise==nil then
        precise=false
        pcall(function()
            ffi.cdef[[int QueryPerformanceCounter(int64_t *);int QueryPerformanceFrequency(int64_t *);]]
            local value=ffi.new('int64_t[1]')
            assert(kernel.QueryPerformanceFrequency(value)~=0 and value[0]>0)
            local frequency=tonumber(value[0])
            assert(kernel.QueryPerformanceCounter(value)~=0)
            precise=function()
                kernel.QueryPerformanceCounter(value);return tonumber(value[0])/frequency
            end
        end)
    end
    return precise and precise() or api.time()
end
-- The operation in progress keeps its seed and missions whatever the campaign
-- seed becomes (operation_identity preserves its row). Returns its row and
-- difficulty when it belongs to the snapshot's planet.
M.active_row=function(s)
    local record=s and s.active
    if type(record)~='string' or #record~=184 then return nil end
    local function byte(at)return tonumber(record:sub(at*2+1,at*2+2),16)end
    if byte(52)==0 or byte(16)+byte(17)*256~=s.planet then return nil end
    return byte(0)+byte(1)*256+byte(2)*65536+byte(3)*16777216,byte(32)
end
local function request_key(difficulty,required,modifiers,constellations,scope)
    local parts={'d'..difficulty,'r'..(scope and scope.region or 'all')}
    for id in pairs(required)do parts[#parts+1]='m'..id end
    for id,mode in pairs(modifiers)do parts[#parts+1]=string.format('o%u:%s',id,mode)end
    for group,tags in pairs(constellations and constellations.groups or {})do
        for tag,mode in pairs(tags)do parts[#parts+1]='c'..group..':'..tag..':'..mode end
    end
    table.sort(parts);return table.concat(parts,',')
end
on_prediction_ready=function(s,definitions,now)
    assert(definitions,'Missing captured definitions')
    local request=M.search_options or {difficulty=10,required={[1]=true,[2]=true,[3]=true}}
    local required={};for id,value in pairs(request.required)do required[id]=value end
    local modifiers={};for id,value in pairs(request.modifiers or {})do modifiers[id]=value end
    local limit=request.limit or default_limit
    local scope=Search.scope(request.scope)
    M.search_report=nil
    local constellations
    if request.constellations and next(request.constellations.groups)then
        if not bind_constellations then reroll_session.finish('search_failed');emit('FILTER_BLOCKED Constellation filters unavailable');return end
        constellations={groups={}}
        for group,tags in pairs(request.constellations.groups)do
            local copy={};for tag,value in pairs(tags)do copy[tag]=value end
            constellations.groups[group]=copy
        end
    end
    local validate_search_request=hooks.validate_search_request
    if validate_search_request then
        local ok,err=pcall(validate_search_request,s,request)
        if not ok then reroll_session.finish('search_failed');emit('FILTER_BLOCKED '..tostring(err));return end
    end
    if M.dialog_enabled and on_existing_match then
        if constellations then
            local ok,err=pcall(function()
                local annotate=bind_constellations(read,s.board,s.planet)
                for _,op in ipairs(s.decoded.operations)do annotate(op,u(s.operations,op.row*92+28),op.operation_id)end
            end)
            if not ok then reroll_session.finish('search_failed');emit('FILTER_BLOCKED '..tostring(err));return end
        end
        local existing=Search.find(s.decoded,request.difficulty,required,modifiers,constellations,scope)
        if existing then M.search_attempts=0;on_existing_match(s,existing,now);return end
    end
    -- A city has one operation per difficulty. While it is in progress no
    -- seed can change it, so searching would only exhaust the budget.
    local fixed_row,fixed_difficulty=M.active_row(s)
    if scope and fixed_row and fixed_difficulty==request.difficulty and Search.in_scope(fixed_row,scope)then
        reroll_session.finish('search_failed');M.search_report='This operation is in progress; its missions are fixed'
        emit('FILTER_BLOCKED operation in progress row='..fixed_row..'; its missions cannot be rerolled');return
    end
    local function baseline(frozen_read)
        local key=frozen_read(s.board+0x101454+s.planet*0x118,4)
        assert(frozen_read(definitions,4)==key,'Planet definitions changed')
        local result=composition_factory(frozen_read,u,api.pointer,game)(s,definitions)
        assert(result.passed and result.independent_bases,'Frozen baseline prediction mismatch')
    end
    local key=request_key(request.difficulty,required,modifiers,constellations,scope)
    local first=(s.seed+1)%4294967296
    local resumed=resume and resume.key==key and resume.planet==s.planet and resume.baseline==s.seed
    if resumed then first=resume.next end
    current_search=make_search_job(read,baseline,function(frozen_read)
        local predict=candidate_factory(frozen_read,u,api.pointer,game,s.board,definitions,s.planet)
        -- Tag inputs join the frozen read set and are revalidated with it.
        local annotate=constellations and bind_constellations(frozen_read,s.board,s.planet)
        local function accepts(row)return Search.in_scope(row,scope)end
        local function evaluate(seed,difficulty)
            local operations=predict(seed,difficulty,accepts)
            if annotate then for _,op in ipairs(operations)do annotate(op)end end
            return operations
        end
        -- Search the requested difficulty; confirm a match on the whole board.
        return function(seed)return evaluate(seed,request.difficulty)end,function(seed)return evaluate(seed)end
    end,{seed=first,limit=limit,difficulty=request.difficulty,required=required,modifiers=modifiers,
        constellations=constellations,scope=scope,quantum=4096,clock=search_clock,slice=0.016,batch=256,revalidate=1})
    current_search.baseline=s
    current_search.required=required
    current_search.modifiers=modifiers
    current_search.constellations=constellations
    current_search.scope=scope
    current_search.key=key
    M.search_attempts=0
    local backend_waited,quiet_since=false,nil
    current_search.context_check=function()
        local live,reason=snapshot(true)
        if not live and reason=='waiting for pending backend requests' then
            backend_waited=true;quiet_since=nil
            return false,reason
        end
        assert(live,'Search context unavailable: '..tostring(reason))
        assert(live.board==s.board and live.planet==s.planet and live.fingerprint==s.fingerprint,'Search context changed')
        if backend_waited then
            quiet_since=quiet_since or api.time()
            if api.time()-quiet_since<0.5 then return false,'waiting for backend to remain idle' end
            backend_waited=false;quiet_since=nil
        end
    end
    -- Timing only: where each slice spends its time.
    local check=current_search.context_check
    current_search.context_check=function()
        local started=search_clock()
        local ok,ready,reason=pcall(check)
        context_time=context_time+search_clock()-started
        if not ok then error(ready,0)end
        return ready,reason
    end
    slices,step_time,context_time=0,0,0
    search_started=now;last_progress=now;max_slice=0;M.search_result=nil;reroll_session.advance('search_running')
    wait_started=nil;wait_total=0;last_wait_poll=-math.huge
    local names={};for id,opt in ipairs(Search.options)do if required[id]then names[#names+1]=opt.name end end
    local modifier_rules={};for id,mode in pairs(modifiers)do modifier_rules[#modifier_rules+1]=string.format('%u:%s',id,mode)end
    table.sort(modifier_rules);emit('LUA_SEARCH_MODIFIERS '..table.concat(modifier_rules,','))
    if constellations then
        local tag_rules={}
        for group,tags in pairs(constellations.groups)do
            local accepted,excluded={},{}
            for tag,mode in pairs(tags)do
                if mode=='exclude' then excluded[#excluded+1]=tag else accepted[#accepted+1]=tag end
            end
            table.sort(accepted);table.sort(excluded)
            tag_rules[#tag_rules+1]=(group==0 and 'operation' or Search.options[group].name)
                ..'=accept '..(#accepted>0 and table.concat(accepted,'|') or 'any')
                ..(#excluded>0 and ' exclude '..table.concat(excluded,'|') or '')
        end
        table.sort(tag_rules);emit('LUA_SEARCH_CONSTELLATIONS '..table.concat(tag_rules,', '))
    end
    emit(string.format('LUA_SEARCH_STARTED planet=%d region=%s baseline_seed=%u first_seed=%u resumed=%s difficulty=%d required=%s limit=%d read_only='..tostring(M.read_only),
        s.planet,scope and scope.region or 'all',s.seed,first,tostring(resumed==true),request.difficulty,table.concat(names,' + '),limit))
end
advance_prediction_search=function(action,now)
    if not current_search then return false end
    local job=current_search
    M.search_attempts=job.attempts or 0
    local waiting=wait_started and now-wait_started or 0
    if action=='cancel' then job:cancel('Cancelled by shortcut or shutdown')
    elseif waiting>=60 or wait_total+waiting>=120 then job:cancel('Backend wait time limit reached')
    elseif now-search_started-wait_total-waiting>180 then job:cancel('Search time limit reached')
    else
        if wait_started and now-last_wait_poll<0.25 then return true end
        last_wait_poll=now
        local started=search_clock();job:step(job.context_check)
        local spent=search_clock()-started
        slices=slices+1;step_time=step_time+spent;max_slice=math.max(max_slice,spent*1000)
    end
    M.search_attempts=job.attempts or 0
    local elapsed=math.max(now-search_started-wait_total-waiting,0.001)
    local compiled=rawget(_G,'jit') and type(jit.status)=='function' and jit.status()
    local timing=string.format('elapsed_s=%.2f slices=%d work_ms=%.0f context_ms=%.0f jit=%s',elapsed,slices,
        (step_time-context_time)*1000,context_time*1000,tostring(compiled))
    if job.status=='running' then
        if job.waiting then
            reroll_session.advance('search_waiting_backend')
            if not wait_started then wait_started=now;emit('LUA_SEARCH_WAIT '..tostring(job.wait_reason))end
        else
            reroll_session.advance('search_running')
            if wait_started then
                wait_total=wait_total+now-wait_started;wait_started=nil
                emit(string.format('LUA_SEARCH_RESUMED wait_seconds=%.3f; revalidating captured inputs',wait_total))
            end
        end
        if now-last_progress>=5 then
            last_progress=now
            emit(string.format('LUA_SEARCH_PROGRESS attempts=%d seeds_per_second=%.0f phase=%s max_slice_ms=%.3f %s',job.attempts,job.attempts/elapsed,job.phase,max_slice,timing))
        end
    else
        M.search_result=job;if job.status=='matched' then reroll_session.advance('search_matched')else reroll_session.finish('search_'..job.status)end
        if job.status=='matched' then
            resume=nil
            local missions={};for _,mission in ipairs(job.operation.missions)do missions[#missions+1]=string.format('%d/%u/level%d',mission.native_type,mission.seed,mission.level_index)end
            if job.constellations then
                local tags={}
                for _,mission in ipairs(job.operation.missions)do
                    local list={};for tag in pairs(mission.tags or {})do list[#list+1]=tag end
                    table.sort(list);tags[#tags+1]=table.concat(list,'+')
                end
                for i,mission in ipairs(job.operation.missions)do tags[i]=mission.native_type..':'..tags[i]end
                emit('LUA_SEARCH_MATCH_CONSTELLATIONS row='..job.operation.row..' missions='..table.concat(tags,','))
            end
            emit(string.format('LUA_SEARCH_MATCH seed=%u row=%d attempts=%d seeds_per_second=%.0f ranges=%d bytes=%d max_slice_ms=%.3f %s missions=%s read_only='..tostring(M.read_only)..' published=false selected=false',
                job.seed,job.operation.row,job.attempts,job.attempts/elapsed,job.ranges,job.bytes,max_slice,timing,table.concat(missions,',')))
            if on_search_match then on_search_match(job,now)end
        else
            -- A failed job saw changed or unsupported inputs; its range is not reusable.
            if job.status~='failed' and job.attempts>0 then
                resume={key=job.key,planet=job.baseline.planet,baseline=job.baseline.seed,next=job.next_seed}
            end
            if job.status=='exhausted' or job.error=='Search time limit reached' then
                M.search_report='No match in '..job.attempts..' seeds; search again to continue'
            end
            emit(string.format('LUA_SEARCH_%s attempts=%d seeds_per_second=%.0f next_seed=%u reason=%s max_slice_ms=%.3f %s',string.upper(job.status),job.attempts,
                job.attempts/elapsed,job.next_seed,tostring(job.error or 'candidate budget reached'),max_slice,timing))
        end
        current_search=nil
    end
    return true
end
emit('Lua search checkpoint: ICBM + Geological Survey + Eradicate, difficulty 10; same shortcut cancels; alt-tab supported; '..config.search_outcome)
return {on_prediction_ready=on_prediction_ready,advance_prediction_search=advance_prediction_search,
    search_clock=search_clock,default_limit=default_limit}
