local _, CP = ...
if CP.stopped then return end

-- Materials two of the player's guides both use, like cloth for Tailoring and First
-- Aid. Each guide's needs to 300 are saved per profession (Gather.SaveNeeds), so a
-- guide can say how much the others want of the same item and the player can gather
-- or buy for both at once.

local Shared = {}
CP.Shared = Shared

local SHORT = { [129] = "First Aid", [197] = "Tailoring", [165] = "Leatherworking", [164] = "Blacksmithing",
                [171] = "Alchemy", [202] = "Engineering", [333] = "Enchanting", [185] = "Cooking",
                [356] = "Fishing", [182] = "Herbalism", [186] = "Mining", [393] = "Skinning" }

-- A profession's name by skill line: "Alchemy".
function Shared.Name(line)
    local g = CP.Guides and CP.Guides[line]
    return SHORT[line] or (g and g.name) or tostring(line)
end

-- What the player's other guides need of `item` to 300: { { key, name, need } }, biggest first.
function Shared.Others(key, item)
    local out = {}
    for other, needs in pairs(CP.charDB and CP.charDB.gatherNeeds or {}) do
        local n = other ~= key and needs[item]
        if n and n > 0 then
            local g = CP.Guides and CP.Guides[other]
            out[#out + 1] = { key = other, name = SHORT[other] or (g and g.name) or "?", need = n }
        end
    end
    table.sort(out, function(a, b) return a.need > b.need end)
    return out
end

-- "+80 First Aid" (one other guide) or "+120 other guides", or nil.
function Shared.Tag(key, item)
    local others = Shared.Others(key, item)
    if #others == 0 then return nil end
    if #others == 1 then return ("+%d %s"):format(others[1].need, others[1].name) end
    local total = 0
    for _, o in ipairs(others) do total = total + o.need end
    return ("+%d other guides"):format(total)
end

-- The guide key of a `CP.Guides` table, or nil.
function Shared.KeyOf(guide)
    for key, g in pairs(CP.Guides or {}) do
        if g == guide then return key end
    end
end

-- Greens for Enchanting ------------------------------------------------------------

Shared.ENCHANTING = 333
local MIN_SHARE = 0.25  -- a credited craft still costs at least this share of its materials

-- True while the "Plan for Enchanting" setting (deEnchant) is on, as it is by default.
function Shared.ForEnchanting()
    return not (CP.db and CP.db.deEnchant == false)
end

-- Disenchant.Yield of a group, kept per data table: the yield is a pure function of the
-- group's rows, which are generated data. Read here only, never handed out.
local groupYields = setmetatable({}, { __mode = "k" })

local function yieldOf(group)
    local rows = CP.DisenchantData.groups[group]
    if not rows then return CP.Disenchant.Yield(group) end
    local y = groupYields[rows]
    if not y then
        y = CP.Disenchant.Yield(group)
        groupYields[rows] = y
    end
    return y
end

-- Materials one craft of `recipe` gives when disenchanted: { { item, count } }, or an
-- empty list when its item doesn't disenchant.
function Shared.DEYield(recipe)
    local group = recipe.makes and CP.DisenchantData and CP.DisenchantData.items[recipe.makes]
    if not group then return {} end
    local per = recipe.yield or 1
    local out = {}
    for _, y in ipairs(yieldOf(group)) do out[#out + 1] = { item = y.item, count = y.count * per } end
    return out
end

-- True when some recipe of `guide` makes an item that disenchants. Kept per guide.
local disenchants = setmetatable({}, { __mode = "k" })

function Shared.Disenchants(guide)
    local v = disenchants[guide]
    if v == nil then
        v = false
        for _, r in pairs(guide.recipes or {}) do
            if r.makes and CP.DisenchantData and CP.DisenchantData.items[r.makes] then v = true break end
        end
        disenchants[guide] = v
    end
    return v
end

-- Worth of disenchanting one craft of `recipe` for the Enchanting guide: materials it
-- still needs at steps its disenchant skill reaches, at `value(item, enchantingGuideItem)`.
-- Zero without Enchanting.
function Shared.DECredit(recipe, value, needs, steps)
    local guide = CP.Guides and CP.Guides[Shared.ENCHANTING]
    if not guide or not needs then return 0 end
    local group = recipe.makes and CP.DisenchantData and CP.DisenchantData.items[recipe.makes]
    local skill = group and CP.Disenchant.Skill(nil, nil, group) or 0
    local total = 0
    for _, y in ipairs(Shared.DEYield(recipe)) do
        -- What Enchanting's steps still need of this dust: those that end above `skill` when
        -- `steps` ({ [item] = { { to, need } } }) are known, else the flat needs.
        local want = needs[y.item] or 0
        if steps and steps[y.item] then
            want = 0
            for _, st in ipairs(steps[y.item]) do
                if st.to > skill then want = want + st.need end
            end
        end
        if want > 0 then
            total = total + y.count * (value(y.item, guide.items and guide.items[y.item]) or 0)
        end
    end
    return total
end

-- True when guide `guideKey` takes Enchanting's disenchant credit: the setting is on, the
-- player (`skills`, a set of skill lines) has Enchanting, and the guide is another one whose
-- products disenchant.
function Shared.Credits(guideKey, skills)
    if not Shared.ForEnchanting() or guideKey == nil or guideKey == Shared.ENCHANTING then return false end
    if not (skills ~= nil and skills[Shared.ENCHANTING] ~= nil and skills[Shared.ENCHANTING] ~= false) then return false end
    local guide = CP.Guides and CP.Guides[guideKey]
    return guide ~= nil and Shared.Disenchants(guide)
end

-- Enchanting's needs to 300 as its plan stands now (Plan.Shut's peek), not as last saved, so
-- every guide's credit reads the same needs whichever profession was solved first, and reading
-- them saves nothing of Enchanting's. The needs are net of what bags, bank and mail hold
-- (Purchases.Have), so stock the player already has earns no credit. Returns the needs ({ [item] = count }, or nil for none),
-- their signature (a string), the professions that shaped Enchanting's plan (Plan's
-- `shapedBy`) and the same needs by step (`{ [item] = { { to, need } } }`: the step's end skill and
-- what it still needs after stock); nil without an Enchanting plan. Kept per Enchanting plan: Plan.Shut hands back
-- the same table until its inputs change.
local fromPlan = setmetatable({}, { __mode = "k" })

-- The per-step needs of each table EnchantingNeeds handed out, for CreditFor to find.
local stepsOf = setmetatable({}, { __mode = "k" })

function Shared.EnchantingNeeds()
    local live = CP.Plan and CP.Plan.Shut(Shared.ENCHANTING, true)
    if not (live and live.guide and live.plan) then return nil end
    local hit = fromPlan[live]
    if not hit then
        local guide, p, Q = live.guide, live.prof, CP.Queue
        local target, byItem = Q.End(guide), {}
        if target > p.skill then
            for _, e in ipairs(Q.Build(guide, p.skill, p.max, target, live.plan, live.learned)) do
                if e.kind == "craft" then
                    for _, pair in ipairs(e.recipe.reagents) do
                        local list = byItem[pair[1]] or {}
                        byItem[pair[1]] = list
                        list[#list + 1] = { to = e.to, need = pair[2] * e.crafts }
                    end
                end
            end
        end
        hit = { gross = CP.Gather.NeedsTo(live, target), steps = byItem, shapedBy = live.shapedBy }
        fromPlan[live] = hit
    end
    local needs, items, steps = nil, {}, {}
    for item, n in pairs(hit.gross or {}) do
        local owed = n - CP.Purchases.Have(item)
        if owed > 0 then
            needs = needs or {}
            needs[item] = owed
            items[#items + 1] = item .. "x" .. owed
            -- Stock covers the earliest steps first.
            local left, list, sum = n - owed, {}, 0
            for _, st in ipairs(hit.steps[item] or {}) do
                local take = math.min(left, st.need)
                left = left - take
                if st.need > take then
                    list[#list + 1] = { to = st.to, need = st.need - take }
                    sum = sum + st.need - take
                end
            end
            if sum == owed then steps[item] = list end
        end
    end
    table.sort(items)
    if needs then stepsOf[needs] = steps end
    return needs, table.concat(items, ","), hit.shapedBy, steps
end

-- Solver option for a guide other than Enchanting when the player has Enchanting:
-- lowers a craft's cost by what disenchanting it saves the Enchanting guide, never
-- below MIN_SHARE of its cost. Level-as-you-go counts the world effort of the
-- materials (field 4, not the craft route, which would count the craft twice);
-- Buy-and-power-level counts their auction price. Make one per solve: it keeps each
-- recipe's credit, which depends on the recipe alone while the solve runs. `needs` and
-- `steps` are Enchanting's (Shared.EnchantingNeeds when nil); a recipe's dust counts only
-- toward steps its disenchant skill reaches, and toward every step without `steps`. Nil while the setting is off.
function Shared.CreditFor(guideKey, collect, skills, needs, steps)
    if not Shared.Credits(guideKey, skills) then return nil end
    if not needs then needs, _, _, steps = Shared.EnchantingNeeds() end
    if not needs then return nil end
    steps = steps or stepsOf[needs]
    local prices = {}
    local value = collect
        and function(_, info) return info and info[4] or 1 end
        or function(item)
            local p = prices[item]
            if p == nil then
                p = CP.Pricing.Auction(item) or false
                prices[item] = p
            end
            return p or nil
        end
    local credits = {}
    return function(_, recipe, cost)
        local credit = credits[recipe]
        if not credit then
            credit = Shared.DECredit(recipe, value, needs, steps)
            credits[recipe] = credit
        end
        if credit <= 0 then return cost end
        return math.max(cost * MIN_SHARE, cost - credit)
    end
end

-- A disenchant yield (crafts x expected count) as a whole number, rounded to the nearest. Every
-- surface that shows dust from disenchanting calls this one rounding.
function Shared.DERound(n)
    return math.floor(n + 0.5)
end

-- Enchanting materials the player's other guides will make by disenchanting their planned
-- greens, counted from the plan each guide shows (Plan.Committed), its current step counted
-- down by the crafts made of it (Plan.StepCrafts), so dust already in the bags is not counted
-- again; with no committed plan, from its last solve. Returns the count of `item`, the names
-- of the guides that give any, and the same split by when (Shared.DEIncomingSplit).
-- `skill` is the Enchanting skill the dust is wanted by (default: the end of Enchanting's current
-- step); a green whose disenchant needs more than that gives none yet. None while the setting is off.
function Shared.DEIncoming(item, skill)
    local out = { now = 0, later = 0, names = {} }
    if not Shared.ForEnchanting() then return 0, out.names, out end
    local bestNow, bestLater = 0, 0
    if skill == nil then
        local ec = CP.Plan.Committed(Shared.ENCHANTING)
        local cur = ec and ec.steps and ec.steps[ec.current or 1]
        skill = cur and cur[2]
    end
    local keys = {}
    for key in pairs(CP.charDB and CP.charDB.lastPlan or {}) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, name in ipairs(keys) do
        local key = tonumber(name) or name
        local guide = key ~= Shared.ENCHANTING and CP.Guides and CP.Guides[key]
        if guide then
            local steps = {}
            local c = CP.Plan.Committed(key)
            if c and c.steps then
                for i = c.current or (#c.steps + 1), #c.steps do
                    local f = c.steps[i]
                    local st = { f[1], f[2], f[3] }
                    if #steps == 0 then
                        local r = guide.recipes[f[3]]
                        local full = f[9] or f[5]
                        if not full and r then full = CP.Guide.Crafts(r, math.max(f[1], c.skill or f[1]), f[2]) end
                        if full and full < math.huge then st[4] = math.max(1, full - (c.made or 0)) end
                    end
                    steps[#steps + 1] = st
                end
            else
                for i, st in ipairs(CP.charDB.lastPlan[key]) do steps[i] = { st[1], st[2], st[3] } end
            end
            local laterFirst, total = false, 0
            for i, st in ipairs(steps) do
                local r = guide.recipes[st[3]]
                local crafts = r and (st[4] or CP.Guide.Crafts(r, st[1], st[2])) or math.huge
                local n = 0
                local group = r and r.makes and CP.DisenchantData.items[r.makes]
                local need = group and CP.Disenchant.Skill(nil, nil, group)
                local reached = not (skill and need) or need < skill
                for _, y in ipairs(reached and crafts < math.huge and Shared.DEYield(r) or {}) do
                    if y.item == item then n = n + y.count * crafts end
                end
                total = total + n
                local step = r and { guide = SHORT[key] or guide.name, recipe = r.name, from = st[1], to = st[2] }
                if i == 1 then
                    out.now = out.now + n
                    if n > bestNow then bestNow, out.nowStep = n, step end
                elseif n > 0 then
                    out.later = out.later + n
                    if not laterFirst then
                        laterFirst = true
                        if n > bestLater or not out.laterStep then bestLater, out.laterStep = n, step end
                    end
                end
            end
            if total > 0 then out.names[#out.names + 1] = SHORT[key] or guide.name end
        end
    end
    out.now, out.later = Shared.DERound(out.now), Shared.DERound(out.later)
    return out.now + out.later, out.names, out
end

-- What the other guides' disenchanting gives of `item`, split by when (tester, 2026-11-18:
-- "I need 19 more [Strange Dust]. But tailoring only shows make 2 more"): `now` from each
-- guide's current step, `later` from its later steps. { now, later, nowStep, laterStep, names },
-- each step { guide, recipe, from, to } where it gives the most. Counts are rounded to the nearest.
function Shared.DEIncomingSplit(item, skill)
    local _, _, split = Shared.DEIncoming(item, skill)
    return split
end
