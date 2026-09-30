-- Read-only captures from session 22836-967517250, selected row 29 then
-- user-confirmed planet overview. Replay the actual UI selection adapter.
local make=assert(loadfile(arg[1]))()
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local make_map=H.module((arg[1]:gsub('ui_operation_selection%.lua$','map_screen.lua')))
local function raw(h)return(h:gsub('..',function(x)return string.char(tonumber(x,16))end))end
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function u(s)local a,b,c,d=s:byte(1,4);return a+b*256+c*65536+d*16777216 end
for _,capture in ipairs({
    {'selected','0c010000ffffffff1d000000ffffffffffffffffffffffff000000000a000000',29},
    {'overview','0c010000ffffffffffffffffffffffffffffffffffffffff000000000a000000',4294967295},
})do
    local memory={};local ui=100000;local writes=0
    local bytes=raw(capture[2])
    for i=1,#bytes do memory[ui+0x4ef8+i-1]=bytes:sub(i,i)end
    local function put(a,s)for i=1,#s do memory[a+i-1]=s:sub(i,i)end end
    local function read(a,n)local out={};for i=0,n-1 do out[#out+1]=assert(memory[a+i])end;return table.concat(out)end
    put(ui+0x4f98,word(capture[3]))
    local before=read(ui+0x4f00,8)
    local map=make_map({read=read,u=function(b,o)return u(b:sub(o+1))end,game=function()return 0 end,
        pointer=function(a)assert(a==0x3326aa0);return ui end})
    local adapter={map=map,signature=function()end,read=read,word=word,
        page=function(a,n)assert(a==ui+0x4f00 and n==8)end,
        write=function(a,s)assert(a==ui+0x4f00 and #s==8);writes=writes+1;put(a,s)end}
    local selection=make(adapter)
    selection:apply(268,10,28)
    assert(writes==1 and read(ui+0x4f00,8)==word(28)..word(4294967295),capture[1])
    assert(not selection:confirmed(28))
    put(ui+0x4f98,word(28));assert(selection:confirmed(28))
    selection:restore();assert(read(ui+0x4f00,8)==before)
end
print('Captured selected-operation and planet-overview states both select, confirm and restore')
