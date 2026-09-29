-- Read-only capture and comparison for the partial Lua generation port.
return function(read,u,predict,special_inputs,levels_factory,verify_levels,composition_capture)
    local ffi=require('ffi')
    local function address_number(address)return tonumber(ffi.cast('uintptr_t',address))end
    local probe={}
    function probe:capture(snapshot)
        local b,planet=snapshot.board,snapshot.planet
        local key=read(b+0x101454+planet*0x118,4)
        local definitions,identity
        for _,offset in ipairs({0x22b1a8,0x2cc9ec,0x36e230})do
            local id=read(b+offset,4)
            if id==key then definitions=b+offset;identity=id;break end
        end
        assert(definitions,'Planet definitions are not cached')
        local count=read(definitions+0xa183c,4)
        local active=read(b+0x17a2c0,92)
        local input={planet=planet,pool_count=u(count,0),max_difficulty=10}
        if active:byte(53)~=0 then
            input.active={row=u(active,0),id=active:byte(25),seed=u(active,12),
                difficulty=active:byte(33),planet=active:byte(17)+active:byte(18)*256}
        end
        local special_key=''
        if special_inputs then input.specials,special_key=special_inputs(b,planet,definitions)end
        local captured={input=input,seed=snapshot.seed,operations=snapshot.operations,definitions=definitions,
            fingerprint=snapshot.fingerprint..string.format('%.0f',address_number(definitions))..identity..key..count..active..special_key}
        if levels_factory then
            local cache={}
            local collect=levels_factory(function(address,size)
                -- Game tostring may return the same display text for every
                -- pointer. User-space addresses fit exactly in Lua numbers.
                local at=address_number(address)
                local sizes=cache[at]
                if not sizes then sizes={};cache[at]=sizes end
                if not sizes[size] then sizes[size]=read(address,size)end
                return sizes[size]
            end)
            local keys={}
            captured.level_graphs={};captured.level_operations=snapshot.decoded.operations
            for _,operation in ipairs(captured.level_operations)do
                local ok,levels,special,graph_key=pcall(collect,definitions,{id=operation.operation_id,
                    category=u(snapshot.operations,operation.row*92+28)})
                assert(ok,string.format('planet=%d seed=%u row=%d: %s',planet,snapshot.seed,operation.row,tostring(levels)))
                captured.level_graphs[operation.row]={levels=levels,special=special}
                keys[#keys+1]=graph_key
            end
            captured.fingerprint=captured.fingerprint..table.concat(keys)
        end
        if composition_capture then
            local key
            captured.composition,key=composition_capture(snapshot,definitions)
            captured.fingerprint=captured.fingerprint..key
        end
        return captured
    end
    function probe:compare_levels(capture)
        assert(verify_levels and capture.level_graphs,'Level verification not configured')
        return verify_levels(capture.level_operations,capture.level_graphs)
    end
    function probe:compare(capture)
        local predicted=predict(capture.input,capture.seed)
        local matched,observed_count,predicted_count,errors=0,0,0,{}
        assert(#capture.operations==110*92,'Invalid operation buffer')
        for row=0,109 do
            local offset=row*92
            local valid=capture.operations:byte(offset+53)~=0
            local p=predicted[row]
            if p then predicted_count=predicted_count+1 end
            if valid then observed_count=observed_count+1 end
            if valid and p then
                local id=capture.operations:byte(offset+25)
                local seed=u(capture.operations,offset+12)
                local difficulty=capture.operations:byte(offset+33)
                if id==p.id and seed==p.seed and difficulty==p.difficulty then matched=matched+1
                else errors[#errors+1]=string.format('row=%d observed=%d/%u/d%d predicted=%d/%u/d%d',row,id,seed,difficulty,p.id,p.seed,p.difficulty)end
            elseif valid or p then errors[#errors+1]='row='..row..(valid and ' unexpected live row' or ' predicted row absent')end
        end
        return {matched=matched,observed=observed_count,predicted=predicted_count,errors=errors,
            passed=#errors==0 and observed_count>0}
    end
    return probe
end
