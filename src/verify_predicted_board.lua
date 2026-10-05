-- Compare every generated descriptor before selecting a published match.
local _,Board=...
return function(snapshot,predicted)
    if #snapshot.decoded.operations~=#predicted then return false,'Operation count differs' end
    local observed={};for _,op in ipairs(snapshot.decoded.operations)do observed[op.row]=op end
    for _,p in ipairs(predicted)do
        local op=observed[p.row];local ops,row=snapshot.operations,p.row
        if not p.valid or not op or op.operation_id~=p.id or op.seed~=p.seed or op.difficulty~=p.difficulty
            or Board.category(ops,row)~=p.category or Board.faction(ops,row)~=p.faction
            or Board.explicit_hash(ops,row)~=p.explicit_hash or op.template_index~=p.template_index then
            return false,'Operation base/template differs at row '..p.row
        end
        if #p.modifiers~=Board.modifier_count(ops,row) then return false,'Modifier count differs' end
        for i,id in ipairs(p.modifiers)do if Board.modifier(ops,row,i)~=id then return false,'Modifier differs' end end
        if #op.missions~=#p.missions then return false,'Mission count differs' end
        for i,m in ipairs(p.missions)do
            local actual=op.missions[i]
            if actual.seed~=m.seed or actual.native_type~=m.native_type or actual.level_index~=m.level_index then
                return false,'Mission descriptor differs at row '..p.row..' slot '..i
            end
        end
    end
    return true
end
