local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d);return a+b*256+c*65536+d*16777216 end
local function pointer(s)local n=u(s,0)+u(s,4)*4294967296;if n>=65536 and n<140737488355328 then return n end end
local function words(...)
    local result={};for _,n in ipairs({...})do result[#result+1]=word(n)end;return table.concat(result)
end
local board,planet,definitions,templates,ids,definition=1000000,100,4000000,5000000,6000000,7000000
local campaign=board+0x101438
local memory={}
memory[campaign+0x70048]=word(3)
memory[campaign+0x6c048]=words(100,1,2,0,0,0,0,0, 101,2,2,0,0,1,0,0, 100,2,2,0,0,1,0,0)
memory[campaign+0x46050+planet*0x130]='\1'
memory[definitions+0xa1834]=word(4)
memory[campaign+0x26018]=word(1)
memory[campaign+0x23018]=words(100,2,99,0,0,0)
memory[board+0x1f8908]=words(templates,0)
memory[board+0x1f8918]=word(2)
memory[board+0x1f8910]=words(ids,0)
memory[ids]=words(77,99)
memory[templates+8]=words(definition,0)
memory[definition+0x30]=words(0,99)
local function read(address,size)
    for start,bytes in pairs(memory)do
        if address>=start and address+size<=start+#bytes then return bytes:sub(address-start+1,address-start+size)end
    end
    error('Unexpected special-input read '..address)
end
local collect=dofile(arg[1]..'/special_operation_inputs.lua')(read,u,pointer)
local events,fingerprint=collect(board,planet,definitions)
assert(#events==1 and events[1].id==2 and events[1].minimum==1 and events[1].maximum==10)
local original_events=memory[campaign+0x6c048]
memory[campaign+0x6c048]=original_events:sub(1,92)..word(123)
local _,progress_key=collect(board,planet,definitions)
assert(progress_key==fingerprint,'Unrelated progress must not destabilize generation input capture')
memory[campaign+0x6c048]=original_events
memory[definition+0x30]=words(3,8)
local next_events,next_key=collect(board,planet,definitions)
assert(next_key~=fingerprint and next_events[1].minimum==3 and next_events[1].maximum==8)
memory[definition+0x30]=words(9,8);assert(#collect(board,planet,definitions)==0)
memory[definition+0x30]=words(1,10)
memory[campaign+0x46050+planet*0x130]='\0';assert(#collect(board,planet,definitions)==0)
memory[campaign+0x46050+planet*0x130]='\1'
memory[definitions+0xa1834]=word(2);assert(#collect(board,planet,definitions)==0)
memory[definitions+0xa1834]=word(4)
local saved=memory[campaign+0x6c048]
memory[campaign+0x6c048]=saved:sub(1,72)..word(1)..saved:sub(77)
assert(not pcall(collect,board,planet,definitions),'Unported faction resolver must stop, not guess')
memory[campaign+0x6c048]=saved
memory[campaign+0x70048]=word(513);assert(not pcall(collect,board,planet,definitions),'Oversized event list must fail before read')
memory[campaign+0x70048]=word(3)
memory[board+0x1f8918]=word(4097);assert(not pcall(collect,board,planet,definitions),'Oversized definition list must fail')
memory[board+0x1f8918]=word(2)
memory[templates+8]=words(0,0);assert(#collect(board,planet,definitions)==0)
memory[templates+8]=words(definition,0)
memory[campaign+0x23018]=words(101,2,99,0,0,0);assert(#collect(board,planet,definitions)==0)

local make_rng=dofile(arg[1]..'/generation_rng.lua')
local predict=dofile(arg[1]..'/operation_identity.lua')(make_rng)
local input={planet=100,pool_count=35,max_difficulty=10,specials={
    {id=2,minimum=1,maximum=2},{id=2,minimum=1,maximum=2},{id=7,minimum=10,maximum=10}}}
local rng=make_rng(123,100);for _=1,60 do rng:next()end
local rows=predict(input,123)
assert(rows[50].seed==rng:next() and rows[51].seed==rng:next() and rows[109].seed==rng:next(),
    'Special events must continue the RNG once per unoccupied row in campaign order')
input.active={row=50,id=2,seed=42,difficulty=1,planet=100}
rng=make_rng(123,100);for _=1,60 do rng:next()end
rows=predict(input,123)
assert(rows[50].seed==42 and rows[50].preserved and rows[51].seed==rng:next() and rows[109].seed==rng:next())
assert(input.active.preserved==nil and input.specials[1].minimum==1,'Caller input mutated')
input.specials[1].id=8;assert(not pcall(predict,input,123),'Out-of-range row must fail')
print('Special inputs: independent eligibility reads, range clamping, guards, fingerprints, event order, duplicate and active-row RNG behavior passed')
