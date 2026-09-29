-- HD2-Addon: mods/ipodalexei/mission_reroller_preflight
if rawget(_G, 'MissionRerollerPreflight') then return end
local M={status='initializing',read_only=true}
_G.MissionRerollerPreflight=M
local create_api = (function()
-- Read-only subset of the sibling SentryAimRetention Windows adapter.
return function()
    local ffi = require('ffi')
    assert(ffi.abi('64bit'), 'Windows x64 is required')
    ffi.cdef [[
        void *GetModuleHandleA(const char *name);
        uint32_t GetModuleFileNameW(void *module, uint16_t *path, uint32_t capacity);
        void *GetCurrentProcess(void);
        uint64_t GetTickCount64(void);
        int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
        void *CreateFileW(const uint16_t *path, uint32_t access, uint32_t share, void *security,
                          uint32_t disposition, uint32_t flags, void *template_file);
        int ReadFile(void *file, void *buffer, uint32_t size, uint32_t *read, void *overlapped);
        int CloseHandle(void *handle);
        int32_t BCryptOpenAlgorithmProvider(void **algorithm, const uint16_t *name,
                                            const uint16_t *provider, uint32_t flags);
        int32_t BCryptCloseAlgorithmProvider(void *algorithm, uint32_t flags);
        int32_t BCryptCreateHash(void *algorithm, void **hash, void *object, uint32_t object_size,
                                 const void *secret, uint32_t secret_size, uint32_t flags);
        int32_t BCryptHashData(void *hash, const void *data, uint32_t size, uint32_t flags);
        int32_t BCryptFinishHash(void *hash, void *digest, uint32_t size, uint32_t flags);
        int32_t BCryptDestroyHash(void *hash);
    ]]
    local kernel, bcrypt = ffi.load('kernel32'), ffi.load('bcrypt')
    local process = kernel.GetCurrentProcess()
    local api = {}
    function api.time() return tonumber(kernel.GetTickCount64()) / 1000 end

    function api.module(name)
        local handle = kernel.GetModuleHandleA(name)
        if handle == nil then return nil end
        return ffi.cast('uint8_t *', handle)
    end

    function api.read(address, size)
        local buffer, count = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
        if kernel.ReadProcessMemory(process, address, buffer, size, count) == 0 or count[0] ~= size then
            return nil
        end
        return ffi.string(buffer, size)
    end

    function api.pointer(bytes, offset)
        offset = offset or 0
        if not bytes or offset < 0 or offset + 8 > #bytes then return nil end
        local value = ffi.new('uintptr_t[1]')
        ffi.copy(value, bytes:sub(offset + 1, offset + 8), 8)
        if value[0] < 0x10000 or value[0] >= 0x800000000000 then return nil end
        return ffi.cast('uint8_t *', value[0])
    end

    function api.module_hash(module)
        local path = ffi.new('uint16_t[32768]')
        local length = kernel.GetModuleFileNameW(module, path, 32768)
        assert(length > 0 and length < 32768, 'Cannot resolve module file')
        local file = kernel.CreateFileW(path, 0x80000000, 7, nil, 3, 0x08000000, nil)
        assert(file ~= ffi.cast('void *', -1), 'Cannot read module file')
        local algorithm, hash = ffi.new('void *[1]'), ffi.new('void *[1]')
        local ok, result = pcall(function()
            local name = ffi.new('uint16_t[7]', {83, 72, 65, 50, 53, 54, 0})
            assert(bcrypt.BCryptOpenAlgorithmProvider(algorithm, name, nil, 0) == 0, 'SHA256 unavailable')
            assert(bcrypt.BCryptCreateHash(algorithm[0], hash, nil, 0, nil, 0, 0) == 0, 'SHA256 creation failed')
            local buffer, count = ffi.new('uint8_t[1048576]'), ffi.new('uint32_t[1]')
            while true do
                assert(kernel.ReadFile(file, buffer, 1048576, count, nil) ~= 0, 'Module file read failed')
                if count[0] == 0 then break end
                assert(bcrypt.BCryptHashData(hash[0], buffer, count[0], 0) == 0, 'SHA256 update failed')
            end
            local digest, hex = ffi.new('uint8_t[32]'), {}
            assert(bcrypt.BCryptFinishHash(hash[0], digest, 32, 0) == 0, 'SHA256 finish failed')
            for i = 0, 31 do hex[#hex + 1] = string.format('%02X', digest[i]) end
            return table.concat(hex)
        end)
        if hash[0] ~= nil then bcrypt.BCryptDestroyHash(hash[0]) end
        if algorithm[0] ~= nil then bcrypt.BCryptCloseAlgorithmProvider(algorithm[0], 0) end
        kernel.CloseHandle(file)
        if not ok then error(result) end
        return result
    end
    return api
end

end)()
local expected_code='32c04584c974370f57c033c00f1181888e07000f1181988e07000f1181a88e07000f1181b88e07000f1181c88e0700488981d88e07008981e08e0700b00184d2751c83b9848e07000074134584c9750e84c07447ba02000000e912010000488b0563e51a0248ba2d7f954c2df45158480fafc248ba4f8167f77e7b05144803c2ba020000004889053ce51a0248c1e8208981848e0700e9d5000000c3cccccccc458bc84c8d8180720f004881c1109a0f00e94afff0ffccccccccccccccccccccc20000cccccccccccccccccccccccccc488b0599771a02488b0d9a771a0280b8f8020700007448488b0592771a0280b8e6670100007538488b05d20b050280b88d10000000752880b89910000000751f4883b8e808000000751583b998a21700007c0c83b9a4a21700007c03b001c332c0c3cccccccccccccccccccccccccccc48c7c0ffffffff660f1f84000000000048ffc080bc01ec6941000075f34885c00f95c0c3cccccccccccccccccccccccc4057488b0507771a024c8bc18bfa8b88d86201004c8d90e062010085c90f849600000048895c24108bd9488974241833f60f1f40006666660f1f840000000000418b90d0801f0041bbffffffff4d8b0a8bc685d2742266660f1f8400000000008bc84881c108f801004803c94d390cc87449ffc03bc272e8488d8a08f8010048c1e1048d42014903c8418980d0801f004183fbff75060f57c00f110109790c4983c2084c89098971084883eb017591488b742418488b5c24105fc3448bd883f8ff74b58bc84881c108f8010048c1e1044903c8ebc7cccccccccccccccccccccc488b1529761a0241b802000000488b9298b30000e9f7000000cccccccccccccc'
local loader=rawget(_G,'CowboyBingusModLoader')
if not loader or (loader.api or 0)<1 or (loader.version or 0)<16 then
    M.status='unsupported_loader'; return
end
local log
pcall(function() log=loader.open_log('MissionRerollerPreflight.log') end)
local function emit(s)
    if log then pcall(function() log:write(s..'\n'); log:flush() end) end
end
local function hex(b) return (b:gsub('.',function(c)return string.format('%02x',c:byte())end)) end
local function u(b,o)
    local a,c,d,e=b:byte(o+1,o+4); assert(e,'short read')
    return a+c*256+d*65536+e*16777216
end
local api,game,ffi,kernel
local function read(a,n)
    local bytes=api.read(a,n)
    assert(bytes,'memory read failed')
    return bytes
end
local function pointer(a)
    local value=api.pointer(read(a,8))
    assert(value,'missing pointer')
    return value
end
local function page(a,n,kind)
    local m=ffi.new('MRP_MEMORY_BASIC_INFORMATION[1]')
    assert(kernel.VirtualQuery(a,m,ffi.sizeof(m[0]))==ffi.sizeof(m[0]),'VirtualQuery failed')
    local begin=tonumber(ffi.cast('uintptr_t',a))
    local limit=tonumber(ffi.cast('uintptr_t',m[0].BaseAddress))+tonumber(m[0].RegionSize)
    assert(begin+n<=limit and m[0].State==0x1000 and m[0].Protect==4 and m[0].Type==kind,
           'unexpected target page')
end
local initialized=false
local function initialize()
    ffi=require('ffi'); api=create_api(); kernel=ffi.load('kernel32')
    ffi.cdef[[
        typedef struct {
            void *BaseAddress; void *AllocationBase; uint32_t AllocationProtect;
            uint16_t PartitionId; uint16_t padding; size_t RegionSize;
            uint32_t State; uint32_t Protect; uint32_t Type; uint32_t padding2;
        } MRP_MEMORY_BASIC_INFORMATION;
        size_t VirtualQuery(const void *, void *, size_t);
        uint32_t GetCurrentThreadId(void);
    ]]
    game=assert(api.module('game.dll'),'missing game.dll')
    assert(api.module_hash(game)=='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E','game.dll hash mismatch')
    assert(api.module_hash(assert(api.module(nil)))=='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06','executable hash mismatch')
    assert(hex(read(game+0x12d5670,#expected_code/2))==expected_code,'helper signature mismatch')
    initialized=true
    emit('build=25480438 hashes=verified helper_signature=verified read_only=true')
end
local function snapshot()
    local b=pointer(game+0x347cee8)
    local session=pointer(game+0x347cef0)
    local backend=pointer(game+0x347cee0)
    local root=pointer(game+0x3326340)
    local screen=read(pointer(game+0x347ce28)+0x429c,24)
    local count=u(screen,20)
    if count<1 or count>5 or u(screen,(count-1)*4)~=15 then return nil,'open galactic map' end
    local selection=read(b+0x17a298,20)
    local planet=u(selection,0)
    if planet>=512 then return nil,'select planet' end
    local cache=read(b+0xf9a08,8)
    if u(cache,0)~=planet or cache:byte(5)~=0 or u(read(b+0xffc0c,4),0)~=planet then
        return nil,'waiting for caches'
    end
    assert(u(read(backend+0x702fc,4),0)==14,'backend not ready')
    assert(u(read(backend+0x702f8,4),0)~=0,'backend unavailable')
    assert(read(session+0x167e6,1)=='\0','session gate set')
    assert(read(root+0x108d,1)=='\0' and read(root+0x1099,1)=='\0' and
           read(root+0x8e8,8)==string.rep('\0',8),'transition gates set')
    local sc=u(read(session+0x162d8,4),0)
    local dc=u(read(b+0x1f80d0,4),0)
    assert(sc==1 and dc<=5,'owner count outside supervised bounds')
    local source=read(session+0x162e0,sc*8)
    local dest=read(b+0x1f8080,dc*16)
    local ids={}; local union=0
    for i=0,dc-1 do
        local id=dest:sub(i*16+1,i*16+8)
        assert(id~=string.rep('\0',8) and not ids[id],'invalid destination owner')
        ids[id]=true; union=union+1
    end
    assert(source~=string.rep('\0',8),'invalid source owner')
    if not ids[source] then union=union+1 end
    assert(union<=5,'owner union overflow')
    page(game+0x3483c38,8,0x1000000) -- Authorized native RNG exception, read only here.
    page(b+0x78e84,4,0x20000)
    page(b+0x1f8080,union*16,0x20000)
    page(b+0x1f80d0,4,0x20000)
    local canonical=read(b+0x78e84,96)
    assert(canonical:sub(1,4)==read(b+0x17a2bc,4),'canonical/snapshot seed mismatch')
    local mc=u(read(b+0xffc08,4),0); assert(mc<=330,'mission count overflow')
    local ops=read(b+0xf7280,110*92)
    local missions=read(b+0xf9a10,mc*76)
    assert(pointer(game+0x347cee8)==b and pointer(game+0x347cef0)==session,'root changed')
    return {fingerprint=tostring(b)..tostring(session)..selection..cache..canonical..source..dest..ops..missions,
        planet=planet,seed=u(canonical,0),active=hex(canonical:sub(5)),sc=sc,dc=dc,union=union}
end
local original_update,original_shutdown=rawget(_G,'update'),rawget(_G,'shutdown')
local pack=function(...)return {n=select('#',...),...}end
local thread,previous,stable,last_wait,next_time=nil,nil,0,nil,0
local stopped=false
local function stop(message)
    stopped=true; M.status=message; emit(message)
end
local function tick()
    if stopped then return end
    if not initialized then initialize() end
    local tid=tonumber(kernel.GetCurrentThreadId())
    if thread then assert(thread==tid,'Lua update thread changed') else thread=tid end
    local now=api.time(); if now<next_time then return end; next_time=now+1
    local s,reason=snapshot()
    if not s then
        previous=nil; stable=0
        if last_wait~=reason then emit('waiting: '..reason);last_wait=reason end
        return
    end
    local again=assert(snapshot(),'context changed during capture')
    assert(s.fingerprint==again.fingerprint,'read passes disagree')
    stable=(previous==s.fingerprint) and stable+1 or 1; previous=s.fingerprint
    if stable==1 then emit('observing stable map; read_only=true') end
    if stable>=10 then
        emit(string.format('thread=%d samples=%d planet=%d seed=%u source_count=%d destination_count=%d union=%d',
            thread,stable,s.planet,s.seed,s.sc,s.dc,s.union))
        emit('active_record='..s.active)
        stop('PREFLIGHT_COMPLETE read_only=true native_calls=0; thread consistency does not prove board ownership')
    end
end
_G.update=function(...)
    local result=original_update and pack(original_update(...)) or {n=0}
    if not stopped then local ok,err=pcall(tick);if not ok then stop('PREFLIGHT_STOP '..tostring(err)) end end
    return unpack(result,1,result.n)
end
_G.shutdown=function(...)
    stopped=true
    if log then pcall(function()log:close()end);log=nil end
    if original_shutdown then return original_shutdown(...) end
end
M.status='waiting_for_update'
emit('Mission Reroller Preflight 0.1.1 loaded; read_only=true; no hotkey or native call')
