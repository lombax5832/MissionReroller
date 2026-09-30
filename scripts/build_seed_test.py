"""Build a one-shot seed publication test with digests, never captured game bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import build_core as build
import build_combined

VERSION='0.5.3'
CANDIDATE_FILE=build.ROOT/'artifacts'/'seed-publication-candidate.txt'

def record_hashes(operations,missions):
    assert len(operations)>=110*92
    rows=b''.join(struct.pack('<I',i)+operations[i*92:(i+1)*92] for i in range(110) if operations[i*92+52])
    return hashlib.sha256(rows).hexdigest(),hashlib.sha256(missions).hexdigest()

def candidate_from_fixture(folder):
    meta=json.loads((folder/'meta.json').read_text())
    baseline=json.loads((folder/'validation.json').read_text())
    independent=[json.loads(p.read_text()) for p in folder.glob('seed-*/validation.json')]
    assert baseline['matched'] and any(v['matched'] and v['seed']!=baseline['seed'] for v in independent), 'Independent validation required'
    found=json.loads((folder/'search-result.json').read_text())
    assert found['status']=='found' and found['published'] is False
    seed=found['seed'];op=found['operation'];target=folder/f'seed-{seed}'
    operations=(target/'predicted-operations.bin').read_bytes()
    missions=(target/'predicted-missions.bin').read_bytes()
    assert len(operations)==110*92 and len(missions)==0x6200
    count=struct.unpack_from('<I',missions,0x61f8)[0];assert count<=330
    rows=b''.join(struct.pack('<I',i)+operations[i*92:(i+1)*92] for i in range(110) if operations[i*92+52])
    row=operations[op['row']*92:(op['row']+1)*92]
    assert row[52] and row[32]==op['difficulty'] and struct.unpack_from('<I',row,12)[0]==op['seed']
    # Active record in the campaign snapshot is the actual input used by replay.
    address=int(meta['board'],16)+0x101438+0x78e88
    active=None
    for path in (folder/'pages').glob('*.json'):
        record=json.loads(path.read_text());start=int(record['address'],16);data=bytes.fromhex(record['hex'])
        if start<=address and address+92<=start+len(data): active=data[address-start:address-start+92]
    assert active is not None,'Active record missing from fixture'
    reference=json.loads((folder/'expected.json').read_text())
    # Preflight protects canonical state; the generator reads the display copy.
    if 'canonical_active_hex' in reference:
        active=bytes.fromhex(reference['canonical_active_hex'])
        assert len(active)==92
    reference_missions=bytes.fromhex(reference['missions'])
    reference_count=struct.unpack_from('<I',reference_missions,0x61f8)[0]
    bh,mh=record_hashes(bytes.fromhex(reference['operations']),reference_missions[:reference_count*76])
    return dict(seed=seed,planet=meta['planet'],difficulty=op['difficulty'],row=op['row'],operation_seed=op['seed'],
                active_hash=hashlib.sha256(active).hexdigest(),operation_hash=hashlib.sha256(rows).hexdigest(),
                mission_hash=hashlib.sha256(missions[:count*76]).hexdigest(),
                baseline_seed=int.from_bytes(bytes.fromhex(reference['seed_hex']),'little'),
                baseline_operation_hash=bh,baseline_mission_hash=mh)

def source():
    root=build.ROOT/'src'
    core=build.entry_path().read_text().replace('MissionReroller','MissionRerollerExperimentCore')
    parts=['-- HD2-Addon: '+build_combined.MODULE,"if rawget(_G,'MissionRerollerExperiment') then return end",
           'local core=(function()\n'+core+'\nend)()']
    for name,file in [('make_publication','seed_publication.lua'),('sha256','bytes_sha256.lua'),
                      ('load_candidate','seed_candidate.lua'),('make_ui_selection','ui_operation_selection.lua'),
                      ('selection_signatures','selection_signatures.lua')]:
        parts.append('local '+name+'=(function()\n'+(root/file).read_text()+'\nend)()')
    parts.append('local candidate={}\nlocal candidate_path='+json.dumps(CANDIDATE_FILE.as_posix()))
    parts.extend([build.inline_adapter(),(root/'seed_test_runtime.lua').read_text()])
    return ('\n'.join(parts)+'\n').encode()

def write_candidate(candidate):
    CANDIDATE_FILE.parent.mkdir(parents=True,exist_ok=True)
    temporary=CANDIDATE_FILE.with_suffix('.tmp')
    temporary.write_text(''.join(f'{key}={value}\n' for key,value in candidate.items()),encoding='ascii')
    temporary.replace(CANDIDATE_FILE)

def main(folder,output=None):
    candidate=candidate_from_fixture(Path(folder))
    write_candidate(candidate)
    output=Path(output) if output else build.ROOT/'releases'/f'Mission-Reroller-Seed-Test-v{VERSION}.zip'
    build.build_addon(build_combined.MODULE,source(),build_combined.GUID,output,
                      f'Mission Reroller v{VERSION} (one-shot seed publication test)')
    print(json.dumps({'output':str(output),'candidate':candidate},indent=2));return output

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('fixture',type=Path)
    parser.add_argument('--output',type=Path);args=parser.parse_args();main(args.fixture,args.output)
