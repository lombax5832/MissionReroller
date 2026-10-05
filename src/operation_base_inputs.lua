-- Supported normal, invasion and special operation bases, derived from campaign inputs.
-- Defense generation and unresolved world-modifier conditions fail closed.
local O,Board=...
return function(make_identity,make_special,make_environments)
    return function(read,u,pointer,game,board,definitions,planet,inputs)
        local function word(a)return u(read(a,4),0)end
        local function count(a,limit)local n=word(a);assert(n<=limit,'Base input count exceeds bound');return n end
        local campaign=board+O.board.campaign
        -- 11e3c10 skips a planet the invasions list (+4); 11e4060 then fills the
        -- same rows with the same draws from the invasion an event record names
        -- (record +4 planet, +12 invasion; invasion +0 id, +8 level, +12 faction).
        local listed,records,first_level=false,{}
        for i=0,count(campaign+O.campaign.invasion_count,64)-1 do
            local at=campaign+O.campaign.invasions+i*0x48
            if word(at+4)==planet then listed=true;first_level=first_level or word(at+8)end
        end
        for i=0,count(campaign+O.campaign.invasion_event_count,64)-1 do
            local at=campaign+O.campaign.invasion_events+i*16
            if word(at+4)==planet then records[#records+1]=at end
        end
        local category,faction=0
        if listed or #records>0 then
            assert(listed and #records==1,'Unsupported invasion event count')
            local invasion
            for i=0,count(campaign+O.campaign.invasion_count,64)-1 do
                local at=campaign+O.campaign.invasions+i*0x48
                if word(at)==word(records[1]+12) then invasion=at;break end
            end
            assert(invasion and word(invasion+4)==planet,'Unsupported invasion of another planet')
            -- A level's category 14 generates no invasion rows.
            category=word(game+O.rva.invasion_levels+math.min(word(invasion+8),3)*0x48)
            assert(category<14,'Unsupported invasion level category')
            faction=word(invasion+12)
        else
            assert(read(campaign+O.campaign.planet_enabled+planet*O.campaign.planet_stride,1):byte()~=0,'Planet generation disabled')
            local events={}
            for i=0,count(campaign+O.campaign.base_count,512)-1 do
                local at=campaign+O.campaign.bases+i*20
                if word(at+8)==planet then events[#events+1]=at end
            end
            assert(#events==1,'Unsupported normal campaign event count')
            assert(word(events[1]+12)~=2,'Unsupported defense operation bases')
            make_environments(read,u,pointer,game,board,inputs.effects,inputs.biome_definition)(planet,4294967295,true)
            faction=word(campaign+O.campaign.planet_faction+planet*O.campaign.planet_stride)
        end
        if faction==1 then faction=2 end
        assert(faction>=2 and faction<=4,'Unsupported operation faction')
        local limit=10;local value=inputs.config.lookup(inputs.config.hash({0xaf218cac,0xfaabbea9}))
        if value and u(value,12)==6 then limit=math.min(10,u(value,16))end
        assert(limit>=1,'Unsupported zero difficulty cap')
        local special=make_special(read,u,pointer)(board,planet,definitions,true)
        for _,event in ipairs(special)do
            local category=word(event.definition+0x38)
            -- 174ab50: 14 resolves to 12, or to 9 unless the planet's first
            -- invasion is at level 1 (8). Special faction 1, also 8, is rejected above.
            if category==14 then category=word(event.definition+0x18)~=1 and 12 or first_level==1 and 8 or 9 end
            assert(category<14,'Unsupported special category')
            event.category=category
        end
        local bytes=read(board+O.board.active_snapshot,Board.OPERATION_SIZE);local active
        if Board.valid(bytes,0) and Board.planet(bytes,0)==planet then
            active=Board.operation(bytes,0)
            assert(Board.modifier_count(bytes,0)<=2,'Invalid preserved modifier count')
            active.modifiers=Board.modifiers(bytes,0)
        end
        local input={planet=planet,pool_count=word(definitions+O.definitions.pool_count),max_difficulty=limit,active=active,specials=special}
        return function(seed)
            local rows=make_identity(input,seed);local result={}
            for row=0,109 do
                local op=rows[row]
                if op then
                    op.category=category;op.faction=faction;op.explicit_hash=0
                    if op.preserved then
                        op.category=active.category;op.faction=active.faction;op.explicit_hash=active.explicit_hash
                    elseif op.special then
                        local found
                        for _,event in ipairs(special)do
                            if event.id==op.id and op.difficulty>=event.minimum and op.difficulty<=event.maximum then found=event;break end
                        end
                        assert(found,'Missing special base metadata');op.category=found.category;op.faction=found.faction
                    end
                    result[#result+1]=op
                end
            end
            -- The identity input last: the seed solver walks the same draws.
            return result,active,input
        end
    end
end
