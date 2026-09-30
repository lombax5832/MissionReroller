-- Key hint for the reroll dialog, drawn beside the war table's own BACK hint
-- in the game's font: a key cap with the shortcut, then a label. The anchor
-- is that hint's solved rectangle {x,y,w,h,scale} with the origin at the
-- bottom-left corner, as the engine's Gui reports it. Everything is sized
-- from the anchor, so the hint follows the game's own UI scale. The cap
-- reads the key given to show, or the default F7 without one.
local H={}
H.KEYS,H.LABEL='F7','REROLL OPERATIONS'
-- In the anchor's scale, from the game's own BACK hint as surveyed: its cap
-- is 57.9 units wide around 41.9 units of text (8 of padding a side), the
-- label starts 15 units after the cap, and both texts are 15.75 units tall
-- in a 32-unit container. GAP is the space we leave after the game's hint.
local GAP,PAD,SPACE,BORDER,TEXT=32,8,15,2,0.5
function H.layout(anchor,width,height,measure,keys)
    local s,h=anchor.scale,anchor.h
    local size=h*TEXT
    measure=measure or function(text,size)return #text*size*0.6 end
    local cap={x=anchor.x+anchor.w+GAP*s,y=anchor.y,w=measure(keys or H.KEYS,size)+2*PAD*s,h=h}
    local label={x=cap.x+cap.w+SPACE*s,cy=anchor.y+h/2,w=measure(H.LABEL,size)}
    local b={x=cap.x,y=anchor.y,w=label.x+label.w-cap.x,h=h,s=s,size=size,border=math.max(1,BORDER*s),
        cap=cap,keys={x=cap.x+PAD*s,cy=anchor.y+h/2},label=label}
    b.fits=b.x>=0 and b.y>=0 and b.x+b.w<=width and b.y+b.h<=height
    return b
end
function H.new(e)
    local self={}
    local gui,world,identity,no_metrics
    function self:clear()
        if gui then for _,w in ipairs(e.Application.worlds())do
            if w==world then e.World.destroy_gui(world,gui);break end
        end end
        gui,world,identity=nil,nil,nil
    end
    -- Draws once per distinct anchor, face and screen; nothing is updated
    -- afterwards. Returns false, drawing nothing, when the hint would not fit.
    function self:show(anchor,face,keys)
        keys=keys or H.KEYS
        local width,height=e.Gui.resolution()
        local target
        for _,w in ipairs(e.Application.worlds())do if w~=e.Application.main_world()then target=w;break end end
        assert(target,'UI world unavailable')
        local key=table.concat({width,height,face.font,face.material,face.atlas,keys,
            string.format('%.1f|%.1f|%.1f|%.1f|%.3f',anchor.x,anchor.y,anchor.w,anchor.h,anchor.scale)},'|')
        if gui and target==world and key==identity then return true end
        self:clear()
        local font,mat=e.IdString64.from_hex(face.font),e.IdString64.from_hex(face.material)
        local function color(r,g,b,a)return e.Color(a or 255,r,g,b)end
        world=target;gui=assert(e.World.create_screen_gui(world,'scale',1,1));identity=key
        local m=assert(e.Gui.material(gui,mat))
        local function slot(v)return e.IdString64.from_hex(v..'00000000')end
        for _,v in ipairs({'8035c266','5e8455fe','309e7783','82b803a8'})do e.Material.set_scalar(m,slot(v),0)end
        e.Material.set_vector2(m,slot('e13777ce'),e.Vector2(1,-1))
        e.Material.set_vector4(m,slot('7701209e'),color(0,0,0,0))
        e.Material.set_texture(m,slot('88bac99b'),e.IdString64.from_hex(face.atlas))
        local function measure(value,size)
            local guess=#value*size*0.6
            if no_metrics then return guess end
            local ok,lo,hi=pcall(function()
                local lo,hi,caret=e.Gui.text_extents(gui,value,font,size)
                local x=e.Vector2.x
                return math.min(0,x(lo)),math.max(x(hi),caret and x(caret) or 0)
            end)
            if ok and type(lo)=='number' and type(hi)=='number' and hi-lo>guess/6 and hi-lo<guess*3 then return hi-lo end
            no_metrics=true;return guess
        end
        local b=H.layout(anchor,width,height,measure,keys)
        if not b.fits then self:clear();return false end
        local function rect(x,y,w,h,z,c)assert(e.Gui.rect(gui,e.Vector3(x,y,z),e.Vector2(w,h),c))end
        local function text(value,x,cy,size,c)
            value=(tostring(value):upper():gsub('[^\32-\126]','?'))
            assert(e.Gui.text(gui,value,font,size,mat,e.Vector3(x,cy-size*0.35,996),c))
        end
        -- As the game draws its key caps: a light cap with dark text, then a
        -- white label.
        local cap,px,edge=b.cap,b.border,color(196,200,204)
        rect(cap.x,cap.y,cap.w,cap.h,990,color(236,238,240))
        rect(cap.x,cap.y,cap.w,px,991,edge);rect(cap.x,cap.y+cap.h-px,cap.w,px,991,edge)
        rect(cap.x,cap.y,px,cap.h,991,edge);rect(cap.x+cap.w-px,cap.y,px,cap.h,991,edge)
        text(keys,b.keys.x,b.keys.cy,b.size,color(51,51,51))
        text(H.LABEL,b.label.x,b.label.cy,b.size,color(255,255,255))
        return true
    end
    return self
end
return H
