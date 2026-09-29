"""Validate a post-launch reference offline before replacing the candidate data file.

The MCP collector supplies a stable, read-only JSON capture. This script has no
process or network access. Original captured pages remain unchanged; a separate
fixture records the explicit active-record/seed overlays and their provenance.
"""
import argparse
import json
from pathlib import Path
import shutil
import struct
from validate_seed_replay import compare
from build_seed_test import candidate_from_fixture,write_candidate,CANDIDATE_FILE

def context_records(capture):
    canonical=bytes.fromhex(capture['canonical']);snapshot=bytes.fromhex(capture['snapshot'])
    assert len(canonical)==len(snapshot)==96 and canonical[:4]==snapshot[:4],'Unstable seed or malformed context'
    return canonical,snapshot

def publication_snapshot(canonical,snapshot,reference):
    if reference is None:return snapshot
    old_canonical,old_snapshot=context_records(reference)
    assert canonical[4:]==old_canonical[4:],'Publication reference belongs to a different active operation'
    return canonical[:4]+old_snapshot[4:]

def overlay(folder,address,payload,required=True):
    for p in (folder/'pages').glob('*.json'):
        record=json.loads(p.read_text());start=int(record['address'],16);data=bytearray.fromhex(record['hex'])
        if start<=address and address+len(payload)<=start+len(data):
            data[address-start:address-start+len(payload)]=payload
            record['hex']=data.hex();p.write_text(json.dumps(record));return
    assert not required,'Snapshot page missing'

def refresh(frozen,capture_file,output,publication_reference=None):
    from emulate_seed import replay
    live=json.loads(capture_file.read_text())
    meta=json.loads((frozen/'meta.json').read_text())
    canonical,snapshot=context_records(live)
    assert live['planet']==meta['planet'] and live['stable'] is True,'Wrong planet or unstable capture'
    assert not output.exists(),'Use a new output directory to preserve evidence'
    shutil.copytree(frozen,output)
    # Overlay exactly the observed seed and active operation, in both canonical
    # and campaign locations of the isolated emulator. Never change live memory.
    board=int(meta['board'],16)
    overlay(output,board+0x78e84,canonical,required=False)
    overlay(output,board+0x17a2bc,snapshot)
    provenance={'method':'frozen generator inputs with observed seed/active overlays',
                'frozen_session':meta['session'],'live_session':live['session'],
                'capture':str(capture_file.resolve())}
    (output/'overlay-provenance.json').write_text(json.dumps(provenance,indent=2))
    expected=dict(session=live['session'],seed_hex=canonical[:4].hex(),canonical_active_hex=canonical[4:].hex(),
                  operations=live['operations'],missions=live['missions'])
    (output/'expected.json').write_text(json.dumps(expected))
    result=replay(output)
    (output/'result.json').write_text(json.dumps(result,indent=2))
    validation=compare(output)
    (output/'validation.json').write_text(json.dumps(validation,indent=2))
    assert validation['matched'],'Live reference mismatch; candidate file was not changed'
    seed=json.loads((frozen/'search-result.json').read_text())['seed']
    inputs=output
    if publication_reference is not None:
        reference=json.loads(publication_reference.read_text())
        projected=publication_snapshot(canonical,snapshot,reference)
        inputs=output/'publication-inputs';inputs.mkdir()
        shutil.copytree(output/'pages',inputs/'pages');shutil.copy2(output/'meta.json',inputs/'meta.json')
        overlay(inputs,board+0x17a2bc,projected)
        (inputs/'projection-provenance.json').write_text(json.dumps({
            'reference':str(publication_reference.resolve()),
            'method':'exact observed post-refresh snapshot for byte-identical canonical active record'},indent=2))
    result=replay(inputs,seed,output=output/f'seed-{seed}')
    (output/f'seed-{seed}'/'result.json').write_text(json.dumps(result,indent=2))
    assert result['status']=='complete','Candidate replay failed'
    matches=[op for op in result['operations'] if op['difficulty']==10
             and {59,81}.issubset({m['type'] for m in op['missions']})]
    assert matches,'Original candidate no longer matches; offline search required'
    (output/'search-result.json').write_text(json.dumps(dict(status='found',seed=seed,
        operation=matches[0],published=False,validation_scope='post-launch live reference verified with explicit overlays'),indent=2))
    candidate=candidate_from_fixture(output)
    write_candidate(candidate)
    return dict(candidate_file=str(CANDIDATE_FILE),validation=validation,candidate=candidate)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('frozen',type=Path);parser.add_argument('capture',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--publication-reference',type=Path)
    args=parser.parse_args();print(json.dumps(refresh(args.frozen,args.capture,args.output,args.publication_reference),indent=2))
