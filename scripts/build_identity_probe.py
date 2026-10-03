"""Build the read-only in-game validation step for the all-Lua generator port."""
from pathlib import Path
import sys
import build_core as build

VERSION = '0.8.0'


def config(search=False,publish=False,dialog=False,version=None):
    """The build's mode, as data the adapter and the runtimes read (host.config)."""
    if dialog:
        banner='Mission Reroller '+version+' docked dialog'
    elif publish:
        banner='Mission Reroller 0.10.1 search, publish and select'
    elif search:
        banner='Mission Reroller 0.9.1 cooperative seed search'
    else:
        banner='Mission Reroller '+VERSION+' independent seed prediction'
    return {
        # Diagnostic builds never write. Publication may predict the viewed
        # planet; it still requires the ship/view/canonical/UI planet to agree
        # in its own preflight.
        'read_only':not publish,
        'preview_prediction':publish or None,
        'version':version,
        'banner':banner,
        'mode':'supervised live publication' if publish else 'read-only',
        'shortcut':'F7 on the galactic map' if dialog else 'Ctrl+Shift+F9',
        'armed':'search then publish one verified seed' if publish else 'no refresh or selection will occur',
        'search_outcome':'publishes a verified match and selects its operation' if publish else 'no refresh or selection',
    }


def lua_value(value):
    if isinstance(value,bool):
        return 'true' if value else 'false'
    assert isinstance(value,str) and all(' '<=c<='~' for c in value),value
    return "'"+value.replace('\\','\\\\').replace("'","\\'")+"'"


def lua_table(values):
    return '{'+','.join(f'{key}={lua_value(value)}' for key,value in values.items() if value is not None)+'}'


# The adapter's inputs: the core, the build's mode, the map screen, the
# offsets it verifies on the first frame, their numbers, and SHA-256.
ADAPTER='core,config,make_map_screen,offsets,O,sha256'


def release_offsets(root):
    """offsets.lua without its research section, which only scripts/ reads."""
    text=(root/'offsets.lua').read_text()
    head,marker,tail=text.partition('\nresearch={\n')
    assert marker and tail.rstrip().endswith('},\n}'),'offsets.lua must end with its research section'
    return head+'\n}'


def factory(root,file,params,args):
    """A source file run as a function of its explicit inputs, unchanged."""
    return f'(function({params})\n'+(root/file).read_text()+f'\nend)({args})'


def source(search=False,publish=False,dialog=False,version=None):
    assert not publish or search
    assert not dialog or publish
    assert bool(version)==bool(dialog),'the dialog build names its release version'
    root = build.ROOT/'src'
    core = build.entry_path().read_text().replace('MissionReroller', 'MissionRerollerExperimentCore')
    parts = ['-- HD2-Addon: '+build.RELEASE_MODULE,
             "if rawget(_G,'MissionRerollerExperiment') then return end",
             'local core=(function()\n'+core+'\nend)()']
    libraries = []
    # The offsets (offsets.lua without its research section) and their
    # numbers O, which every module receives as its chunk argument (local O=...).
    parts.append('local offsets=(function()\n'+release_offsets(root)+'\nend)()')
    parts.append('local O=(function()\n'+(root/'offset_values.lua').read_text()+'\nend)()(offsets)')
    def library(name,file):
        libraries.append(name)
        parts.append('local '+name+'=(function(...)\n'+(root/file).read_text()+'\nend)(O)')
    def derived(name,expression):
        libraries.append(name)
        parts.append('local '+name+'='+expression)
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
                       ('sha256', 'bytes_sha256.lua'), ('ModInventory', 'mod_inventory.lua'),
                       ('make_reroll_session', 'reroll_session.lua'), ('make_map_screen', 'map_screen.lua'),
                       ('make_planet_sky', 'planet_sky.lua'), ('make_day_night', 'day_night.lua'),
                       ('ExternalEdits', 'external_edits.lua')]:
        library(name,file)
    derived('predict_identity','make_identity(make_rng)')
    derived('DayNight','make_day_night(make_planet_sky(make_rng))')
    # The planet model's modules, by the name planet_model.lua uses for each.
    planet = {'rng':'make_rng','identity':'predict_identity','special_inputs':'make_special_inputs',
              'levels':'make_level_inputs','level_choice':'choose_level','config':'make_config',
              'effects':'make_effects','eligible':'mission_eligible','category':'choose_category',
              'finalizer':'make_finalizer','mission_choice':'make_mission_choice',
              'environments':'make_environments','composition_inputs':'make_composition_inputs',
              'composition_prediction':'make_composition_prediction','capture':'make_composition_capture',
              'base_inputs':'make_base_inputs'}
    if dialog:
        for name,file in [('Panel','docked_panel.lua'),('Hint','keybind_hint.lua'),('Binding','mod_binding.lua'),('EscapeGate','escape_gate.lua'),('Compatibility','mission_compatibility.lua'),('FilterCatalogue','filter_catalogue.lua'),('FilterRequest','filter_request.lua'),('make_gate','window_mouse_gate.lua'),('make_router','modal_pointer.lua'),('make_cursor','window_cursor.lua'),
                          ('Constellations','constellation_prediction.lua'),('make_constellation_inputs','constellation_inputs.lua'),
                          ('SideObjectives','side_objective_prediction.lua'),('make_objective_inputs','side_objective_inputs.lua'),
                          ('UnitForecast','unit_forecast.lua'),
                          ('KycRoster','vendor/know_your_constellation/roster.lua'),
                          ('KycRosterData','vendor/know_your_constellation/roster_data.lua')]:
            library(name,file)
        # Know Your Constellation's roster, bundled with CowboyBingus's permission.
        derived('BundledRoster','(function(...)\n'+(root/'bundled_roster.lua').read_text()+'\nend)(O,KycRoster,KycRosterData)')
        planet.update({'constellation_inputs':'make_constellation_inputs','catalogue':'FilterCatalogue',
                       'compatibility':'Compatibility','options':'Search.options','labels':'Constellations.names',
                       'objective_inputs':'make_objective_inputs','objectives':'SideObjectives'})
    if publish:
        for name,file in [('make_publication','seed_publication.lua'),('make_ui_selection','ui_operation_selection.lua'),
                          ('make_guarded_write','guarded_write.lua'),
                          ('verify_predicted_board','verify_predicted_board.lua')]:
            library(name,file)
    if search:
        for name, file in [('make_frozen_reads','frozen_prediction_reads.lua'), ('make_seed_search','seed_search.lua'),
                           ('Search','search_session.lua'), ('make_candidate_predictor','candidate_predictor.lua'),
                           ('make_prediction_job','prediction_search_job.lua')]:
            library(name,file)
        derived('make_search_job','make_prediction_job(make_frozen_reads,make_seed_search,Search)')
        planet['predictor']='make_candidate_predictor'
    # One construction path for every planet's prediction (src/planet_model.lua).
    derived('Planet','(function(...)\n'+(root/'planet_model.lua').read_text()+'\nend)(O)({'
            +','.join(f'{key}={value}' for key,value in sorted(planet.items()))+'})')
    # The adapter and each runtime run as a function of explicit inputs:
    # host (the adapter's services and the build's config), lib (the modules
    # above) and hooks (entry points of the other runtimes, nil for a runtime
    # the build leaves out). No source text is rewritten.
    parts.append('local config='+lua_table(config(search,publish,dialog,version)))
    parts.append('local host='+factory(root,'experiment_adapter.lua',ADAPTER,ADAPTER))
    # The adapter returns nothing when another copy already runs or the loader
    # is too old, after setting M.status; the addon then stays inert.
    parts.append('if not host then return end')
    # The one writer of M.status (src/reroll_session.lua), shared by every runtime.
    parts.append('host.reroll_session=make_reroll_session(host.M,host.emit)')
    # The one guarded memory write (src/guarded_write.lua), only in the builds
    # that publish; the read-only builds carry no write.
    if publish:
        parts.append('host.write=make_guarded_write(host)')
    parts.append('local lib={'+','.join(f'{name}={name}' for name in libraries)+'}')
    inputs='host,lib,hooks'
    identity_hooks=[]
    # Runtimes are created in this order so their startup lines keep their order in the log.
    if publish:
        parts.append('local publication='+factory(root,'live_publication_runtime.lua',inputs,'host,lib,{}'))
        identity_hooks.append('advance_live_publication=publication.advance_live_publication')
    if dialog:
        parts.append('local constellations='+factory(root,'constellation_runtime.lua',inputs,'host,lib,{}'))
        identity_hooks.append('observe_constellations=constellations.observe_constellations')
        parts.append('local objectives='+factory(root,'side_objective_runtime.lua',inputs,'host,lib,{}'))
        identity_hooks.append('observe_objectives=objectives.observe_objectives')
    if search:
        search_hooks=[]
        if dialog:
            search_hooks+=['bind_constellations=constellations.bind_constellations','bind_objectives=objectives.bind_objectives']
        if publish:
            search_hooks+=[f'{name}=publication.{name}' for name in ('on_existing_match','on_search_match')]
        parts.append('local search_hooks={'+','.join(search_hooks)+'}')
        parts.append('local search='+factory(root,'prediction_search_runtime.lua',inputs,'host,lib,search_hooks'))
        identity_hooks+=[f'{name}=search.{name}' for name in ('on_prediction_ready','advance_prediction_search','search_clock')]
    if dialog:
        parts.append('local dialog='+factory(root,'prediction_dialog_runtime.lua',inputs,'host,lib,{default_limit=search.default_limit}'))
        # The search validates a request against the dialog's catalogue.
        parts.append('search_hooks.validate_search_request=dialog.validate_search_request')
        identity_hooks+=[f'{name}=dialog.{name}' for name in ('dialog_tick','dialog_release')]
    parts.append('local identity='+factory(root,'identity_probe_runtime.lua',inputs,'host,lib,{'+','.join(identity_hooks)+'}'))
    return ('\n'.join(parts)+'\n').encode()


def main(output=None):
    output = Path(output) if output else build.ROOT/'releases'/f'Mission-Reroller-Lua-Probe-v{VERSION}.zip'
    build.build_addon(build.RELEASE_MODULE, source(), build.RELEASE_GUID, output,
                      f'Mission Reroller v{VERSION} (read-only Lua composition validation)')
    print(output)
    return output


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv)>1 else None)
