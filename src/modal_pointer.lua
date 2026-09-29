-- Input ownership must be established externally before this router is opened.
-- No engine calls: acquisition/restoration contracts can be tested independently.
return function(gate)
    local M={opened=false,closing=false}
    local owned,pressed,was_down,armed=false,nil,false,false
    function M:open()
        assert(not owned,'Modal already owned')
        assert(gate:acquire()==true,'Verified input ownership unavailable')
        owned=true;self.opened=true;self.closing=false;armed=false;pressed=nil;was_down=false
    end
    function M:close()
        if not owned then return end
        self.opened=false;self.closing=true;pressed=nil
    end
    function M:step(x,y,down,targets)
        if not owned then return nil end
        assert(gate:held()==true,'Modal input ownership lost')
        if self.closing then
            -- Do not give the underlying UI the release of the closing click.
            if not down and not was_down then
                assert(gate:release()==true,'Modal input restoration failed')
                owned=false;self.closing=false
            end
            was_down=down;return nil
        end
        local hit
        for _,t in ipairs(targets) do
            if t.enabled~=false and x>=t.x and y>=t.y and x<t.x+t.w and y<t.y+t.h then
                assert(not hit,'Overlapping mouse targets');hit=t.id
            end
        end
        local action
        if not down then
            if armed and was_down and pressed and hit==pressed then action=hit end
            armed=true;pressed=nil
        elseif armed and not was_down then pressed=hit end
        was_down=down
        return action
    end
    function M:abort()
        if owned then assert(gate:release()==true,'Modal input restoration failed') end
        owned=false;self.opened=false;self.closing=false;pressed=nil
    end
    return M
end
