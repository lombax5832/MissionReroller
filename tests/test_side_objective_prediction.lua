-- Usage: luajit test_side_objective_prediction.lua <src>
-- The side-objective port on small hand-made pools: minimum entries and the
-- primary, slot counts and the category scale, caps, shared mask bits, the
-- filters before a draw, the extra objective and the filter rows. Exact
-- agreement with the game is scripts/validate_side_objectives.py's job.
local root=assert(arg[1])
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local R=H.module(root..'/side_objective_prediction.lua')
local function record(id,extra)
    local r={id=id,cap=1,minimum=0,maximum=0,mask=0,environments={0,0,0,0}}
    for k,v in pairs(extra or {})do r[k]=v end
    return r
end
local records={}
local function inputs(extra)
    local i={objective=function(id)return records[id] or record(0,{cap=0})end,disabled=function()return false end,
        context={banned={},modifiers={}},environment=function()return 1 end}
    for k,v in pairs(extra or {})do i[k]=v end
    return i
end
local function entry(id,role,extra)
    local e={id=id,weight=1,group=0,role=role,minimum=0,maximum=1}
    for k,v in pairs(extra or {})do e[k]=v end
    return e
end
local function mission(pool,extra)
    local m={category=1,lo=1,hi=1,pool={},biomes={0}}
    for i=1,32 do m.pool[i]=pool[i] or entry(0,0,{weight=0})end
    for k,v in pairs(extra or {})do m[k]=v end
    return m
end
local function roles(list)
    local n={}
    for _,o in ipairs(list)do n[o.role]=(n[o.role] or 0)+1 end
    return n
end
local counts={side=2,tactical=1,substeps=0}
-- Ids 1..6 side, 7..9 tactical; every record allows one copy.
for id=1,9 do records[id]=record(id)end
records[100]=record(100,{cap=4});records[101]=record(101,{cap=4})
local sides={entry(100,0,{minimum=1})}
for id=1,6 do sides[#sides+1]=entry(id,3)end
for id=7,9 do sides[#sides+1]=entry(id,2)end
local base=mission(sides)
for seed=0,200 do
    local list=R.resolve(seed*2654435761%4294967296,6,base,counts,nil,inputs())
    local n=roles(list)
    assert(list[1].id==100 and list[1].role==0 and n[0]==1,'The primary comes first')
    assert(n[3]==2 and n[2]==1,'Two side and one tactical objective')
    local seen={}
    for _,o in ipairs(list)do assert(not seen[o.id],'A capped objective is drawn once');seen[o.id]=true end
end
-- The same seed gives the same objectives.
local a,b=R.resolve(12345,6,base,counts,nil,inputs()),R.resolve(12345,6,base,counts,nil,inputs())
assert(R.describe(a)==R.describe(b),'Deterministic')
-- A category scale of 0 removes the side objectives; 1 keeps them.
assert(roles(R.resolve(7,6,base,counts,0,inputs()))[3]==nil,'Scaled to no side objectives')
assert(roles(R.resolve(7,6,base,counts,1,inputs()))[3]==2,'Scale 1')
-- Without a minimum the first primary entry still appears once.
local plain=mission({entry(100,0),entry(1,3)})
local list=R.resolve(3,6,plain,{side=1,tactical=0,substeps=0},nil,inputs())
assert(list[1].id==100 and list[2].id==1 and #list==2,'Primary added once')
-- Difficulty zero draws nothing.
assert(#R.resolve(3,0,plain,counts,nil,inputs())==0)
-- A shared mask bit allows only one of the two.
records[20]=record(20,{mask=1});records[21]=record(21,{mask=1})
local masked=mission({entry(100,0,{minimum=1}),entry(20,3),entry(21,3)})
for seed=1,50 do
    local n=roles(R.resolve(seed,6,masked,{side=2,tactical=0,substeps=0},nil,inputs()))
    assert(n[3]==1,'Mask bits exclude each other')
end
-- Repeats up to the cap: one entry with cap 3 fills three slots.
records[30]=record(30,{cap=3})
local repeated=mission({entry(100,0,{minimum=1}),entry(30,3,{maximum=4})})
assert(roles(R.resolve(9,6,repeated,{side=4,tactical=0,substeps=0},nil,inputs()))[3]==3,'Capped repeats')
-- Filters: difficulty range, configuration, world-modifier bans, environments.
records[40]=record(40,{minimum=8});records[41]=record(41);records[42]=record(42);records[43]=record(43,{environments={4,0,0,0}})
local filtered=mission({entry(100,0,{minimum=1}),entry(40,3),entry(41,3),entry(42,3),entry(43,3),entry(1,3)})
local rules=inputs({disabled=function(id)return id==41 end,context={banned={[42]=true},modifiers={}},environment=function()return 1 end})
for seed=1,40 do
    local got=R.resolve(seed,6,filtered,{side=4,tactical=0,substeps=0},nil,rules)
    for _,o in ipairs(got)do assert(o.id==100 or o.id==1,'Only the allowed side objective: '..o.id)end
end
local hive=inputs({environment=function()return 4 end})
local found=false
for _,o in ipairs(R.resolve(5,6,mission({entry(100,0,{minimum=1}),entry(43,3)}),{side=1,tactical=0,substeps=0},nil,hive))do
    if o.id==43 then found=true end
end
assert(found,'An environment-limited objective on its environment')
-- The environment is read only when an objective is limited to one.
local asked=0
R.resolve(5,6,base,counts,nil,inputs({environment=function()asked=asked+1;return 1 end}))
assert(asked==0,'No environment read without a limited objective')
-- The flag appends its tactical objective last.
local flagged=R.resolve(5,6,base,counts,nil,inputs({context={banned={},modifiers={},extra=true}}))
assert(flagged[#flagged].id==0x68bfbb59 and flagged[#flagged].role==2)
-- Sub-steps: lo..hi blends the minimum and maximum totals.
records[50]=record(50,{cap=4})
local steps=mission({entry(100,0,{minimum=1}),entry(50,1,{minimum=1,maximum=4})},{lo=1,hi=10})
local function substeps(d,min)
    local n=0
    for _,o in ipairs(R.resolve(77,d,steps,{side=0,tactical=0,substeps=min},nil,inputs()))do if o.id==50 then n=n+1 end end
    return n
end
-- The primary and the sub-step make totals of 2 and 5; at most the row's
-- minimum, here 4. roundf((1-t)*2+5*t): t=4/9 gives 3.33, t=5/9 gives 3.67.
assert(substeps(1,4)==1 and substeps(10,4)==3,'Range ends')
assert(substeps(5,4)==2 and substeps(6,4)==3,'Rounded to nearest')
assert(substeps(10,2)==1,'At most the difficulty row minimum')
-- Rows: one per title, keyed by the first id; set() keeps side and tactical.
assert(#R.rows>=30,'Every titled objective has a row')
local keys={}
for _,row in ipairs(R.rows)do
    assert(row.id==row.ids[1] and R.names[row.id]==row.name and not keys[row.name],row.name);keys[row.name]=true
    for _,id in ipairs(row.ids)do assert(R.row_of[id]==row.id)end
end
assert(R.names[R.row_of[0x86cfeedb]]=='SEAF Artillery' and R.names[R.row_of[0xf1969b14]]=='Lidar Station')
assert(R.row_of[0xf86cb0fc]==R.row_of[0xb34e46ea],'Both anti-air emplacements are one row')
local set=R.set({{id=0x86cfeedb,role=3},{id=0xf1969b14,role=0},{id=0x4c10b12e,role=2},{id=0x12345678,role=3}})
assert(set[0x86cfeedb] and set[0x4c10b12e] and not set[0xf1969b14],'Side and tactical rows only')
assert(R.describe({{id=0x86cfeedb,role=3},{id=0x12345678,role=1}})=='SEAF Artillery/3, 12345678/1')
print('Side objective prediction: primary and minimum entries, slots, scale, caps, mask bits, filters, environment, flag, sub-step rounding and rows passed')
