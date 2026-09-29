"""Build the read-only in-game validation step for the all-Lua generator port."""
from pathlib import Path
import sys
import build
import build_combined

VERSION = '0.8.0'


def source(search=False,publish=False,dialog=False):
    assert not publish or search
    assert not dialog or publish
    root = build.ROOT/'src'
    core = build.entry_path().read_text().replace('MissionReroller', 'MissionRerollerExperimentCore')
    parts = ['-- HD2-Addon: '+build_combined.MODULE,
             "if rawget(_G,'MissionRerollerExperiment') then return end",
             'local core=(function()\n'+core+'\nend)()']
    for name, file in [('make_rng', 'generation_rng.lua'), ('make_identity', 'operation_identity.lua'),
                       ('make_probe', 'identity_probe.lua'), ('make_special_inputs', 'special_operation_inputs.lua'),
                       ('make_level_inputs', 'level_inputs.lua'), ('choose_level', 'mission_level_choice.lua'),
                       ('make_level_verification', 'level_verification.lua'),
                       ('make_config', 'configuration_lookup.lua'), ('make_effects', 'campaign_effects.lua'),
                       ('mission_eligible', 'mission_eligibility.lua'), ('choose_category', 'mission_category_choice.lua'),
                       ('make_finalizer', 'operation_finalization.lua'), ('make_mission_choice', 'mission_weighted_choice.lua'),
                       ('make_environments', 'template_environments.lua'), ('make_composition_inputs', 'composition_inputs.lua'),
                       ('make_composition_prediction', 'composition_prediction.lua'), ('make_composition_capture', 'composition_capture.lua'),
                       ('make_base_inputs', 'operation_base_inputs.lua'),
                       ('sha256', 'bytes_sha256.lua')]:
        parts.append('local '+name+'=(function()\n'+(root/file).read_text()+'\nend)()')
    parts.append('local predict_identity=make_identity(make_rng)')
    parts.append('local predict_composition=make_composition_prediction(make_rng,choose_category,choose_level,make_mission_choice(make_rng),make_finalizer(make_rng))')
    parts.append('local composition_factory=make_composition_capture(make_composition_inputs,make_config,make_effects,mission_eligible,make_environments,make_level_inputs,predict_composition,make_base_inputs(predict_identity,make_special_inputs,make_environments))')
    parts.append('local on_prediction_ready,advance_prediction_search,on_search_match,on_existing_match,advance_live_publication,dialog_tick,dialog_release,validate_search_request')
    parts.append('local bind_constellations,observe_constellations')
    if dialog:
        for name,file in [('Panel','docked_panel.lua'),('Compatibility','mission_compatibility.lua'),('FilterCatalogue','filter_catalogue.lua'),('make_gate','window_mouse_gate.lua'),('make_router','modal_pointer.lua'),('window_signatures','window_signatures.lua'),
                          ('Constellations','constellation_prediction.lua'),('make_constellation_inputs','constellation_inputs.lua')]:
            parts.append('local '+name+'=(function()\n'+(root/file).read_text()+'\nend)()')
    if publish:
        for name,file in [('make_publication','seed_publication.lua'),('make_ui_selection','ui_operation_selection.lua'),
                          ('selection_signatures','selection_signatures.lua'),('verify_predicted_board','verify_predicted_board.lua')]:
            parts.append('local '+name+'=(function()\n'+(root/file).read_text()+'\nend)()')
    if search:
        for name, file in [('make_frozen_reads','frozen_prediction_reads.lua'), ('make_seed_search','seed_search.lua'),
                           ('Search','search_session.lua'), ('make_candidate_predictor','candidate_predictor.lua'),
                           ('make_prediction_job','prediction_search_job.lua')]:
            parts.append('local '+name+'=(function()\n'+(root/file).read_text()+'\nend)()')
        parts.append('local candidate_factory=make_candidate_predictor(make_composition_inputs,make_config,make_effects,mission_eligible,make_environments,make_level_inputs,make_base_inputs(predict_identity,make_special_inputs,make_environments),predict_composition)')
        parts.append('local make_search_job=make_prediction_job(make_frozen_reads,make_seed_search,Search)')
    adapter = (root/'experiment_adapter.lua').read_text()
    assert adapter.count('read_only=false') == 1
    # Prediction may inspect another planet; publication itself still requires
    # the ship/view/canonical/UI planet to agree in its own preflight.
    if publish:
        adapter=adapter.replace('read_only=false','read_only=false,preview_prediction=true')
        adapter=adapter.replace("assert(M.read_only,'Preview snapshots are read-only')","assert(M.read_only or M.preview_prediction,'Preview snapshots are read-only')")
        parts.append(adapter)
        parts.append((root/'live_publication_runtime.lua').read_text())
    else:
        parts.append(adapter.replace('read_only=false', 'read_only=true'))
    if dialog:
        parts.append((root/'constellation_runtime.lua').read_text())
    if search:
        search_runtime=(root/'prediction_search_runtime.lua').read_text()
        if publish:
            search_runtime=search_runtime.replace('no refresh or selection','publishes a verified match and selects its operation')
        parts.append(search_runtime)
    runtime=(root/'identity_probe_runtime.lua').read_text()
    if dialog:
        parts.append((root/'prediction_dialog_runtime.lua').read_text())
    if search:
        runtime=runtime.replace('0.8.0 independent seed prediction','0.9.1 cooperative seed search')
    if publish:
        runtime=runtime.replace('0.9.1 cooperative seed search','0.10.1 search, publish and select').replace('read_only=true','read_only=false')
        runtime=runtime.replace('no refresh or selection will occur','search then publish one verified seed')
        runtime=runtime.replace('; read-only;', '; supervised live publication;')
    if dialog:
        runtime=runtime.replace('0.10.1 search, publish and select','0.20.2 docked dialog').replace('Ctrl+Shift+F9','Ctrl+Shift+F8')
    parts.append(runtime)
    return ('\n'.join(parts)+'\n').encode()


def main(output=None):
    output = Path(output) if output else build.ROOT/'releases'/f'Mission-Reroller-Lua-Probe-v{VERSION}.zip'
    build.build_addon(build_combined.MODULE, source(), build_combined.GUID, output,
                      f'Mission Reroller v{VERSION} (read-only Lua composition validation)')
    print(output)
    return output


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv)>1 else None)
