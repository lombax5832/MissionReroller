-- Usage: luajit test_runtime_factories.lua <src>
-- Each runtime file, and the adapter, runs as a function of its explicit
-- inputs: created with a fake host it touches no global beyond the standard
-- library and returns its entry points. The assembler wraps the files the
-- same way (build_identity_probe.factory).
local src=assert(arg[1])
local function text(file)
    local f=assert(io.open(src..'/'..file,'rb'));local s=f:read('*a');f:close();return s
end
local standard={assert=assert,error=error,ipairs=ipairs,pairs=pairs,pcall=pcall,xpcall=xpcall,next=next,
    select=select,tostring=tostring,tonumber=tonumber,type=type,unpack=unpack,rawget=rawget,
    string=string,table=table,math=math,coroutine=coroutine,debug=debug,jit=jit,require=require}
-- g stands in for _G: what a factory installs globally lands there.
local function factory(file,params,g)
    local env=setmetatable({_G=g},{__index=function(_,name)
        if standard[name]~=nil then return standard[name] end
        error(file..' reads the global '..tostring(name),2)
    end,__newindex=function(_,name)error(file..' writes the global '..tostring(name),2)end})
    local chunk=assert(loadstring('return function('..params..')\n'..text(file)..'\nend','@'..file))
    return setfenv(chunk,env)()
end
-- The adapter's inputs (build_identity_probe.ADAPTER).
local ADAPTER='core,config,make_map_screen,offsets,O,sha256,Board'
local lines={}
local binders={}
local make_reroll_session=factory('reroll_session.lua','',{})()
-- The offsets and their numbers, as the build passes them.
local offsets=dofile(src..'/offsets.lua')
local O=dofile(src..'/offset_values.lua')(offsets)
local function sha256()return '' end
local make_map_screen=factory('map_screen.lua','...',{})(O)
local Board=factory('board_records.lua','...',{})(O)
local function fake_host(config)
    local M,emit={status='initializing'},function(s)lines[#lines+1]=s end
    return {M=M,config=config,emit=emit,reroll_session=make_reroll_session(M,emit,{strict=true}),
        hex=function()return '' end,u=function()return 0 end,read=function()error('no memory')end,
        pointer=function()error('no memory')end,page=function()end,participants=function()end,
        snapshot=function()return nil,'open galactic map' end,initialize=function()end,O=O,verify_code=function()end,
        map=setmetatable({HINT_WIDGET=1696},{__index=function()return function()error('no memory')end end}),
        write=function()error('no writes')end,
        when_initialized=function(bind)binders[#binders+1]=bind end,close_log=function()end}
end
-- Library values are opaque to a factory until its functions run.
local lib=setmetatable({},{__index=function(_,name)return 'lib.'..name end})
local config={read_only=false,preview_prediction=true,version='9.9.9',banner='Mission Reroller 9.9.9 test build',
    mode='test mode',shortcut='test key',armed='test armed',search_outcome='test outcome'}
local function last()return lines[#lines]end

-- The adapter: its host, and nothing when the loader is unsupported.
local g={CowboyBingusModLoader={api=1,version=18,open_log=function()return nil end}}
local host=factory('experiment_adapter.lua',ADAPTER,g)({},config,make_map_screen,offsets,O,sha256,Board)
local M=g.MissionRerollerExperiment
assert(host and host.M==M and host.config==config and M.read_only==false and M.preview_prediction==true and M.version=='9.9.9')
for _,name in ipairs({'emit','hex','u','read','pointer','page','participants','snapshot','initialize','when_initialized','close_log'})do
    assert(type(host[name])=='function','host.'..name)
end
for _,name in ipairs({'stack','screens','on_top','ui','viewed','rows_address','processed_row','pointed_row','back_hint'})do
    assert(type(host.map[name])=='function','host.map.'..name)
end
assert(host.map.HINT_WIDGET==1696 and host.write==nil,'The adapter has no write; publishing builds add host.write')
-- The guarded write registers for the native handles and returns the write.
local write_binders={}
local write=factory('guarded_write.lua','',{})()({read=function()end,page=function()end,
    when_initialized=function(bind)write_binders[#write_binders+1]=bind end})
assert(type(write)=='function' and #write_binders==1)
assert(host.O==O and type(host.verify_code)=='function' and host.u('\1\2\0\0',0)==513)
local old={CowboyBingusModLoader={api=1,version=15}}
assert(factory('experiment_adapter.lua',ADAPTER,old)({},{read_only=true},make_map_screen,offsets,O,sha256,Board)==nil)
assert(old.MissionRerollerExperiment.status=='unsupported_loader' and old.MissionRerollerExperiment.read_only==true)
local again={MissionRerollerExperiment={}}
assert(factory('experiment_adapter.lua',ADAPTER,again)({},config,make_map_screen,offsets,O,sha256,Board)==nil,'A second copy stays inert')

-- The runtimes, created in the assembler's order.
local runtime='host,lib,hooks'
local publication=factory('live_publication_runtime.lua',runtime,{})(fake_host(config),lib,{})
for _,name in ipairs({'on_existing_match','on_search_match','advance_live_publication'})do assert(type(publication[name])=='function',name)end
assert(publication.advance_live_publication('tick',0)==false,'Nothing to publish')
local constellations=factory('constellation_runtime.lua',runtime,{})(fake_host(config),lib,{})
assert(type(constellations.bind_constellations)=='function' and type(constellations.observe_constellations)=='function')
local objectives=factory('side_objective_runtime.lua',runtime,{})(fake_host(config),lib,{})
assert(type(objectives.bind_objectives)=='function' and type(objectives.observe_objectives)=='function')
local search_hooks={}
local search=factory('prediction_search_runtime.lua',runtime,{})(fake_host(config),lib,search_hooks)
assert(last():find('; test outcome',1,true),last())
assert(type(search.on_prediction_ready)=='function' and type(search.advance_prediction_search)=='function')
assert(type(search.search_clock)=='function' and search.default_limit==1000000)
assert(search.advance_prediction_search('tick',0)==false,'No search is running')
local dialog=factory('prediction_dialog_runtime.lua',runtime,{})(fake_host(config),lib,{default_limit=search.default_limit})
for _,name in ipairs({'dialog_tick','dialog_release','validate_search_request'})do assert(type(dialog[name])=='function',name)end
-- The identity runtime wraps the globals update and shutdown and names the build.
local calls={}
local globals={update=function(...)calls[#calls+1]='update';return 1,nil,3 end,shutdown=function()calls[#calls+1]='shutdown';return 4 end}
local closed=false
local probe_host=fake_host(config);probe_host.close_log=function()closed=true end
local identity=factory('identity_probe_runtime.lua',runtime,globals)(probe_host,lib,{
    dialog_release=function(reason)calls[#calls+1]='release '..reason end})
assert(type(identity.tick)=='function')
assert(last()=='Mission Reroller 9.9.9 test build; test mode; test key; background progress enabled',last())
assert(globals.shutdown()==4 and closed and calls[1]=='release shutdown' and calls[2]=='shutdown')
-- Every runtime waits for the native handles; each factory registered once.
assert(#binders==6,#binders)
-- Without the search the capture slices on the adapter's timer.
local timed={}
for _,bind in ipairs(binders)do bind({api={time=function()timed[#timed+1]=true;return 0 end}})end
local slice_clock
for i=1,255 do
    local name,value=debug.getupvalue(identity.tick,i)
    if not name then break end
    if name=='prepare' then
        for j=1,255 do
            local inner,fn=debug.getupvalue(value,j)
            if not inner then break end
            if inner=='sliced_read' then
                for k=1,255 do local n,v=debug.getupvalue(fn,k);if not n then break end;if n=='slice_clock' then slice_clock=v end end
            end
        end
    end
end
assert(slice_clock,'slice_clock is reachable')
slice_clock();assert(#timed==1,'The fallback clock is the adapter timer')
print('Runtime factories: adapter host, unsupported loader, second copy, five runtimes with explicit inputs, config banners and clock fallback passed')
