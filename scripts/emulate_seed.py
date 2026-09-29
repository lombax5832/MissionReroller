"""Research-only x64 generator replay in Unicorn. Never opens the game process.

Missing memory is reported for a separate read-only MCP collector. Captured
pages and all emulated writes remain local; no emulator output is published.
"""
import argparse
import collections
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent/'tools/seed-emulator-deps'))
from unicorn import Uc, UcError, UC_ARCH_X86, UC_MODE_64, UC_HOOK_MEM_UNMAPPED, UC_HOOK_MEM_WRITE, UC_HOOK_MEM_FETCH_PROT, UC_HOOK_INSN, UC_HOOK_INTR
from unicorn.x86_const import *

SCRATCH = 0x10000000000
STACK = SCRATCH + 0x100000
STOP = SCRATCH + 0x300000


def replay(folder, seed=None, output=None, observer=None):
    meta = json.loads((folder/'meta.json').read_text())
    base = int(meta['game'], 16)
    board = int(meta['board'], 16)
    campaign = board + 0x101438
    planet = meta['planet']
    if seed is not None and not 0 <= seed <= 0xffffffff:
        raise ValueError('Seed must fit uint32')
    uc = Uc(UC_ARCH_X86, UC_MODE_64)
    mapped = set()
    for file in sorted((folder/'pages').glob('*.json')):
        record = json.loads(file.read_text())
        if record['session'] != meta['session']:
            raise ValueError('Mixed capture sessions')
        address = int(record['address'],16)
        data = bytes.fromhex(record['hex'])
        if address % 4096 or len(data) % 4096:
            raise ValueError('Capture blocks must contain whole pages')
        for offset in range(0,len(data),4096):
            page = address+offset
            if page in mapped:
                raise ValueError('Overlapping capture pages')
            # Data pages cannot execute; only the pinned game-code interval can.
            uc.mem_map(page,4096,7 if base+0x1000<=page<base+0x2110000 else 3)
            uc.mem_write(page,data[offset:offset+4096]);mapped.add(page)
    for address,size in ((SCRATCH,0x10000),(STACK,0x100000),(STOP,0x1000)):
        uc.mem_map(address,size)
    uc.mem_write(SCRATCH+0x2790,b'\xa5'*(0x4000-0x2790))
    uc.mem_write(SCRATCH+0xa200,b'\xa5'*(0x10000-0xa200))
    uc.mem_write(SCRATCH+0x2788,struct.pack('<I',0xffffffff))
    missing=[]; violations=[]; written=collections.Counter(); blocks=collections.Counter()
    def absent(engine,access,address,size,value,context):
        missing.append({'address':hex(address&~4095),'size':4096,'access':access,'rip':hex(engine.reg_read(UC_X86_REG_RIP))})
        return False
    def write(engine,access,address,size,value,context):
        if not SCRATCH <= address < STOP+4096:
            written[hex(address&~4095)]+=1
    def protected_fetch(engine,access,address,size,value,context):
        violations.append('Execution outside pinned game code: '+hex(address));return False
    def forbidden(engine,*args):
        violations.append('System call or interrupt');engine.emu_stop()
    uc.hook_add(UC_HOOK_MEM_UNMAPPED,absent)
    uc.hook_add(UC_HOOK_MEM_WRITE,write,None,1,SCRATCH-1)
    uc.hook_add(UC_HOOK_MEM_WRITE,write,None,STOP+4096,0x7fffffffffff)
    uc.hook_add(UC_HOOK_MEM_FETCH_PROT,protected_fetch)
    uc.hook_add(UC_HOOK_INSN,forbidden,None,1,0,UC_X86_INS_SYSCALL)
    uc.hook_add(UC_HOOK_INTR,forbidden)
    if observer is not None:
        observer(uc,base,board)
    def invoke(rva,args):
        stack=STACK+0xfff08 # Windows x64 entry alignment and shadow space.
        uc.mem_write(stack,struct.pack('<Q',STOP))
        uc.reg_write(UC_X86_REG_RSP,stack)
        for register,value in zip((UC_X86_REG_RCX,UC_X86_REG_RDX,UC_X86_REG_R8,UC_X86_REG_R9),args):
            uc.reg_write(register,value)
        uc.emu_start(base+rva,STOP,timeout=10_000_000,count=100_000_000)
        if uc.reg_read(UC_X86_REG_RIP)!=STOP:
            raise RuntimeError('Execution stopped before return (budget or forbidden path)')
    stage='operations'
    try:
        # The mask helper reads the global board operation array. Preserve that
        # alias in EMULATED memory instead of passing an unrelated scratch array.
        for address in (board+0xf9a0c,):
            page=address&~4095
            if page not in mapped:
                missing.append({'address':hex(page),'size':4096,'access':'output_metadata'})
                return {'status':'missing','missing':missing}
        uc.mem_write(board+0xf9a0c,b'\x01')
        if seed is not None:
            page=(campaign+0x78e84)&~4095
            if page not in mapped:
                missing.append({'address':hex(page),'size':4096,'access':'seed_override'})
                return {'status':'missing','missing':missing}
            uc.mem_write(campaign+0x78e84,struct.pack('<I',seed))
        invoke(0x12d5550,(board,campaign,planet))
        stage='missions'
        invoke(0x11e5670,(SCRATCH+0x4000,campaign,board+0xf7280,planet))
        operations=bytes(uc.mem_read(board+0xf7280,0x2788))
        missions=bytes(uc.mem_read(SCRATCH+0x4000,0x6200))
        if bytes(uc.mem_read(SCRATCH+0x2790,0x4000-0x2790))!=b'\xa5'*(0x4000-0x2790) or bytes(uc.mem_read(SCRATCH+0xa200,0x10000-0xa200))!=b'\xa5'*(0x10000-0xa200):
            raise RuntimeError('Generator exceeded output buffer boundary')
        mission_count=struct.unpack_from('<I',missions,0x61f8)[0]
        if mission_count>330:
            raise RuntimeError('Invalid generated mission count')
        destination=output or (folder if seed is None else folder/f'seed-{seed}')
        destination.mkdir(parents=True,exist_ok=True)
        (destination/'predicted-operations.bin').write_bytes(operations)
        (destination/'predicted-missions.bin').write_bytes(missions)
        result={'status':'complete','seed':seed,'operations':[],'emulated_capture_page_writes':dict(written)}
        for i in range(110):
            row=operations[i*92:(i+1)*92]
            if not row[52]:continue
            if row[88]>3 or any(index>=mission_count for index in row[85:85+row[88]]):
                raise RuntimeError('Invalid generated mission references')
            ids=[]
            for index in row[85:85+row[88]]:
                m=missions[index*76:(index+1)*76]
                ids.append({'type':struct.unpack_from('<I',m,48)[0],'seed':struct.unpack_from('<I',m,52)[0]})
            result['operations'].append({'row':i,'id':row[24],'difficulty':row[32],'seed':struct.unpack_from('<I',row,12)[0],'missions':ids})
        return result
    except (UcError,RuntimeError) as error:
        return {'status':'missing' if missing else 'stopped','stage':stage,'missing':missing,
                'error':str(error),'rip':hex(uc.reg_read(UC_X86_REG_RIP)),
                'violations':violations,'emulated_capture_page_writes':dict(written),
                'hot_blocks':blocks.most_common(5),
                'registers':{name:hex(uc.reg_read(reg)) for name,reg in
                             [('rcx',UC_X86_REG_RCX),('rdx',UC_X86_REG_RDX),('r8',UC_X86_REG_R8),('r9',UC_X86_REG_R9),('rsp',UC_X86_REG_RSP)]}}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    parser.add_argument('--seed',type=lambda x:int(x,0))
    args=parser.parse_args()
    result=replay(args.directory,args.seed)
    destination=args.directory if args.seed is None else args.directory/f'seed-{args.seed}'
    destination.mkdir(parents=True,exist_ok=True)
    (destination/'result.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result if result['status']!='complete' else
                     {**result,'operations':len(result['operations'])}))
