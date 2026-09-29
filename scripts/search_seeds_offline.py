"""Bounded seed search using captured memory. Never publishes a seed to the game."""
import argparse
import json
from pathlib import Path
import time
from emulate_seed import replay


def search(folder,difficulty,requirements,attempts=100,seconds=30):
    validation=json.loads((folder/'validation.json').read_text())
    if not validation['matched']:
        raise ValueError('Current-seed replay must match the reference before searching')
    if not requirements or any(not group for group in requirements):
        raise ValueError('At least one nonempty mission requirement is required')
    if not 1<=difficulty<=10 or not 1<=attempts<=1000 or not 0<seconds<=300:
        raise ValueError('Invalid search bounds')
    start=time.monotonic()
    for i in range(attempts):
        if time.monotonic()-start>=seconds:
            return {'status':'time_limit','attempts':i,'published':False}
        seed=(validation['seed']+i+1)&0xffffffff
        result=replay(folder,seed)
        if result['status']!='complete':
            return {'status':'replay_stopped','attempts':i+1,'seed':seed,'replay':result,'published':False}
        for operation in result['operations']:
            ids={m['type'] for m in operation['missions']}
            if operation['difficulty']==difficulty and all(ids&group for group in requirements):
                return {'status':'found','attempts':i+1,'elapsed_seconds':time.monotonic()-start,
                        'seed':seed,'operation':operation,'published':False,
                        'validation_scope':'one captured reference seed; new seed is an unverified prediction'}
    return {'status':'attempt_limit','attempts':attempts,'published':False}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    parser.add_argument('--difficulty',type=int,default=10)
    parser.add_argument('--require',action='append',required=True,help='Comma-separated native IDs for one mission family; repeat for AND requirements')
    parser.add_argument('--attempts',type=int,default=100)
    parser.add_argument('--seconds',type=float,default=30)
    args=parser.parse_args()
    result=search(args.directory,args.difficulty,[{int(x) for x in group.split(',')} for group in args.require],args.attempts,args.seconds)
    (args.directory/'search-result.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result))
