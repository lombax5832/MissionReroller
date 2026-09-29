-- Uses the Windows SHA256 declarations installed by experiment_adapter.
return function(bytes)
    local ffi=require('ffi');local bcrypt=ffi.load('bcrypt')
    local algorithm,hash=ffi.new('void *[1]'),ffi.new('void *[1]')
    local ok,result=pcall(function()
        local name=ffi.new('uint16_t[7]',{83,72,65,50,53,54,0})
        assert(bcrypt.BCryptOpenAlgorithmProvider(algorithm,name,nil,0)==0,'SHA256 unavailable')
        assert(bcrypt.BCryptCreateHash(algorithm[0],hash,nil,0,nil,0,0)==0,'SHA256 creation failed')
        assert(bcrypt.BCryptHashData(hash[0],bytes,#bytes,0)==0,'SHA256 update failed')
        local digest=ffi.new('uint8_t[32]')
        assert(bcrypt.BCryptFinishHash(hash[0],digest,32,0)==0,'SHA256 finish failed')
        local parts={};for i=0,31 do parts[#parts+1]=string.format('%02x',digest[i]) end
        return table.concat(parts)
    end)
    if hash[0]~=nil then bcrypt.BCryptDestroyHash(hash[0]) end
    if algorithm[0]~=nil then bcrypt.BCryptCloseAlgorithmProvider(algorithm[0],0) end
    assert(ok,result);return result
end
