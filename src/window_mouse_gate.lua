-- Candidate window gate, not a proven native-HUD modal contract.
return function(window,check)
    local G={};local saved,saved_cursor,handle,token
    function G:acquire()
        assert(not handle,'Mouse gate already held')
        token=check()
        handle=assert(window.get_main_window(),'Main window unavailable')
        saved=window.mouse_focus(handle)
        assert(type(saved)=='boolean' and saved,'Window mouse focus already disabled')
        saved_cursor=window.show_cursor(handle)
        assert(type(saved_cursor)=='boolean','Cursor visibility unavailable')
        -- Save ownership before mutation so callers can restore after a partial failure.
        window.set_mouse_focus(handle,false)
        assert(window.mouse_focus(handle)==false,'Mouse focus did not change')
        window.set_show_cursor(handle,true,false) -- Preserve pointer position.
        assert(window.show_cursor(handle)==true,'Native cursor not enabled')
        return true
    end
    function G:held()
        return handle~=nil and check()==token and window.mouse_focus(handle)==false
            and window.show_cursor(handle)==true
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
    return G
end
