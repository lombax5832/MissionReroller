-- Asynchronous prediction lifecycle, independent of the evaluator/transport.
-- Only a result belonging to the current request and unchanged context is usable.
return function(engine)
    local self={state='idle',serial=0,status='Choose filters',attempts=0}
    function self:cancel(reason)
        if self.state~='searching' then return end
        self.state='cancelled';self.status=reason or 'Cancelled'
        engine.cancel(self.id)
    end
    function self:start(snapshot,difficulty,required,now)
        assert(self.state~='searching','Prediction already running')
        assert(difficulty>=1 and difficulty<=10 and difficulty==math.floor(difficulty),'Invalid difficulty')
        local copy={};local count=0
        for i,v in pairs(required)do assert(type(i)=='number' and i>=1 and i<=12 and i==math.floor(i) and v==true,'Invalid filter');copy[i]=true;count=count+1 end
        local slots=difficulty<=2 and 1 or difficulty<=4 and 2 or 3
        assert(count>=1 and count<=slots,'Select 1 to '..slots..' mission types')
        self.serial=self.serial+1;self.id=engine.id(self.serial)
        self.context=snapshot.context;self.seed=snapshot.seed;self.started=now
        self.state='searching';self.status='Predicting operations';self.attempts=0;self.result=nil
        local ok,err=pcall(engine.request,self.id,snapshot,difficulty,copy)
        if not ok then self:cancel('Prediction request failed');error(err)end
    end
    function self:poll(snapshot,now)
        if self.state~='searching' then return end
        if now-self.started>180 then self:cancel('Prediction timed out');return end
        if snapshot and (snapshot.context~=self.context or snapshot.seed~=self.seed) then
            self:cancel('Planet or operation state changed');return
        end
        local result=engine.poll(self.id)
        if not result or result.id~=self.id then return end
        self.attempts=result.attempts or self.attempts
        if result.status=='working' then return end
        if result.status~='found' then
            self.state='failed';self.status=result.message or 'No matching prediction';return
        end
        if not snapshot then return end -- Require a fresh usable context at handoff.
        self.result=result;self.state='ready';self.status='Prediction ready'
        return result
    end
    return self
end
