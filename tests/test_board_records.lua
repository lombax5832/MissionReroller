-- Usage: luajit test_board_records.lua <src>
-- The board's records (src/board_records.lua) over synthesized bytes: each
-- field of an operation and a mission record, the active record as row 0,
-- and the hovered mission's lookup over a sparse fake memory.
local src=assert(arg[1])
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(src)
local B=H.module(src..'/board_records.lua')
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function zeros(n)return string.rep('\0',n)end

assert(B.OPERATION_SIZE==92 and B.MISSION_SIZE==76 and B.OPERATIONS==110 and B.MISSION_LIMIT==330)
-- One operation record laid out by docs/OPERATION_LAYOUT.md.
local function operation(f)
    local r=word(f.row)..zeros(4)..word(f.explicit_hash)..word(f.seed)..string.char(f.planet%256,math.floor(f.planet/256))
        ..zeros(6)..string.char(f.id)..zeros(3)..word(f.category)..string.char(f.difficulty)..zeros(3)..word(f.faction)
        ..zeros(12)..string.char(f.valid and 1 or 0)..zeros(3)..word(f.template_index)
    for i=1,2 do r=r..word(f.modifiers[i] or 0)end
    r=r..string.char(#f.modifiers)
    return r..zeros(92-#r)
end
local fields={row=7,explicit_hash=0xdeadbeef,seed=4000000000,planet=268,id=21,category=4,difficulty=9,faction=3,
    valid=true,template_index=1234,modifiers={0xa0687641,0x1101e25c}}
local record=operation(fields)
assert(#record==92)
local rows={};for row=0,109 do rows[row+1]=row==7 and record or zeros(92)end
local buffer=table.concat(rows)
assert(#buffer==B.OPERATIONS*B.OPERATION_SIZE)
for _,case in ipairs({{buffer,7},{record,0}})do
    local bytes,row=case[1],case[2]
    assert(B.valid(bytes,row)and B.row(bytes,row)==7 and B.explicit_hash(bytes,row)==0xdeadbeef and B.seed(bytes,row)==4000000000)
    assert(B.planet(bytes,row)==268 and B.operation_id(bytes,row)==21 and B.category(bytes,row)==4 and B.difficulty(bytes,row)==9)
    assert(B.faction(bytes,row)==3 and B.template_index(bytes,row)==1234 and B.modifier_count(bytes,row)==2)
    assert(B.modifier(bytes,row,1)==0xa0687641 and B.modifier(bytes,row,2)==0x1101e25c)
    local list=B.modifiers(bytes,row);assert(#list==2 and list[1]==0xa0687641 and list[2]==0x1101e25c)
    local op=B.operation(bytes,row)
    for key,value in pairs({row=7,id=21,seed=4000000000,difficulty=9,planet=268,category=4,faction=3,explicit_hash=0xdeadbeef,template_index=1234})do
        assert(op[key]==value,key)
    end
    assert(op.modifiers==nil and op.valid==nil,'The base fields only')
end
assert(not B.valid(buffer,6)and not B.valid(buffer,8)and #B.modifiers(buffer,6)==0)
assert(not pcall(B.seed,record,1),'A read past the buffer fails')

-- Mission records: the parent operation, the type and the seed.
local function mission(row,kind,seed)return zeros(40)..word(row)..zeros(4)..word(kind)..word(seed)..zeros(20)end
local missions=mission(3,59,11)..mission(7,72,12)..mission(7,59,13)
assert(#missions==3*B.MISSION_SIZE)
assert(B.mission_operation(missions,1)==7 and B.mission_kind(missions,1)==72 and B.mission_seed(missions,1)==12)
assert(B.has_mission(missions,3,7,59,13)and B.has_mission(missions,3,3,59,11))
assert(not B.has_mission(missions,3,7,59,11)and not B.has_mission(missions,2,7,59,13)and not B.has_mission('',0,7,59,13))

-- The hovered mission over sparse zero-filled memory.
local memory={}
local function poke(address,bytes)for i=1,#bytes do memory[address+i-1]=bytes:byte(i)end end
local function read(address,size)
    local out={};for i=0,size-1 do out[#out+1]=string.char(memory[address+i] or 0)end
    return table.concat(out)
end
local board=0x20000000
local function preview(seed,difficulty,kind,key)
    local d=word(seed)..zeros(4)..string.char(3,difficulty)..zeros(2)..word(key)..zeros(10)..string.char(kind%256,math.floor(kind/256))
    poke(board+O.board.mission_preview,d..zeros(0xe8-#d))
end
poke(board+O.board.selection_row,word(7))
poke(board+O.board.operations+7*92,record)
poke(board+O.board.campaign+268*O.campaign.definition_stride+0x18,word(0xabc))
poke(board+O.board.mission_count,word(3));poke(board+O.board.missions,missions)
preview(13,9,59,0xabc)
local hovered=B.hovered(read,board)
assert(hovered and hovered.row==7 and hovered.planet==268 and hovered.seed==13 and hovered.difficulty==9 and hovered.kind==59)
assert(hovered.category==4 and hovered.operation_id==21 and hovered.preview==read(board+O.board.mission_preview,0xe8))
-- Each check that turns the lookup down.
preview(14,9,59,0xabc);assert(B.hovered(read,board)==nil,'No mission of that seed in the operation')
preview(12,9,72,0xabc);assert(B.hovered(read,board).kind==72)
preview(13,9,59,0xabd);assert(B.hovered(read,board)==nil,'A descriptor of another planet')
preview(13,0,59,0xabc);assert(B.hovered(read,board)==nil,'Difficulty 0')
preview(13,11,59,0xabc);assert(B.hovered(read,board)==nil,'Difficulty 11')
preview(13,9,162,0xabc);assert(B.hovered(read,board)==nil,'A mission type outside the table')
preview(13,9,59,0xabc)
poke(board+O.board.selection_row,word(110));assert(B.hovered(read,board)==nil,'No selected operation')
poke(board+O.board.selection_row,word(6));assert(B.hovered(read,board)==nil,'An invalid operation')
poke(board+O.board.selection_row,word(7))
poke(board+O.board.operations+7*92+16,string.char(0,2));assert(B.hovered(read,board)==nil,'Planet 512')
poke(board+O.board.operations+7*92+16,string.char(268%256,1))
poke(board+O.board.mission_count,word(0));assert(B.hovered(read,board)==nil,'No missions')
poke(board+O.board.mission_count,word(331))
local ok,err=pcall(B.hovered,read,board);assert(not ok and tostring(err):find('Mission count overflow',1,true),tostring(err))
poke(board+O.board.mission_count,word(3));assert(B.hovered(read,board))
print('Board records: operation and mission fields, the active record, modifiers, membership and the hovered mission passed')
