-- Controlled read-only search checkpoint: fixed filter, no UI or publication.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
-- hooks: bind_constellations, bind_objectives, on_existing_match, on_search_match, and
-- validate_search_request, which the assembler adds once the dialog exists.
local M,emit,read,u,snapshot,config=host.M,host.emit,host.read,host.u,host.snapshot,host.config
local reroll_session,O,map=host.reroll_session,host.O,host.map
local Search,Planet,make_search_job,DayNight=lib.Search,lib.Planet,lib.make_search_job,lib.DayNight
local ExternalEdits,SideObjectives=lib.ExternalEdits,lib.SideObjectives
local SeedSolver,predict_identity=lib.SeedSolver,lib.predict_identity
local bind_constellations,on_existing_match,on_search_match=hooks.bind_constellations,hooks.on_existing_match,hooks.on_search_match
local bind_objectives=hooks.bind_objectives
local api,game,ffi,kernel
host.when_initialized(function(n)api,game,ffi,kernel=n.api,n.game,n.ffi,n.kernel end)
local on_prediction_ready,advance_prediction_search
local current_search,search_started,last_progress,max_slice
local slices,step_time,context_time
local wait_started,wait_total,last_wait_poll
local default_limit=1000000
-- Walk steps per second of a search in game (about a million on 2026-10-04).
local solver_rate=800000
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
local function request_key(difficulty,required,modifiers,constellations,scope,time,excluded,objectives)
    local parts={'d'..difficulty,'r'..(scope and scope.region or 'all'),'t'..(time or 'any')}
    for id in pairs(required)do parts[#parts+1]='m'..id end
    for id in pairs(excluded)do parts[#parts+1]='x'..id end
    for id,mode in pairs(modifiers)do parts[#parts+1]=string.format('o%u:%s',id,mode)end
    for group,tags in pairs(constellations and constellations.groups or {})do
        for tag,mode in pairs(tags)do parts[#parts+1]='c'..group..':'..tag..':'..mode end
    end
    for group,rows in pairs(objectives and objectives.groups or {})do
        for row,mode in pairs(rows)do parts[#parts+1]=string.format('s%d:%u:%s',group,row,mode)end
    end
    table.sort(parts);return table.concat(parts,',')
end
on_prediction_ready=function(s,definitions,now)
    assert(definitions,'Missing captured definitions')
    local request=reroll_session.view().request or {difficulty=10,required={[1]=true,[2]=true,[3]=true}}
    local required={};for id,value in pairs(request.required)do required[id]=value end
    local excluded={};for id,value in pairs(request.excluded or {})do excluded[id]=value end
    local modifiers={};for id,value in pairs(request.modifiers or {})do modifiers[id]=value end
    local limit=request.limit or default_limit
    local scope=Search.scope(request.scope)
    reroll_session.report(nil)
    local constellations
    if request.constellations and next(request.constellations.groups)then
        if not bind_constellations then reroll_session.finish('search_failed');emit('FILTER_BLOCKED Constellation filters unavailable');return end
        constellations={groups={}}
        for group,tags in pairs(request.constellations.groups)do
            local copy={};for tag,value in pairs(tags)do copy[tag]=value end
            constellations.groups[group]=copy
        end
    end
    local objectives
    if request.objectives and next(request.objectives.groups)then
        if not bind_objectives then reroll_session.finish('search_failed');emit('FILTER_BLOCKED Side objective filters unavailable');return end
        objectives={groups={}}
        for group,rows in pairs(request.objectives.groups)do
            local copy={};for row,value in pairs(rows)do copy[row]=value end
            objectives.groups[group]=copy
        end
    end
    -- The Day / Night filter checks the viewed planet's sky (src/day_night.lua).
    local daynight
    if request.time then
        local ok,planet,why=pcall(DayNight.load,read,u,s.board,s.planet,map.sky())
        if not ok or not planet then
            local reason=ok and why or tostring(planet)
            reroll_session.finish('search_failed');reroll_session.report(reason)
            emit('FILTER_BLOCKED day/night '..reason);return
        end
        daynight=DayNight.checker(planet,request.time)
        daynight.planet=planet
        daynight.refresh(DayNight.war_time(read,s.board))
        emit(string.format('DAYNIGHT_SEARCH side=%s day_s=%.0f buffer_s=%.0f band_min=%d margin_s=%d slack_s=%d',
            request.time,planet.day_length,planet.buffer,DayNight.BAND,DayNight.MARGIN,DayNight.SLACK))
    end
    local validate_search_request=hooks.validate_search_request
    if validate_search_request then
        local ok,err=pcall(validate_search_request,s,request)
        if not ok then reroll_session.finish('search_failed');emit('FILTER_BLOCKED '..tostring(err));return end
    end
    if M.dialog_enabled and on_existing_match then
        if constellations or objectives then
            local ok,err=pcall(function()
                local model=Planet.bind(read,u,api.pointer,game,s.board,s.planet)
                for _,bind in ipairs({constellations and bind_constellations or false,objectives and bind_objectives or false})do
                    if bind then
                        local annotate=bind(model)
                        for _,op in ipairs(s.decoded.operations)do
                            annotate(op,u(s.operations,op.row*92+28),op.operation_id)
                            -- Side objectives are drawn on first use; draw them here, where a failure is caught.
                            for _,mission in ipairs(op.missions)do local _=mission.objectives end
                        end
                    end
                end
            end)
            if not ok then reroll_session.finish('search_failed');emit('FILTER_BLOCKED '..tostring(err));return end
        end
        -- An operation another mod edited (s.external) holds missions no seed
        -- gives; it is never offered as the match.
        local existing=Search.find({operations=ExternalEdits.without(s.decoded.operations,s.external)},
            request.difficulty,required,modifiers,constellations,scope,daynight and daynight.accepts,excluded,objectives)
        if existing then reroll_session.progress(0);on_existing_match(s,existing,now);return end
    end
    -- A city has one operation per difficulty. While it is in progress no
    -- seed can change it, so searching would only exhaust the budget.
    local fixed_row,fixed_difficulty=Search.active_row(s)
    if scope and fixed_row and fixed_difficulty==request.difficulty and Search.in_scope(fixed_row,scope)then
        reroll_session.finish('search_failed');reroll_session.report('This operation is in progress; its missions are fixed')
        emit('FILTER_BLOCKED operation in progress row='..fixed_row..'; its missions cannot be rerolled');return
    end
    local function baseline(frozen_read)
        local key=frozen_read(s.board+O.board.campaign+0x1c+s.planet*O.campaign.definition_stride,4)
        assert(frozen_read(definitions,4)==key,'Planet definitions changed')
        local result=Planet.capture(frozen_read,u,api.pointer,game)(s,definitions)
        assert(ExternalEdits.composition_passes(result,s.external) and result.independent_bases,'Frozen baseline prediction mismatch')
    end
    local key=request_key(request.difficulty,required,modifiers,constellations,scope,request.time,excluded,objectives)
    local first=(s.seed+1)%4294967296
    local resumed=resume and resume.key==key and resume.planet==s.planet and resume.baseline==s.seed
    if resumed then first=resume.next end
    current_search=make_search_job(read,baseline,function(frozen_read,pause)
        local planet=Planet.bind(frozen_read,u,api.pointer,game,s.board,s.planet)
        local predict=planet.predictor(definitions)
        -- Tag inputs join the frozen read set and are revalidated with it.
        local annotate=constellations and bind_constellations(planet)
        local annotate_objectives=objectives and bind_objectives(planet)
        local function accepts(row)return Search.in_scope(row,scope)end
        -- The seed solver proposes the candidates when it can seed this
        -- request (src/seed_solver_search.lua); its inputs are read through
        -- the frozen reads, so they are revalidated with the predictor's.
        local source
        if SeedSolver then
            local started=search_clock()
            local ok,result,why=pcall(function()
                local solver,input=planet.solver(definitions,request.difficulty,constellations~=nil or objectives~=nil,
                    scope and scope.region)
                if not solver then return nil,input end
                return SeedSolver.source({solver=solver,input=input,identity=predict_identity,difficulty=request.difficulty,
                    required=required,options=Search.options,constellations=constellations,objectives=objectives,scope=scope,
                    daynight=daynight and daynight.accepts,row_of=SideObjectives and SideObjectives.row_of,
                    random=SeedSolver.starts(s.seed+math.floor(started*1000000)),checkpoint=pause})
            end)
            local ms=(search_clock()-started)*1000
            if ok and result then
                source=result
                result.setup=ms/1000
                emit(string.format('SEED_SOLVER paths=%d rows=%d setup_ms=%.0f match=1/%.0f expected_steps=%.0f%s',result.paths,
                    result.rows,ms,1/math.max(result.estimate.match,1e-12),result.estimate.steps,
                    result.ids and string.format(' daynight_ids=%d/%d',result.valid,result.ids) or ''))
            else
                emit(string.format('SEED_SOLVER_OFF reason=%s setup_ms=%.0f; scanning seeds in order',
                    tostring(ok and why or result),ms))
            end
        end
        local function evaluate(seed,difficulty)
            local operations=predict(seed,difficulty,accepts)
            if annotate then for _,op in ipairs(operations)do annotate(op)end end
            if annotate_objectives then for _,op in ipairs(operations)do if op.valid then annotate_objectives(op)end end end
            return operations
        end
        -- Search the requested difficulty; confirm a match on the whole board.
        return function(seed)return evaluate(seed,request.difficulty)end,function(seed)return evaluate(seed)end,source
    end,{seed=first,limit=limit,difficulty=request.difficulty,required=required,excluded=excluded,modifiers=modifiers,
        constellations=constellations,objectives=objectives,scope=scope,daynight=daynight and daynight.accepts,
        quantum=4096,clock=search_clock,slice=0.016,batch=256,revalidate=1})
    current_search.baseline=s
    current_search.required=required
    current_search.excluded=excluded
    current_search.modifiers=modifiers
    current_search.constellations=constellations
    current_search.objectives=objectives
    current_search.scope=scope
    current_search.daynight=daynight
    current_search.definitions=definitions
    current_search.key=key
    reroll_session.progress(0)
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
    search_started=now;last_progress=now;max_slice=0;reroll_session.result(nil);reroll_session.advance('search_running')
    wait_started=nil;wait_total=0;last_wait_poll=-math.huge
    local names={};for id,opt in ipairs(Search.options)do if required[id]then names[#names+1]=opt.name end end
    local modifier_rules={};for id,mode in pairs(modifiers)do modifier_rules[#modifier_rules+1]=string.format('%u:%s',id,mode)end
    table.sort(modifier_rules);emit('LUA_SEARCH_MODIFIERS '..table.concat(modifier_rules,','))
    if next(excluded)then
        local list={};for id,opt in ipairs(Search.options)do if excluded[id]then list[#list+1]=opt.name end end
        emit('LUA_SEARCH_EXCLUDED_MISSIONS '..table.concat(list,' + '))
    end
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
    if objectives then
        local rules={}
        for group,rows in pairs(objectives.groups)do
            local wanted,unwanted={},{}
            for row,mode in pairs(rows)do
                local name=SideObjectives.names[row] or string.format('%08x',row)
                if mode=='exclude' then unwanted[#unwanted+1]=name else wanted[#wanted+1]=name end
            end
            table.sort(wanted);table.sort(unwanted)
            rules[#rules+1]=(group==0 and 'operation' or Search.options[group].name)
                ..'=require '..(#wanted>0 and table.concat(wanted,'+') or 'none')
                ..(#unwanted>0 and ' exclude '..table.concat(unwanted,'|') or '')
        end
        table.sort(rules);emit('LUA_SEARCH_OBJECTIVES '..table.concat(rules,', '))
    end
    emit(string.format('LUA_SEARCH_STARTED planet=%d region=%s baseline_seed=%u first_seed=%u resumed=%s difficulty=%d required=%s limit=%d read_only='..tostring(M.read_only),
        s.planet,scope and scope.region or 'all',s.seed,first,tostring(resumed==true),request.difficulty,table.concat(names,' + '),limit))
end
advance_prediction_search=function(action,now)
    if not current_search then return false end
    local job=current_search
    reroll_session.progress(job.attempts)
    local waiting=wait_started and now-wait_started or 0
    if action=='cancel' then job:cancel('Cancelled by shortcut or shutdown')
    elseif waiting>=60 or wait_total+waiting>=120 then job:cancel('Backend wait time limit reached')
    elseif now-search_started-wait_total-waiting>180 then job:cancel('Search time limit reached')
    else
        if wait_started and now-last_wait_poll<0.25 then return true end
        last_wait_poll=now
        -- The day/night window follows war time; the war time is read live.
        if job.daynight then
            local ok,err=pcall(function()job.daynight.refresh(DayNight.war_time(read,job.baseline.board))end)
            if not ok then job:cancel('Day/night window unavailable: '..tostring(err))end
        end
        local started=search_clock();job:step(job.context_check)
        local spent=search_clock()-started
        slices=slices+1;step_time=step_time+spent;max_slice=math.max(max_slice,spent*1000)
    end
    reroll_session.progress(job.attempts)
    local elapsed=math.max(now-search_started-wait_total-waiting,0.001)
    -- The dialog's estimate: the solver's expected walk at the walk rate
    -- measured so far, or a typical in-game rate before there is one, plus
    -- the set-up and the match's confirmation.
    if job.source and job.source.estimate and job.solving~=false then
        local e,steps=job.source.estimate,job.source.steps()
        local work=elapsed-(job.source.setup or 0)
        local rate=solver_rate
        -- A measured rate also serves the dialog's next estimates.
        if steps>=200000 and work>0.5 then rate=steps/work;solver_rate=rate end
        reroll_session.estimate({match=e.match,seconds=(job.source.setup or 0)+e.steps/rate+0.3,elapsed=elapsed})
    else reroll_session.estimate(nil)end
    local compiled=rawget(_G,'jit') and type(jit.status)=='function' and jit.status()
    local timing=string.format('elapsed_s=%.2f slices=%d work_ms=%.0f context_ms=%.0f jit=%s',elapsed,slices,
        (step_time-context_time)*1000,context_time*1000,tostring(compiled))
    if job.source then
        timing=timing..string.format(' mode=%s walk_steps=%.0f',job.solving and 'solver' or 'scan',job.source.steps())
    end
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
        -- Just before the write the match must hold for the whole buffer from
        -- now; when the side ends sooner the search continues after it.
        if job.status=='matched' and job.daynight then
            local T=DayNight.war_time(read,job.baseline.board)
            local times={}
            for _,mission in ipairs(job.operation.missions)do
                times[#times+1]=string.format('level%d@%.0f',mission.level_index,job.daynight.time_of_day(mission.level_index,T))
            end
            local held=job.daynight.confirm(job.operation,T)
            emit(string.format('DAYNIGHT_MATCH side=%s row=%d seed=%u war_time=%.1f buffer_s=%.0f holds=%s minutes=%s',
                job.daynight.side,job.operation.row,job.seed,T,job.daynight.planet.buffer,tostring(held),table.concat(times,',')))
            if not held then
                resume={key=job.key,planet=job.baseline.planet,baseline=job.baseline.seed,next=(job.seed+1)%4294967296}
                current_search=nil
                emit('DAYNIGHT_WINDOW_CLOSED row='..job.operation.row..' seed='..job.seed..'; searching on')
                on_prediction_ready(job.baseline,job.definitions,now)
                return true
            end
        end
        reroll_session.result(job);if job.status=='matched' then reroll_session.advance('search_matched')else reroll_session.finish('search_'..job.status)end
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
            if job.objectives then
                local lists={}
                for _,mission in ipairs(job.operation.missions)do
                    lists[#lists+1]=mission.native_type..':['..SideObjectives.describe(mission.objective_list or {})..']'
                end
                emit('LUA_SEARCH_MATCH_OBJECTIVES row='..job.operation.row..' missions='..table.concat(lists,' '))
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
                reroll_session.report('No match in '..job.attempts..' seeds; search again to continue')
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
    search_clock=search_clock,default_limit=default_limit,solver_rate=function()return solver_rate end}
