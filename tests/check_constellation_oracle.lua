-- Usage: luajit check_constellation_oracle.lua <oracle.lua> <src>
-- Replays scripts/validate_constellation_choice.py cases through the packaged
-- decoders, reading the saved static tables through an injected reader.
local oracle=dofile(arg[1]);local root=arg[2]
local R=dofile(root..'/constellation_prediction.lua')
local make_inputs=dofile(root..'/constellation_inputs.lua')
local game=0x10000000;local ranges={}
for i,range in ipairs(oracle.ranges)do
    ranges[i]={first=game+range.rva,bytes=(range.hex:gsub('..',function(v)return string.char(tonumber(v,16))end))}
end
local function read(address,size)
    for _,range in ipairs(ranges)do
        local at=address-range.first
        if at>=0 and at+size<=#range.bytes then return range.bytes:sub(at+1,at+size)end
    end
    error(string.format('Read outside saved tables: %x+%d',address-game,size))
end
local function u(b,o)local a,c,d,e=b:byte(o+1,o+4);return a+c*256+d*65536+e*16777216 end
local config={hash=function()return 0 end,lookup=function()return nil end}
local inputs=make_inputs(read,u,function()return nil end,game,0,{collect=function()return {}end},config)
local checked,tagged=0,0
for _,case in ipairs(oracle.cases)do
    local faction,difficulty,kind,seed,initial,expected=unpack(case)
    local record=inputs.mission(kind)
    assert(record.faction==faction,'Mission record faction differs for '..kind)
    local result=R.resolve(seed,inputs.settings(faction,difficulty),initial,record,inputs.disabled)
    assert(table.concat(result.list,',')==table.concat(expected,','),string.format(
        'Oracle mismatch faction=%d difficulty=%d type=%d seed=%u expected=%s got=%s',
        faction,difficulty,kind,seed,table.concat(expected,','),table.concat(result.list,',')))
    checked=checked+1;if #expected>0 then tagged=tagged+1 end
end
assert(checked>=5000 and tagged>=3000,'Oracle coverage is too small')
-- Per-mission options over the saved tables. Campaign memory is not part of
-- the image, so planet-wide tags are absent here.
local C=dofile(root..'/filter_catalogue.lua');local options=dofile(root..'/search_session.lua').options
local tags={settings=inputs.settings,mission=inputs.mission,disabled=inputs.disabled,campaign=function()return {}end}
for faction=2,4 do
    for _,difficulty in ipairs({1,2,10})do
        local catalogue={faction=faction,mission_set={},native={}}
        for id,option in ipairs(options)do for _,kind in ipairs(option.ids)do
            if inputs.mission(kind).faction==faction then catalogue.native[kind]=true;catalogue.mission_set[id]=true end
        end end
        C.constellations(catalogue,tags,R.names,0,difficulty,options)
        local any=catalogue.constellation_groups[0];local expected=inputs.settings(faction,difficulty)
        local drawable=0
        for _,row in ipairs(expected.candidates)do if expected.draws>0 and row.id~=0 and row.weight>0 then drawable=drawable+1 end end
        assert(#any.list==drawable,'Any-mission options must equal the drawable candidates')
        local names={};for _,option in ipairs(any.list)do names[#names+1]=option.name end
        for id in pairs(catalogue.mission_set)do
            local group=catalogue.constellation_groups[id]
            for _,option in ipairs(group.list)do assert(any.set[option.id])end
            for _,kind in ipairs(options[id].ids)do if catalogue.native[kind]then
                for _,removed in ipairs(inputs.mission(kind).exclusions)do
                    local others=false
                    for _,other in ipairs(options[id].ids)do if other~=kind and catalogue.native[other]then others=true end end
                    assert(others or not group.set[removed],'A removed constellation must not be offered')
                end
            end end
        end
        print(string.format('faction=%d difficulty=%d any mission: %s',faction,difficulty,#names>0 and table.concat(names,'; ') or 'none'))
    end
end
print('Constellation oracle: '..checked..' saved-table cases matched ('..tagged..' with tags)')
