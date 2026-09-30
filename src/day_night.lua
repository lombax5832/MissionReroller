-- The Day / Night filter on the viewed planet (docs/DAY_NIGHT_RESEARCH.md).
-- An operation matches when every mission's level node stays on the chosen
-- side, outside the twilight band, for the buffer after the seed is written.
-- Sky is src/planet_sky.lua. load() reads the planet through read(address,n)
-- and u(bytes,offset); the rest is arithmetic on what it read.
local O=...
local ffi=require('ffi')
return function(Sky)
    local D={}
    -- Minutes of the time of day on each side of 06:00 and 18:00 that count
    -- as neither day nor night.
    D.BAND=30
    -- Seconds the chosen side must last after the write, before the cap.
    D.WANTED=9000
    -- The search checks from MARGIN seconds ahead for SLACK seconds more than
    -- the buffer, so a match still holds when it is written; the window is
    -- recomputed every REFRESH seconds of war time.
    D.MARGIN,D.SLACK,D.REFRESH=5,60,5
    local cell=ffi.new('double[1]')
    local single=ffi.new('float[1]')
    local function f(bytes,at)ffi.copy(single,bytes:sub(at+1,at+4),4);return single[0]end
    function D.war_time(read,board)
        ffi.copy(cell,read(board+O.board.war_time,8),8)
        local T=cell[0]
        assert(T==T and T>0 and T<1e12,'Invalid war time')
        return T
    end
    -- The viewed planet: its sky (map.sky()), level node longitudes and day
    -- length, or nil and the reason it is not ready.
    function D.load(read,u,board,planet,ref)
        local definition=board+O.board.campaign+planet*O.campaign.definition_stride
        if ref.seed~=u(read(definition+0x2c,4),0)then return nil,'Waiting for the sky of the viewed planet' end
        local key=read(definition+0x1c,4)
        local definitions
        for _,offset in ipairs(O.board.definitions)do if read(board+offset,4)==key then definitions=board+offset end end
        if not definitions then return nil,'Waiting for the level map of the viewed planet' end
        local count=u(read(definitions+O.definitions.node_count,4),0)
        assert(count<=512,'Invalid level node count')
        local sky=Sky.read(read,f,ref.env,ref.seed,ref.viewer)
        local T=D.war_time(read,board)
        local day=Sky.day_length(sky,T)
        assert(day>60 and day<1e7,'Invalid day length')
        local longitudes={}
        local P={planet=planet,sky=sky,definitions=definitions,day_length=day,buffer=Sky.buffer(day,D.BAND,D.WANTED)}
        function P.longitude(node)
            assert(node>=0 and node<count,'Level node outside the planet')
            local value=longitudes[node]
            if not value then
                local position=read(definitions+node*0x88+4,8)
                value=math.deg(math.atan2(f(position,4),f(position,0)))
                longitudes[node]=value
            end
            return value
        end
        return P
    end
    local function all_hold(P,line,op,side,first,last)
        if #op.missions==0 then return false end
        for _,mission in ipairs(op.missions)do
            if not Sky.holds(line,first or 1,last or #line.tods,P.longitude(mission.level_index),side,D.BAND)then return false end
        end
        return true
    end
    -- The search's check, fixed to one side. refresh(T) moves its window to
    -- the war time T; accepts(op) is Search.find's day/night argument;
    -- confirm(op,T) checks the plain buffer from T, as just before a write.
    function D.checker(P,side)
        assert(side=='day' or side=='night','Invalid side')
        local c={side=side}
        local line,at
        function c.refresh(T)
            if not line or T-at>=D.REFRESH or T<at then
                line=Sky.timeline(P.sky,T+D.MARGIN,P.buffer+D.SLACK);at=T
            end
        end
        function c.accepts(op)return all_hold(P,assert(line,'Day/night window not set'),op,side)end
        function c.confirm(op,T)return all_hold(P,Sky.timeline(P.sky,T,P.buffer),op,side)end
        -- The time of day at a node now, for the log.
        function c.time_of_day(node,T)return Sky.time_of_day(P.longitude(node),Sky.sun_longitude(P.sky,T))end
        return c
    end
    -- The earliest wait in seconds before one of the nodes starts a whole
    -- buffer on side: 0 when one does now, nil when none does within a day.
    function D.wait(P,nodes,side,T)
        local line=Sky.timeline(P.sky,T,P.day_length+P.buffer)
        local best
        for _,node in ipairs(nodes)do
            local wait=Sky.wait(line,P.buffer,P.longitude(node),side,D.BAND)
            if wait and (not best or wait<best)then best=wait end
            if best==0 then break end
        end
        return best
    end
    -- 2h 30m, 45m or 20s.
    function D.duration(seconds)
        seconds=math.floor(seconds+0.5)
        if seconds<60 then return seconds..'s' end
        local h,m=math.floor(seconds/3600),math.floor(seconds%3600/60)
        if h==0 then return m..'m' end
        return m==0 and h..'h' or h..'h '..m..'m'
    end
    return D
end
