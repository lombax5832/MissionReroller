-- Modal UI for the in-process predictor. Losing focus releases input ownership
-- but never cancels the search. Only an explicit cancel/close cancels work.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
local M,emit,read,pointer,page,u,hex,snapshot=host.M,host.emit,host.read,host.pointer,host.page,host.u,host.hex,host.snapshot
local reroll_session=host.reroll_session
local Panel,Hint,Binding,Compatibility,FilterCatalogue,EscapeGate=lib.Panel,lib.Hint,lib.Binding,lib.Compatibility,lib.FilterCatalogue,lib.EscapeGate
local FilterRequest=lib.FilterRequest
local make_gate,make_router,window_signatures,make_cursor=lib.make_gate,lib.make_router,lib.window_signatures,lib.make_cursor
local Search,Constellations,make_constellation_inputs=lib.Search,lib.Constellations,lib.make_constellation_inputs
local make_composition_inputs,make_config,make_effects=lib.make_composition_inputs,lib.make_config,lib.make_effects
local mission_eligible,make_environments=lib.mission_eligible,lib.make_environments
local default_limit=hooks.default_limit
local api,game,ffi,kernel,user32
host.when_initialized(function(n)api,game,ffi,kernel,user32=n.api,n.game,n.ffi,n.kernel,n.user32 end)
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
    -- The key hint sits beside the war table's own BACK hint, a widget of
    -- the map screen object: the 136x32 design-unit container at local
    -- (56,16) that holds the key cap and the BACK label, found by
    -- scripts/survey_map_widgets.py on 2026-09-29. nil draws no hint.
    local HINT_WIDGET=1696
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
        local rows=read(pointer(game+0x3326aa0)+0x4f00,8)
        local row=u(rows,4);if row>=110 then row=u(rows,0)end
        if row>=30 and row<110 then return math.floor((row-30)/10)end
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
    -- The screen stack, bottom first, for the log.
    local function screens()
        local screen=read(pointer(game+0x347ce28)+0x429c,24);local depth=u(screen,20)
        if depth<1 or depth>5 then return 'depth '..depth end
        local list={};for i=1,depth do list[i]=u(screen,(i-1)*4)end
        return table.concat(list,',')
    end
    -- Whether the galactic map (15) is the top screen.
    local function map_on_top()
        local screen=read(pointer(game+0x347ce28)+0x429c,24);local depth=u(screen,20)
        return depth>=1 and depth<=5 and u(screen,(depth-1)*4)==15
    end
    local function back_hint()
        if not HINT_WIDGET then return nil end
        if not map_on_top()then return nil end
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
            write=function(a,bytes)
                page(a,#bytes,0x20000)
                ffi.cdef[[int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);]]
                local count=ffi.new('size_t[1]')
                assert(kernel.WriteProcessMemory(kernel.GetCurrentProcess(),a,bytes,#bytes,count)~=0
                    and count[0]==#bytes,'Binding map write failed')
                assert(read(a,#bytes)==bytes,'Binding map write did not persist')
            end})
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
                local ok,value=pcall(back_hint)
                if ok then anchor=value else block(value)end
            end
            if anchor then on_map=true
            else
                local top_ok,top=pcall(map_on_top)
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
                if compatible and not fixed and filters:rule_count()>0 then begin(s)end
            elseif not retained then gap.queued=nil;report,report_tone='Planet changed; search not started','warn'
            elseif now-gap.queued>=10 then gap.queued=nil;report,report_tone='Planet data did not arrive; try again','warn' end
        end
        run=reroll_session.view()
        local model=filters:model(catalogue,{shown=s or running or retained,fresh=s~=nil,retained=retained,running=running,
            queued=gap.queued~=nil,fixed=fixed,overdue=overdue,run=run,why=why,report=report,tone=report_tone,
            difficulty=difficulty,scope=scope,limit=default_limit})
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
