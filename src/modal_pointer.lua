-- Input ownership must be established externally before this router is opened.
-- No engine calls: acquisition/restoration contracts can be tested independently.
return function(gate)
    local M={opened=false,closing=false}
    -- Each button keeps its own press. A press with both buttons down is
    -- dropped until both are up.
    local owned,armed,chord=false,false,false
    local buttons={{},{}}
    local function reset()for _,b in ipairs(buttons)do b.pressed,b.was_down=nil,false end end
    function M:open()
        assert(not owned,'Modal already owned')
        assert(gate:acquire()==true,'Verified input ownership unavailable')
        owned=true;self.opened=true;self.closing=false;armed=false;chord=false;reset()
    end
    function M:close()
        if not owned then return end
        self.opened=false;self.closing=true
        for _,b in ipairs(buttons)do b.pressed=nil end
    end
    -- down and right: whether the left and right buttons are down. Returns
    -- the target clicked, and true when the right button clicked it; the
    -- right button clicks only cycle targets.
    function M:step(x,y,down,targets,right)
        if not owned then return nil end
        assert(gate:held()==true,'Modal input ownership lost')
        right=right==true
        local up=not down and not right
        if self.closing then
            -- Do not give the underlying UI the release of the closing click.
            if up and not buttons[1].was_down and not buttons[2].was_down then
                assert(gate:release()==true,'Modal input restoration failed')
                owned=false;self.closing=false
            end
            buttons[1].was_down,buttons[2].was_down=down,right;return nil
        end
        local hit,cycle
        for _,t in ipairs(targets) do
            if t.enabled~=false and x>=t.x and y>=t.y and x<t.x+t.w and y<t.y+t.h then
                assert(not hit,'Overlapping mouse targets');hit,cycle=t.id,t.cycle
            end
        end
        if down and right then chord=true end
        local action,reverse
        for n,b in ipairs(buttons)do
            local held=n==1 and down or n==2 and right
            if not held then
                if armed and not chord and b.was_down and b.pressed and hit==b.pressed then action,reverse=hit,n==2 end
                b.pressed=nil
            elseif armed and not b.was_down and (n==1 or cycle) then b.pressed=hit end
            b.was_down=held
        end
        if up then armed=true;chord=false end
        return action,reverse
    end
    function M:abort()
        if owned then assert(gate:release()==true,'Modal input restoration failed') end
        owned=false;self.opened=false;self.closing=false;reset()
    end
    return M
end
