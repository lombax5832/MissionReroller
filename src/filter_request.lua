-- The player's Filters in the dialog, and the panel's view model built from
-- them. Pure: the dialog runtime reads the game, the session and the mouse,
-- and hands this module plain tables.
-- new(options,catalogue,labels,stamped): options are Search.options,
-- catalogue is src/filter_catalogue.lua (possible, validate), labels the
-- constellation names, stamped the tags a map stamp can add.
local R={}
R.__index=R
local PAGE=24
function R.new(options,catalogue,labels,stamped)
    -- One section is open at a time, or none. The enemy section shows the
    -- rules of one group: a checked mission, or 0 for any mission.
    return setmetatable({options=options,catalogue=catalogue,labels=labels,stamped=stamped or {},
        selected={},excluded={},modifiers={},constellations={},time=nil,section='missions',page=1,pages=1,group_choice=0},R)
end
-- A copy of a set, with id set to value when given.
local function copy(set,id,value)
    local out={};for k,v in pairs(set)do out[k]=v end
    if id~=nil then out[id]=value end
    return out
end
-- Opening the dialog starts on the first page of the missions.
function R:open()self.section,self.page='missions',1 end
-- Constellation rules belong to a checked mission. Without checked
-- missions the single group 0 applies to the operation.
function R:groups()
    local list={}
    for id=1,#self.options do if self.selected[id]then list[#list+1]=id end end
    if #list==0 then list[1]=0 end
    return list
end
local function prune_groups(self)
    local active={};for _,group in ipairs(self:groups())do active[group]=true end
    for group in pairs(self.constellations)do if not active[group]then self.constellations[group]=nil end end
end
-- The constellation rules of the active groups, as a copy.
function R:tag_filter()
    local groups={}
    for _,group in ipairs(self:groups())do
        local copy={};for tag,mode in pairs(self.constellations[group] or {})do copy[tag]=mode end
        if next(copy)then groups[group]=copy end
    end
    return {groups=groups}
end
-- Checked and excluded missions, modifier rules, constellation rules and the
-- time of day.
function R:rule_count()
    local n=self.time and 1 or 0
    for _,id in ipairs(self:groups())do if id~=0 then n=n+1 end end
    for _ in pairs(self.excluded)do n=n+1 end
    for _ in pairs(self.modifiers)do n=n+1 end
    for _,tags in pairs(self:tag_filter().groups)do for _ in pairs(tags)do n=n+1 end end
    return n
end
-- Whether the request can be met; true without a catalogue.
function R:possible(catalogue)
    if not catalogue then return true end
    return self.catalogue.possible(catalogue,self.selected,self.modifiers,self:tag_filter(),self.excluded)
end
-- Raises with the reason the request cannot be searched.
function R:validate(catalogue)
    self.catalogue.validate(catalogue,self.selected,self.modifiers,self:tag_filter(),self.time,self.excluded)
end
-- The request reroll_session.start takes, as a copy.
function R:to_request(scope,difficulty)
    return {difficulty=difficulty,required=copy(self.selected),excluded=copy(self.excluded),
        modifiers=copy(self.modifiers),constellations=self:tag_filter(),
        scope=scope and {region=scope.region} or nil,time=self.time}
end
-- Drops the rules a fresh catalogue no longer offers. A catalogue of another
-- planet or difficulty (new_view) turns back to the first mission page.
-- Returns whether anything was removed.
function R:prune(catalogue,new_view)
    if new_view then self.page=1 end
    local removed=false
    for id in pairs(self.selected)do if not catalogue.mission_set[id]then self.selected[id]=nil;removed=true end end
    for id in pairs(self.excluded)do if not catalogue.mission_set[id]then self.excluded[id]=nil;removed=true end end
    for id in pairs(self.modifiers)do if not catalogue.modifier_set[id]then self.modifiers[id]=nil;removed=true end end
    for group,tags in pairs(self.constellations)do
        local offered=(catalogue.constellation_groups or {})[group]
        for tag in pairs(tags)do if not (offered and offered.set[tag])then tags[tag]=nil;removed=true end end
    end
    prune_groups(self)
    return removed
end
-- Pages, sections and groups; allowed while the request is locked.
-- Returns whether the action was one of them.
function R:navigate(action)
    if action=='previous_page' then self.page=math.max(1,self.page-1)
    elseif action=='next_page' then self.page=math.min(self.pages,self.page+1)
    elseif type(action)=='string' and action:match('^section:')then
        -- Clicking the open section closes it.
        local name=action:sub(9);self.section=self.section~=name and name or nil
    elseif type(action)=='string' and action:match('^group:')then self.group_choice=tonumber(action:sub(7))
    else return false end
    return true
end
-- Whether a mission that is neither required nor excluded could be required,
-- with the reason when not; and whether it could be excluded.
function R:can_require(id,catalogue,filter)
    return self.catalogue.possible(catalogue,copy(self.selected,id,true),self.modifiers,filter,self.excluded)
end
function R:can_exclude(id,catalogue,filter)
    return self.catalogue.possible(catalogue,self.selected,self.modifiers,filter,copy(self.excluded,id,true))
end
-- Edits the request: clear, a mission id, 'modifier:<id>',
-- 'constellation:<group>:<id>' or 'time:any|day|night'. A mission cycles
-- any, required, excluded. One the catalogue cannot require with the rest
-- stays unchecked; a required one that cannot be excluded goes back to any.
-- Returns whether the action was an edit.
function R:toggle(action,catalogue)
    if action=='clear' then self.selected={};self.excluded={};self.modifiers={};self.constellations={};self.time=nil
    elseif action=='time:any' then self.time=nil
    elseif action=='time:day' or action=='time:night' then self.time=action:sub(6)
    elseif type(action)=='number' then
        local selected,excluded=self.selected,self.excluded
        if excluded[action]then excluded[action]=nil
        else
            -- Unchecking drops the mission's constellations before the next step is tried.
            local was=selected[action];selected[action]=nil;prune_groups(self)
            local filter=self:tag_filter()
            if not was then
                if self:can_require(action,catalogue,filter)then selected[action]=true end
            elseif self:can_exclude(action,catalogue,filter)then excluded[action]=true end
        end
        prune_groups(self)
    elseif type(action)=='string' and action:match('^modifier:')then
        local id=tonumber(action:sub(10))
        local modifiers=self.modifiers
        modifiers[id]=modifiers[id]==nil and 'require' or modifiers[id]=='require' and 'exclude' or nil
    elseif type(action)=='string' and action:match('^constellation:')then
        local target,id=action:match('^constellation:(%d+):(%d+)$')
        target,id=tonumber(target),tonumber(id)
        local tags=self.constellations[target] or {}
        tags[id]=tags[id]==nil and 'accept' or tags[id]=='accept' and 'exclude' or nil
        self.constellations[target]=next(tags) and tags or nil
    else return false end
    return true
end
local function grouped(n)
    local digits,found=tostring(math.floor(n))
    repeat digits,found=digits:gsub('^(%d+)(%d%d%d)','%1,%2')until found==0
    return digits
end
local function count(n)return n==0 and 'Any' or n..(n==1 and ' rule' or ' rules')end
-- The panel's model. catalogue is the last one built, used for compatibility
-- even while not shown. v: shown (the catalogue may be displayed), fresh
-- (planet data of this frame), retained (the catalogue is kept through a
-- gap), running, queued (a start waits for fresh data), fixed (an operation
-- in progress blocks the city), overdue (the gap is shown), run (the
-- session's view), why (why there is no fresh data), report and tone (the
-- last outcome), difficulty, scope, limit (seeds per search) and sky: the
-- viewed planet's day and night with a time of day chosen, {note} or
-- {pending=reason} or {blocked=reason} (src/day_night.lua).
function R:model(catalogue,v)
    local options,selected,excluded,modifiers,section=self.options,self.selected,self.excluded,self.modifiers,self.section
    local display=v.shown and catalogue
    local groups=self:groups()
    local group=groups[1]
    for _,id in ipairs(groups)do if id==self.group_choice then group=id end end
    self.group_choice=group
    local filter=self:tag_filter()
    local names,modifier_rules,tag_rules={},0,0
    for _,id in ipairs(groups)do if id~=0 then names[#names+1]=options[id].name end end
    local checked=#names
    for id,option in ipairs(options)do if excluded[id]then names[#names+1]='not '..option.name end end
    for _ in pairs(modifiers)do modifier_rules=modifier_rules+1 end
    for _,tags in pairs(filter.groups)do for _ in pairs(tags)do tag_rules=tag_rules+1 end end
    local rules=#names+modifier_rules+tag_rules+(self.time and 1 or 0)
    local compatible,compatibility_reason=self:possible(catalogue)
    local running,fresh,retained,fixed=v.running,v.fresh,v.retained,v.fixed
    local busy=running or v.queued
    local locked=busy or not (fresh or retained)
    local items,pages,tabs,forced={},1,{},{}
    if display and section=='missions' then
        local available=catalogue.missions or {}
        pages=math.max(1,math.ceil(#available/PAGE));self.page=math.min(self.page,pages)
        for i=(self.page-1)*PAGE+1,math.min(#available,self.page*PAGE)do
            local option=available[i]
            local mode=selected[option.id] and 'require' or excluded[option.id] and 'exclude' or nil
            -- A mission that cannot join the required ones is disabled; it
            -- is excluded only by clicking it again once required.
            local enabled,reason=true,nil
            if not mode then enabled,reason=self:can_require(option.id,catalogue,filter)end
            items[#items+1]={id=option.id,name=option.name,mode=mode,enabled=enabled,reason=reason}
        end
    elseif display and section=='modifiers' then
        for _,option in ipairs(catalogue.modifiers or {})do
            items[#items+1]={id='modifier:'..option.id,name=option.name,mode=modifiers[option.id]}
        end
    elseif display and section=='enemies' then
        local offered=(catalogue.constellation_groups or {})[group]
        if offered then
            assert(#offered.list<=11,'Too many constellation options')
            for _,option in ipairs(offered.list)do
                -- A tag the map can add after generation carries a marker; its
                -- tooltip says why (src/unit_forecast.lua).
                local title,stamped=(option.name:gsub(' %b()$','')),self.stamped[option.id] or false
                items[#items+1]={id='constellation:'..group..':'..option.id,name=title..(stamped and ' *' or ''),
                    title=title,tag=option.id,stamped=stamped,mode=(self.constellations[group] or {})[option.id]}
            end
        end
        for i,id in ipairs(groups)do
            tabs[i]={id=id,name=id==0 and 'Any mission' or options[id].name,selected=id==group}
        end
        -- The names table also holds the game's tag, which the log keeps.
        for i,tag in ipairs(catalogue.forced or {})do forced[i]=((self.labels[tag] or 'tag '..tag):gsub(' %b()$',''))end
    elseif display and section=='time' then
        for _,side in ipairs({{'any','Any time'},{'day','Day'},{'night','Night'}})do
            items[#items+1]={id='time:'..side[1],name=side[2],mode=(self.time or 'any')==side[1] and 'chosen' or nil}
        end
    end
    -- The sky decides only when a side is chosen.
    local sky=self.time and (v.sky or {pending='Waiting for the sky of the viewed planet'}) or {}
    local dark=sky.blocked or sky.pending
    self.pages=pages
    local ready=not busy and (fresh or retained) and compatible and not fixed and not dark
    -- The same precedence as before the panel was docked.
    local status,tone
    local run,why,report=v.run,v.why,v.report
    if running then status,tone=run.caption,'busy'
    elseif v.queued then status,tone='Checking planet data','busy'
    elseif fixed then status,tone='Operation in progress. Finish or abandon it to reroll','warn'
    elseif v.overdue then status,tone='Updating planet data. Your choices are kept','warn'
    elseif not compatible then status,tone=compatibility_reason,'bad'
    elseif sky.blocked and (fresh or retained) then status,tone=sky.blocked,'bad'
    elseif sky.pending and (fresh or retained) then status,tone=sky.pending,'warn'
    elseif not fresh and not retained then
        status,tone=why=='Choose a planet and map difficulty' and 'Open a planet on the war table first' or why or report or 'Waiting for planet data','warn'
    elseif report then status,tone=report,v.tone
    else status,tone=rules>0 and 'Ready to search' or 'Choose what the operation must contain','idle' end
    -- An empty request is refused by validation; the panel disables Start instead.
    return {running=busy,locked=locked,ready=ready,can_start=ready and rules>0,can_clear=not locked and rules>0,
        difficulty=v.difficulty,status=tostring(status),tone=tone,
        step=busy and (running and run.step or 1) or nil,
        detail=busy and grouped(running and run.progress or 0)..' of '..grouped(v.limit)..' seeds searched'
            or ready and rules>0 and tone=='idle' and 'Rerolls every unstarted operation of the campaign' or '',
        faction=display and catalogue.faction or nil,scope=v.scope and 'city' or 'planet',
        section=section,items=items,page=self.page,pages=pages,groups=tabs,group=group,
        slots=display and catalogue.slots or nil,checked=checked,rules=rules,
        summaries={missions=#names>0 and table.concat(names,', ') or 'Any',modifiers=count(modifier_rules),enemies=count(tag_rules),
            time=self.time=='day' and 'Day' or self.time=='night' and 'Night' or 'Any'},
        time_note=v.sky and v.sky.note or nil,
        forced=table.concat(forced,', '),
        note=display and section=='enemies' and group==0 and 'Check a mission to set its own enemies' or nil}
end
return R
