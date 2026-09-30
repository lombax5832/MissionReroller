-- Cursor position and client area of a window, resolved by address.
--
-- LuaJIT keeps the first `ffi.cdef` of a function name for the whole VM and
-- silently ignores later ones, even through a fresh `ffi.load`. Every addon
-- shares that VM, so another addon that declares `int GetCursorPos(POINT *)`
-- with its own POINT struct wins, and buffers of our struct are then rejected
-- with "cannot convert 'struct N [1]' to 'struct M *'". The three entry
-- points used here are therefore fetched with GetProcAddress and called
-- through unnamed function pointers that take untyped pointers, which no
-- declaration elsewhere can change.
return function(ffi)
    ffi.cdef[[void *GetModuleHandleA(const char *); void *GetProcAddress(void *, const char *);]]
    local kernel=ffi.load('kernel32')
    local user32=kernel.GetModuleHandleA('user32.dll')
    assert(user32~=nil,'user32 not loaded')
    local function import(name,signature)
        local address=kernel.GetProcAddress(user32,name)
        assert(address~=nil,name..' unavailable')
        return ffi.cast(signature,address)
    end
    local get_cursor_pos=import('GetCursorPos','int (*)(void *)')
    local screen_to_client=import('ScreenToClient','int (*)(void *, void *)')
    local get_client_rect=import('GetClientRect','int (*)(void *, void *)')
    local point=ffi.typeof('struct { int32_t x,y; }[1]')
    local rect=ffi.typeof('struct { int32_t left,top,right,bottom; }[1]')
    local C={}
    -- The cursor in client pixels of `window`, then the client width and height.
    function C.client(window)
        local p,r=point(),rect()
        assert(get_cursor_pos(p)~=0 and screen_to_client(window,p)~=0 and get_client_rect(window,r)~=0,'Mouse position unavailable')
        assert(r[0].right>0 and r[0].bottom>0,'Invalid client dimensions')
        return tonumber(p[0].x),tonumber(p[0].y),tonumber(r[0].right),tonumber(r[0].bottom)
    end
    return C
end
