-- Read-only capture and comparison for the partial Lua generation port.
local O,Board=...
return function(read,u,predict,special_inputs,levels_factory,verify_levels,composition_capture)
    local ffi=require('ffi')
    local function address_number(address)return tonumber(ffi.cast('uintptr_t',address))end
    local probe={}
    function probe:capture(snapshot)
        local b,planet=snapshot.board,snapshot.planet
        local key=read(b+O.board.campaign+0x1c+planet*O.campaign.definition_stride,4)
        local definitions,identity
        for _,offset in ipairs(O.board.definitions)do
            local id=read(b+offset,4)
            if id==key then definitions=b+offset;identity=id;break end
        end
        assert(definitions,'Planet definitions are not cached')
        local count=read(definitions+O.definitions.pool_count,4)
        local active=read(b+O.board.active_snapshot,Board.OPERATION_SIZE)
        local input={planet=planet,pool_count=u(count,0),max_difficulty=10}
        if Board.valid(active,0)then
            input.active={row=Board.row(active,0),id=Board.operation_id(active,0),seed=Board.seed(active,0),
                difficulty=Board.difficulty(active,0),planet=Board.planet(active,0)}
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
                    category=Board.category(snapshot.operations,operation.row)})
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
    -- skip: rows another mod edited (external_edits.lua), left unchecked.
    function probe:compare_levels(capture,skip)
        assert(verify_levels and capture.level_graphs,'Level verification not configured')
        local operations=capture.level_operations
        if skip then
            operations={}
            for _,op in ipairs(capture.level_operations)do if not skip[op.row] then operations[#operations+1]=op end end
        end
        return verify_levels(operations,capture.level_graphs)
    end
    -- differences lists each failing row as {row,kind,observed,predicted};
    -- kind is value, unexpected live row or predicted row absent.
    function probe:compare(capture)
        local predicted=predict(capture.input,capture.seed)
        local matched,observed_count,predicted_count,errors=0,0,0,{}
        local differences,matched_rows={},{}
        assert(#capture.operations==Board.OPERATIONS*Board.OPERATION_SIZE,'Invalid operation buffer')
        for row=0,109 do
            local valid=Board.valid(capture.operations,row)
            local p=predicted[row]
            if p then predicted_count=predicted_count+1 end
            if valid then observed_count=observed_count+1 end
            if valid and p then
                local id=Board.operation_id(capture.operations,row)
                local seed=Board.seed(capture.operations,row)
                local difficulty=Board.difficulty(capture.operations,row)
                if id==p.id and seed==p.seed and difficulty==p.difficulty then matched=matched+1;matched_rows[#matched_rows+1]=row
                else
                    errors[#errors+1]=string.format('row=%d observed=%d/%u/d%d predicted=%d/%u/d%d',row,id,seed,difficulty,p.id,p.seed,p.difficulty)
                    differences[#differences+1]={row=row,kind='value',observed={id=id,seed=seed,difficulty=difficulty},predicted=p}
                end
            elseif valid or p then
                local kind=valid and 'unexpected live row' or 'predicted row absent'
                errors[#errors+1]='row='..row..' '..kind
                differences[#differences+1]={row=row,kind=kind,predicted=p}
            end
        end
        return {matched=matched,observed=observed_count,predicted=predicted_count,errors=errors,
            differences=differences,matched_rows=matched_rows,passed=#errors==0 and observed_count>0}
    end
    return probe
end
