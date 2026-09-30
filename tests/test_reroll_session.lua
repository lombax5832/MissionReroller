-- Usage: luajit test_reroll_session.lua <src/reroll_session.lua>
local make=dofile(arg[1])
local function new(strict)
    local M,logs={status='initializing'},{}
    return make(M,function(line)logs[#logs+1]=line end,{strict=strict}),M,logs
end
local function refused(fn,...)
    local ok,err=pcall(fn,...)
    assert(not ok and tostring(err):find('Reroll session',1,true),tostring(err))
end

-- The vocabulary is closed and complete: every phase has a kind, every
-- running phase a stage and a step, every checkpoint a final caption.
local session=new(true)
for name,p in pairs(session.phases)do
    assert(({idle=1,progress=1,checkpoint=1,outcome=1})[p.kind],name)
    if p.kind=='progress' or p.kind=='checkpoint' then assert(p.stage and p.step,name)end
    if p.kind=='checkpoint' then assert(p.final,name)end
end

-- A whole run, request to selection. M.status mirrors every phase.
local session,M=new(true)
assert(session.advance('ready_read_only') and M.status=='ready_read_only' and not session.view().running)
local request={difficulty=10,required={[2]=true}}
M.search_attempts=99;M.search_report='No match in 256 seeds'
assert(session.start(request) and M.request_search and M.search_options==request and M.search_attempts==0 and not M.search_report)
local view=session.view()
assert(view.running and view.phase=='requested' and view.caption=='Checking planet data' and view.tone=='busy' and view.step==1 and view.run==1)
for _,case in ipairs({{'waiting_for_stable_inputs','Checking planet data',1},{'capture_retry','Retrying changed planet data',1},
    {'waiting_for_stable_inputs','Checking planet data',1},{'identity_test_passed','Checking planet data',1},
    {'identity_and_level_tests_passed','Checking planet data',1},{'composition_test_passed','Checking planet data',1},
    {'search_running','Searching seeds',2},{'search_waiting_backend','Waiting for game requests',2},{'search_running','Searching seeds',2},
    {'search_matched','Checking planet data',2},{'publication_pending','Refreshing operations',3},{'selection_pending','Opening matching operation',4}})do
    assert(session.advance(case[1],'detail') and M.status==case[1],case[1])
    view=session.view()
    assert(view.running and view.caption==case[2] and view.step==case[3] and view.tone=='busy' and view.detail=='detail' and not view.outcome,case[1])
end
M.search_attempts=2731;assert(session.view().progress==2731)
assert(session.finish('publication_test_passed') and M.status=='publication_test_passed')
view=session.view()
assert(not view.running and view.outcome=='publication_test_passed' and view.caption=='Matching operation selected' and view.tone=='good' and view.step==nil)
-- The captions and tones the dialog showed before the session owned them.
for name,expected in pairs({search_exhausted={'No match; search again to continue','warn'},search_cancelled={'Search cancelled','idle'},
    cancelled={'Search cancelled','idle'},publication_blocked={'Map changed; reopen the planet and retry','warn'},
    publication_cancelled={'publication_cancelled','idle'},capture_timeout={'capture_timeout','bad'},search_failed={'search_failed','bad'},
    publication_failed={'publication_failed','bad'},identity_test_mismatch={'identity_test_mismatch','bad'}})do
    local s=new(true);s.advance('waiting_for_stable_inputs');s.finish(name)
    view=s.view();assert(view.caption==expected[1] and view.tone==expected[2],name)
end

-- Transitions. A run begins only at an entry phase and only moves forward;
-- outcomes and progress are not interchangeable; unknown names are refused.
session,M=new(true)
refused(session.advance,'search_running')
refused(session.advance,'no_such_phase')
refused(session.finish,'no_such_outcome')
assert(session.advance('waiting_for_stable_inputs'))
refused(session.advance,'ready_read_only')
refused(session.advance,'cancelled')
refused(session.finish,'search_running')
refused(session.finish,'stopped')
refused(session.start,{})
assert(session.advance('search_running'))
refused(session.advance,'waiting_for_stable_inputs')
refused(session.advance,'composition_test_passed')
assert(session.advance('selection_pending'),'A stage may be skipped, as an existing match skips the search')
assert(session.finish('publication_blocked'))
refused(session.advance,'publication_pending')
assert(session.advance('waiting_for_stable_inputs') and session.view().run==2,'A new run begins at an entry phase')

-- Terminal guarantee. When the pipeline has no work left, a run at a
-- checkpoint ends there, keeping M.status for the log and research builds.
session,M=new(true)
session.start({});session.advance('waiting_for_stable_inputs');session.advance('composition_test_passed')
assert(session.view().running and session.settle())
view=session.view()
assert(not view.running and view.outcome=='composition_test_passed' and M.status=='composition_test_passed')
assert(view.caption=='Seed prediction unavailable for this planet' and view.tone=='bad')
assert(not session.settle(),'Settling outside a run does nothing')
session.advance('waiting_for_stable_inputs');session.advance('search_matched');session.settle()
view=session.view();assert(view.outcome=='search_matched' and view.tone=='good')
-- Any other phase means a stage was abandoned: a bug, refused in tests.
session.advance('waiting_for_stable_inputs');session.advance('search_running')
local ok,err=pcall(session.settle);assert(not ok and err:find('abandoned at search_running',1,true),err)

-- In game nothing is raised: the call is logged, the run fails and the
-- pipeline is asked to cancel, so the dialog never waits forever.
local logs
session,M,logs=new(false)
session.start({});session.advance('waiting_for_stable_inputs')
assert(not session.advance('mystery_phase') and #logs==1 and logs[1]=='SESSION_REJECTED unknown phase mystery_phase')
view=session.view()
assert(not view.running and view.outcome=='session_failed' and M.status=='session_failed' and M.cancel_requested)
assert(view.caption=='Reroll stopped unexpectedly; see the log' and view.tone=='bad')
assert(not session.finish('cancelled') and session.view().outcome=='session_failed','The cancellation it asked for keeps the failure')
M.cancel_requested=nil
assert(not session.advance('search_running') and logs[2]=='SESSION_REJECTED search_running outside a run')
M.cancel_requested=nil
assert(session.start({}) and session.view().running,'The next run starts normally')
session.advance('publication_pending');assert(not session.advance('search_running') and logs[3]=='SESSION_REJECTED search_running after publication_pending')
session.start({});session.advance('search_running')
assert(session.settle() and logs[4]=='SESSION_UNFINISHED phase=search_running' and session.view().outcome=='session_failed')

-- Cancel: the dialog asks, the pipeline answers. A later cleanup step
-- names the outcome more precisely but never reopens the run.
session,M=new(true)
session.start({});session.advance('waiting_for_stable_inputs');session.advance('search_running')
session.cancel();assert(M.cancel_requested and session.view().running,'Only the pipeline ends the run')
assert(session.finish('search_cancelled') and session.finish('cancelled'))
view=session.view();assert(not view.running and view.outcome=='cancelled' and view.caption=='Search cancelled' and view.tone=='idle')

-- A stopped mod: STOPPED: <reason> as the log and README expect, and
-- nothing afterwards changes it.
session,M=new(true)
session.start({});session.advance('waiting_for_stable_inputs')
assert(session.fail('Generator signature mismatch') and M.status=='STOPPED: Generator signature mismatch')
view=session.view();assert(not view.running and view.outcome=='stopped' and view.caption==M.status and view.tone=='bad')
assert(not session.finish('publication_cancelled') and not session.advance('waiting_for_stable_inputs') and not session.settle())
assert(not session.start({}) and M.status=='STOPPED: Generator signature mismatch')
print('Reroll session: vocabulary, captions, whole run, transitions, settle at checkpoints, in-game rejection, cancel and stop passed')
