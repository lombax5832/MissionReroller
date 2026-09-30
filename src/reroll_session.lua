-- One reroll run, from the dialog's request to its outcome. The dialog starts
-- and cancels runs; the pipeline (capture, comparison, search, publication)
-- reports its phase here. This is the only writer of M.status, which mirrors
-- the phase for the log, the research builds and their tests.
--
-- The session also holds the run's record: the request the dialog started it
-- with, the pending start and cancel the pipeline takes, the search's report
-- for the player, its progress in seeds and its finished job. A new run
-- begins with an empty record; the last run's stays readable until then.
--
-- A run begins at an entry phase, only moves forward through the stages and
-- ends in exactly one outcome. The pipeline calls settle() whenever no stage
-- has work left, so a run that stopped at a checkpoint still ends. A call
-- outside these rules is a bug: strict mode (tests) raises; in game it logs
-- SESSION_REJECTED, ends the run as session_failed and asks the pipeline to
-- cancel, so the dialog never waits for an outcome that will not come.
--
-- kind: idle (outside a run), progress, checkpoint (progress a run may end
-- at, with the final caption), outcome (ends a run). Captions and tones are
-- the dialog's; an outcome without a caption shows its own name.
local UNAVAILABLE='Seed prediction unavailable for this planet'
local phases={
    initializing={kind='idle'},
    ready_read_only={kind='idle'},
    requested={kind='progress',stage=0,entry=true,step=1},
    waiting_for_stable_inputs={kind='progress',stage=1,entry=true,step=1},
    capture_retry={kind='progress',stage=1,caption='Retrying changed planet data',step=1},
    identity_test_passed={kind='checkpoint',stage=2,step=1,final=UNAVAILABLE},
    identity_and_level_tests_passed={kind='checkpoint',stage=2,step=1,final=UNAVAILABLE},
    composition_test_passed={kind='checkpoint',stage=2,step=1,final=UNAVAILABLE},
    search_running={kind='progress',stage=3,caption='Searching seeds',step=2},
    search_waiting_backend={kind='progress',stage=3,caption='Waiting for game requests',step=2},
    search_matched={kind='checkpoint',stage=4,step=2,final='Match found; publication unavailable',final_tone='good'},
    publication_pending={kind='progress',stage=5,caption='Refreshing operations',step=3},
    selection_pending={kind='progress',stage=6,caption='Opening matching operation',step=4},
    publication_test_passed={kind='outcome',caption='Matching operation selected',tone='good'},
    publication_blocked={kind='outcome',caption='Map changed; reopen the planet and retry',tone='warn'},
    publication_failed={kind='outcome'},
    publication_restored={kind='outcome'},
    publication_cancelled={kind='outcome',tone='idle'},
    search_exhausted={kind='outcome',caption='No match; search again to continue',tone='warn'},
    search_failed={kind='outcome'},
    search_cancelled={kind='outcome',caption='Search cancelled',tone='idle'},
    cancelled={kind='outcome',caption='Search cancelled',tone='idle'},
    capture_timeout={kind='outcome'},
    identity_test_mismatch={kind='outcome'},
    level_test_mismatch={kind='outcome'},
    composition_test_mismatch={kind='outcome'},
    -- Ends of a run this module imposes: a rejected call, or fail().
    session_failed={kind='outcome',caption='Reroll stopped unexpectedly; see the log'},
    stopped={kind='outcome'},
}
return function(M,emit,options)
    local strict=options and options.strict
    local phase=phases[M.status] and M.status or 'initializing'
    local running,outcome,detail,run=false,nil,nil,0
    -- The run record. pending: a start the pipeline has not taken yet.
    local request,pending,cancelling,report,progress,result=nil,false,false,nil,0,nil
    local self={phases=phases}
    local function set(name,text)phase=name;detail=text;M.status=name end
    local function close(name,text)
        running=false;outcome=name;set(name,text)
    end
    -- A stopped mod accepts nothing further; a failed run keeps its outcome
    -- against the cleanup the cancellation it asked for reports.
    local function sealed()return outcome=='stopped' end
    local function reject(message)
        if strict then error('Reroll session: '..message,3)end
        emit('SESSION_REJECTED '..message)
        cancelling=true
        close('session_failed',message)
        return false
    end
    -- Progress within a run, or an idle phase outside one. An entry phase
    -- outside a run begins a new one.
    function self.advance(name,text)
        if sealed()then return false end
        local p=phases[name]
        if not p then return reject('unknown phase '..tostring(name))end
        if p.kind=='idle' then
            if running then return reject(name..' during '..phase)end
            set(name,text);return true
        end
        if p.kind=='outcome' then return reject(name..' is an outcome; finish it')end
        if not running then
            if not p.entry then return reject(name..' outside a run')end
            running=true;outcome=nil;run=run+1
            -- The last run's record must not stand for this one.
            request,pending,report,progress,result=nil,false,nil,0,nil
        elseif p.stage<phases[phase].stage then
            return reject(name..' after '..phase)
        end
        set(name,text);return true
    end
    -- The outcome of the run. Outside a run it renames the last outcome, as
    -- a later cleanup step reports it more precisely; it never reopens a run.
    function self.finish(name,text)
        if sealed()then return false end
        local p=phases[name]
        if not p then return reject('unknown outcome '..tostring(name))end
        if p.kind~='outcome' or name=='stopped' then return reject(name..' is not an outcome')end
        if not running and outcome=='session_failed' then return false end
        close(name,text);return true
    end
    -- The pipeline has no work left. A run at a checkpoint ends there; one
    -- at any other phase was abandoned by a bug and fails.
    function self.settle()
        if sealed() or not running then return false end
        if phases[phase].kind=='checkpoint' then close(phase,detail);return true end
        if strict then error('Reroll session: run abandoned at '..phase,2)end
        emit('SESSION_UNFINISHED phase='..phase)
        close('session_failed','abandoned at '..phase)
        return true
    end
    -- The mod stops: log lines and the README expect STOPPED: <reason>.
    function self.fail(reason)
        if sealed()then return false end
        running=false;outcome='stopped';phase='stopped';detail=tostring(reason)
        M.status='STOPPED: '..detail
        return true
    end
    -- The dialog's side of the handshake.
    function self.start(filters)
        if not self.advance('requested')then return false end
        request,pending=filters,true
        return true
    end
    function self.cancel()cancelling=true end
    -- The pipeline's side: each start and cancel is taken once, as true.
    -- The run's filters are view().request.
    function self.take_request()
        local asked=pending;pending=false;return asked
    end
    function self.take_cancel()
        local asked=cancelling;cancelling=false;return asked
    end
    -- The search's side of the record. report is the dialog's text for an
    -- outcome that needs more than its caption; progress counts seeds tried;
    -- result is the finished search job.
    function self.report(text)report=text end
    function self.progress(attempts)progress=attempts or 0 end
    function self.result(job)result=job end
    function self.view()
        local p=phases[phase]
        local view={phase=phase,running=running,outcome=outcome,detail=detail,run=run,
            request=request,report=report,progress=progress,result=result}
        if running then
            view.caption=p.caption or 'Checking planet data';view.tone='busy';view.step=p.step or 1
        elseif outcome=='stopped' then view.caption,view.tone=M.status,'bad'
        elseif outcome and p.kind=='checkpoint' then view.caption,view.tone=p.final,p.final_tone or 'bad'
        else view.caption,view.tone=p.caption or phase,p.tone or (outcome and 'bad' or 'idle')end
        return view
    end
    return self
end
