local make=assert(loadfile(arg[1]))()
-- The real map screen reads the map UI fields at their offsets.
local make_map=assert(loadfile((arg[1]:gsub('ui_operation_selection%.lua$','map_screen.lua'))))()
local root=100000;local writes=0;local memory={}
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function u(b)local a,c,d,e=b:byte(1,4);return a+c*256+d*65536+e*16777216 end
memory[root+0x4ef8]=word(268);memory[root+0x4f14]=word(10)
local before=word(4294967295)..word(4294967295)
memory[root+0x4f00]=before;memory[root+0x4f98]=word(4294967295)
local function read(at,n)return assert(memory[at]):sub(1,n)end
local map=make_map({read=read,u=function(b,o)return u(b:sub(o+1))end,game=function()return 0 end,
 pointer=function(at)assert(at==0x3326aa0);return root end})
local a={map=map,word=word,signature=function()end,read=read,
 page=function(at,n)assert(at==root+0x4f00 and n==8)end,
 write=function(at,b)assert(at==root+0x4f00 and #b==8);writes=writes+1;memory[at]=b end}
local s=make(a)
assert(not pcall(function()s:apply(269,10,28)end) and writes==0)
assert(not pcall(function()s:apply(268,9,28)end) and writes==0)
s:apply(268,10,28);assert(memory[root+0x4f00]==word(28)..word(4294967295))
assert(not s:confirmed(28),'Campaign/UI current row alone cannot confirm processed UI state')
memory[root+0x4f98]=word(28);assert(s:confirmed(28))
s:restore();assert(memory[root+0x4f00]==before)
s:apply(268,10,28);memory[root+0x4f00]=word(29)..word(4294967295)
s:restore();assert(u(memory[root+0x4f00])==29,'Do not overwrite later user selection')
s:apply(268,10,28);s:commit();s:restore();assert(u(memory[root+0x4f00])==28)
print('map UI selection: planet/difficulty guards, exact fields, processed-state confirmation and conditional restoration passed')
