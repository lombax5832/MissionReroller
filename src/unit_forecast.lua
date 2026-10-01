-- Tooltips of the enemy rows. Their units come from Know Your
-- Constellation's own roster (EnemyIntelligence.roster, api 1) when that mod
-- runs for this game build; nothing of it is copied here. Without it only the
-- map-stamp note of a stamped tag is left. Pure: the dialog runtime hands in
-- the globals, the catalogue and the row.
local O=...
local F={}
F.STAMP_NOTE='* The map can add this after a reroll, so excluding it is not guaranteed'
F.FOOTER='Possible encounters. Spawns are not guaranteed.'
F.CREDIT='Unit data: Know Your Constellation'
-- The roster to use, or nil; and the reason, for the log.
function F.roster(globals)
    local state=rawget(globals,'EnemyIntelligence')
    if type(state)~='table' then return nil,'not installed' end
    local revision='revision '..tostring(rawget(state,'revision'))
    -- Know Your Constellation stops itself on an unsupported game build.
    local status=rawget(state,'status')
    if type(status)=='string' and status:find('^disabled:')then return nil,revision..' '..status end
    local r=rawget(state,'roster')
    if type(r)~='table' or r.api~=1 or type(r.forecast)~='function' or type(r.from_native)~='function' then
        return nil,revision..' has no roster api 1'
    end
    if tostring(r.build)~=tostring(O.build)then return nil,revision..' roster build '..tostring(r.build)..' is not game build '..O.build end
    return r,revision..' build '..tostring(r.build)
end
-- A forecast's units, checked: names, and 1 to 10 meter ticks.
local function units(report)
    assert(type(report)=='table' and type(report.large)=='table' and type(report.small)=='table','Invalid forecast')
    local large,small={},{}
    for i,entry in ipairs(report.large)do
        assert(type(entry)=='table' and type(entry.name)=='string' and type(entry.ticks)=='number'
            and entry.ticks>=1 and entry.ticks<=10,'Invalid large enemy')
        large[i]={name=entry.name,ticks=math.floor(entry.ticks)}
    end
    for i,name in ipairs(report.small)do assert(type(name)=='string','Invalid enemy name');small[i]=name end
    return large,small
end
-- new(emit,globals): one per dialog. tip(item,catalogue,forced) is the
-- tooltip of an enemy row, or nil: {title, with, large={{name,ticks}},
-- small={name}, footer, note, credit}, every part but the title optional. A roster
-- that fails turns unit tooltips off for the session; an input that cannot be
-- read leaves only that tooltip without units.
function F.new(emit,globals)
    local self={}
    local said,broken,key,last
    local function say(line)if line~=said then said=line;emit(line)end end
    -- Checked on every use: Know Your Constellation may stop itself after
    -- this mod's first frame.
    function self:roster()
        if broken then return nil end
        local r,why=F.roster(globals)
        say('KYC_ROSTER '..(r and 'ready ' or 'off: ')..why)
        return r
    end
    function self:tip(item,catalogue,forced)
        local r=self:roster()
        local now=table.concat({tostring(item.id),tostring(catalogue),tostring(r),forced or ''},'|')
        if now==key then return last end
        key=now
        local tip={title=item.title or item.name,note=item.stamped and F.STAMP_NOTE or nil}
        if r and catalogue and catalogue.forecast then
            local ok,input=pcall(catalogue.forecast,item.tag)
            if not ok then say('KYC_ROSTER_INPUT '..tostring(input))
            else
                local done,value=pcall(function()
                    local tags={}
                    for i,tag in ipairs(input.tags)do tags[i]=r.from_native(tag)end
                    return {units(r.forecast({faction=input.faction,difficulty=input.difficulty,tags=tags},input.zone,input.war))}
                end)
                if done then
                    tip.large,tip.small,tip.footer,tip.credit=value[1],value[2],F.FOOTER,F.CREDIT
                    if (forced or '')~='' then tip.with=forced end
                else
                    broken=true
                    say('KYC_ROSTER_FAILED '..tostring(value)..'; unit tooltips off for this session')
                end
            end
        end
        last=(tip.large or tip.note) and tip or nil
        return last
    end
    return self
end
return F
