"""Compare replay output with a read-only live reference capture."""
import argparse
import json
from pathlib import Path
import struct


def compare(folder):
    result=json.loads((folder/'result.json').read_text())
    if result['status']!='complete':
        raise ValueError('Replay did not complete')
    expected=json.loads((folder/'expected.json').read_text())
    op=bytes.fromhex(expected['operations']);missions=bytes.fromhex(expected['missions'])
    predicted=(folder/'predicted-operations.bin').read_bytes()
    predicted_missions=(folder/'predicted-missions.bin').read_bytes()
    differences=[]
    active=[i for i in range(110) if op[i*92+52]]
    generated=[i for i in range(110) if predicted[i*92+52]]
    if active!=generated:differences.append({'kind':'valid_rows','expected':active,'predicted':generated})
    for row in set(active)&set(generated):
        a,b=op[row*92:(row+1)*92],predicted[row*92:(row+1)*92]
        if a!=b:differences.append({'kind':'operation','row':row,'byte_offsets':[i for i in range(92) if a[i]!=b[i]]})
    count=struct.unpack_from('<I',missions,0x61f8)[0]
    got=struct.unpack_from('<I',predicted_missions,0x61f8)[0]
    if count!=got:differences.append({'kind':'mission_count','expected':count,'predicted':got})
    for row in range(min(count,got)):
        a,b=missions[row*76:(row+1)*76],predicted_missions[row*76:(row+1)*76]
        if a!=b:differences.append({'kind':'mission','row':row,'byte_offsets':[i for i in range(76) if a[i]!=b[i]]})
    return {'matched':not differences,'operations':len(active),'missions':count,
            'seed':int.from_bytes(bytes.fromhex(expected['seed_hex']),'little'),
            'comparison':'all bytes in valid operation and populated mission records',
            'differences':differences}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('directory',type=Path)
    folder=parser.parse_args().directory
    report=compare(folder)
    (folder/'validation.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))
