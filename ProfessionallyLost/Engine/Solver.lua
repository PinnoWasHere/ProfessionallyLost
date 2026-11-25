local _, CP = ...
if CP.stopped then return end

-- Re-plans the guide from the player's skill with live prices. For each skill point
-- it picks the recipe with the lowest expected cost per point: craft cost divided by
-- the chance of a skill-up. A cheap yellow recipe can beat an expensive orange one.
-- Green is a last resort: a point goes to a green recipe only when no orange or yellow
-- one covers it, gap fillers included. In order: allowed recipes, then gap fillers
-- (trainer, last-resort, dropped patterns), each orange or yellow; then the same two
-- tiers green. Grey gives nothing and is never planned. The previous pick is kept while within STICKY of the best, so the plan doesn't
-- flip between near-equal recipes. Pure logic, so it runs headless.

local Solver = {}
CP.Solver = Solver

local STICKY = 1.15
local MAX_SKILL = 300  -- the top skill in Forever; recipes stay non-grey past it
local UNKNOWN_PRICE = 50000  -- copper; materials with no price are steered around
local UNAVAILABLE = 1e8      -- copper; a cooldown-made material (Mooncloth) with no auction price

-- What the planner pays for `item`: its price, else a stand-in that steers around it.
local function priced(priceFn, guide, item)
    local gi = guide.items and guide.items[item]
    local p = priceFn(item, gi)
    if p then return p end
    return gi and gi.cooldown and UNAVAILABLE or UNKNOWN_PRICE
end
Solver.MIN_RUN = 3           -- a shorter run joins a neighbouring step that can carry it
Solver.MAX_RESOLVES = 3      -- extra solves at most, each dropping coupled recipes that ended with no step

-- True when `r` is green at skill `s`: from the yellow-grey midpoint to grey, where a
-- craft rarely gives a point (Prof.DifficultyAt's green).
local function isGreen(r, s) return s >= CP.Professions.GreenFrom(r) end
Solver.IsGreen = isGreen

-- The skill where `r` turns green.
function Solver.GreenFrom(r) return CP.Professions.GreenFrom(r) end

-- Orange or yellow first, then green, each from materials the player can get; a material
-- no one can get (a cooldown-made one with no auction price) only when nothing else gives
-- the point.
local TIERS = { { green = false }, { green = true }, { any = true } }
local NO_TIERS = {}

local function inTier(tier, r, s) return tier.any or isGreen(r, s) == tier.green end
local function affordable(tier, c)
    if c and (tier.any or c < UNAVAILABLE) then return c end
    return nil
end

-- Cost of one craft, and whether any material had no price.
function Solver.CraftCost(guide, recipe, priceFn)
    local total, missing = 0, false
    for _, pair in ipairs(recipe.reagents) do
        local price = priceFn(pair[1], guide.items and guide.items[pair[1]])
        if not price then
            price, missing = priced(priceFn, guide, pair[1]), true
        end
        total = total + price * pair[2]
    end
    return total, missing
end

-- True when every material of `a` is also a material of `b`.
local function usesOnly(a, b)
    local has = {}
    for _, pair in ipairs(b.reagents) do has[pair[1]] = true end
    for _, pair in ipairs(a.reagents) do
        if not has[pair[1]] then return false end
    end
    return true
end

-- The settle pass. A maker is a recipe whose product a
-- later step uses: a prep material (bolts, powders, grinding stones) or craft-only gear. Every craft
-- of it those steps need is made anyway, so it is made as early as it gives points, and the points
-- count. Off only for the simulator's self-test.
Solver.SETTLE = true

-- Expected crafts of `r` from skill `from` to `to`, with fractions.
local function craftsBetween(r, from, to)
    local total = 0
    for s = from, to - 1 do
        local p = CP.Guide.Chance(r, s) * (r.ups or 1)
        if p <= 0 then return math.huge end
        total = total + 1 / p
    end
    return total
end

-- The skill `crafts` of `r` take the player to from `from`, point by point with fractions. It stops
-- at grey.
function Solver.Play(r, from, crafts)
    local x, left = from, crafts
    while left > 1e-9 do
        local s = math.floor(x)
        local p = CP.Guide.Chance(r, s) * (r.ups or 1)
        if p <= 0 then break end
        local step = (s + 1 - x) / p
        if left >= step then
            left, x = left - step, s + 1
        else
            x, left = x + left * p, 0
        end
    end
    return x
end

-- Grows each maker's run in `picks` to the end its whole count reaches, played from its start. The
-- count is what later runs use of its product, less the bags. Makers settle lowest start first, and a
-- run only grows. A fixed point, the held current step and a pick that makes craft-only gear are
-- never overwritten; the maker's rest settles again past such a block. `usable(id)` says whether
-- the player can craft maker `id`.
local function settle(guide, skill, cap, picks, learned, usable, held, opts, holdId, holdEnd)
    local G = CP.Guide
    local fixed = opts and opts.fixed or {}
    local cuts = opts and opts.cuts or {}
    local craftOnly, prep = guide.craftOnly or {}, guide.prep or {}
    held = held or {}

    local function runsOf()
        local runs, s = {}, skill
        while s < cap do
            local id, from = picks[s], s
            while s < cap and picks[s] == id and not (s > from and cuts[s]) do s = s + 1 end
            if id then runs[#runs + 1] = { id = id, from = from, to = s } end
        end
        return runs
    end

    -- Each maker's product per craft of recipe `id`, cached.
    local uses = {}
    local function usesOf(id, item)
        local key = id .. ":" .. item
        if uses[key] == nil then
            uses[key] = false
            for _, pair in ipairs(guide.recipes[id].reagents) do
                if pair[1] == item then uses[key] = pair[2] end
            end
        end
        return uses[key]
    end

    -- The makers whose product a pick uses, with their start in today's picks.
    local runs = runsOf()
    local makers, seen = {}, {}
    local function add(item, id)
        if seen[id] or not guide.recipes[id] then return end
        local start, used
        for _, run in ipairs(runs) do
            if run.id == id and not start then start = run.from end
            if run.id ~= id and usesOf(run.id, item) then used = used or run.from end
        end
        if not used then return end
        if not start and craftOnly[item] then return end
        seen[id] = true
        makers[#makers + 1] = { item = item, id = id, start = start or used }
    end
    for item, id in pairs(prep) do add(item, id) end
    for _, run in ipairs(runs) do
        local r = guide.recipes[run.id]
        if r.makes and craftOnly[r.makes] then add(r.makes, run.id) end
    end
    table.sort(makers, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        return a.id < b.id
    end)

    local floor = skill
    for _, m in ipairs(makers) do
        runs = runsOf()
        local M = guide.recipes[m.id]
        local s0, firstEnd
        for _, run in ipairs(runs) do
            if run.id == m.id and run.to > floor then
                s0, firstEnd = math.max(run.from, floor), run.to
                break
            end
        end
        if not s0 and not craftOnly[m.item] then
            for _, run in ipairs(runs) do
                if run.to > floor and run.id ~= m.id and usesOf(run.id, m.item) then
                    s0 = math.max(run.from, floor)
                    if not learned[m.id] then s0 = math.max(s0, M.learn) end
                    firstEnd = s0
                    break
                end
            end
        end
        local top = math.min(M.grey, cap)
        local ok = s0 and s0 < top and usable(m.id) and (learned[m.id] or M.learn <= s0)
            and G.Chance(M, s0) > 0
        if ok then
            -- Held rare materials cap what can be made (Level-as-you-go's hides).
            local rareCap
            if opts and opts.rareFromStock then
                for _, raw in ipairs(M.reagents) do
                    local info = guide.items and guide.items[raw[1]]
                    if info and info[5] == true then
                        local n = (held[raw[1]] or 0) / raw[2]
                        rareCap = math.min(rareCap or n, n)
                    end
                end
            end
            -- Runs before the maker's start use the stock first.
            local stock = held[m.item] or 0
            for _, run in ipairs(runs) do
                local k = run.id ~= m.id and run.to <= s0 and usesOf(run.id, m.item)
                if k then
                    local c = G.Crafts(guide.recipes[run.id], run.from, run.to)
                    if c < math.huge then stock = math.max(0, stock - c * k) end
                end
            end
            local function need(E)
                local n = 0
                for _, run in ipairs(runs) do
                    local k = run.id ~= m.id and run.to > E and usesOf(run.id, m.item)
                    if k then
                        local c = G.Crafts(guide.recipes[run.id], math.max(run.from, E), run.to)
                        if c < math.huge then n = n + c * k end
                    end
                end
                n = math.max(0, n - stock) / (M.yield or 1)
                if rareCap then n = math.min(n, rareCap) end
                return n
            end
            local function blocked(s)
                local id = picks[s]
                if id == m.id then return false end
                if fixed[s] then return true end
                if holdId and s < holdEnd then return true end
                -- A pick that only uses gear may shrink: the gear it no longer uses stays spare.
                local r = id and guide.recipes[id]
                return r and r.makes and craftOnly[r.makes] and true or false
            end
            local start, lo, done = s0, firstEnd, 0
            while start < top do
                local bestE, bestD
                for E = math.max(lo, start), top do
                    local played = Solver.Play(M, start, need(E) - done)
                    local d = math.abs(played - E)
                    if not bestD or d <= bestD then bestE, bestD = E, d end
                    if played < E - 1 then break end
                end
                local s = start
                while s < bestE and not blocked(s) do
                    picks[s] = m.id
                    s = s + 1
                end
                floor = math.max(floor, s)
                if s >= bestE then break end
                -- Blocked: the rest settles again from the block's end.
                local made = craftsBetween(M, start, s)
                if made == math.huge then break end
                done = done + made
                local b = s
                while b < top and blocked(b) do b = b + 1 end
                if b >= top or G.Chance(M, b) <= 0 then break end
                start, lo = b, b
            end
        end
    end
end

-- A step makes first what stock and earlier steps leave short of a prep material no earlier step
-- makes (GuideTab.MakeShort). While that maker still gives points at the step's start, the step's
-- count is the one whose crafts, played after the maker's, end closest to the step's end. Ties keep
-- the larger count. A locked step keeps its count.
local function madeFirst(guide, steps, held, fixed)
    local prep = guide.prep or {}
    local have, makes = {}, {}
    for item in pairs(prep) do have[item] = held and held[item] or 0 end

    local function ended(r, st, crafts)
        local x = st.from
        for _, pair in ipairs(r.reagents) do
            local item = pair[1]
            local M = prep[item] and not makes[item] and guide.recipes[prep[item]]
            local short = M and pair[2] * crafts - have[item] or 0
            if short > 0 and CP.Guide.Chance(M, math.floor(x)) > 0 then
                x = Solver.Play(M, x, math.ceil(short / (M.yield or 1)))
            end
        end
        return Solver.Play(r, x, crafts), x
    end

    for _, st in ipairs(steps) do
        local r = st.spell and guide.recipes[st.spell]
        if r then
            local x0 = select(2, ended(r, st, st.crafts))
            if x0 > st.from and not fixed[st.from] and st.crafts < math.huge then
                local best, bestD = st.crafts, math.abs(ended(r, st, st.crafts) - st.to)
                for c = st.crafts - 1, 1, -1 do
                    local d = math.abs(ended(r, st, c) - st.to)
                    if d >= bestD then break end
                    best, bestD = c, d
                end
                if best < st.crafts then
                    st.cost = st.cost * best / st.crafts
                    st.crafts = best
                end
            end
            for _, pair in ipairs(r.reagents) do
                if have[pair[1]] then have[pair[1]] = math.max(0, have[pair[1]] - pair[2] * st.crafts) end
            end
            if r.makes and prep[r.makes] then makes[r.makes] = true end
        end
    end
end

-- Steps from `skill` to the guide's end: { spell, from, to, crafts, cost }.
-- `learned` is a set of known recipe ids; known recipes are usable whatever their
-- learn level, others from their learn level on. `allow(id, recipe)`, when given,
-- drops recipes the player can't use (Sourcing.Filter). Every point goes to the
-- recipe that costs least per expected skill-up at `priceFn`'s prices; what the
-- player owns only lowers the shopping list, never the pick, so crafting or buying
-- materials doesn't reshuffle the guide. `prefer`, when given, is the last plan as
-- skill -> recipe id; its pick stays while within STICKY of the best. A material in
-- `guide.craftOnly` comes only from earlier steps: a recipe needing it is usable only
-- while what earlier picks made, plus `held` (craft-only item -> count in the
-- player's bags), covers it (no Fine Leather Belts made, no Dark Leather Belt).
-- `opts.rareFromStock` (Level-as-you-go) limits rare byproducts (guide item field 5,
-- hides) to what `held` has, so curing covers the hides on hand and other recipes
-- the rest; the next re-plan adds curing back as more hides turn up.
-- `opts.credit(id, recipe, cost)`, when given, returns a craft's cost after what its
-- output saves another guide (greens disenchanted for Enchanting).
-- `opts.plain` = { allow, price, touched(id, recipe), causes(id, recipe) }, when given, is the character
-- without the professions that change this guide: the filter and prices it would have.
-- When a step's recipe is `touched` (another profession let it in, cheapened it, or
-- credits it), the steps' field `plain` holds the plan without any of that, from the
-- same call, so rows can say which steps another profession changed.
-- `opts.fees` (Buy-and-power-level, where costs are gold) adds an unlearned
-- recipe's trainer fee, spread over the points it can give from here.
-- `opts.fillGaps` lets a recipe `allow` drops cover the points no allowed recipe can.
-- `opts.lastResort(id, recipe)` marks gap fillers tried only after the rest (fish recipes).
-- `opts.locked(id, recipe)` marks unlearned recipes the player can't get at all (a
-- pattern sold only at a standing they lack): never planned, not even to fill gaps.
-- `opts.fixed` (skill -> recipe id) holds the player's locked steps: those points take that
-- recipe whatever it costs, no later pass moves them, and the free points plan around them.
-- `opts.cuts` (a set of skills) starts a new step at each, so a locked step keeps its own range.
-- `opts.maker(id, recipe)`, when given, lets in a maker `allow` drops: one the player can craft
-- though its own materials fall outside the filter (the settle pass).
local function solve(guide, skill, learned, priceFn, allow, prefer, held, opts, credit, skip)
    local G = CP.Guide

    -- Each item is priced once per solve. Prices can't change while it runs, and the memo
    -- dies with it.
    local asked, rawPrice = {}, priceFn
    priceFn = function(item, info)
        local p = asked[item]
        if p == nil then
            p = rawPrice(item, info) or false
            asked[item] = p
        end
        return p or nil
    end

    local ids, spare, cost, prices, cap = {}, {}, {}, {}, 0
    local locked = opts and opts.locked
    for id, r in pairs(guide.recipes) do
        local allowed = not (skip and skip[id]) and (not allow or allow(id, r))
        local gettable = learned[id] or not (locked and locked(id, r))
        -- Gap fillers: guide recipes the filter drops, and any trainer recipe.
        local trainer = r.src == "trainer" or r.src == "auto"
        if opts and opts.fillGaps and gettable
            and ((r.step or learned[id]) and not allowed or not (r.step or learned[id]) and trainer) then
            spare[#spare + 1] = id
            cost[id] = Solver.CraftCost(guide, r, priceFn)
        end
        if (r.step or learned[id]) and allowed and gettable then
            ids[#ids + 1] = id
            cost[id] = Solver.CraftCost(guide, r, priceFn)
            if credit then cost[id] = credit(id, r, cost[id]) end
            for _, pair in ipairs(r.reagents) do
                if prices[pair[1]] == nil then
                    prices[pair[1]] = priced(priceFn, guide, pair[1])
                end
            end
            if r.grey > cap then cap = r.grey end
        end
    end
    table.sort(ids)
    table.sort(spare)
    for _, id in ipairs(spare) do
        if guide.recipes[id].grey > cap then cap = guide.recipes[id].grey end
    end
    cap = math.min(cap, MAX_SKILL)

    local craftOnly, prep = guide.craftOnly or {}, guide.prep or {}

    -- Rare byproducts limited to what is held: Level-as-you-go's hides, built once per solve.
    local rareSet = {}
    if opts and opts.rareFromStock then
        for item, it in pairs(guide.items or {}) do
            if it[5] == true then rareSet[item] = true end
        end
    end
    local function rare(item) return rareSet[item] end

    local function priceOf(item)
        if prices[item] == nil then
            prices[item] = priced(priceFn, guide, item)
        end
        return prices[item]
    end

    -- Limited supplies on hand: crafted gear, prep and rare materials the player holds,
    -- plus what earlier picks make, minus what later picks use.
    local made, stock = {}, {}
    for item, n in pairs(held or {}) do
        if craftOnly[item] or prep[item] or rare(item) then made[item] = n end
        if prep[item] then stock[item] = n end
    end

    -- The current step: the last plan's recipe at `skill`, through the end of its run.
    -- Prep in the bags is free only after it, so bolts made for later steps don't hand
    -- the step to the cloak they feed. Once the player has gained a point on it (its run
    -- starts below `skill`), a known current step holds to its end while it still gives a
    -- point from materials the player can get, whatever the costs say now. The step it
    -- ends in is picked afresh. A held first step keeps its start as `since`, so the saved
    -- plan says it is under way.
    local usable, allowed = {}, {}
    for _, id in ipairs(ids) do usable[id], allowed[id] = true, true end
    for _, id in ipairs(spare) do usable[id] = true end
    -- A maker the player can craft: one the filter lets in, else one `opts.maker` passes.
    local maker = opts and opts.maker
    local function makerUsable(id)
        if not (allowed[id] or maker and maker(id, guide.recipes[id])) then return false end
        if cost[id] == nil then
            cost[id] = Solver.CraftCost(guide, guide.recipes[id], priceFn)
            if credit then cost[id] = credit(id, guide.recipes[id], cost[id]) end
        end
        return true
    end
    local holdId, holdEnd = prefer and prefer[skill], skill
    if holdId then
        while prefer[holdEnd] == holdId do holdEnd = holdEnd + 1 end
    end
    local reserveEnd = holdEnd
    local since = skill
    while holdId and prefer[since - 1] == holdId do since = since - 1 end
    if not (holdId and learned[holdId] and usable[holdId] and since < skill) then
        holdId, holdEnd = nil, skill
    end

    -- Cost of making `count` of a prep material (a Cured Heavy Hide) at skill `s`, or
    -- nil when its recipe isn't usable yet or the rare materials on hand fall short.
    local function prepCost(item, s, count)
        local maker = guide.recipes[prep[item]]
        if not maker or not (learned[prep[item]] or maker.learn <= s) then return nil end
        local runs, total = count / (maker.yield or 1), 0
        for _, pair in ipairs(maker.reagents) do
            if rare(pair[1]) and (made[pair[1]] or 0) + 1e-9 < pair[2] * runs then return nil end
            total = total + pair[2] * runs * priceOf(pair[1])
        end
        return total
    end

    -- Cost of one expected skill point at skill `s`: the craft's materials over the
    -- skill-up chance. Craft-only gear is already paid for by the step that made it
    -- (nil when earlier steps haven't made enough). Prep materials in the player's bags
    -- are free past the current step; the rest cost what making them takes, even when an
    -- earlier pick made them, so a bolt and the cloak that uses it don't trade points one by one.
    local function pointCost(r, p, s)
        local total = 0
        for _, pair in ipairs(r.reagents) do
            local item, use = pair[1], pair[2] / p
            if craftOnly[item] then
                if (made[item] or 0) + 1e-9 < use then return nil end
            elseif prep[item] then
                local short = use - (s < reserveEnd and 0 or (stock[item] or 0))
                if short > 0 then
                    local c = prepCost(item, s, short)
                    if not c then return nil end
                    total = total + c
                end
            elseif rareSet[item] then
                if (made[item] or 0) + 1e-9 < use then return nil end
                total = total + use * (prices[item] or priceOf(item))
            else
                total = total + use * (prices[item] or priceOf(item))
            end
        end
        -- What the output saves another guide, per craft, spread over the expected point.
        if credit then return credit(nil, r, total * p) / p end
        return total
    end

    -- A trainer fee per point: the fee over the points the recipe gives from `s`.
    local fees = opts and opts.fees
    local function feeShare(id, r, s)
        if not fees or learned[id] or not r.fee or r.fee <= 0 then return 0 end
        return r.fee / math.max(1, r.grey - math.max(s, r.learn))
    end

    local fixed = opts and opts.fixed or {}
    local cuts = opts and opts.cuts or {}
    for s, id in pairs(fixed) do
        if s >= cap and s < MAX_SKILL then cap = s + 1 end
        local r = guide.recipes[id]
        if r and cost[id] == nil then
            cost[id] = Solver.CraftCost(guide, r, priceFn)
            if credit then cost[id] = credit(id, r, cost[id]) end
        end
    end

    local picks, prev = {}, nil
    local boost = G.boost
    for s = skill, cap - 1 do
        local holdP
        if holdId and s < holdEnd then
            local r = guide.recipes[holdId]
            local p = G.Chance(r, s) * (r.ups or 1)
            holdP = p > 0 and pointCost(r, p, s) and p
            -- Blocked: the plan picks afresh from here.
            if not holdP then holdEnd = s end
        end
        -- The pick to hold on to: the last plan's at this skill, else the one before.
        local anchor = (prefer and prefer[s]) or prev
        local best, bestCost, bestP, anchorCost
        local lastResort = opts and opts.lastResort
        if holdP then best, bestP = holdId, holdP end
        local fix = fixed[s] and guide.recipes[fixed[s]]
        local fixP = fix and G.Chance(fix, s) * (fix.ups or 1)
        if fixP and fixP > 0 then
            best, bestP, holdP = fixed[s], fixP, fixP
            anchor = nil
        end
        for _, tier in ipairs(holdP and NO_TIERS or TIERS) do
            for _, id in ipairs(ids) do
                local r = guide.recipes[id]
                if (learned[id] or r.learn <= s) and inTier(tier, r, s) then
                    -- Guide.Chance, inline: this loop runs per skill point per recipe.
                    local grey = r.grey
                    local p = s >= grey and 0 or s < r.yellow and 1 or (grey - s) / (grey - r.yellow)
                    if boost ~= 1 and p > 0 then p = math.min(1, p * boost) end
                    p = p * (r.ups or 1)
                    if p > 0 then
                        local c = pointCost(r, p, s)
                        if c then c = affordable(tier, c + feeShare(id, r, s)) end
                        -- Ties go to the recipe already known, then to the surer skill-up.
                        local known = learned[id] == true
                        if c and (not bestCost or c < bestCost
                            or (c == bestCost and known and not learned[best])
                            or (c == bestCost and known == (learned[best] == true) and p > bestP)) then
                            best, bestCost, bestP = id, c, p
                        end
                        if c and id == anchor then anchorCost = c end
                    end
                end
            end
            -- Nothing allowed gives a point here: the cheapest spare recipe fills the gap,
            -- a last-resort one (fish) only after the rest, an unlearned dropped pattern last.
            for pass = 1, 3 do
                if best then break end
                for _, id in ipairs(spare) do
                    local r = guide.recipes[id]
                    local rank = r.src == "pattern" and not learned[id] and 3
                        or lastResort and lastResort(id, r) and 2 or 1
                    if rank == pass and (learned[id] or r.learn <= s) and inTier(tier, r, s) then
                        local p = G.Chance(r, s) * (r.ups or 1)
                        local c = p > 0 and affordable(tier, pointCost(r, p, s))
                        if c and (not bestCost or c < bestCost) then best, bestCost, bestP = id, c, p end
                    end
                end
            end
            if best then break end
        end
        -- Hold the anchor while it is within STICKY of the best, except that a recipe
        -- unlocking here, or a cheaper one from the same materials (Heavy Wool over
        -- Wool Bandage), takes over at once.
        local unlocked = best and not learned[best] and guide.recipes[best].learn == s and s > skill
        local upgrade = anchorCost and best ~= anchor and usesOnly(guide.recipes[best], guide.recipes[anchor])
        -- A recipe the player knows takes over at once from a held one still to learn
        -- (Brilliant Smallfish, known, over Slitherskin Mackerel's pattern) when it costs no more.
        local known = anchorCost and best and learned[best] and not learned[anchor]
        if anchorCost and best ~= anchor and bestCost <= anchorCost and (unlocked or upgrade or known) then
            anchorCost = nil
        end
        if anchorCost and anchorCost <= bestCost * STICKY then
            best, bestP = anchor, G.Chance(guide.recipes[anchor], s) * (guide.recipes[anchor].ups or 1)
        end
        if best then
            local r = guide.recipes[best]
            for _, pair in ipairs(r.reagents) do
                local item, use = pair[1], pair[2] / bestP
                if prep[item] then
                    -- What stock doesn't cover gets made now, spending its rare materials.
                    local short = use - (made[item] or 0)
                    local maker = guide.recipes[prep[item]]
                    if short > 0 and maker then
                        for _, raw in ipairs(maker.reagents) do
                            if rare(raw[1]) then
                                made[raw[1]] = math.max(0, (made[raw[1]] or 0) - raw[2] * short / (maker.yield or 1))
                            end
                        end
                    end
                end
                if craftOnly[item] or prep[item] or rare(item) then
                    made[item] = math.max(0, (made[item] or 0) - use)
                end
                if stock[item] then stock[item] = math.max(0, stock[item] - use) end
            end
            if r.makes and (craftOnly[r.makes] or prep[r.makes]) then
                made[r.makes] = (made[r.makes] or 0) + (r.yield or 1) / bestP
            end
        end
        picks[s] = best or false
        prev = best
    end

    -- Every recipe the point-by-point pass picked, before later passes move points.
    local picked = {}
    for s = skill, cap - 1 do
        if picks[s] then picked[picks[s]] = true end
    end

    if Solver.SETTLE ~= false then settle(guide, skill, cap, picks, learned, makerUsable, held, opts, holdId, holdEnd) end

    -- A run of one recipe between two runs of another (Cloak, then Armor while the
    -- hides last, then Cloak again) is cheapest point by point, but asks the player
    -- to switch crafts twice. Move the middle run to the front or back of the outer
    -- recipe's span when that costs no more than STICKY over the split plan.
    -- A move that turns a point green that `old` kept orange or yellow never pays.
    local function spanCost(list, from, old)
        local total = 0
        for i, id in ipairs(list) do
            local r, s = guide.recipes[id], from + i - 1
            local p = id and (learned[id] or r.learn <= s) and G.Chance(r, s) * (r.ups or 1) or 0
            if p <= 0 then return math.huge end
            if old and isGreen(r, s) and not isGreen(guide.recipes[old[i]], s) then return math.huge end
            total = total + cost[id] / p
        end
        return total
    end
    -- Recipes tied to other steps (making or using craft-only gear or prep) keep their
    -- order: a Dark Leather Belt can't move ahead of the Fine Leather Belts it uses.
    local function chained(id)
        local r = guide.recipes[id]
        if r.makes and (craftOnly[r.makes] or prep[r.makes]) then return true end
        for _, pair in ipairs(r.reagents) do
            if craftOnly[pair[1]] then return true end
        end
        return false
    end
    local s0 = skill
    while s0 < cap do
        local a = picks[s0]
        local e1 = s0
        while e1 < cap and picks[e1] == a do e1 = e1 + 1 end
        local b = picks[e1]
        local e2 = e1
        while e2 < cap and picks[e2] == b do e2 = e2 + 1 end
        local e3 = e2
        while e3 < cap and picks[e3] == a do e3 = e3 + 1 end
        local held = false
        for s = s0, e3 - 1 do
            if fixed[s] then held = true break end
        end
        if a and b and e3 > e2 and not chained(a) and not chained(b) and not held then
            local old, front, back = {}, {}, {}
            for s = s0, e3 - 1 do old[#old + 1] = picks[s] end
            local outer, inner = (e1 - s0) + (e3 - e2), e2 - e1
            for i = 1, inner do front[i] = b end
            for i = 1, outer do front[inner + i] = a; back[i] = a end
            for i = 1, inner do back[outer + i] = b end
            local was = spanCost(old, s0)
            -- The held current step stays first.
            local holding = s0 == skill and holdEnd > skill
            local f = holding and math.huge or spanCost(front, s0, old)
            local k = spanCost(back, s0, old)
            local pick = f <= k and front or back
            if math.min(f, k) <= was * STICKY then
                for i, id in ipairs(pick) do picks[s0 + i - 1] = id end
            end
        end
        s0 = e1 > s0 and e1 or s0 + 1
    end

    -- A run of one or two points (Scorpid Surprise for 64-65) joins the step before it,
    -- else the step after, when that recipe still gives points there: nobody buys a
    -- pattern or farms a rare drop for one craft.
    -- A neighbour carries a short run only where it is no greener than the run's own pick.
    local function carries(id, from, to)
        local r = id and guide.recipes[id]
        if not (r and usable[id]) or chained(id) then return false end
        local own = guide.recipes[picks[from]]
        for k = from, to - 1 do
            if not (learned[id] or r.learn <= k) or G.Chance(r, k) <= 0 then return false end
            if isGreen(r, k) and not isGreen(own, k) then return false end
        end
        return true
    end
    local s1 = skill
    while s1 < cap do
        local id, e = picks[s1], s1
        while e < cap and picks[e] == id and not (e > s1 and cuts[e]) and (fixed[e] ~= nil) == (fixed[s1] ~= nil) do e = e + 1 end
        -- Chained recipes (making or using craft-only gear or prep) keep their runs, and
        -- so do the held current step and the locked steps.
        local holding = (s1 == skill and holdEnd > skill) or fixed[s1] ~= nil
        if id and e - s1 < Solver.MIN_RUN and not chained(id) and not holding then
            local before, after = s1 > skill and picks[s1 - 1] or nil, e < cap and picks[e] or nil
            local into = (carries(before, s1, e) and before) or (carries(after, s1, e) and after) or nil
            if into then
                for k = s1, e - 1 do picks[k] = into end
            end
        end
        s1 = e
    end

    local steps, s = {}, skill
    while s < cap do
        local spell, from = picks[s], s
        while s < cap and picks[s] == spell and not (s > from and cuts[s]) do s = s + 1 end
        if spell then
            local crafts = G.Crafts(guide.recipes[spell], from, s)
            steps[#steps + 1] = { spell = spell, from = from, to = s, crafts = crafts, cost = cost[spell] * crafts,
                                  since = from == skill and spell == holdId and holdEnd > skill and since or nil }
        else
            steps[#steps + 1] = { spell = nil, from = from, to = s, crafts = 0, cost = 0 }
        end
    end
    if Solver.SETTLE ~= false then madeFirst(guide, steps, held, fixed) end
    -- Guide.SplitAtCaps reads it to place the trainer visits.
    steps.learned = learned
    return steps, cost, picked
end

function Solver.Plan(guide, skill, learned, priceFn, allow, prefer, held, opts)
    local credit = opts and opts.credit
    local steps, cost, picked = solve(guide, skill, learned, priceFn, allow, prefer, held, opts, credit)
    local plain = opts and opts.plain
    if not plain then return steps, cost end
    -- A coupled recipe that won points and then lost them all to later passes moved the plan
    -- but shows no row. When no shown step names a profession behind it, solve again without it,
    -- so a profession changes the plan only through rows that can name it.
    local causes, dropped = plain.causes, nil
    for _ = 1, Solver.MAX_RESOLVES do
        local shown, named = {}, {}
        for _, st in ipairs(steps) do
            if st.spell and not shown[st.spell] then
                shown[st.spell] = true
                for _, line in ipairs(causes(st.spell, guide.recipes[st.spell])) do named[line] = true end
            end
        end
        local gone = false
        for id in pairs(picked) do
            if not shown[id] then
                for _, line in ipairs(causes(id, guide.recipes[id])) do
                    if not named[line] then
                        dropped = dropped or {}
                        dropped[id], gone = true, true
                        break
                    end
                end
            end
        end
        if not gone then break end
        steps, cost, picked = solve(guide, skill, learned, priceFn, allow, prefer, held, opts, credit, dropped)
    end
    local touched = false
    for _, st in ipairs(steps) do
        if st.spell and plain.touched(st.spell, guide.recipes[st.spell]) then touched = true break end
    end
    if touched then
        -- The last plan's touched picks are no anchor without the coupling, and a locked step
        -- on a touched recipe is not held there either.
        local function untouched(map)
            if not map then return nil end
            local out = {}
            for s, id in pairs(map) do
                if not plain.touched(id, guide.recipes[id]) then out[s] = id end
            end
            return out
        end
        local plainOpts = opts
        if opts.fixed then
            plainOpts = {}
            for k, v in pairs(opts) do plainOpts[k] = v end
            plainOpts.fixed = untouched(opts.fixed)
        end
        steps.plain = solve(guide, skill, learned, plain.price, plain.allow, untouched(prefer), held, plainOpts, nil)
    end
    return steps, cost
end
