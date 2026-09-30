-- Addons share one LuaJIT VM, so C declarations are global and the first one
-- of a function wins. Mod Bindings Menu v2.0 declares VirtualQuery with its
-- own struct pointer before Mission Reroller initialises; in game that
-- stopped the mod with "cannot convert 'struct [1]' to 'struct *'". This
-- declares it the same way first, then runs the entry's real page check on
-- real private memory.
local function up(fn,name,value,set)
    for i=1,200 do local k,v=debug.getupvalue(fn,i);if k==name then if set then debug.setupvalue(fn,i,value)end;return v end;if not k then break end end
    error('Missing upvalue '..name)
end
local ffi=require('ffi')
-- Verbatim from ModBindingsMenu src/mod_bindings_menu.lua.
ffi.cdef[[
typedef unsigned short MBM_u16;
typedef unsigned int MBM_u32;
typedef struct {
    void *BaseAddress; void *AllocationBase; MBM_u32 AllocationProtect;
    MBM_u16 PartitionId; size_t RegionSize; MBM_u32 State; MBM_u32 Protect; MBM_u32 Type;
} MBM_MEMORY_BASIC_INFORMATION;
size_t VirtualQuery(const void *address, MBM_MEMORY_BASIC_INFORMATION *info, size_t length);
]]
CowboyBingusModLoader={api=1,version=18,open_log=function()return {write=function()end,flush=function()end,close=function()end}end}
update=function()end;shutdown=function()end
dofile(arg[1])
local dialog=up(up(update,'tick'),'dialog_tick')
local page=up(up(up(dialog,'init'),'check_window'),'page')
-- The adapter's own declarations, as its initialize() makes them.
ffi.cdef[[
    typedef struct {
        void *BaseAddress; void *AllocationBase; uint32_t AllocationProtect;
        uint16_t PartitionId; uint16_t padding; size_t RegionSize;
        uint32_t State; uint32_t Protect; uint32_t Type; uint32_t padding2;
    } MRE_MEMORY_BASIC_INFORMATION;
    size_t VirtualQuery(const void *, void *, size_t);
]]
up(page,'ffi',ffi,true);up(page,'kernel',ffi.load('kernel32'),true)
-- A large FFI allocation is private read/write memory of this process.
local buffer=ffi.new('uint8_t[?]',1048576)
page(buffer+4096,16,0x20000)
assert(not pcall(page,buffer+4096,16,0x1000000),'the page type is still checked')
print('test_ffi_conflicts: page check works after Mod Bindings Menu declares VirtualQuery')
