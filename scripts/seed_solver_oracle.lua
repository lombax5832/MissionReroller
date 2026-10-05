-- Usage: luajit seed_solver_oracle.lua tables  <src> <capture oracle> <out.json>
--        luajit seed_solver_oracle.lua predict <src> <capture oracle> <seeds.txt> <out.json>
-- Research oracle for scripts/seed_solver.py. It replays a saved campaign
-- capture (artifacts/level-capture-oracle.lua) through the real prediction
-- modules in src: `tables` exports the frozen per-operation decision inputs
-- the solver inverts, `predict` writes the complete predicted board for each
-- campaign seed so solved seeds are checked by the mod's own predictor.
local mode,root,capture=arg[1],arg[2],arg[3]
assert((mode=='tables' and arg[4]) or (mode=='predict' and arg[5]),'Usage: tables|predict <src> <capture> ...')
local here=(arg[0]:match('^(.*[/\\])') or '')
local C=dofile(here..'seed_solver_capture.lua')(here,root,capture)
local json,write,board_of,planet,case=C.json,C.write,C.board_of,C.planet,C.case
local SideObjectives,Constellations,m=C.SideObjectives,C.Constellations,C.m

if mode=='predict' then
    local out={}
    for line in io.lines(arg[4])do
        local seed=tonumber(line)
        if seed then out[#out+1]='{"seed":'..string.format('%d',seed)..',"operations":'..json(board_of(seed))..'}' end
    end
    write(arg[5],'['..table.concat(out,',\n')..']\n')
    return
end

local solver,identity=C.solver_inputs()
local seeded=solver.seeded
local operations={}
for _,op in ipairs(solver.operations)do
    local templates={}
    for i,t in ipairs(op.templates)do
        local weights={}
        for id,weight in pairs(t.weights)do weights[#weights+1]={id,weight}end
        table.sort(weights,function(a,b)return a[1]<b[1]end)
        templates[i]={index=t.index,weight=t.weight,modifiers=t.modifiers,candidates=t.candidates,weights=weights,rules=t.rules}
    end
    local categories={}
    for id,category in pairs(op.category_of)do categories[#categories+1]={id,category}end
    table.sort(categories,function(a,b)return a[1]<b[1]end)
    local entry={difficulty=op.difficulty,id=op.id,category=op.category,faction=op.faction,budget=op.budget,total=op.total,
        templates=templates,levels=op.levels,special=op.special,extra=op.extra,mission_categories=categories,effect_id=op.effect_id}
    if seeded then
        local kinds={}
        for _,info in pairs(op.kind_of)do kinds[#kinds+1]=info end
        table.sort(kinds,function(a,b)return a.kind<b.kind end)
        local banned={}
        for id in pairs(op.context.banned)do banned[#banned+1]=id end
        table.sort(banned)
        entry.kinds,entry.initial_tags,entry.counts=kinds,op.initial_tags,op.counts
        entry.context={banned=banned,extra=op.context.extra,modifiers=op.context.modifiers}
    end
    operations[#operations+1]=entry
end
local objectives,disabled_tags={},{}
for id,r in pairs(solver.records)do
    objectives[#objectives+1]={pool_id=id,id=r.id,cap=r.cap,minimum=r.minimum,maximum=r.maximum,mask=r.mask,
        environments=r.environments,disabled=r.disabled}
end
table.sort(objectives,function(a,b)return a.pool_id<b.pool_id end)
for tag in pairs(solver.disabled_tags)do disabled_tags[#disabled_tags+1]=tag end
table.sort(disabled_tags)
-- The filter rows (side_objective_prediction.lua R.rows): id -> row key, name.
local rows={}
for id,row in pairs(SideObjectives.row_of)do rows[#rows+1]={id=id,row=row,name=SideObjectives.names[row]}end
table.sort(rows,function(a,b)return a.id<b.id end)
local tag_names={}
for tag,name in pairs(Constellations.names)do tag_names[#tag_names+1]={tag,name}end
-- Mission family names by kind (search_session.lua options).
local kind_names={}
for _,option in ipairs(m.options)do for _,id in ipairs(option.ids)do kind_names[#kind_names+1]={id,option.name}end end
table.sort(operations,function(a,b)return a.difficulty*100+a.id<b.difficulty*100+b.id end)
local specials={}
for i,event in ipairs(identity.specials or {})do specials[i]={id=event.id,minimum=event.minimum,maximum=event.maximum}end
local active=identity.active
if active and active.planet==planet then active={row=active.row,id=active.id,seed=active.seed,difficulty=active.difficulty}else active=nil end
write(arg[4],json({planet=planet,active=active,capture_seed=case.seed,pool_count=identity.pool_count,max_difficulty=identity.max_difficulty,
    specials=specials,operations=operations,objectives=objectives,disabled_tags=disabled_tags,
    objective_rows=rows,tag_names=tag_names,kind_names=kind_names})..'\n')
print(string.format('seed_solver_oracle: %d operations exported for planet %d%s',#operations,planet,
    seeded and ', with enemy tags and side objectives' or ', missions only (the capture lacks tag and objective inputs)'))
