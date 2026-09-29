local make=assert(loadfile(arg[1]))()
local response,cancelled,requested
local job=make({id=function(n)return 'session-'..n end,
 request=function(id,s,d,r)requested={id=id,difficulty=d,required=r}end,
 cancel=function(id)cancelled=id end,poll=function()return response end})
local s={context='planet/active/owner',seed=7};local filters={[1]=true,[2]=true}
job:start(s,10,filters,0);filters[1]=nil
assert(requested.required[1] and requested.required[2])
response={id='old',status='found'};assert(not job:poll(s,1) and job.state=='searching')
response={id=job.id,status='found'};assert(not job:poll(nil,2))
assert(job:poll(s,3)==response and job.state=='ready')
job:start(s,10,{[1]=true},4);local id=job.id;job:cancel()
response={id=id,status='found'};assert(not job:poll(s,5) and cancelled==id)
job:start(s,10,{[1]=true},6);job:poll({context='other',seed=7},7);assert(job.state=='cancelled')
job:start(s,10,{[1]=true},8);job:poll({context=s.context,seed=8},9);assert(job.state=='cancelled')
job:start(s,10,{[1]=true},10);job:poll(nil,191);assert(job.state=='cancelled')
assert(not pcall(function()job:start(s,2,{[1]=true,[2]=true},192)end))
print('prediction job: copied AND filters, stale response, fresh context, cancellation, changed seed and timeout passed')
