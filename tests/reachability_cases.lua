-- Recorded requests for the dialog's reachability check
-- (tests/check_seed_solver_search.lua with a case name; capture under
-- artifacts/<name>/capture.lua, made with scripts/check_live_planet.py).
-- accept: enemy-force tags accepted per mission; exclude_objectives: side
-- objectives excluded on every mission, by name; refused: the options the
-- dialog must disable, '<mission>:<tag|objective>:<id>:<mode>'.
return {
    -- 2026-10-05, planet 268, difficulty 10. In game, Search and Destroy with
    -- Light Bugs accepted and these objectives excluded logged
    -- SEED_SOLVER_OFF reason=no draw path and scanned 261,043 seeds in vain.
    ['planet-268']={difficulty=10,required={'Geological Survey','Spread Democracy','Search and Destroy'},
        accept={['Geological Survey']={3},['Spread Democracy']={3}},
        exclude_objectives={'Lidar Station','SEAF Artillery'},
        refused={'Search and Destroy:tag:6:accept','Search and Destroy:tag:7:accept','Search and Destroy:tag:8:accept'}},
}
