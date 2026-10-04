-- Usage: luajit seed_chain_bench.lua <params.lua>
-- Times the inner units of scripts/seed_chain.py as a LuaJIT port would run
-- them, after checking each against answers computed by the Python port:
-- one step of the three-gap root walk, one draw check (multiply, add,
-- shift, compare in uint64), and one fixed-basis inversion. The parameters
-- come from scripts/measure_seed_chain.py.
local ffi = require('ffi')
local bit = require('bit')
local P = dofile(arg[1])
local clock = os.clock

-- The walk carries the state's offset in the interval as a uint64; a step
-- back below zero wraps to a huge value, so "o < w" tests both bounds.
-- (The offset plus a step stays below 2^64 while the interval is narrower
-- than 2^63.)
local function walk(n, check)
  local s, off, w = P.s0, P.off0, P.width
  local q1, d1, sg1, q2, d2, sg2, q12, d12 = P.q1, P.d1, P.sign1, P.q2, P.d2, P.sign2, P.q12, P.d12
  local a6, c6, lo6, hi6 = P.a6, P.c6, P.lo6, P.hi6
  local pass = 0
  for _ = 1, n do
    if check then
      local h = tonumber(bit.rshift(a6 * (0ULL + s) + c6, 32))
      if h >= lo6 and h <= hi6 then pass = pass + 1 end
    end
    local o = sg1 > 0 and off + d1 or off - d1
    if o < w then s, off = s + q1, o
    else
      o = sg2 > 0 and off + d2 or off - d2
      if o < w then s, off = s + q2, o
      else s, off = s + q12, off + d12 end
    end
  end
  return s, pass
end

local s, pass = walk(P.steps, true)
assert(s == P.last, ('walk ends at %d, expected %d'):format(s, P.last))
assert(pass == P.passing, ('walk passes %d, expected %d'):format(pass, P.passing))

local N = 20000000
local t = clock()
walk(N, false)
local walk_ns = (clock() - t) / N * 1e9
t = clock()
walk(N, true)
local draw_ns = (clock() - t) / N * 1e9 - walk_ns

-- Inversion: every s < 2^32 with high32(a*s + c) == value, from the lattice
-- point nearest the centre of the answer square. i*us + j*vs is computed in
-- wrapping int64, which is exact for any answer below 2^32.
local a, c, us, vs = P.a, P.c, P.us, P.vs
local p, q, r, z, ri, rj = P.p, P.q, P.r, P.z, P.ri, P.rj
local floor, ceil = math.floor, math.ceil
local LIMIT = 4294967296ULL
local function invert(value, out)
  local n = 0
  local target = bit.lshift(0ULL + value, 32) - c
  local cs, ct = 2147483648, tonumber(target) + 2147483648
  local ci, cj = cs * p + ct * r, cs * q + ct * z
  for i = floor(ci - ri), ceil(ci + ri) do
    local iu = (0LL + i) * us
    for j = floor(cj - rj), ceil(cj + rj) do
      local sv = ffi.cast('uint64_t', iu + (0LL + j) * vs)
      if sv < LIMIT and tonumber(bit.rshift(a * sv + c, 32)) == value then
        n = n + 1
        out[n] = tonumber(sv)
      end
    end
  end
  return n
end

local out = {}
for k, value in ipairs(P.values) do
  local n = invert(value, out)
  local want = P.answers[k]
  local got = {}
  for i = 1, n do got[i] = out[i] end
  table.sort(got)
  assert(#got == #want, ('inversion %d: %d answers, expected %d'):format(value, #got, #want))
  for i = 1, #want do assert(got[i] == want[i], 'inversion mismatch') end
end

local M = 2000000
t = clock()
for k = 1, M do invert(P.values[k % #P.values + 1], out) end
local invert_ns = (clock() - t) / M * 1e9

print(('walk_ns=%.2f draw_ns=%.2f invert_ns=%.1f jit=%s'):format(
  walk_ns, draw_ns, invert_ns, tostring(jit.status())))
