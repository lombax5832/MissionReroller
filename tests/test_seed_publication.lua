local make=assert(loadfile(arg[1]))()
local function fixture()
    local calls={};local a={}
    function a.preflight(s,e)calls[#calls+1]='guard' end
    function a.publish(s,seed)calls[#calls+1]='publish';assert(seed==22) end
    function a.restore(s,seed)calls[#calls+1]='restore';assert(s.seed==11 and seed==22) end
    function a.matches(s,e)calls[#calls+1]='verify';return s.good end
    return make(a,{seed=22}),a,calls
end
local before={seed=11,context='same'}
local candidate={seed=22,context='same',good=true}
local s,a,c=fixture();s:start(before,0)
assert(s:poll(nil,1)=='pending' and s:poll(before,2)=='pending')
assert(s:poll(candidate,3)=='verified');s:commit()
assert(s.state=='committed' and not s.before and table.concat(c,',')=='guard,publish,verify')
assert(not pcall(function()s:start(before,4)end),'Must not repeat publication')
s,a,c=fixture();s:start(before,0)
assert(s:poll({seed=22,context='same',good=false},1)=='restored')
assert(table.concat(c,',')=='guard,publish,verify,restore')
for _,reason in ipairs({'timeout','context','external'})do
    s,a,c=fixture();s:start(before,0)
    if reason=='timeout' then s:poll(nil,31)
    elseif reason=='context' then s:poll({seed=22,context='other'},1)
    else s:poll({seed=33,context='same'},1) end
    assert(s.state=='restored' and c[#c]=='restore')
end
s,a,c=fixture();a.preflight=function()error('guard blocked')end
assert(not pcall(function()s:start(before,0)end) and not s.used and not s.before and #c==0)
s,a,c=fixture();a.publish=function()error('partial publication')end
assert(not pcall(function()s:start(before,0)end) and s.used and s.before)
s:restore('error cleanup');assert(s.state=='restored')
s,a,c=fixture();s:start(before,0);a.restore=function()error('stale owner')end
assert(not pcall(function()s:restore('cancel')end) and s.before and s.state=='restoring')
print('seed publication: success, mismatch, timeout, context, guard, partial-write recovery, stale restore passed')
