-- The Board's operation and mission records (docs/OPERATION_LAYOUT.md): their
-- sizes and the fields the mod reads, in one place. The arrays sit at
-- O.board.operations and O.board.missions. The field offsets are below 0x100,
-- so by docs/UPDATING.md they stay here inline, written as row*92+<offset>:
-- that is the form scripts/check_offsets.py looks for in src/ when an update
-- changes the code that reads these records.
--
-- bytes is an operation buffer and row a record in it; a lone record, such as
-- O.board.active_snapshot, is row 0. The field readers allocate nothing, for
-- the loops that read every row.
local O=...
local B={OPERATION_SIZE=92,MISSION_SIZE=76,
    -- Operation records on the board, and the mission array's allocation bound.
    OPERATIONS=110,MISSION_LIMIT=330}
local function u32(b,o)
    local a,c,d,e=b:byte(o+1,o+4);assert(e,'short read')
    return a+c*256+d*65536+e*16777216
end
-- The row index the game stored in the record; for a live row it equals row.
function B.row(bytes,row)return u32(bytes,row*92)end
function B.explicit_hash(bytes,row)return u32(bytes,row*92+8)end
-- The generation seed: the mission generator's RNG starting state.
function B.seed(bytes,row)return u32(bytes,row*92+12)end
function B.planet(bytes,row)local at=row*92+16;return bytes:byte(at+1)+bytes:byte(at+2)*256 end
-- The operation ID, distinct from the row.
function B.operation_id(bytes,row)return bytes:byte(row*92+24+1)end
function B.category(bytes,row)return u32(bytes,row*92+28)end
function B.difficulty(bytes,row)return bytes:byte(row*92+32+1)end
function B.faction(bytes,row)return u32(bytes,row*92+36)end
function B.valid(bytes,row)return bytes:byte(row*92+52+1)~=0 end
function B.template_index(bytes,row)return u32(bytes,row*92+56)end
function B.modifier_count(bytes,row)return bytes:byte(row*92+68+1)end
-- Modifier i, from 1 to modifier_count.
function B.modifier(bytes,row,i)return u32(bytes,row*92+56+i*4)end
-- The base fields of an operation record, as one table.
function B.operation(bytes,row)
    return {row=B.row(bytes,row),id=B.operation_id(bytes,row),seed=B.seed(bytes,row),
        difficulty=B.difficulty(bytes,row),planet=B.planet(bytes,row),category=B.category(bytes,row),
        faction=B.faction(bytes,row),explicit_hash=B.explicit_hash(bytes,row),template_index=B.template_index(bytes,row)}
end
-- Its modifiers as a list.
function B.modifiers(bytes,row)
    local list={}
    for i=1,B.modifier_count(bytes,row)do list[i]=B.modifier(bytes,row,i)end
    return list
end

-- Mission records, index i of a mission buffer.
function B.mission_operation(missions,i)return u32(missions,i*76+40)end
-- The mission type: an index into the mission settings.
function B.mission_kind(missions,i)return u32(missions,i*76+48)end
function B.mission_seed(missions,i)return u32(missions,i*76+52)end
-- Whether one of count missions belongs to operation row with this type and seed.
function B.has_mission(missions,count,row,kind,seed)
    for i=0,count-1 do
        if B.mission_operation(missions,i)==row and B.mission_kind(missions,i)==kind and B.mission_seed(missions,i)==seed then return true end
    end
    return false
end

-- The mission the map previews, the mission under the cursor of the selected
-- operation, as {row,planet,seed,difficulty,kind,category,operation_id,
-- preview}, preview being the descriptor's bytes. nil unless the board's
-- selected operation is valid, the descriptor is one this mod decodes and of
-- that operation's planet, and the operation holds a mission of its type and
-- seed. b is the board's address.
function B.hovered(read,b)
    local row=u32(read(b+O.board.selection_row,4),0)
    if row>=B.OPERATIONS then return nil end
    local op=read(b+O.board.operations+row*92,92)
    if not B.valid(op,0)then return nil end
    local preview=read(b+O.board.mission_preview,0xe8)
    local seed,difficulty,kind=u32(preview,0),preview:byte(10),preview:byte(27)+preview:byte(28)*256
    if difficulty<1 or difficulty>10 or kind>=162 then return nil end
    local planet=B.planet(op,0)
    if planet>=512 or u32(read(b+O.board.campaign+planet*O.campaign.definition_stride+0x18,4),0)~=u32(preview,12)then return nil end
    local count=u32(read(b+O.board.mission_count,4),0);assert(count<=B.MISSION_LIMIT,'Mission count overflow')
    local missions=count>0 and read(b+O.board.missions,count*76) or ''
    if not B.has_mission(missions,count,row,kind,seed)then return nil end
    return {row=row,planet=planet,seed=seed,difficulty=difficulty,kind=kind,
        category=B.category(op,0),operation_id=B.operation_id(op,0),preview=preview}
end
return B
