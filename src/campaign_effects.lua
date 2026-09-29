-- Bounded input decoder for the ordered, deduplicated effect list in 12df110.
return function(read,u,pointer,game,board)
    local campaign=board+0x101438
    local function word(a)return u(read(a,4),0)end
    local function count(a,max)local n=word(a);assert(n<=max,'Campaign effect count exceeds capacity');return n end
    local function ptr(a)return assert(pointer(read(a,8)),'Missing campaign pointer')end
    local manager=ptr(game+0x347cd98)
    local function special_template(hash)
        local entries=pointer(read(board+0x1f8908,8));if not entries then return nil end
        local n=count(board+0x1f8918,4096);if n==0 then return nil end
        local ids=ptr(board+0x1f8910)
        for i=0,n-1 do if word(ids+i*4)==hash then return pointer(read(entries+i*8,8))end end
    end
    local function binding(planet,id)
        for i=0,count(campaign+0x26018,512)-1 do
            local row=campaign+0x23018+i*24
            if word(row)==planet and word(row+4)==id then return special_template(word(row+8))end
        end
    end
    local function collect(planet,operation,class)
        local session=ptr(game+0x347cef0);local root=ptr(game+0x3326340)
        if read(session+0x167e6,1):byte()~=0 or read(root+0x108d,1):byte()~=0 or read(root+0x1099,1):byte()~=0 then return {}end
        local total=count(manager+0xd000,1024)
        local selected,seen={},{}
        local function add(id)
            if seen[id] or #selected>=128 then return end
            for i=0,total-1 do
                local row=manager+i*52
                if word(row)==id then
                    if class==0 or word(row+4)==class then
                        selected[#selected+1]=read(row,52);seen[id]=true
                    end
                    return
                end
            end
        end
        if planet~=4294967295 then
            assert(planet>=0 and planet<512,'Invalid effect planet')
            for i=0,count(campaign+0x78d14,4)-1 do
                local row=campaign+0x78c68+i*44
                if word(row)==planet then
                    for j=0,count(row+36,8)-1 do add(word(row+4+j*4))end
                end
            end
            local stats=campaign+planet*0x130
            for i=0,count(stats+0x46168,32)-1 do add(word(stats+0x460e8+i*4))end
            local definition=campaign+planet*0x118
            for i=0,count(definition+0xc8,4)-1 do add(word(definition+0xb8+i*4))end
            if operation~=4294967295 then
                local template=binding(planet,operation)
                if template then
                    local n=count(template+0x60,1024)
                    if n>0 then
                        local ids=ptr(template+0x58)
                        for i=0,n-1 do
                            local hash=word(ids+i*4)
                            for j=0,total-1 do
                                local row=manager+j*52
                                if word(row+8)==hash then add(word(row));break end
                            end
                        end
                    end
                end
            end
        end
        for i=0,count(campaign+0x77a58,8)-1 do
            local event=campaign+0x72c58+i*0x9c0
            local n=count(event+0x9b0,32);local applies=n==0
            if not applies and planet~=4294967295 then
                for j=0,n-1 do if word(event+0x930+j*4)==planet then applies=true;break end end
            end
            if applies then for j=0,count(event+0x92c,3)-1 do add(word(event+0x920+j*4))end end
        end
        return selected
    end
    return {collect=collect,binding=binding}
end
