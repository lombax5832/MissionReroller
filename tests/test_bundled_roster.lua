-- The bundled Know Your Constellation roster (src/bundled_roster.lua) and the
-- fallback to it in src/unit_forecast.lua.
-- Usage: luajit tests/test_bundled_roster.lua <src folder>
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local src=assert(arg[1],'usage: test_bundled_roster.lua <src folder>')
local O=H.offsets(src)
local vendor=src..'/vendor/know_your_constellation/'
local roster=assert(loadfile(vendor..'roster.lua'))()
local data=assert(loadfile(vendor..'roster_data.lua'))()
local R=assert(loadfile(src..'/bundled_roster.lua'))(O,roster,data)
local F=H.module(src..'/unit_forecast.lua')

-- The export's shape, for the game build this release supports.
assert(R.api==1 and R.build==tostring(O.build) and R.revision=='v4.0','Roster api 1 for build '..O.build)
-- Native tag IDs to the roster's: native 1 is new in build 25480438.
assert(R.from_native(0)==0 and R.from_native(1)==31 and R.from_native(2)==1 and R.from_native(31)==30)
assert(not pcall(R.from_native,32),'An unknown native tag raises')

-- The forecast is the roster's own report, with names in place of indexes.
local snapshot={faction=2,difficulty=10,tags={R.from_native(8),R.from_native(3)}}
local report=roster.compute(data,snapshot)
local forecast=R.forecast(snapshot)
assert(#forecast.large==#report.large and #forecast.small==#report.small and #forecast.large>0)
local seen={}
for i,entry in ipairs(forecast.large)do
    assert(entry.name==data.names[report.large[i][1]][1] and entry.ticks==report.large[i][2])
    assert(entry.ticks>=1 and entry.ticks<=10)
    seen[entry.name]=true
end
for i,name in ipairs(forecast.small)do assert(name==data.names[report.small[i]][1])end
assert(seen['Bile Titans'],'Terminids at difficulty 10 field Bile Titans')

-- The fallback order: the installed export, then the bundled roster.
local r,why=F.roster({},nil)
assert(r==nil and why=='not installed')
r,why=F.roster({},R)
assert(r==R and why=='bundled v4.0 build '..O.build..' (not installed)',why)
local export={api=1,build=O.build,from_native=R.from_native,forecast=R.forecast}
r,why=F.roster({EnemyIntelligence={revision='v4.1',status='ready',roster=export}},R)
assert(r==export and why=='revision v4.1 build '..O.build,'An installed export comes first')
r,why=F.roster({EnemyIntelligence={revision='v4.0',status='ready'}},R)
assert(r==R and why=='bundled v4.0 build '..O.build..' (revision v4.0 has no roster api 1)',why)
local stale=setmetatable({build='1'},{__index=R})
r,why=F.roster({},stale)
assert(r==nil and why=='not installed; bundled roster build 1 is not game build '..O.build,why)

-- A tooltip from the bundled roster, and the note alone without any roster.
local logs={}
local function emit(line)logs[#logs+1]=line end
local catalogue={forecast=function(tag)return {faction=2,difficulty=10,tags={8,tag}}end}
local item={id='constellation:2:3',title='Predator Strain',tag=3,stamped=true}
local tip=F.new(emit,{},R):tip(item,catalogue)
assert(tip.large[1].name==forecast.large[1].name and tip.credit==F.CREDIT and tip.note==F.STAMP_NOTE)
assert(logs[1]=='KYC_ROSTER ready bundled v4.0 build '..O.build..' (not installed)',logs[1])
tip=F.new(emit,{},nil):tip(item,catalogue)
assert(tip.note and not tip.large and logs[#logs]=='KYC_ROSTER off: not installed','A note-only tooltip')
print('Bundled roster: api 1, tag IDs, forecast, fallback order and tooltips passed')
