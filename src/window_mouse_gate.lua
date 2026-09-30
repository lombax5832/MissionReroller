-- Candidate window gate, not a proven native-HUD modal contract.
return function(window,check)
    local G={};local saved,saved_cursor,handle,token
    -- Times a held gate found the game had changed its flags underneath it
    -- and took them back, and what it found last. The game does this after
    -- a resolution change; before v0.21.0 it stopped the mod.
    G.drifts,G.reason=0,nil
    function G:acquire()
        assert(not handle,'Mouse gate already held')
        local t=check()
        local h=assert(window.get_main_window(),'Main window unavailable')
        local s=window.mouse_focus(h)
        assert(type(s)=='boolean' and s,'Window mouse focus already disabled')
        local c=window.show_cursor(h)
        assert(type(c)=='boolean','Cursor visibility unavailable')
        -- Nothing is kept until both flags are confirmed: a failed acquire
        -- puts back what it changed and leaves the gate free.
        window.set_mouse_focus(h,false)
        if window.mouse_focus(h)~=false then pcall(window.set_mouse_focus,h,s);error('Mouse focus did not change')end
        window.set_show_cursor(h,true,false) -- Preserve pointer position.
        if window.show_cursor(h)~=true then
            pcall(window.set_show_cursor,h,c,false);pcall(window.set_mouse_focus,h,s);error('Native cursor not enabled')
        end
        handle,token,saved,saved_cursor=h,t,s,c
        self.drifts,self.reason=0,nil
        return true
    end
    function G:held()
        if not handle then return false end
        if check()~=token then self.reason='window identity changed';return false end
        local focus,cursor=window.mouse_focus(handle),window.show_cursor(handle)
        if focus==false and cursor==true then return true end
        -- Take ownership back with the same calls as acquire, on the same
        -- handle. Holding fails only when they no longer stick.
        if focus~=false then window.set_mouse_focus(handle,false)end
        if cursor~=true then window.set_show_cursor(handle,true,false)end
        self.drifts=self.drifts+1
        self.reason=string.format('mouse_focus=%s show_cursor=%s reapplied',tostring(focus),tostring(cursor))
        return window.mouse_focus(handle)==false and window.show_cursor(handle)==true
    end
    function G:release()
        if not handle then return true end
        assert(check()==token,'Window identity changed; retained handle not safe to restore')
        -- Restore input even if cursor restoration fails.
        local ok,err=true,nil
        if saved_cursor~=nil then ok,err=pcall(window.set_show_cursor,handle,saved_cursor,false) end
        window.set_mouse_focus(handle,saved)
        assert(window.mouse_focus(handle)==saved,'Mouse focus restoration failed')
        assert(ok,err)
        if saved_cursor~=nil then assert(window.show_cursor(handle)==saved_cursor,'Cursor restoration failed') end
        handle,saved,saved_cursor,token=nil,nil,nil,nil
        return true
    end
    -- Drop a handle that release refused to touch, so the gate can be
    -- acquired again on the window the game has now. Nothing is written.
    function G:forget()
        handle,saved,saved_cursor,token=nil,nil,nil,nil
    end
    return G
end
