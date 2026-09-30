-- Usage: luajit test_constellation_runtime.lua <built dialog entry>
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
-- The entry's offsets, from the src folder beside tests/.
local O=H.offsets((arg[0]:match('^(.*[/\\])') or '')..'../src')
local up=H.up
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local logs={}
CowboyBingusModLoader={api=1,version=18,open_log=function()return {write=function(_,s)logs[#logs+1]=s end,flush=function()end,close=function()end}end}
update=function()end;shutdown=function()end
dofile(arg[1])
local tick=up(update,'tick');local ready=up(tick,'on_prediction_ready')
local observe=up(tick,'observe_constellations');local bind=up(ready,'bind_constellations')
local M=MissionRerollerExperiment
-- Sparse zero-filled process memory.
local memory={}
local function poke(address,bytes)for i=1,#bytes do memory[address+i-1]=bytes:byte(i)end end
local function link(address,target)poke(address,word(target%4294967296)..word(math.floor(target/4294967296)))end
local function read(address,size)
    local out={};for i=0,size-1 do out[#out+1]=string.char(memory[address+i] or 0)end
    return table.concat(out)
end
local function decode(bytes,offset)
    offset=offset or 0
    if not bytes or #bytes<offset+8 then return nil end
    local a,b,c,d,e,f=bytes:byte(offset+1,offset+6)
    local value=a+b*256+c*65536+d*16777216+e*4294967296+f*1099511627776
    if value<0x10000 then return nil end
    return value
end
H.natives(update,{api={read=read,pointer=decode,time=function()return 0 end},game=0x10000000})
jit.flush()
local game,board,root,controller,level,screens=0x10000000,0x20000000,0x30000000,0x40000000,0x50000000,0x70000000
local owner,variants,records,manager,sets=0x80000000,0x81000000,0x82000000,0x83000000,0x84000000
link(game+O.rva.screen_owner,screens);poke(screens+O.screen_owner.stack,word(15)..string.rep('\0',16)..word(1))
link(game+O.rva.board,board);link(game+O.rva.ui_root,root);link(root+O.ui_root.level_controller,controller)
link(game+O.rva.configuration,0x90000000);link(game+O.rva.effect_manager,0x91000000);link(game+O.rva.session,0x92000000)
link(game+O.rva.global_effects,0x93000000)
for i=0,31 do poke(game+O.rva.enemy_tags+i*4,word(0x5000+i))end
local row=game+O.rva.difficulty_rows+9*O.difficulty_row.size
poke(row+O.difficulty_row.constellation_draws,word(1));poke(row+O.difficulty_row.constellation_candidates[1],word(4)..'\0\0\128\63')
poke(game+O.rva.mission_types+72*O.mission_type.size+8,word(2))
poke(board+O.board.campaign+O.campaign.planet_count,word(300));poke(board+O.board.campaign+268*O.campaign.definition_stride+0x18,word(0xabc))
local seed=123456
local function descriptor(kind)
    return word(seed)..word(0)..string.char(2,10,0,0)..word(0xabc)..string.rep('\0',10)..string.char(kind%256,math.floor(kind/256))
end
poke(board+O.board.selection_row,word(3))
local operation=board+O.board.operations+3*92
poke(operation+16,string.char(268%256,1));poke(operation+24,string.char(5));poke(operation+52,string.char(1))
poke(board+O.board.mission_preview,descriptor(72))
poke(board+O.board.mission_count,word(1))
poke(board+O.board.missions+40,word(3));poke(board+O.board.missions+48,word(72));poke(board+O.board.missions+52,word(seed))
-- Predicted operations receive base tags from the mission seed alone.
local Planet=up(ready,'Planet')
local annotate=bind(Planet.bind(read,up(ready,'u'),decode,game,board,268))
local op={difficulty=10,effect_id=4294967295,missions={{native_type=72,seed=seed},{native_type=72,seed=99}}}
annotate(op);assert(op.missions[1].tags[4] and op.missions[2].tags[4] and not op.missions[1].tags[2])
poke(game+O.rva.mission_types+73*O.mission_type.size+8,word(0))
local generic={difficulty=10,missions={{native_type=73,seed=1}}}
annotate(generic,0,5);assert(generic.missions[1].tags==nil,'Missions without a faction stay unresolved')
-- Busy states and an absent preview log nothing.
local now=0
local function poll()now=now+1;observe(now)end
local before=#logs
local session=up(observe,'reroll_session')
session.advance('waiting_for_stable_inputs');session.advance('search_running')
poll();assert(#logs==before,'The observer must not run during a search')
session.finish('search_exhausted')
for _=1,5 do poll()end
assert(#logs==before,'A preview that has not loaded must be retried quietly')
-- Loaded preview with a tagged first stamp.
poke(controller,word(1));poke(controller+8,descriptor(72));link(controller+O.level_controller.level,level);link(controller+O.level_controller.stamp_manager,manager)
poke(level+O.level.kind,word(72));poke(level+O.level.stamp_count,word(1))
link(level+O.level.stamps,owner);poke(level+O.level.stamps+8,word(0xadc32faa));poke(level+O.level.stamps+0xa1,string.char(0,1))
link(owner+0x28,variants);link(variants+8,records);poke(variants+0x10,word(2));poke(owner+0x30,word(1));poke(owner,word(0xfeed))
poke(records+8,word(1));poke(records+O.stamp.size+8,word(1));poke(records+O.stamp.size+0xd0,word(13))
poke(manager+0xbc,word(1));link(manager+0x38,sets);link(sets,owner)
poll()
local text=table.concat(logs,'\n')
assert(text:find('CONSTELLATION_CHECK planet=268 row=3 type=72 seed=123456 difficulty=10 faction=2',1,true),text)
assert(text:find('predicted=[Hunter Swarms (BugPredators)] level=2c8 explicit=[] stamps=1 stamp=13(type=adc32faa variant=0 index=1) later_tagged=[]',1,true),text)
assert(text:find('full=[Hunter Swarms (BugPredators), Shriekers (GM_BugShrieker_Traveler)] agree=false',1,true),text)
assert(text:find('CONSTELLATION_STAMP_SURVEY sets=1 records=2 tagged=1 tags=[13:1] examples=[0000feed/0/1=13] truncated=false',1,true),text)
before=#logs;poll();poll();assert(#logs==before,'Each previewed mission is logged once')
-- The alternate level slot, explicit tags and no stamp.
seed=777
poke(board+O.board.mission_preview,descriptor(72));poke(controller+8,descriptor(72));poke(board+O.board.missions+52,word(seed))
link(controller+O.level_controller.level,0);link(controller+O.level_controller.previous_level,level)
poke(level+O.level.stamp_count,word(0));poke(level+O.level.explicit_tags,word(9));poke(level+O.level.explicit_tags+12,word(1))
poll();text=table.concat(logs,'\n')
assert(text:find('seed=777',1,true) and text:find('level=288 explicit=[9] stamps=0 stamp=none later_tagged=[]',1,true),text)
poke(level+O.level.explicit_tags+12,word(0))
seed=778;poke(board+O.board.mission_preview,descriptor(72));poke(controller+8,descriptor(72));poke(board+O.board.missions+52,word(seed))
poll();text=table.concat(logs,'\n')
assert(text:find('seed=778',1,true) and text:match('seed=778[^\n]*agree=true'),text)
-- Values outside the tag table are logged raw and left unresolved.
seed=781;poke(board+O.board.mission_preview,descriptor(72));poke(controller+8,descriptor(72));poke(board+O.board.missions+52,word(seed))
poke(level+O.level.explicit_tags,word(77));poke(level+O.level.explicit_tags+12,word(1))
poll();assert(table.concat(logs,'\n'):match('seed=781[^\n]*explicit=%[77%] stamps=0 stamp=none later_tagged=%[%] full=unresolved agree=unknown'))
poke(level+O.level.explicit_tags,word(0));poke(level+O.level.explicit_tags+12,word(0))
-- A first stamp without a record contributes nothing; later stamps never do,
-- but tagged ones are listed.
seed=782;poke(board+O.board.mission_preview,descriptor(72));poke(controller+8,descriptor(72));poke(board+O.board.missions+52,word(seed))
poke(level+O.level.stamp_count,word(3));poke(level+O.level.stamps+0xa1,string.char(255,255))
link(level+O.level.stamps+2*O.level.stamp_size,owner);poke(level+O.level.stamps+2*O.level.stamp_size+8,word(0xadc32faa));poke(level+O.level.stamps+2*O.level.stamp_size+0xa1,string.char(0,1))
poke(level+O.level.stamps+O.level.stamp_size+0xa1,string.char(255,255))
poll();assert(table.concat(logs,'\n'):match('seed=782[^\n]*stamps=3 stamp=none%(type=adc32faa variant=255 index=255%) later_tagged=%[2:13%][^\n]*agree=true'),table.concat(logs,'\n'))
poke(level+O.level.stamp_count,word(0))
-- A map preview leaves the controller unloaded; its first stamp still counts.
seed=783;poke(board+O.board.mission_preview,descriptor(72));poke(controller+8,descriptor(72));poke(board+O.board.missions+52,word(seed))
poke(controller,word(0));poke(level+O.level.stamp_count,word(1));poke(level+O.level.stamps+0xa1,string.char(0,1))
poll();assert(table.concat(logs,'\n'):match('seed=783[^\n]*stamps=1 stamp=13%(type=adc32faa variant=0 index=1 preview%)[^\n]*Shriekers[^\n]*agree=false'),table.concat(logs,'\n'))
poke(controller,word(1));poke(level+O.level.stamp_count,word(0))
-- A level describing another mission is never used; it is reported unavailable.
seed=779;poke(board+O.board.mission_preview,descriptor(72));poke(controller+8,descriptor(72));poke(board+O.board.missions+52,word(seed))
poke(level+O.level.kind,word(71))
for _=1,19 do poll()end
assert(not table.concat(logs,'\n'):find('seed=779',1,true))
poll();assert(table.concat(logs,'\n'):match('seed=779[^\n]*level=unavailable agree=unknown'))
-- Missions outside the highlighted operation and read failures stay silent or report once.
seed=780;poke(board+O.board.mission_preview,descriptor(72));poke(controller+8,descriptor(72))
before=#logs;for _=1,25 do poll()end;assert(#logs==before,'Preview must belong to the highlighted operation')
poke(board+O.board.mission_count,word(400));poll();poll()
local blocked=0;for _,line in ipairs(logs)do if line:find('CONSTELLATION_CHECK_BLOCKED',1,true)then blocked=blocked+1 end end
assert(blocked==1,'Diagnostic failures are reported once and never raised')
-- Search path: candidate operations are tagged through the frozen reader,
-- and displayed operations are tagged before the existing-match check.
poke(board+O.board.mission_count,word(1))
local advance=up(tick,'advance_prediction_search')
local s={board=board,planet=268,seed=500,fingerprint='stable',operations=string.rep('\0',110*92),
    decoded={operations={{row=3,operation_id=5,seed=1,difficulty=10,missions={{native_type=72,seed=5,level_index=1}}}}}}
local matched,existing,evaluated
up(ready,'snapshot',function()return s end,true)
up(ready,'hooks').validate_search_request=nil
-- The planet's tag inputs are real; its predictor is scripted.
up(ready,'Planet',{capture=function()return function()return {passed=true,independent_bases=true}end end,
    bind=function(take,...)
        local planet=Planet.bind(take,...)
        planet.predictor=function()return function(candidate,difficulty)
            take(board+O.board.campaign+O.campaign.planet_count,4);evaluated=candidate
            return {{valid=true,row=7,id=1,category=0,faction=2,difficulty=10,effect_id=4294967295,modifiers={},
                missions={{native_type=72,seed=candidate,level_index=1},{native_type=72,seed=candidate+1,level_index=2}}},
                -- The complete board also holds another difficulty.
                not difficulty and {valid=true,row=1,id=2,category=0,faction=2,difficulty=4,effect_id=4294967295,modifiers={},
                    missions={{native_type=72,seed=candidate+2,level_index=1}}} or nil}
        end end
        return planet
    end},true)
up(ready,'on_existing_match',function(_,op)existing=op;session.finish('publication_test_passed')end,true)
up(advance,'on_search_match',function(job)matched=job end,true)
jit.flush()
local function search(required,groups)
    matched,existing,evaluated=nil,nil,nil
    -- The dialog starts a run and the capture hands it over to the search;
    -- the last one ended at its match, as the idle pipeline would settle it.
    session.settle()
    local request={difficulty=10,required=required,constellations={groups=groups},limit=256}
    assert(session.start(request) and session.take_request() and session.view().request==request)
    session.advance('waiting_for_stable_inputs')
    ready(s,0x60000000,now)
    for _=1,4000 do
        if M.status~='search_running' then break end
        now=now+0.01;advance('tick',now)
    end
end
-- Mission type 72 stands in for the Search and Destroy family (7).
local family=up(ready,'Search').options[7];family.ids[#family.ids+1]=72
M.dialog_enabled=true;search({[7]=true},{[7]={[4]='accept'}})
assert(existing and existing.row==3 and existing.missions[1].tags[4] and not evaluated,'Displayed operations are tagged before searching')
M.dialog_enabled=false;search({[7]=true},{[7]={[4]='accept',[6]='accept',[2]='exclude'}})
assert(M.status=='search_matched' and matched.seed==501 and matched.constellations.groups[7][2]=='exclude',tostring(M.status))
assert(matched.operation.missions[1].tags[4] and matched.operation.missions[2].tags[4])
assert(#matched.operations==2 and matched.operations[2].missions[1].tags,'The complete board is tagged as well')
text=table.concat(logs,'\n')
assert(text:find('LUA_SEARCH_CONSTELLATIONS Search and Destroy=accept 4|6 exclude 2',1,true),text)
assert(text:find('LUA_SEARCH_MATCH_CONSTELLATIONS row=7 missions=72:4,72:4',1,true),text)
search({[7]=true},{[7]={[2]='accept'}});assert(M.status=='search_exhausted' and not matched and evaluated==756,'A constellation never drawn exhausts the budget')
search({[7]=true},{[7]={[4]='exclude'}});assert(M.status=='search_exhausted' and not matched,'An excluded constellation that is always drawn')
search({[7]=true},{[7]={[2]='exclude',[6]='exclude'}});assert(M.status=='search_matched','Exclusions that never occur')
search({},{[0]={[4]='accept'}});assert(M.status=='search_matched' and table.concat(logs,'\n'):find('LUA_SEARCH_CONSTELLATIONS operation=accept 4',1,true))
search({},{[0]={[2]='exclude',[3]='exclude'}})
assert(M.status=='search_matched' and table.concat(logs,'\n'):find('LUA_SEARCH_CONSTELLATIONS operation=accept any exclude 2|3',1,true))
search({},{[0]={[2]='accept'}});assert(M.status=='search_exhausted')
family.ids[#family.ids]=nil
text=table.concat(logs,'\n')
assert(not text:find('SESSION_',1,true),'Every phase change follows the session rules: '..tostring(text:match('SESSION_[^\n]*')))
print('Constellation runtime: search tagging, annotation, preview observer, stamp survey, alternate level slot and fail-quiet diagnostics passed')
