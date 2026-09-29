-- Enemy-tag resolution order of 177dd80: initial tags, weighted base draws and
-- fallback (1758000), conditional HordeOnly and mission exclusions (177deb0),
-- then configuration exclusions. Tags are native indices. No reads or writes.
local ffi,bit=require('ffi'),require('bit')
local single=ffi.new('float[1]')
local function f(n)single[0]=n;return tonumber(single[0])end
local R={}
R.names={[1]='Horde Only (HordeOnly)',[2]='Bile Bugs (BugAcid)',[3]='Armored Bugs (BugArmored)',
    [4]='Hunter Swarms (BugPredators)',[5]='Flyers (BugFlyers)',[6]='Light Bugs (BugFodder)',
    [7]='Nursing Spewers (BugCrawlers)',[8]='Mixed Terminids (BugBalanced)',
    [9]='Predator Strain (GM_BugSuperPredators)',[10]='Gloom Strain (GM_BugGloom)',
    [11]='Rupture Strain (GM_BugBurrowers)',[12]='Dragonroaches (GM_BugDragon_Traveler)',
    [13]='Shriekers (GM_BugShrieker_Traveler)',[14]='Assault Forces (BotAssault)',
    [15]='Phalanx Forces (BotPhalanx)',[16]='Artillery Forces (BotArtillery)',[17]='Air Forces (BotAir)',
    [18]='Armored Column (BotPanzer)',[19]='Mixed Automatons (BotBalanced)',
    [20]='Jet Brigade (GM_BotAssault)',[21]='Cyborgs (GM_BotCyborgs)',
    [22]='Gunships (GM_BotGunships_Traveler)',[23]='Incineration Corps (GM_IvoryLegion)',
    [24]='Hive Lord (GM_BugHiveLord)',[25]='Stragglers (IlluminateStraggler)',
    [26]='War Machine (GM_IlluminateWarmachine_Traveler)',[27]='Engineers (GM_IlluminateEngineers)',
    [28]='Invasion (GM_IlluminateInvasion)',[29]='Harvest (GM_IlluminateHarvest)',
    [30]='Body Horror (GM_IlluminateBodyHorror)',[31]='SEAF Support (GM_SEAF)'}
local function find(tags,tag)for i=1,#tags do if tags[i]==tag then return i end end end
local function remove(tags,i)tags[i]=tags[#tags];tags[#tags]=nil end
function R.add(tags,tag)
    assert(type(tag)=='number' and tag>=0 and tag<32 and tag==math.floor(tag),'Invalid enemy tag')
    -- Native keeps at most 16 distinct tags and ignores overflow.
    if not find(tags,tag) and #tags<16 then tags[#tags+1]=tag end
end
function R.base(tags,seed,settings)
    assert(type(seed)=='number' and seed>=0 and seed<=4294967295 and seed==math.floor(seed),'Invalid mission seed')
    assert(settings.draws>=0 and settings.draws<=16 and settings.draws==math.floor(settings.draws),'Invalid draw count')
    -- The only-when-empty test uses the tag count before any draw.
    local pool,total,empty={},0,#tags==0
    for _,row in ipairs(settings.candidates)do
        if row.id~=0 and (not row.only_when_empty or empty)then
            assert(row.weight>=0 and row.weight<math.huge,'Invalid constellation weight')
            pool[#pool+1]=row;total=f(total+row.weight)
        end
    end
    local state=ffi.new('uint64_t',seed)
    for _=1,settings.draws do
        if #pool==0 or total<=0 then break end
        state=state*6364136223846793005ULL+1442695040888963407ULL
        local target=f(f(f(tonumber(bit.rshift(state,32)))*f(1/4294967296))*total)
        local sum=0
        for _,row in ipairs(pool)do
            sum=f(sum+row.weight)
            if target<=sum then R.add(tags,row.id);break end
        end
    end
    if settings.fallback~=0 and not find(tags,settings.fallback)then
        for _,blocker in ipairs(settings.blockers)do
            if blocker==0 then break end
            if find(tags,blocker)then return end
        end
        R.add(tags,settings.fallback)
    end
end
function R.resolve(seed,settings,initial,mission,disabled)
    local tags={}
    for _,tag in ipairs(initial)do R.add(tags,tag)end
    R.base(tags,seed,settings)
    if mission.horde then R.add(tags,1)end
    for _,tag in ipairs(mission.exclusions)do
        local i=find(tags,tag);if i then remove(tags,i)end
    end
    local i=1
    while i<=#tags do if disabled(tags[i])then remove(tags,i)else i=i+1 end end
    -- Index 0 is the native "none" entry; it occupies a slot but names nothing.
    local result={set={},list={}}
    for _,tag in ipairs(tags)do if tag~=0 then result.set[tag]=true;result.list[#result.list+1]=tag end end
    table.sort(result.list)
    return result
end
function R.describe(list)
    local names={};for _,tag in ipairs(list)do names[#names+1]=R.names[tag] or ('tag '..tag)end
    return #names>0 and table.concat(names,', ') or 'none'
end
return R
