-- Know Your Constellation's roster (src/vendor/know_your_constellation, its
-- v4.0 roster.lua and roster_data.lua, included with CowboyBingus's
-- permission) as the roster api 1 that src/unit_forecast.lua reads from
-- EnemyIntelligence.roster. Used only when no installed Know Your
-- Constellation exports one. Pure: the build passes the two vendored modules.
local _,roster,data=...
local R={api=1,build=data.build,revision='v4.0',source='bundled'}
local forecasts=roster.new(data)
-- Know Your Constellation's resolve.from_native: its authored tag IDs stayed
-- put when build 25480438 inserted native tag 1.
function R.from_native(tag)
    assert(tag>=0 and tag<=31,'Unknown native enemy tag')
    if tag==1 then return 31 end
    return tag>1 and tag-1 or 0
end
-- forecast({faction, difficulty, tags}, zone, war) -> {large={{name, ticks}}, small={name}},
-- names as the roster's English display names.
function R.forecast(snapshot,zone,war)
    local report=forecasts:report(snapshot,zone,war)
    local large,small={},{}
    for i,entry in ipairs(report.large)do large[i]={name=data.names[entry[1]][1],ticks=entry[2]}end
    for i,index in ipairs(report.small)do small[i]=data.names[index][1]end
    return {large=large,small=small}
end
return R
