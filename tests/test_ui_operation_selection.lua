local make=assert(loadfile(arg[1]))()
-- The real map screen reads the map UI fields at their offsets.
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local make_map=H.module((arg[1]:gsub('ui_operation_selection%.lua$','map_screen.lua')))
local O=H.offsets(arg[1]:match('^(.*)[/\\]'))
local root=100000;local writes=0;local memory={}
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function u(b)local a,c,d,e=b:byte(1,4);return a+c*256+d*65536+e*16777216 end
memory[root+O.map_ui.planet]=word(268);memory[root+O.map_ui.difficulty]=word(10)
local before=word(4294967295)..word(4294967295)
memory[root+O.map_ui.rows]=before;memory[root+O.map_ui.processed_row]=word(4294967295)
local function read(at,n)return assert(memory[at]):sub(1,n)end
local map=make_map({read=read,u=function(b,o)return u(b:sub(o+1))end,game=function()return 0 end,
 pointer=function(at)assert(at==O.rva.map_ui);return root end})
local a={map=map,word=word,signature=function()end,read=read,
 page=function(at,n)assert(at==root+O.map_ui.rows and n==8)end,
 write=function(at,b)assert(at==root+O.map_ui.rows and #b==8);writes=writes+1;memory[at]=b end}
local s=make(a)
assert(not pcall(function()s:apply(269,10,28)end) and writes==0)
assert(not pcall(function()s:apply(268,9,28)end) and writes==0)
s:apply(268,10,28);assert(memory[root+O.map_ui.rows]==word(28)..word(4294967295))
assert(not s:confirmed(28),'Campaign/UI current row alone cannot confirm processed UI state')
memory[root+O.map_ui.processed_row]=word(28);assert(s:confirmed(28))
s:restore();assert(memory[root+O.map_ui.rows]==before)
s:apply(268,10,28);memory[root+O.map_ui.rows]=word(29)..word(4294967295)
s:restore();assert(u(memory[root+O.map_ui.rows])==29,'Do not overwrite later user selection')
s:apply(268,10,28);s:commit();s:restore();assert(u(memory[root+O.map_ui.rows])==28)
print('map UI selection: planet/difficulty guards, exact fields, processed-state confirmation and conditional restoration passed')
