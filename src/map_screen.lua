-- The galactic map screen of build 25480438, read-only: the screen stack, the
-- map UI's viewed planet, difficulty and operation rows, and the BACK hint
-- widget. Every offset of these reads lives here. The adapter creates it as
-- host.map; the runtimes and the adapter's snapshot read the map through it.
--
-- memory: read(address,n), pointer(address) (the pointer stored there),
-- u(bytes,offset), pointer_at(bytes,offset) (a pointer inside bytes, or nil),
-- game() (the game.dll base) and ffi(). The adapter passes functions that
-- look its own locals up on every call, so the native handles set on the
-- first frame reach the map too.
return function(memory)
    local read,pointer,u=memory.read,memory.pointer,memory.u
    local map={}
    local GALACTIC_MAP=15
    -- The screen stack: up to five screen ids, bottom first, depth at +20.
    function map.stack()return read(pointer(memory.game()+0x347ce28)+0x429c,24)end
    -- The screen ids bottom first, or nil and the depth when it is out of range.
    function map.screens(stack)
        stack=stack or map.stack()
        local depth=u(stack,20)
        if depth<1 or depth>5 then return nil,depth end
        local list={};for i=1,depth do list[i]=u(stack,(i-1)*4)end
        return list,depth
    end
    -- Whether the galactic map is the top screen.
    function map.on_top(stack)
        stack=stack or map.stack()
        local depth=u(stack,20)
        return depth>=1 and depth<=5 and u(stack,(depth-1)*4)==GALACTIC_MAP
    end
    -- The map UI object.
    function map.ui()return pointer(memory.game()+0x3326aa0)end
    -- The planet and the difficulty the map UI shows.
    function map.viewed(ui)
        ui=ui or map.ui()
        local planet=u(read(ui+0x4ef8,4),0)
        return planet,u(read(ui+0x4f14,4),0)
    end
    -- The map UI's two operation-row words: the selected row, then the row
    -- under the cursor (0xffffffff for none).
    function map.rows_address(ui)return (ui or map.ui())+0x4f00 end
    -- The row the map UI has processed as selected.
    function map.processed_row(ui)return u(read((ui or map.ui())+0x4f98,4),0)end
    -- The operation row under the cursor, or else the selected one; nil
    -- when neither is an operation row.
    function map.pointed_row()
        local rows=read(map.rows_address(),8)
        local row=u(rows,4);if row>=110 then row=u(rows,0)end
        if row<110 then return row end
    end
    -- The key hint sits beside the war table's own BACK hint, a widget of
    -- the map screen object: the 136x32 design-unit container at local
    -- (56,16) that holds the key cap and the BACK label, found by
    -- scripts/survey_map_widgets.py on 2026-09-29. nil draws no hint.
    map.HINT_WIDGET=1696
    -- The BACK hint's solved rectangle, or nil when the galactic map is not
    -- the top screen or the hint is hidden. The map screen object is the one
    -- inline subscriber of a UI manager event registry; a widget record keeps
    -- its flags at +0 (0x10 visible), unscaled size at +36, inherited opacity
    -- at +84, scale at +100/+140 and solved bottom-left position at +148/+156.
    local single
    function map.back_hint()
        if not map.HINT_WIDGET then return nil end
        if not map.on_top()then return nil end
        local entry=read(pointer(memory.game()+0x3326e68)+25224,24)
        if u(entry,0)~=1 or u(entry,16)~=226 then return nil end
        local owner=memory.pointer_at(entry,8)
        if not owner then return nil end
        local w=read(owner+map.HINT_WIDGET,164)
        local ffi=memory.ffi()
        single=single or ffi.new('float[1]')
        local function f(o)ffi.copy(single,w:sub(o+1,o+4),4);return tonumber(single[0])end
        if math.floor(u(w,0)/16)%2==0 then return nil end
        local opacity=f(84)
        if not (opacity>=0.995 and opacity<=1.01)then return nil end
        local sx,sy=f(100),f(140)
        local box={x=f(148),y=f(156),w=f(36)*sx,h=f(40)*sy,scale=sx}
        for _,v in pairs(box)do if v~=v or v<0 or v>32768 then return nil end end
        if sx<0.3 or sx>4 or math.abs(sx-sy)>0.01 or box.w<8 or box.h<8 then return nil end
        return box
    end
    return map
end
