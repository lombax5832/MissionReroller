"""Assemble one plaintext addon from independently testable local modules."""
import sys
from pathlib import Path
import build_core as build
MODULE = 'mods/ipodalexei/mission_reroller_experiment'
GUID = '1b378e53-cb80-44f0-a05c-909834932ea1'
VERSION = '0.3.1'

def source():
    root = build.ROOT / 'src'
    core = build.entry_path().read_text(encoding='utf-8')
    # Keep the pure decoder private to this package; do not conflict with the core addon.
    core = core.replace('MissionReroller', 'MissionRerollerExperimentCore')
    pieces = ['-- HD2-Addon: ' + MODULE,
              "if rawget(_G,'MissionRerollerExperiment') then return end",
              'local core=(function()\n' + core + '\nend)()',
              'local Search=(function()\n' + (root/'search_session.lua').read_text() + '\nend)()',
              'local make_panel=(function()\n' + (root/'filter_panel.lua').read_text() + '\nend)()',
              build.inline_adapter(),
              (root/'experiment_runtime.lua').read_text()]
    return ('\n'.join(pieces) + '\n').encode('utf-8')

def main(output=None):
    output = Path(output) if output else build.ROOT/'releases'/f'Mission-Reroller-Experiment-v{VERSION}.zip'
    build.build_addon(MODULE, source(), GUID, output, f'Mission Reroller Experiment v{VERSION}')
    print(output)
    return output

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv)>1 else None)
