-- Capture rule inputs and compare predicted descriptors. With make_bases,
-- operation bases come from campaign state and the requested seed. Without it,
-- retain the earlier base-input checkpoint for isolated tests. The canonical
-- active operation remains an explicitly preserved input in either mode.
-- bind is Planet.bind (planet_model.lua): the inputs decode through the
-- capture's own cached reads.
local O,Board=...
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
                assert(type(op.difficulty)=='number',string.format('[COMPOSITION_INPUT] decoded row=%s difficulty=%s raw_difficulty=%s',
                    tostring(op.row),tostring(op.difficulty),tostring(Board.difficulty(snapshot.operations,op.row))))
                operations[#operations+1]={row=op.row,id=op.operation_id,seed=op.seed,difficulty=op.difficulty,
                    faction=Board.faction(snapshot.operations,op.row),category=Board.category(snapshot.operations,op.row),
                    explicit_hash=Board.explicit_hash(snapshot.operations,op.row)}
            end end
            local bytes=take(snapshot.board+O.board.active_snapshot,Board.OPERATION_SIZE);local active
            if Board.valid(bytes,0) and Board.planet(bytes,0)==snapshot.planet then
                active={row=Board.row(bytes,0),seed=Board.seed(bytes,0),id=Board.operation_id(bytes,0),template_index=Board.template_index(bytes,0)}
                assert(Board.modifier_count(bytes,0)<=2,'Invalid preserved modifier count')
                active.modifiers=Board.modifiers(bytes,0)
            end
            if make_bases then
                operations,active=make_bases(take,u,pointer,game,snapshot.board,definitions,snapshot.planet,inputs)(snapshot.seed)
            end
            local predicted=predict(operations,snapshot.planet,inputs,function(op)return level(definitions,op)end,active)
            local errors,checked,templates,modifiers,bases={},0,0,0,0
            -- failed_rows and general (errors of no row) let a caller excuse
            -- rows another mod edited (external_edits.lua).
            local failed_rows,general={},0
            local function fail(row,text)
                errors[#errors+1]=text
                if row then failed_rows[row]=true else general=general+1 end
            end
            local by_row={};for _,op in ipairs(snapshot.decoded.operations)do by_row[op.row]=op end
            if #predicted~=#snapshot.decoded.operations then fail(nil,'operation count mismatch')end
            for i,op in ipairs(predicted)do
                local observed=by_row[op.row];local ops,row=snapshot.operations,op.row
                local prefix='row='..op.row..' '
                if not observed then fail(op.row,prefix..'predicted row absent')
                elseif not op.valid then fail(op.row,prefix..'predicted invalid')
                else
                    if make_bases then
                        if op.id==observed.operation_id and op.seed==observed.seed and op.difficulty==observed.difficulty
                            and op.category==Board.category(ops,row) and op.faction==Board.faction(ops,row)
                            and op.explicit_hash==Board.explicit_hash(ops,row) then bases=bases+1
                        else fail(op.row,prefix..'base fields mismatch')end
                    end
                    if op.template_index~=Board.template_index(ops,row) then fail(op.row,prefix..'template mismatch')
                    else templates=templates+1 end
                    local same=#op.modifiers==Board.modifier_count(ops,row)
                    for j,id in ipairs(op.modifiers)do if id~=Board.modifier(ops,row,j)then same=false end end
                    if same then modifiers=modifiers+1 else fail(op.row,prefix..'modifier mismatch')end
                    if #op.missions~=#observed.missions then fail(op.row,prefix..'mission count mismatch')
                    else
                        for slot,mission in ipairs(op.missions)do
                            local actual=observed.missions[slot]
                            if mission.seed==actual.seed and mission.native_type==actual.native_type and mission.level_index==actual.level_index then checked=checked+1
                            else fail(op.row,string.format('%sslot=%d predicted=%d/%u/level%d actual=%d/%u/level%d',
                                prefix,slot-1,mission.native_type,mission.seed,mission.level_index,actual.native_type,actual.seed,actual.level_index))end
                        end
                    end
                end
            end
            return {passed=#errors==0 and checked>0,checked=checked,templates=templates,modifiers=modifiers,
                operations=#predicted,errors=errors,failed_rows=failed_rows,general=general,
                independent_bases=make_bases~=nil,bases=bases},table.concat(parts)
        end
    end
end
