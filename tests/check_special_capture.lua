local fixture=dofile(arg[1])
local function bytes(hex)return (hex:gsub('..',function(s)return string.char(tonumber(s,16))end))end
local ranges={}
for _,range in ipairs(fixture.ranges)do ranges[#ranges+1]={address=tonumber(range.address),data=bytes(range.hex)}end
local function read(address,size)
    for _,range in ipairs(ranges)do
        local offset=address-range.address
        if offset>=0 and offset+size<=#range.data then return range.data:sub(offset+1,offset+size)end
    end
    error(string.format('Missing captured read 0x%x/%d',address,size))
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d);return a+b*256+c*65536+d*16777216 end
local function pointer(s)local n=u(s,0)+4294967296*u(s,4);if n>=65536 and n<140737488355328 then return n end end
local root=arg[2]
local predict=dofile(root..'/src/operation_identity.lua')(dofile(root..'/src/generation_rng.lua'))
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local collect=H.module(root..'/src/special_operation_inputs.lua')(read,u,pointer)
local probe=H.module(root..'/src/identity_probe.lua')(read,u,predict,collect)
local b=tonumber(fixture.board)
local s={board=b,planet=fixture.planet,seed=u(read(b+0x17a2bc,4),0),operations=read(b+0xf7280,110*92),fingerprint='captured'}
local captured=probe:capture(s)
local result=probe:compare(captured)
assert(result.passed,table.concat(result.errors,'\n'))
assert(#captured.input.specials==1 and result.matched==40,'Expected captured special-event coverage')
print('Captured campaign inputs -> Lua prediction: all 40 rows matched, including 10 special rows; no generated rows used as predictor inputs')
