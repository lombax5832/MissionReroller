local P={}
function P.layout(width,height,model)
    assert(width>=640 and height>=480,'Viewport too small')
    local s=math.min(width/1200,height/820)
    local w,h=960*s,650*s
    local x,y=(width-w)/2,(height-h)/2
    local b={x=x,y=y,w=w,h=h,s=s,targets={}}
    for i=1,(model and model.items and #model.items or 12) do
        local col=math.floor((i-1)/6);local row=(i-1)%6
        b.targets[#b.targets+1]={id=model and model.items and model.items[i].id or i,x=x+(32+col*460)*s,y=y+h-(206+row*54)*s,w=436*s,h=44*s,enabled=not(model and model.running) and not(model and model.items and model.items[i].enabled==false)}
    end
    if model and model.tab then
        b.targets[#b.targets+1]={id='missions_tab',x=x+32*s,y=y+h-154*s,w=190*s,h=30*s}
        b.targets[#b.targets+1]={id='modifiers_tab',x=x+234*s,y=y+h-154*s,w=190*s,h=30*s}
        b.targets[#b.targets+1]={id='constellations_tab',x=x+436*s,y=y+h-154*s,w=176*s,h=30*s}
        if model.pages>1 then
            b.targets[#b.targets+1]={id='previous_page',x=x+620*s,y=y+h-154*s,w=46*s,h=30*s}
            b.targets[#b.targets+1]={id='next_page',x=x+676*s,y=y+h-154*s,w=46*s,h=30*s}
        end
    end
    b.targets[#b.targets+1]={id='clear',x=x+32*s,y=y+30*s,w=180*s,h=46*s,enabled=not(model and model.running)}
    b.targets[#b.targets+1]={id='close',x=x+w-212*s,y=y+30*s,w=180*s,h=46*s}
    if model then
        if not model.difficulty_locked then
            b.targets[#b.targets+1]={id='down',x=x+236*s,y=y+30*s,w=42*s,h=46*s,enabled=not model.running}
            b.targets[#b.targets+1]={id='up',x=x+374*s,y=y+30*s,w=42*s,h=46*s,enabled=not model.running}
        end
        b.targets[#b.targets+1]={id=model.running and 'cancel' or 'start',x=x+440*s,y=y+30*s,w=276*s,h=46*s,enabled=model.running or model.ready}
    end
    return b
end
function P.new(e)
    local gui,world,ids,texts,cache,identity
    local self={}
    function self:clear()
        if gui then for _,w in ipairs(e.Application.worlds()) do
            if w==world then e.World.destroy_gui(world,gui);break end
        end end
        gui,world,ids,texts,cache,identity=nil,nil,nil,nil,nil,nil
    end
    function self:show(options,selected,face,pointer,model)
        local width,height=e.Gui.resolution();local b=P.layout(width,height,model)
        local target
        for _,w in ipairs(e.Application.worlds()) do if w~=e.Application.main_world() then target=w;break end end
        assert(target,'UI world unavailable')
        local key=table.concat({width,height,face.font,face.material,face.atlas},'|')
        if model and model.items then
            key=key..'|'..model.tab..':'..model.pages
            for _,item in ipairs(model.items)do key=key..'|'..tostring(item.id)..':'..item.name end
        end
        if target~=world or key~=identity then self:clear() end
        local font,mat=e.IdString64.from_hex(face.font),e.IdString64.from_hex(face.material)
        local function color(r,g,blue,a)return e.Color(a or 255,r,g,blue)end
        local gold,white,muted=color(255,213,0),color(237,241,245),color(153,167,178)
        if not gui then
            world=target;gui=assert(e.World.create_screen_gui(world,'scale',1,1));ids={};texts={};identity=key
            local m=assert(e.Gui.material(gui,mat))
            local function slot(v)return e.IdString64.from_hex(v..'00000000')end
            for _,v in ipairs({'8035c266','5e8455fe','309e7783','82b803a8'}) do e.Material.set_scalar(m,slot(v),0)end
            e.Material.set_vector2(m,slot('e13777ce'),e.Vector2(1,-1))
            e.Material.set_vector4(m,slot('7701209e'),color(0,0,0,0))
            e.Material.set_texture(m,slot('88bac99b'),e.IdString64.from_hex(face.atlas))
        end
        local hover;local count=0;local bits={};local items={}
        if model and model.items then
            for _,item in ipairs(model.items)do items[item.id]=item;bits[#bits+1]=tostring(item.id)..item.name..tostring(item.mode)..tostring(item.enabled)..tostring(item.caption)end
        end
        local checked={};for id in pairs(selected)do checked[#checked+1]=id;count=count+1 end
        table.sort(checked);bits[#bits+1]='|'..table.concat(checked,',')..'|'
        local hint
        for _,t in ipairs(b.targets)do
            if t.enabled==false and items[t.id] and pointer.x>=t.x and pointer.x<t.x+t.w and pointer.y>=t.y and pointer.y<t.y+t.h then hint=items[t.id].reason end
            if t.enabled~=false and pointer.x>=t.x and pointer.x<t.x+t.w and pointer.y>=t.y and pointer.y<t.y+t.h then hover=t.id end
        end
        local state=table.concat(bits)..tostring(hover)..tostring(hint)..(model and table.concat({model.difficulty,model.status,tostring(model.running),tostring(model.ready),model.calls,model.tab or '',model.page or 1,model.hint or ''},'|') or '')
        if cache==state then return end
        local function rect(id,x,y,w,h,z,c)
            if ids[id] then e.Gui.update_rect(gui,ids[id],e.Vector3(x,y,z),e.Vector2(w,h),c)
            else ids[id]=assert(e.Gui.rect(gui,e.Vector3(x,y,z),e.Vector2(w,h),c))end
        end
        local function text(id,value,x,y,size,c)
            local pos=e.Vector3(x,y,995)
            if texts[id] then e.Gui.update_text(gui,texts[id],value,font,size*b.s,mat,pos,c)
            else texts[id]=assert(e.Gui.text(gui,value,font,size*b.s,mat,pos,c))end
        end
        local x,y,w,h,s=b.x,b.y,b.w,b.h,b.s
        rect('dim',0,0,width,height,985,color(0,0,0,170))
        rect('edge',x-1*s,y-1*s,w+2*s,h+2*s,990,color(90,102,110))
        rect('body',x,y,w,h,991,color(15,21,28))
        rect('accent',x,y+h-4*s,w,4*s,993,gold)
        text('title','REROLL OPERATIONS',x+32*s,y+h-53*s,32,gold)
        text('sub',model and model.subtitle or 'Choose the missions you want in one operation.',x+32*s,y+h-86*s,18,white)
        rect('divider',x+32*s,y+h-108*s,w-64*s,1*s,993,color(65,77,88))
        text('section',model and model.tab and '' or 'REQUIRED MISSIONS',x+32*s,y+h-141*s,16,muted)
        text('count',model and model.tab and ('PAGE '..model.page..' / '..model.pages) or count..' SELECTED',x+w-168*s,y+h-141*s,16,gold)
        text('empty',model and model.items and #model.items==0 and 'No eligible options for this planet and difficulty.' or '',x+32*s,y+h-210*s,18,muted)
        for i,t in ipairs(b.targets)do
            local item=items[t.id]
            local over=hover==t.id;local picked=type(t.id)=='number' and selected[t.id]
            rect('row'..i,t.x,t.y,t.w,t.h,993,over and color(49,60,69) or color(25,34,43))
            if type(t.id)=='number' then
                rect('box'..i,t.x+14*s,t.y+12*s,20*s,20*s,994,picked and gold or t.enabled==false and color(52,60,68) or color(104,119,130))
                rect('inner'..i,t.x+17*s,t.y+15*s,14*s,14*s,994,picked and gold or color(15,21,28))
                text('label'..i,item and item.name or options[t.id].name,t.x+48*s,t.y+15*s,17,picked and gold or t.enabled==false and color(100,110,120) or white)
            elseif item and item.caption then
                text('label'..i,item.caption,t.x+14*s,t.y+15*s,16,over and gold or white)
            elseif item then
                local mode=item.mode or 'any'
                text('label'..i,string.upper(mode)..'  '..item.name,t.x+14*s,t.y+15*s,16,(mode=='require' or mode=='accept') and gold or mode=='exclude' and color(255,130,110) or muted)
            else
                local captions={clear='CLEAR SELECTION',close='CLOSE',down='-',up='+',start='REROLL OPERATIONS',cancel='CANCEL SEARCH',missions_tab='MISSIONS',modifiers_tab='MODIFIERS',constellations_tab='CONSTELLATIONS',previous_page='<',next_page='>'}
                text('label'..i,captions[t.id],t.x+(t.w<50*s and 13 or 18)*s,t.y+(t.h<40*s and 8 or 16)*s,17,t.enabled==false and muted or over and gold or white)
            end
        end
        text('rule',hint or (model and model.hint) or (model and model.tab=='modifiers' and 'Click to cycle: ANY > REQUIRE > EXCLUDE. Rules apply to the same operation.' or 'All checked missions are required. Extra missions are unrestricted.'),x+32*s,y+120*s,16,muted)
        if model then
            text('preview',(model.difficulty_locked and 'MAP D ' or 'D ')..model.difficulty,x+(model.difficulty_locked and 254 or 296)*s,y+46*s,18,gold)
            text('status',model.status:sub(1,78)..'  ['..(model.counter_label or 'Rerolls')..': '..model.calls..']',x+32*s,y+91*s,16,white)
        else text('preview','UI PREVIEW  /  Rerolling is disabled',x+254*s,y+48*s,16,muted) end
        cache=state
    end
    return self
end
return P
