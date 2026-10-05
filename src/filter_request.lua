-- The player's Filters in the dialog, and the panel's view model built from
-- them. Pure: the dialog runtime reads the game, the session and the mouse,
-- and hands this module plain tables.
-- Its chunk arguments are O, unused, and Rules (src/filter_rules.lua).
-- new(options,catalogue,labels,stamped): options are Search.options,
-- catalogue is src/filter_catalogue.lua (possible, validate), labels the
-- constellation names, stamped the tags a map stamp can add.
local _,Rules=...
local R={}
R.__index=R
local PAGE=24
function R.new(options,catalogue,labels,stamped)
    -- One section is open at a time, or none. The enemy section shows the
    -- rules of one group: a checked mission, or 0 for any mission. changed
    -- marks the sections whose rules a mission click discarded, until their
    -- header is clicked.
    return setmetatable({options=options,catalogue=catalogue,labels=labels,stamped=stamped or {},
        selected={},excluded={},modifiers={},constellations={},objectives={},time=nil,section='missions',page=1,pages=1,group_choice=0,
        changed={}},R)
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
-- missions the single group 0 applies to the operation. selected defaults
-- to the request's own.
function R:groups(selected)
    local list={}
    for id=1,#self.options do if (selected or self.selected)[id]then list[#list+1]=id end end
    if #list==0 then list[1]=0 end
    return list
end
-- Drops the groups no longer active. Returns the sections that lost rules,
-- as {enemies=true,objectives=true}.
local function prune_groups(self)
    local active,lost={},{}
    for _,group in ipairs(self:groups())do active[group]=true end
    for group,tags in pairs(self.constellations)do
        if not active[group]then
            if next(tags)then lost.enemies=true end
            self.constellations[group]=nil
        end
    end
    for group,rows in pairs(self.objectives)do
        if not active[group]then
            if next(rows)then lost.objectives=true end
            self.objectives[group]=nil
        end
    end
    return lost
end
-- The rules of field in the active groups of selected, as a copy.
local function group_rules(self,field,selected)
    local groups={}
    for _,group in ipairs(self:groups(selected))do
        local copy={};for key,mode in pairs(self[field][group] or {})do copy[key]=mode end
        if next(copy)then groups[group]=copy end
    end
    return {groups=groups}
end
-- The constellation rules of the active groups, as a copy.
function R:tag_filter(selected)return group_rules(self,'constellations',selected)end
-- The side-objective rules of the active groups, as a copy.
function R:objective_filter(selected)return group_rules(self,'objectives',selected)end
-- The Filters as filter rules (src/filter_rules.lua), with selected,
-- excluded or the side-objective groups in place of the request's own when
-- given. Constellation and side-objective rules are those of the active
-- groups of selected.
function R:rules(selected,excluded,objectives)
    selected=selected or self.selected
    return Rules.new({required=selected,excluded=excluded or self.excluded,modifiers=self.modifiers,
        constellations=self:tag_filter(selected),objectives=objectives or self:objective_filter(selected),time=self.time})
end
-- Checked and excluded missions, modifier rules, constellation rules and the
-- time of day.
function R:rule_count()return (self:rules():count())end
-- Whether the request can be met; true without a catalogue.
function R:possible(catalogue)
    if not catalogue then return true end
    return self.catalogue.possible(catalogue,self:rules())
end
-- Raises with the reason the request cannot be searched.
function R:validate(catalogue)
    self.catalogue.validate(catalogue,self:rules())
end
-- The request reroll_session.start takes, as a copy.
function R:to_request(scope,difficulty)
    return {difficulty=difficulty,required=copy(self.selected),excluded=copy(self.excluded),
        modifiers=copy(self.modifiers),constellations=self:tag_filter(),objectives=self:objective_filter(),
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
    for group,rows in pairs(self.objectives)do
        local offered=(catalogue.objective_groups or {})[group]
        for row in pairs(rows)do if not (offered and offered.set[row])then rows[row]=nil;removed=true end end
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
        -- Clicking the open section closes it. Clicking a header marked
        -- changed shows the player saw it.
        local name=action:sub(9);self.section=self.section~=name and name or nil
        self.changed[name]=nil
    elseif type(action)=='string' and action:match('^group:')then self.group_choice=tonumber(action:sub(7))
    else return false end
    return true
end
-- Whether a mission that is neither required nor excluded could be required,
-- with the reason when not; and whether it could be excluded. Requiring the
-- first mission discards the any-mission rules, so they do not count.
function R:can_require(id,catalogue)
    return self.catalogue.possible(catalogue,self:rules(copy(self.selected,id,true)))
end
function R:can_exclude(id,catalogue)
    return self.catalogue.possible(catalogue,self:rules(nil,copy(self.excluded,id,true)))
end
-- The reason an option the seed solver rules out is disabled.
local UNREACHABLE='This mission never gets this here at this difficulty'
-- Whether the seed solver finds a path with one enemy-force ('tag') or
-- side-objective ('objective') option of a checked mission set to mode,
-- with the reason when not. self.reach is the request's reachability
-- (src/seed_solver_search.lua R.reachability, set by model); without it, or
-- for an option it did not check, nothing is ruled out.
local function reachable(self,field,group,id,mode)
    local reach=self.reach
    if not reach or group==0 or not self.selected[group] then return true end
    if reach[field](group,id,mode)==false then return false,UNREACHABLE end
    return true
end
-- Whether a side-objective row of a group could take a mode, with the
-- reason when not.
function R:can_objective(group,row,mode,catalogue)
    if not catalogue then return true end
    local filter=self:objective_filter()
    filter.groups[group]=copy(filter.groups[group] or {},row,mode)
    local possible,why=self.catalogue.possible(catalogue,self:rules(nil,nil,filter))
    if not possible then return possible,why end
    return reachable(self,'objective',group,row,mode)
end
-- Whether a constellation tag of a group could take a mode, with the reason
-- when not.
function R:can_tag(group,tag,mode)return reachable(self,'tag',group,tag,mode)end
-- Edits the request: clear, a mission id, 'modifier:<id>',
-- 'constellation:<group>:<id>', 'objective:<group>:<row>' or
-- 'time:any|day|night'. A mission cycles any, required, excluded. One the
-- catalogue cannot require with the rest stays unchecked; a required one
-- that cannot be excluded goes back to any. A side objective cycles the
-- same way, skipping a mode the catalogue rules out; a constellation cycles
-- accept, exclude, any, skipping a mode the seed solver rules out. A mission click that
-- discards enemy or side-objective rules marks those sections changed.
-- Returns whether the action was an edit.
function R:toggle(action,catalogue)
    if action=='clear' then
        self.selected={};self.excluded={};self.modifiers={};self.constellations={};self.objectives={};self.time=nil;self.changed={}
    elseif action=='time:any' then self.time=nil
    elseif action=='time:day' or action=='time:night' then self.time=action:sub(6)
    elseif type(action)=='number' then
        local selected,excluded=self.selected,self.excluded
        if excluded[action]then excluded[action]=nil
        else
            -- Unchecking drops the mission's constellations before the next step is tried.
            local was=selected[action];selected[action]=nil
            for name in pairs(prune_groups(self))do self.changed[name]=true end
            if not was then
                if self:can_require(action,catalogue)then selected[action]=true end
            elseif self:can_exclude(action,catalogue)then excluded[action]=true end
        end
        for name in pairs(prune_groups(self))do self.changed[name]=true end
    elseif type(action)=='string' and action:match('^modifier:')then
        local id=tonumber(action:sub(10))
        local modifiers=self.modifiers
        modifiers[id]=modifiers[id]==nil and 'require' or modifiers[id]=='require' and 'exclude' or nil
    elseif type(action)=='string' and action:match('^constellation:')then
        local target,id=action:match('^constellation:(%d+):(%d+)$')
        target,id=tonumber(target),tonumber(id)
        local tags=self.constellations[target] or {}
        local mode=tags[id]
        local order=mode==nil and {'accept','exclude'} or mode=='accept' and {'exclude'} or {}
        tags[id]=nil
        for _,next_mode in ipairs(order)do
            if self:can_tag(target,id,next_mode)then tags[id]=next_mode;break end
        end
        self.constellations[target]=next(tags) and tags or nil
    elseif type(action)=='string' and action:match('^objective:')then
        local target,row=action:match('^objective:(%d+):(%d+)$')
        target,row=tonumber(target),tonumber(row)
        local rows=self.objectives[target] or {}
        local mode=rows[row]
        local order=mode==nil and {'require','exclude'} or mode=='require' and {'exclude'} or {}
        rows[row]=nil
        for _,next_mode in ipairs(order)do
            if self:can_objective(target,row,next_mode,catalogue)then rows[row]=next_mode;break end
        end
        self.objectives[target]=next(rows) and rows or nil
    else return false end
    return true
end
local function grouped(n)
    local digits,found=tostring(math.floor(n))
    repeat digits,found=digits:gsub('^(%d+)(%d%d%d)','%1,%2')until found==0
    return digits
end
local function count(n)return n==0 and 'Any' or n..(n==1 and ' rule' or ' rules')end
-- How strict a solved search's filter is and how long it usually takes
-- (prediction_search_runtime.lua: {match, seconds, elapsed}); without
-- seconds (this machine's walk rate not yet measured) only how strict.
-- running: the shorter form a running search shows after its clock.
local function estimate_text(e,running)
    if e.match<=0 then return 'No seed gives this now' end
    local strict
    if e.match>=0.5 then strict='Most seeds match'
    else
        local n=1/e.match
        local scale=10^math.max(0,math.floor(math.log10(n))-1)
        strict='1 in '..grouped(math.floor(n/scale+0.5)*scale)..' seeds match'
    end
    local s=e.seconds
    if not s then return strict end
    -- One unmeasured text redrawn every frame: kept under the panel's width.
    local expect=running and '' or 'expect '
    local usual=s<1 and expect..'under a second' or s<90 and string.format('%sabout %d s',expect,math.floor(s+0.5))
        or s<=180 and string.format('%sabout %d min',expect,math.floor(s/60+0.5))
        or 'over the 3 min limit'
    return strict..' - '..usual
end
-- A search's elapsed time, as the clock at the start of its line: 0:07.
local function clock_text(seconds)
    local s=math.max(0,math.floor(seconds))
    return string.format('%d:%02d',math.floor(s/60),s%60)
end
-- A count in two or three figures: 350K, 2.4M, 28M, 1.2B.
local function compact(n)
    if n<10000 then return grouped(n)end
    local function figures(v,unit)
        if v<10 then return string.format('%.1f',math.floor(v*10+0.5)/10):gsub('%.0$','')..unit end
        return grouped(math.floor(v+0.5))..unit
    end
    -- The unit by the rounded figure, so 999,999,999.9 reads 1B, not 1,000M.
    if n<999500 then return figures(n/1e3,'K')end
    if n<999.5e6 then return figures(n/1e6,'M')end
    return figures(n/1e9,'B')
end
-- While a search starts (no seed tried, no estimate of its own yet): the
-- estimate the request showed before the search, else a plain line, rather
-- than a count of zero seeds.
local function starting_text(before)
    if type(before)=='table' and before.match and before.match>0 then return estimate_text(before,true)end
    return 'Starting search'
end
-- Under a running search: its clock, then the solver's estimate or the
-- seeds searched. With the seeds the solver has covered so far (the seeds
-- an in-order scan would have checked for the same chance of a match), the
-- count and the filter's strictness, compact, replace the usual time.
-- before: the request's estimate from before the search.
local function running_text(run,limit,before)
    local e=run.estimate
    local what
    if e and e.covered and e.match>0 then
        what=compact(e.covered)..' seeds covered - '..(e.match>=0.5 and 'most seeds match' or '1 in '..compact(1/e.match)..' match')
    elseif e then what=estimate_text(e,true)
    elseif (run.progress or 0)==0 then what=starting_text(before)
    else what=grouped(run.progress)..' of '..grouped(limit)..' seeds searched' end
    return run.elapsed and clock_text(run.elapsed)..' - '..what or what
end
-- Under a request ready to search: its estimate (solver_estimate.lua) once
-- worked out.
local function before_search(e)
    if e=='pending' then return 'Working out how strict this is' end
    if type(e)=='table' and e.impossible then return 'No seed gives this now' end
    if type(e)=='table' and e.match then return estimate_text(e)end
    return 'Rerolls every unstarted operation of the campaign'
end
local CHANGED=' - Mission changed'
-- The panel's model. catalogue is the last one built, used for compatibility
-- even while not shown. v: shown (the catalogue may be displayed), fresh
-- (planet data of this frame), retained (the catalogue is kept through a
-- gap), running, queued (a start waits for fresh data), fixed (an operation
-- in progress blocks the city), overdue (the gap is shown), run (the
-- session's view), why (why there is no fresh data), report and tone (the
-- last outcome), difficulty, scope, limit (seeds per search) and sky: the
-- viewed planet's day and night with a time of day chosen, {hold} or
-- {pending=reason} or {blocked=reason} (src/day_night.lua).
-- v.estimate is the request's estimate (src/solver_estimate.lua) and
-- v.reachable its reachability, which disables the enemy-force and
-- side-objective options no path meets. A request no path meets keeps every
-- option enabled, so the player can edit it back, and cannot be started.
function R:model(catalogue,v)
    local options,selected,excluded,modifiers,section=self.options,self.selected,self.excluded,self.modifiers,self.section
    self.reach=v.reachable and v.reachable.ok and v.reachable or nil
    local impossible=type(v.estimate)=='table' and v.estimate.impossible==true
    local display=v.shown and catalogue
    local groups=self:groups()
    local group=groups[1]
    for _,id in ipairs(groups)do if id==self.group_choice then group=id end end
    self.group_choice=group
    local names={}
    for _,id in ipairs(groups)do if id~=0 then names[#names+1]=options[id].name end end
    local checked=#names
    for id,option in ipairs(options)do if excluded[id]then names[#names+1]='not '..option.name end end
    local rules,kinds=self:rules():count()
    local modifier_rules,tag_rules,objective_rules=kinds.modifiers,kinds.constellations,kinds.objectives
    local compatible,compatibility_reason=self:possible(catalogue)
    local running,fresh,retained,fixed=v.running,v.fresh,v.retained,v.fixed
    local busy=running or v.queued
    local locked=busy or not (fresh or retained)
    local items,pages,tabs,forced,slots={},1,{},{},nil
    if display and section=='missions' then
        local available=catalogue.missions or {}
        pages=math.max(1,math.ceil(#available/PAGE));self.page=math.min(self.page,pages)
        for i=(self.page-1)*PAGE+1,math.min(#available,self.page*PAGE)do
            local option=available[i]
            local mode=selected[option.id] and 'require' or excluded[option.id] and 'exclude' or nil
            -- A mission that cannot join the required ones is disabled; it
            -- is excluded only by clicking it again once required.
            local enabled,reason=true,nil
            if not mode then enabled,reason=self:can_require(option.id,catalogue)end
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
                local mode=(self.constellations[group] or {})[option.id]
                -- A tag no path gives or avoids is disabled with the reason.
                local enabled,reason=true,nil
                if not mode then
                    local can,why=self:can_tag(group,option.id,'accept')
                    if not can then enabled=(self:can_tag(group,option.id,'exclude'));reason=why end
                end
                items[#items+1]={id='constellation:'..group..':'..option.id,name=title..(stamped and ' *' or ''),
                    title=title,tag=option.id,stamped=stamped,mode=mode,enabled=enabled,reason=reason}
            end
        end
        for i,id in ipairs(groups)do
            tabs[i]={id=id,name=id==0 and 'Any mission' or options[id].name,selected=id==group}
        end
        -- The names table also holds the game's tag, which the log keeps.
        for i,tag in ipairs(catalogue.forced or {})do forced[i]=((self.labels[tag] or 'tag '..tag):gsub(' %b()$',''))end
    elseif display and section=='objectives' then
        local offered=(catalogue.objective_groups or {})[group]
        if offered then
            local rows=self.objectives[group] or {}
            for _,option in ipairs(offered.list)do
                local mode=rows[option.id]
                -- A row that can take neither rule is disabled with the reason.
                local enabled,reason=true,nil
                if not mode then
                    local can,why=self:can_objective(group,option.id,'require',catalogue)
                    if not can then
                        enabled=self:can_objective(group,option.id,'exclude',catalogue)
                        reason=why
                    end
                end
                items[#items+1]={id='objective:'..group..':'..option.id,name=option.name,mode=mode,enabled=enabled,reason=reason,
                    role=option.role==2 and 'tactical' or 'side'}
            end
            -- The side and tactical slots of the group's mission types.
            if group~=0 then
                local side,tactical
                for _,info in pairs(offered.kinds)do
                    side=math.max(side or 0,info.side);tactical=math.max(tactical or 0,info.tactical)
                end
                if side then slots=side..' SIDE + '..tactical..' TACTICAL' end
            end
        end
        for i,id in ipairs(groups)do
            tabs[i]={id=id,name=id==0 and 'Any mission' or options[id].name,selected=id==group}
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
    elseif impossible and (fresh or retained) and rules>0 then status,tone='No seed gives this now. Change a rule to search','bad'
    elseif not fresh and not retained then
        status,tone=why=='Choose a planet and map difficulty' and 'Open a planet on the war table first' or why or report or 'Waiting for planet data','warn'
    elseif report then status,tone=report,v.tone
    else status,tone=rules>0 and 'Ready to search' or 'Choose what the operation must contain','idle' end
    -- An empty request is refused by validation; the panel disables Start instead.
    return {running=busy,locked=locked,ready=ready,can_start=ready and rules>0 and not impossible,can_clear=not locked and rules>0,
        difficulty=v.difficulty,status=tostring(status),tone=tone,
        step=busy and (running and run.step or 1) or nil,
        detail=busy and (running and running_text(run,v.limit,v.estimate) or starting_text(v.estimate))
            or ready and rules>0 and tone=='idle' and before_search(v.estimate) or '',
        faction=display and catalogue.faction or nil,scope=v.scope and 'city' or 'planet',
        section=section,items=items,page=self.page,pages=pages,groups=tabs,group=group,
        slots=display and catalogue.slots or nil,checked=checked,rules=rules,
        objective_slots=slots,
        -- A section whose rules a mission click discarded says so until its
        -- header is clicked; the panel paints that header red.
        changed={enemies=self.changed.enemies,objectives=self.changed.objectives},
        summaries={missions=#names>0 and table.concat(names,', ') or 'Any',modifiers=count(modifier_rules),
            enemies=count(tag_rules)..(self.changed.enemies and CHANGED or ''),
            objectives=count(objective_rules)..(self.changed.objectives and CHANGED or ''),
            time=self.time=='day' and 'Day' or self.time=='night' and 'Night' or 'Any'},
        time=self.time or 'any',time_hold=v.sky and v.sky.hold or nil,
        -- A search shows its own status; the tile stays as it started.
        time_sky=not busy and (sky.blocked and 'blocked' or sky.pending and 'pending') or nil,
        forced=table.concat(forced,', '),
        note=display and section=='enemies' and group==0 and 'Check a mission to set its own enemies' or nil,
        objective_note=display and section=='objectives' and group==0 and 'ANY MISSION OF THE OPERATION' or nil}
end
return R
