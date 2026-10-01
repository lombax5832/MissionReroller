if rawget(_G, 'MissionRerollerExperiment') then return end
local M={status='initializing',read_only=false,native_calls=0}
-- The build's mode: read_only for the diagnostic builds, preview_prediction
-- where prediction may inspect the viewed planet (publication still checks
-- the ship/view/canonical/UI planet agree in its own preflight).
M.read_only=config.read_only==true;M.preview_prediction=config.preview_prediction;M.version=config.version
_G.MissionRerollerExperiment=M
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
-- The build's offsets: offsets (src/offsets.lua) for the first-frame checks,
-- O (src/offset_values.lua) for the reads.
local hashes=offsets.hashes
local loader=rawget(_G,'CowboyBingusModLoader')
if not loader or (loader.api or 0)<1 or (loader.version or 0)<16 then
    M.status='unsupported_loader'; return
end
local log
pcall(function() log=loader.open_log('MissionRerollerExperiment.log') end)
local function emit(s)
    if log then pcall(function() log:write(s..'\n'); log:flush() end) end
end
local function hex(b) return (b:gsub('.',function(c)return string.format('%02x',c:byte())end)) end
local function u(b,o)
    local a,c,d,e=b:byte(o+1,o+4); assert(e,'short read')
    return a+c*256+d*65536+e*16777216
end
local api,game,ffi,kernel,user32
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
-- The galactic map screen: its screen stack, map UI and BACK hint. It reads
-- through the adapter's own locals, so the native handles reach it too.
local map_screen=make_map_screen({read=function(a,n)return read(a,n)end,pointer=function(a)return pointer(a)end,u=u,
    pointer_at=function(bytes,offset)return api.pointer(bytes,offset)end,
    game=function()return game end,ffi=function()return ffi end})
local function page(a,n,kind)
    local m=ffi.new('MRE_MEMORY_BASIC_INFORMATION[1]')
    -- C declarations are shared by every addon in the VM and the first one
    -- wins: Mod Bindings Menu declares VirtualQuery with its own struct
    -- pointer. A void pointer converts to whichever declaration won.
    assert(kernel.VirtualQuery(a,ffi.cast('void *',m),ffi.sizeof(m[0]))==ffi.sizeof(m[0]),'VirtualQuery failed')
    local begin=tonumber(ffi.cast('uintptr_t',a))
    local limit=tonumber(ffi.cast('uintptr_t',m[0].BaseAddress))+tonumber(m[0].RegionSize)
    assert(begin+n<=limit and m[0].State==0x1000 and m[0].Protect==4 and m[0].Type==kind,
           'unexpected target page')
end
-- The players of the session: one alone, up to four in a lobby. Only the
-- dialog build accepts a lobby; the earlier builds were tested alone.
local function participants(session)
    local n=u(read(session+O.session.player_count,4),0)
    assert(n>=1 and n<=(M.dialog_enabled and 4 or 1),'owner count outside supervised bounds')
    local bytes,list,known=read(session+O.session.players,n*8),{},{}
    for i=0,n-1 do
        local id=bytes:sub(i*8+1,i*8+8)
        assert(id~=string.rep('\0',8) and not known[id],'invalid source owner')
        known[id]=true;list[#list+1]=id
    end
    return bytes,list,known
end
local initialized=false
local binders={}
local bases={}
local function sorted_names(section)
    local names={};for name in pairs(section)do names[#names+1]=name end
    table.sort(names);return names
end
-- A code entry of offsets.lua still holds its bytes, or its SHA-256; an
-- entry within another is checked with it.
local function verify_code(names)
    for _,name in ipairs(names)do
        local entry=assert(offsets.code[name],'unknown code entry '..tostring(name))
        local at=bases[entry.module]+entry.rva
        if entry.bytes then
            assert(hex(read(at,#entry.bytes/2))==entry.bytes,'offset signature '..name..' mismatch')
        elseif entry.sha256 then
            assert(sha256(read(at,entry.size))==entry.sha256,'offset signature '..name..' mismatch')
        end
    end
end
-- Every code entry, and the instruction that anchors each global and each
-- struct field anchored to an instruction rather than a code entry.
local function verify_offsets()
    local names=sorted_names(offsets.code)
    verify_code(names)
    local anchored=0
    local function verify_anchor(module,anchor,name)
        local bytes=anchor.bytes
        assert(hex(read(bases[module]+anchor.rva,#bytes/2))==bytes,'offset anchor '..name..' mismatch')
        anchored=anchored+1
    end
    for _,name in ipairs(sorted_names(offsets.globals))do
        local entry=offsets.globals[name]
        if entry.anchor then verify_anchor(entry.module,entry.anchor,name)end
    end
    for _,struct in ipairs(sorted_names(offsets.structs))do
        local fields=offsets.structs[struct]
        for _,field in ipairs(sorted_names(fields))do
            local anchor=fields[field].anchor
            if type(anchor)=='table' then verify_anchor(anchor.module or 'game',anchor,struct..'.'..field)end
        end
    end
    return #names,anchored
end
local function initialize()
    ffi=require('ffi'); api=create_api(); kernel=ffi.load('kernel32')
    ffi.cdef[[
        typedef struct {
            void *BaseAddress; void *AllocationBase; uint32_t AllocationProtect;
            uint16_t PartitionId; uint16_t padding; size_t RegionSize;
            uint32_t State; uint32_t Protect; uint32_t Type; uint32_t padding2;
        } MRE_MEMORY_BASIC_INFORMATION;
        size_t VirtualQuery(const void *, void *, size_t);
        uint32_t GetCurrentThreadId(void);
        uint32_t GetCurrentProcessId(void);
        int16_t GetAsyncKeyState(int key);
        void *GetForegroundWindow(void);
        uint32_t GetWindowThreadProcessId(void *, uint32_t *);
    ]]
    game=assert(api.module('game.dll'),'missing game.dll')
    local exe=assert(api.module(nil))
    assert(api.module_hash(game)==hashes.game,'game.dll hash mismatch')
    assert(api.module_hash(exe)==hashes.exe,'executable hash mismatch')
    bases.game,bases.exe=game,exe
    local signatures,anchors=verify_offsets()
    user32=ffi.load('user32')
    initialized=true
    for _,bind in ipairs(binders)do bind({api=api,game=game,ffi=ffi,kernel=kernel,user32=user32})end
    emit('build='..O.build..' hashes=verified signatures='..signatures..' anchors='..anchors..' verified')
end
local function snapshot(viewed_planet)
    if viewed_planet then assert(M.read_only or M.preview_prediction,'Preview snapshots are read-only')end
    local b=pointer(game+O.rva.board)
    local session=pointer(game+O.rva.session)
    local backend=pointer(game+O.rva.backend)
    local root=pointer(game+O.rva.ui_root)
    local screen=map_screen.stack()
    if not map_screen.on_top(screen) then return nil,'open galactic map' end
    local selection=read(b+O.board.selection,20)
    local planet=u(selection,viewed_planet and 4 or 0)
    if planet>=512 then return nil,'select planet' end
    local cache=read(b+O.board.operation_cache,8)
    if u(cache,0)~=planet or cache:byte(5)~=0 or u(read(b+O.board.mission_cache,4),0)~=planet then
        return nil,'waiting for caches'
    end
    local pending=u(read(backend+O.backend.pending_requests,4),0)
    assert(pending<=64,'invalid backend request count')
    if pending~=0 then return nil,'waiting for pending backend requests' end
    assert(u(read(backend+O.backend.state,4),0)==14,'backend not ready')
    assert(u(read(backend+O.backend.available,4),0)~=0,'backend unavailable')
    assert(read(session+O.session.gate,1)=='\0','session gate set')
    assert(read(root+O.ui_root.loading_gate,1)=='\0' and read(root+O.ui_root.transition_gate,1)=='\0' and
           read(root+O.ui_root.transition,8)==string.rep('\0',8),'transition gates set')
    local source,sources,known=participants(session)
    local sc=#sources
    -- In a lobby the board belongs to its host, and only the host rerolls.
    -- Alone nothing more is read than before.
    if sc>1 then
        local player=read(session+O.session.local_player,8)
        if not (known[player] and read(b+O.board.selection_owner,8)==player)then return nil,'Only the host can reroll operations' end
    end
    local dc=u(read(b+O.board.owner_count,4),0)
    assert(dc<=5,'owner count outside supervised bounds')
    local dest=read(b+O.board.owners,dc*16)
    local ids={}; local union=0
    for i=0,dc-1 do
        local id=dest:sub(i*16+1,i*16+8)
        assert(id~=string.rep('\0',8) and not ids[id],'invalid destination owner')
        ids[id]=true; union=union+1
    end
    for _,id in ipairs(sources)do if not ids[id] then union=union+1 end end
    assert(union<=5,'owner union overflow')
    page(game+O.rva.rng_state,8,0x1000000) -- Only the native helper may update this module data.
    page(b+O.board.seed,4,0x20000)
    page(b+O.board.owners,union*16,0x20000)
    page(b+O.board.owner_count,4,0x20000)
    local canonical=read(b+O.board.seed,96)
    if canonical:sub(1,4)~=read(b+O.board.published_seed,4) then return nil,'waiting for seed publication' end
    local mc=u(read(b+O.board.mission_count,4),0); assert(mc<=330,'mission count overflow')
    local ops=read(b+O.board.operations,110*92)
    local missions=read(b+O.board.missions,mc*76)
    assert(pointer(game+O.rva.board)==b and pointer(game+O.rva.session)==session,'root changed')
    -- The core decoder's first word denotes the buffer's planet. Normalize only
    -- this local decoder input; retain the raw selection in the stability key.
    local decoded_selection=viewed_planet and (selection:sub(5,8)..selection:sub(5)) or selection
    local frame={selection=decoded_selection,operations=ops,operation_cache=cache,mission_count=read(b+O.board.mission_count,4),mission_cache=read(b+O.board.mission_cache,4),missions=missions,campaign_seed=canonical:sub(1,4),screen=screen}
    local decoded=core.inspect_snapshot({build=O.build,session='inprocess',session_after='inprocess',before=frame,after=frame})
    return {context=tostring(b)..'|'..planet..'|'..hex(canonical:sub(5))..'|'..hex(source),decoded=decoded, fingerprint=tostring(b)..tostring(session)..selection..cache..canonical..source..dest..ops..missions,
        board=b,selection=selection,operations=ops,missions=missions,planet=planet,seed=u(canonical,0),active=hex(canonical:sub(5)),sc=sc,dc=dc,union=union}
end
-- Runtime host: what the runtimes may use of the adapter. build_identity_probe
-- wraps this file as function(core,config,make_map_screen,offsets,O,sha256)
-- and passes the table to each runtime.
return {M=M,config=config,emit=emit,hex=hex,u=u,read=read,pointer=pointer,page=page,participants=participants,
    snapshot=snapshot,initialize=initialize,map=map_screen,O=O,verify_code=verify_code,
    -- The native handles exist once initialize() has run on the first frame;
    -- it passes them to every function registered here.
    when_initialized=function(bind)binders[#binders+1]=bind end,
    close_log=function()if log then pcall(function()log:close()end);log=nil end end}
