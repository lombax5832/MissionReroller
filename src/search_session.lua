-- Pure bounded experiment controller. The adapter owns native guards and publication.
local S={}
-- Every mission type of build 25480438 that has a title, grouped by title
-- (scripts/list_mission_families.py). The three Eradicate titles are one
-- family. A family's position is its identifier; append, never reorder.
S.options={
    {name='Launch ICBM',ids={0,59,119}},
    {name='Geological Survey',ids={22,81,82,129,157}},
    {name='Eradicate forces',ids={7,40,56,65,110,120}},
    {name='Spread Democracy',ids={28,55,85,135}},
    {name='Evacuate High-Value Assets',ids={17,18,74,109,125,143}},
    {name='Retrieve Valuable Data',ids={3,63,118,158}},
    {name='Search and Destroy',ids={12,35,51,68,103}},
    {name='Emergency Evacuation',ids={26,84,107}},
    {name='Nuke Nursery',ids={79,80,111}},
    {name='Purge Hatcheries',ids={66,108}},
    {name='Destroy Command Bunkers',ids={21,38}},
    {name='Retrieve Recon Craft Intel',ids={57,58,136,146}},
    {name='Acquire Evidence',ids={45}},
    {name='Activate Oil Pumps',ids={87}},
    {name='Activate TCS+ Station',ids={91}},
    {name='Activate Terminid Control System',ids={90}},
    {name='Annex Untapped Mineral Sites',ids={41}},
    {name='Chart Terminid Tunnels',ids={101}},
    {name='Cleanse Infested District',ids={104}},
    {name='Collect Gloom Spore Readings',ids={102}},
    {name='Collect Gloom-Infused Oil',ids={100}},
    {name='Collect Meteorological Data',ids={98}},
    {name='Conduct Mobile E-711 Extraction',ids={116}},
    {name='Confiscate Assets',ids={42}},
    {name='Cull Spawn',ids={96}},
    {name='Deactivate Terminid Control System',ids={92}},
    {name='Democratize the Void',ids={159}},
    {name='Deploy Dark Fluid',ids={93}},
    {name='Destroy Bio-Processors',ids={49}},
    {name='Destroy Exospire',ids={152}},
    {name='Destroy Gazer Spire',ids={155}},
    {name='Destroy Harvesters',ids={132,141}},
    {name='Destroy Illuminate Warp Ships',ids={122,140}},
    {name='Destroy Spore Lung',ids={115}},
    {name='Destroy Transmission Network',ids={33}},
    {name='Destroy Warp Gateways',ids={123}},
    {name='Eliminate Automaton Factory Strider',ids={34}},
    {name='Eliminate Automaton Hulks',ids={4,39}},
    {name='Eliminate Bile Titans',ids={72}},
    {name='Eliminate Brood Commanders',ids={83}},
    {name='Eliminate Chargers',ids={62}},
    {name='Eliminate Devastators',ids={25}},
    {name='Eliminate Impaler',ids={94}},
    {name='Enable Oil Extraction',ids={64}},
    {name='Evacuate Citizens',ids={142}},
    {name='Evacuate Colonists',ids={137}},
    {name='Extract Anomalous Material',ids={154}},
    {name='Extract E-711',ids={114}},
    {name='Extract Intel',ids={44}},
    {name='Extract Research Probe Data',ids={99}},
    {name='Free Colony',ids={134}},
    {name='Free the City',ids={139}},
    {name='Halt Cyborg Production',ids={1}},
    {name='Infiltrate Illuminate Lair',ids={153,160}},
    {name='Neutralize Anomalous Artifacts',ids={151}},
    {name='Neutralize Ground-to-Orbit Defenses',ids={27,52}},
    {name='Rapid Acquisition',ids={8}},
    {name='Repel Invasion Fleet',ids={144}},
    {name='Restart Pumps',ids={113}},
    {name='Restore Air Quality',ids={105}},
    {name='Retrieve Essential Personnel',ids={14,71}},
    {name='Root out Hives',ids={97}},
    {name='Sabotage Air Base',ids={5,32,37,53}},
    {name='Sabotage Orgo-Plasma Synthesis',ids={43}},
    {name='Sabotage Supply Bases',ids={24,36,54}},
    {name='Scour Surface',ids={95}},
    {name='Secure Black Box',ids={46}},
    {name='Secure Research Site',ids={69}},
    {name='Seize Industrial Complex',ids={6}},
    {name='Start Fuel Pumps',ids={29,86}},
    {name='Suppress Toxic Pollination',ids={156}},
    {name='Take Down Overship',ids={147,148,161}},
    {name='Terminate Illegal Broadcast',ids={30,88,138}},
    {name='Upload Escape Pod Data',ids={31,89}},
}
-- A constellation group holds the rules for one mission, tag -> 'accept' or
-- 'exclude': the mission carries at least one accepted tag, if any is
-- accepted, and no excluded tag. Group i belongs to the mission of checked
-- family i. A mission without resolved tags never satisfies a rule.
local function satisfies(group,m)
    if not group or not next(group)then return true end
    if not m.tags then return false end
    local wanted,found=false,false
    for tag,mode in pairs(group)do
        if mode=='exclude' then
            if m.tags[tag]then return false end
        else wanted=true;if m.tags[tag]then found=true end end
    end
    return found or not wanted
end
-- Group 0 applies when no mission is checked: one mission of the operation
-- carries an accepted tag, and no mission carries an excluded one.
local function operation_satisfies(group,op)
    if not group or not next(group)then return true end
    if #op.missions==0 then return false end
    local wanted,excludes,found=false,false,false
    for _,mode in pairs(group)do if mode=='exclude' then excludes=true else wanted=true end end
    for _,m in ipairs(op.missions)do
        if not m.tags then
            if excludes then return false end
        else
            for tag,mode in pairs(group)do
                if m.tags[tag]then
                    if mode=='exclude' then return false end
                    found=true
                end
            end
        end
    end
    return found or not wanted
end
-- The operation in progress keeps its seed and missions whatever the campaign
-- seed becomes (operation_identity preserves its row). Returns its row and
-- difficulty when it belongs to the snapshot's planet.
function S.active_row(s)
    local record=s and s.active
    if type(record)~='string' or #record~=184 then return nil end
    local function byte(at)return tonumber(record:sub(at*2+1,at*2+2),16)end
    if byte(52)==0 or byte(16)+byte(17)*256~=s.planet then return nil end
    return byte(0)+byte(1)*256+byte(2)*65536+byte(3)*16777216,byte(32)
end
-- A city or megafactory is a planet region. Its operations occupy rows
-- 30 + region*10 .. 39 + region*10, one per difficulty (11e44d0). Without a
-- scope every operation of the planet is searched.
function S.in_scope(row,scope)
    if not scope then return true end
    return row>=30 and row<110 and math.floor((row-30)/10)==scope.region
end
function S.scope(value)
    if value==nil then return nil end
    local region=value.region
    assert(type(region)=='number' and region>=0 and region<8 and region==math.floor(region),'Invalid city scope')
    return {region=region}
end
function S.find(snapshot,difficulty,required,modifiers,constellations,scope)
    local groups=constellations and constellations.groups or {}
    for _,op in ipairs(snapshot.operations) do
        if op.difficulty==difficulty and S.in_scope(op.row,scope) then
            local found={};local yes=operation_satisfies(groups[0],op)
            for _,m in ipairs(op.missions) do
                for i,opt in ipairs(S.options) do
                    for _,id in ipairs(opt.ids) do if m.native_type==id and satisfies(groups[i],m) then found[i]=true end end
                end
            end
            for i in pairs(required) do if not found[i] then yes=false end end
            if next(modifiers or {}) then
                if not op.modifiers then yes=false
                else
                    local present={};for _,id in ipairs(op.modifiers)do present[id]=true end
                    for id,mode in pairs(modifiers)do
                        if (mode=='require' and not present[id]) or (mode=='exclude' and present[id])then yes=false end
                    end
                end
            end
            if yes then return op end
        end
    end
end
function S.new(options)
    options=options or {}
    local limit=options.max_calls
    if limit==nil then limit=5 end -- Preserve the earlier standalone experiment.
    local interval=options.interval or 5
    assert(limit==false or (type(limit)=='number' and limit>=1 and limit==math.floor(limit)),'Invalid call limit')
    assert(type(interval)=='number' and interval>=1,'Invalid pacing interval')
    local self={calls=0,status='idle',running=false,last_call=-math.huge}
    function self:cancel(reason)
        if not self.running then return end -- Keep the last search result after UI/focus changes.
        self.running=false;self.status=reason or 'Cancelled';self.pending=nil
    end
    function self:start(s,difficulty,required,now)
        assert(not self.running,'Search already running')
        assert(not limit or self.calls<limit,'Session call budget exhausted')
        assert(difficulty>=1 and difficulty<=10 and difficulty==math.floor(difficulty),'Invalid difficulty')
        local n=0;local copy={}
        for i,v in pairs(required) do assert(S.options[i] and v==true,'Invalid filter');copy[i]=true;n=n+1 end
        local slots=difficulty<=2 and 1 or difficulty<=4 and 2 or 3
        assert(n>0 and n<=slots,'Select 1 to '..slots..' mission types')
        self.context=s.context;self.required=copy;self.difficulty=difficulty
        self.running=true;self.pending=nil;self.started=now
        self.match=nil;self.status='Checking existing operations'
    end
    function self:advance(s,now,invoke)
        if not self.running then return end
        if now-self.started>180 then self:cancel('Search time limit reached');return end
        if self.pending and now-self.last_call>30 then self:cancel('Refresh timed out; no retry');return end
        if not s then return end
        if s.context~=self.context then self:cancel('Context changed');return end
        if self.pending then
            if s.seed~=self.pending then self.pending=nil else return end
        end
        local op=S.find(s,self.difficulty,self.required)
        if op then self.match=op;self:cancel('Matched operation row '..op.row);return end
        if limit and self.calls>=limit then self:cancel('Session call limit reached');return end
        if now-self.last_call<interval then self.status='Waiting for pacing interval';return end
        self.calls=self.calls+1;self.last_call=now;self.pending=s.seed
        self.status='Waiting for refresh '..self.calls..(limit and '/'..limit or '')
        -- Account for the call before invoking; exceptions cannot cause an automatic retry.
        local ok,err=pcall(invoke,s)
        if not ok then self:cancel('Native call stopped: '..tostring(err));error(err) end
    end
    return self
end
return S
