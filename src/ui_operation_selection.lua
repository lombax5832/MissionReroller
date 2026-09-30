-- Mirror the two local UI fields set immediately before the native operation
-- selector in the normal click handler. No mission or active operation writes.
-- adapter.map is the map screen (src/map_screen.lua); the two fields are its
-- operation-row words.
return function(adapter)
    local self={}
    local map=adapter.map
    local function u32(bytes)local a,b,c,d=bytes:byte(1,4);return a+b*256+c*65536+d*16777216 end
    function self:apply(planet,difficulty,row)
        assert(row>=0 and row<110 and row==math.floor(row),'Invalid UI operation row')
        adapter.signature()
        local ui=map.ui()
        local shown_planet,shown_difficulty=map.viewed(ui)
        assert(shown_planet==planet,'Map UI planet differs')
        assert(shown_difficulty==difficulty,'Map UI difficulty differs')
        local rows=map.rows_address(ui)
        adapter.page(rows,8)
        self.ui=ui;self.rows=rows;self.before=adapter.read(rows,8)
        self.value=adapter.word(row)..adapter.word(4294967295)
        adapter.write(rows,self.value)
        assert(adapter.read(rows,8)==self.value,'Map UI selection write failed')
    end
    function self:confirmed(row)
        return self.ui and map.ui()==self.ui
            and u32(adapter.read(self.rows,4))==row
            and map.processed_row(self.ui)==row
    end
    function self:restore()
        if not self.before then return end
        -- Never overwrite a later user selection or a different UI instance.
        if map.ui()==self.ui and adapter.read(self.rows,8)==self.value then
            adapter.page(self.rows,8);adapter.write(self.rows,self.before)
        end
        self.before=nil
    end
    function self:commit()self.before=nil end
    return self
end
