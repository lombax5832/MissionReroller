-- Structural reachability, not seed sampling. Ignore random weight/seed
-- correlations and mission repeat counters: a superset prevents false rejection.
-- A mask is a set of mission families, kept as a canonical string of 30-bit
-- words so that it can be a table key for any number of families.
local bit=require('bit')
local C={}
local WORDS,BITS=4,30
local parsed={}
local function words(mask)
    local value=parsed[mask]
    if not value then
        value={};for word in mask:gmatch('[^:]+')do value[#value+1]=tonumber(word)end
        assert(#value==WORDS,'Invalid mission family mask');parsed[mask]=value
    end
    return value
end
local function key(value)return table.concat(value,':')end
C.none=key({0,0,0,0})
function C.bit(id)
    assert(type(id)=='number' and id>=1 and id<=WORDS*BITS and id==math.floor(id),'Mission family outside mask capacity')
    local value={0,0,0,0}
    value[math.floor((id-1)/BITS)+1]=bit.lshift(1,(id-1)%BITS)
    return key(value)
end
function C.union(a,b)
    local x,y=words(a),words(b);local value={}
    for i=1,WORDS do value[i]=bit.bor(x[i],y[i])end
    return key(value)
end
function C.covers(available,required)
    local x,y=words(available),words(required)
    for i=1,WORDS do if bit.band(x[i],y[i])~=y[i] then return false end end
    return true
end
function C.mask(required)local mask=C.none;for id in pairs(required)do mask=C.union(mask,C.bit(id))end;return mask end
function C.family(kind,options)
    local mask=C.none
    for id,option in ipairs(options)do for _,native in ipairs(option.ids)do
        if native==kind then mask=C.union(mask,C.bit(id))end
    end end
    return mask
end
function C.missions(candidates,rules,slots,options)
    local groups,unique={},{}
    for _,item in ipairs(candidates)do
        local category=item.category or 0;local mask=C.family(item.id,options)
        local key=category..':'..mask
        if not unique[key]then unique[key]=true;groups[#groups+1]={category=category,mask=mask}end
    end
    local result,seen={},{}
    local function walk(left,usage,mask)
        local parts={left,mask};for cat=0,8 do parts[#parts+1]=usage[cat] or 0 end
        local key=table.concat(parts,'|');if seen[key]then return end;seen[key]=true
        if left==0 then result[mask]=true;return end
        local categories,forced={},0
        for _,rule in ipairs(rules)do
            if rule.minimum~=0 and (usage[rule.category] or 0)<rule.minimum then forced=rule.category;break end
        end
        if #rules==0 then categories[0]=true
        elseif forced~=0 then categories[forced]=true
        else
            local available,added={},{}
            for _,group in ipairs(groups)do
                local cat=group.category;local blocked=false
                for _,rule in ipairs(rules)do if rule.category==cat then
                    blocked=rule.maximum~=0 and (usage[cat] or 0)>=rule.maximum;break
                end end
                if not blocked and not added[cat]then added[cat]=true;available[#available+1]=cat end
            end
            if #available==1 then categories[available[1]]=true
            elseif #available==0 then categories[0]=true
            else
                local positive=false
                for _,cat in ipairs(available)do for _,rule in ipairs(rules)do if rule.category==cat then
                    categories[cat]=true;if rule.weight>0 then positive=true end;break
                end end end
                if not positive then categories={[0]=true}end
            end
        end
        local allowed={}
        for cat in pairs(categories)do
            local found=false
            for i,group in ipairs(groups)do if cat==0 or group.category==cat then allowed[i]=true;found=true end end
            -- The native chooser falls back to all candidates for an empty category.
            if not found then for i in ipairs(groups)do allowed[i]=true end end
        end
        if not next(allowed)then result[mask]=true;return end
        for i in pairs(allowed)do
            local group=groups[i];local cat=group.category
            usage[cat]=(usage[cat] or 0)+1
            walk(left-1,usage,C.union(mask,group.mask))
            usage[cat]=usage[cat]-1
        end
    end
    walk(slots,{},C.none);return result
end
function C.modifiers(pool,budget)
    local results={}
    local function walk(remaining,left,chosen)
        local options={};for i,m in ipairs(remaining)do if m.cost<=left then options[#options+1]=i end end
        if #chosen==2 or #options==0 then
            local copy={};for _,id in ipairs(chosen)do copy[#copy+1]=id end;results[#results+1]=copy;return
        end
        for _,index in ipairs(options)do
            local rest={};for i,m in ipairs(remaining)do if i~=index then rest[#rest+1]=m end end
            chosen[#chosen+1]=remaining[index].id
            walk(rest,left-remaining[index].cost,chosen);chosen[#chosen]=nil
        end
    end
    walk(pool,budget,{});return results
end
function C.possible(profiles,required,rules)
    local mask=C.mask(required)
    for _,profile in ipairs(profiles)do
        local valid=true;local present={}
        for _,id in ipairs(profile.modifiers)do present[id]=true end
        for id,mode in pairs(rules or {})do
            if (mode=='require' and not present[id])or(mode=='exclude' and present[id])then valid=false;break end
        end
        if valid then for available in pairs(profile.masks)do
            if C.covers(available,mask)then return true end
        end end
    end
    return false,'Incompatible with selected missions or modifier rules'
end
return C
