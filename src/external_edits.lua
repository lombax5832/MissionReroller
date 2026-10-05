-- Operations another mod rewrote on a planet without changing the campaign
-- seed, such as Refresh Operations' F6 (docs/EXTERNAL_EDITS.md). A reroll
-- regenerates every unstarted operation from the new seed, so such a row
-- plays no part in the search. The comparisons leave a row out only once it
-- is proven to be an edit and not a gap in the generator port; the check
-- after publication still compares the whole regenerated board.
--
-- Proof, per differing row, which must be an unstarted operation that kept
-- its difficulty:
-- * baseline: the planet was seen under the same campaign seed with this row
--   equal to the prediction, so the row changed after generation;
-- * later_rows: only the operation seed differs and a later row matches.
--   Every row draws its seed the same way, and a port error in the draws
--   would carry into the rows after it.
local _,Board=...
local E={}
-- id, seed and difficulty of each displayed row of a 110-row operation buffer.
function E.rows(operations)
    local rows={}
    for row=0,109 do
        if Board.valid(operations,row)then
            rows[row]={id=Board.operation_id(operations,row),seed=Board.seed(operations,row),difficulty=Board.difficulty(operations,row)}
        end
    end
    return rows
end
local PLANETS=64
-- Keeps the first board seen per planet under a campaign seed. A later board
-- under the same seed never replaces it, so an edit cannot become its own
-- proof. Returns true when it stored a new board.
function E.observe(store,planet,seed,operations)
    local known=store[planet]
    if known and known.seed==seed then return false end
    if not known then
        local count=0
        for _ in pairs(store)do count=count+1 end
        if count>=PLANETS then for key in pairs(store)do store[key]=nil end end
    end
    store[planet]={seed=seed,rows=E.rows(operations)}
    return true
end
-- Whether the planet's board under this seed is already stored.
function E.known(store,planet,seed)
    local known=store[planet]
    return known~=nil and known.seed==seed
end
local function same(a,b)return a.id==b.id and a.seed==b.seed and a.difficulty==b.difficulty end
-- The edits behind a failed identity comparison (identity_probe.lua compare),
-- as {rows={[row]={observed,predicted,evidence}},count=n}, or nil and why the
-- difference is not one.
function E.classify(result,store,planet,seed)
    if result.passed then return nil,'identity passed'end
    local differences=result.differences or {}
    if #differences==0 or (result.matched or 0)==0 then return nil,'no matching rows'end
    local last=-1
    for _,row in ipairs(result.matched_rows or {})do if row>last then last=row end end
    local known=store and store[planet]
    if known and known.seed~=seed then known=nil end
    local rows,count={},0
    for _,d in ipairs(differences)do
        local where='row='..d.row..' '
        if d.kind~='value' then return nil,where..d.kind end
        local o,p=d.observed,d.predicted
        if p.preserved then return nil,where..'operation in progress differs'end
        if o.difficulty~=p.difficulty then return nil,where..'difficulty differs'end
        local before=known and known.rows[d.row]
        local evidence
        if before and same(before,p) then evidence='baseline'
        elseif o.id==p.id and last>d.row then evidence='later_rows'
        else
            return nil,where..(o.id~=p.id and 'operation type differs' or 'no matching row after it')..' and the planet was not seen before the change'
        end
        rows[d.row]={observed=o,predicted=p,evidence=evidence};count=count+1
    end
    return {rows=rows,count=count}
end
-- A composition result (composition_capture.lua) passes when every failed row
-- is an edit. rows is classify's rows table, or nil.
function E.composition_passes(result,rows)
    if result.passed then return true end
    if not rows or (result.general or 1)>0 or (result.checked or 0)==0 then return false end
    for row in pairs(result.failed_rows or {})do if not rows[row] then return false end end
    return true
end
-- operations without the edited rows, for checks on the live board.
function E.without(operations,rows)
    if not rows then return operations end
    local kept={}
    for _,op in ipairs(operations)do if not rows[op.row] then kept[#kept+1]=op end end
    return kept
end
return E
