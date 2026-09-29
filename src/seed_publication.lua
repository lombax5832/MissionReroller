-- One-shot transaction. The adapter guards every write and owns restoration.
return function(adapter,expected)
    local self={state='idle',used=false}
    function self:restore(reason)
        if not self.before then return end
        self.state='restoring'
        adapter.restore(self.before,expected.seed)
        self.before=nil;self.state='restored';self.reason=reason
    end
    function self:start(s,now)
        assert(not self.used,'Publication already attempted this session')
        adapter.preflight(s,expected)
        self.used=true;self.before=s;self.started=now;self.state='pending'
        adapter.publish(s,expected.seed)
    end
    function self:poll(s,now)
        if self.state~='pending' then return self.state end
        if now-self.started>30 then self:restore('Publication timed out');return self.state end
        if not s then return self.state end
        if s.context~=self.before.context then self:restore('Context changed');return self.state end
        if s.seed==self.before.seed then return self.state end
        if s.seed~=expected.seed then self:restore('Seed changed externally');return self.state end
        if not adapter.matches(s,expected) then self:restore('Prediction mismatch');return self.state end
        self.state='verified';return self.state
    end
    function self:commit()
        assert(self.state=='verified','Publication not verified')
        self.before=nil;self.state='committed'
    end
    return self
end
