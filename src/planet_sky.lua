-- Day and night on a planet: the sun of the war table's viewed planet at a
-- war time, and the time of day at a level node (docs/DAY_NIGHT_RESEARCH.md).
-- The sky is the map UI's environment: a chain of bodies, each spinning and
-- orbiting its parent, with the star at the origin (101c7c0, 1016c20,
-- 1022270). The time of day is 1017ef0: the angle about the planet's Z axis
-- between the node and the sun, in minutes, 720 at noon.
local O=...
local ffi=require('ffi')
return function(make_rng)
    local M={}
    local TWO_PI=6.2831854820251465
    -- The generator is started at the seed plus these, per body (1022270, 101c7c0).
    local SPIN_SALT,ORBIT_SALT=0x10e3,0x10ec
    local float=ffi.new('float[1]')
    local function f32(x)float[0]=x;return float[0]end
    local function lerp(a,b,t)return f32(f32((1-t)*a)+f32(t*b))end
    -- A float in [0,1) from one step of the generator started at x.
    local function unit(x)return f32(f32(make_rng(x%4294967296):next())*2.3283064365386963e-10)end

    -- The sky of the environment at env: its seed, viewer body and the chain of
    -- bodies up from the viewer. read(address,size) returns bytes, f(bytes,
    -- offset) a float of them.
    function M.read(read,f,env,seed,viewer)
        assert(viewer>=0 and viewer<9,'Invalid viewer body')
        local bodies={}
        local function body(index,depth)
            if bodies[index]then return end
            assert(depth<9,'Sky body chain too deep')
            local L=read(env+index*O.sky_body.size,O.sky_body.spin_blend+4)
            local b={
                before={f(L,0x94),f(L,0x98),f(L,0x9c),f(L,0xa0)},
                after={f(L,0xa4),f(L,0xa8),f(L,0xac),f(L,0xb0)},
                parent=L:byte(O.sky_body.parent+1),
                distance=f(L,O.sky_body.distance),
                orbit={f(L,O.sky_body.orbit_period),f(L,O.sky_body.orbit_period+4),f(L,O.sky_body.orbit_blend)},
                spin={f(L,O.sky_body.spin_period),f(L,O.sky_body.spin_period+4),f(L,O.sky_body.spin_blend)},
                phase={f(L,O.sky_body.phase),f(L,O.sky_body.phase+4)},
            }
            for _,list in ipairs({b.before,b.after,b.orbit,b.spin,b.phase,{b.distance}})do
                for _,v in ipairs(list)do assert(v==v and v>-1e9 and v<1e9,'Invalid sky body value')end
            end
            bodies[index]=b
            if b.parent~=9 then assert(b.parent<9,'Invalid sky body parent');body(b.parent,depth+1)end
        end
        body(viewer,0)
        return {seed=seed,viewer=viewer,bodies=bodies}
    end

    -- Rigid transforms in the game's row-vector convention, p' = p*R + t.
    local IDENTITY={1,0,0,0,1,0,0,0,1}
    local function quaternion(q)
        local x,y,z,w=q[1],q[2],q[3],q[4]
        local n=x*x+y*y+z*z+w*w
        local s=n~=0 and 2/n or 0
        return {1-s*(y*y+z*z),s*(x*y+w*z),s*(x*z-w*y),
            s*(x*y-w*z),1-s*(x*x+z*z),s*(y*z+w*x),
            s*(x*z+w*y),s*(y*z-w*x),1-s*(x*x+y*y)},{0,0,0}
    end
    local function turn(a)
        local c,s=math.cos(a),math.sin(a)
        return {c,s,0,-s,c,0,0,0,1},{0,0,0}
    end
    -- A, then B.
    local function compose(Ra,ta,Rb,tb)
        local R,t={},{}
        for i=0,2 do for j=1,3 do
            R[i*3+j]=Ra[i*3+1]*Rb[j]+Ra[i*3+2]*Rb[3+j]+Ra[i*3+3]*Rb[6+j]
        end end
        for j=1,3 do t[j]=ta[1]*Rb[j]+ta[2]*Rb[3+j]+ta[3]*Rb[6+j]+tb[j]end
        return R,t
    end
    -- 1016c20: the angle of a rotation of a period at war time T.
    local function angle(T,period,phase)
        if period<0 then return phase end
        return f32(math.fmod(T/(period+0.001)*TWO_PI+phase,TWO_PI))
    end
    -- 101c7c0: the body's world transform.
    local function world(sky,index,T)
        local b=sky.bodies[index]
        local orbit=angle(T,lerp(b.orbit[1],b.orbit[2],b.orbit[3]),lerp(b.phase[1],b.phase[2],unit(sky.seed+index+ORBIT_SALT)))
        local R,t=quaternion(b.before)
        R,t=compose(R,t,IDENTITY,{0,b.distance,0})
        local Rt,tt=turn(orbit);R,t=compose(R,t,Rt,tt)
        local Ra,ta=quaternion(b.after);R,t=compose(R,t,Ra,ta)
        if b.parent~=9 then local Rp,tp=world(sky,b.parent,T);R,t=compose(R,t,Rp,tp)end
        return R,t
    end

    -- 1022270: the direction to the star in the viewer's spinning frame, the
    -- frame of the level nodes, at war time T.
    function M.sun(sky,T)
        local b=sky.bodies[sky.viewer]
        local spin=angle(T,lerp(b.spin[1],b.spin[2],b.spin[3]),lerp(b.phase[1],b.phase[2],unit(sky.seed+sky.viewer+SPIN_SALT)))
        local R,t=turn(spin)
        local Rw,tw=world(sky,sky.viewer,T)
        R,t=compose(R,t,Rw,tw)
        -- The origin in the local frame: -t times the transpose of R.
        local x=-(t[1]*R[1]+t[2]*R[2]+t[3]*R[3])
        local y=-(t[1]*R[4]+t[2]*R[5]+t[3]*R[6])
        local z=-(t[1]*R[7]+t[2]*R[8]+t[3]*R[9])
        local n=math.sqrt(x*x+y*y+z*z)
        assert(n>0,'Sky without a star')
        return x/n,y/n,z/n
    end
    function M.sun_longitude(sky,T)
        local x,y=M.sun(sky,T)
        return math.deg(math.atan2(y,x))
    end
    -- 1017ef0: minutes into the day at a longitude (degrees), 720 at noon.
    function M.time_of_day(longitude,sun_longitude)
        return (720+4*(longitude-sun_longitude))%1440
    end

    -- The time of day at longitude 0 from war time from to from+duration,
    -- sampled so that it moves at most one minute between samples, and kept
    -- running past 1440 instead of wrapping. Longitude L adds 4*L.
    function M.timeline(sky,from,duration)
        assert(duration>=0,'Invalid timeline')
        local first=M.sun_longitude(sky,from)
        local rate=math.abs(((first-M.sun_longitude(sky,from+1)+180)%360)-180)*4
        local step=math.max(0.5,math.min(600,1/math.max(rate,1e-9)))
        local count=math.min(20000,math.max(1,math.ceil(duration/step)))
        step=duration/count
        local tods,previous,value={M.time_of_day(0,first)},first,M.time_of_day(0,first)
        for i=1,count do
            local lon=M.sun_longitude(sky,from+step*i)
            value=value+4*(((previous-lon+180)%360)-180)
            previous=lon;tods[i+1]=value
        end
        return {from=from,step=step,tods=tods}
    end

    -- Day is [360+band, 1080-band] minutes and night [1080+band, 1800-band],
    -- past midnight, outside the twilight band. Whether a node at longitude
    -- stays on side for samples first..last of the timeline.
    local function side_range(side,band)
        if side=='day' then return 360+band,1080-band end
        if side=='night' then return 1080+band,1800-band end
        error('Invalid side '..tostring(side))
    end
    function M.holds(line,first,last,longitude,side,band)
        local lo,hi=side_range(side,band)
        local base=line.tods[first]+4*longitude
        -- Shift by whole days so the start lies in [lo-360, lo+1080).
        local DAY=1440
        local shift=DAY*math.floor((lo-360+DAY-base)/DAY)
        for i=first,last do
            local tod=line.tods[i]+4*longitude+shift
            if tod<lo or tod>hi then return false end
        end
        return true
    end
    -- Whether a node holds over the whole timeline.
    function M.holds_all(line,longitude,side,band)
        return M.holds(line,1,#line.tods,longitude,side,band)
    end

    -- The length of a day in seconds at war time T.
    function M.day_length(sky,T)
        local first=M.sun_longitude(sky,T)
        local rate=math.abs(((first-M.sun_longitude(sky,T+60)+180)%360)-180)/60
        local guess=360/math.max(rate,1e-9)
        local line=M.timeline(sky,T,guess)
        return guess*1440/math.max(line.tods[#line.tods]-line.tods[1],1e-9)
    end

    -- The buffer the filter guarantees: wanted seconds, or half of a side
    -- outside the twilight band when a day is short.
    function M.buffer(day_length,band,wanted)
        local side=day_length/2-2*band*day_length/1440
        return math.max(0,math.min(wanted,0.5*side))
    end

    -- Seconds after line.from until a node at longitude starts a stretch of
    -- `duration` seconds on side, or nil when none starts within the line.
    function M.wait(line,duration,longitude,side,band)
        local span=math.ceil(duration/line.step)
        for i=1,#line.tods-span do
            if M.holds(line,i,i+span,longitude,side,band)then return (i-1)*line.step end
        end
    end
    return M
end
