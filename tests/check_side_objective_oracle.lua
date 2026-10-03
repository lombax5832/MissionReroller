-- Usage: luajit check_side_objective_oracle.lua <capture.lua> <src> <cases.lua> <missing page file>
-- Replays scripts/validate_side_objectives.py's emulated descriptors: the
-- Lua port gives the native objectives and roles for every case on the
-- captured pages. A page absent from the capture is written to
-- <missing page file>, exit 3.
local fixture=dofile(arg[1]);local root=arg[2];local cases=dofile(arg[3]);local ffi=require('ffi')
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local pages={}
for _,r in ipairs(fixture.ranges)do pages[tonumber(r.address)]=raw(r.hex)end
local function read(a,n)
    a=tonumber(ffi.cast('uintptr_t',a))
    local pieces={};local remaining=n;local at=a
    while remaining>0 do
        local page=math.floor(at/4096)*4096;local offset=at-page
        local data=pages[page]
        if not data then
            local out=assert(io.open(arg[4],'w'));out:write(string.format('0x%x',page));out:close()
            os.exit(3)
        end
        local count=math.min(remaining,4096-offset);pieces[#pieces+1]=data:sub(offset+1,offset+count)
        at=at+count;remaining=remaining-count
    end
    return table.concat(pieces)
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function pointer(s,o)
    local value=ffi.new('uint64_t[1]');ffi.copy(value,s:sub((o or 0)+1,(o or 0)+8),8)
    if value[0]<0x10000 then return nil end
    return ffi.cast('uint8_t*',value[0])
end
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(root)
local function module(name)return H.module(root..'/'..name..'.lua')end
local game=ffi.cast('uint8_t*',tonumber(fixture.game));local board=tonumber(fixture.board)
local config=module('configuration_lookup')(read,u,pointer,assert(pointer(read(game+O.rva.configuration,8))))
local composition=module('composition_inputs')(read,u,pointer,game,board,config,nil,nil,nil)
local inputs=module('side_objective_inputs')(read,u,pointer,game,board,config,composition)
local Prediction=module('side_objective_prediction')
local failures,sides,tacticals=0,0,0
for n,c in ipairs(cases)do
    local context=inputs.context_of(c.modifiers)
    local mission=inputs.mission(c.kind)
    local environment=inputs.environments(c.planet,c.kind,context.modifiers)
    local list=Prediction.resolve(c.seed,c.difficulty,mission,inputs.counts(c.difficulty),inputs.scale(mission.category),
        {objective=inputs.objective,disabled=inputs.disabled,context=context,environment=function()return environment(c.seed)end})
    local got,want={},{}
    for _,o in ipairs(list)do got[#got+1]=string.format('%08x/%d',o.id,o.role)end
    for _,o in ipairs(c.expected)do
        want[#want+1]=string.format('%08x/%d',o[1],o[2])
        if o[2]==3 then sides=sides+1 elseif o[2]==2 then tacticals=tacticals+1 end
    end
    got,want=table.concat(got,' '),table.concat(want,' ')
    if got~=want then
        failures=failures+1
        if failures<=12 then
            print(string.format('MISMATCH case %d planet=%d kind=%d difficulty=%d seed=%d environment=%d\n  native %s\n  lua    %s',
                n,c.planet,c.kind,c.difficulty,c.seed,environment(c.seed),want,got))
        end
    end
end
print(string.format('side objective oracle: %d cases, %d side and %d tactical objectives, %d mismatches',#cases,sides,tacticals,failures))
os.exit(failures==0 and 0 or 1)
