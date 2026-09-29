-- Template and modifier choices from 11e3250, given resolved legal templates
-- and the effective difficulty's modifier budget. No native calls or writes.
return function(make_rng)
    local ffi=require('ffi');local single=ffi.new('float[1]')
    local function f(n)single[0]=n;return tonumber(single[0])end
    local function draw(pool,rng)
        local total=0
        for _,item in ipairs(pool)do
            assert(item.weight>=0 and item.weight<math.huge,'Invalid finalizer weight')
            total=f(total+f(item.weight))
        end
        local threshold=f(f(f(rng:next())*f(1/4294967296))*total)
        local accumulated=0
        for i,item in ipairs(pool)do
            accumulated=f(accumulated+f(item.weight))
            if threshold<=accumulated then return i end
        end
    end
    return function(seed,templates,explicit_hash,budget,all_templates)
        assert(#templates<=25,'Too many operation templates')
        assert(budget>=0 and budget==math.floor(budget),'Invalid modifier budget')
        local rng=make_rng(seed)
        local template
        if explicit_hash and explicit_hash~=0 then
            for _,item in ipairs(assert(all_templates,'Missing explicit template lookup'))do
                if item.hash==explicit_hash then template=item;break end
            end
        end
        if not template then local index=draw(templates,rng);template=index and templates[index]end
        if not template then return {valid=false,modifiers={},state=rng:state_bytes()}end
        local pool={}
        for _,item in ipairs(template.modifiers)do
            assert(#pool<8 and item.cost>=0 and item.cost==math.floor(item.cost),'Invalid modifier input')
            pool[#pool+1]=item
        end
        local modifiers={}
        while #pool>0 and #modifiers<2 do
            local i=1
            while i<=#pool do
                if pool[i].cost>budget then pool[i]=pool[#pool];pool[#pool]=nil else i=i+1 end
            end
            if #pool==0 then break end
            local selected=assert(draw(pool,rng),'No weighted operation modifier')
            local item=pool[selected];modifiers[#modifiers+1]=item.id;budget=budget-item.cost
            pool[selected]=pool[#pool];pool[#pool]=nil
        end
        return {valid=true,template_index=template.index,modifiers=modifiers,state=rng:state_bytes()}
    end
end
