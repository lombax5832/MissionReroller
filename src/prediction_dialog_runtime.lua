-- Modal UI for the in-process predictor. Losing focus releases input ownership
-- but never cancels the search. Only an explicit cancel/close cancels work.
do
    local panel,gate,router,exe
    local selected,difficulty,key_down={},10,true
    local modifiers,tab,page_number={},'missions',1
    local constellations,tag_error={},nil
    -- A city or megafactory appears on the map as its operation. The one
    -- under the cursor when the dialog opens, or else the selected one,
    -- limits the dialog and the search to that city.
    local scope
    local function pointed_region()
        local rows=read(pointer(game+0x3326aa0)+0x4f00,8)
        local row=u(rows,4);if row>=110 then row=u(rows,0)end
        if row>=30 and row<110 then return math.floor((row-30)/10)end
    end
    local function accepts(row)return Search.in_scope(row,scope)end
    -- Constellation rules belong to a checked mission. Without checked
    -- missions the single group 0 applies to the operation.
    local function active_groups()
        local list={}
        for id=1,#Search.options do if selected[id]then list[#list+1]=id end end
        if #list==0 then list[1]=0 end
        return list
    end
    local function prune_groups()
        local active={};for _,group in ipairs(active_groups())do active[group]=true end
        for group in pairs(constellations)do if not active[group]then constellations[group]=nil end end
    end
    local function tag_filter()
        local groups={}
        for _,group in ipairs(active_groups())do
            local copy={};for tag,mode in pairs(constellations[group] or {})do copy[tag]=mode end
            if next(copy)then groups[group]=copy end
        end
        return {groups=groups}
    end
    local catalogue,catalogue_key,catalogue_view
    local running=false
    local report='Select missions; difficulty follows the map'
    local terminal={publication_test_passed=true,publication_blocked=true,publication_failed=true,
        publication_restored=true,publication_cancelled=true,search_exhausted=true,
        search_failed=true,search_cancelled=true,capture_timeout=true,cancelled=true,
        identity_test_mismatch=true,level_test_mismatch=true,composition_test_mismatch=true}
    local captions={waiting_for_stable_inputs='Checking planet data',capture_retry='Retrying changed planet data',
        search_running='Searching seeds',search_waiting_backend='Waiting for game requests',
        publication_pending='Refreshing operations',selection_pending='Opening matching operation',
        publication_test_passed='Matching operation selected',search_exhausted='No match; search again to continue',
        search_cancelled='Search cancelled',cancelled='Search cancelled',publication_blocked='Map changed; reopen the planet and retry'}
    local function face()
        local function hash(a)local b=read(a,8);return string.format('%08x%08x',u(b,4),u(b,0))end
        local f={font=hash(game+0x3772268),material=hash(pointer(game+0x37c5478)+24),atlas=hash(game+0x3772ee8)}
        for _,v in pairs(f)do assert(v~='0000000000000000','Font not ready')end
        return f
    end
    local function check_window()
        for _,sig in ipairs(window_signatures)do
            assert(hex(read(exe+sig[1],#sig[2]/2))==sig[2],'Window binding signature mismatch')
        end
        local app=pointer(exe+0x1a10210)
        assert(u(read(app+0x3b8,4),0)==1,'Expected one game window')
        local window=pointer(pointer(app+0x3c0))
        page(window+0x80,10,0x20000)
        local flag=read(window+0x89,1):byte();assert(flag==0 or flag==1,'Invalid focus flag')
        return tostring(window)
    end
    dialog_release=function(reason)
        if gate then gate:release()end
        router=nil
        if panel then panel:clear()end
        emit('MODAL_RELEASE '..reason)
    end
    local function init()
        exe=assert(api.module(nil));panel=Panel.new(assert(stingray))
        ffi.cdef[[typedef struct { int32_t x,y; } MRD_POINT;
            typedef struct { int32_t left,top,right,bottom; } MRD_RECT;
            int GetCursorPos(MRD_POINT *); int ScreenToClient(void *,MRD_POINT *);
            int GetClientRect(void *,MRD_RECT *);]]
        gate=make_gate(stingray.Window,check_window)
    end
    local function context()
        local ui=pointer(game+0x3326aa0)
        local viewed=u(read(ui+0x4ef8,4),0)
        local d=u(read(ui+0x4f14,4),0)
        if viewed>=512 or d<1 or d>10 then return nil,'Choose a planet and map difficulty' end
        local view=viewed..':'..d
        local s,why=snapshot(true)
        if not s then return nil,why,view end
        if viewed~=s.planet then
            return nil,'Waiting for the viewed planet',view
        end
        return s,d,view
    end
    local function catalogue_for(s,d,within)
        local inputs=make_composition_inputs(read,u,api.pointer,game,s.board,make_config,make_effects,mission_eligible,make_environments)
        local result=FilterCatalogue.build(inputs,s,d,u,Search.options,Compatibility,nil,nil,
            within and function(row)return Search.in_scope(row,within)end)
        -- Mission and modifier filters must survive a constellation input failure.
        local ok,err=pcall(function()
            local tags=make_constellation_inputs(read,u,api.pointer,game,s.board,inputs.effects,inputs.config)
            FilterCatalogue.constellations(result,tags,Constellations.names,s.planet,d,Search.options)
        end)
        if not ok and tostring(err)~=tag_error then tag_error=tostring(err);emit('CONSTELLATION_CATALOGUE_BLOCKED '..tag_error)end
        return result
    end
    validate_search_request=function(s,request)
        FilterCatalogue.validate(catalogue_for(s,request.difficulty,Search.scope(request.scope)),request.required,request.modifiers,request.constellations)
    end
    dialog_tick=function(focused,now)
        if not panel then init()end
        if running and (terminal[M.status] or tostring(M.status):find('STOPPED',1,true))then
            running=false;report=M.search_report or captions[M.status] or M.status
            if M.status=='publication_test_passed' and router then router:close()end
        end
        if not focused then
            if router then dialog_release('focus lost; search continues')end
            key_down=true;return
        end
        local down=user32.GetAsyncKeyState(0x11)<0 and user32.GetAsyncKeyState(0x10)<0 and user32.GetAsyncKeyState(0x77)<0
        if down and not key_down then
            if router then M.cancel_requested=running;running=false;router:close()
            else
                catalogue_key=nil
                local ok,region=pcall(pointed_region)
                scope=ok and region and {region=region} or nil
                router=make_router(gate);router:open()
                emit('MODAL_OPEN scope='..(scope and 'region '..scope.region or 'planet'))
            end
        end
        key_down=down
        if not router then return end
        local hwnd=user32.GetForegroundWindow()
        local p=ffi.new('MRD_POINT[1]');local r=ffi.new('MRD_RECT[1]')
        assert(user32.GetCursorPos(p)~=0 and user32.ScreenToClient(hwnd,p)~=0 and user32.GetClientRect(hwnd,r)~=0,'Mouse position unavailable')
        assert(r[0].right>0 and r[0].bottom>0,'Invalid client dimensions')
        local width,height=stingray.Gui.resolution()
        local x=tonumber(p[0].x)*width/r[0].right;local y=height-tonumber(p[0].y)*height/r[0].bottom
        local s,why,view
        if not running then s,why,view=context();if s then difficulty=why;view=s.planet..':'..difficulty end end
        if s and scope then
            -- The city must belong to the viewed planet.
            local present=false
            for _,op in ipairs(s.decoded.operations)do if accepts(op.row)then present=true;break end end
            if not present then scope=nil end
        end
        if s then
            local key=s.fingerprint..':'..difficulty..':'..(scope and scope.region or 'planet')
            if key~=catalogue_key then
                local ok,value=pcall(catalogue_for,s,difficulty,scope)
                if ok then
                    catalogue=value;catalogue_key=key;catalogue_view=view;page_number=1
                    local removed=false
                    for id in pairs(selected)do if not catalogue.mission_set[id]then selected[id]=nil;removed=true end end
                    for id in pairs(modifiers)do if not catalogue.modifier_set[id]then modifiers[id]=nil;removed=true end end
                    for group,tags in pairs(constellations)do
                        local offered=(catalogue.constellation_groups or {})[group]
                        for tag in pairs(tags)do if not (offered and offered.set[tag])then tags[tag]=nil;removed=true end end
                    end
                    prune_groups()
                    if removed then report='Unavailable filters cleared for this planet/difficulty' end
                else catalogue=nil;catalogue_key=key;emit('FILTER_CATALOGUE_BLOCKED '..tostring(value))end
            end
            if not catalogue then why='Eligibility unavailable; reopen filters to retry';s=nil end
        end
        -- Retain presentation only while the independently read UI still names
        -- the same planet/difficulty. Never use retained data to start a search.
        local retained=not s and not running and catalogue and view==catalogue_view
        local display=(s or running or retained) and catalogue
        -- The constellations tab has one page per active group.
        local available=display and tab~='constellations' and catalogue[tab] or {}
        local groups=active_groups()
        local pages=tab=='constellations' and #groups or math.max(1,math.ceil(#available/12))
        page_number=math.min(page_number,pages)
        local group=groups[page_number]
        local items={}
        for i=(page_number-1)*12+1,math.min(#available,page_number*12)do
            local option=available[i]
            local enabled,reason=true,nil
            if tab=='missions' and not selected[option.id]then
                local proposed={};for id,v in pairs(selected)do proposed[id]=v end;proposed[option.id]=true
                enabled,reason=FilterCatalogue.possible(catalogue,proposed,modifiers,tag_filter())
            end
            if retained then enabled=false;reason='Waiting for fresh planet data' end
            items[#items+1]={id=tab=='missions' and option.id or 'modifier:'..option.id,name=option.name,mode=modifiers[option.id],enabled=enabled,reason=reason}
        end
        local offered=tab=='constellations' and display and (catalogue.constellation_groups or {})[group]
        if offered and #offered.list>0 then
            assert(#offered.list<=11,'Too many constellation options')
            items[1]={id='constellation_group',name='group',enabled=false,
                caption='FOR: '..(group==0 and 'THE OPERATION' or string.upper(Search.options[group].name)),
                reason=pages>1 and 'Use < and > to switch between checked missions' or nil}
            for _,option in ipairs(offered.list)do
                items[#items+1]={id='constellation:'..group..':'..option.id,name=option.name,
                    mode=(constellations[group] or {})[option.id],enabled=not retained,
                    reason=retained and 'Waiting for fresh planet data' or nil}
            end
        end
        -- The operation in progress keeps its missions; a city has no other
        -- operation at this difficulty to reroll.
        local fixed=false
        if s and scope then
            local row,level=M.active_row(s)
            fixed=row~=nil and level==difficulty and accepts(row)
        end
        local compatible,compatibility_reason=true,nil
        if catalogue then compatible,compatibility_reason=FilterCatalogue.possible(catalogue,selected,modifiers,tag_filter())end
        local status=running and (captions[M.status] or 'Checking planet data') or (not s and why or report)
        if not running and not compatible then status=compatibility_reason end
        if retained then status='Updating planet data; filters retained' end
        if fixed and not running then status='This operation is in progress; its missions cannot be rerolled' end
        local model={running=running,ready=not running and s~=nil and compatible and not fixed,difficulty=difficulty,difficulty_locked=true,
            calls=M.search_attempts or 0,counter_label='Seeds',status=tostring(status),items=items,tab=tab,page=page_number,pages=pages,
            subtitle=display and (({[2]='Terminids',[3]='Automatons',[4]='Illuminate'})[catalogue.faction]
                ..(scope and ' / This city or megafactory only' or ' / Valid options for this planet and difficulty'))
                or 'Waiting for planet eligibility'}
        if tab=='constellations' then
            model.hint=group==0 and 'ACCEPT: a mission carries one of them. EXCLUDE: no mission carries any. Click to cycle.'
                or 'ACCEPT: this mission carries one of them. EXCLUDE: it carries none. Click to cycle.'
            if display and #(catalogue.forced or {})>0 then
                model.subtitle=(scope and 'Always here' or 'Planet-wide')..', not rerollable: '..Constellations.describe(catalogue.forced)
            end
        end
        local action=router:step(x,y,user32.GetAsyncKeyState(1)<0,Panel.layout(width,height,model).targets)
        if action=='close' then M.cancel_requested=running;running=false;router:close()
        elseif action=='cancel' then M.cancel_requested=true;running=false;report='Search cancelled'
        elseif action=='missions_tab' then tab='missions';page_number=1
        elseif action=='modifiers_tab' then tab='modifiers';page_number=1
        elseif action=='constellations_tab' then tab='constellations';page_number=1
        elseif action=='previous_page' then page_number=math.max(1,page_number-1)
        elseif action=='next_page' then page_number=math.min(pages,page_number+1)
        elseif not running then
            if action=='clear' then selected={};modifiers={};constellations={}
            elseif type(action)=='number' then
                if selected[action]then selected[action]=nil
                else
                    local proposed={};for id,v in pairs(selected)do proposed[id]=v end;proposed[action]=true
                    if FilterCatalogue.possible(catalogue,proposed,modifiers,tag_filter())then selected[action]=true end
                end
                prune_groups()
            elseif type(action)=='string' and action:match('^modifier:')then
                local id=tonumber(action:sub(10))
                modifiers[id]=modifiers[id]==nil and 'require' or modifiers[id]=='require' and 'exclude' or nil
            elseif type(action)=='string' and action:match('^constellation:')then
                local target,id=action:match('^constellation:(%d+):(%d+)$')
                target,id=tonumber(target),tonumber(id)
                local tags=constellations[target] or {}
                tags[id]=tags[id]==nil and 'accept' or tags[id]=='accept' and 'exclude' or nil
                constellations[target]=next(tags) and tags or nil
            elseif action=='start' and model.ready then
                -- Refresh eligibility immediately before accepting a request.
                local ok,err=pcall(function()FilterCatalogue.validate(catalogue_for(s,difficulty,scope),selected,modifiers,tag_filter())end)
                if ok then
                    local required,rules={},{}
                    for id,v in pairs(selected)do required[id]=v end
                    for id,v in pairs(modifiers)do rules[id]=v end
                    M.search_options={difficulty=difficulty,required=required,modifiers=rules,constellations=tag_filter(),
                        scope=scope and {region=scope.region} or nil}
                    M.request_search=true;M.search_attempts=0;running=true;report='Checking planet data'
                    emit('DIALOG_SEARCH planet='..s.planet..' region='..(scope and scope.region or 'all')..' difficulty='..difficulty)
                else report=tostring(err)end
            end
        end
        if not router.opened and not router.closing then dialog_release('closed');return end
        local temp=stingray.Script.temp_byte_count()
        local ok,err=pcall(function()panel:show(Search.options,selected,face(),{x=x,y=y},model)end)
        stingray.Script.set_temp_byte_count(temp);assert(ok,err)
    end
    M.dialog_enabled=true
    emit('Mission filters: Ctrl+Shift+F8; native cursor; all checked families in one operation; map difficulty; constellations per mission; repeat searches allowed')
end
