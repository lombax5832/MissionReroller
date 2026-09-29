-- Research subset of 11e3c10 / 11e4060 / 11e44d0: IDs and seeds only.
-- This does NOT reproduce finalizer validity, modifiers, or mission selection.
return function(make_rng)
    local function mark(rows,difficulty,mask)
        -- Native 11e4b50 includes the next difficulty's first row.
        local first=(difficulty-1)*3
        for row=first,first+3 do
            if rows[row] then mask[rows[row].id]=true end
        end
    end
    local function choose(rng,count,mask)
        local start=rng:index(count)
        for offset=0,count-1 do
            local id=(start+offset)%count
            if not mask[id] then return id end
        end
    end
    return function(input,seed)
        local count,maximum=input.pool_count,input.max_difficulty
        assert(type(count)=='number' and count>=1 and count<=64 and count==math.floor(count),'Invalid pool size')
        assert(type(maximum)=='number' and maximum>=1 and maximum<=10 and maximum==math.floor(maximum),'Invalid difficulty cap')
        local rows,all={},{}
        local active=input.active
        if active and active.planet==input.planet then
            assert(active.row>=0 and active.row<110 and active.row==math.floor(active.row),'Invalid active row')
            assert(active.id>=0 and active.id<64 and active.id==math.floor(active.id),'Invalid active ID')
            rows[active.row]={row=active.row,id=active.id,seed=active.seed,difficulty=active.difficulty,preserved=true}
        end
        for difficulty=1,maximum do mark(rows,difficulty,all)end
        local rng=make_rng(seed,input.planet)
        for difficulty=1,maximum do
            local used={};mark(rows,difficulty,used)
            for row=(difficulty-1)*3,difficulty*3-1 do
                if not rows[row] then
                    local id=choose(rng,count,all)
                    if id==nil then id=choose(rng,count,used)end
                    if id~=nil then
                        rows[row]={row=row,id=id,seed=rng:next(),difficulty=difficulty}
                        all[id]=true;used[id]=true
                    end
                end
            end
        end
        -- Event order is significant; each accepted event continues this RNG.
        -- Active rows are preserved and consume no draws, as in the native pass.
        for _,event in ipairs(input.specials or {})do
            assert(event.id>=0 and event.id<8 and event.id==math.floor(event.id),'Invalid special operation ID')
            assert(event.minimum>=1 and event.maximum<=10 and event.minimum==math.floor(event.minimum)
                and event.maximum==math.floor(event.maximum),'Invalid special difficulty range')
            for difficulty=event.minimum,event.maximum do
                local row=event.id*10+29+difficulty
                if not rows[row] then
                    rows[row]={row=row,id=event.id,seed=rng:next(),difficulty=difficulty,special=true}
                end
            end
        end
        return rows
    end
end
