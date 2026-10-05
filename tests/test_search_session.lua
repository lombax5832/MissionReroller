local S=dofile(assert(arg[1]))
local function packet(seed,types,context)
    local m={};for _,id in ipairs(types)do m[#m+1]={native_type=id}end
    return {seed=seed,context=context or 'same',operations={{row=2,difficulty=10,operation_id=6,missions=m}}}
end
local p=packet(1,{59,81,65})
local s=S.new();s:start(p,10,{[1]=true,[2]=true},0)
s:advance(p,0,function()error('existing match must not call')end)
assert(s.match and s.calls==0 and not s.running)
local result=s.status;s:cancel('Dialog closed');assert(s.status==result and s.match)
assert(S.find(packet(2,{81,85,65}),10,{required={[2]=true,[4]=true}}))
assert(S.find(packet(2,{82,85,59}),10,{required={[2]=true,[4]=true}}))
assert(not S.find(packet(2,{81,59,65}),10,{required={[2]=true,[4]=true}}))
assert(not S.find(packet(1,{59,65}),10,{required={[1]=true,[2]=true}}))
-- The day/night check vetoes an otherwise matching operation, and alone
-- selects among the operations of the difficulty.
local asked={}
local function dark(op)asked[#asked+1]=op.row;return op.row==3 end
local two=packet(2,{81,85,65});two.operations[2]={row=3,difficulty=10,missions={{native_type=85}}}
assert(not S.find(two,10,{required={[2]=true,[4]=true}},nil,function()return false end),'day/night veto')
assert(S.find(two,10,{required={[2]=true,[4]=true}},nil,function()return true end).row==2)
assert(S.find(two,10,{required={}},nil,dark).row==3 and #asked==2,'day/night alone')
asked={};assert(not S.find(two,10,{required={[2]=true,[4]=true}},nil,dark) and #asked==1,'asked only for a matching operation')
local split=packet(1,{59});split.operations[2]={row=3,difficulty=10,missions={{native_type=81}}}
assert(not S.find(split,10,{required={[1]=true,[2]=true}}),'must match one operation')
local n=0
local function call()n=n+1 end
s=S.new();p=packet(1,{65});s:start(p,10,{[1]=true},0);s:advance(p,0,call)
for i=1,29 do s:advance(p,i,call)end
assert(n==1);s:advance(nil,31,call);assert(not s.running and n==1)
s=S.new();n=0;s:start(p,10,{[1]=true},0)
for i=0,30 do s:advance(packet(i+1,{65}),i,call)end
assert(n==5 and s.calls==5 and not s.running)
assert(not pcall(function()s:start(p,10,{[1]=true},32)end))
s=S.new();n=0;s:start(p,10,{[1]=true},0);s:advance(p,0,call);s:cancel();s:advance(packet(2,{65}),9,call)
assert(n==1);s:start(packet(2,{65}),10,{[1]=true},10);assert(s.calls==1)
s:advance(packet(2,{65},'other'),10,call);assert(not s.running and n==1)
assert(not pcall(function()S.new():start(p,1,{[1]=true,[2]=true},0)end))
assert(not pcall(function()S.new():start(p,10,{},0)end))
-- Combined mode can pass the old cap, but never outruns publication or pacing.
s=S.new({max_calls=false,interval=1});n=0
s:start(p,10,{[1]=true,[2]=true},0);s:advance(p,0,call)
s:advance(packet(2,{65}),0.99,call);assert(n==1)
s:advance(packet(2,{65}),1,call);assert(n==2)
s:advance(packet(2,{65}),2,call);assert(n==2,'same seed must not reroll')
for i=3,8 do s:advance(packet(i,{65}),i,call)end
assert(n==8 and s.running,'must continue beyond five calls')
s:advance(packet(9,{59,81,65}),9,call)
assert(s.match and not s.running and n==8,'match both requirements after the old cap')
s:start(packet(9,{65}),10,{[1]=true},9);s:advance(packet(9,{65}),9,call)
assert(n==9,'another search needs no process restart')
s:cancel();s:start(packet(10,{65}),10,{[1]=true},9.1)
s:advance(packet(10,{65}),9.1,call);assert(n==9,'restart must preserve pacing')
s:advance(packet(10,{65}),10,call);assert(n==10)
s:advance(nil,41,call);assert(not s.running and n==10,'unlimited mode still times out stalled refresh')
s:start(packet(11,{65}),10,{[1]=true},42)
s:advance(packet(11,{65}),223,call);assert(not s.running and n==10,'search time limit remains')
-- The operation in progress: a 92-byte record as hex, whose row (bytes 0-3),
-- planet (16-17), difficulty (32) and in-progress flag (52) the dialog and
-- the search read.
local function active(row,planet,level,flag)
    local out={};for i=1,92 do out[i]='00' end
    out[1]=string.format('%02x',row%256);out[2]=string.format('%02x',math.floor(row/256))
    out[17]=string.format('%02x',planet%256);out[18]=string.format('%02x',math.floor(planet/256))
    out[33]=string.format('%02x',level);out[53]=flag or '01'
    return table.concat(out)
end
local row,level=S.active_row({planet=269,active=active(49,269,10)})
assert(row==49 and level==10,'The operation in progress on this planet')
row,level=S.active_row({planet=300,active=active(300,300,7)})
assert(row==300 and level==7,'Rows and planets span two bytes')
assert(S.active_row({planet=268,active=active(49,269,10)})==nil,'Another planet')
assert(S.active_row({planet=269,active=active(49,269,10,'00')})==nil,'Not in progress')
assert(S.active_row({planet=269,active=active(49,269,10):sub(3)})==nil,'A truncated record')
assert(S.active_row({planet=269})==nil and S.active_row(nil)==nil,'No record or no snapshot')
-- Side objectives: every required row and no excluded one, on the same
-- mission as its family; without a checked family across the operation.
local function op(row,missions)return {row=row,difficulty=10,missions=missions}end
local lidar,artillery,sam=0xf1969b14,0x86cfeedb,0xc46443b2
local board={operations={
    op(1,{{native_type=0,objectives={[artillery]=true,[lidar]=true}},{native_type=22,objectives={}}}),
    op(2,{{native_type=0,objectives={[lidar]=true,[sam]=true}},{native_type=22,objectives={[artillery]=true}}}),
    op(3,{{native_type=0}}),
}}
local function rows(group,rules)return {groups={[group]=rules}}end
local icbm={[1]=true}
assert(S.find(board,10,{required=icbm,objectives=rows(1,{[lidar]='require'})}).row==1)
assert(S.find(board,10,{required=icbm,objectives=rows(1,{[lidar]='require',[artillery]='exclude'})}).row==2,'Excluded on the mission')
assert(S.find(board,10,{required=icbm,objectives=rows(1,{[lidar]='require',[sam]='require'})}).row==2,'Every required row')
assert(not S.find(board,10,{required=icbm,objectives=rows(1,{[lidar]='require',[artillery]='require',[sam]='require'})}),'All of them')
assert(S.find(board,10,{required={},objectives=rows(0,{[sam]='require',[artillery]='require'})}).row==2,'Across the operation')
assert(not S.find(board,10,{required={},objectives=rows(0,{[lidar]='require',[artillery]='exclude'})}),'Excluded anywhere in the operation')
assert(not S.find({operations={board.operations[3]}},10,{required={},objectives=rows(0,{[lidar]='exclude'})}),'Unresolved objectives never match')
assert(not S.find({operations={board.operations[3]}},10,{required=icbm,objectives=rows(1,{[lidar]='exclude'})}))
assert(S.find({operations={board.operations[3]}},10,{required=icbm,objectives={groups={}}}).row==3,'No rules, no objectives needed')
print('search: existing match, AND, pacing, timeout, legacy budget, uncapped mode, cancellation, context, operation in progress and side objectives passed')
