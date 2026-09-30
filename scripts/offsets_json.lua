-- Print src/offsets.lua as JSON for the Python tools (scripts/offsets.py).
-- A table with both list values and named keys, such as a struct field
-- {0x78e84,unverified=true}, becomes an object whose list is under "values".
local offsets=dofile(assert(arg[1],'usage: offsets_json.lua <src/offsets.lua>'))
local function encode(value)
    local kind=type(value)
    if kind=='number' then
        assert(value==math.floor(value),'offsets hold integers only')
        return string.format('%d',value)
    elseif kind=='string' then
        return '"'..value:gsub('[%c"\\]',function(c)return string.format('\\u%04x',c:byte())end)..'"'
    elseif kind=='boolean' then
        return tostring(value)
    end
    assert(kind=='table','unsupported value '..kind)
    local list,keys={},{}
    for i=1,#value do list[i]=encode(value[i])end
    for key in pairs(value)do
        if type(key)=='string' then keys[#keys+1]=key
        else assert(type(key)=='number' and key>=1 and key<=#value,'unsupported key')end
    end
    table.sort(keys)
    if #keys==0 and #list>0 then return '['..table.concat(list,',')..']'end
    local parts={}
    if #list>0 then parts[1]='"values":['..table.concat(list,',')..']'end
    for _,key in ipairs(keys)do parts[#parts+1]=encode(key)..':'..encode(value[key])end
    return '{'..table.concat(parts,',')..'}'
end
io.write(encode(offsets),'\n')
