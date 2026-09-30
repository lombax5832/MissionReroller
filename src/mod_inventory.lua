-- The Lua mods the loaders started, for the top of the log. Bingus Shared
-- Loader records each module's status but not its version, so a version is
-- whatever the mod publishes: a version field on the table its entry
-- returned, or on its global, named by convention after the entry's last
-- path segment (mods/cowboybingus/mod_bindings_menu -> ModBindingsMenu).
-- Every read is a rawget, so no mod's metatable runs.
local I={}
local FIELDS={'version','VERSION','_VERSION'}
local function version_of(t)
    if type(t)~='table' then return nil end
    for _,k in ipairs(FIELDS)do
        local v=rawget(t,k)
        if type(v)=='string' or type(v)=='number' then return tostring(v)end
    end
    return nil
end
local function flat(s)return (tostring(s):gsub('[\r\n]+',' | '))end
function I.global_name(module)
    local last=module:match('([^/]+)$') or module
    return (last:gsub('^%l',string.upper):gsub('_(%w)',string.upper))
end
-- G is the global table; returns the log lines.
function I.lines(G)
    local lines,entries,seen={},{},{}
    local package_table=rawget(G,'package')
    local loaded=type(package_table)=='table' and rawget(package_table,'loaded') or nil
    for _,source in ipairs({{'CowboyBingusModLoader','Bingus Shared Loader'},{'HD2ModLoader','HD2ModLoader'}})do
        local loader=rawget(G,source[1])
        if type(loader)=='table' then
            lines[#lines+1]=string.format('LOADER %s version=%s api=%s',source[2],
                flat(rawget(loader,'version') or 'unknown'),flat(rawget(loader,'api') or 'unknown'))
            local modules=rawget(loader,'modules')
            if type(modules)=='table' then
                for name,status in pairs(modules)do
                    if type(name)=='string' and status~='not installed' and not seen[name] then
                        seen[name]=true;entries[#entries+1]={name=name,status=flat(status)}
                    end
                end
            end
        end
    end
    table.sort(entries,function(a,b)return a.name<b.name end)
    local started=0
    for _,e in ipairs(entries)do if e.status=='loaded' then started=started+1 end end
    lines[#lines+1]=string.format('MODS started=%d other=%d',started,#entries-started)
    for _,e in ipairs(entries)do
        local version=version_of(loaded and rawget(loaded,e.name)) or version_of(rawget(G,I.global_name(e.name)))
        lines[#lines+1]=string.format('MOD %s version=%s status=%s',e.name,flat(version or 'unknown'),e.status)
    end
    return lines
end
return I
