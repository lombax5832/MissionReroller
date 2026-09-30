-- Usage: luajit test_day_night.lua <src>
-- src/planet_sky.lua and src/day_night.lua on synthetic skies and memory:
-- the sun of a spinning body and of a moon, the time of day at a node, the
-- window a match must hold for, the buffer cap and the city wait.
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local src=assert(arg[1])
local O=H.offsets(src)
local make_rng=H.module(src..'/generation_rng.lua')
local Sky=H.module(src..'/planet_sky.lua')(make_rng)
local D=H.module(src..'/day_night.lua')(Sky)
local ffi=require('ffi')
local function near(a,b,e,what)assert(math.abs(a-b)<=e,string.format('%s: %.6f vs %.6f',what,a,b))end
local function angle_near(a,b,e,what)near(((a-b+180)%360)-180,0,e,what)end

-- A sky built in Lua, as M.read returns it.
local IDENTITY={0,0,0,1}
local function body(t)
    return {before=t.before or IDENTITY,after=t.after or IDENTITY,parent=t.parent or 9,distance=t.distance or 100,
        orbit={t.orbit or 50000,t.orbit or 50000,0},spin={t.spin or 3600,t.spin or 3600,0},phase={t.phase or 0,t.phase or 0}}
end

-- One spinning body: the orbit cancels and the sun sits at -90 degrees minus
-- the spin angle (1016c20 with the phase fixed by an equal range).
local spin,phase=7200,0.4
local planet={seed=12345,viewer=0,bodies={[0]=body({spin=spin,phase=phase,orbit=90000,distance=500})}}
for _,T in ipairs({0,1000,5000,84733314.67})do
    local a=math.fmod(T/(spin+0.001)*6.2831854820251465+phase,6.2831854820251465)
    local x,y,z=Sky.sun(planet,T)
    near(x*x+y*y+z*z,1,1e-9,'unit sun');near(z,0,1e-9,'equatorial sun')
    angle_near(Sky.sun_longitude(planet,T),-90-math.deg(a),1e-3,'spin angle at '..T)
end
near(Sky.day_length(planet,1000),spin+0.001,spin*1e-4,'day length of a spin')
assert(Sky.time_of_day(10,10)==720 and Sky.time_of_day(10,-80)==1080 and Sky.time_of_day(10,190)==0,'minutes of 1017ef0')

-- A timeline runs on past midnight; a node's time of day is shifted by 4 a degree.
local line=Sky.timeline(planet,1000,spin)
near(line.tods[#line.tods]-line.tods[1],1440,2,'one day of samples')
for i=2,#line.tods do assert(line.tods[i]>line.tods[i-1] and line.tods[i]-line.tods[i-1]<=1.01,'monotone, a minute a sample')end
local sun=Sky.sun_longitude(planet,1000)
local function at(tod)return sun+(tod-720)/4 end    -- the longitude where it is tod now
-- Two hours at 10:00 stay in the day; from 16:00 they cross the dusk band.
local short=Sky.timeline(planet,1000,spin/12)       -- two hours of the planet's day
assert(Sky.holds_all(short,at(600),'day',30),'10:00 holds two hours of day')
assert(not Sky.holds_all(short,at(960),'day',30),'16:00 reaches the dusk band')
assert(Sky.holds_all(short,at(900),'day',30),'15:00 ends at 17:00, outside the band')
assert(not Sky.holds_all(short,at(600),'night',30),'10:00 is not night')
assert(Sky.holds_all(short,at(1200),'night',30) and Sky.holds_all(short,at(60),'night',30),'night on both sides of midnight')
assert(Sky.holds_all(short,at(1380),'night',30),'23:00 runs past midnight in the night')
assert(not Sky.holds_all(short,at(300),'night',30),'05:00 reaches the dawn band')
assert(not Sky.holds_all(short,at(1080),'night',30) and not Sky.holds_all(short,at(1080),'day',30),'18:00 is twilight')
-- The wait for a node at 16:00 to start two hours of night: 18:30 is the first start.
local ahead=Sky.timeline(planet,1000,spin*1.2)
near(Sky.wait(ahead,spin/12,at(960),'night',30),spin*150/1440,ahead.step+1,'wait for the night')
assert(Sky.wait(ahead,spin/12,at(1200),'night',30)==0,'already night')
assert(Sky.wait(ahead,spin*0.6,at(960),'night',30)==nil,'no night lasts 60% of a day')

-- The buffer: 2.5 hours on a long day, half a side outside the bands on a short one.
assert(Sky.buffer(56553,30,9000)==9000,'long day')
near(Sky.buffer(3870,30,9000),0.5*(3870/2-2*30*3870/1440),1e-9,'short day')
assert(Sky.buffer(100,400,9000)==0,'no side left')

-- A moon of a planet: its sun moves at neither the spin nor the orbit rate
-- alone, and the moon's longitude changes unevenly.
local moon={seed=0xa8f91202,viewer=0,bodies={[0]=body({parent=1,distance=125,orbit=5000,spin=17000}),
    [1]=body({distance=875,orbit=86400,spin=8000})}}
local day=Sky.day_length(moon,84733809)
assert(day>3000 and day<6000,'a moon day: '..day)
local rates={}
for i=0,4 do
    local T=84733809+i*1000
    rates[#rates+1]=(((Sky.sun_longitude(moon,T)-Sky.sun_longitude(moon,T+10)+180)%360)-180)/10
end
assert(math.max(unpack(rates))-math.min(unpack(rates))>0.001,'the rate varies over the moon orbit')

-- Synthetic memory: a board with the planet's definition, its level map and a
-- sky of the map UI, laid out with the offsets of src/offsets.lua.
local bytes={}
local function put(address,s)for i=1,#s do bytes[address+i-1]=s:byte(i)end end
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function float(v)local c=ffi.new('float[1]',v);return ffi.string(c,4)end
local function double(v)local c=ffi.new('double[1]',v);return ffi.string(c,8)end
local function read(address,size)
    local out={}
    for i=0,size-1 do out[i+1]=string.char(bytes[address+i] or 0)end
    return table.concat(out)
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local board,env=0x20000000,0x40000000
local index=7
local definition=board+O.board.campaign+index*O.campaign.definition_stride
put(definition+0x1c,word(0xabcdef01));put(definition+0x2c,word(12345))
local slot=board+O.board.definitions[2]
put(slot,word(0xabcdef01));put(slot+O.definitions.node_count,word(4))
local longitudes={0,90,-135,170}
for n,lon in ipairs(longitudes)do
    local r=math.rad(lon)
    put(slot+(n-1)*0x88+4,float(math.cos(r)*0.8)..float(math.sin(r)*0.8)..float(0.6))
end
local L=env
put(L+0x94,float(0)..float(0)..float(0)..float(1));put(L+0xa4,float(0)..float(0)..float(0)..float(1))
put(L+O.sky_body.parent,string.char(9));put(L+O.sky_body.distance,float(500))
put(L+O.sky_body.orbit_period,float(90000)..float(90000));put(L+O.sky_body.spin_period,float(spin)..float(spin))
put(L+O.sky_body.phase,float(phase)..float(phase))
local T=84733314.5
put(board+O.board.war_time,double(T))
assert(D.war_time(read,board)==T)
-- The sky of another planet is not used.
local P,why=D.load(read,u,board,index,{env=env,seed=999,viewer=0})
assert(P==nil and why:find('sky'),'another planet')
P=assert(D.load(read,u,board,index,{env=env,seed=12345,viewer=0}))
assert(P.definitions==slot and P.planet==index)
near(P.day_length,spin,1,'loaded day length')
assert(P.buffer==Sky.buffer(P.day_length,D.BAND,D.WANTED) and P.buffer<D.WANTED,'a two-hour day caps the buffer')
for n,lon in ipairs(longitudes)do near(P.longitude(n-1),lon,1e-4,'node longitude '..n)end
assert(not pcall(P.longitude,4),'node outside the planet')
-- The checker: an operation holds when all its missions do.
local c=D.checker(P,'night')
assert(not pcall(c.accepts,{missions={{level_index=0}}}),'a window is needed first')
c.refresh(T)
local sun_now=Sky.sun_longitude(P.sky,T)
local tods={}
for n,lon in ipairs(longitudes)do tods[n]=Sky.time_of_day(lon,sun_now)end
for n=1,4 do near(c.time_of_day(n-1,T),tods[n],1e-3,'time of day of node '..n)end
local function op(...)local m={};for i,node in ipairs({...})do m[i]={level_index=node}end;return {row=1,missions=m}end
for n=1,4 do
    local expected=Sky.holds_all(Sky.timeline(P.sky,T+D.MARGIN,P.buffer+D.SLACK),longitudes[n],'night',D.BAND)
    assert(c.accepts(op(n-1))==expected,'node '..n..' at '..tods[n])
end
local night,day
for n=1,4 do
    if c.accepts(op(n-1))then night=n-1 end
    if D.checker(P,'day').confirm(op(n-1),T)then day=n-1 end
end
assert(night and day,'one night and one day node on this planet: '..table.concat(tods,','))
assert(c.accepts(op(night,night)) and not c.accepts(op(night,day)) and not c.accepts({missions={}}),'every mission must hold')
assert(c.confirm(op(night),T),'the match holds at the write')
-- The countdown: now for a node that holds, later for one that does not.
assert(D.wait(P,{day,night},'night',T)==0)
local later=D.wait(P,{day},'night',T)
assert(later and later>0 and later<P.day_length,'the day node reaches the night')
assert(D.wait(P,{},'night',T)==nil)
assert(D.duration(9000)=='2h 30m' and D.duration(2700)=='45m' and D.duration(20)=='20s' and D.duration(3600)=='1h')
print('Day and night: sun of a spin and a moon, time of day, windows, buffer cap, city wait and planet loading passed')
