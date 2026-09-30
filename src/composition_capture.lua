-- Capture rule inputs and compare predicted descriptors. With make_bases,
-- operation bases come from campaign state and the requested seed. Without it,
-- retain the earlier base-input checkpoint for isolated tests. The canonical
-- active operation remains an explicitly preserved input in either mode.
-- bind is Planet.bind (planet_model.lua): the inputs decode through the
-- capture's own cached reads.
return function(bind,make_levels,predict,make_bases)
    local ffi=require('ffi')
    return function(read,u,pointer,game)
        return function(snapshot,definitions)
            local cache,parts={},{}
            local function take(address,size)
                local at=tonumber(ffi.cast('uintptr_t',address))
                local key=string.format('%.0f:%d',at,size)
                if not cache[key] then
                    local bytes=read(address,size)
                    assert(bytes and #bytes==size,'Short composition input')
                    cache[key]=bytes;parts[#parts+1]=key..':'..bytes
                end
                return cache[key]
            end
            local inputs=bind(take,u,pointer,game,snapshot.board,snapshot.planet).inputs()
            local level=make_levels(take,u,game)
            local operations={}
            if not make_bases then for _,op in ipairs(snapshot.decoded.operations)do
                local at=op.row*92
                assert(type(op.difficulty)=='number',string.format('[COMPOSITION_INPUT] decoded row=%s difficulty=%s raw_difficulty=%s',
                    tostring(op.row),tostring(op.difficulty),tostring(snapshot.operations:byte(at+33))))
                operations[#operations+1]={row=op.row,id=op.operation_id,seed=op.seed,difficulty=op.difficulty,
                    faction=u(snapshot.operations,at+36),category=u(snapshot.operations,at+28),explicit_hash=u(snapshot.operations,at+8)}
            end end
            local bytes=take(snapshot.board+0x17a2c0,92);local active
            if bytes:byte(53)~=0 and bytes:byte(17)+bytes:byte(18)*256==snapshot.planet then
                active={row=u(bytes,0),seed=u(bytes,12),id=bytes:byte(25),template_index=u(bytes,56),modifiers={}}
                assert(bytes:byte(69)<=2,'Invalid preserved modifier count')
                for i=0,bytes:byte(69)-1 do active.modifiers[#active.modifiers+1]=u(bytes,60+i*4)end
            end
            if make_bases then
                operations,active=make_bases(take,u,pointer,game,snapshot.board,definitions,snapshot.planet,inputs)(snapshot.seed)
            end
            local predicted=predict(operations,snapshot.planet,inputs,function(op)return level(definitions,op)end,active)
            local errors,checked,templates,modifiers,bases={},0,0,0,0
            local by_row={};for _,op in ipairs(snapshot.decoded.operations)do by_row[op.row]=op end
            if #predicted~=#snapshot.decoded.operations then errors[#errors+1]='operation count mismatch'end
            for i,op in ipairs(predicted)do
                local observed=by_row[op.row];local at=op.row*92
                local prefix='row='..op.row..' '
                if not observed then errors[#errors+1]=prefix..'predicted row absent'
                elseif not op.valid then errors[#errors+1]=prefix..'predicted invalid'
                else
                    if make_bases then
                        if op.id==observed.operation_id and op.seed==observed.seed and op.difficulty==observed.difficulty
                            and op.category==u(snapshot.operations,at+28) and op.faction==u(snapshot.operations,at+36)
                            and op.explicit_hash==u(snapshot.operations,at+8) then bases=bases+1
                        else errors[#errors+1]=prefix..'base fields mismatch'end
                    end
                    if op.template_index~=u(snapshot.operations,at+56) then errors[#errors+1]=prefix..'template mismatch'
                    else templates=templates+1 end
                    local same=#op.modifiers==snapshot.operations:byte(at+69)
                    for j,id in ipairs(op.modifiers)do if id~=u(snapshot.operations,at+56+j*4)then same=false end end
                    if same then modifiers=modifiers+1 else errors[#errors+1]=prefix..'modifier mismatch'end
                    if #op.missions~=#observed.missions then errors[#errors+1]=prefix..'mission count mismatch'
                    else
                        for slot,mission in ipairs(op.missions)do
                            local actual=observed.missions[slot]
                            if mission.seed==actual.seed and mission.native_type==actual.native_type and mission.level_index==actual.level_index then checked=checked+1
                            else errors[#errors+1]=string.format('%sslot=%d predicted=%d/%u/level%d actual=%d/%u/level%d',
                                prefix,slot-1,mission.native_type,mission.seed,mission.level_index,actual.native_type,actual.seed,actual.level_index)end
                        end
                    end
                end
            end
            return {passed=#errors==0 and checked>0,checked=checked,templates=templates,modifiers=modifiers,
                operations=#predicted,errors=errors,independent_bases=make_bases~=nil,bases=bases},table.concat(parts)
        end
    end
end
