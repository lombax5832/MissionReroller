-- Usage: luajit test_map_screen.lua <src>
-- The host's map screen (src/map_screen.lua) against fake game memory, and
-- the guarded write (src/guarded_write.lua) against a fake page check and
-- fake Win32 entry points, then once for real into this process's memory.
local src=assert(arg[1])
local ffi=require('ffi')
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(src)
local make_map=H.module(src..'/map_screen.lua')
local make_write=assert(loadfile(src..'/guarded_write.lua'))()
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function u(b,o)local a,c,d,e=b:byte(o+1,o+4);assert(e,'short read');return a+c*256+d*65536+e*16777216 end
local function float(v)local f=ffi.new('float[1]',v);return ffi.string(f,4)end

-- Fake game memory: exact reads only, pointers as plain numbers.
local game,stack_owner,ui,registry,widgets=0x10000000,0x20000000,0x30000000,0x40000000,0x50000000
local memory,pointers,reads={},{},{}
local function read(a,n)
    reads[#reads+1]=a..':'..n
    local bytes=assert(memory[a],string.format('Unexpected read of %d at %x',n,a))
    assert(#bytes==n,string.format('Read of %d at %x, expected %d',n,a,#bytes));return bytes
end
local function pointer(a)return assert(pointers[a],string.format('Missing pointer at %x',a))end
local map=make_map({read=read,pointer=pointer,u=u,game=function()return game end,ffi=function()return ffi end,
    pointer_at=function(bytes,o)local v=u(bytes,o);return v>=0x10000 and v or nil end})
pointers[game+O.rva.screen_owner]=stack_owner;pointers[game+O.rva.map_ui]=ui;pointers[game+O.rva.ui_manager]=registry
local function stack(...)
    local ids={...};local bytes=''
    for i=1,5 do bytes=bytes..word(ids[i] or 0)end
    memory[stack_owner+O.screen_owner.stack]=bytes..word(#ids)
end

-- The screen stack, bottom first; the galactic map (15) only counts on top.
stack(15);assert(map.on_top() and table.concat(assert(map.screens()),',')=='15')
stack(15,26);assert(not map.on_top() and table.concat(assert(map.screens()),',')=='15,26')
stack(3,15);assert(map.on_top())
memory[stack_owner+O.screen_owner.stack]=string.rep('\0',20)..word(0)
local list,depth=map.screens();assert(list==nil and depth==0 and not map.on_top())
memory[stack_owner+O.screen_owner.stack]=string.rep('\0',20)..word(6)
list,depth=map.screens();assert(list==nil and depth==6 and not map.on_top())
-- A stack read once is decided without a second read.
stack(15);reads={};local raw=map.stack();assert(map.on_top(raw) and map.screens(raw) and #reads==1)
assert(reads[1]==(stack_owner+O.screen_owner.stack)..':24')

-- The map UI: the viewed planet and difficulty, and the operation rows.
memory[ui+O.map_ui.planet]=word(268);memory[ui+O.map_ui.difficulty]=word(7)
local planet,difficulty=map.viewed();assert(planet==268 and difficulty==7)
assert(map.ui()==ui and map.rows_address()==ui+O.map_ui.rows and map.rows_address(ui)==ui+O.map_ui.rows)
memory[ui+O.map_ui.processed_row]=word(29);assert(map.processed_row()==29 and map.processed_row(ui)==29)
-- The row under the cursor wins; else the selected row; else none.
memory[ui+O.map_ui.rows]=word(29)..word(41);assert(map.pointed_row()==41)
memory[ui+O.map_ui.rows]=word(29)..word(4294967295);assert(map.pointed_row()==29)
memory[ui+O.map_ui.rows]=word(4294967295)..word(4294967295);assert(map.pointed_row()==nil)
memory[ui+O.map_ui.rows]=word(4294967295)..word(110);assert(map.pointed_row()==nil)

-- The BACK hint: the map screen's widget at HINT_WIDGET, visible and opaque.
assert(map.HINT_WIDGET==O.map_screen.hint_widget)
local function widget(flags,opacity,sx,sy,x,y,w,h)
    local b=string.rep('\0',164)
    local function at(o,v)b=b:sub(1,o)..v..b:sub(o+#v+1)end
    at(0,word(flags));at(36,float(w));at(40,float(h));at(84,float(opacity));at(100,float(sx));at(140,float(sy))
    at(148,float(x));at(156,float(y))
    memory[widgets+O.map_screen.hint_widget]=b
end
memory[registry+O.ui_manager.registry]=word(1)..word(0)..word(widgets)..word(0)..word(226)..word(0)
stack(15);widget(0x10,1,1.5,1.5,48,32,80,24)
local box=assert(map.back_hint())
assert(box.x==48 and box.y==32 and box.w==120 and box.h==36 and box.scale==1.5)
widget(0,1,1.5,1.5,48,32,80,24);assert(map.back_hint()==nil,'Hidden')
widget(0x10,0.5,1.5,1.5,48,32,80,24);assert(map.back_hint()==nil,'Fading')
widget(0x10,1,1.5,1.2,48,32,80,24);assert(map.back_hint()==nil,'Uneven scale')
widget(0x10,1,1,1,48,32,4,4);assert(map.back_hint()==nil,'Too small')
widget(0x10,1,1.5,1.5,48,32,80,24)
stack(15,26);assert(map.back_hint()==nil,'Not on top');stack(15)
memory[registry+O.ui_manager.registry]=word(1)..word(0)..word(widgets)..word(0)..word(227)..word(0)
assert(map.back_hint()==nil,'Another subscriber')
memory[registry+O.ui_manager.registry]=word(1)..word(0)..word(0)..word(0)..word(226)..word(0)
assert(map.back_hint()==nil,'No owner')
map.HINT_WIDGET=nil;assert(map.back_hint()==nil,'Disabled');map.HINT_WIDGET=O.map_screen.hint_widget
print('map screen: stack, top screen, viewed planet and difficulty, operation rows and BACK hint passed')

-- The guarded write against fakes: the page check, the Win32 write through
-- a pointer resolved by address, and the read back.
local cells={}
local pages,natives,next_result={},0,nil
local binders={}
local function address(a)return tonumber(ffi.cast('uintptr_t',a))end
local host={read=function(a,n)a=address(a);return cells[a] and cells[a]:sub(1,n) or string.rep('\0',n)end,
    page=function(a,n,kind)
        a=address(a);pages[#pages+1]=a..':'..n..':'..kind
        -- As VirtualQuery would answer: only private read/write pages pass.
        assert(a<0x9000,'unexpected target page')
    end,
    when_initialized=function(bind)binders[#binders+1]=bind end}
local write=make_write(host)
assert(#binders==1,'The write waits for the native handles')
local signature='int (*)(void *, void *, const void *, size_t, void *)'
local resolved={}
local callback=ffi.cast(signature,function(process,address,bytes,n,count)
    natives=natives+1
    local a=tonumber(ffi.cast('uintptr_t',address));n=tonumber(n)
    local result=next_result or 'ok';next_result=nil
    ffi.cast('size_t *',count)[0]=result=='short' and n-1 or n
    if result=='fail' then return 0 end
    if result~='lost' then cells[a]=ffi.string(bytes,n)end
    return 1
end)
local kernel={GetCurrentProcess=function()return ffi.cast('void *',-1)end,
    GetModuleHandleA=function(name)resolved[#resolved+1]=name;return ffi.cast('void *',0x1234)end,
    GetProcAddress=function(module,name)resolved[#resolved+1]=name;return ffi.cast('void *',callback)end}
binders[1]({ffi=ffi,kernel=kernel})
local at=ffi.cast('uint8_t *',0x4000)
write(at,word(77),'Seed')
assert(cells[0x4000]==word(77) and natives==1 and pages[1]==tostring(0x4000)..':4:'..0x20000)
assert(resolved[1]=='kernel32.dll' and resolved[2]=='WriteProcessMemory')
write(at,word(78),'Seed');assert(#resolved==2,'Resolved once')
local function fails(expected,...)
    local ok,err=pcall(write,...)
    assert(not ok and tostring(err):find(expected,1,true),tostring(err))
end
next_result='fail';fails('Seed write failed',at,word(79),'Seed');assert(cells[0x4000]==word(78))
next_result='short';fails('Binding map write failed',at,word(79),'Binding map')
next_result='lost';fails('Seed write did not persist',at,word(80),'Seed')
-- Without verification a write that did not persist passes, as the map UI's does.
next_result='lost';write(at,word(81),'Map UI',false);assert(cells[0x4000]==word(79))
next_result='fail';fails('Map UI write failed',at,word(81),'Map UI',false)
-- A target outside private read/write memory is never written.
local before=natives
fails('unexpected target page',ffi.cast('uint8_t *',0x9000),word(1),'Seed');assert(natives==before)
print('guarded write: page check, resolved write, count and read-back checks passed')

-- Once for real: WriteProcessMemory on this process into private memory,
-- after another addon declared the function with its own struct pointer.
ffi.cdef[[
    typedef struct { size_t value; } OTHER_ADDON_SIZE;
    int WriteProcessMemory(void *, void *, const void *, size_t, OTHER_ADDON_SIZE *);
    void *GetCurrentProcess(void);
    void *GetModuleHandleA(const char *);
]]
local buffer=ffi.new('uint8_t[?]',64)
local real={read=function(a,n)return ffi.string(a,n)end,page=function(a,n,kind)assert(kind==0x20000)end,
    when_initialized=function(bind)bind({ffi=ffi,kernel=ffi.load('kernel32')})end}
make_write(real)(buffer+8,'abcd','Seed')
assert(ffi.string(buffer+8,4)=='abcd' and buffer[7]==0 and buffer[12]==0)
print('guarded write: a real write into private memory passed despite a conflicting declaration')
