local _, CP = ...
if CP.stopped then return end

-- Picks the current guide step from a generated guide (Data/Guides). Pure logic,
-- so it runs headless.

local Guide = {}
CP.Guide = Guide

-- Skill-up chance multiplier from the Working Overtime legacy perk. Prof.ReadOvertime sets it.
Guide.boost = 1

-- Chance `p` with the perk's multiplier, capped at 1.
function Guide.Boost(p)
    local b = Guide.boost
    if b == 1 or p <= 0 then return p end
    return math.min(1, p * b)
end

-- Chance that one craft at skill `s` gives a point.
function Guide.Chance(recipe, s)
    if s >= recipe.grey then return 0 end
    if s < recipe.yellow then return 1 end
    return Guide.Boost((recipe.grey - s) / (recipe.grey - recipe.yellow))
end

-- Expected crafts to go from skill `from` to `to` with this recipe.
function Guide.Crafts(recipe, from, to)
    local total = 0
    for s = from, to - 1 do
        local p = Guide.Chance(recipe, s)
        if p <= 0 then return math.huge end
        total = total + 1 / p
    end
    return math.ceil(total)
end

-- The guide for a profession, by any of its ids, else by name.
function Guide.For(prof)
    local guides = CP.Guides or {}
    for _, id in ipairs(prof.ids or { prof.id }) do
        if guides[id] then return guides[id] end
    end
    for _, g in pairs(guides) do
        if g.name == prof.name then return g end
    end
    return nil
end

-- Where `skill` sits in `guide`. `learned` is a set of recipe ids the player knows.
-- `steps` is a live plan from Solver.Plan; without it the generated steps are used.
-- Returns nil past the end of the guide, else:
--   { index, step, recipe, from, crafts, learned, next }
-- A step starts at the player's skill once it is under way; a step whose recipe is
-- already grey hands over to the following step.
function Guide.Current(guide, skill, learned, steps)
    steps = steps or guide.steps
    for i, step in ipairs(steps) do
        if skill < step.to and step.spell then
            local recipe = guide.recipes[step.spell]
            if recipe and Guide.Chance(recipe, math.max(skill, step.from)) > 0 then
                local from = math.max(skill, step.from)
                local nextStep = steps[i + 1]
                return {
                    index = i,
                    step = step,
                    recipe = recipe,
                    from = from,
                    crafts = Guide.Crafts(recipe, from, step.to),
                    learned = learned[step.spell] == true,
                    next = nextStep and nextStep.spell and {
                        step = nextStep, recipe = guide.recipes[nextStep.spell],
                    } or nil,
                }
            end
        end
    end
    return nil
end

-- What trainer `entry` charges for `recipe`: its own fee where the guide's `fees` gives
-- one, else the recipe's `fee` (the lowest).
function Guide.Fee(recipe, entry)
    return recipe.fees and entry and recipe.fees[entry] or recipe.fee or 0
end

-- Where visit `stop` sends the player: its first recipe, with `npcs` cut to the trainers
-- who teach every recipe of the visit. An apprentice trainer teaches the early recipes
-- only (Kamari, Leatherworking), so the first recipe's trainers alone can be the wrong
-- stop. With no trainer teaching them all, the first recipe's trainers.
function Guide.VisitTarget(stop)
    if stop.target then return stop.target end
    local first = stop.recipes[1]
    local teaches, listed = {}, 0
    for _, r in ipairs(stop.recipes) do
        if r.npcs and #r.npcs > 0 then listed = listed + 1 end
        for _, entry in ipairs(r.npcs or {}) do teaches[entry] = (teaches[entry] or 0) + 1 end
    end
    local all = {}
    for _, entry in ipairs(first.npcs or {}) do
        if teaches[entry] == listed then all[#all + 1] = entry end
    end
    local target = first
    if #all > 0 and #all < #(first.npcs or {}) then
        target = setmetatable({ npcs = all }, { __index = first })
    end
    stop.target = target
    return target
end

-- True when a trainer teaches every recipe of visit `stop` and recipe `r` too. A recipe
-- with no trainer list goes with any visit.
local function sharesTrainer(stop, r)
    if not (r.npcs and #r.npcs > 0) then return true end
    local teaches, listed = {}, 0
    for _, other in ipairs(stop.recipes) do
        if other.npcs and #other.npcs > 0 then
            listed = listed + 1
            for _, entry in ipairs(other.npcs) do teaches[entry] = (teaches[entry] or 0) + 1 end
        end
    end
    if listed == 0 then return true end
    for _, entry in ipairs(r.npcs) do
        if teaches[entry] == listed then return true end
    end
    return false
end

-- What each trainer of the player's side charges for visit `stop`: { { entry, name, fee } },
-- cheapest first, from the trainers its waypoint can go to (Guide.VisitTarget).
-- Empty when the guide gives no per-trainer fees for the visit.
local function visitFees(guide, stop)
    local varies = false
    for _, r in ipairs(stop.recipes) do
        if r.fees then varies = true end
    end
    if not varies then return {} end
    local side = CP.Sourcing and CP.Sourcing.Side()
    local out = {}
    for _, entry in ipairs(Guide.VisitTarget(stop).npcs or {}) do
        local npc = guide.npcs and guide.npcs[entry]
        if npc and (npc[2] == "N" or not side or npc[2] == side) then
            local fee = 0
            for _, r in ipairs(stop.recipes) do fee = fee + Guide.Fee(r, entry) end
            out[#out + 1] = { entry = entry, name = npc[1], fee = fee }
        end
    end
    table.sort(out, function(a, b) return a.fee < b.fee or a.fee == b.fee and a.entry < b.entry end)
    return out
end

-- How deep a made material's own made materials count (Unstable Trigger's Solid Blasting Powder).
Guide.PREP_DEPTH = 3

-- Trainer visits the plan needs: one per skill where a step first uses an unlearned
-- trainer recipe (never below `skill`). Returns, in skill order,
-- { { skill, recipes = { recipe... }, spells, fee, fees, before, pattern } }; `before`
-- indexes `steps`. `fee` is the lowest a trainer of the player's side charges; `fees` lists
-- each one's (visitFees) where they differ.
-- A recipe that makes a step's material (`guide.prep`) and isn't learned is taught before
-- the first step whose crafts the held stock (`held`, item -> count) doesn't cover. A trainer
-- one rides the last visit from its learn skill to that step, else gets a visit at the step.
-- A pattern one (a vendor or favor schematic) gets a stop of its own, `pattern` set.
function Guide.TrainStops(guide, steps, learned, skill, held)
    local bySkill, order, trained = {}, {}, {}
    local prep = guide.prep or {}

    -- A new stop at skill `at`, the `nth` there.
    local function newStop(at, pattern)
        bySkill[at] = bySkill[at] or {}
        local stop = { skill = at, recipes = {}, spells = {}, fee = 0, seen = {}, pattern = pattern }
        local n = #bySkill[at] + 1
        stop.nth = n > 1 and n or nil
        bySkill[at][n] = stop
        order[#order + 1] = stop
        return stop
    end

    local function teach(stop, id, r, i)
        trained[id] = true
        if not stop.seen[id] then
            stop.seen[id] = true
            stop.recipes[#stop.recipes + 1] = r
            stop.spells[#stop.spells + 1] = id
            if not stop.pattern then stop.fee = stop.fee + (r.fee or 0) end
            -- Taught only after a rank quest (doctors after Triage).
            stop.after = stop.after or Guide.AfterText(guide, r)
        end
        if i then stop.need = math.min(stop.need or i, i) end
    end

    -- The maker of a made material step `i` needs. A trainer recipe joins the last visit
    -- from its learn skill up to the step's start whose trainer teaches it too.
    local function teachMaker(i, st, id, r)
        if learned[id] or trained[id] then return end
        local word = Guide.SourceWord(r)
        -- An "auto" recipe comes with its rank, a specialization's with the specialization.
        if r.src == "auto" or r.src == "specialization" then return end
        local start = math.max(skill, st.from or skill)
        local at = math.max(start, r.learn or 1)
        if word ~= "trainer" then return teach(newStop(at, true), id, r, i) end
        local ride
        for _, stop in ipairs(order) do
            if not stop.pattern and stop.skill >= math.max(skill, r.learn or 1) and stop.skill <= start
                and sharesTrainer(stop, r) and (not ride or stop.skill >= ride.skill) then
                ride = stop
            end
        end
        if not ride then
            for _, s in ipairs(bySkill[at] or {}) do
                if not s.pattern and sharesTrainer(s, r) then ride = s break end
            end
        end
        teach(ride or newStop(at), id, r, i)
    end

    -- What the bags and bank hold of each made material, drawn down step by step.
    local left = {}
    for item, n in pairs(held or {}) do
        if prep[item] then left[item] = n end
    end
    local function needMade(i, st, item, count, depth)
        local id = prep[item]
        local r = id and guide.recipes[id]
        if not r or count <= 0 then return end
        local take = math.min(left[item] or 0, count)
        left[item] = (left[item] or 0) - take
        count = count - take
        if count <= 1e-9 then return end
        teachMaker(i, st, id, r)
        if depth >= Guide.PREP_DEPTH then return end
        local runs = math.ceil(count / (r.yield or 1))
        for _, pair in ipairs(r.reagents or {}) do needMade(i, st, pair[1], pair[2] * runs, depth + 1) end
    end

    for i, st in ipairs(steps) do
        local r = st.spell and guide.recipes[st.spell]
        if r and r.src == "trainer" and not learned[st.spell] and not trained[st.spell] then
            local at = math.max(skill, st.from or skill, r.learn)
            -- One visit per trainer: recipes no common trainer teaches are separate visits
            -- at the same skill (an apprentice trainer and a journeyman one).
            local stop
            for _, s in ipairs(bySkill[at] or {}) do
                if not s.pattern and sharesTrainer(s, r) then stop = s break end
            end
            teach(stop or newStop(at), st.spell, r)
        end
        if r then
            for _, pair in ipairs(r.reagents or {}) do needMade(i, st, pair[1], pair[2] * (st.crafts or 0), 1) end
        end
        -- An "or" row's made materials are taught as a step's are. The row stands in for the
        -- step, so it draws on the stock without using it up.
        local stock = {}
        for item, n in pairs(left) do stock[item] = n end
        for _, spell in ipairs(st.ors or {}) do
            local o = guide.recipes[spell]
            local lo, upto = o and math.max(st.from or skill, o.learn or 1), o and math.min(st.to or 0, o.grey or 0)
            local crafts = o and lo < upto and Guide.Crafts(o, lo, upto) or 0
            if crafts > 0 and crafts < math.huge then
                for _, pair in ipairs(o.reagents or {}) do needMade(i, st, pair[1], pair[2] * crafts, 1) end
            end
            for item in pairs(left) do left[item] = stock[item] end
        end
    end
    table.sort(order, function(a, b) return a.skill < b.skill or a.skill == b.skill and (a.nth or 1) < (b.nth or 1) end)
    -- A step's "or" rows (`ors`, recipe ids) join the last visit from their learn skill up
    -- to the step's start. Without one, the "or" row itself says "trainer".
    for _, st in ipairs(steps) do
        for _, spell in ipairs(st.ors or {}) do
            local r = guide.recipes[spell]
            if r and r.src == "trainer" and not learned[spell] and not trained[spell] then
                -- The last such visit whose trainer teaches the "or" row too; with none, a
                -- visit of its own at the last one's skill.
                local visit, shared
                for _, stop in ipairs(order) do
                    if not stop.pattern and stop.skill >= math.max(skill, r.learn) and stop.skill <= (st.from or skill) then
                        visit = stop
                        if sharesTrainer(stop, r) then shared = stop end
                    end
                end
                if visit and not shared then
                    local same = bySkill[visit.skill]
                    shared = { skill = visit.skill, recipes = {}, spells = {}, fee = 0, nth = #same + 1 }
                    same[#same + 1] = shared
                    local at = #order + 1
                    for i, stop in ipairs(order) do
                        if stop == same[#same - 1] then at = i + 1 end
                    end
                    table.insert(order, at, shared)
                end
                visit = shared
                if visit then
                    trained[spell] = true
                    visit.recipes[#visit.recipes + 1] = r
                    visit.spells[#visit.spells + 1] = spell
                    visit.fee = visit.fee + (r.fee or 0)
                    visit.after = visit.after or Guide.AfterText(guide, r)
                end
            end
        end
    end
    for _, stop in ipairs(order) do
        local fees = visitFees(guide, stop)
        if #fees > 0 then
            stop.fee = fees[1].fee
            if fees[#fees].fee > fees[1].fee then stop.fees = fees end
        end
        stop.seen = nil
        stop.before = #steps + 1
        for i, st in ipairs(steps) do
            if (st.from or 0) >= stop.skill then
                stop.before = i
                break
            end
        end
        -- A maker comes before the first step that needs it, under way or not.
        if stop.need and stop.need < stop.before then stop.before = stop.need end
        stop.need = nil
    end
    return order
end

-- The trainer visit pending rank `p` (a PendingRanks entry) rides: the first of `visits`
-- (TrainStops) from the rank's learn skill up to below its cap, at or before the step the rank
-- would stand before. Nil for a book or quest rank, or with no such visit.
function Guide.RankVisit(p, visits)
    if p.rank.kind ~= "trainer" then return nil end
    for _, stop in ipairs(visits) do
        if not stop.pattern and stop.skill >= p.rank.skill and stop.skill < p.rank.cap and stop.before <= p.before then
            return stop
        end
    end
    return nil
end

-- True when step `st` climbs through `cap` and WithStops draws it cut there. The current step
-- keeps its one row, as its card and Next up count the whole step.
function Guide.DrawnCut(guide, st, cap)
    return st ~= nil and st.spell ~= nil and guide.recipes[st.spell] ~= nil and not (st.current or st.first)
        and st.from < cap and st.to > cap
end

-- `steps` with stop rows put in place: a { key, train } row before the first step at
-- or past each trainer visit, a { key, rank } row where PendingRanks puts it (the cap). A
-- saved step through that cap (cut nowhere by SplitAtCaps while the rank rode a visit) is
-- drawn as two rows with the rank row between, unless it is the current step.
-- A trainer rank joins the first trainer visit from its learn skill up to below its cap,
-- so one trip does both, and leads that visit's rows. The rank that holds the player at their
-- cap gets `capped`; one the player's skill has opened but their level can't train gets
-- `levelShort` (Guide.LevelShort). `learned` is a set of recipe ids; `maxSkill` the
-- player's current cap; `level` the character level, else the game's; `held` the made
-- materials in the bags and bank (item -> count), else Plan.Held's.
function Guide.WithStops(guide, steps, learned, skill, maxSkill, level, held)
    local at = {}
    local function add(before, row, first)
        at[before] = at[before] or {}
        table.insert(at[before], first and 1 or #at[before] + 1, row)
    end
    held = held or (CP.Plan and CP.Plan.Held and CP.Plan.Held(guide)) or {}
    local visits = Guide.TrainStops(guide, steps, learned, skill, held)
    for _, stop in ipairs(visits) do
        local kind = stop.pattern and "pattern" or "train"
        add(stop.before, { key = kind .. stop.skill .. (stop.nth and ("." .. stop.nth) or ""), train = stop })
    end
    level = level or Guide.PlayerLevel()
    local held = Guide.CapRank(guide, skill, maxSkill)
    local ranks = Guide.PendingRanks(guide, maxSkill, steps)
    -- A saved step that crosses the cap of a rank with no visit to ride is drawn cut at the
    -- cap, the rank row between its parts: index -> { cap, rank rows }.
    local inside = {}
    for i = #ranks, 1, -1 do
        local p = ranks[i]
        local before, where = p.before, p.at
        local visit = Guide.RankVisit(p, visits)
        if visit then before, where = visit.before, visit.skill end
        local row = { key = "rank" .. p.rank.skill, rank = p.rank, at = where, capped = p.rank == held or nil,
                      levelShort = Guide.LevelShort(p.rank, skill, level) }
        local st, cap = steps[before], p.rank.cap
        if not visit and Guide.DrawnCut(guide, st, cap) and (not inside[before] or inside[before].cap == cap) then
            row.at = cap
            inside[before] = inside[before] or { cap = cap, rows = {} }
            table.insert(inside[before].rows, 1, row)
        else
            add(before, row, true)
        end
    end
    local out = {}
    for i = 1, #steps + 1 do
        for _, row in ipairs(at[i] or {}) do out[#out + 1] = row end
        local st, cut = steps[i], inside[i]
        if cut then
            local tail = Guide.StepPart(guide, st, cut.cap, st.to)
            local head = Guide.StepPart(guide, st, st.from, cut.cap)
            tail.key, tail.current, tail.keep, tail.planIndex = cut.cap, nil, nil, nil
            -- The head keeps what the row counts beyond the tail: kept crafts, crafts made so far.
            head.crafts = math.max(1, (st.crafts or 0) - (tail.crafts or 0))
            out[#out + 1] = head
            for _, row in ipairs(cut.rows) do out[#out + 1] = row end
            out[#out + 1] = tail
        elseif st then
            out[#out + 1] = st
        end
    end
    return out
end

-- WithStops' `rows` with each run of one recipe drawn as one row: a step row joins the step row
-- right before it when both craft the same recipe over touching ranges. The plan cuts a step at
-- a rank's cap, and the rank row can sit earlier, on a trainer visit; the two parts then stand
-- side by side with nothing to do between them (Woolen Cape 73-75, 75-97).
-- A stop row between two parts keeps them apart, and so do the current row and any row
-- `alone(row)` holds (a locked step, one with "or" rows). The joined row keeps the first part's
-- fields and adds the second's range, crafts, cost and keeps.
function Guide.JoinRuns(rows, alone)
    local out = {}
    local function step(row)
        return row and row.spell and not (row.rank or row.train or row.side) and row.from and row.to
    end
    for _, row in ipairs(rows) do
        local prev = out[#out]
        if step(prev) and step(row) and prev.spell == row.spell and prev.to == row.from
            and not prev.current and not row.current and not (alone and (alone(prev) or alone(row))) then
            local joined = {}
            for k, v in pairs(prev) do joined[k] = v end
            joined.to = row.to
            joined.crafts = (prev.crafts or 0) + (row.crafts or 0)
            joined.cost = (prev.cost or row.cost) and (prev.cost or 0) + (row.cost or 0) or nil
            if prev.keep or row.keep then
                local names, seen = {}, {}
                for _, k in ipairs({ prev.keep or {}, row.keep or {} }) do
                    for _, name in ipairs(k.names or {}) do
                        if not seen[name] then
                            seen[name] = true
                            names[#names + 1] = name
                        end
                    end
                end
                joined.keep = { count = (prev.keep and prev.keep.count or 0) + (row.keep and row.keep.count or 0), names = names }
            end
            joined.parts = (prev.parts or 1) + 1
            out[#out] = joined
        else
            out[#out + 1] = row
        end
    end
    return out
end

-- The character's level, nil where the game can't say.
function Guide.PlayerLevel()
    local level = UnitLevel and UnitLevel("player")
    return type(level) == "number" and level or nil
end

-- A rank the player's `skill` has opened but their `level` is too low to learn:
-- { need, have, text }, else nil.
function Guide.LevelShort(rank, skill, level)
    if not (rank.level and level and skill) or level >= rank.level or skill < rank.skill then return nil end
    return { need = rank.level, have = level,
             text = ("%s needs level %d (you're %d)"):format(rank.name, rank.level, level) }
end

-- The first rank still to learn that `skill` has opened and `level` is too low for, as
-- Guide.LevelShort's result, else nil. `maxSkill` is the player's current cap.
function Guide.LevelShortFor(guide, skill, maxSkill, level)
    for _, rank in ipairs(guide.ranks or {}) do
        if (maxSkill or 0) <= rank.cap then
            local short = Guide.LevelShort(rank, skill, level)
            if short then return short end
        end
    end
    return nil
end

-- How far the player's gathered materials go and what to buy from vendors for the step.
-- `reagents` is { { itemID, name, need, have } } (need per craft); a material is a
-- vendor one when the guide marks it sold without limit. Returns the crafts the
-- gathered materials cover (capped at `crafts`) and { { itemID, name, count } } to buy:
-- each vendor good for all `crafts`, since it is cheap and the rest is gathered anyway
-- (owner, 2026-11-18).
function Guide.VendorTopUp(guide, reagents, crafts)
    local n = crafts
    for _, m in ipairs(reagents) do
        local item = guide.items and guide.items[m.itemID]
        if not (item and item[2]) and m.need > 0 then
            n = math.min(n, math.floor(m.have / m.need))
        end
    end
    local buy = {}
    for _, m in ipairs(reagents) do
        local item = guide.items and guide.items[m.itemID]
        if item and item[2] then
            local short = crafts * m.need - m.have
            if short > 0 then buy[#buy + 1] = { itemID = m.itemID, name = m.name, count = short } end
        end
    end
    return n, buy
end

-- What to hold on to from each step: crafted items later steps use as materials.
-- `held` (item -> count in the player's bags) is drawn on first. Returns
-- { [step index] = { count, names = { recipe name... } } }, earliest makers supplying
-- first. What later steps need of a prep or craft-only product beyond everything made goes on
-- the last maker before the first step that needs the item, so that step asks for enough (Cured
-- Rugged Hide: make 24, not 15). A maker cut at a rank cap keeps its surplus on the part that ends at grey.
function Guide.Keeps(guide, steps, held)
    local supply, out, last = {}, {}, {}
    for item, n in pairs(held or {}) do supply[item] = { { index = 0, left = n } } end
    for i, st in ipairs(steps) do
        local r = st.spell and guide.recipes[st.spell]
        if r then
            for _, pair in ipairs(r.reagents) do
                local need = pair[2] * (st.crafts or 0)
                -- The last maker before the first step that needs this item.
                if last[pair[1]] == nil then
                    last[pair[1]] = false
                    for _, src in ipairs(supply[pair[1]] or {}) do
                        if src.index > 0 then last[pair[1]] = src end
                    end
                end
                -- With none there, the earliest maker so far.
                local into = last[pair[1]] or nil
                for _, src in ipairs(supply[pair[1]] or {}) do
                    if src.index > 0 and not into then into = src end
                    if need <= 0 then break end
                    local take = math.min(src.left, need)
                    if take > 0 then
                        src.left, need = src.left - take, need - take
                        local k = out[src.index] or { count = 0, names = {}, seen = {} }
                        out[src.index] = k  -- index 0 is the player's own stock
                        k.count = k.count + take
                        if not k.seen[r.name] then
                            k.seen[r.name] = true
                            k.names[#k.names + 1] = r.name
                        end
                    end
                end
                -- Surplus goes on a maker row only for a prep or craft-only product; a made product
                -- that also drops or sells is bought for the rest (decision 0008 rule 10).
                local item = pair[1]
                if need > 0 and into and ((guide.prep or {})[item] or (guide.craftOnly or {})[item]) then
                    local k = out[into.index] or { count = 0, names = {}, seen = {} }
                    out[into.index] = k
                    k.count = k.count + need
                    if not k.seen[r.name] then
                        k.seen[r.name] = true
                        k.names[#k.names + 1] = r.name
                    end
                end
            end
            if r.makes then
                supply[r.makes] = supply[r.makes] or {}
                table.insert(supply[r.makes], { index = i, left = (st.crafts or 0) * (r.yield or 1) })
            end
        end
    end
    out[0] = nil
    for _, k in pairs(out) do
        k.seen = nil
        k.count = math.ceil(k.count)
    end
    return out
end

-- Crafts of recipe `r` that make `count` of its product. A keep counts items; one craft of
-- Silver Contact makes 5.
function Guide.KeepCrafts(r, count)
    if not count or count <= 0 then return 0 end
    return math.ceil(count / (r and r.yield or 1) - 1e-9)
end

-- A visit's fee as its card reads it: at trainer `entry` when one is named, with where it
-- costs less ("90s (55s at Hahrana Ironhide)"); with none named, the lowest and who charges
-- it ("55s at Hahrana Ironhide"); just the fee where every trainer charges the same.
local function visitCost(t, entry)
    local fmt = CP.Pricing and CP.Pricing.Format or tostring
    local fees = t.fees
    if not fees then return fmt(t.fee) end
    local low = fees[1]
    for _, f in ipairs(fees) do
        if f.entry == entry then
            if f.fee <= low.fee then return fmt(f.fee) end
            return ("%s (%s at %s)"):format(fmt(f.fee), fmt(low.fee), low.name)
        end
    end
    return ("%s at %s"):format(fmt(low.fee), low.name)
end

-- Row name and one-line explanation for a stop row: { rank = ... } or { train = ... }.
-- A rank is a book unless its `kind` says trainer or quest. `entry`: the trainer the card
-- names for a visit, whose fee it quotes.
function Guide.StopText(row, entry)
    local fmt = CP.Pricing and CP.Pricing.Format or tostring
    if row.rank then
        local r = row.rank
        local level = r.level and ("  ·  level %d"):format(r.level) or ""
        -- At the cap: no craft gives a point until this rank is learned.
        local held = row.capped and ("Skill capped at %d. "):format(r.cap) or ""
        if row.levelShort then held = held .. row.levelShort.text .. ". " end
        if r.kind == "trainer" then
            local cost = (r.fee or 0) > 0 and ("  ·  " .. fmt(r.fee)) or ""
            return "Train " .. r.name,
                ("%sVisit a trainer at skill %d to train past %d%s%s"):format(held, r.skill, r.cap, cost, level)
        elseif r.kind == "quest" then
            return r.name, ("%sQuest at skill %d to train past %d: %s%s"):format(held, r.skill, r.cap, r.quest or "?", level)
        end
        return r.name, ("%sBuy and read at skill %d to train past %d  ·  %s from a vendor"):format(held, r.skill, r.cap,
            fmt(r.price))
    end
    local t = row.train
    -- A schematic that makes a step's material: "Learn EZ-Thro Fireproof Fuse".
    if t.pattern then
        local r = t.recipes[1]
        return "Learn " .. r.name, ("Get the pattern by skill %d: %s"):format(t.skill, Guide.LearnText(r))
    end
    local names = {}
    for i, r in ipairs(t.recipes) do names[i] = r.name end
    local name = #names == 1 and ("Train " .. names[1]) or ("Train %d recipes"):format(#names)
    local cost = t.fee > 0 and ("  ·  " .. visitCost(t, entry)) or ""
    local after = t.after and ("  ·  " .. t.after) or ""
    return name, ("Visit a trainer at skill %d: %s%s%s"):format(t.skill, table.concat(names, ", "), cost, after)
end

-- The NPC nearest the player that teaches or sells `target` (a recipe or rank), with its
-- `entry`, or nil.
function Guide.Nearest(guide, target)
    return target and guide and CP.Waypoint.NearestFor(guide, target) or nil
end

-- What the card adds after a trainer's name whose recipe's trainers are a guess (the data's
-- `npcsUnconfirmed`).
Guide.UNCONFIRMED = "trainer not confirmed"

-- " from Shandrina, Ashenvale (50.2, 67.1)" for the NPC nearest the player for `target`,
-- with "  ·  trainer not confirmed" for a guessed trainer, and that NPC; "" and nil when none.
function Guide.FromText(guide, target)
    local npc = Guide.Nearest(guide, target)
    if not npc then return "", nil end
    local text = (" from %s, %s"):format(npc.name, CP.Waypoint.Describe(npc))
    if target.npcsUnconfirmed then text = text .. "  ·  " .. Guide.UNCONFIRMED end
    return text, npc
end

-- Short tag for a rank row: "buy" for a book, "train" or its fee, "quest".
function Guide.RankTag(rank)
    if rank.kind == "quest" then return "quest" end
    if rank.kind == "trainer" then
        local fmt = CP.Pricing and CP.Pricing.Format or tostring
        return (rank.fee or 0) > 0 and fmt(rank.fee) or "train"
    end
    return "buy"
end

-- "after the Triage quest" for a recipe its trainer teaches only past a rank quest, else nil.
function Guide.AfterText(guide, recipe)
    if not recipe.after then return nil end
    for _, rank in ipairs(guide.ranks or {}) do
        if rank.spell == recipe.after then
            return rank.quest and ("after the %s quest"):format(rank.quest) or ("after " .. rank.name)
        end
    end
    return nil
end

local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

local function secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- The player's reaction with a faction (1 Hated .. 8 Exalted) and its name, or nil
-- when the game doesn't say (no API, faction not met yet, secret values).
function Guide.Standing(factionID)
    if not (C_Reputation and C_Reputation.GetFactionDataByID) then return nil end
    local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
    if not ok then return nil end
    -- No data for a faction the player has never met (seen in game 2026-11-12): no standing.
    if data == nil then return 0 end
    if type(data) ~= "table" then return nil end
    local reaction, name = data.reaction, data.name
    if secret(reaction) or type(reaction) ~= "number" or reaction < 1 then return nil end
    if secret(name) or type(name) ~= "string" or name == "" then name = nil end
    return reaction, name
end

-- Whether the player has the standing a recipe's pattern needs: true (or no faction),
-- false when the game shows less, nil when it can't be read.
function Guide.HasStanding(recipe)
    if not recipe.faction then return true end
    local reaction = Guide.Standing(recipe.faction)
    if not reaction then return nil end
    return reaction >= (recipe.standing or 0)
end

-- "needs Zandalar Tribe Friendly" for a reputation pattern, else nil.
function Guide.StandingText(guide, recipe)
    if not recipe.faction then return nil end
    local _, name = Guide.Standing(recipe.faction)
    name = name or (guide and guide.factions and guide.factions[recipe.faction]) or "a faction"
    local label = _G["FACTION_STANDING_LABEL" .. tostring(recipe.standing)]
    if secret(label) or type(label) ~= "string" then label = STANDING[recipe.standing] or "" end
    return ("needs %s %s"):format(name, label)
end

-- What learning an unlearned recipe needs besides its source, joined: the faction
-- standing and the rank quest. Nil when nothing.
function Guide.Needs(guide, recipe)
    local out = {}
    out[#out + 1] = Guide.StandingText(guide, recipe)
    out[#out + 1] = guide and Guide.AfterText(guide, recipe) or nil
    return #out > 0 and table.concat(out, "  ·  ") or nil
end

-- The nearest of `vendors` (creature entries in guide.npcs) on the player's continent:
-- { name, continent, x, y }, or nil.
function Guide.NearestSeller(guide, vendors)
    if not (guide and vendors and #vendors > 0) then return nil end
    local continent = CP.Waypoint.PlayerWorld()
    local near = CP.Waypoint.NearestFor(guide, { npcs = vendors })
    if near and continent and near.continent == continent then return near end
    return nil
end

-- The card's line for a vendor good whose data names its seller: "Buy Mote of Magic at an
-- Enchanting Supplies vendor: Jessara Cordell, Stormwind City (52.6, 74.2)". Nil for
-- goods without a named seller.
function Guide.BuyNote(guide, itemID, name)
    local it = guide.items and guide.items[itemID]
    if not (it and it[2] and it.seller) then return nil end
    local article = it.seller:find("^[AEIOUaeiou]") and "an" or "a"
    local text = ("Buy %s at %s %s vendor"):format(name, article, it.seller)
    local near = Guide.NearestSeller(guide, it.vendors)
    if near then text = ("%s: %s, %s"):format(text, near.name, CP.Waypoint.Describe(near)) end
    return text
end

-- Tools: a recipe's `tools` = { itemID... } must be in the bags to craft it (Blacksmith
-- Hammer, Arclight Spanner, a runed rod). The guide's `toolsAlso` = { [tool] = { itemID... } }
-- names items that serve for a tool (a Runed Arcanite Rod for a Runed Copper Rod). The first
-- tool the bags lack, as { item, name, text }: "Take Blacksmith Hammer from the bank" when only
-- the bank holds it or a stand-in (named: the one the bank holds), "Make Runed Copper Rod first"
-- when a guide recipe makes it, else "Needs Blacksmith Hammer".
Guide.TOOL_MAKE = "Make %s first"
Guide.TOOL_BANK = "Take %s from the bank"
Guide.TOOL_NEEDS = "Needs %s"

-- The tool or a stand-in the bags hold (with `bank`, bags and bank), or nil.
local function held(guide, item, bank)
    if (C_Item.GetItemCount(item, bank) or 0) > 0 then return item end
    for _, other in ipairs(guide.toolsAlso and guide.toolsAlso[item] or {}) do
        if (C_Item.GetItemCount(other, bank) or 0) > 0 then return other end
    end
    return nil
end

function Guide.MissingTool(guide, recipe)
    for _, item in ipairs(recipe and recipe.tools or {}) do
        if not held(guide, item) then
            local banked = held(guide, item, true)
            local shown = banked or item
            -- The name may still be loading; the item's redraw brings it.
            local name = CP.ItemName(shown)
            if not name or name == "" then name = "item " .. shown end
            local made
            for _, r in pairs(guide.recipes) do
                if r.makes == item then made = true break end
            end
            local text = banked and Guide.TOOL_BANK or made and Guide.TOOL_MAKE or Guide.TOOL_NEEDS
            return { item = shown, name = name, text = text:format(name) }
        end
    end
    return nil
end

-- A step's material made on demand by a recipe the player hasn't learned and can't
-- train ("EZ-Thro Fireproof Fuse: Schematic for 180 Merchant's Favor ..."), else nil. A
-- trainer maker needs no note: its Train row stands above the step.
function Guide.PrepNote(guide, recipe, learned)
    for _, pair in ipairs(recipe.reagents or {}) do
        local makerID = guide.prep and guide.prep[pair[1]]
        local maker = makerID and guide.recipes[makerID]
        if maker and not learned[makerID] and Guide.SourceWord(maker) ~= "trainer" then
            return ("%s: %s"):format(maker.name, Guide.LearnText(maker, guide))
        end
    end
    return nil
end

-- Ranks the player still needs: those whose cap the player's max hasn't passed, while
-- some step climbs past it. Each sits where the player needs it: at the start of the first
-- step past its cap, which SplitAtCaps starts at the cap. WithStops pulls a trainer rank
-- earlier, into a trainer visit the player makes anyway. Returns { { rank, before, at } },
-- `before` an index into `steps`.
function Guide.PendingRanks(guide, maxSkill, steps)
    local out = {}
    for _, rank in ipairs(guide.ranks or {}) do
        if (maxSkill or 0) <= rank.cap then
            local before
            for i, st in ipairs(steps) do
                if st.to > rank.cap then
                    before = i
                    break
                end
            end

            -- Shown at the skill where it sits, so the list's skill column keeps climbing.
            if before then
                out[#out + 1] = { rank = rank, before = before, at = math.max(rank.skill, steps[before].from or 0) }
            end
        end
    end
    return out
end

-- The rank that holds the player at their cap: `skill` has reached `maxSkill` and a
-- rank lifts it. Nil below the cap, at 300, or when the guide has no such rank.
function Guide.CapRank(guide, skill, maxSkill)
    if not (skill and maxSkill) or maxSkill <= 0 or skill < maxSkill then return nil end
    for _, rank in ipairs(guide.ranks or {}) do
        if rank.cap == maxSkill then return rank end
    end
    return nil
end

-- The rank a craft step from `from` waits on: the one that lifts `maxSkill`, when the
-- step starts at or past it, or the player's `skill` is already there. Crafting it gives
-- no skill until that rank is learned.
function Guide.PastCap(guide, from, skill, maxSkill)
    from = math.max(from or 0, skill or 0)
    if not maxSkill or maxSkill <= 0 or from < maxSkill then return nil end
    for _, rank in ipairs(guide.ranks or {}) do
        if rank.cap == maxSkill then return rank end
    end
    return nil
end

-- What learning `rank` takes: "Train" at a trainer, "Read" for a book, else "Learn".
function Guide.RankVerb(rank)
    if rank.kind == "trainer" then return "Train" end
    if rank.kind == "quest" then return "Learn" end
    return "Read"
end

-- Why a step past the cap can't be crafted: "Skill capped at 150. Train Expert Leatherworking first."
function Guide.CapText(rank)
    return ("Skill capped at %d. %s %s first."):format(rank.cap, Guide.RankVerb(rank), rank.name)
end

-- The pending trainer ranks of a solved plan (Solver.Plan's `steps`, which carry the solve's
-- `learned`) that ride a trainer visit before their cap (Guide.RankVisit). A set of ranks.
function Guide.RidingRanks(guide, steps, maxSkill)
    local out = {}
    local learned, first = steps.learned, steps[1]
    if not (learned and first) then return out end
    local held = CP.Plan and CP.Plan.Held and CP.Plan.Held(guide) or {}
    local visits = Guide.TrainStops(guide, steps, learned, first.from, held)
    for _, p in ipairs(Guide.PendingRanks(guide, maxSkill, steps)) do
        if Guide.RankVisit(p, visits) then out[p.rank] = true end
    end
    return out
end

-- `steps` with the step that climbs past a rank's cap cut at the cap, so the rank sits
-- between its two parts. Only ranks the player still needs count (`maxSkill` at or below
-- their cap). A rank that rides an earlier trainer visit (Guide.RidingRanks) sits there,
-- so its cap cuts nothing. A cut step keeps its spell; crafts and cost are counted again
-- for each part.
function Guide.SplitAtCaps(guide, steps, maxSkill)
    local out = steps
    local riding = Guide.RidingRanks(guide, steps, maxSkill)
    for _, rank in ipairs(guide.ranks or {}) do
        if (maxSkill or 0) <= rank.cap and not riding[rank] then
            for i, st in ipairs(out) do
                if st.to > rank.cap then
                    if st.from < rank.cap then
                        local cut = {}
                        for j = 1, i - 1 do cut[j] = out[j] end
                        cut[i] = Guide.StepPart(guide, st, st.from, rank.cap)
                        cut[i + 1] = Guide.StepPart(guide, st, rank.cap, st.to)
                        for j = i + 1, #out do cut[#cut + 1] = out[j] end
                        out = cut
                    end
                    break
                end
            end
        end
    end
    return out
end

-- Step `st` from `from` to `to`: its crafts for that stretch, its cost in proportion.
function Guide.StepPart(guide, st, from, to)
    local part = {}
    for k, v in pairs(st) do part[k] = v end
    part.from, part.to = from, to
    -- Only the part that starts where the step did is under way.
    if from ~= st.from then part.since = nil end
    local recipe = st.spell and guide.recipes[st.spell]
    if recipe then
        local crafts = Guide.Crafts(recipe, from, to)
        if crafts < math.huge then
            part.cost = (st.crafts or 0) > 0 and (st.cost or 0) * crafts / st.crafts or 0
            part.crafts = crafts
        end
    end
    return part
end

-- Everything in `guide` the player can buy from a vendor and still needs: unlearned
-- vendor and reputation patterns, and rank books not yet read. `learned` is a set of
-- recipe ids. Returns { { name, npcs, item, skill, faction?, standing? } }, lowest
-- skill first; a reputation pattern needs reaction `standing` with `faction`.
function Guide.VendorBuys(guide, learned, maxSkill)
    local out = {}
    for spell, r in pairs(guide.recipes) do
        local sold = r.src == "vendor" or (r.src == "reputation" and r.faction)
        if sold and r.pattern and r.npcs and not learned[spell] then
            out[#out + 1] = { name = r.name, npcs = r.npcs, item = r.pattern, skill = r.learn,
                              faction = r.faction, standing = r.standing, limited = r.limited }
        end
    end
    for _, rank in ipairs(guide.ranks or {}) do
        if rank.item and maxSkill <= rank.cap then
            out[#out + 1] = { name = rank.name, npcs = rank.npcs, item = rank.item, skill = rank.skill }
        end
    end
    table.sort(out, function(a, b)
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.item < b.item
    end)
    return out
end

-- What a row's waypoint points at (anything with `name` and `npcs`) and who that is
-- ("book vendor", "trainer", "quest giver" or "vendor"), or nil when the row has
-- nowhere to go. Rank rows, trainer visits and unlearned recipes have somewhere;
-- Guide rows and Queue entries alike.
local RANK_WHO = { trainer = "trainer", quest = "quest giver" }

function Guide.WaypointFor(row, prof)
    local target, who
    if row.rank then
        target, who = row.rank, RANK_WHO[row.rank.kind] or "book vendor"
    elseif row.train and row.train.pattern then
        local r = row.train.recipes[1]
        local gate = Guide.LearnGate(r, prof)
        if gate and not gate.early then return nil end
        target, who = r, "vendor"
    elseif row.train then
        target, who = Guide.VisitTarget(row.train), "trainer"
    elseif row.recipe and not row.learned then
        -- A recipe the player can't learn yet has no waypoint, unless its pattern is buyable early.
        local gate = Guide.LearnGate(row.recipe, prof)
        if gate and not gate.early then return nil end
        target, who = row.recipe, Guide.SourceWord(row.recipe) == "trainer" and "trainer" or "vendor"
    end
    if target and target.npcs and #target.npcs > 0 then return target, who end
    return nil
end

-- The guide that holds `recipe`: `prof.id`'s guide, else the one whose table has it.
local function guideOf(recipe, prof)
    local g = prof.id and CP.Guides and CP.Guides[prof.id]
    if g and g.recipes then return g end
    for _, other in pairs(CP.Guides or {}) do
        for _, r in pairs(other.recipes or {}) do
            if r == recipe then return other end
        end
    end
    return nil
end

-- The rank in `guide` that lifts a player capped at `max`: the lowest cap at or past it.
local function rankFor(guide, max)
    local best
    for _, rank in ipairs(guide and guide.ranks or {}) do
        if rank.cap >= max and (best == nil or rank.cap < best.cap) then best = rank end
    end
    return best
end

-- Button label and tip phrase for taking a rank: train it, read its book or do its quest.
local function rankStep(rank)
    if rank.kind == "trainer" then
        return "Train " .. rank.name, rank.name
    elseif rank.kind == "quest" then
        local quest = rank.quest or rank.name
        return "Do " .. quest, "the quest " .. quest
    end
    return "Read " .. rank.name, "the " .. rank.name
end

-- Whether the player can learn an unlearned recipe yet. `prof` is { skill, max, name? }.
-- Returns nil when nothing blocks it, else { label, tip, early }. `early` marks a vendor
-- pattern, which can be bought before the skill and so keeps its waypoint.
function Guide.LearnGate(recipe, prof)
    if not (recipe and prof and prof.skill) then return nil end
    local req = recipe.learn or 0
    local name = prof.name and (" " .. prof.name) or ""
    if recipe.src == "vendor" or recipe.src == "reputation" then
        if req > prof.skill then
            return { label = "Buy pattern", early = true,
                     tip = ("Learnable at%s %d. The pattern can be bought now."):format(name, req) }
        end
        return nil
    end
    if req > prof.skill then
        local word = Guide.SourceWord(recipe)
        if word == "trainer" and prof.max and req > prof.max then
            local rank = rankFor(guideOf(recipe, prof), prof.max)
            if rank then
                local label, what = rankStep(rank)
                local detail = rank.kind == "quest" and ("%s, skill %d"):format(rank.name, rank.skill)
                    or ("skill %d"):format(rank.skill)
                return { label = label,
                         tip = ("Needs %s first (%s), then%s %d."):format(what, detail, name, req) }
            end
        end
        return { label = "At " .. req, tip = ("Learnable at%s %d"):format(name, req) }
    end
    local level = UnitLevel and UnitLevel("player") or nil
    if recipe.level and level and level < recipe.level and Guide.SourceWord(recipe) == "trainer" then
        return { label = "Level " .. recipe.level, tip = ("Needs character level %d"):format(recipe.level) }
    end
    return nil
end

-- One word for where an unlearned recipe comes from: "trainer", "quest" or "pattern".
function Guide.SourceWord(recipe)
    -- An "auto" recipe the player lacks comes with training the profession's rank.
    if recipe.src == "trainer" or recipe.src == "specialization" or recipe.src == "auto" then return "trainer" end
    if recipe.src == "quest" then return "quest" end
    if recipe.src == "favor" then return "favor" end
    if recipe.src == "seasonal" then return "seasonal" end
    return "pattern"
end

-- One line saying how to learn a recipe that isn't known yet. Forever's new recipes
-- carry GUIDZ's own line (`how`): where a blueprint drops, which favor vendor sells it.
-- With `guide`, what else it needs follows (faction standing, a rank quest).
function Guide.LearnText(recipe, guide)
    local text
    if recipe.how and recipe.src ~= "trainer" then
        text = (recipe.how:gsub(": drops from", " drops from"))
    elseif recipe.src == "vendor" then
        text = ("Buy the pattern from a vendor (skill %d)"):format(recipe.learn)
    elseif recipe.src == "auto" then
        return "Learned with the profession"
    elseif recipe.src == "reputation" then
        text = ("Buy the pattern from a reputation vendor (skill %d)"):format(recipe.learn)
    elseif recipe.src == "pattern" then
        text = ("Learn from a pattern (skill %d)"):format(recipe.learn)
    elseif recipe.src == "quest" then
        text = ("Learn from a quest (skill %d)"):format(recipe.learn)
    else
        text = ("Learn from a trainer (skill %d)"):format(recipe.learn)
    end
    local needs = Guide.Needs(guide, recipe)
    return needs and (text .. "  ·  " .. needs) or text
end

-- Empty-tab text for a profession with no crafting guide. Gathering professions have
-- their guide on the Guide tab.
function Guide.NoGuideText(p)
    for _, id in ipairs(p and (p.ids or { p.id }) or {}) do
        if CP.GatherGuide and CP.GatherGuide.Has(id) then
            return "Gathering has nothing to buy. See the Guide tab."
        end
    end
    return "No guide for this profession yet."
end
