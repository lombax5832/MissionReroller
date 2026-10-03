-- Helpers for LuaJIT tests of an assembled entry.
-- Load with: local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local H={}

-- The closure variable `name` of fn; with set, replaces it by value.
function H.up(fn,name,value,set)
    for i=1,255 do
        local k,v=debug.getupvalue(fn,i)
        if k==name then if set then debug.setupvalue(fn,i,value)end;return v end
        if not k then break end
    end
    error('Missing upvalue '..name,2)
end

-- Hands the adapter and every runtime the native handles (api, game, ffi,
-- kernel, user32) as the adapter's initialize() would on the first frame,
-- without running it. The runtimes see nil for a key left out.
function H.natives(update,natives)
    local initialize=H.up(H.up(H.up(update,'tick'),'prepare'),'initialize')
    for i=1,255 do
        local k=debug.getupvalue(initialize,i)
        if not k then break end
        if natives[k]~=nil then debug.setupvalue(initialize,i,natives[k])end
        if k=='initialized' then debug.setupvalue(initialize,i,true)end
    end
    -- The module bases the offsets' code entries are checked against.
    local bases=H.up(initialize,'bases')
    bases.game,bases.exe=natives.game,natives.exe
    for _,bind in ipairs(H.up(initialize,'binders'))do bind(natives)end
end

-- The numbers of src/offsets.lua (src/offset_values.lua) for a src folder,
-- as the build creates O; the table itself is the second value.
local numbers={}
function H.offsets(src)
    if not numbers[src]then
        local offsets=dofile(src..'/offsets.lua')
        numbers[src]={dofile(src..'/offset_values.lua')(offsets),offsets}
    end
    return numbers[src][1],numbers[src][2]
end

-- A module file of src run as the build runs it: its chunk argument is O.
function H.module(path)
    local src=assert(path:match('^(.*)[/\\][^/\\]+$'),'module path needs a folder')
    return assert(loadfile(path))((H.offsets(src)))
end

-- The planet model (src/planet_model.lua) built from the modules in src, as
-- build_identity_probe.source() builds it for the release. Entries of
-- `replace` override a module; the table of modules is the second value.
function H.planet_model(src,replace)
    local function module(name)return H.module(src..'/'..name..'.lua')end
    local rng=module('generation_rng')
    local m={rng=rng,identity=module('operation_identity')(rng),special_inputs=module('special_operation_inputs'),
        levels=module('level_inputs'),level_choice=module('mission_level_choice'),config=module('configuration_lookup'),
        effects=module('campaign_effects'),eligible=module('mission_eligibility'),category=module('mission_category_choice'),
        finalizer=module('operation_finalization'),mission_choice=module('mission_weighted_choice'),
        environments=module('template_environments'),composition_inputs=module('composition_inputs'),
        composition_prediction=module('composition_prediction'),capture=module('composition_capture'),
        base_inputs=module('operation_base_inputs'),predictor=module('candidate_predictor'),
        constellation_inputs=module('constellation_inputs'),catalogue=module('filter_catalogue'),
        compatibility=module('mission_compatibility'),options=module('search_session').options,
        labels=module('constellation_prediction').names,objective_inputs=module('side_objective_inputs'),
        objectives=module('side_objective_prediction')}
    for key,value in pairs(replace or {})do m[key]=value end
    return module('planet_model')(m),m
end

return H
