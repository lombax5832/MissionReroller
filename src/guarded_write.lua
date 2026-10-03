-- The one way the runtimes write game memory: host.write(address, bytes,
-- what, verify). It checks that the target is committed private read/write
-- memory (host.page, VirtualQuery), writes through WriteProcessMemory on the
-- game's own process, and reads the bytes back unless verify is false.
-- Failures raise '<what> write failed' or '<what> write did not persist'.
-- Only the builds that publish include this file; the read-only builds carry
-- no write at all.
--
-- LuaJIT keeps the first `ffi.cdef` of a function name for the whole VM, and
-- every addon shares that VM (src/window_cursor.lua). The write entry point
-- is therefore fetched with GetProcAddress and called through an unnamed
-- function pointer that takes untyped pointers, which no declaration
-- elsewhere can change. It is resolved on the first write.
return function(host)
    local read,page=host.read,host.page
    local ffi,kernel,write_memory
    host.when_initialized(function(n)ffi,kernel=n.ffi,n.kernel end)
    local function native(address,bytes)
        if not write_memory then
            ffi.cdef[[void *GetModuleHandleA(const char *); void *GetProcAddress(void *, const char *);]]
            local entry=kernel.GetProcAddress(kernel.GetModuleHandleA('kernel32.dll'),'WriteProcessMemory')
            assert(entry~=nil,'WriteProcessMemory unavailable')
            write_memory=ffi.cast('int (*)(void *, void *, const void *, size_t, void *)',entry)
        end
        local count=ffi.new('size_t[1]')
        return write_memory(kernel.GetCurrentProcess(),address,bytes,#bytes,count)~=0 and count[0]==#bytes
    end
    return function(address,bytes,what,verify)
        page(address,#bytes,0x20000,what)
        assert(native(address,bytes),what..' write failed')
        if verify~=false then assert(read(address,#bytes)==bytes,what..' write did not persist')end
    end
end
