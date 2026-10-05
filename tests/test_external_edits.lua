-- luajit tests/test_external_edits.lua src/external_edits.lua
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local E=H.module(arg[1])
local function word(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)
end
-- A board of rows {row={id,seed,difficulty}} as the game's 110-row buffer.
local function buffer(rows)
    local parts={}
    for row=0,109 do
        local r=rows[row]
        local bytes=string.rep('\0',92)
        if r then
            bytes=string.rep('\0',12)..word(r.seed)..string.rep('\0',8)..string.char(r.id)..string.rep('\0',7)
                ..string.char(r.difficulty)..string.rep('\0',19)..string.char(1)..string.rep('\0',39)
        end
        parts[#parts+1]=bytes
    end
    return table.concat(parts)
end
-- The prediction for rows 27-29 of the planet in the 2026-10-01 log, after
-- row 26, which stands for the 27 rows that match before them.
local predicted={[26]={id=20,seed=555,difficulty=9},[27]={id=22,seed=1214857270,difficulty=10},[28]={id=23,seed=1048270963,difficulty=10},
    [29]={id=21,seed=777,difficulty=10}}
local function copy(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
-- A comparison result shaped like identity_probe.lua's compare.
local function compare(live)
    local differences,matched_rows,matched={},{},0
    for row=26,29 do
        local o,p=live[row],predicted[row]
        if o and o.id==p.id and o.seed==p.seed and o.difficulty==p.difficulty then
            matched=matched+1;matched_rows[#matched_rows+1]=row
        elseif o then differences[#differences+1]={row=row,kind='value',observed=o,predicted=p}
        else differences[#differences+1]={row=row,kind='predicted row absent',predicted=p}end
    end
    return {passed=#differences==0,matched=matched,differences=differences,matched_rows=matched_rows}
end
local planet,seed=201,1263716310

-- Rows round-trip through the buffer.
local decoded=E.rows(buffer(predicted))
assert(decoded[28].id==23 and decoded[28].seed==1048270963 and decoded[28].difficulty==10 and not decoded[0])

-- The log case: F6 gave row 28 a new seed; row 29 still matches.
local live=copy(predicted);live[28]={id=23,seed=3061063729,difficulty=10}
local edits=assert(E.classify(compare(live),{},planet,seed))
assert(edits.count==1 and edits.rows[28].evidence=='later_rows' and edits.rows[28].observed.seed==3061063729)

-- The last row has no row after it: unproven without a baseline.
live=copy(predicted);live[29]={id=21,seed=999,difficulty=10}
local none,why=E.classify(compare(live),{},planet,seed)
assert(none==nil and why:find('row=29 no matching row after it',1,true),why)
-- With the planet seen before F6 under the same seed it is proven.
local store={}
assert(E.observe(store,planet,seed,buffer(predicted)))
edits=assert(E.classify(compare(live),store,planet,seed))
assert(edits.rows[29].evidence=='baseline')
-- A baseline under another campaign seed proves nothing.
assert(E.classify(compare(live),store,planet,seed+1)==nil)

-- F6 over several operations: each row needs its own proof.
live=copy(predicted)
live[27]={id=22,seed=1,difficulty=10};live[28]={id=23,seed=2,difficulty=10};live[29]={id=21,seed=3,difficulty=10}
none,why=E.classify(compare(live),{},planet,seed)
assert(none==nil and why:find('row=27 no matching row after it',1,true),why)
edits=assert(E.classify(compare(live),store,planet,seed))
assert(edits.count==3)
live[29]=predicted[29]
edits=assert(E.classify(compare(live),{},planet,seed))
assert(edits.count==2 and edits.rows[27].evidence=='later_rows' and edits.rows[28].evidence=='later_rows')

-- A different operation type is accepted only on a baseline.
live=copy(predicted);live[28]={id=5,seed=3061063729,difficulty=10}
none,why=E.classify(compare(live),{},planet,seed)
assert(none==nil and why:find('operation type differs',1,true),why)
assert(E.classify(compare(live),store,planet,seed).rows[28].evidence=='baseline')

-- Never: a changed difficulty, the operation in progress, or a missing row.
live=copy(predicted);live[28]={id=23,seed=3061063729,difficulty=9}
none,why=E.classify(compare(live),store,planet,seed)
assert(none==nil and why:find('difficulty differs',1,true),why)
local result=compare(copy(predicted));result.passed=false
result.differences={{row=28,kind='value',observed={id=23,seed=4,difficulty=10},
    predicted={id=23,seed=1048270963,difficulty=10,preserved=true}}}
none,why=E.classify(result,store,planet,seed)
assert(none==nil and why:find('operation in progress',1,true),why)
live=copy(predicted);live[28]=nil
none,why=E.classify(compare(live),store,planet,seed)
assert(none==nil and why:find('predicted row absent',1,true),why)
assert(E.classify(compare(copy(predicted)),store,planet,seed)==nil,'A pass has no edits')

-- The baseline keeps the first board under a seed, so an edit seen later
-- cannot prove itself; a new seed replaces it.
live=copy(predicted);live[29]={id=21,seed=999,difficulty=10}
assert(not E.observe(store,planet,seed,buffer(live)))
assert(E.known(store,planet,seed) and store[planet].rows[29].seed==777)
assert(E.observe(store,planet,seed+1,buffer(live)) and store[planet].rows[29].seed==999)
local crowded={}
for p=0,63 do E.observe(crowded,p,1,buffer(predicted))end
E.observe(crowded,64,1,buffer(predicted))
local count=0;for _ in pairs(crowded)do count=count+1 end
assert(count==1 and crowded[64],'The store stays bounded')

-- Composition passes only when every failed row is an edit.
local rows={[28]=true}
assert(E.composition_passes({passed=true},nil))
assert(E.composition_passes({passed=false,general=0,checked=60,failed_rows={[28]=true}},rows))
assert(not E.composition_passes({passed=false,general=0,checked=60,failed_rows={[28]=true}},nil))
assert(not E.composition_passes({passed=false,general=0,checked=60,failed_rows={[27]=true,[28]=true}},rows))
assert(not E.composition_passes({passed=false,general=1,checked=60,failed_rows={[28]=true}},rows))
assert(not E.composition_passes({passed=false,general=0,checked=0,failed_rows={[28]=true}},rows))
assert(not E.composition_passes({passed=false,checked=60,failed_rows={[28]=true}},rows),'An older result fails closed')

-- without drops the edited rows from a live board.
local kept=E.without({{row=27},{row=28},{row=29}},rows)
assert(#kept==2 and kept[1].row==27 and kept[2].row==29)
assert(#E.without({{row=1}},nil)==1)
print('External edits: proof per row, F6 over several operations, rejections, bounded baseline and composition passed')
