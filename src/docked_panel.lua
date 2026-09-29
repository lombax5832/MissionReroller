-- Docked briefing panel of the prediction dialog. It is laid out top-down in a
-- 1920x1080 design space and flipped once, because Stingray's origin is the
-- bottom-left corner. Lists shrink their rows so the longest one still ends
-- above the footer of a running search.
local P={}
local W,H,EDGE,LEFT,INNER,FOOT=664,1008,40,25,610,820
local SECTIONS={{id='missions',title='MISSIONS'},{id='modifiers',title='MODIFIERS'},{id='enemies',title='ENEMY FORCES'}}
local FACTIONS={[2]={'TERMINIDS',255,179,0},[3]={'AUTOMATONS',255,90,79},[4]={'ILLUMINATE',197,139,255}}
local STEPS={'1 CHECK PLANET','2 SEARCH SEEDS','3 REFRESH BOARD','4 OPEN OPERATION'}
local WORDS={require='REQUIRED',accept='ACCEPTED',exclude='EXCLUDED'}
function P.layout(width,height,model)
    assert(width>=640 and height>=480,'Viewport too small')
    model=model or {}
    local s=math.min(width/1920,height/1080)
    local b={s=s,w=W*s,h=H*s,targets={},headers={},rows={},groups={},pager={}}
    -- Hang off the real right edge, also on screens wider than 16:9.
    b.x,b.y=width-(EDGE+W)*s,(height-H*s)/2
    local function target(id,left,top,w,h,enabled)
        local t={id=id,x=b.x+left*s,y=b.y+(H-top-h)*s,w=w*s,h=h*s,enabled=enabled and true or false}
        b.targets[#b.targets+1]=t;return t
    end
    local items,top=model.items or {},107
    local function usable(item)return not model.locked and item.enabled~=false end
    for i,section in ipairs(SECTIONS)do
        b.headers[i]=target('section:'..section.id,LEFT,top,INNER,52,true)
        top=top+58
        if model.section==section.id then
            local first,below=top+36,(#SECTIONS-i)*58
            b.meta=top+19
            if section.id=='enemies' then
                local groups=model.groups or {}
                local w=(INNER+4)/math.max(1,#groups)-4
                for n,group in ipairs(groups)do b.groups[n]=target('group:'..group.id,LEFT+(n-1)*(w+4),top+10,w,36,true)end
                first=top+(#groups>0 and 54 or 10);below=below+48;b.meta=first+9
            elseif section.id=='missions' and (model.pages or 1)>1 then
                b.pager[1]=target('previous_page',LEFT+INNER-64,top+6,30,26,true)
                b.pager[2]=target('next_page',LEFT+INNER-30,top+6,30,26,true)
            end
            local last=section.id=='enemies' and first+18 or first-8
            if #items>0 and section.id=='missions' then
                local rows=math.ceil(#items/2)
                assert(rows<=12,'Too many missions on one page')
                for n,item in ipairs(items)do
                    b.rows[n]=target(item.id,LEFT+math.floor((n-1)/rows)*308,first+((n-1)%rows)*35,302,32,usable(item))
                end
                last=first+rows*35-3
            elseif #items>0 then
                local h=math.min(38,math.floor((FOOT-14-below-first-(#items-1)*4)/#items))
                for n,item in ipairs(items)do b.rows[n]=target(item.id,LEFT,first+(n-1)*(h+4),INNER,h,usable(item))end
                last=first+#items*(h+4)-4
            end
            if section.id=='enemies' then b.notes={last+17,last+37};last=last+48 end
            top=last+14
        end
    end
    b.primary=target(model.running and 'cancel' or 'start',LEFT,931,394,56,model.running or model.can_start)
    b.clear=target('clear',LEFT+402,931,100,56,model.can_clear)
    b.close=target('close',LEFT+510,931,100,56,true)
    return b
end
function P.new(e)
    local gui,world,ids,texts,shapes,cache,detail,identity
    local widths,fits,known={},{},0
    -- Triangles and text metrics are optional. After one failure they stay off:
    -- no chevrons, square corners and estimated widths.
    local no_shapes,no_metrics
    local self={}
    function self:clear()
        if gui then for _,w in ipairs(e.Application.worlds()) do
            if w==world then e.World.destroy_gui(world,gui);break end
        end end
        gui,world,ids,texts,shapes,cache,detail,identity=nil,nil,nil,nil,nil,nil,nil,nil
        widths,fits,known={},{},0
    end
    function self:show(options,selected,face,pointer,model)
        model=model or {}
        local width,height=e.Gui.resolution();local b=P.layout(width,height,model)
        local target
        for _,w in ipairs(e.Application.worlds()) do if w~=e.Application.main_world() then target=w;break end end
        assert(target,'UI world unavailable')
        local items,groups,summaries=model.items or {},model.groups or {},model.summaries or {}
        local key={width,height,face.font,face.material,face.atlas,tostring(model.section),model.page or 1,model.pages or 1}
        for _,group in ipairs(groups)do key[#key+1]='group:'..group.id..':'..group.name end
        for _,item in ipairs(items)do key[#key+1]=tostring(item.id)..':'..item.name end
        key=table.concat(key,'|')
        if target~=world or key~=identity then self:clear() end
        local font,mat=e.IdString64.from_hex(face.font),e.IdString64.from_hex(face.material)
        local function color(r,g,blue,a)return e.Color(a or 255,r,g,blue)end
        if not gui then
            world=target;gui=assert(e.World.create_screen_gui(world,'scale',1,1));ids={};texts={};shapes={};identity=key
            local m=assert(e.Gui.material(gui,mat))
            local function slot(v)return e.IdString64.from_hex(v..'00000000')end
            for _,v in ipairs({'8035c266','5e8455fe','309e7783','82b803a8'}) do e.Material.set_scalar(m,slot(v),0)end
            e.Material.set_vector2(m,slot('e13777ce'),e.Vector2(1,-1))
            e.Material.set_vector4(m,slot('7701209e'),color(0,0,0,0))
            e.Material.set_texture(m,slot('88bac99b'),e.IdString64.from_hex(face.atlas))
        end
        local hover,hint
        local function inside(t)return pointer.x>=t.x and pointer.x<t.x+t.w and pointer.y>=t.y and pointer.y<t.y+t.h end
        for _,t in ipairs(b.targets)do if t.enabled and inside(t)then hover=t.id end end
        for n,t in ipairs(b.rows)do if not t.enabled and inside(t)then hint=items[n].reason end end
        local bits={tostring(hover),tostring(hint),model.status or '',model.tone or '',tostring(model.step),tostring(model.running),
            tostring(model.locked),tostring(model.can_start),tostring(model.can_clear),tostring(model.faction),model.scope or '',
            tostring(model.difficulty),tostring(model.slots),tostring(model.checked),model.forced or '',model.note or ''}
        for _,section in ipairs(SECTIONS)do bits[#bits+1]=summaries[section.id] or ''end
        for _,group in ipairs(groups)do bits[#bits+1]=tostring(group.selected)end
        for _,item in ipairs(items)do bits[#bits+1]=tostring(item.mode)..tostring(item.enabled)..tostring(selected[item.id]==true)end
        local state=table.concat(bits,'|')
        -- The seed counter changes every frame of a search; it is one text.
        local full,counter=cache~=state,model.detail or ''
        if not full and detail==counter then return end
        local s,used=b.s,{}
        local function rect(id,x,y,w,h,z,c)
            used[id]=true
            if ids[id] then e.Gui.update_rect(gui,ids[id],e.Vector3(x,y,z),e.Vector2(w,h),c)
            else ids[id]=assert(e.Gui.rect(gui,e.Vector3(x,y,z),e.Vector2(w,h),c))end
        end
        -- Created once and never updated: whatever a triangle depends on is
        -- part of the identity that recreates the GUI.
        local function tri(id,ax,ay,bx,by,cx,cy,z,c)
            if no_shapes or shapes[id] then return end
            -- As the sibling overlays call it: x/z is the screen plane.
            local ok,made=pcall(function()
                return e.Gui.triangle(gui,e.Vector3(ax,0,ay),e.Vector3(bx,0,by),e.Vector3(cx,0,cy),z,c)
            end)
            if ok and made then shapes[id]=made else no_shapes=true end
        end
        local function measure(value,size)
            local k=size..'|'..value
            if widths[k] then return widths[k] end
            -- Without metrics assume wide glyphs, so text stays inside its box.
            local guess=#value*size*0.6
            local got=guess
            if not no_metrics and value~='' then
                local ok,lo,hi=pcall(function()
                    local lo,hi,caret=e.Gui.text_extents(gui,value,font,size)
                    local x=e.Vector2.x
                    return math.min(0,x(lo)),math.max(x(hi),caret and x(caret) or 0)
                end)
                if ok and type(lo)=='number' and type(hi)=='number' and hi-lo>guess/6 and hi-lo<guess*3 then got=hi-lo
                else no_metrics=true end
            end
            if known>=512 then widths,fits,known={},{},0 end
            widths[k]=got;known=known+1
            return got
        end
        local function fit(value,size,room)
            local k=size..'|'..room..'|'..value
            local f=fits[k];if f then return f[1],f[2],f[3] end
            local short,w=value,measure(value,size)
            if w>room then
                -- Shrink a little first; cut the text only when that is not enough.
                size=size*math.max(0.8,room/w*0.98);w=measure(value,size)
                local n=#value
                while w>room and n>1 do
                    n=math.max(1,math.min(n-1,math.floor(n*room/w)))
                    short=(value:sub(1,n):gsub('%s+$',''))..'...'
                    w=measure(short,size)
                end
            end
            fits[k]={short,size,w};known=known+1
            return short,size,w
        end
        -- x is the left edge, the right edge or the centre; cy the middle of the line.
        local function text(id,value,x,cy,size,c,align,room)
            -- The design is set in capitals. The font atlas may lack glyphs outside ASCII.
            value=(tostring(value):upper():gsub('[^\32-\126]','?'))
            size=size*s
            local w
            if room then value,size,w=fit(value,size,math.max(room,size))end
            if align then w=w or measure(value,size);x=x-(align=='right' and w or w/2)end
            local pos=e.Vector3(x,cy-size*0.35,996)
            used['#'..id]=true
            if texts[id] then e.Gui.update_text(gui,texts[id],value,font,size,mat,pos,c)
            else texts[id]=assert(e.Gui.text(gui,value,font,size,mat,pos,c))end
            return w
        end
        local x,y,w,h=b.x,b.y,b.w,b.h
        local left,right,px=x+LEFT*s,x+(LEFT+INNER)*s,math.max(1,s)
        local function at(top)return y+(H-top)*s end
        local muted=color(143,155,165)
        if full then
            local yellow,white,red,amber=color(255,232,10),color(237,241,245),color(255,107,90),color(255,179,0)
            local ink,dim,dark,outline,none=color(11,13,16),color(86,96,105),color(14,17,21),color(122,135,145),color(0,0,0,0)
            local function glass(a)return color(255,255,255,a)end
            local function wash(c,a)return color(c[1],c[2],c[3],a)end
            local YELLOW,RED={255,232,10},{255,107,90}
            local faction=FACTIONS[model.faction]
            local tint=faction and color(faction[2],faction[3],faction[4]) or muted
            rect('body',x,y,w,h,990,color(8,10,13,242))
            rect('edge_top',x,y+h-px,w-5*s,px,991,glass(43))
            rect('edge_bottom',x,y,w-5*s,px,991,glass(43))
            rect('edge_left',x,y+px,px,h-2*px,991,glass(43))
            rect('bar',x+w-5*s,y,5*s,h,991,yellow)
            if faction then
                local fw=text('faction',faction[1],left,at(32),15,tint,nil,220*s)
                text('scope','/ '..(model.scope=='city' and 'THIS CITY ONLY' or 'WHOLE PLANET'),left+fw+8*s,at(32),15,muted)
                text('level','DIFFICULTY '..tostring(model.difficulty),right,at(32),15,muted,'right',160*s)
            else text('faction','NO PLANET',left,at(32),15,muted)end
            text('title','REROLL OPERATIONS',left,at(66),40,white,nil,INNER*s)
            for i,t in ipairs(b.headers)do
                local section=SECTIONS[i]
                local open,over,cy=model.section==section.id,hover==t.id,t.y+t.h/2
                rect('head'..i,t.x,t.y,t.w,t.h,992,open and (over and color(255,241,110) or yellow) or glass(over and 43 or 18))
                rect('number'..i,t.x+16*s,cy-14*s,28*s,28*s,993,open and ink or glass(36))
                text('number'..i,i,t.x+30*s,cy,16,open and yellow or white,'centre')
                text('head'..i,section.title,t.x+58*s,cy,21,open and ink or white,nil,200*s)
                text('summary'..i,summaries[section.id] or '',t.x+t.w-44*s,cy,15,open and ink or muted,'right',290*s)
                local cx=t.x+t.w-23*s
                if open then tri('chevron'..i,cx-7*s,cy-4.5*s,cx+7*s,cy-4.5*s,cx,cy+4.5*s,996,ink)
                else tri('chevron'..i,cx-7*s,cy+4.5*s,cx,cy-4.5*s,cx+7*s,cy+4.5*s,996,muted)end
            end
            local section=model.section
            local empty=#items==0 and (not faction and 'NO PLANET CHOSEN' or section=='enemies' and 'NO ENEMY FORCES CAN BE CHOSEN HERE'
                or 'NO ELIGIBLE OPTIONS FOR THIS PLANET AND DIFFICULTY')
            if section=='missions' or section=='modifiers' then
                local limit=b.pager[1] and b.pager[1].x-10*s or right-2*s
                for n,t in ipairs(b.pager)do
                    rect('pager'..n,t.x,t.y,t.w,t.h,992,glass(hover==t.id and 51 or 18))
                    text('pager'..n,n==1 and '<' or '>',t.x+t.w/2,t.y+t.h/2,17,white,'centre')
                end
                local note=empty and '' or section=='modifiers' and 'AT MOST TWO PER OPERATION'
                    or (b.pager[1] and 'PAGE '..tostring(model.page)..'/'..tostring(model.pages)..'   ' or '')
                        ..(model.checked or 0)..' OF '..tostring(model.slots)..' SLOTS'
                local used_width=text('meta_right',note,limit,at(b.meta),15,muted,'right',300*s)
                text('meta',hint or empty or (section=='modifiers' and 'CLICK TO CYCLE: ANY, REQUIRED, EXCLUDED'
                    or 'ALL CHECKED MISSIONS MUST BE IN ONE OPERATION'),left+2*s,at(b.meta),15,hint and white or muted,nil,limit-left-used_width-18*s)
            elseif section=='enemies' then
                for n,t in ipairs(b.groups)do
                    local chosen=groups[n].selected
                    rect('group'..n,t.x,t.y,t.w,t.h,992,chosen and white or glass(hover==t.id and 51 or 18))
                    text('group'..n,groups[n].name,t.x+t.w/2,t.y+t.h/2,15,chosen and ink or white,'centre',t.w-12*s)
                end
                if empty then text('meta',empty,left+2*s,at(b.meta),15,muted,nil,INNER*s)end
                local line=1
                if (model.forced or '')~='' then
                    local lead=text('always','ALWAYS PRESENT:',left+2*s,at(b.notes[1]),15,muted,nil,220*s)
                    text('forced',model.forced,left+8*s+lead,at(b.notes[1]),15,tint,nil,INNER*s-lead-10*s)
                    line=2
                end
                if model.note then text('note',model.note,left+2*s,at(b.notes[line]),15,muted,nil,INNER*s)end
            end
            for n,t in ipairs(b.rows)do
                local item,over,off,cy=items[n],hover==t.id,not t.enabled,t.y+t.h/2
                if section=='missions' then
                    local picked=selected[item.id]
                    rect('row'..n,t.x,t.y,t.w,t.h,992,picked and wash(YELLOW,over and 56 or 28) or glass(off and 5 or over and 41 or 13))
                    rect('box'..n,t.x+9*s,cy-8*s,16*s,16*s,993,picked and yellow or off and dim or outline)
                    rect('gap'..n,t.x+11*s,cy-6*s,12*s,12*s,994,dark)
                    rect('mark'..n,t.x+13*s,cy-4*s,8*s,8*s,995,picked and yellow or none)
                    text('label'..n,item.name,t.x+34*s,cy,15,picked and yellow or off and dim or white,nil,t.w-43*s)
                else
                    local on,out=item.mode=='require' or item.mode=='accept',item.mode=='exclude'
                    local rule=on and yellow or out and red
                    rect('row'..n,t.x,t.y,t.w,t.h,992,off and glass(5) or on and wash(YELLOW,over and 56 or 28)
                        or out and wash(RED,over and 52 or 26) or glass(over and 41 or 13))
                    rect('box'..n,t.x+14*s,cy-10*s,20*s,20*s,993,rule or outline)
                    rect('gap'..n,t.x+16*s,cy-8*s,16*s,16*s,994,on and yellow or dark)
                    rect('mark'..n,t.x+19*s,cy-1.5*s,10*s,3*s,995,out and red or none)
                    local word=text('word'..n,WORDS[item.mode] or 'ANY',t.x+t.w-14*s,cy,14,rule or muted,'right',120*s)
                    text('label'..n,item.name,t.x+43*s,cy,19,off and dim or rule or white,nil,t.w-73*s-word)
                end
            end
            local foot=model.running and FOOT or FOOT+36
            rect('foot',x+px,y+px,w-5*s-px,(H-foot)*s-px,991,glass(9))
            rect('foot_edge',x+px,at(foot),w-5*s-px,px,992,glass(43))
            if model.running then
                local step=model.step or 1
                for n,caption in ipairs(STEPS)do
                    local sx=left+(n-1)*153.5*s
                    rect('step'..n,sx,at(839),149.5*s,4*s,992,n<=step and yellow or glass(36))
                    text('step'..n,caption,sx,at(853),12,n==step and yellow or n<step and white or muted,nil,149.5*s)
                end
            end
            local tones={idle=white,busy=yellow,bad=red,warn=amber,good=yellow}
            text('status',model.status or '',left,at(882),19,tones[model.tone] or white,nil,INNER*s)
            local t=b.primary
            rect('primary',t.x,t.y,t.w,t.h,992,model.running and (hover==t.id and color(255,148,133) or red)
                or t.enabled and (hover==t.id and white or yellow) or wash(YELLOW,82))
            text('primary',model.running and 'CANCEL SEARCH' or 'REROLL OPERATIONS',t.x+t.w/2,t.y+t.h/2,25,ink,'centre',t.w-44*s)
            -- Chamfers are cut out with the footer's colour, so a missing
            -- triangle leaves a plain rectangle.
            local cut=color(16,18,21)
            tri('cut_top',t.x+t.w-16*s,t.y+t.h,t.x+t.w,t.y+t.h-16*s,t.x+t.w,t.y+t.h,993,cut)
            tri('cut_bottom',t.x,t.y,t.x+16*s,t.y,t.x,t.y+16*s,993,cut)
            for _,button in ipairs({b.clear,b.close})do
                rect(button.id,button.x,button.y,button.w,button.h,992,glass(not button.enabled and 7 or hover==button.id and 51 or 23))
                text(button.id,button.id,button.x+button.w/2,button.y+button.h/2,21,button.enabled and white or dim,'centre',button.w-16*s)
            end
        end
        text('detail',counter,left,at(907),15,muted)
        if full then
            -- Whatever this state did not draw is left over from the previous one.
            local none=color(0,0,0,0)
            for id,handle in pairs(ids)do
                if not used[id]then e.Gui.update_rect(gui,handle,e.Vector3(x,y,990),e.Vector2(px,px),none)end
            end
            for id,handle in pairs(texts)do
                if not used['#'..id]then e.Gui.update_text(gui,handle,'',font,10*s,mat,e.Vector3(x,y,996),none)end
            end
        end
        cache,detail=state,counter
    end
    return self
end
return P
