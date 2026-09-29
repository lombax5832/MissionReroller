-- Exercise the real update/snapshot path using bounded synthetic process reads.
local ffi=require('ffi')
local entry=assert(arg[1])
local f=assert(io.open(entry,'rb'));local source=f:read('*a');f:close()
local logs={}
CowboyBingusModLoader={api=1,version=16,open_log=function()
    return {write=function(_,s)logs[#logs+1]=s end,flush=function()end}
end}
update=function()return 'original',nil end
dofile(entry)
local function up(fn,name,value,set)
    for i=1,100 do
        local key,v=debug.getupvalue(fn,i)
        if not key then break end
        if key==name then if set then debug.setupvalue(fn,i,value) end;return v end
    end
    error('missing upvalue '..name)
end
local tick=up(update,'tick')
local initialize=up(tick,'initialize')
local snapshot=up(tick,'snapshot')
local game=ffi.cast('uint8_t *',0x10000000)
local board,session,backend,root,screen=0x20000000,0x30000000,0x40000000,0x50000000,0x60000000
local memory={}
local function put(a,s)memory[a]=s end
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function ptr(n)return word(n)..word(0)end
put(0x1347cee8,ptr(board));put(0x1347cef0,ptr(session));put(0x1347cee0,ptr(backend))
put(0x13326340,ptr(root));put(0x1347ce28,ptr(screen))
put(screen+0x429c,word(15)..string.rep('\0',16)..word(1))
put(board+0x17a298,word(268)..string.rep('\0',16))
put(board+0xf9a08,word(268)..word(0));put(board+0xffc0c,word(268))
put(backend+0x702fc,word(14));put(backend+0x702f8,word(1))
put(session+0x167e6,'\0');put(root+0x108d,'\0');put(root+0x1099,'\0');put(root+0x8e8,string.rep('\0',8))
put(session+0x162d8,word(1));put(board+0x1f80d0,word(0))
put(session+0x162e0,ptr(123));put(board+0x1f8080,'')
put(board+0x78e84,word(321)..string.rep('\0',92));put(board+0x17a2bc,word(321))
put(board+0xffc08,word(1));put(board+0xf7280,string.rep('\0',110*92))
put(board+0xf9a10,string.rep('\0',76))
put(backend+0x31c48,word(0))
local signature=assert(source:match("local expected_code='(%x+)'"))
put(0x112d5670,(signature:gsub("..",function(h)return string.char(tonumber(h,16))end)))
local now=0
local api={time=function()now=now+0.25;return now end,read=function(a,n)
    local b=memory[tonumber(ffi.cast('uintptr_t',a))]
    assert(b and #b>=n,'unexpected synthetic read');return b:sub(1,n)
end}
-- Use the entry's real pointer decoder, including its optional offset argument.
local body=assert(source:match('(    function api.pointer.-)\n    function api.module_hash'))
assert(loadstring('local api,ffi=...\n'..body..'\nreturn api.pointer'))(api,ffi)
ffi.cdef[[typedef struct {void *BaseAddress;void *AllocationBase;uint32_t AllocationProtect;
uint16_t PartitionId;uint16_t padding;size_t RegionSize;uint32_t State;uint32_t Protect;
uint32_t Type;uint32_t padding2;} MRRP_MEMORY_BASIC_INFORMATION;]]
local kernel={GetCurrentThreadId=function()return 42 end,VirtualQuery=function(a,m)
    m[0].BaseAddress=a;m[0].RegionSize=4096;m[0].State=0x1000;m[0].Protect=4
    m[0].Type=(tonumber(ffi.cast('uintptr_t',a))==0x13483c38) and 0x1000000 or 0x20000
    return ffi.sizeof(m[0])
end}
up(tick,'initialized',true,true)
up(tick,'api',api,true);up(tick,'kernel',kernel,true)
up(snapshot,'game',game,true)
up(initialize,'ffi',ffi,true)
local scenario=arg[2] or 'success'
local calls=0
local key_down,foreground=true,true
kernel.GetCurrentProcessId=function()return 7 end
up(initialize,'user32',{
    GetForegroundWindow=function()return nil end,
    GetWindowThreadProcessId=function(_,pid)pid[0]=foreground and 7 or 8 end,
    GetAsyncKeyState=function()return key_down and -32768 or 0 end,
},true)
local real_trigger=up(tick,'trigger')
assert(not real_trigger(),'held key must not arm')
key_down=false;assert(not real_trigger())
key_down=true;assert(real_trigger(),'fresh chord should trigger')
assert(not real_trigger(),'held chord must not repeat')
foreground=false;key_down=false;assert(not real_trigger())
foreground=true;key_down=true;assert(not real_trigger(),'focus change must disarm')
up(tick,'trigger',function()return true end,true)
up(tick,'invoke',function(b)
    assert(tonumber(ffi.cast('uintptr_t',b))==board)
    calls=calls+1
    put(board+0x78e84,word(999)..string.rep('\0',92))
    if scenario=='active_change' then put(board+0x78e88,string.rep('x',92)) end
    if scenario~='timeout' then
        put(board+0x17a2bc,word(999))
        put(board+0xf7280,string.rep('x',110*92))
    end
end,true)
put(board+0x78e88,string.rep('\0',92))
if scenario=='queue' or scenario=='queue_clears' then put(backend+0x31c48,word(1)) end
if scenario=='page' then kernel.VirtualQuery=function()return 0 end end
for i=1,220 do
    if scenario=='queue_clears' and i==20 then
        assert(calls==0,'called while queue busy')
        put(backend+0x31c48,word(0))
    end
    assert(update()=='original')
    if scenario=='queue_clears' and i<59 then assert(calls==0,'stable window bypassed') end
end
local status=MissionRerollerProbe.status
if scenario=='success' or scenario=='queue_clears' then assert(status:find('PROBE_COMPLETE',1,true),table.concat(logs))
elseif scenario=='queue' then assert(status=='waiting_for_update' and calls==0,table.concat(logs))
elseif scenario=='timeout' then assert(status:find('PROBE_TIMEOUT',1,true),table.concat(logs))
else assert(status:find('PROBE_STOP',1,true),table.concat(logs)) end
assert(calls==((scenario=='queue' or scenario=='page') and 0 or 1),'unexpected call count')
print('one-shot '..scenario..': passed; calls='..calls)
