-- The numbers of src/offsets.lua for the code that reads memory:
-- O.rva.<code entry or global> and O.<struct>.<field>, a number or, for a
-- field with several values, a list. The build creates O once and hands it
-- to every module (local O=...) and runtime (host.O); tests do the same:
--   local O=dofile(src..'/offset_values.lua')(dofile(src..'/offsets.lua'))
-- An unknown name raises instead of reading nil.
return function(offsets)
    local function strict(t,what)
        return setmetatable(t,{__index=function(_,key)error('unknown offset '..what..'.'..tostring(key),2)end})
    end
    local O={build=offsets.build,rva={}}
    for _,section in ipairs({'code','globals'})do
        for name,entry in pairs(offsets[section])do
            assert(O.rva[name]==nil,'duplicate offset name '..name)
            O.rva[name]=entry.rva
        end
    end
    strict(O.rva,'rva')
    for struct,fields in pairs(offsets.structs)do
        assert(O[struct]==nil,'struct name taken: '..struct)
        local values={}
        for field,entry in pairs(fields)do
            if #entry==1 then values[field]=entry[1]
            else local list={};for i=1,#entry do list[i]=entry[i]end;values[field]=list end
        end
        O[struct]=strict(values,struct)
    end
    return strict(O,'O')
end
