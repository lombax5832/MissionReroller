-- Mirror the two local UI fields set immediately before the native operation
-- selector in the normal click handler. No mission or active operation writes.
return function(adapter)
    local self={}
    function self:apply(planet,difficulty,row)
        assert(row>=0 and row<110 and row==math.floor(row),'Invalid UI operation row')
        adapter.signature()
        local ui=adapter.root()
        assert(adapter.u32(adapter.read(ui+0x4ef8,4))==planet,'Map UI planet differs')
        assert(adapter.u32(adapter.read(ui+0x4f14,4))==difficulty,'Map UI difficulty differs')
        adapter.page(ui+0x4f00,8)
        self.ui=ui;self.before=adapter.read(ui+0x4f00,8)
        self.value=adapter.word(row)..adapter.word(4294967295)
        adapter.write(ui+0x4f00,self.value)
        assert(adapter.read(ui+0x4f00,8)==self.value,'Map UI selection write failed')
    end
    function self:confirmed(row)
        return self.ui and adapter.root()==self.ui
            and adapter.u32(adapter.read(self.ui+0x4f00,4))==row
            and adapter.u32(adapter.read(self.ui+0x4f98,4))==row
    end
    function self:restore()
        if not self.before then return end
        -- Never overwrite a later user selection or a different UI instance.
        if adapter.root()==self.ui and adapter.read(self.ui+0x4f00,8)==self.value then
            adapter.page(self.ui+0x4f00,8);adapter.write(self.ui+0x4f00,self.before)
        end
        self.before=nil
    end
    function self:commit()self.before=nil end
    return self
end
