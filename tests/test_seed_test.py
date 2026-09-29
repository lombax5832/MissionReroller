"""Check one-shot state transitions, Windows digest, wrapper contract and package."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import build_seed_test as build
lua=os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe'))
subprocess.run([lua,str(ROOT/'tests/test_seed_publication.lua'),str(ROOT/'src/seed_publication.lua')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_ui_operation_selection.lua'),str(ROOT/'src/ui_operation_selection.lua')],check=True)
with tempfile.TemporaryDirectory() as directory:
    entry=Path(directory)/'test.lua';entry.write_bytes(build.source())
    source=entry.read_text()
    assert source.startswith('-- HD2-Addon: '+build.build_combined.MODULE+'\n')
    for forbidden in ['VirtualProtect','OpenProcess','CreateRemoteThread','VirtualAlloc','os.execute','io.popen']:
        assert forbidden not in source
    assert "ffi.cast('void (*)(void *, uint8_t, uintptr_t, uint8_t)'" not in source
    harness=Path(directory)/'harness.lua'
    harness.write_text('''
local function up(fn,key,value,set)
 for i=1,100 do local k,v=debug.getupvalue(fn,i);if not k then break end
  if k==key then if set then debug.setupvalue(fn,i,value)end;return v end end
 error('missing upvalue '..key)
end
local closed=false;local logs={}
CowboyBingusModLoader={api=1,version=16,open_log=function()
 return {write=function(_,text)logs[#logs+1]=text end,flush=function()end,close=function()closed=true end} end}
update=function()return 'original',nil,7 end
shutdown=function()return 'shutdown',nil,8 end
dofile(arg[1])
local installed=update;dofile(arg[1]);assert(update==installed)
local tick=up(update,'tick');local prepare=up(tick,'prepare')
local initialize=up(prepare,'initialize')
-- Install Windows declarations without reading or attaching to another process.
up(initialize,'create_api')()
local adapter
local make=up(prepare,'make_publication')
up(prepare,'make_publication',function(a,expected)adapter=a;return make(a,expected)end,true)
up(prepare,'initialize',function()end,true)
up(prepare,'ffi',require('ffi'),true)
prepare()
local sha=up(up(adapter.matches,'records_hash'),'sha256')
assert(sha('abc')=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
-- Exercise the actual write adapter without dereferencing process addresses.
local ffi=require('ffi');local board=ffi.cast('uint8_t *',0x20000000)
local ownership=up(adapter.preflight,'ownership')
local game=ffi.cast('uint8_t *',0x10000000);local session=ffi.cast('uint8_t *',0x30000000)
up(ownership,'game',game,true)
up(ownership,'pointer',function(a)
 if a==game+0x347cee8 then return board end
 assert(a==game+0x347cef0);return session
end,true)
local owner=string.char(1)..string.rep(string.char(0),7)
local count=0;local existing=false;local capacity_checked=false;local count_checked=false
local signature=up(ownership,'expected_code'):gsub('..',function(v)return string.char(tonumber(v,16))end)
up(ownership,'read',function(a,n)
 if a==session+0x162d8 then return string.char(1,0,0,0)end
 if a==session+0x162e0 or a==session+0xb398 or a==board+0x1f8078 then return owner end
 if a==board+0x1f80d0 then return string.char(count,0,0,0)end
 if a==board+0x1f8080 then
  local rows={};for i=1,count do rows[i]=string.char(existing and i or i+1)..string.rep(string.char(0),15)end
  return table.concat(rows)
 end
 assert(a==game+0x12d5670);return signature
end,true)
up(ownership,'page',function(a,n,kind)
 assert(kind==0x20000)
 if a==board+0x1f8080 then capacity_checked=n==16 end
 if a==board+0x1f80d0 then count_checked=n==4 end
end,true)
assert(ownership(board) and capacity_checked and count_checked,'Empty queue must allow one capacity-checked native insertion')
count=5;assert(not pcall(function()ownership(board)end),'Full queue must reject a missing source owner')
existing=true;assert(ownership(board),'Full queue with existing source must remain valid')
local seed=string.char(11,0,0,0);local active=string.rep(string.char(0),92)
local writes,notifications=0,0
local write_seed=up(adapter.publish,'write_seed')
up(adapter.publish,'ownership',function(b)assert(b==board);return 'owner'end,true)
up(adapter.publish,'notify',function(b)assert(b==board);notifications=notifications+1 end,true)
up(write_seed,'page',function(a,n,kind)assert(a==board+0x78e84 and n==4 and kind==0x20000)end,true)
up(write_seed,'kernel',{
 GetCurrentThreadId=function()return 7 end,
 GetCurrentProcessId=function()return 42 end,
 GetCurrentProcess=function()return 'self'end,
 WriteProcessMemory=function(process,a,bytes,n,count)
  assert(process=='self' and a==board+0x78e84 and n==4)
  seed=bytes;count[0]=4;writes=writes+1;return 1
 end},true)
up(write_seed,'read',function(a,n)
 if a==board+0x78e84 then assert(n==4);return seed end
 assert(a==board+0x78e88 and n==92);return active
end,true)
local s={board=board,seed=11,active=string.rep('00',92),owner_guard='owner'}
adapter.publish(s,22);assert(seed:byte()==22 and writes==1 and notifications==1)
adapter.restore(s,22);assert(seed:byte()==11 and writes==2 and notifications==2)
seed=string.char(33,0,0,0)
assert(not pcall(function()adapter.restore(s,22)end) and writes==2,'External changes must not be overwritten')
up(adapter.publish,'ownership',function()error('changed owner')end,true)
assert(not pcall(function()adapter.publish(s,22)end) and writes==2,'Guard must precede write')
-- Reproduce stale preflight through the real tick, then refresh data without
-- restarting/reloading the entry. The second keypress must publish exactly once.
seed=string.char(11,0,0,0)
up(adapter.publish,'ownership',function()return 'owner'end,true)
s.operations=string.rep(string.char(0),110*92);s.missions='';s.planet=268
s.context='same';s.fingerprint='stable';s.selection=string.rep(string.char(0),20)
local e={seed=22,planet=268,difficulty=10,row=28,operation_seed=123,baseline_seed=11,
 active_hash=string.rep('a',64),operation_hash=sha(''),mission_hash=sha(''),
 baseline_operation_hash=sha(''),baseline_mission_hash=sha('')}
local function manifest()
 local f=assert(io.open(arg[2],'wb'));for k,v in pairs(e)do f:write(k..'='..tostring(v)..'\\n')end;f:close()
end
manifest()
up(tick,'candidate_path',arg[2],true)
up(tick,'snapshot',function()return s end,true)
local now,down,focused=0,false,true
up(tick,'api',{time=function()now=now+0.25;return now end},true)
up(tick,'user32',{
 GetForegroundWindow=function()return 'window'end,
 GetWindowThreadProcessId=function(_,pid)pid[0]=focused and 42 or 99 end,
 GetAsyncKeyState=function()return down and -1 or 0 end},true)
tick();down=true;tick();focused=false;tick()
assert(up(tick,'armed') and writes==2,'Alt-tab must preserve the armed attempt')
focused=true;down=false
for i=1,42 do tick()end
down=true;tick()
local tx=up(tick,'transaction')
assert(not tx.used and writes==2,'Stale prediction must not write or consume attempt')
e.active_hash=sha(active);manifest()
down=false;for i=1,42 do tick()end
down=true;tick()
for i=1,40 do if tx.used then break end;tick()end
assert(tx.used and tx.state=='pending' and writes==3 and seed:byte()==22,'Fresh candidate must publish without restarting')
focused=false;tick()
assert(tx.state=='pending' and writes==3,'Alt-tab must not restore or cancel pending publication')
local selected_in_background=false
up(tick,'select_match',function(frame)assert(frame.seed==22);selected_in_background=true end,true)
local fresh={};for key,value in pairs(s)do fresh[key]=value end
s=fresh;s.seed=22;s.fingerprint='published'
for i=1,4 do tick()end
assert(tx.state=='committed' and selected_in_background and writes==3,'Verification and selection must advance while unfocused')
up(update,'tick',function()error('synthetic stop')end,true)
local a,b,c=update();assert(a=='original' and b==nil and c==7)
assert(MissionRerollerExperiment.status:find('synthetic stop',1,true))
local a,b,c=shutdown();assert(a=='shutdown' and b==nil and c==8 and closed)
print('seed test runtime: compile, duplicate guard, SHA256, error cleanup and wrapper returns passed')
''')
    subprocess.run([lua,str(harness),str(entry),str(Path(directory)/'candidate.txt')],check=True)
    output=Path(directory)/'test.zip'
    build.build.build_addon(build.build_combined.MODULE,entry.read_bytes(),build.build_combined.GUID,output,'Seed test')
    with zipfile.ZipFile(output) as archive:
        assert len(archive.namelist())==4
        assert entry.read_bytes() in archive.read(next(n for n in archive.namelist() if n.endswith('.patch_0')))
print('seed test package passed')
