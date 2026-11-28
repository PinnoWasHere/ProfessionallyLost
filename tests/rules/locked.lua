-- locked (decision 0007; owner, 2026-11-18: "we just have to make sure
-- that it doesn't surprise the player by changing steps within their grasp", and "needs to be more
-- efficient, but not reactionary"). Look by look (cast by cast, and in pair runs), with the
-- profession's window open, the guide's main craft rows as drawn from Plan.Current:
--   * a row locked at the last look and still locked now keeps its recipe, range and count; the
--     current one counts down by the crafts of it (once they run out, its rest is counted again);
--   * when the unlocked rows changed, the rows that changed cost at least Plan.BETTER_BY less than
--     the ones they replaced at this look's costs (Plan.RouteCost), unless those can't be done or
--     an upgrade gave them up (Plan.Dropped); the locked rows hold through an upgrade too;
--   * a plan setting turned between the two looks lifts both: it is the player asking. So does a
--     cheaper "or" row picked (Plan.Swapped, Plan.Switch).
-- Locked, read from the rows and the world's bags and bank: the current row (the first main row), the
-- earliest row from it whose recipe uses a held material (its reagents, and what a reagent the guide
-- makes is made from), and the rows that make craft-only gear a locked row uses. A row that can't be
-- done is never locked: its recipe grey in the game's window, not known and not learnable where it
-- starts, a limited pattern shown sold out, or no skill-up where it starts.
--
-- ctx: CP, line, guide, live (Plan.Current's plan), st (the run's state; each look that saw the route
-- change is counted in `st.changes`), casts (the world's casts so far, spell -> count),
-- held(item) (bags and bank).

setfenv(1, Rules.ENV)

Rules.LOCK_DEPTH = 3   -- how far a held material counts through the guide's prep makers

-- Casts of `spell` (and of the player's own spell `alias` for it) in `casts`.
-- @rule[CastsOf] independent: the world's casts, counted
function Rules.CastsOf(casts, spell, alias)
    return (casts[spell] or 0) + (alias and alias ~= spell and casts[alias] or 0)
end

-- The settings that change guide `ctx.line`'s plan (Settings.LIST `plans`) as they stand.
-- @rule[PlanSettings] self: which settings change a plan comes from the addon's Settings.LIST
function Rules.PlanSettings(ctx)
    local CP, line = ctx.CP, ctx.line
    local parts = {}
    for _, s in ipairs(CP.Settings.LIST) do
        local plans = s.plans == true or (type(s.plans) == "table" and s.plans[line])
        if plans and s.key then parts[#parts + 1] = s.key .. "=" .. tostring(CP.db[s.key] ~= false) end
    end
    return table.concat(parts, ",")
end

local function mainRows(CP, live)
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        if row.spell and row.recipe and not row.side and not (row.rank or row.train) then out[#out + 1] = row end
    end
    return out
end

local function routeOf(rows, skill)
    local parts = {}
    for _, r in ipairs(rows) do
        if r.to > skill then parts[#parts + 1] = r.spell .. ":" .. r.to end
    end
    return table.concat(parts, ";")
end

-- Every material recipe `r` reads, through the guide's prep makers.
local function materials(guide, r, out, depth)
    for _, pair in ipairs(r and r.reagents or {}) do
        out[pair[1]] = true
        local maker = guide.prep and guide.prep[pair[1]]
        if maker and depth < Rules.LOCK_DEPTH then materials(guide, guide.recipes[maker], out, depth + 1) end
    end
    return out
end

-- The world's count of every material `rows` read, as one string.
local function heldOf(ctx, guide, rows)
    local items = {}
    for _, row in ipairs(rows) do materials(guide, row.recipe, items, 0) end
    local list = {}
    for item in pairs(items) do
        local n = ctx.held(item)
        if n > 0 then list[#list + 1] = item .. "x" .. n end
    end
    table.sort(list)
    return table.concat(list, ",")
end

-- The rows of `rows` locked at `skill` with the world's bags as they are: a set of indexes.
-- ctx: CP, guide, held(item).
-- @rule[LockSet] self: a row is doable by the addon's Guide.Chance and VendorWatch.IsSoldOut
function Rules.LockSet(ctx, rows, skill, dead)
    local CP, guide = ctx.CP, ctx.guide
    local function doable(row)
        local from = math.max(row.from, skill)
        local r = row.recipe
        if not (row.learned or (r.learn or 0) <= from) then return false end
        -- A limited pattern the vendor showed sold out, as ProfLost saw it.
        if r.limited and r.pattern and not row.learned and CP.VendorWatch.IsSoldOut(r.pattern) then return false end
        return not (dead and dead[row.spell]) and CP.Guide.Chance(r, from) > 0
    end
    local out, first = {}, nil
    for i, row in ipairs(rows) do
        if row.to > skill then first = i break end
    end
    if not first then return out end
    if doable(rows[first]) then out[first] = true end
    local earliest = {}
    for i = first, #rows do
        for item in pairs(materials(guide, rows[i].recipe, {}, 0)) do earliest[item] = earliest[item] or i end
    end
    for item, i in pairs(earliest) do
        if ctx.held(item) > 0 and doable(rows[i]) then out[i] = true end
    end
    local craftOnly = guide.craftOnly or {}
    for i = #rows, first, -1 do
        for _, pair in ipairs(out[i] and rows[i].recipe.reagents or {}) do
            if craftOnly[pair[1]] then
                for j = first, i - 1 do
                    if rows[j].recipe.makes == pair[1] and doable(rows[j]) then out[j] = true end
                end
            end
        end
    end
    return out
end

local function needsKey(CP)
    local items = {}
    for item, n in pairs(CP.charDB.gatherNeeds and CP.charDB.gatherNeeds[CP.Shared.ENCHANTING] or {}) do
        items[#items + 1] = item .. "x" .. tostring(n)
    end
    table.sort(items)
    return table.concat(items, ",")
end

local function rowText(row) return ("%s %d-%d x%d"):format(row.recipe.name, row.from, row.to, row.crafts) end

-- @rule[Locked] self: route costs from Plan.RouteCost and BETTER_BY, locks from Rules.LockSet
function Rules.Locked(ctx)
    local CP, line, st, casts = ctx.CP, ctx.line, ctx.st, ctx.casts
    local function castsOf(spell, alias) return Rules.CastsOf(casts, spell, alias) end
    local out = {}
    st.changes = st.changes or 0
    local live = ctx.live
    if not (live and live.guide == ctx.guide and live.plan) then st.last = nil return out end
    local guide = live.guide
    local rows = mainRows(CP, live)
    local cur = rows[1]
    if not cur then st.last = nil return out end
    local skill = live.prof.skill
    local alias = live.alias and live.alias[cur.spell]
    local lockCtx = { CP = CP, guide = guide, held = ctx.held }
    local look = { line = line, skill = skill, rows = rows, ctx = Rules.PlanSettings(ctx),
                   dropped = CP.Plan.Dropped[line] or 0, swapped = CP.Plan.Swapped and CP.Plan.Swapped[line] or 0,
                   locks = Rules.LockSet(lockCtx, rows, skill, live.dead), held = heldOf(ctx, guide, rows),
                   needs = needsKey(CP),
                   cur = { spell = cur.spell, to = cur.to, crafts = cur.crafts }, alias = alias,
                   castsOf = castsOf(cur.spell, alias), castsAll = {} }
    for spell, n in pairs(casts) do look.castsAll[spell] = n end
    local last = st.last
    -- An upgrade that gave up the unlocked steps (Plan.Dropped) marks a route that can't be done: those
    -- steps give way whole, and the locked ones still hold. A plan the upgrade drops whole (decision 0008
    -- rule 4) is dropped before any look shows it.
    local gaveUp = last and last.dropped ~= look.dropped
    -- A cheaper "or" row picked (Plan.Switch) is the player asking, as a setting turned is.
    if last and last.line == line and last.ctx == look.ctx and last.swapped == look.swapped then
        local why = {}
        if heldOf(ctx, guide, last.rows) ~= last.held then why[#why + 1] = "the bags changed" end
        if look.needs ~= last.needs then why[#why + 1] = "Enchanting's needs changed" end
        if skill ~= last.skill then why[#why + 1] = ("the skill went %d -> %d"):format(last.skill, skill) end
        local since = #why > 0 and table.concat(why, ", ") or "nothing the check reads"
        local still = Rules.LockSet(lockCtx, last.rows, skill, live.dead)
        -- Crafts of `spell` since the last look, the player's own spell for it too.
        local function madeOf(spell)
            local own = live.alias and live.alias[spell]
            local was = (last.castsAll[spell] or 0) + (own and own ~= spell and last.castsAll[own] or 0)
            return castsOf(spell, own) - was
        end
        -- The current row now: it counts down by the crafts of it. One that was current at the last look
        -- counts down by exactly those; one that became current since by at most those, as its count
        -- starts once it is current.
        local function isNow(r) return r.spell == cur.spell and r.to == cur.to end
        local held = {}
        for i, row in ipairs(last.rows) do
            if last.locks[i] and still[i] and row.to > skill then
                local wasCur = row.spell == last.cur.spell and row.to == last.cur.to
                local made = wasCur and castsOf(last.cur.spell, last.alias) - last.castsOf or madeOf(row.spell)
                local lo, hi = row.crafts, row.crafts
                if isNow(row) then
                    lo = math.max(1, row.crafts - made)
                    hi = wasCur and lo or row.crafts
                end
                local spent = isNow(row) and made >= row.crafts
                local want = lo
                local found
                for j, now in ipairs(rows) do
                    if now.spell == row.spell and now.to == row.to and (isNow(row) or now.from == row.from)
                        and (spent or (now.crafts >= lo and now.crafts <= hi)) then
                        found = j
                    end
                end
                if found then
                    held[found] = true
                else
                    local now
                    for _, r in ipairs(rows) do
                        if not now and r.to > math.max(row.from, skill) and r.from < row.to then now = r end
                    end
                    out[#out + 1] = ("locked step %s changed (expected x%d), now %s; since the last look: %s"):format(
                        rowText(row), want, now and rowText(now) or "nothing", since)
                end
            end
        end
        -- The unlocked rows that changed, against the ones they replaced.
        local count = {}
        local function key(r)
            if isNow(r) then return ("now:%d:%d"):format(r.spell, r.to) end
            return ("%d:%d:%d:%d"):format(r.spell, math.max(r.from, skill), r.to, r.crafts)
        end
        for i, r in ipairs(last.rows) do
            if r.to > skill and not (last.locks[i] and still[i]) then count[key(r)] = (count[key(r)] or 0) + 1 end
        end
        local new, gone = {}, {}
        for j, r in ipairs(rows) do
            if not held[j] then
                local k = key(r)
                if (count[k] or 0) > 0 then count[k] = count[k] - 1 else new[#new + 1] = r end
            end
        end
        for i, r in ipairs(last.rows) do
            local k = key(r)
            if r.to > skill and not (last.locks[i] and still[i]) and (count[k] or 0) > 0 then
                count[k] = count[k] - 1
                gone[#gone + 1] = r
            end
        end
        if #new > 0 or #gone > 0 then
            st.changes = st.changes + 1
            -- The rule read here, not through Plan.Better: the old rows can't be done, cover other
            -- skill points, or cost at least BETTER_BY more.
            local was, wasPoints = CP.Plan.RouteCost(guide, gone, skill, live.costs, live.dead, live.learned)
            local now, nowPoints = CP.Plan.RouteCost(guide, new, skill, live.costs, live.dead, live.learned)
            local allowed = gaveUp or not was or wasPoints ~= nowPoints or (now and now <= was * (1 - CP.Plan.BETTER_BY))
            if not allowed then
                local a, b = {}, {}
                for _, r in ipairs(gone) do a[#a + 1] = rowText(r) end
                for _, r in ipairs(new) do b[#b + 1] = rowText(r) end
                out[#out + 1] = ("unlocked steps changed for less than %d%%: %s (%s) -> %s (%s); since the last look: %s"):format(
                    math.floor(CP.Plan.BETTER_BY * 100 + 0.5), table.concat(a, "; "), tostring(was and math.floor(was)),
                    table.concat(b, "; "), tostring(now and math.floor(now)), since)
            end
        end
    elseif last and last.line == line and routeOf(last.rows, skill) ~= routeOf(rows, skill) then
        st.changes = st.changes + 1
    end
    st.last = look
    return out
end
