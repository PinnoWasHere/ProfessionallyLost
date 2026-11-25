local _, CP = ...
if CP.stopped then return end

-- Disenchanting as a source of Enchanting skill-ups. Disenchant sits on Enchanting's skill line
-- in the client data and earns points like a craft, so the Enchanting guide plans the greens the
-- player can disenchant as a step of their own, ahead of the crafts that cost materials. The
-- greens are the bags' (not ignored, not worth more sold) and those another guide's current step
-- makes for Enchanting's dust. The step reads as a guide recipe (Deskill.Install) that no solve
-- picks on its own: Plan places it through Solver.Plan's `opts.fixed`.
--
-- A green is used only when disenchanting it costs less than crafting its points. Disenchanting
-- costs the green's vendor sale value less what its dust and essence are worth (`net`). The
-- alternative costs the points the green is expected to give at the player's skill (the
-- disenchant chance) times the cheapest craft's cost per point there. Early on that craft is
-- Enchant Bracer - Inferior Stamina at one Mote of Magic (10c) a point, so only a green that
-- sells for little is worth disenchanting.

local Deskill = {}
CP.Deskill = Deskill

Deskill.SPELL = 13262
Deskill.ENCHANTING = 333
Deskill.QUALITY = 2   -- greens

-- Disenchant on Enchanting's skill line: Forever's SkillLineAbility row 7316 (learned with the
-- profession at 1, TrivialSkillLineRankLow 20, TrivialSkillLineRankHigh 60, NumSkillUps 1).
Deskill.RECIPE = { name = "Disenchant", src = "deskill", deskill = true, learn = 1, yellow = 20, grey = 60, ups = 1,
                   reagents = {} }

Deskill.NAME = "Disenchant greens"
Deskill.CARD = "Disenchant %d %s; the Disenchant tab lists them"
Deskill.CARD_FROM = "Disenchant %d %s: %d in your bags, %s"
Deskill.FROM = "%d from %s's crafts"
Deskill.GIVES = "Gives ~%s"
Deskill.SKIPPED = "%s sell for more than crafting these points costs"
Deskill.SKIPPED_ONE = "1 green sells for more than crafting these points costs"

local function greens(n) return n == 1 and "green" or "greens" end

-- "12 greens"
function Deskill.Count(n) return ("%d %s"):format(n, greens(n)) end

-- "Disenchant 12 greens; the Disenchant tab lists them", or where they come from when another
-- guide's step makes some: "Disenchant 30 greens: 8 in your bags, 22 from Leatherworking's crafts".
function Deskill.CardText(n, supply)
    local text = Deskill.CardBody(n, supply or Deskill.Chosen())
    local skipped = Deskill.Skipped()
    if skipped == 0 then return text end
    return text .. "\n" .. (skipped == 1 and Deskill.SKIPPED_ONE or Deskill.SKIPPED:format(Deskill.Count(skipped)))
end

function Deskill.CardBody(n, supply)
    local bags, from, names = 0, {}, {}
    for k = 1, math.min(n, #supply) do
        local who = supply[k].from
        if who then
            if not from[who] then names[#names + 1] = who end
            from[who] = (from[who] or 0) + 1
        else
            bags = bags + 1
        end
    end
    if #names == 0 then return Deskill.CARD:format(n, greens(n)) end
    local parts = {}
    for i, who in ipairs(names) do parts[i] = Deskill.FROM:format(from[who], who) end
    return Deskill.CARD_FROM:format(n, greens(n), bags, table.concat(parts, ", "))
end

-- True for the guide recipe of a disenchant step.
function Deskill.Is(r) return r ~= nil and r.deskill == true end

-- Puts the step's recipe under the Enchanting guide's recipes by id only: a lookup finds it, and
-- pairs() over the recipes, which every solve and check walks, never sees it.
function Deskill.Install()
    local guide = CP.Guides and CP.Guides[Deskill.ENCHANTING]
    if not guide or not guide.recipes then return end
    local mt = getmetatable(guide.recipes)
    if mt and mt.deskill then return end
    setmetatable(guide.recipes, { deskill = true, __index = { [Deskill.SPELL] = Deskill.RECIPE } })
end

-- Supply --------------------------------------------------------------------------------------

-- The current saved step of each other guide that takes Enchanting's credit and makes greens that
-- disenchant: { { key, step, recipe, committed } }. Reads saved plans only, never a solve, since
-- Enchanting's own plan cache reads this.
local function pairedSteps()
    local out = {}
    if not (CP.Shared.ForEnchanting() and CP.Plan and CP.Plan.Committed) then return out end
    local skills = CP.Sourcing.PlayerSkills()
    local keys = {}
    for key in pairs(CP.Guides or {}) do
        if key ~= Deskill.ENCHANTING then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local c = CP.Shared.Credits(key, skills) and CP.Plan.Committed(key)
        local f = c and c.steps and c.steps[c.current or 1]
        local r = f and CP.Guides[key].recipes[f[3]]
        if r and r.makes and CP.DisenchantData.items[r.makes] then
            out[#out + 1] = { key = key, step = f, recipe = r, committed = c }
        end
    end
    return out
end

-- Gear in the bags a paired step made for the dust: { [item] = count }, as Disenchant.Queue's
-- `planned`. Such gear is never told "sell".
local function madeForDust(paired)
    local out = {}
    for _, ps in ipairs(paired) do
        local made = math.min(ps.committed.made or 0, ps.step[9] or 0)
        if made > 0 then out[ps.recipe.makes] = (out[ps.recipe.makes] or 0) + made * (ps.recipe.yield or 1) end
    end
    return out
end

-- Greens a paired step still makes: { { need, group, from } }, one entry a green. The item must be
-- loaded for its disenchant skill.
local function coming(out, paired)
    for _, ps in ipairs(paired) do
        local f, c, r = ps.step, ps.committed, ps.recipe
        local group = CP.DisenchantData.items[r.makes]
        local _, _, quality, ilvl = C_Item.GetItemInfo(r.makes)
        local need = quality == Deskill.QUALITY and ilvl and CP.Disenchant.Skill(ilvl, quality)
        local left = math.floor(((f[9] or f[5] or 0) - (c.made or 0)) * (r.yield or 1))
        if need then
            local sale = select(11, C_Item.GetItemInfo(r.makes)) or 0
            local net = sale - (CP.Disenchant.Value(group, CP.Pricing.Auction) or 0)
            for _ = 1, left do
                out[#out + 1] = { need = need, group = group, net = net, from = CP.Shared.Name(ps.key) }
            end
        elseif not quality then
            CP.RequestItem(r.makes)
        end
    end
end

-- The greens there are to disenchant for points: { { need, group, from? } }, lowest skill first,
-- bags before another guide's. Read again each new frame and after each bag change.
local cache = { time = nil, db = nil, list = nil }

local function clear() cache.list = nil end
CP:On("BAG_UPDATE_DELAYED", clear)

function Deskill.Supply()
    local now = GetTime()
    if cache.list and cache.time == now and cache.db == CP.charDB then return cache.list end
    local list = {}
    local DE = CP.Disenchant
    local ignored = CP.charDB and CP.charDB.deIgnore or {}
    local paired = pairedSteps()
    local planned = madeForDust(paired)
    local queue = DE.Queue(DE.Bags(), Deskill.RECIPE.grey, ignored, CP.Pricing.Auction, CP.Pricing.Auction,
        nil, false, planned)
    for _, it in ipairs(queue) do
        if it.quality == Deskill.QUALITY and it.advice.verdict ~= "sell" then
            list[#list + 1] = { need = it.need, group = it.group, net = (it.vendor or 0) - (it.advice.de or 0) }
        end
    end
    coming(list, paired)
    for i, g in ipairs(list) do g.order = i end
    table.sort(list, function(a, b)
        if a.need ~= b.need then return a.need < b.need end
        return a.order < b.order
    end)
    cache.time, cache.db, cache.list = now, CP.charDB, list
    return list
end

-- The supply as a string, for the plan caches.
function Deskill.Key()
    local parts = {}
    for i, g in ipairs(Deskill.Supply()) do parts[i] = g.need .. ":" .. g.group .. ":" .. g.net end
    return table.concat(parts, ",")
end

-- The cheapest craft's cost per skill point at `skill`, in copper: one craft's materials over its
-- chance, among the recipes the player gets with the profession or from the trainer.
local function craftPerPoint(skill)
    local guide = CP.Guides and CP.Guides[Deskill.ENCHANTING]
    if not guide then return math.huge end
    local best = math.huge
    for _, r in pairs(guide.recipes) do
        if (r.src == "auto" or r.src == "trainer") and not r.makes and #r.reagents > 0 and (r.learn or 0) <= skill then
            local chance = CP.Guide.Chance(r, skill)
            if chance > 0 then
                best = math.min(best, (CP.Solver.CraftCost(guide, r, CP.Pricing.Get)) / chance)
            end
        end
    end
    return best
end

-- What the last plan chose: the greens used in order, and how many it left out for their price.
local last = { chosen = nil, skipped = 0 }

-- The skill the supply takes the player to from `skill`, never past `max`, the greens used, how
-- many were left out for selling above the craft cost, and the greens used in order. Each green is
-- one disenchant, played point by point with the crafts' chance (Solver.Play). A green joins once
-- the skill reaches what it needs, the one with the lowest `net` first, and the step ends when even
-- that one costs more than crafting the point.
function Deskill.Reach(skill, max, supply)
    supply = supply or Deskill.Supply()
    local r = Deskill.RECIPE
    local top = math.min(max or r.grey, r.grey)
    local x, i, pool, chosen, priced = skill, 1, {}, {}, false
    local cost = {}
    local function perPoint(s)
        if not cost[s] then cost[s] = craftPerPoint(s) end
        return cost[s]
    end
    while math.floor(x + 1e-9) < top do
        local s = math.floor(x + 1e-9)
        while supply[i] and supply[i].need <= s do
            pool[#pool + 1] = supply[i]
            i = i + 1
        end
        local chance = CP.Guide.Chance(r, s)
        if #pool == 0 or chance <= 0 then break end
        local pick = 1
        for k = 2, #pool do
            if pool[k].net < pool[pick].net then pick = k end
        end
        if pool[pick].net > chance * perPoint(s) then
            priced = true
            break
        end
        chosen[#chosen + 1] = table.remove(pool, pick)
        x = CP.Solver.Play(r, x, 1)
    end
    local skipped = 0
    if priced then
        local at = math.floor(x + 1e-9)
        local worth = CP.Guide.Chance(r, at) * perPoint(at)
        skipped = #pool
        for k = i, #supply do
            if supply[k].net > worth then skipped = skipped + 1 end
        end
    end
    return math.min(math.floor(x + 1e-9), top), #chosen, skipped, chosen
end

-- The greens the last plan uses, in order; the whole supply before any plan.
function Deskill.Chosen() return last.chosen or Deskill.Supply() end

-- How many greens the last plan left out for their sale value.
function Deskill.Skipped() return last.skipped end

-- What disenchanting the first `n` greens of the plan gives: { [item] = expected count }.
function Deskill.Gives(n, supply)
    supply = supply or Deskill.Chosen()
    local out = {}
    for k = 1, math.min(n, #supply) do
        for _, y in ipairs(CP.Disenchant.Yield(supply[k].group)) do out[y.item] = (out[y.item] or 0) + y.count end
    end
    return out
end

-- "Gives ~14 Strange Dust, ~4 Lesser Magic Essence", the likeliest first; nil for nothing.
function Deskill.GivesText(n, nameOf)
    local list = {}
    for item, count in pairs(Deskill.Gives(n)) do
        local k = CP.Shared.DERound(count)
        if k > 0 then list[#list + 1] = { item = item, count = k } end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.item < b.item
    end)
    local parts = {}
    for i, g in ipairs(list) do parts[i] = ("%d %s"):format(g.count, nameOf(g.item)) end
    return Deskill.GIVES:format(table.concat(parts, ", ~"))
end

-- Plan ----------------------------------------------------------------------------------------

-- Fixes the points the greens cover to the disenchant step, in Solver.Plan's `fixed` and `cuts`
-- (made when nil). `locked` lists { from, to } of the steps the player holds. The step takes the
-- first stretch from `p.skill` that no locked step covers and the greens reach into, so it never
-- shortens a locked step. Returns them and the step's end, nil without a step.
function Deskill.Fix(guide, p, fixed, cuts, locked)
    if not (CP.Guides and guide == CP.Guides[Deskill.ENCHANTING]) then return fixed, cuts, nil end
    Deskill.Install()
    local spans = {}
    for _, l in ipairs(locked or {}) do spans[#spans + 1] = l end
    table.sort(spans, function(a, b) return a[1] < b[1] end)
    local top = p.max or Deskill.RECIPE.grey
    local start, to, k = p.skill, p.skill, 1
    last.chosen, last.skipped = {}, 0
    while start < top do
        while spans[k] and spans[k][2] <= start do k = k + 1 end
        if spans[k] and spans[k][1] <= start then
            start = spans[k][2]
        else
            local limit = spans[k] and math.min(spans[k][1], top) or top
            local reached, _, skipped, chosen = Deskill.Reach(start, limit)
            last.chosen, last.skipped = chosen, skipped
            to = reached
            if to > start or not spans[k] then break end
            start = spans[k][2]
        end
    end
    if to <= start then return fixed, cuts, nil end
    fixed, cuts = fixed or {}, cuts or {}
    for s = start, to - 1 do fixed[s] = Deskill.SPELL end
    cuts[start], cuts[to] = true, true
    return fixed, cuts, to
end
