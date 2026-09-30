-- The cursor reads must survive another addon declaring the same user32
-- functions first with its own structs, which is what a user's log showed.
local ffi=require('ffi')
ffi.load('user32')  -- the game always has it loaded; standalone LuaJIT does not
ffi.cdef[[typedef struct { int32_t x,y; } OTHER_POINT; typedef struct { int32_t l,t,r,b; } OTHER_RECT;
    int GetCursorPos(OTHER_POINT *); int ScreenToClient(void *,OTHER_POINT *); int GetClientRect(void *,OTHER_RECT *);
    void *GetDesktopWindow(void);]]
local user32=ffi.load('user32')
-- A later declaration is ignored, so a buffer of our own struct is rejected.
ffi.cdef[[typedef struct { int32_t x,y; } MINE_POINT; int GetCursorPos(MINE_POINT *);]]
local ok,err=pcall(user32.GetCursorPos,ffi.new('MINE_POINT[1]'))
assert(not ok and tostring(err):find('cannot convert',1,true),tostring(err))
local cursor=dofile(assert(arg[1]))(ffi)
local x,y,w,h=cursor.client(user32.GetDesktopWindow())
assert(type(x)=='number' and type(y)=='number' and w>0 and h>0,'client read failed')
assert(x==math.floor(x) and w==math.floor(w),'not plain numbers')
-- No window: GetClientRect fails and the read reports it instead of returning zeros.
ok,err=pcall(cursor.client,nil)
assert(not ok and tostring(err):find('Mouse position unavailable',1,true),tostring(err))
print('window cursor: passed')
