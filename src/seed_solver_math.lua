-- Exact 1-D solving on the generator's LCG (src/generation_rng.lua), for
-- solving campaign seeds instead of searching them
-- (docs/SEED_SOLVER_RESEARCH.md, port of scripts/seed_chain.py). A start s
-- below 2^32 reaches the state A[p]*s + C[p] mod 2^64 after p draws, whose
-- output is the high half. Loops use only wrapping 64-bit arithmetic; the
-- 128-bit Euclid (first) runs once per walk or job setup.
local ffi,bit=require('ffi'),require('bit')
local R={}
local M32=2^32
local TOP=0x8000000000000000ULL -- 2^63
local MAX_POSITION=128
-- A[p], C[p]: the state after p draws is A[p]*state0 + C[p].
local A,C={[0]=1ULL},{[0]=0ULL}
for p=1,MAX_POSITION do
    A[p]=A[p-1]*6364136223846793005ULL
    C[p]=C[p-1]*6364136223846793005ULL+1442695040888963407ULL
end
R.A,R.C,R.MAX_POSITION=A,C,MAX_POSITION
local function u64(n)return 0ULL+n end
-- The position-th output (1-based) of the stream started at a 32-bit state.
function R.output(state0,position)
    return tonumber(bit.rshift(A[position]*u64(state0)+C[position],32))
end

-- (high, low) of a*b, 64 by 64 bits.
local MASK=0xffffffffULL
local function mul(a,b)
    local a1,a0,b1,b0=bit.rshift(a,32),bit.band(a,MASK),bit.rshift(b,32),bit.band(b,MASK)
    local middle=bit.rshift(a0*b0,32)+bit.band(a1*b0,MASK)+bit.band(a0*b1,MASK)
    return a1*b1+bit.rshift(a1*b0,32)+bit.rshift(a0*b1,32)+bit.rshift(middle,32),a*b
end
-- floor((high*2^64 + low)/d) for high < d: restoring long division.
local function divide(high,low,d)
    local q,r=0ULL,high
    for i=63,0,-1 do
        local carry=bit.rshift(r,63)
        r=bit.bor(bit.lshift(r,1),bit.band(bit.rshift(low,i),1ULL))
        if carry~=0ULL or r>=d then r=r-d;q=bit.bor(q,bit.lshift(1ULL,i))end
    end
    return q
end
R.mul,R.divide=mul,divide

-- Least x >= 0 with lo <= a*x mod m <= hi (0 <= lo <= hi < m), or nil. All
-- uint64; m == 0 stands for 2^64. Euclid-like: when [lo, hi] holds no
-- multiple of a, the wrap count of a*x obeys the same kind of condition
-- modulo a (seed_solver.py _first).
local function first(a,m,lo,hi)
    if m~=0ULL then a=a%m end
    if lo==0ULL then return 0ULL end
    if a==0ULL then return nil end
    -- 2a > m: (m-a)x = -ax keeps the modulus halving.
    if (m==0ULL and a>TOP) or (m~=0ULL and a>m-a) then return first(m-a,m,m-hi,m-lo)end
    local k=lo/a;if lo%a~=0ULL then k=k+1ULL end
    if k<=hi/a then return k end
    local s=lo%a
    local rest=m==0ULL and (0ULL-a)%a or m%a -- m mod a
    local y=first((a-rest)%a,a,s,s+(hi-lo))
    if y==nil then return nil end
    -- ceil((lo + m*y)/a), below 2^64 since the answer is below m.
    local high,low
    if m==0ULL then high,low=y,0ULL else high,low=mul(m,y)end
    local add=lo+(a-1ULL)
    if add<lo then high=high+1ULL end -- carry out of lo + a - 1
    local sum=low+add
    if sum<low then high=high+1ULL end
    return divide(high,sum,a)
end
R.first=first

-- Every start s whose position-th output lies in [lo, hi] (32-bit outputs),
-- ascending. By the three-gap theorem consecutive solutions differ by q1,
-- q2 or q1+q2, where q1 moves the state forward by less than the interval's
-- width W and q2 back by less than W; the next solution is the nearer of
-- the first two that stays inside, else their sum. The walk carries the
-- state's offset in the interval as a uint64.
function R.walk(position,lo,hi)
    assert(position>=1 and position<=MAX_POSITION and lo>=0 and lo<=hi and hi<M32,'Invalid walk')
    local a,c=A[position],C[position]
    local base=bit.lshift(u64(lo),32)
    local count=hi-lo+1
    local w={}
    if count==M32 then
        -- Every start: the walk steps by one.
        function w.start(s)return s,a*u64(s)+c end
        function w.advance(s,off)return s+1,off+a end
        return w
    end
    local width=bit.lshift(u64(count),32)
    local q1=first(a,0ULL,1ULL,width-1ULL)
    local q2=first(a,0ULL,0ULL-width+1ULL,0ULL-1ULL)
    local d1,d2=a*q1,0ULL-a*q2 -- forward by d1, back by d2
    local qa,da,fa,qb,db,fb=q1,d1,true,q2,d2,false
    if q2<q1 then qa,da,fa,qb,db,fb=q2,d2,false,q1,d1,true end
    local na,nb,n12,d12=tonumber(qa),tonumber(qb),tonumber(q1+q2),d1-d2
    local function move(off,d,forward)
        if forward then
            local o=off+d
            if o>=off and o<width then return o end
        elseif off>=d then return off-d end
    end
    -- The first solution at or after s, with its offset, or nil.
    function w.start(s)
        local left=base-c-a*u64(s) -- a*t mod 2^64 in [left, left + width)
        local t=0ULL
        if left~=0ULL and left<=0ULL-width then t=first(a,0ULL,left,left+(width-1ULL))end
        if t==nil then return nil end
        local at=s+tonumber(t)
        return at,a*u64(at)+c-base
    end
    function w.advance(s,off)
        local o=move(off,da,fa)
        if o then return s+na,o end
        o=move(off,db,fb)
        if o then return s+nb,o end
        return s+n12,off+d12
    end
    return w
end

-- The 32-bit starts whose position-th output equals a value. They lie in a
-- 2^32 by 2^32 square of the lattice {(s, A*s mod 2^64)}, of determinant
-- 2^64: a reduced basis, fixed per position, puts a few basis combinations
-- around the square's centre over every answer. Floating point finds the
-- combinations; wrapping int64 arithmetic gives s exactly when it is an
-- answer, and every candidate is checked in uint64.
local inverters={}
local function signed(x)return ffi.cast('int64_t',x)end
local function reduce(a)
    -- A lattice vector is (s, t) with t = A*s - j*2^64 small; t is tracked
    -- as int64, exact while the true value is below 2^63 in size.
    local us,ut=1LL,signed(a)
    local k=math.floor(M32*M32/tonumber(ut)+0.5)
    local vs=-ffi.new('int64_t',k)
    local vt=signed(a*ffi.cast('uint64_t',vs))
    local function norm(s,t)local x,y=tonumber(s),tonumber(t);return x*x+y*y end
    for _=1,200 do -- Gauss (Lagrange) reduction, rounding in floating point
        if norm(us,ut)>norm(vs,vt)then us,ut,vs,vt=vs,vt,us,ut end
        local q=math.floor((tonumber(us)*tonumber(vs)+tonumber(ut)*tonumber(vt))/norm(us,ut)+0.5)
        if q==0 then break end
        local kq=ffi.new('int64_t',q)
        vs,vt=vs-kq*us,vt-kq*ut
        if norm(vs,vt)>=norm(us,ut)then break end
    end
    return us,ut,vs,vt
end
function R.inverter(position)
    if inverters[position]then return inverters[position]end
    assert(position>=1 and position<=MAX_POSITION,'Invalid inversion position')
    local a,c=A[position],C[position]
    local us,ut,vs,vt=reduce(a)
    local fus,fut,fvs,fvt=tonumber(us),tonumber(ut),tonumber(vs),tonumber(vt)
    local det=fus*fvt-fut*fvs
    local p,q,r,z=fvt/det,-fut/det,-fvs/det,fus/det -- (s, t) -> (i, j)
    local half=M32/2
    local ri=math.abs(p)*half+math.abs(r)*half+1
    local rj=math.abs(q)*half+math.abs(z)*half+1
    local floor,ceil=math.floor,math.ceil
    local LIMIT=bit.lshift(1ULL,32)
    -- Fills out[1..n] with the answers (unordered) and returns n.
    local function invert(value,out)
        local n=0
        local target=bit.lshift(u64(value),32)-c
        local cs,ct=half,tonumber(target)+half
        local ci,cj=cs*p+ct*r,cs*q+ct*z
        for i=floor(ci-ri),ceil(ci+ri)do
            local iu=ffi.new('int64_t',i)*us
            for j=floor(cj-rj),ceil(cj+rj)do
                local s=ffi.cast('uint64_t',iu+ffi.new('int64_t',j)*vs)
                if s<LIMIT and tonumber(bit.rshift(a*s+c,32))==value then
                    n=n+1;out[n]=tonumber(s)
                end
            end
        end
        return n
    end
    inverters[position]=invert
    return invert
end
return R
