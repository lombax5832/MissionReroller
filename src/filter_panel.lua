-- Retained engine GUI; no native widget mutation or mouse interception.
return function(e)
    local gui,world,identity,texts,signature,cursor_ids
    local P={}
    local function exists(w)
        for _,v in ipairs(e.Application.worlds()) do if v==w then return true end end
    end
    function P:clear()
        if gui and exists(world) then e.World.destroy_gui(world,gui) end
        gui,world,identity,texts,signature,cursor_ids=nil,nil,nil,nil,nil,nil
    end
    function P:show(lines,face,pointer)
        local target
        for _,w in ipairs(e.Application.worlds()) do if w~=e.Application.main_world() then target=w;break end end
        if not target then self:clear();return false end
        local width,height=e.Gui.resolution()
        assert(width>=640 and height>=480,'Viewport too small')
        local key=table.concat({face.font,face.material,face.atlas,width,height},'|')
        if world~=target or identity~=key then self:clear() end
        local scale=math.min(width/1280,height/900)
        local x,y,w,h=30*scale,30*scale,740*scale,820*scale
        local font=e.IdString64.from_hex(face.font)
        local mat=e.IdString64.from_hex(face.material)
        local function color(a,r,g,b)return e.Color(a,r,g,b)end
        if not gui then
            world=target;gui=assert(e.World.create_screen_gui(world,'scale',1,1));texts={};identity=key
            local material=assert(e.Gui.material(gui,mat))
            local function slot(s)return e.IdString64.from_hex(s..'00000000')end
            for _,s in ipairs({'8035c266','5e8455fe','309e7783','82b803a8'}) do e.Material.set_scalar(material,slot(s),0) end
            e.Material.set_vector2(material,slot('e13777ce'),e.Vector2(1,-1))
            e.Material.set_vector4(material,slot('7701209e'),color(0,0,0,0))
            e.Material.set_texture(material,slot('88bac99b'),e.IdString64.from_hex(face.atlas))
            e.Gui.rect(gui,e.Vector3(x-2,y-2,990),e.Vector2(w+4,h+4),color(255,255,213,0))
            e.Gui.rect(gui,e.Vector3(x,y,991),e.Vector2(w,h),color(255,12,18,25))
        end
        local value=table.concat(lines,'\n')
        if value~=signature then
            for i=1,26 do
                local line=lines[i] or ''
                local size=(i==1 and 25 or 19)*scale
                local pos=e.Vector3(x+20*scale,y+h-i*30*scale,992)
                local ink=i==1 and color(255,255,213,0) or color(255,230,235,240)
                if texts[i] then e.Gui.update_text(gui,texts[i],line,font,size,mat,pos,ink)
                else texts[i]=assert(e.Gui.text(gui,line,font,size,mat,pos,ink)) end
            end
            signature=value
        end
        if pointer then
            assert(type(pointer.x)=='number' and type(pointer.y)=='number'
                and pointer.x==pointer.x and pointer.y==pointer.y,'Invalid pointer coordinates')
            cursor_ids=cursor_ids or {}
            local function part(i,dx,dy,cw,ch,z,ink)
                local pos=e.Vector3(pointer.x+dx*scale,pointer.y+dy*scale,z)
                local size=e.Vector2(cw*scale,ch*scale)
                if cursor_ids[i] then e.Gui.update_rect(gui,cursor_ids[i],pos,size,ink)
                else cursor_ids[i]=assert(e.Gui.rect(gui,pos,size,ink)) end
            end
            -- A high-contrast crosshair remains visible independently of native cursor focus.
            part(1,-10,-3,20,6,1000,color(255,0,0,0))
            part(2,-3,-10,6,20,1000,color(255,0,0,0))
            part(3,-9,-1,18,2,1001,color(255,255,255,255))
            part(4,-1,-9,2,18,1001,color(255,255,255,255))
        elseif cursor_ids then
            for _,id in ipairs(cursor_ids) do e.Gui.destroy_rect(gui,id) end
            cursor_ids=nil
        end
        return true
    end
    return P
end
