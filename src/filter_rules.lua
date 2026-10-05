-- Filter rules: the Filters of one request as one value, built once and
-- passed whole to the catalogue checks (src/filter_catalogue.lua), the
-- matcher (src/search_session.lua find) and the search. Pure.
-- Fields, read directly by those checks:
--   required        family -> true, the missions the operation must hold
--   excluded        family -> true, the missions it must not hold, or nil
--   modifiers       modifier id -> 'require' | 'exclude'
--   constellations  {groups={[family or 0]={tag -> 'accept' | 'exclude'}}}, or nil
--   objectives      {groups={[family or 0]={row -> 'require' | 'exclude'}}}, or nil
--   time            'day' | 'night', or nil
-- Treat a value as read-only; new copies what it is given.
local F={}
F.__index=F
local function copy(set)
    local out={};for k,v in pairs(set or {})do out[k]=v end
    return out
end
-- Rule groups without an empty group; nil when no group is left.
local function groups(value)
    local out,any={},false
    for group,rules in pairs(value and value.groups or {})do
        if next(rules)then out[group]=copy(rules);any=true end
    end
    return any and {groups=out} or nil
end
-- request: any table with the fields above (filter_request.lua to_request);
-- each may be missing.
function F.new(request)
    local excluded=request.excluded
    return setmetatable({required=copy(request.required),excluded=excluded and next(excluded) and copy(excluded) or nil,
        modifiers=copy(request.modifiers),constellations=groups(request.constellations),
        objectives=groups(request.objectives),time=request.time},F)
end
-- Raises unless every rule is well formed for options (Search.options): known
-- families, a constellation or side-objective group belonging to a required
-- family (group 0 only without one), and at most three required families.
-- The catalogue checks what a planet offers (filter_catalogue.lua validate).
function F:check(options)
    local function integer(n,lo,hi)return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi end
    local n=0
    for id,value in pairs(self.required)do
        assert(options[id] and value==true,'Invalid mission filter');n=n+1
    end
    -- Excluded families take no slot; none may also be required.
    for id,value in pairs(self.excluded or {})do
        assert(options[id] and value==true and not self.required[id],'Invalid excluded mission')
    end
    for id,mode in pairs(self.modifiers)do
        assert(integer(id,0,4294967295) and (mode=='require' or mode=='exclude'),'Invalid modifier rule')
    end
    -- Group 0 constrains the operation and is only meaningful without
    -- checked missions; every other group belongs to a checked mission.
    for group,tags in pairs(self.constellations and self.constellations.groups or {})do
        assert(integer(group,0,#options) and ((group==0 and n==0) or self.required[group]),'Invalid constellation group')
        for tag,mode in pairs(tags)do
            assert(integer(tag,1,31) and (mode=='accept' or mode=='exclude'),'Invalid constellation rule')
        end
    end
    -- Side-objective groups follow the same rule; rows are objective ids.
    for group,rows in pairs(self.objectives and self.objectives.groups or {})do
        assert(integer(group,0,#options) and ((group==0 and n==0) or self.required[group]),'Invalid side objective group')
        for row,mode in pairs(rows)do
            assert(integer(row,1,4294967295) and (mode=='require' or mode=='exclude'),'Invalid side objective rule')
        end
    end
    assert(n<=3,'Select missions, modifier rules, constellations or side objectives')
end
local function size(set)local n=0;for _ in pairs(set or {})do n=n+1 end;return n end
local function grouped(value)
    local n=0;for _,rules in pairs(value and value.groups or {})do n=n+size(rules)end
    return n
end
-- The number of rules, as the panel shows it: each required and excluded
-- mission, modifier rule, constellation, side objective and the time of
-- day counts one. The second value holds the count of each field.
function F:count()
    local kinds={required=size(self.required),excluded=size(self.excluded),modifiers=size(self.modifiers),
        constellations=grouped(self.constellations),objectives=grouped(self.objectives),time=self.time and 1 or 0}
    local n=0;for _,k in pairs(kinds)do n=n+k end
    return n,kinds
end
-- Whether constellation or side-objective rules need the missions' tags or
-- objectives predicted.
function F:seeded()return self.constellations~=nil or self.objectives~=nil end
-- Equal rules, equal text.
function F:key()
    local parts={'t'..(self.time or 'any')}
    for id in pairs(self.required)do parts[#parts+1]='m'..id end
    for id in pairs(self.excluded or {})do parts[#parts+1]='x'..id end
    for id,mode in pairs(self.modifiers)do parts[#parts+1]=string.format('o%u:%s',id,mode)end
    for group,tags in pairs(self.constellations and self.constellations.groups or {})do
        for tag,mode in pairs(tags)do parts[#parts+1]='c'..group..':'..tag..':'..mode end
    end
    for group,rows in pairs(self.objectives and self.objectives.groups or {})do
        for row,mode in pairs(rows)do parts[#parts+1]=string.format('s%d:%u:%s',group,row,mode)end
    end
    table.sort(parts);return table.concat(parts,',')
end
return F
