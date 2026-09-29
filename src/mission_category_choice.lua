-- Choice stage of 11e5100. Candidate order is template order, not type ID.
-- Input candidates have already passed eligibility with category wildcard 0.
return function(candidates,rules,usage,rng)
    local ffi=require('ffi');local single=ffi.new('float[1]')
    local function f(n)single[0]=n;return tonumber(single[0])end
    assert(#candidates<=32 and #rules<=9,'Category input capacity exceeded')
    local category=0
    if #rules>0 then
        for _,rule in ipairs(rules)do
            if rule.minimum~=0 and (usage[rule.category] or 0)<rule.minimum then
                category=rule.category;break
            end
        end
        if category==0 then
            local available,seen={},{}
            for _,candidate in ipairs(candidates)do
                local cat=candidate.category
                assert(cat>=0 and cat<=8 and cat==math.floor(cat),'Invalid mission category')
                if not seen[cat] then
                    local blocked=false
                    for _,rule in ipairs(rules)do
                        if rule.category==cat then
                            blocked=rule.maximum~=0 and (usage[cat] or 0)>=rule.maximum;break
                        end
                    end
                    if not blocked then available[#available+1]=cat;seen[cat]=true end
                end
            end
            if #available==1 then category=available[1]
            elseif #available>1 then
                local weights,total={},0
                for _,cat in ipairs(available)do
                    for _,rule in ipairs(rules)do
                        if rule.category==cat then
                            assert(rule.weight>=0 and rule.weight<math.huge,'Invalid category weight')
                            weights[cat]=f(rule.weight);total=f(total+weights[cat]);break
                        end
                    end
                end
                if total>0 then
                    local threshold=f(f(f(rng:next())*f(1/4294967296))*total)
                    local sum=0
                    for _,cat in ipairs(available)do
                        if weights[cat] then
                            sum=f(sum+weights[cat])
                            if threshold<=sum then category=cat;break end
                        end
                    end
                end
            end
        end
    end
    local selected={}
    for _,candidate in ipairs(candidates)do
        if category==0 or candidate.category==category then selected[#selected+1]=candidate.id end
    end
    if #selected==0 and category~=0 then
        category=0
        for _,candidate in ipairs(candidates)do selected[#selected+1]=candidate.id end
    end
    return selected,category
end
