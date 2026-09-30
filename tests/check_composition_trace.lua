local fixture=dofile(arg[1]);local root=arg[2];local ffi=require('ffi')
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local pages={}
for _,r in ipairs(fixture.ranges)do pages[tonumber(r.address)]=raw(r.hex)end
local function number(a)return tonumber(ffi.cast('uintptr_t',a))end
local function read(a,n)
    a=number(a);local result={}
    while n>0 do
        local page=math.floor(a/4096)*4096;local offset=a-page
        local data=assert(pages[page],string.format('Missing input page 0x%x',page))
        local count=math.min(n,4096-offset);result[#result+1]=data:sub(offset+1,offset+count)
        a=a+count;n=n-count
    end
    return table.concat(result)
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function pointer(s)local value=ffi.new('uint64_t[1]');ffi.copy(value,s,8);if value[0]==0 then return nil end;return ffi.cast('uint8_t*',value[0])end
local lookup_factory=dofile(root..'/configuration_lookup.lua')
local checked=0
local effects=dofile(root..'/campaign_effects.lua')(read,u,pointer,tonumber(fixture.game),tonumber(fixture.board))
local effect_checks=0
local Planet=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua').planet_model(root)
local inputs=Planet.bind(read,u,pointer,tonumber(fixture.game),tonumber(fixture.board),fixture.planet).inputs()
local enabled_checks=0
local category_checks=0
local choose_category=dofile(root..'/mission_category_choice.lua')
local make_rng=dofile(root..'/generation_rng.lua')
local template_checks=0
for _,r in ipairs(fixture.trace)do
    if r.name=='config_new' then
        assert(r.args[2]==1,'Unsupported configuration scope in fixture')
        local config=lookup_factory(read,u,pointer,ffi.cast('uint8_t*',r.args[1]))
        local result=config.lookup(r.args[3]%4294967296)
        assert(result==(r.value and raw(r.value) or nil),'Configuration lookup mismatch')
        checked=checked+1
    elseif r.name=='effects' then
        local result=effects.collect(r.args[4]%4294967296,r.args[5]%4294967296,r.args[6]%4294967296)
        assert(#result==#r.effects,'Effect count mismatch')
        for i,bytes in ipairs(result)do assert(bytes==raw(r.effects[i]),'Effect order mismatch')end
        effect_checks=effect_checks+1
    elseif r.name=='enabled' then
        assert(r.args[5]%256~=0,'Unexpected disabled override path')
        local result=inputs.enable(r.args[1],r.args[2]%4294967296,r.args[3]%4294967296,r.args[4]%4294967296,0x4b,0xaf218cac)
        assert(result==(r.result%256~=0),'Mission enable-rule mismatch')
        enabled_checks=enabled_checks+1
    elseif r.name=='category' then
        local op=raw(r.operation)
        local template=(r.args[4]-tonumber(fixture.game)-0x32fef10)/0x490
        local operation={faction=u(op,36),difficulty=op:byte(33),effect_id=4294967295}
        local candidates,weights,rules=inputs.candidates(template,operation,r.args[5]%4294967296)
        local usage={}
        for _,id in ipairs(r.used_types)do
            local cat=read(tonumber(fixture.game)+0x3773420+id*0x380+0x34,1):byte()
            usage[cat]=(usage[cat] or 0)+1
        end
        local rng=make_rng(0,0,raw(r.before_rng))
        local selected=choose_category(candidates,rules,usage,rng)
        assert(#selected==#r.candidates,'Decoded category candidate count')
        for i,id in ipairs(selected)do assert(id==r.candidates[i],'Decoded category order')end
        assert(rng:state_bytes()==raw(r.after_rng),'Decoded category RNG')
        category_checks=category_checks+1
    elseif r.name=='templates' then
        local operation={difficulty=r.args[4]%4294967296,category=r.args[5]%4294967296,
            faction=r.args[6]%4294967296,effect_id=r.args[3]%4294967296}
        local templates=inputs.templates(operation,r.args[2]%4294967296)
        assert(#templates==#r.candidates,'Template candidate count mismatch')
        for i,t in ipairs(templates)do assert(t.index==r.candidates[i],'Template order mismatch')end
        template_checks=template_checks+1
    end
end
print('Configuration table lookups matched: '..checked)
print('Campaign effect collections matched: '..effect_checks)
print('Mission enable rules matched: '..enabled_checks)
print('Decoded eligible pools and category choices matched: '..category_checks)
print('Decoded template candidates matched: '..template_checks)
