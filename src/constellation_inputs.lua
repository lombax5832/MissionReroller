-- Bounded decoders for the enemy-tag inputs of 177dd80: campaign effects and
-- global entries (11deda0, 12e1210), difficulty tables (1758000), mission
-- records (177deb0) and configuration exclusions. All reads are injected.
-- Level-owned tags (explicit descriptor tags, first placed stamp) exist only
-- after a mission preview loads; they are observed separately, never guessed.
return function(read,u,pointer,game,board,effects,config)
    local ffi=require('ffi');local scalar=ffi.new('float[1]')
    local function word(a)return u(read(a,4),0)end
    local function float(bytes,at)ffi.copy(scalar,bytes:sub(at+1,at+4),4);return tonumber(scalar[0])end
    local function tag(value)assert(value<32,'Unknown enemy tag index');return value end
    local hashes=read(game+0x21e1920,32*4);local by_hash={}
    for i=0,31 do
        local hash=u(hashes,i*4);assert(by_hash[hash]==nil,'Duplicate enemy tag hash');by_hash[hash]=i
    end
    local api={}
    local cache={settings={},mission={},campaign={},disabled={},effect={}}
    function api.settings(faction,difficulty)
        assert(faction>=2 and faction<=4,'Unsupported constellation faction')
        local key=faction..':'..difficulty;local result=cache.settings[key]
        if result then return result end
        local limit=10;local value=config.lookup(config.hash({0xaf218cac,0xfaabbea9}))
        if value and u(value,12)==6 then limit=math.min(10,u(value,16))end
        assert(limit>=1,'Unsupported zero difficulty cap')
        local effective=difficulty==0 and 1 or math.min(difficulty,limit)
        local row=read(game+0x328d2a0+(effective-1)*0x330,0x330)
        local first=({[2]=0x114,[3]=0x174,[4]=0x1d4})[faction]
        local fallback=({[2]=0x234,[3]=0x258,[4]=0x27c})[faction]
        result={draws=u(row,0x110),candidates={},blockers={},fallback=tag(u(row,fallback+32))}
        assert(result.draws<=16,'Invalid constellation draw count')
        for i=0,7 do
            local at=first+i*12
            result.candidates[i+1]={id=tag(u(row,at)),weight=float(row,at+4),only_when_empty=row:byte(at+9)~=0}
            result.blockers[i+1]=tag(u(row,fallback+i*4))
        end
        cache.settings[key]=result;return result
    end
    function api.mission(kind)
        assert(kind>=0 and kind<162 and kind==math.floor(kind),'Invalid mission metadata index')
        local result=cache.mission[kind]
        if result then return result end
        local at=game+0x3773420+kind*0x380
        result={faction=word(at+8),exclusions={},
            horde=read(at+0x34,1):byte()==2 and read(at+0x360,8)=='\x49\x78\x82\x7f\xd1\x2c\x7c\x85'}
        local list=read(at+0x14,32)
        -- Native stops at the first empty exclusion slot.
        for i=0,7 do
            local value=u(list,i*4);if value==0 then break end
            result.exclusions[#result.exclusions+1]=tag(value)
        end
        cache.mission[kind]=result;return result
    end
    function api.effect_id(category,id,planet)
        local key=category..':'..id..':'..planet;local result=cache.effect[key]
        if result then return result end
        result=4294967295
        if category<14 and read(game+0x32e98e0+category*0xa8+9,1):byte()~=0 then
            local campaign=board+0x101438
            local n=word(campaign+0x26018);assert(n<=512,'Campaign operation count exceeds capacity')
            for i=0,n-1 do
                local at=campaign+0x23018+i*24
                if word(at)==planet and word(at+4)==id then result=id;break end
            end
        end
        cache.effect[key]=result;return result
    end
    function api.campaign(planet,effect_id)
        assert(planet>=0 and planet<512 and planet==math.floor(planet),'Invalid constellation planet')
        local key=planet..':'..effect_id;local result=cache.campaign[key]
        if result then return result end
        result={}
        for _,row in ipairs(effects.collect(planet,effect_id,0x28))do
            -- Unknown hashes are skipped natively rather than rejected.
            if u(row,24)==13 and by_hash[u(row,28)]then result[#result+1]=by_hash[u(row,28)]end
        end
        local planets=word(board+0x12444c);assert(planets<=512,'Planet count exceeds capacity')
        if planet<planets then
            local dynamic=read(board+0x147458+planet*0x130,0x130)
            local faction,region=u(dynamic,0x24),u(dynamic,0x40)
            local globals=read(assert(pointer(read(game+0x346d518,8)),'Missing global effects'),32*0x164)
            for i=0,31 do
                local at=i*0x164
                local scope,value,filter=globals:byte(at+0x55),u(globals,at+0x58),u(globals,at+0x5c)
                local applies=scope==3 or (scope==0 and value==planet) or (scope==1 and value==region)
                    or (scope==2 and value==faction)
                if applies and (filter==0 or filter==faction)then
                    local n=u(globals,at+0x50);assert(n<=5,'Too many global effect entries')
                    for j=0,n-1 do
                        local entry=at+j*16
                        if globals:byte(entry+1)==0x11 and u(globals,entry+4)~=0 and #result<32 then
                            result[#result+1]=tag(u(globals,entry+4))
                        end
                    end
                end
            end
        end
        cache.campaign[key]=result;return result
    end
    function api.disabled(index)
        local result=cache.disabled[index]
        if result==nil then
            result=config.lookup(config.hash({0xe165f457,0xec4e3719,u(hashes,tag(index)*4)}))~=nil
            cache.disabled[index]=result
        end
        return result
    end
    return api
end
