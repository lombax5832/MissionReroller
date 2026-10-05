-- Filter rules (src/filter_rules.lua): copied and normalised once, counted,
-- keyed and checked.
-- Usage: luajit tests/test_filter_rules.lua <src folder>
local root=arg[1]
local Rules=dofile(root..'/filter_rules.lua');local options=dofile(root..'/search_session.lua').options
local spores=0x1101e25c
-- Copied once: later edits of the request do not reach the rules.
local request={required={[1]=true},excluded={[3]=true},modifiers={[spores]='require'},
    constellations={groups={[1]={[2]='accept'}}},objectives={groups={[1]={[7]='require'}}},time='night',
    difficulty=10,scope={region=1},limit=5}
local r=Rules.new(request)
request.required[2]=true;request.excluded[4]=true;request.modifiers[spores]='exclude'
request.constellations.groups[1][2]='exclude';request.objectives.groups[1][8]='exclude'
assert(not r.required[2] and not r.excluded[4] and r.modifiers[spores]=='require','Sets are copied')
assert(r.constellations.groups[1][2]=='accept' and not r.objectives.groups[1][8],'Groups are copied')
assert(r.time=='night' and r.difficulty==nil and r.scope==nil and r.limit==nil,'Only the Filters')
-- Normalised: nothing chosen is nil, and an empty group is no rule.
local empty=Rules.new({excluded={},constellations={groups={[0]={}}},objectives={groups={}}})
assert(next(empty.required)==nil and next(empty.modifiers)==nil,'Required and modifiers are always sets')
assert(empty.excluded==nil and empty.constellations==nil and empty.objectives==nil and empty.time==nil)
local kept=Rules.new({required={[1]=true},constellations={groups={[0]={},[1]={[2]='exclude'}}}})
assert(kept.constellations.groups[0]==nil and kept.constellations.groups[1][2]=='exclude')
-- Counted as the panel counts: one per mission, rule, tag, row and the time.
local n,kinds=r:count()
assert(n==6 and kinds.required==1 and kinds.excluded==1 and kinds.modifiers==1 and kinds.constellations==1
    and kinds.objectives==1 and kinds.time==1,n)
assert(empty:count()==0 and Rules.new({constellations={groups={[0]={[2]='accept',[4]='exclude'}}}}):count()==2)
-- Seeded when tags or objectives must be predicted.
assert(r:seeded() and not empty:seeded() and not Rules.new({required={[1]=true},time='day'}):seeded())
assert(Rules.new({objectives={groups={[0]={[7]='exclude'}}}}):seeded())
-- Keyed: equal rules give equal text, whatever the order or empty parts.
local a=Rules.new({required={[1]=true,[2]=true},modifiers={[spores]='exclude'},excluded={}})
local b=Rules.new({modifiers={[spores]='exclude'},required={[2]=true,[1]=true},constellations={groups={[1]={}}}})
assert(a:key()==b:key(),a:key()..' ~= '..b:key())
for _,other in ipairs({{required={[1]=true}},{required={[1]=true,[2]=true},modifiers={[spores]='require'}},
    {required={[1]=true,[2]=true},modifiers={[spores]='exclude'},time='day'},
    {required={[1]=true,[2]=true},modifiers={[spores]='exclude'},excluded={[3]=true}},
    {required={[1]=true,[2]=true},modifiers={[spores]='exclude'},constellations={groups={[1]={[2]='accept'}}}},
    {required={[1]=true,[2]=true},modifiers={[spores]='exclude'},objectives={groups={[1]={[7]='require'}}}}})do
    assert(Rules.new(other):key()~=a:key(),Rules.new(other):key())
end
-- Checked against the mission families, with the search's messages.
r:check(options);empty:check(options)
local function refused(t,why)
    local ok,err=pcall(Rules.check,Rules.new(t),options)
    assert(not ok and tostring(err):find(why,1,true),tostring(err))
end
refused({required={[999]=true}},'Invalid mission filter')
refused({required={[1]='require'}},'Invalid mission filter')
refused({required={[1]=true},excluded={[1]=true}},'Invalid excluded mission')
refused({excluded={[999]=true}},'Invalid excluded mission')
refused({modifiers={[spores]='accept'}},'Invalid modifier rule')
refused({modifiers={[-1]='require'}},'Invalid modifier rule')
refused({required={[1]=true},constellations={groups={[3]={[2]='accept'}}}},'Invalid constellation group')
refused({required={[1]=true},constellations={groups={[0]={[2]='accept'}}}},'Invalid constellation group')
refused({constellations={groups={[0]={[32]='accept'}}}},'Invalid constellation rule')
refused({constellations={groups={[0]={[2]='require'}}}},'Invalid constellation rule')
refused({required={[1]=true},objectives={groups={[2]={[7]='require'}}}},'Invalid side objective group')
refused({objectives={groups={[0]={[7]='accept'}}}},'Invalid side objective rule')
refused({required={[1]=true,[2]=true,[3]=true,[4]=true}},'Select missions')
print('Filter rules: copy, normalisation, count, seeded, key and check passed')
