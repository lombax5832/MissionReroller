-- Modal UI for the in-process predictor. Losing focus releases input ownership
-- but never cancels the search. Only an explicit cancel/close cancels work.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
local M,emit,read,pointer,page,u,hex,snapshot=host.M,host.emit,host.read,host.pointer,host.page,host.u,host.hex,host.snapshot
local reroll_session=host.reroll_session
local map,write,O,verify_code=host.map,host.write,host.O,host.verify_code
local Panel,Hint,Binding,FilterCatalogue,EscapeGate=lib.Panel,lib.Hint,lib.Binding,lib.FilterCatalogue,lib.EscapeGate
local FilterRequest=lib.FilterRequest
local make_gate,make_router,make_cursor=lib.make_gate,lib.make_router,lib.make_cursor
local Search,Constellations,Planet,DayNight=lib.Search,lib.Constellations,lib.Planet,lib.DayNight
local default_limit=hooks.default_limit
local api,game,ffi,user32
host.when_initialized(function(n)api,game,ffi,user32=n.api,n.game,n.ffi,n.user32 end)
local dialog_tick,dialog_release,validate_search_request
do
    local panel,hint,binding,gate,router,exe,cursor
    local difficulty,key_down=10,true
    -- The player's Filters and the panel's model (src/filter_request.lua).
    local filters
    -- Escape closes the dialog. While it is open the game's own Escape
    -- mappings are taken out of its binding map (src/escape_gate.lua), so
    -- the war table does not go BACK as well. They are put back once the
    -- dialog has closed and Escape is up, so the game never sees the press
    -- that closed it. A map that cannot be read leaves Escape to the game
    -- for the session; the key still closes the dialog.
    local VK_ESCAPE=0x1B
    local escape,escape_down,escape_blocked=nil,true,false
    -- The key hint sits beside the war table's own BACK hint
    -- (src/map_screen.lua). nil draws no hint.
    local HINT_WIDGET=map.HINT_WIDGET
    local hint_blocked=false
    -- The dialog opens and closes on the Reroll operations binding of Mod
    -- Bindings Menu's MODS tab, or on F7 while that binding has no key or the
    -- menu is not installed. The hint names the key in use. The shortcut
    -- only acts on the galactic map, never with another screen such as the
    -- options or ESC menu above it.
    local DEFAULT_KEY=0x76
    local screens_logged
    local tag_error
    -- A city or megafactory appears on the map as its operation. The one
    -- under the cursor when the dialog opens, or else the selected one,
    -- limits the dialog and the search to that city.
    local scope
    local function pointed_region()
        local row=map.pointed_row()
        if row and row>=30 then return math.floor((row-30)/10)end
    end
    local function accepts(row)return Search.in_scope(row,scope)end
    local catalogue,catalogue_key,catalogue_view
    local running=false
    -- Planet data is briefly unavailable now and then. since: when the gap
    -- began. queued: when a start was requested during it. fixed: the last
    -- known answer, kept through the gap.
    local gap={}
    -- The outcome of the last search, or an error. Editing the request
    -- discards it.
    -- Phases, captions and steps belong to reroll_session.
    local report,report_tone
    -- Closing the dialog cancels a running search.
    local function close()
        if running or gap.queued then report,report_tone='Search cancelled','idle' end
        if running then reroll_session.cancel()end;running=false;gap.queued=nil;router:close()
    end
    local function escape_key()return user32.GetAsyncKeyState(VK_ESCAPE)<0 end
    local function hold_escape()
        -- Still held from a close whose Escape has not been released.
        if not escape or escape_blocked or escape.held then return end
        local ok,value=pcall(escape.hold,escape)
        if ok then emit('ESCAPE_HELD mappings='..value..' actions='..(escape.actions~='' and escape.actions or 'none'))return end
        escape_blocked=true;emit('ESCAPE_BLOCKED '..tostring(value))
        -- Put back whatever was written before the failure.
        if escape.held then local restored=escape:release();emit('ESCAPE_RESTORED buckets='..restored)end
    end
    -- Raises when a bucket cannot be written back, which stops the mod.
    local function restore_escape(force)
        if not (escape and escape.held)then return end
        if not force and escape_key()then return end
        local restored,skipped=escape:release()
        emit('ESCAPE_RESTORED buckets='..restored..(skipped>0 and ' changed='..skipped or ''))
    end
    local function face()
        local function hash(a)local b=read(a,8);return string.format('%08x%08x',u(b,4),u(b,0))end
        local f={font=hash(game+O.rva.font),material=hash(pointer(game+O.rva.font_material)+24),atlas=hash(game+O.rva.font_atlas)}
        for _,v in pairs(f)do assert(v~='0000000000000000','Font not ready')end
        return f
    end
    -- The screen stack, bottom first, for the log.
    local function screens()
        local list,depth=map.screens()
        if not list then return 'depth '..depth end
        return table.concat(list,',')
    end
    local function check_window()
        -- The native window and cursor code (src/offsets.lua), checked before each use.
        local ok,err=pcall(verify_code,{'window_focus_get','window_focus_set','window_argument','cursor_shown_get',
            'cursor_shown_set','cursor_apply','cursor_restore'})
        assert(ok,'Window binding signature mismatch: '..tostring(err))
        local app=pointer(exe+O.rva.application)
        assert(u(read(app+O.application.window_count,4),0)==1,'Expected one game window')
        local window=pointer(pointer(app+O.application.windows))
        page(window+0x80,10,0x20000)
        local flag=read(window+0x89,1):byte();assert(flag==0 or flag==1,'Invalid focus flag')
        return tostring(window)
    end
    dialog_release=function(reason)
        if gate then gate:release()end
        router=nil
        if panel then panel:clear()end
        if hint then pcall(function()hint:clear()end)end
        -- A normal close waits for Escape to be released; every other
        -- release puts the mappings back now.
        local ok,err=pcall(restore_escape,reason~='closed')
        if not ok then emit('ESCAPE_RESTORE_FAILED '..tostring(err))end
        local drifts=gate and gate.drifts or 0
        emit('MODAL_RELEASE '..reason..(drifts>0 and ' reasserted='..drifts..' last='..tostring(gate.reason) or ''))
    end
    local function init()
        exe=assert(api.module(nil));panel=Panel.new(assert(stingray));hint=Hint.new(stingray)
        binding=Binding.new({read=read,pointer=pointer,u=u,game=game,emit=emit,keyboard=stingray.Keyboard,
            menu=function()return rawget(_G,'ModBindingsMenu')end})
        cursor=make_cursor(ffi)
        gate=make_gate(stingray.Window,check_window)
        escape=EscapeGate.new({read=read,u=u,
            buckets=function()
                local owner=pointer(game+Binding.INPUT_OWNER)
                assert(u(read(owner+Binding.BINDING_MAP+8,4),0)==EscapeGate.BUCKETS,'Unexpected binding map size')
                return pointer(owner+Binding.BINDING_MAP)
            end,
            write=function(a,bytes)write(a,bytes,'Binding map')end})
    end
    local function context()
        local viewed,d=map.viewed()
        if viewed>=512 or d<1 or d>10 then return nil,'Choose a planet and map difficulty' end
        local view=viewed..':'..d
        local s,why=snapshot(true)
        if not s then return nil,why,view end
        if viewed~=s.planet then
            return nil,'Waiting for the viewed planet',view
        end
        return s,d,view
    end
    local function catalogue_for(s,d,within,only)
        -- Mission and modifier filters survive a constellation input failure.
        local result,err=Planet.bind(read,u,api.pointer,game,s.board,s.planet).catalogue(s,d,
            only or within and function(row)return Search.in_scope(row,within)end)
        if err and tostring(err)~=tag_error then tag_error=tostring(err);emit('CONSTELLATION_CATALOGUE_BLOCKED '..tag_error)end
        return result
    end
    validate_search_request=function(s,request)
        FilterCatalogue.validate(catalogue_for(s,request.difficulty,Search.scope(request.scope)),request.required,request.modifiers,
            request.constellations,request.time)
    end
    -- Day and night on the viewed planet while a time of day is chosen
    -- (src/day_night.lua), refreshed once a second: the buffer note, or why
    -- a search cannot start. Cities do not move, so when only a city can
    -- meet the filters and none stays on the chosen side for the buffer,
    -- the search waits for one and says how long.
    local sky_planet,sky_state,sky_key,sky_at,sky_error
    local open_catalogue,open_key
    local function outside_cities(s)
        local key=s.fingerprint..':'..difficulty
        if key~=open_key then
            open_key=key
            local ok,value=pcall(catalogue_for,s,difficulty,nil,function(row)return row<30 end)
            open_catalogue=ok and value or nil
        end
        return open_catalogue
    end
    local function sky_view(s,now)
        local key=s.fingerprint..':'..difficulty..':'..(scope and scope.region or 'planet')..':'..filters.time
        if sky_state and key==sky_key and now-sky_at<1 then return sky_state end
        local ok,value=pcall(function()
            local ref=map.sky()
            if not sky_planet or sky_planet.planet~=s.planet or sky_planet.sky.seed~=ref.seed then
                local planet,why=DayNight.load(read,u,s.board,s.planet,ref)
                if not planet then sky_planet=nil;return {pending=why}end
                sky_planet=planet
                emit(string.format('DAYNIGHT_PLANET planet=%d day_s=%.0f buffer_s=%.0f band_min=%d',s.planet,planet.day_length,planet.buffer,DayNight.BAND))
            end
            local planet=sky_planet
            local note=(planet.buffer<DayNight.WANTED and 'SHORT DAYS: ' or '')..'HOLDS '..DayNight.duration(planet.buffer)
                ..' / DAY '..DayNight.duration(planet.day_length)
            local open=not scope and outside_cities(s)
            if open and filters:possible(open)then return {note=note}end
            local nodes={}
            for _,op in ipairs(s.decoded.operations)do
                if op.difficulty==difficulty and op.row>=30 and op.row<110 and (not scope or accepts(op.row))then
                    for _,mission in ipairs(op.missions or {})do nodes[#nodes+1]=mission.level_index end
                end
            end
            if #nodes==0 then return {note=note}end
            local wait=DayNight.wait(planet,nodes,filters.time,DayNight.war_time(read,s.board))
            if wait==0 then return {note=note}end
            local side=filters.time=='day' and 'Day' or 'Night'
            if not wait then return {note=note,blocked='No city here stays in '..side:lower()..' for '..DayNight.duration(planet.buffer)}end
            return {note=note,blocked=side..(scope and ' here' or ' at a city here')..' in '..DayNight.duration(wait)}
        end)
        if ok then sky_error=nil
        elseif tostring(value)~=sky_error then sky_error=tostring(value);emit('DAYNIGHT_BLOCKED '..sky_error)end
        sky_state=ok and value or {pending='Day and night unavailable here'}
        sky_key,sky_at=key,now
        return sky_state
    end
    local function begin(s)
        -- Refresh eligibility immediately before accepting a request.
        local ok,err=pcall(function()filters:validate(catalogue_for(s,difficulty,scope))end)
        if ok then
            running=reroll_session.start(filters:to_request(scope,difficulty))
            if running then report,report_tone='Checking planet data','idle' else report,report_tone=reroll_session.view().caption,'bad' end
            emit('DIALOG_SEARCH planet='..s.planet..' region='..(scope and scope.region or 'all')..' difficulty='..difficulty
                ..' players='..tostring(s.sc))
        else report,report_tone=tostring(err),'bad' end
    end
    dialog_tick=function(focused,now)
        if not panel then init()end
        filters=filters or FilterRequest.new(Search.options,FilterCatalogue,Constellations.names)
        if not router then restore_escape(not focused)end
        local run=reroll_session.view()
        if running and not run.running then
            running=false;report=run.report or run.caption
            report_tone=run.report and 'warn' or run.tone
            if run.outcome=='publication_test_passed' and router then router:close()end
        end
        local pulse=binding and focused and binding:step() or false
        local keys,bind_state=nil,'unknown'
        if binding then keys,bind_state=binding:keys()end
        -- The map is on screen when it is the top screen and its BACK hint is
        -- fully shown. Without a readable hint the top screen alone decides.
        -- The hint is cosmetic: a failure disables it for the session and is
        -- logged once, without stopping the mod.
        local function block(err)hint_blocked=true;pcall(function()hint:clear()end);emit('HINT_BLOCKED '..tostring(err))end
        local anchor,on_map=nil,false
        if focused then
            if not hint_blocked then
                local ok,value=pcall(map.back_hint)
                if ok then anchor=value else block(value)end
            end
            if anchor then on_map=true
            else
                local top_ok,top=pcall(map.on_top)
                on_map=top_ok and top and (hint_blocked or not HINT_WIDGET)or false
            end
        end
        if hint and not hint_blocked then
            local ok,err=pcall(function()
                if anchor then hint:show(anchor,face(),keys)else hint:clear()end
            end)
            if not ok then block(err)end
        end
        if not focused then
            if router then dialog_release('focus lost; search continues')end
            if gap.queued then gap.queued=nil;report,report_tone='Search cancelled','idle' end
            key_down=true;return
        end
        -- A bound key replaces F7; an unreadable binding keeps both.
        local down=pulse or bind_state~='bound' and user32.GetAsyncKeyState(DEFAULT_KEY)<0
        local pressed=down and not key_down
        key_down=down
        if pressed and not on_map then
            local ok,list=pcall(screens)
            local line='SHORTCUT_IGNORED screens='..(ok and list or '?')
            if line~=screens_logged then screens_logged=line;emit(line)end
        elseif pressed then
            if router then close()
            else
                catalogue_key=nil;filters:open();gap={}
                local ok,region=pcall(pointed_region)
                scope=ok and region and {region=region} or nil
                router=make_router(gate);router:open()
                -- An Escape held while opening does not close the dialog.
                escape_down=true;hold_escape()
                local ok,list=pcall(screens)
                emit('MODAL_OPEN scope='..(scope and 'region '..scope.region or 'planet')..' key='..(keys or 'F7')
                    ..' screens='..(ok and list or '?'))
            end
        end
        if not router then return end
        local escape_now=escape_key()
        local escape_pressed=escape_now and not escape_down and router.opened
        escape_down=escape_now
        local cx,cy,cw,ch=cursor.client(user32.GetForegroundWindow())
        local width,height=stingray.Gui.resolution()
        local x=cx*width/cw;local y=height-cy*height/ch
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
                    local removed=filters:prune(value,view~=catalogue_view)
                    catalogue=value;catalogue_key=key;catalogue_view=view
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
        -- The operation in progress keeps its missions; a city has no other
        -- operation at this difficulty to reroll.
        if s then
            gap.fixed=false
            if scope then
                local row,level=Search.active_row(s)
                gap.fixed=row~=nil and level==difficulty and accepts(row)
            end
        elseif not retained then gap.fixed=false end
        local fixed=gap.fixed
        local compatible=filters:possible(catalogue)
        -- A start requested during a gap waits for fresh data, and is then
        -- validated like any other.
        if gap.queued then
            if s then
                gap.queued=nil
                local sky=filters.time and sky_view(s,now)
                if compatible and not fixed and filters:rule_count()>0 and not (sky and (sky.blocked or sky.pending))then begin(s)end
            elseif not retained then gap.queued=nil;report,report_tone='Planet changed; search not started','warn'
            elseif now-gap.queued>=10 then gap.queued=nil;report,report_tone='Planet data did not arrive; try again','warn' end
        end
        run=reroll_session.view()
        local sky
        if filters.time then
            if s then sky=sky_view(s,now)elseif retained then sky=sky_state end
        end
        local model=filters:model(catalogue,{shown=s or running or retained,fresh=s~=nil,retained=retained,running=running,
            queued=gap.queued~=nil,fixed=fixed,overdue=overdue,run=run,why=why,report=report,tone=report_tone,
            difficulty=difficulty,scope=scope,limit=default_limit,sky=sky})
        -- Losing input ownership closes the dialog and restores the window;
        -- it does not stop the mod. A running search continues, as on focus loss.
        local ok,action=pcall(router.step,router,x,y,user32.GetAsyncKeyState(1)<0,Panel.layout(width,height,model).targets)
        if not ok then
            emit('MODAL_INPUT_LOST '..tostring(action)..(gate.reason and ' ('..gate.reason..')' or ''))
            if not pcall(router.abort,router) and gate.forget then gate:forget()end
            report,report_tone='Dialog closed: input ownership lost. Press the shortcut to reopen','warn'
            gap.queued=nil
            dialog_release('input ownership lost')
            return
        end
        if action=='close' or escape_pressed then close()
        elseif action=='cancel' then
            if gap.queued then gap.queued=nil else reroll_session.cancel();running=false end
            report,report_tone='Search cancelled','idle'
        elseif action=='start' then
            if model.can_start then if s then begin(s)else gap.queued=now end end
        elseif not filters:navigate(action) and not model.locked and filters:toggle(action,catalogue)then report=nil end
        if not router.opened and not router.closing then dialog_release('closed');return end
        local temp=stingray.Script.temp_byte_count()
        local ok,err=pcall(function()panel:show(Search.options,filters.selected,face(),{x=x,y=y},model)end)
        stingray.Script.set_temp_byte_count(temp);assert(ok,err)
    end
    M.dialog_enabled=true
    emit('Mission filters: F7 or the Reroll operations binding on the MODS tab, on the galactic map only; Escape closes; native cursor; docked panel; key hint beside BACK '..(HINT_WIDGET and 'at widget '..HINT_WIDGET or 'disabled')..'; alone or hosting a lobby; all checked families in one operation; map difficulty; constellations per mission; repeat searches allowed')
end
return {dialog_tick=dialog_tick,dialog_release=dialog_release,validate_search_request=validate_search_request}
