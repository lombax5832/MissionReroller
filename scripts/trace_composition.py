"""Record intermediate composition inputs during offline saved-image replay."""
import argparse
import json
from pathlib import Path
import struct
from emulate_seed import replay
from unicorn import UC_HOOK_CODE
from unicorn.x86_const import *


def main(folder):
    records=[];pending={}
    def observe(engine,base,board):
        hooked=set()
        names={0x11e3250:('finalize',1),0x11e5100:('category',10),0x11e6800:('eligibility',9),
               0x11f96e0:('enabled',5),0x11e4cd0:('templates',8),
               0x12d7990:('config_old',3),0x12e7990:('config_new',3),
               0x12df110:('effects',6),0x177e5b0:('environment',3),0x11e6340:('weighted',14)}
        def watch(address):
            if address not in hooked:
                engine.hook_add(UC_HOOK_CODE,hook,begin=address,end=address);hooked.add(address)
        def read(a,n):return bytes(engine.mem_read(a,n))
        def q(a):return struct.unpack('<Q',read(a,8))[0]
        def d(a):return struct.unpack('<I',read(a,4))[0]
        def hook(uc,address,size,user):
            sp=uc.reg_read(UC_X86_REG_RSP)
            key=(address,sp)
            if key in pending:
                record=pending.pop(key);record['result']=uc.reg_read(UC_X86_REG_RAX)&0xffffffff
                args=record['args'];name=record['name']
                if name=='category':
                    record['after_rng']=read(args[8],8).hex()
                    record['candidates']=[d(args[9]+i*4) for i in range(record['result'])]
                elif name=='finalize':record['after']=read(args[0],92).hex()
                elif name=='templates':record['candidates']=[d(args[7]+i*4) for i in range(record['result'])]
                elif name=='effects':record['effects']=[read(q(args[1]+i*8),52).hex() for i in range(d(args[1]+0x800))]
                elif name=='environment':record['environments']=[d(args[0]+i*4) for i in range(d(args[0]+36))]
                elif name.startswith('config'):
                    pointer=uc.reg_read(UC_X86_REG_RAX)
                    record['value']=read(pointer,24).hex() if pointer else None
                elif name=='weighted':record['selected']=d(args[9]+48);record['after_counts']=read(args[13],162*4).hex()
                records.append(record)
            rva=address-base
            if rva not in names:return
            name,count=names[rva]
            args=[uc.reg_read(reg) for reg in (UC_X86_REG_RCX,UC_X86_REG_RDX,UC_X86_REG_R8,UC_X86_REG_R9)]
            args=args[:count]+[q(sp+0x28+i*8) for i in range(max(0,count-4))]
            record=dict(name=name,args=args)
            if name=='finalize':record['before']=read(args[0],92).hex()
            elif name=='category':
                record['before_rng']=read(args[8],8).hex();record['operation']=read(args[2],92).hex()
                record['template']=read(args[3],0x490).hex()
                op=read(args[2],92);record['used_types']=[d(args[0]+op[85+i]*76+48) for i in range(op[88])]
            elif name=='eligibility':record['metadata']=read(args[4],0x380).hex()
            elif name=='weighted':record['counts']=read(args[13],162*4).hex()
            pending[(q(sp),sp+8)]=record
            watch(q(sp))
        for rva in names:watch(base+rva)
    target=folder/'composition-trace'
    result=replay(folder,output=target,observer=observe)
    assert result['status']=='complete',result
    target.mkdir(exist_ok=True)
    (target/'trace.json').write_text(json.dumps(records),encoding='utf-8')
    from collections import Counter
    print(dict(Counter(r['name'] for r in records)))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('fixture',type=Path);main(p.parse_args().fixture)
