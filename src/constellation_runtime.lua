-- Constellation tags for predicted or displayed operations, and a read-only
-- observer that compares a prediction with the loaded mission preview.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
local M,log,read,pointer,u=host.M,host.log,host.read,host.pointer,host.u
local reroll_session=host.reroll_session
local map,O=host.map,host.O
local Constellations,Planet=lib.Constellations,lib.Planet
local Board=lib.Board
local api,game
host.when_initialized(function(n)api,game=n.api,n.game end)
local bind_constellations,observe_constellations
do
    -- A Planet.bind result: its tag inputs decode through its reads.
    local function bind(model)
        local inputs,planet=model.constellation_inputs(),model.index
        return function(op,category,id)
            local effect=op.effect_id or inputs.effect_id(category,id,planet)
            local initial=inputs.campaign(planet,effect)
            for _,mission in ipairs(op.missions)do
                local record=inputs.mission(mission.native_type)
                -- The native resolver reads the mission record's own faction.
                -- Leave other values unresolved: unknown tags never match.
                if record.faction>=2 and record.faction<=4 then
                    mission.tags=Constellations.resolve(mission.seed,inputs.settings(record.faction,op.difficulty),
                        initial,record,inputs.disabled).set
                end
            end
        end,inputs
    end
    bind_constellations=bind

    local last,seen,attempts,logged,surveyed,reported=-math.huge,{},{},0,false,false
    local function join(list)
        local parts={};for _,value in ipairs(list)do parts[#parts+1]=tostring(value)end
        return table.concat(parts,',')
    end
    -- Level-owned inputs of 177deb0. The level must describe the same mission.
    -- Values outside the tag table are reported raw and never resolved.
    local function stamp_record(entry)
        local variant,index=entry:byte(0xa2),entry:byte(0xa3)
        if index==255 then return nil end
        local owner=assert(api.pointer(entry),'Missing stamp owner')
        if u(entry,8)~=0xadc32faa then return pointer(owner)end
        if variant~=255 then return pointer(pointer(owner+0x28)+variant*0x18+8)+index*O.stamp.size end
    end
    local function level_inputs(controller,offset,kind)
        local level=api.pointer(api.read(controller+offset,8))
        if not level then return nil end
        local head=api.read(level+O.level.kind,4)
        if not head or u(head,0)~=kind then return nil end
        local explicit=read(level+O.level.explicit_tags,16);local n=u(explicit,12)
        local result={offset=offset,tags={},explicit={},stamps=u(read(level+O.level.stamp_count,4),0),stamp='none',valid=n<=3}
        local function add(tag)
            if tag<32 then result.tags[#result.tags+1]=tag else result.valid=false end
        end
        for i=0,math.min(n,3)-1 do
            result.explicit[#result.explicit+1]=u(explicit,i*4);add(u(explicit,i*4))
        end
        if n>3 then result.explicit[#result.explicit+1]='count='..n end
        local loaded=read(controller,8)~=string.rep('\0',8)
        if result.stamps~=0 then
            local entry=read(level+O.level.stamps,O.level.stamp_size)
            local record=stamp_record(entry)
            local where=string.format('(type=%08x variant=%d index=%d%s)',u(entry,8),entry:byte(0xa2),entry:byte(0xa3),
                loaded and '' or ' preview')
            -- Native reads the first stamp only while the controller is loaded,
            -- which a map preview is not. The mission will carry the tag once
            -- it is played, so it counts here either way.
            if record then
                local tag=u(read(record+0xd0,4),0)
                result.stamp=tag..where;add(tag)
            else result.stamp='none'..where end
        end
        -- Only the first stamp feeds the resolver. The others are listed to
        -- learn which missions place tagged stamps at all.
        local tagged={}
        pcall(function()
            for i=1,math.min(result.stamps,256)-1 do
                local record=stamp_record(read(level+O.level.stamps+i*O.level.stamp_size,O.level.stamp_size))
                local tag=record and u(read(record+0xd0,4),0) or 0
                if tag~=0 and #tagged<8 then tagged[#tagged+1]=i..':'..tag end
            end
        end)
        result.later=table.concat(tagged,',')
        return result
    end
    -- Static stamp records reachable from the loaded definitions (f70f20).
    local function survey(controller)
        local manager=api.pointer(read(controller+O.level_controller.stamp_manager,8))
        if not manager then return false end
        local sets=u(read(manager+0xbc,4),0);assert(sets<=4096,'Stamp set count exceeds bound')
        local records,tagged,counts,examples,truncated=0,0,{},{},false
        if sets>0 then
            local array=pointer(manager+0x38)
            for i=0,sets-1 do
                local set=api.pointer(read(array+i*8,8))
                local variants=set and u(read(set+0x30,4),0) or 0
                assert(variants<=1024,'Stamp variant count exceeds bound')
                for j=0,variants-1 do
                    local head=read(pointer(set+0x28)+j*0x18,0x18)
                    local n,base=u(head,0x10),api.pointer(head,8)
                    if base and n>0 then
                        if n>512 or records+n>8000 then truncated=true;break end
                        local bytes=read(base,n*O.stamp.size)
                        for k=0,n-1 do
                            if bytes:sub(k*O.stamp.size+9,k*O.stamp.size+16)~=string.rep('\0',8)then
                                records=records+1
                                local tag=u(bytes,k*O.stamp.size+0xd0)
                                if tag~=0 then
                                    tagged=tagged+1;counts[tag]=(counts[tag] or 0)+1
                                    if #examples<12 then examples[#examples+1]=string.format('%08x/%d/%d=%d',u(read(set,4),0),j,k,tag)end
                                end
                            end
                        end
                    end
                end
                if truncated then break end
            end
        end
        local totals={};for tag,count in pairs(counts)do totals[#totals+1]=tag..':'..count end
        table.sort(totals)
        log.debug(string.format('CONSTELLATION_STAMP_SURVEY sets=%d records=%d tagged=%d tags=[%s] examples=[%s] truncated=%s',
            sets,records,tagged,table.concat(totals,','),table.concat(examples,','),tostring(truncated)))
        return true
    end
    local function observe()
        if not map.on_top()then return end
        local b=pointer(game+O.rva.board)
        local hovered=Board.hovered(read,b)
        if not hovered then return end
        local preview,row,seed,difficulty,kind,planet=hovered.preview,hovered.row,hovered.seed,hovered.difficulty,hovered.kind,hovered.planet
        local key=seed..':'..kind..':'..difficulty..':'..u(preview,12)
        if seen[key]then return end
        local controller=pointer(pointer(game+O.rva.ui_root)+O.ui_root.level_controller)
        -- The preview loads asynchronously; wait for the matching descriptor.
        local level=read(controller+8,28)==preview:sub(1,28)
            and (level_inputs(controller,O.level_controller.level,kind) or level_inputs(controller,O.level_controller.previous_level,kind))
        if not level then
            attempts[key]=(attempts[key] or 0)+1
            if attempts[key]<20 then return end
        end
        seen[key]=true;logged=logged+1
        local _,inputs=bind(Planet.bind(read,u,api.pointer,game,b,planet))
        local record=inputs.mission(kind)
        local faction=preview:byte(9)
        assert(faction==record.faction and faction>=2 and faction<=4,'Preview faction differs from mission record')
        local effect=inputs.effect_id(hovered.category,hovered.operation_id,planet)
        local campaign=inputs.campaign(planet,effect);local settings=inputs.settings(faction,difficulty)
        local predicted=Constellations.resolve(seed,settings,campaign,record,inputs.disabled)
        local head=string.format('CONSTELLATION_CHECK planet=%d row=%d type=%d seed=%u difficulty=%d faction=%d effect=%u campaign=[%s] predicted=[%s]',
            planet,row,kind,seed,difficulty,faction,effect,join(campaign),Constellations.describe(predicted.list))
        if not level then log.debug(head..' level=unavailable agree=unknown');return end
        if not level.valid then
            log.debug(string.format('%s level=%x explicit=[%s] stamps=%d stamp=%s later_tagged=[%s] full=unresolved agree=unknown',head,
                level.offset,join(level.explicit),level.stamps,level.stamp,level.later))
            return
        end
        local initial={};for _,tag in ipairs(campaign)do initial[#initial+1]=tag end
        for _,tag in ipairs(level.tags)do initial[#initial+1]=tag end
        local full=Constellations.resolve(seed,settings,initial,record,inputs.disabled)
        log.debug(string.format('%s level=%x explicit=[%s] stamps=%d stamp=%s later_tagged=[%s] full=[%s] agree=%s',head,level.offset,
            join(level.explicit),level.stamps,level.stamp,level.later,Constellations.describe(full.list),
            tostring(join(full.list)==join(predicted.list))))
        if not surveyed then
            surveyed=true
            local ok,err=pcall(survey,controller)
            if not ok then log.warn('CONSTELLATION_STAMP_SURVEY_BLOCKED '..tostring(err))
            elseif not err then surveyed=false end
        end
    end
    -- Diagnostics must never stop the mod or interrupt a search.
    observe_constellations=function(now)
        if now-last<0.5 or logged>=64 or reroll_session.view().running then return end
        last=now
        local ok,err=pcall(observe)
        if not ok and not reported then reported=true;log.warn('CONSTELLATION_CHECK_BLOCKED '..tostring(err))end
    end
end
log.debug('Constellations: accept or exclude per checked mission, else for the operation; hover a mission to log CONSTELLATION_CHECK')
return {bind_constellations=bind_constellations,observe_constellations=observe_constellations}
