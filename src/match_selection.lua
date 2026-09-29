-- Pure selection lifecycle. Native adapter must only highlight an operation.
return function(adapter)
    local S={state='idle'}
    function S:start(snapshot,match,now)
        assert(self.state=='idle','Selection already attempted')
        local found
        for _,op in ipairs(snapshot.operations) do
            if op.row==match.row and op.seed==match.seed and op.operation_id==match.operation_id
                and op.difficulty==match.difficulty then found=op;break end
        end
        assert(found,'Matched operation is stale')
        self.state='pending';self.row=match.row;self.seed=snapshot.seed;self.context=snapshot.context
        self.started=now
        adapter.select(snapshot,found) -- Never retried if this raises or publication times out.
    end
    function S:poll(snapshot,now)
        if self.state~='pending' then return self.state end
        if now-self.started>5 then self.state='failed';self.reason='Operation selection timed out';return self.state end
        if not snapshot then return self.state end
        if snapshot.context~=self.context or snapshot.seed~=self.seed then
            self.state='failed';self.reason='Context changed during selection'
        elseif adapter.confirm(snapshot,self.row) then self.state='selected' end
        return self.state
    end
    return S
end
