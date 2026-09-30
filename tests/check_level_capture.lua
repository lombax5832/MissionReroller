local fixture=dofile(arg[1]);local root=arg[2]
local ffi=require('ffi')
-- The game's tostring renders distinct FFI pointers identically. Reproduce
-- that environment so the real capture cache cannot key on display strings.
local original_tostring=tostring
if arg[3]=='opaque-pointers' then
    _G.tostring=function(value)
        if type(value)=='cdata' then return '[cdata (deleted)]'end
        return original_tostring(value)
    end
end
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local ranges={}
for _,r in ipairs(fixture.ranges)do ranges[#ranges+1]={address=tonumber(r.address),data=raw(r.hex)}end
local function read(address,size)
    local pieces={}
    while size>0 do
        local found=false
        for _,range in ipairs(ranges)do
            local offset=address-range.address
            if offset>=0 and offset<#range.data then
                local count=math.min(size,#range.data-offset)
                pieces[#pieces+1]=range.data:sub(offset+1,offset+count)
                address=address+count;size=size-count;found=true;break
            end
        end
        assert(found,string.format('Missing level input 0x%x',address))
    end
    return table.concat(pieces)
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d);return a+b*256+c*65536+d*16777216 end
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local collect=H.module(root..'/src/level_inputs.lua')(read,u,tonumber(fixture.game))
local verify=dofile(root..'/src/level_verification.lua')(dofile(root..'/src/generation_rng.lua'),dofile(root..'/src/mission_level_choice.lua'))
local total=0
for _,case in ipairs(fixture.cases)do
    local operations,graphs={},{}
    local opbytes,missions=raw(case.operations),raw(case.missions)
    for row=0,109 do
        local at=row*92
        if opbytes:byte(at+53)~=0 then
            local operation={row=row,id=opbytes:byte(at+25),operation_id=opbytes:byte(at+25),category=u(opbytes,at+28),seed=u(opbytes,at+12),missions={}}
            local levels,special=collect(tonumber(fixture.definitions),operation)
            graphs[row]={levels=levels,special=special}
            for slot=0,opbytes:byte(at+89)-1 do
                local index=opbytes:byte(at+86+slot)*76
                operation.missions[#operation.missions+1]={seed=u(missions,index+52),level_index=u(missions,index+44)}
            end
            operations[#operations+1]=operation
        end
    end
    local result=verify(operations,graphs)
    assert(result.passed,'seed='..case.seed..'\n'..table.concat(result.errors,'\n'))
    -- Exercise the same cached capture with pointer addresses used in-game.
    local definitions=tonumber(fixture.definitions)
    local board=definitions-0x22b1a8
    local function runtime_read(address,size)
        address=tonumber(ffi.cast('uintptr_t',address))
        if address==board+0x101454 then return read(definitions,4)end
        if address==board+0x17a2c0 then return string.rep('\0',92)end
        return read(address,size)
    end
    local probe=H.module(root..'/src/identity_probe.lua')(runtime_read,u,function()end,nil,
        function(cached)return H.module(root..'/src/level_inputs.lua')(cached,u,ffi.cast('uint8_t*',tonumber(fixture.game)))end,verify)
    local captured=probe:capture({board=ffi.cast('uint8_t*',board),planet=0,seed=case.seed,
        operations=opbytes,fingerprint='fixture',decoded={operations=operations}})
    local integrated=probe:compare_levels(captured)
    assert(integrated.passed,table.concat(integrated.errors,'\n'))
    total=total+result.checked
end
print(string.format('Level input decoder and seed-conditioned replay: %d cases, %d mission levels matched',#fixture.cases,total))
