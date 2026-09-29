-- Data only: never evaluate a candidate file as Lua.
return function(path)
    local f=assert(io.open(path,'rb'),'Candidate file unavailable')
    local text=f:read(4097);f:close()
    assert(text and #text<=4096,'Candidate file too large')
    local numbers={seed=true,planet=true,difficulty=true,row=true,operation_seed=true,baseline_seed=true}
    local hashes={active_hash=true,operation_hash=true,mission_hash=true,baseline_operation_hash=true,baseline_mission_hash=true}
    local result={};local count=0
    for line in text:gmatch('[^\r\n]+')do
        local key,value=line:match('^([a-z_]+)=([a-z0-9]+)$')
        assert(key and not result[key],'Malformed or duplicate candidate field')
        if numbers[key] then
            assert(value:match('^%d+$'),'Invalid candidate number')
            value=assert(tonumber(value));assert(value>=0 and value<=4294967295 and value==math.floor(value),'Candidate number outside uint32')
        else assert(hashes[key] and #value==64 and value:match('^[0-9a-f]+$'),'Invalid candidate digest') end
        result[key]=value;count=count+1
    end
    assert(count==11,'Incomplete candidate')
    for key in pairs(numbers)do assert(result[key]~=nil,'Missing candidate field')end
    for key in pairs(hashes)do assert(result[key]~=nil,'Missing candidate digest')end
    assert(result.planet<512 and result.row<110 and result.difficulty>=1 and result.difficulty<=10,'Invalid candidate context')
    return result
end
