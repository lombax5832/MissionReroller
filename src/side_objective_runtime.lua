-- Side objectives for predicted or displayed operations, and a read-only
-- observer that compares a prediction with the hovered mission's preview
-- descriptor, which carries the game's own objective list.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
local emit,read,pointer,u=host.emit,host.read,host.pointer,host.u
local reroll_session,map,O=host.reroll_session,host.map,host.O
local SideObjectives,Planet=lib.SideObjectives,lib.Planet
local Board=lib.Board
local api,game
host.when_initialized(function(n)api,game=n.api,n.game end)
local bind_objectives,observe_objectives
do
    -- A Planet.bind result: annotate(op, category, id) gives each mission
    -- its objectives (native order, objective_list) and their filter rows
    -- (objectives). Displayed operations name their category and id. The
    -- draw runs when a field is first read, so a search pays only for the
    -- missions a rule looks at.
    local function bind(model)
        local inputs,tags,planet=model.objective_inputs(),model.constellation_inputs(),model.index
        local function annotate(op,category,id)
            local context=inputs.context(planet,op.effect_id or tags.effect_id(category,id,planet))
            local counts,difficulty=inputs.counts(op.difficulty),op.difficulty
            for _,mission in ipairs(op.missions)do
                setmetatable(mission,{__index=function(m,key)
                    if key~='objectives' and key~='objective_list' then return nil end
                    local record=inputs.mission(m.native_type)
                    local environment=inputs.environments(planet,m.native_type,context.modifiers)
                    local list=SideObjectives.resolve(m.seed,difficulty,record,counts,inputs.scale(record.category),
                        {objective=inputs.objective,disabled=inputs.disabled,context=context,
                            environment=function()return environment(m.seed)end})
                    rawset(m,'objective_list',list);rawset(m,'objectives',SideObjectives.set(list))
                    return rawget(m,key)
                end})
            end
            return context
        end
        return annotate,inputs
    end
    bind_objectives=bind

    local last,seen,logged,reported=-math.huge,{},0,false
    local function hex(list)
        local parts={};for _,value in ipairs(list)do parts[#parts+1]=string.format('%08x',value)end
        return table.concat(parts,',')
    end
    local function observe()
        if not map.on_top()then return end
        local b=pointer(game+O.rva.board)
        local hovered=Board.hovered(read,b)
        if not hovered then return end
        local preview,row,seed,difficulty,kind,planet=hovered.preview,hovered.row,hovered.seed,hovered.difficulty,hovered.kind,hovered.planet
        local count=preview:byte(0x1e)
        if count>32 then return end
        local live={};for i=0,count-1 do live[#live+1]=u(preview,0x20+i*4)end
        local modifiers={};for i=0,math.min(preview:byte(0xc8),8)-1 do modifiers[#modifiers+1]=u(preview,0xc8+i*4)end
        local key=seed..':'..kind..':'..difficulty..':'..u(preview,12)..':'..hex(live)
        if seen[key]then return end
        seen[key]=true;logged=logged+1
        local annotate=bind(Planet.bind(read,u,api.pointer,game,b,planet))
        local predicted={difficulty=difficulty,missions={{native_type=kind,seed=seed}}}
        local context=annotate(predicted,hovered.category,hovered.operation_id)
        local ids={};for _,o in ipairs(predicted.missions[1].objective_list)do ids[#ids+1]=o.id end
        emit(string.format('SIDE_OBJECTIVE_CHECK planet=%d row=%d type=%d seed=%u difficulty=%d modifiers=[%s] predicted_modifiers=[%s] predicted=[%s] live=[%s] modifiers_agree=%s agree=%s',
            planet,row,kind,seed,difficulty,hex(modifiers),hex(context.modifiers),SideObjectives.describe(predicted.missions[1].objective_list),
            hex(live),tostring(hex(modifiers)==hex(context.modifiers)),tostring(hex(ids)==hex(live))))
    end
    -- Diagnostics must never stop the mod or interrupt a search.
    observe_objectives=function(now)
        if now-last<0.5 or logged>=64 or reroll_session.view().running then return end
        last=now
        local ok,err=pcall(observe)
        if not ok and not reported then reported=true;emit('SIDE_OBJECTIVE_CHECK_BLOCKED '..tostring(err))end
    end
end
emit('Side objectives: require or exclude per checked mission, else for the operation; hover a mission to log SIDE_OBJECTIVE_CHECK')
return {bind_objectives=bind_objectives,observe_objectives=observe_objectives}
