-- Usage: luajit test_seed_solver_paths.lua <src> <capture> <expected.lua>
-- Replays a saved capture (scripts/seed_solver_capture.lua) and checks
-- src/seed_solver_paths.lua:
-- 1. its step-wise enemy-tag and side-objective draws resolve every mission
--    kind of every operation exactly as constellation_prediction.lua and
--    side_objective_prediction.lua do, on random mission seeds;
-- 2. its draw paths for each filter equal the Python prototype's
--    (scripts/seed_solver.py), written by tests/test_seed_solver_lua.py.
local root,capture,expected=arg[1],arg[2],dofile(arg[3])
local here=(arg[0]:match('^(.*[/\\])') or '')
local C=dofile(here..'../scripts/seed_solver_capture.lua')(here..'../scripts/',root,capture)
local H=C.H
local solver=C.solver_inputs()
local Paths=H.module(root..'/seed_solver_paths.lua')(H.module(root..'/mission_category_choice.lua'),
    H.module(root..'/mission_weighted_choice.lua'),H.module(root..'/operation_finalization.lua'))
local P=Paths.new({records=solver.records,row_of=C.SideObjectives.row_of,disabled_tags=solver.disabled_tags})
local Rng=H.module(root..'/generation_rng.lua')

-- 1. Forward resolution against the predictor's modules.
local resolved=0
if solver.seeded then
    local tags,objectives=C.model.constellation_inputs(),C.model.objective_inputs()
    local state=25480438
    local function random()state=(state*1103515245+12345)%4294967296;return state end
    for _,op in ipairs(solver.operations)do
        local context=objectives.context(C.planet,op.effect_id)
        for kind,info in pairs(op.kind_of)do
            local record=tags.mission(kind)
            local srecord=objectives.mission(kind)
            local pick=objectives.environments(C.planet,kind,context.modifiers)
            for _=1,8 do
                local seed=random()
                local env=pick(seed)
                if info.settings then
                    local want=C.Constellations.resolve(seed,info.settings,op.initial_tags,record,tags.disabled).set
                    local rng=Rng(seed)
                    local got=P.tags(info,op.initial_tags,seed,function()return rng:next()end)
                    for t in pairs(want)do assert(got[t],string.format('kind %d seed %d: tag %d missing',kind,seed,t))end
                    for t in pairs(got)do assert(want[t],string.format('kind %d seed %d: extra tag %d',kind,seed,t))end
                end
                local want=C.SideObjectives.resolve(seed,op.difficulty,srecord,op.counts,objectives.scale(srecord.category),
                    {objective=objectives.objective,disabled=objectives.disabled,context=context,
                        environment=function()return env end})
                local rng=Rng(seed)
                local got=P.objectives.resolve(info,op.difficulty,op.counts,op.context,env,function()return rng:next()end)
                assert(#got==#want,string.format('kind %d seed %d: %d objectives, expected %d',kind,seed,#got,#want))
                for i,o in ipairs(want)do
                    assert(got[i][1]==o.id and got[i][2]==o.role,string.format('kind %d seed %d: objective %d differs',kind,seed,i))
                end
                resolved=resolved+1
            end
        end
    end
end

-- 2. Draw paths against the Python prototype's.
local function text(path)
    local parts={}
    for _,s in ipairs(path.constraints)do
        local t=string.format('%s:%d:%s:%s',s.kind,s.position,tostring(s.lo),tostring(s.hi))
        if s.mission then
            local draws={}
            for p,r in pairs(s.mission.draws)do draws[#draws+1]={p,r}end
            table.sort(draws,function(a,b)return a[1]<b[1]end)
            local d={}
            for _,x in ipairs(draws)do d[#d+1]=string.format('%d=%d-%d',x[1],x[2][1],x[2][2])end
            local mods={}
            for _,m in ipairs(s.mission.mods)do mods[#mods+1]=string.format('%d:%d-%d',m[1],m[2],m[3])end
            t=t..'['..table.concat(d,',')..'|'..table.concat(mods,',')..']'
        end
        parts[#parts+1]=t
    end
    return table.concat(parts,';')
end
local compared=0
for _,f in ipairs(expected.filters)do
    local paths=assert(P.shared_paths(solver.operations,f.difficulty,f.required,f.rules),'paths differ by operation ID')
    local got={}
    for i,path in ipairs(paths)do got[i]=text(path)end
    table.sort(got)
    local want={unpack(f.paths)}
    table.sort(want)
    assert(#got==#want,string.format('%s: %d paths, expected %d',f.name,#got,#want))
    for i=1,#want do assert(got[i]==want[i],string.format('%s: path differs\n  lua    %s\n  python %s',f.name,got[i],want[i]))end
    compared=compared+#want
end
print(string.format('test_seed_solver_paths: passed (planet %d: %d missions resolved, %d paths in %d filters)',
    C.planet,resolved,compared,#expected.filters))
