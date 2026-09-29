-- Pure predicate from 11e6800. The caller resolves dynamic enable overrides
-- and the planet's positive-weight environment entries before invoking it.
return function(mission,context,category)
    if mission.faction~=0 and mission.faction~=context.faction then return false end
    if context.difficulty<mission.minimum or context.difficulty>mission.maximum then return false end
    if category~=0 and mission.category~=category then return false end
    if not context.environment_present or not mission.enabled then return false end
    local allowed=assert(mission.biomes,'Missing mission biome restrictions')
    if allowed[1]==0 then return true end
    for _,biome in ipairs(context.biomes)do
        for _,legal in ipairs(allowed)do
            if legal==0 or legal==biome then return true end
        end
    end
    return false
end
