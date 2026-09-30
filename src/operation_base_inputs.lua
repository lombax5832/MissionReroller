-- Supported normal and special operation bases, derived from campaign inputs.
-- Invasion/defense generation and unresolved world-modifier conditions fail closed.
local O=...
return function(make_identity,make_special,make_environments)
    return function(read,u,pointer,game,board,definitions,planet,inputs)
        local function word(a)return u(read(a,4),0)end
        local function count(a,limit)local n=word(a);assert(n<=limit,'Base input count exceeds bound');return n end
        local campaign=board+O.board.campaign
        assert(read(campaign+O.campaign.planet_enabled+planet*O.campaign.planet_stride,1):byte()~=0,'Planet generation disabled')
        local events={}
        for i=0,count(campaign+O.campaign.base_count,512)-1 do
            local at=campaign+O.campaign.bases+i*20
            if word(at+8)==planet then events[#events+1]=at end
        end
        assert(#events==1,'Unsupported normal campaign event count')
        assert(word(events[1]+12)~=2,'Unsupported defense operation bases')
        for i=0,count(campaign+O.campaign.invasion_count,64)-1 do
            assert(word(campaign+O.campaign.invasions+4+i*0x48)~=planet,'Unsupported invasion operation bases')
        end
        make_environments(read,u,pointer,game,board,inputs.effects,inputs.biome_definition)(planet,4294967295,true)
        local faction=word(campaign+O.campaign.planet_faction+planet*O.campaign.planet_stride)
        if faction==1 then faction=2 end
        assert(faction>=2 and faction<=4,'Unsupported normal faction')
        local limit=10;local value=inputs.config.lookup(inputs.config.hash({0xaf218cac,0xfaabbea9}))
        if value and u(value,12)==6 then limit=math.min(10,u(value,16))end
        assert(limit>=1,'Unsupported zero difficulty cap')
        local special=make_special(read,u,pointer)(board,planet,definitions,true)
        for _,event in ipairs(special)do
            local category=word(event.definition+0x38)
            if category==14 then category=word(event.definition+0x18)==1 and 9 or 12 end
            assert(category<14,'Unsupported special category')
            event.category=category
        end
        local bytes=read(board+O.board.active_snapshot,92);local active
        if bytes:byte(53)~=0 and bytes:byte(17)+bytes:byte(18)*256==planet then
            active={row=u(bytes,0),id=bytes:byte(25),seed=u(bytes,12),difficulty=bytes:byte(33),planet=planet,
                category=u(bytes,28),faction=u(bytes,36),explicit_hash=u(bytes,8),template_index=u(bytes,56),modifiers={}}
            assert(bytes:byte(69)<=2,'Invalid preserved modifier count')
            for i=0,bytes:byte(69)-1 do active.modifiers[#active.modifiers+1]=u(bytes,60+i*4)end
        end
        local input={planet=planet,pool_count=word(definitions+O.definitions.pool_count),max_difficulty=limit,active=active,specials=special}
        return function(seed)
            local rows=make_identity(input,seed);local result={}
            for row=0,109 do
                local op=rows[row]
                if op then
                    op.category=0;op.faction=faction;op.explicit_hash=0
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
            return result,active
        end
    end
end
