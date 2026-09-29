-- Choice portion of 11e6020. Graph decoding is isolated in level_inputs.lua.
return function(levels,special,slot,used,rng)
    assert(type(slot)=='number' and slot>=0 and slot==math.floor(slot),'Invalid mission slot')
    assert(#levels<=16,'Level candidate capacity exceeded')
    if slot>=#levels then return nil end
    local index=slot
    if special and slot~=0 then
        index=rng:index(#levels)
        for attempt=0,#levels-1 do
            -- Native retries add the attempt to the previous index, not the
            -- original draw; preserve this cumulative progression exactly.
            index=(index+attempt)%#levels
            local taken=false
            for _,level in ipairs(used)do if levels[index+1]==level then taken=true;break end end
            if not taken then break end
        end
    end
    return levels[index+1]
end
