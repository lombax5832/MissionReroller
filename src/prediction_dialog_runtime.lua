-- Modal UI for the in-process predictor. Losing focus releases input ownership
-- but never cancels the search. Only an explicit cancel/close cancels work.
do
    local panel,hint,gate,router,exe
    local selected,difficulty,key_down={},10,true
    -- The key hint sits beside the war table's own BACK hint, a widget of
    -- the map screen object: the 136x32 design-unit container at local
    -- (56,16) that holds the key cap and the BACK label, found by
    -- scripts/survey_map_widgets.py on 2026-09-29. nil draws no hint.
    local HINT_WIDGET=1696
    local hint_blocked=false
    -- One section is open at a time, or none. The enemy section shows the
    -- rules of one group: a checked mission, or 0 for any mission.
    local modifiers,section,mission_page,group_choice={},'missions',1,0
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
    -- Planet data is briefly unavailable now and then. since: when the gap
    -- began. queued: when a start was requested during it. fixed: the last
    -- known answer, kept through the gap.
    local gap={}
    -- The outcome of the last search, or an error. Editing the request
    -- discards it.
    local report,report_tone
    local terminal={publication_test_passed=true,publication_blocked=true,publication_failed=true,
        publication_restored=true,publication_cancelled=true,search_exhausted=true,
        search_failed=true,search_cancelled=true,capture_timeout=true,cancelled=true,
        identity_test_mismatch=true,level_test_mismatch=true,composition_test_mismatch=true}
    local captions={waiting_for_stable_inputs='Checking planet data',capture_retry='Retrying changed planet data',
        search_running='Searching seeds',search_waiting_backend='Waiting for game requests',
        publication_pending='Refreshing operations',selection_pending='Opening matching operation',
        publication_test_passed='Matching operation selected',search_exhausted='No match; search again to continue',
        search_cancelled='Search cancelled',cancelled='Search cancelled',publication_blocked='Map changed; reopen the planet and retry'}
    local tones={publication_test_passed='good',search_exhausted='warn',publication_blocked='warn',
        search_cancelled='idle',cancelled='idle',publication_cancelled='idle'}
    local steps={waiting_for_stable_inputs=1,capture_retry=1,search_running=2,search_waiting_backend=2,
        publication_pending=3,selection_pending=4}
    local function grouped(n)
        local digits,found=tostring(math.floor(n))
        repeat digits,found=digits:gsub('^(%d+)(%d%d%d)','%1,%2')until found==0
        return digits
    end
    local function count(n)return n==0 and 'Any' or n..(n==1 and ' rule' or ' rules')end
    -- The names table also holds the game's tag, which the log keeps.
    local function friendly(tag)return ((Constellations.names[tag] or 'tag '..tag):gsub(' %b()$',''))end
    -- Closing the dialog cancels a running search.
    local function close()
        if running or gap.queued then report,report_tone='Search cancelled','idle' end
        M.cancel_requested=running;running=false;gap.queued=nil;router:close()
    end
    local function face()
        local function hash(a)local b=read(a,8);return string.format('%08x%08x',u(b,4),u(b,0))end
        local f={font=hash(game+0x3772268),material=hash(pointer(game+0x37c5478)+24),atlas=hash(game+0x3772ee8)}
        for _,v in pairs(f)do assert(v~='0000000000000000','Font not ready')end
        return f
    end
    -- The BACK hint's solved rectangle, or nil when the galactic map is not
    -- the top screen or the hint is hidden. The map screen object is the one
    -- inline subscriber of a UI manager event registry; a widget record keeps
    -- its flags at +0 (0x10 visible), unscaled size at +36, inherited opacity
    -- at +84, scale at +100/+140 and solved bottom-left position at +148/+156.
    local single
    local function back_hint()
        if not HINT_WIDGET then return nil end
        local screen=read(pointer(game+0x347ce28)+0x429c,24);local depth=u(screen,20)
        if depth<1 or depth>5 or u(screen,(depth-1)*4)~=15 then return nil end
        local entry=read(pointer(game+0x3326e68)+25224,24)
        if u(entry,0)~=1 or u(entry,16)~=226 then return nil end
        local owner=api.pointer(entry,8)
        if not owner then return nil end
        local w=read(owner+HINT_WIDGET,164)
        single=single or ffi.new('float[1]')
        local function f(o)ffi.copy(single,w:sub(o+1,o+4),4);return tonumber(single[0])end
        if math.floor(u(w,0)/16)%2==0 then return nil end
        local opacity=f(84)
        if not (opacity>=0.995 and opacity<=1.01)then return nil end
        local sx,sy=f(100),f(140)
        local box={x=f(148),y=f(156),w=f(36)*sx,h=f(40)*sy,scale=sx}
        for _,v in pairs(box)do if v~=v or v<0 or v>32768 then return nil end end
        if sx<0.3 or sx>4 or math.abs(sx-sy)>0.01 or box.w<8 or box.h<8 then return nil end
        return box
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
        if hint then pcall(function()hint:clear()end)end
        emit('MODAL_RELEASE '..reason)
    end
    local function init()
        exe=assert(api.module(nil));panel=Panel.new(assert(stingray));hint=Hint.new(stingray)
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
    local function begin(s)
        -- Refresh eligibility immediately before accepting a request.
        local ok,err=pcall(function()FilterCatalogue.validate(catalogue_for(s,difficulty,scope),selected,modifiers,tag_filter())end)
        if ok then
            local required,rules={},{}
            for id,v in pairs(selected)do required[id]=v end
            for id,v in pairs(modifiers)do rules[id]=v end
            M.search_options={difficulty=difficulty,required=required,modifiers=rules,constellations=tag_filter(),
                scope=scope and {region=scope.region} or nil}
            M.request_search=true;M.search_attempts=0;running=true;report,report_tone='Checking planet data','idle'
            emit('DIALOG_SEARCH planet='..s.planet..' region='..(scope and scope.region or 'all')..' difficulty='..difficulty
                ..' players='..tostring(s.sc))
        else report,report_tone=tostring(err),'bad' end
    end
    dialog_tick=function(focused,now)
        if not panel then init()end
        if running and (terminal[M.status] or tostring(M.status):find('STOPPED',1,true))then
            running=false;report=M.search_report or captions[M.status] or M.status
            report_tone=M.search_report and 'warn' or tones[M.status] or 'bad'
            if M.status=='publication_test_passed' and router then router:close()end
        end
        -- The hint is cosmetic: a failure disables it for the session and is
        -- logged once, without stopping the mod.
        if hint and not hint_blocked then
            local ok,err=pcall(function()
                local anchor=focused and back_hint()
                if anchor then hint:show(anchor,face())else hint:clear()end
            end)
            if not ok then hint_blocked=true;pcall(function()hint:clear()end);emit('HINT_BLOCKED '..tostring(err))end
        end
        if not focused then
            if router then dialog_release('focus lost; search continues')end
            if gap.queued then gap.queued=nil;report,report_tone='Search cancelled','idle' end
            key_down=true;return
        end
        local down=user32.GetAsyncKeyState(0x11)<0 and user32.GetAsyncKeyState(0x10)<0 and user32.GetAsyncKeyState(0x77)<0
        if down and not key_down then
            if router then close()
            else
                catalogue_key=nil;section,mission_page='missions',1;gap={}
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
                    -- Refreshed data of the same view keeps the page.
                    if view~=catalogue_view then mission_page=1 end
                    catalogue=value;catalogue_key=key;catalogue_view=view
                    local removed=false
                    for id in pairs(selected)do if not catalogue.mission_set[id]then selected[id]=nil;removed=true end end
                    for id in pairs(modifiers)do if not catalogue.modifier_set[id]then modifiers[id]=nil;removed=true end end
                    for group,tags in pairs(constellations)do
                        local offered=(catalogue.constellation_groups or {})[group]
                        for tag in pairs(tags)do if not (offered and offered.set[tag])then tags[tag]=nil;removed=true end end
                    end
                    prune_groups()
                    if removed then report,report_tone='Unavailable filters cleared for this planet/difficulty','warn' end
                else catalogue=nil;catalogue_key=key;emit('FILTER_CATALOGUE_BLOCKED '..tostring(value))end
            end
            if not catalogue then why='Eligibility unavailable; reopen filters to retry';s=nil end
        end
        -- Retain presentation only while the independently read UI still names
        -- the same planet/difficulty. Never use retained data to start a search.
        local retained=not s and not running and catalogue and view==catalogue_view
            and why~='Only the host can reroll operations'
        -- A short gap is not shown and does not block editing: the request is
        -- edited against the retained catalogue and fresh data prunes it.
        gap.since=retained and (gap.since or now) or nil
        local overdue=retained and now-gap.since>=1.5
        local display=(s or running or retained) and catalogue
        local groups=active_groups()
        local group=groups[1]
        for _,id in ipairs(groups)do if id==group_choice then group=id end end
        group_choice=group
        local filter=tag_filter()
        local names,modifier_rules,tag_rules={},0,0
        for _,id in ipairs(groups)do if id~=0 then names[#names+1]=Search.options[id].name end end
        for _ in pairs(modifiers)do modifier_rules=modifier_rules+1 end
        for _,tags in pairs(filter.groups)do for _ in pairs(tags)do tag_rules=tag_rules+1 end end
        local rules=#names+modifier_rules+tag_rules
        -- The operation in progress keeps its missions; a city has no other
        -- operation at this difficulty to reroll.
        if s then
            gap.fixed=false
            if scope then
                local row,level=M.active_row(s)
                gap.fixed=row~=nil and level==difficulty and accepts(row)
            end
        elseif not retained then gap.fixed=false end
        local fixed=gap.fixed
        local compatible,compatibility_reason=true,nil
        if catalogue then compatible,compatibility_reason=FilterCatalogue.possible(catalogue,selected,modifiers,filter)end
        -- A start requested during a gap waits for fresh data, and is then
        -- validated like any other.
        if gap.queued then
            if s then
                gap.queued=nil
                if compatible and not fixed and rules>0 then begin(s)end
            elseif not retained then gap.queued=nil;report,report_tone='Planet changed; search not started','warn'
            elseif now-gap.queued>=10 then gap.queued=nil;report,report_tone='Planet data did not arrive; try again','warn' end
        end
        local busy=running or gap.queued~=nil
        local locked=busy or not (s or retained)
        local items,pages,tabs,forced={},1,{},{}
        if display and section=='missions' then
            local available=catalogue.missions or {}
            pages=math.max(1,math.ceil(#available/24));mission_page=math.min(mission_page,pages)
            for i=(mission_page-1)*24+1,math.min(#available,mission_page*24)do
                local option=available[i]
                local enabled,reason=true,nil
                if not selected[option.id]then
                    local proposed={};for id,v in pairs(selected)do proposed[id]=v end;proposed[option.id]=true
                    enabled,reason=FilterCatalogue.possible(catalogue,proposed,modifiers,filter)
                end
                items[#items+1]={id=option.id,name=option.name,enabled=enabled,reason=reason}
            end
        elseif display and section=='modifiers' then
            for _,option in ipairs(catalogue.modifiers or {})do
                items[#items+1]={id='modifier:'..option.id,name=option.name,mode=modifiers[option.id]}
            end
        elseif display and section=='enemies' then
            local offered=(catalogue.constellation_groups or {})[group]
            if offered then
                assert(#offered.list<=11,'Too many constellation options')
                for _,option in ipairs(offered.list)do
                    items[#items+1]={id='constellation:'..group..':'..option.id,name=(option.name:gsub(' %b()$','')),
                        mode=(constellations[group] or {})[option.id]}
                end
            end
            for i,id in ipairs(groups)do
                tabs[i]={id=id,name=id==0 and 'Any mission' or Search.options[id].name,selected=id==group}
            end
            for i,tag in ipairs(catalogue.forced or {})do forced[i]=friendly(tag)end
        end
        local ready=not busy and (s~=nil or retained) and compatible and not fixed
        -- The same precedence as before the panel was docked.
        local status,tone
        if running then status,tone=captions[M.status] or 'Checking planet data','busy'
        elseif gap.queued then status,tone='Checking planet data','busy'
        elseif fixed then status,tone='Operation in progress. Finish or abandon it to reroll','warn'
        elseif overdue then status,tone='Updating planet data. Your choices are kept','warn'
        elseif not compatible then status,tone=compatibility_reason,'bad'
        elseif not s and not retained then
            status,tone=why=='Choose a planet and map difficulty' and 'Open a planet on the war table first' or why or report or 'Waiting for planet data','warn'
        elseif report then status,tone=report,report_tone
        else status,tone=rules>0 and 'Ready to search' or 'Choose what the operation must contain','idle' end
        -- An empty request is refused by validation; the panel disables Start instead.
        local model={running=busy,locked=locked,ready=ready,can_start=ready and rules>0,can_clear=not locked and rules>0,
            difficulty=difficulty,status=tostring(status),tone=tone,
            step=busy and (running and steps[M.status] or 1) or nil,
            detail=busy and grouped(running and M.search_attempts or 0)..' of '..grouped(default_limit)..' seeds searched'
                or ready and rules>0 and tone=='idle' and 'Rerolls every unstarted operation of the campaign' or '',
            faction=display and catalogue.faction or nil,scope=scope and 'city' or 'planet',
            section=section,items=items,page=mission_page,pages=pages,groups=tabs,group=group,
            slots=display and catalogue.slots or nil,checked=#names,rules=rules,
            summaries={missions=#names>0 and table.concat(names,', ') or 'Any',modifiers=count(modifier_rules),enemies=count(tag_rules)},
            forced=table.concat(forced,', '),
            note=display and section=='enemies' and group==0 and 'Check a mission to set its own enemies' or nil}
        local action=router:step(x,y,user32.GetAsyncKeyState(1)<0,Panel.layout(width,height,model).targets)
        if action=='close' then close()
        elseif action=='cancel' then
            if gap.queued then gap.queued=nil else M.cancel_requested=true;running=false end
            report,report_tone='Search cancelled','idle'
        elseif action=='previous_page' then mission_page=math.max(1,mission_page-1)
        elseif action=='next_page' then mission_page=math.min(pages,mission_page+1)
        elseif type(action)=='string' and action:match('^section:')then
            -- Clicking the open section closes it.
            local name=action:sub(9);section=section~=name and name or nil
        elseif type(action)=='string' and action:match('^group:')then group_choice=tonumber(action:sub(7))
        elseif not locked then
            if action=='clear' then selected={};modifiers={};constellations={};report=nil
            elseif type(action)=='number' then
                if selected[action]then selected[action]=nil
                else
                    local proposed={};for id,v in pairs(selected)do proposed[id]=v end;proposed[action]=true
                    if FilterCatalogue.possible(catalogue,proposed,modifiers,filter)then selected[action]=true end
                end
                prune_groups();report=nil
            elseif type(action)=='string' and action:match('^modifier:')then
                local id=tonumber(action:sub(10))
                modifiers[id]=modifiers[id]==nil and 'require' or modifiers[id]=='require' and 'exclude' or nil
                report=nil
            elseif type(action)=='string' and action:match('^constellation:')then
                local target,id=action:match('^constellation:(%d+):(%d+)$')
                target,id=tonumber(target),tonumber(id)
                local tags=constellations[target] or {}
                tags[id]=tags[id]==nil and 'accept' or tags[id]=='accept' and 'exclude' or nil
                constellations[target]=next(tags) and tags or nil
                report=nil
            elseif action=='start' and model.can_start then
                if s then begin(s)else gap.queued=now end
            end
        end
        if not router.opened and not router.closing then dialog_release('closed');return end
        local temp=stingray.Script.temp_byte_count()
        local ok,err=pcall(function()panel:show(Search.options,selected,face(),{x=x,y=y},model)end)
        stingray.Script.set_temp_byte_count(temp);assert(ok,err)
    end
    M.dialog_enabled=true
    emit('Mission filters: Ctrl+Shift+F8; native cursor; docked panel; key hint beside BACK '..(HINT_WIDGET and 'at widget '..HINT_WIDGET or 'disabled')..'; alone or hosting a lobby; all checked families in one operation; map difficulty; constellations per mission; repeat searches allowed')
end
