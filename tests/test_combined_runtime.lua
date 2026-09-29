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
uint32_t Type;uint32_t padding2;} MRE_MEMORY_BASIC_INFORMATION;]]
local kernel={GetCurrentThreadId=function()return 42 end,VirtualQuery=function(a,m)
    m[0].BaseAddress=a;m[0].RegionSize=4096;m[0].State=0x1000;m[0].Protect=4
    m[0].Type=(tonumber(ffi.cast('uintptr_t',a))==0x13483c38) and 0x1000000 or 0x20000
    return ffi.sizeof(m[0])
end}
up(tick,'initialized',true,true)
up(tick,'api',api,true);up(tick,'kernel',kernel,true)
up(snapshot,'game',game,true)
up(initialize,'ffi',ffi,true)

-- Supply structurally valid operation and mission records to the real core decoder.
local function patch(bytes,at,value)return bytes:sub(1,at)..value..bytes:sub(at+#value+1)end
local op=string.rep('\0',110*92)
op=patch(op,16,word(268));op=patch(op,32,word(10));op=patch(op,52,string.char(1))
op=patch(op,84,string.char(3,0,1,2,3))
local missions=string.rep('\0',3*76)
for i,id in ipairs({59,81,65}) do
 local at=(i-1)*76
 missions=patch(missions,at+48,word(id));missions=patch(missions,at+60,word(10))
 missions=patch(missions,at+68,word(i-1))
end
put(board+0xf7280,op);put(board+0xffc08,word(3));put(board+0xf9a10,missions)
kernel.GetCurrentProcessId=function()return 7 end
up(initialize,'user32',{GetForegroundWindow=function()return nil end,
 GetWindowThreadProcessId=function(_,pid)pid[0]=7 end,GetAsyncKeyState=function()return 0 end},true)
up(tick,'panel',{clear=function()end,show=function()return true end},true)
stingray={Script={temp_byte_count=function()return 0 end,set_temp_byte_count=function()end}}

stingray.Gui={resolution=function()return 1920,1080 end}
ffi.cdef[[typedef struct {int32_t x,y;} MRC_POINT;
typedef struct {int32_t left,top,right,bottom;} MRC_RECT;]]
local user=up(initialize,'user32')
user.GetCursorPos=function(p)p[0].x=0;p[0].y=0;return 1 end
user.ScreenToClient=function()return 1 end
user.GetClientRect=function(_,r)r[0].right=1920;r[0].bottom=1080;return 1 end
local calls,selections=0,0
put(board+0x78e88,string.rep('\0',92))
up(tick,'invoke',function()calls=calls+1 end,true)
up(tick,'select_operation',function(s,op)
 selections=selections+1;assert(op.row==0)
 put(board+0x17a298,word(268)..word(0)..word(0)..word(4294967295)..word(0))
 put(board+0x17a2a4,word(4294967295))
end,true)
for i=1,45 do update() end
local s=up(tick,'latest');assert(s,table.concat(logs))
local action='start'
local router={opened=true,closing=false,step=function(self)
 if self.closing then self.closing=false end
 local a=action;action=nil;return a
end,close=function(self)self.opened=false;self.closing=true end}
up(tick,'router',router,true)
local releases=0
up(tick,'gate',{release=function()releases=releases+1;return true end},true)
up(tick,'selected',{[1]=true,[2]=true},true)
up(tick,'face',function()return {}end,true)
-- A previously used session must still enable Start and accept a match.
up(tick,'search').calls=6
for i=1,15 do update() end
local search=up(tick,'search')
assert(search.match and calls==0 and selections==1,table.concat(logs))
assert(search.calls==6)
assert(search.status=='Matched operation selected',table.concat(logs))
assert(up(tick,'router')==nil and releases==1,table.concat(logs))
print('combined runtime: mouse start, initial AND match, one selection, confirmation, modal release')
