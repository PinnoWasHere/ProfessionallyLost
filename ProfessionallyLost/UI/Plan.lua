local _, CP = ...
if CP.stopped then return end

-- The live plan for the open profession, shared by the Guide and Shop tabs.

local Prof = CP.Professions
local Plan = {}
CP.Plan = Plan

local ALTERNATIVES = 3

CP.Deskill.Install()

-- Level-as-you-go never weighs materials by auction price; Buy-and-power-level does.
-- Each solve gets its own price function, so it reads the player's skills once.
local function priceFor()
    return CP.db.collect and CP.Pricing.CollectFn() or CP.Pricing.Get
end

-- Sourcing's filter, minus limited patterns a vendor visit showed sold out.
-- `dead` (optional): guide recipes the game says give no points now (see Plan.Dead).
local COOKING = 185

local function usesFish(guide, r)
    for _, pair in ipairs(r.reagents) do
        if CP.Sourcing.GatherSkill(guide, pair[1]) == CP.Gather.FISHING then return true end
    end
    return false
end
Plan.UsesFish = usesFish

-- usesFish for `guide`, each recipe's answer kept for the function's life, one solve.
local function fishTest(guide)
    local seen = {}
    return function(r)
        local v = seen[r]
        if v == nil then
            v = usesFish(guide, r)
            seen[r] = v
        end
        return v
    end
end

-- Level-as-you-go keeps fish off the main path (Blackmouth Oil shows as an "or" row):
-- fishing is a detour from the profession. Cooking is the exception, where Fishing and
-- Cooking pair up (the fishCook setting).
local function fishAside(guide)
    return CP.db.collect and CP.Shared.KeyOf(guide) ~= COOKING
end

-- The skills a guide plans with under "Gather it yourself": the player's, without Fishing
-- for Cooking while "Fish for Cooking" is off, so Cooking then plans as without Fishing.
local function skillsFor(guide)
    local skills = CP.Sourcing.PlayerSkills()
    if skills[CP.Gather.FISHING] and CP.Shared.KeyOf(guide) == COOKING and not CP.Settings.FishCook() then
        skills[CP.Gather.FISHING] = nil
    end
    return skills
end
Plan.SkillsFor = skillsFor

-- `withFish` lets fish recipes through for the "or" rows. `skills` (default: skillsFor)
-- are the professions whose materials count as gettable.
local function allowFor(guide, learned, dead, withFish, skills)
    local collect = CP.db.collect
    local allow = CP.Sourcing.Filter(guide, learned, collect, collect and (skills or skillsFor(guide)) or nil,
        collect and CP.Sourcing.PlayerReach() or nil)
    local noFish = not withFish and fishAside(guide) and fishTest(guide)
    return function(id, r)
        if dead and dead[id] then return false end
        if noFish and noFish(r) then return false end
        -- Level-as-you-go: a dropped pattern (Wizardweave Turban, 2% from Dark Casters)
        -- leads only once learned; until then it only fills points nothing else covers
        -- (fillGaps). Buy-and-power-level can buy the pattern, so it stays a candidate.
        if CP.db.collect and r.src == "pattern" and not learned[id] then return false end
        if r.limited and r.pattern and not learned[id] and CP.VendorWatch and CP.VendorWatch.IsSoldOut(r.pattern) then
            return false
        end
        return not allow or allow(id, r)
    end
end

-- A maker the player can craft (Solver.Plan's `opts.maker`): allowFor without "Gather it yourself",
-- since a material the plan asks to make is made whatever its own materials take. Grey in the game,
-- an unlearned dropped or sold-out pattern, or a recipe the player can't learn stays out.
local function makerAllow(guide, learned, dead)
    local side = CP.Sourcing.Side()
    return function(id, r)
        if dead and dead[id] then return false end
        if learned[id] then return true end
        if CP.db.collect and r.src == "pattern" then return false end
        if r.limited and r.pattern and CP.VendorWatch and CP.VendorWatch.IsSoldOut(r.pattern) then return false end
        return CP.Sourcing.CanLearn(guide, id, r, learned, side)
    end
end

-- Crafted gear, prep materials and rare byproducts (hides) the player holds, bags and
-- bank and mail (as the Shop counts): the supply later steps draw on before anything is made.
function Plan.Held(guide)
    local held = {}
    local function count(item)
        local n = CP.Purchases.Have(item)
        if n and n > 0 then held[item] = n end
    end
    for _, set in ipairs({ guide.craftOnly or {}, guide.prep or {} }) do
        for item in pairs(set) do count(item) end
    end
    for item, info in pairs(guide.items or {}) do
        if info[5] then count(item) end
    end
    return held
end

-- A pattern sold only at a faction standing the game shows the player lacks, or a recipe whose
-- trainers teach only a specialization the player lacks (`spec`). One whose standing can't be
-- read stays in, and its step names the standing it needs.
function Plan.Locked(_, r)
    if r.spec and not Prof.Holds(r.spec) then return true end
    return r.faction ~= nil and CP.Guide.HasStanding(r) == false
end

-- Level-as-you-go plans rare byproducts only as far as the bags go. With Enchanting
-- too, crafts whose greens disenchant into what the Enchanting guide needs cost less. The
-- credit reads Enchanting's current plan (Shared.EnchantingNeeds); `deNeeds` and `deShapedBy`
-- keep what it read.
local function solverOpts(guide)
    local fish = fishAside(guide) and fishTest(guide)
    local key, skills = CP.Shared.KeyOf(guide), CP.Sourcing.PlayerSkills()
    local needs, by
    if CP.Shared.Credits(key, skills) then
        local n, _, b = CP.Shared.EnchantingNeeds()
        needs, by = n, b
    end
    return { rareFromStock = CP.db.collect, fees = not CP.db.collect, fillGaps = CP.db.collect,
             credit = needs and CP.Shared.CreditFor(key, CP.db.collect, skills, needs) or nil,
             deNeeds = needs, deShapedBy = by,
             lastResort = fish and function(_, r) return fish(r) end or nil,
             locked = Plan.Locked }
end

-- Couplings ---------------------------------------------------------------------
-- Another profession changes a guide three ways: Enchanting's disenchant credit ("Plan for
-- Enchanting"), materials another profession makes, gathers or Fishing catches counting as
-- gettable under "Gather it yourself" (Fishing for Cooking only while "Fish for Cooking" is on), and
-- Enchanting materials priced lower while the player crafts greens that disenchant into
-- them. When one of them picked a step, the solver plans the guide again without them in
-- the same call (Solver.Plan's `opts.plain`), and the rows that differ name the cause.

local BIG = 1e9

-- Prices as the character without the coupling professions (`solo`) would weigh them.
local function soloPrice(solo)
    return function(item, info)
        local effort, how = CP.Pricing.GetCollect(item, info, solo)
        if how ~= "fishing" then return effort, how end
        -- No Fishing: a fish costs its own effort.
        effort = CP.Pricing.Effort(info)
        for line, e in pairs(info and info[6] or {}) do
            if solo[line] and e < effort then effort = e end
        end
        return effort, "collect"
    end
end

-- The world without couplings for one solve of `guide`, as Solver.Plan's `opts.plain`, with
-- `causes(id, recipe)`: the profession lines that let the recipe in or cheapen it, `de`
-- when the Enchanting credit does, and `via` = { { item, line, how } } with how "makes"
-- (another profession makes the material), "gathers" (Herbalism, Mining or Skinning),
-- "fish" or "greens" (its greens disenchant into it). `shapedByDE` lists the professions that
-- shaped Enchanting's plan. Nil when nothing can couple.
local function plainWorld(guide, learned, dead, allow, credit, price, shapedByDE)
    local real = CP.db.collect and skillsFor(guide) or nil
    local solo = real and CP.Sourcing.Solo(real, CP.Shared.KeyOf(guide))
    local differs = credit ~= nil
    for line in pairs(real or {}) do
        if not solo[line] then differs = true end
    end
    if not differs then return nil end
    local plainAllow = real and allowFor(guide, learned, dead, false, solo) or allow
    local plainPrice = real and soloPrice(solo) or price
    local reach = real and CP.Sourcing.PlayerReach()
    local key = CP.Shared.KeyOf(guide)
    local shaped = {}
    for _, line in ipairs(credit and shapedByDE or {}) do
        if line ~= key then shaped[#shaped + 1] = line end
    end
    local memo = {}
    local function causes(id, r)
        local out = memo[r]
        if out then return out end
        out = {}
        local seen = {}
        local function add(line, item, how)
            if not seen[line] then
                seen[line] = true
                out[#out + 1] = line
            end
            if item then
                out.via = out.via or {}
                out.via[#out.via + 1] = { item = item, line = line, how = how }
            end
        end
        if credit and credit(id, r, BIG) < BIG then
            out.de = true
            add(CP.Shared.ENCHANTING)
            -- The credit reads Enchanting's needs, so what shaped them shaped this too.
            for _, line in ipairs(shaped) do add(line) end
        end
        if real then
            local admitted = allow(id, r) and not plainAllow(id, r)
            for _, pair in ipairs(r.reagents) do
                local item = pair[1]
                local info = guide.items and guide.items[item]
                if admitted then
                    for _, line in ipairs(CP.Sourcing.GotThrough(guide, item, real, solo, reach)) do
                        add(line, item, line == CP.Gather.FISHING and "fish"
                            or CP.Sourcing.IsGathering(line) and "gathers" or "makes")
                    end
                end
                local a, b = price(item, info), plainPrice(item, info)
                if a and b and a < b then
                    if CP.Pricing.IsFish(item) and real[CP.Gather.FISHING] then add(CP.Gather.FISHING, item, "fish") end
                    local greens = {}
                    for line in pairs(info and info[6] or {}) do
                        if real[line] and not solo[line] then greens[#greens + 1] = line end
                    end
                    table.sort(greens)
                    for _, line in ipairs(greens) do add(line, item, "greens") end
                end
            end
        end
        memo[r] = out
        return out
    end
    return { allow = plainAllow, price = plainPrice, causes = causes,
             touched = function(id, r) return #causes(id, r) > 0 end }
end

-- The other professions whose couplings changed `plan` from `plain`, the plan without them:
-- every line a step's causes name, once any step differs. Nil when none changed it.
local function shapedBy(guide, plan, plain, causes)
    if not (plain and causes) then return nil end
    local count = {}
    for _, st in ipairs(plain) do
        if st.spell then
            local k = st.spell .. ":" .. st.from .. ":" .. st.to
            count[k] = (count[k] or 0) + 1
        end
    end
    local differs = false
    for _, st in ipairs(plan) do
        if st.spell then
            local k = st.spell .. ":" .. st.from .. ":" .. st.to
            if (count[k] or 0) > 0 then count[k] = count[k] - 1 else differs = true end
        end
    end
    if not differs then return nil end
    local out, seen = {}, {}
    for _, st in ipairs(plan) do
        for _, line in ipairs(st.spell and causes(st.spell, guide.recipes[st.spell]) or {}) do
            if not seen[line] then
                seen[line] = true
                out[#out + 1] = line
            end
        end
    end
    return #out > 0 and out or nil
end

-- `held` without rare byproducts: the main path never leans on hides, so it doesn't
-- move as hides turn up. Crafts that use them show as side rows instead.
function Plan.WithoutRare(guide, held)
    local out = {}
    for item, n in pairs(held) do
        local info = guide.items and guide.items[item]
        if not (info and info[5]) then out[item] = n end
    end
    return out
end

-- Side crafts: recipes that use rare byproducts the player holds (Cured Heavy Hide from
-- Heavy Hides in the bags) and give skill-ups over a main step's range, so they can be
-- done instead of it at the same time. Only recipes the player already knows (never a
-- pattern still to buy), only when the bags cover at least one craft, only while the
-- recipe is orange or yellow at the step's start, and each recipe once, under the first
-- step it fits. Returns { [step index] = { spell, recipe, learned, crafts, rareFor, upto } };
-- `crafts` is how many the held materials cover, capped at the crafts the range needs up
-- to where the recipe turns green (`upto`, nil when it stays yellow through the step).
-- Candidates with the same chance go to the lowest spell id.
function Plan.Sides(guide, steps, learned, held, allow)
    if not CP.db.collect then return {} end
    local pool, out, offered = {}, {}, {}
    for item, n in pairs(held) do pool[item] = n end
    for i, st in ipairs(steps) do
        local main = st.spell and guide.recipes[st.spell]
        if main and main.deskill then main = nil end
        local best, bestP, bestRare
        for id, r in pairs(guide.recipes) do
            if main and id ~= st.spell and not offered[id] and learned[id]
                and (not allow or allow(id, r)) then
                local rareItems, covered = {}, true
                for _, pair in ipairs(r.reagents) do
                    local info = guide.items and guide.items[pair[1]]
                    if info and info[5] then
                        rareItems[#rareItems + 1] = pair
                        if (pool[pair[1]] or 0) < pair[2] then covered = false end
                    end
                end
                local p = CP.Guide.Chance(r, st.from)
                if #rareItems > 0 and covered and p > 0 and not CP.Solver.IsGreen(r, st.from)
                    and (not bestP or p > bestP or (p == bestP and id < best)) then
                    best, bestP, bestRare = id, p, rareItems
                end
            end
        end
        if best then
            local r = guide.recipes[best]
            local n = math.huge
            for _, pair in ipairs(bestRare) do n = math.min(n, math.floor((pool[pair[1]] or 0) / pair[2])) end
            local upto = math.min(st.to, CP.Solver.GreenFrom(r))
            n = math.min(n, CP.Guide.Crafts(r, st.from, upto))
            for _, pair in ipairs(bestRare) do pool[pair[1]] = (pool[pair[1]] or 0) - n * pair[2] end
            offered[best] = true
            out[i] = { spell = best, recipe = r, learned = learned[best] == true, crafts = n, rareFor = bestRare[1][1],
                       upto = upto < st.to and upto or nil }
        end
    end
    return out
end

-- A plan as saved: { { from, to, spell, since } }, only steps with a recipe. `since` is
-- where a step under way began (Solver.Plan), else nil.
function Plan.Pack(steps)
    local out = {}
    for _, st in ipairs(steps or {}) do
        if st.spell then out[#out + 1] = { st.from, st.to, st.spell, st.since } end
    end
    return out
end

-- A saved plan as skill -> recipe id, or nil. A step under way covers its points from `since`.
function Plan.Expand(packed)
    if not packed then return nil end
    local map = {}
    for _, st in ipairs(packed) do
        for s = st[4] or st[1], st[2] - 1 do map[s] = st[3] end
    end
    return map
end

-- Guide recipes the player knows under another spell id: Forever gave some recipes a
-- second spell of the same recipe (Basic Campfire is 818 in the guide, 1229737 in the
-- camping list). Each such guide id joins `learned`; returns { [guide id] = live id }.
-- A guide recipe matches the player's learned recipe (one the guide has no id for) by the
-- item it makes when that item names one guide recipe only, else by name, so a client in
-- another language still matches.
function Plan.Alias(guide, recipes, learned)
    local byName, byItem, alias = {}, {}, {}
    for _, r in ipairs(recipes or {}) do
        if r.learned and r.name then byName[r.name] = r end
        if r.learned and not guide.recipes[r.id] then
            local item = Prof.Output(r.id)
            if item and not byItem[item] then byItem[item] = r end
        end
    end
    local makers = {}
    for _, r in pairs(guide.recipes) do
        if r.makes then makers[r.makes] = (makers[r.makes] or 0) + 1 end
    end
    for id, r in pairs(guide.recipes) do
        local live = not learned[id] and (r.makes and makers[r.makes] == 1 and byItem[r.makes] or byName[r.name])
        if live then
            learned[id] = true
            alias[id] = live.id
        end
    end
    return alias
end

-- Guide recipes whose live counterpart (same id, or the player's same-name recipe) the
-- game marks trivial: it gives no points, whatever the guide's data says (Forever's
-- Basic Campfire moved to Camping and stopped giving Cooking points).
function Plan.Dead(guide, recipes, alias)
    local trivial = {}
    for _, r in ipairs(recipes or {}) do
        if r.difficulty == Prof.GREY then trivial[r.id] = true end
    end
    local dead = {}
    for id in pairs(guide.recipes) do
        if trivial[(alias and alias[id]) or id] then dead[id] = true end
    end
    return dead
end

-- Returns { prof, guide, recipes, learned, plan } for the open profession, or nil
-- when none is open. `guide` and `plan` are nil when the profession has no guide.
-- The last live plan, reused while every input the solve reads is the same (see
-- currentKey): bag changes that leave the held counts alone cost no solve. Plan.Invalidate()
-- drops it and every shut plan (skill, recipes, settings, prices).
local cached, epoch = nil, 0
local lastKey, nextKey = {}, {}
local KEY_SIZE = 16

-- Bumped with `epoch` by everything but a skill change. Every shut plan keys on it and on the
-- skills a solve reads (enchantingKey) instead of `epoch`, so another profession's skill-up costs no
-- shut solve.
local sureEpoch = 0

function Plan.Invalidate()
    epoch = epoch + 1
    sureEpoch = sureEpoch + 1
end

local function skillsMoved()
    epoch = epoch + 1
end

-- Bumped per profession when its saved known list or grey set changes, or its step's crafts run
-- out before its end; Plan.Shut's cache key reads it.
local readRev = {}

-- What every solve reads of the player's other skills (first for Enchanting, so the name stays): which professions they have (couplings), and
-- whether Fishing is free for fish (Pricing.FishingFree). The guide's own skill and the
-- disenchant credit (Plan.CreditKey) are in Plan.Shut's key.
local function enchantingKey()
    local lines = {}
    for line in pairs(CP.Sourcing.PlayerSkills()) do lines[#lines + 1] = tostring(line) end
    table.sort(lines)
    return sureEpoch .. "/" .. table.concat(lines, ",") .. "/" .. tostring(CP.Pricing.FishingFree())
end

-- What guide `id`'s solve reads of Enchanting, as a string for a cache key: the signature of
-- Enchanting's current needs while the guide takes its credit, else "".
function Plan.CreditKey(id)
    if not CP.Shared.Credits(id, CP.Sourcing.PlayerSkills()) then return "" end
    local _, sig = CP.Shared.EnchantingNeeds()
    return sig or "-"
end

-- The guide id of profession `p` (Prof.Current's answer), or nil.
local function guideKeyOf(p)
    for _, id in ipairs(p and p.ids or {}) do
        if CP.Guides and CP.Guides[id] then return id end
    end
end

-- Distinct factions among the guide's reputation patterns, built once per guide.
local factionsOf = setmetatable({}, { __mode = "k" })

-- The standing the game shows with each of the guide's pattern factions, as a string.
local function standingKey(guide)
    local list = factionsOf[guide]
    if not list then
        list = {}
        local seen = {}
        for _, r in pairs(guide.recipes) do
            if r.faction and not seen[r.faction] then
                seen[r.faction] = true
                list[#list + 1] = r.faction
            end
        end
        table.sort(list)
        factionsOf[guide] = list
    end
    if #list == 0 then return "" end
    local parts = {}
    for i, faction in ipairs(list) do parts[i] = tostring(CP.Guide.Standing(faction)) end
    return table.concat(parts, ",")
end

-- The guide's materials a gathering profession or Fishing gets (Sourcing.GatherSkill), with the
-- lines that get them, by item id: { { item, line, line2 }, ... }.
local function gathered(guide)
    local list, seen = {}, {}
    for _, r in pairs(guide.recipes) do
        for _, pair in ipairs(r.reagents or {}) do
            local item = pair[1]
            if not seen[item] then
                seen[item] = true
                local line, also = CP.Sourcing.GatherSkill(guide, item)
                if line then list[#list + 1] = { item, line, also } end
            end
        end
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    return list
end

-- What the gathering reach (Sourcing.Reach) lets into guide `guide`'s solve under "Gather it
-- yourself": the guide's gathered materials the player's ranks and level reach now, as a string.
-- It moves only when a rank or the level crosses a source's need, so most gathering skill-ups
-- solve nothing.
local reachSigs = setmetatable({}, { __mode = "k" })
function Plan.ReachKey(guide)
    if not (guide and CP.db.collect) then return "" end
    local ranks, level = CP.Gather.Skills(), CP.Gather.PlayerLevel()
    local parts = {}
    for i, line in ipairs(CP.Gather.PROFS) do parts[i] = ranks[line] or 0 end
    local raw = table.concat(parts, ",") .. ":" .. tostring(level) .. ":" .. CP.Farm.Generation()
    local hit = reachSigs[guide]
    if hit and hit.raw == raw then return hit.sig end
    local reach, h, n = CP.Sourcing.Reach(ranks, level), 0, 0
    for _, g in ipairs(gathered(guide)) do
        for k = 2, 3 do
            local line = g[k]
            if line and ranks[line] and reach(line, g[1]) then
                n = n + 1
                h = (h * 31 + g[1] * 7 + line) % 2147483647
            end
        end
    end
    local sig = n .. "/" .. h
    reachSigs[guide] = { raw = raw, sig = sig }
    return sig
end

-- Everything Plan.Solve reads that can change while the window stays open, into `key`:
-- the profession and its skill, the recipe set and colours, the settings, the faction, the
-- held craft-only, prep and rare counts, pattern standings, Enchanting's needs (the
-- disenchant credit), the specializations held, the Working Overtime rank, and the epoch, which events and
-- settings bump for the rest.
local function currentKey(key, p, recipes)
    local guide = CP.Guide.For(p)
    key[1], key[2], key[3], key[4] = p.id, p.skill, p.max, Prof.RecipeSetKey(recipes)
    key[5], key[6], key[7], key[8] = CP.db.collect, CP.db.fishCook, epoch, CP.Sourcing.Side()
    key[9] = guide and Plan.HeldKey(guide, true) or ""
    key[10] = guide and standingKey(guide) or ""
    key[11] = guide and Plan.CreditKey(CP.Shared.KeyOf(guide)) or ""
    key[12] = guide or false
    key[13] = CP.db.deEnchant
    key[14] = guide and Prof.SpecKey(guide) or ""
    key[15] = Prof.OvertimeRank()
    key[16] = guide and Plan.ReachKey(guide) or ""
end

function Plan.Current()
    local p = Prof.Current()
    if not p then return nil end
    local recipes = Prof.Recipes(p)
    -- The recipe list still on its way: what ProfLost knows already (the saved list, else the
    -- spellbook and the unread state), as with the window shut, until the list arrives.
    local key = Prof.Changing() and guideKeyOf(p)
    local shutLive = key and Plan.Shut(key)
    if shutLive then return shutLive end
    currentKey(nextKey, p, recipes)
    local same = cached ~= nil
    for i = 1, KEY_SIZE do
        if nextKey[i] ~= lastKey[i] then same = false end
    end
    if same then
        -- An equal key means the same recipes, learned and coloured alike; a re-read list
        -- only brings fresher craftable counts.
        cached.recipes = recipes
        return cached
    end
    -- A copy, so a nested Plan.Current during the solve can't change the key it is filed under.
    local key = {}
    for i = 1, KEY_SIZE do key[i] = nextKey[i] end
    cached = Plan.Solve(p, recipes)
    lastKey = key
    return cached
end

CP:On("NEW_RECIPE_LEARNED", Plan.Invalidate)
CP:On("ProfLost_SKILLS", skillsMoved)            -- the open plan re-reads the skills
CP:On("MERCHANT_SHOW", Plan.Invalidate)       -- a sold-out pattern drops out of the plan
-- A window's recipe list changed: the open plan re-reads it; a saved list that moved bumps readRev.
CP:On("TRADE_SKILL_DATA_SOURCE_CHANGED", skillsMoved)

-- The last plan a solve leans on ---------------------------------------------------
-- A solve leans on the last plan (Solver.Plan's `prefer`), so the guide doesn't reshuffle
-- under the player as they work through it. The saved plan keeps, per context (settings
-- and faction), the state it was solved for and the plan it leaned on:
-- `memo[context] = { state, base, plan }`.
--   * The same state leans on the same base again, so it gives the same plan.
--   * A state that moved on (a skill-up, a craft, a recipe learned) leans on the last plan.
--   * A context with no memo (other settings, the other faction) leans on nothing.
-- Open and shut windows share it, and their states are equal when they read the same.

local function hash(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
    return h
end

local function sortedKeys(set)
    local list = {}
    for k in pairs(set or {}) do list[#list + 1] = k end
    table.sort(list)
    return table.concat(list, ",")
end

-- The settings and faction a plan is made under.
local function contextOf()
    return table.concat({ tostring(CP.db.collect), tostring(CP.db.fishCook), tostring(CP.db.deEnchant),
        tostring(CP.Sourcing.Side()) }, ":")
end
-- The settings that change profession `id`'s plan (Settings.LIST `plans`) and the faction, as
-- one string: each such set keeps its own shown plan (Plan.Commit).
function Plan.Context(id)
    local parts = { tostring(CP.Sourcing.Side()) }
    for _, s in ipairs(CP.Settings and CP.Settings.LIST or {}) do
        local plans = s.plans == true or (type(s.plans) == "table" and s.plans[id])
        if plans and s.key then parts[#parts + 1] = s.key .. "=" .. tostring(CP.db ~= nil and CP.db[s.key] ~= false) end
    end
    return table.concat(parts, ",")
end

-- What else the solve reads that play changes, as a number: skill, cap, known recipes,
-- held counts, pattern standings, specializations held, the Working Overtime rank, and Enchanting's needs
-- while its credit is on. Recipes
-- the game marks grey (Plan.Dead) are left out: only the open window sees them, and they
-- give no point now or later, so a shut and an open solve of one character share a state.
local function stateOf(guide, p, learned, opts)
    local parts = { p.skill, p.max, sortedKeys(learned), Plan.HeldKey(guide, true), standingKey(guide),
                    Prof.SpecKey(guide), Prof.OvertimeRank() }
    if opts.credit then
        local items = {}
        for item, n in pairs(opts.deNeeds or {}) do
            if n > 0 then items[#items + 1] = item .. "x" .. n end
        end
        table.sort(items)
        parts[#parts + 1] = table.concat(items, ",")
    end
    return hash(table.concat(parts, "|"))
end

-- For a solve of profession `p`: the memo to file it in, its context and state, and the
-- packed plan to lean on (nil for none). `saved` is charDB.lastPlan[p.id].
function Plan.Leans(saved, guide, p, learned, opts)
    local ctx, state = contextOf(), stateOf(guide, p, learned, opts)
    local memo = saved and saved.memo
    local m = memo and memo[ctx]
    local base
    if m then
        if m.state == state then base = m.base else base = m.plan end
    elseif saved and not memo then
        -- A plan saved before memos: leaned on once.
        base = {}
        for i, st in ipairs(saved) do base[i] = st end
    end
    return memo or {}, ctx, state, base
end

-- Locked steps --------------------------------------------------------------------
-- Owner, 2026-11-18: the guide must not "surprise the player by changing steps within their
-- grasp", and should be "more efficient, but not reactionary". The plan shown is saved per character,
-- profession and settings context (charDB.committed[id][ctx]). At each solve:
--   * its locked steps hold (Plan.Locks): the current step, and each later step the player has
--     started preparing for;
--   * the solve plans the other steps around them (Solver.Plan's `opts.fixed`);
--   * those replace the shown unlocked steps only when at least BETTER_BY cheaper, or when the
--     shown ones can't be done any more (Plan.Commit).
-- The current step counts down one a craft of it. A plan setting turned is the player asking:
-- that context's plan shows, or a fresh one.

-- Version 4: maker rows earn their points. A version 2 or 3 plan is checked once (Plan.Hold):
-- kept when it obeys that, else solved afresh. Version 5: the disenchant credit reads Enchanting's current plan, so an older plan
-- that took the credit is solved afresh once.
Plan.COMMIT_VERSION = 5
Plan.STALE_SLACK = 1    -- points an older plan's maker row's count may play past its end
Plan.BETTER_BY = 0.10   -- the unlocked route changes only for a route at least this much cheaper
Plan.PREP_DEPTH = 3     -- how far a held material counts through the guide's prep makers

-- Profession `id`'s saved plans, one per settings context.
local function committedFor(id)
    if not CP.charDB then return {} end
    CP.charDB.committed = CP.charDB.committed or {}
    CP.charDB.committed[id] = CP.charDB.committed[id] or {}
    return CP.charDB.committed[id]
end

-- Profession `id`'s saved plan under the settings as they stand, or nil.
function Plan.Committed(id)
    local all = CP.charDB and CP.charDB.committed and CP.charDB.committed[id]
    return all and all[Plan.Context(id)] or nil
end

-- Crafts of the current step since it became current: each successful cast of its recipe
-- (or the player's own spell for it) counts once.
CP:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spell)
    if unit ~= "player" or not spell then return end
    for id in pairs(CP.charDB and CP.charDB.committed or {}) do
        local c = Plan.Committed(id)
        local cur = c and c.steps and c.steps[c.current or 1]
        if cur and (cur[3] == spell or c.alias == spell) then
            c.made = (c.made or 0) + 1
            -- Out of crafts before the step's end: its rest is counted again at once.
            if c.made >= (cur[9] or 0) then
                -- Only this profession's plans change: the open plan and its shut plan.
                epoch = epoch + 1
                readRev[id] = (readRev[id] or 0) + 1
            end
        end
    end
end)

-- A step as saved: { from, to, spell, since, crafts, keepCount, keepNames, cost, shown };
-- `shown` is the row's count, at least what later steps keep (Guide.Keeps). A locked step keeps
-- the entry it was saved with (`st.entry`).
local function freeze(guide, steps)
    local keeps = CP.Guide.Keeps(guide, steps, Plan.Held(guide))
    local out = {}
    for i, st in ipairs(steps or {}) do
        if st.entry then
            out[#out + 1] = st.entry
        elseif st.spell then
            local k = keeps[i]
            local keepCrafts = CP.Guide.KeepCrafts(guide.recipes[st.spell], k and k.count)
            out[#out + 1] = { st.from, st.to, st.spell, st.since, st.crafts, k and k.count or nil,
                              k and k.names or nil, st.cost, math.max(st.crafts or 0, keepCrafts) }
        end
    end
    return out
end

-- Saved step `f` as a plan step from `skill`.
local function thawOne(f, skill, ref)
    return { from = math.max(f[1], skill), to = f[2], spell = f[3], since = f[4], crafts = f[5],
             keepCount = f[6], keepNames = f[7], cost = f[8], committed = ref, entry = f }
end

-- The saved steps from `skill` as plan steps; the first is the current one, counted down by
-- the crafts made of it (Plan.StepCrafts). `locks` marks the locked ones.
local function thaw(frozen, skill, ref, locks)
    local out, first = {}, true
    for i, f in ipairs(frozen or {}) do
        if f[2] > skill then
            local st = thawOne(f, skill, ref)
            st.locked = locks and locks[i] or nil
            if first then
                st.first, st.full = true, f[9]
                first = false
            end
            out[#out + 1] = st
        end
    end
    out.frozen = true
    return out
end

local function setKey(set)
    local list = {}
    for id, on in pairs(set or {}) do if on then list[#list + 1] = id end end
    table.sort(list)
    return table.concat(list, ",")
end

-- Every material saved step recipe `spell` reads: its reagents, and what a reagent made in
-- the guide (`guide.prep`) is made from, PREP_DEPTH deep. Into the set `out`.
local function materials(guide, spell, out, depth)
    local r = guide.recipes[spell]
    for _, pair in ipairs(r and r.reagents or {}) do
        out[pair[1]] = true
        local maker = guide.prep and guide.prep[pair[1]]
        if maker and depth < Plan.PREP_DEPTH then materials(guide, maker, out, depth + 1) end
    end
    return out
end
Plan.Materials = function(guide, spell) return materials(guide, spell, {}, 0) end

-- True when saved step `f` can still be done from `skill`: its recipe is known or can be
-- learned where the step starts (its specialization held), is not grey in the game's window, is not an unlearned limited
-- pattern the vendor showed sold out, and gives a skill-up where the step starts.
-- Without `learned`, whether the recipe can be learned is not asked.
local function doable(guide, spell, from, learned, dead)
    local r = guide.recipes[spell]
    if not r or (dead and dead[spell]) then return false end
    if r.deskill then return CP.Deskill.Reach(from) > from end
    local known = learned and learned[spell]
    if learned and not known and (r.learn or 0) > from then return false end
    if learned and not known and r.spec and not Prof.Holds(r.spec) then return false end
    if r.limited and r.pattern and not known and CP.VendorWatch
        and CP.VendorWatch.IsSoldOut and CP.VendorWatch.IsSoldOut(r.pattern) then
        return false
    end
    return CP.Guide.Chance(r, from) > 0
end

function Plan.Doable(guide, f, skill, learned, dead)
    return doable(guide, f[3], math.max(f[1], skill), learned or {}, dead)
end

-- A saved step's identity: its recipe and range.
function Plan.StepKey(f) return ("%d:%d:%d"):format(f[3], f[1], f[2]) end

-- The locked steps of saved plan `c` at `skill`, as a set of indexes into `c.steps`:
--   * the current step (the first that ends above the skill);
--   * each later step the player has started preparing for: the bags or bank hold one of its
--     materials (Plan.Materials), counted toward the earliest step from the current one that
--     uses it;
--   * the earlier steps that make craft-only gear a locked step uses.
-- A step that can't be done (Plan.Doable) is never locked.
function Plan.Locks(c, guide, skill, learned, dead)
    local steps, locks = c and c.steps or {}, {}
    local first
    for i, f in ipairs(steps) do
        if f[2] > skill then first = i break end
    end
    if not first then return locks end
    local function lock(i)
        if not locks[i] and Plan.Doable(guide, steps[i], skill, learned, dead) then locks[i] = true end
    end
    lock(first)
    local earliest = {}
    for i = first, #steps do
        for item in pairs(materials(guide, steps[i][3], {}, 0)) do
            earliest[item] = earliest[item] or i
        end
    end
    local function held(item)
        local n = C_Item.GetItemCount(item, true)
        return n ~= nil and n > 0
    end
    for item, i in pairs(earliest) do
        if held(item) then lock(i) end
    end
    -- A step locked at the last solve stays locked while the bags hold any of its materials,
    -- even when a step planned since before it uses the same material.
    for i = first + 1, #steps do
        if c.invested and c.invested[Plan.StepKey(steps[i])] then
            for item in pairs(materials(guide, steps[i][3], {}, 0)) do
                if held(item) then lock(i) break end
            end
        end
    end
    local craftOnly = guide.craftOnly or {}
    for i = #steps, first, -1 do
        local r = locks[i] and guide.recipes[steps[i][3]]
        for _, pair in ipairs(r and r.reagents or {}) do
            if craftOnly[pair[1]] then
                for j = first, i - 1 do
                    local m = guide.recipes[steps[j][3]]
                    if m and m.makes == pair[1] then lock(j) end
                end
            end
        end
    end
    return locks
end

-- What the unlocked steps of `steps` cost from `skill`, at the per-craft costs `costs`
-- (Solver.Plan's second answer), and the skill points they cover. The cost is nil when one of
-- them can't be done: no cost known now, or not doable as Plan.Doable reads it (with `learned`,
-- a recipe not known that can't be learned there yet too).
function Plan.RouteCost(guide, steps, skill, costs, dead, learned)
    local total, points = 0, 0
    for _, st in ipairs(steps or {}) do
        if st.spell and st.to > skill and not st.locked then
            local from = math.max(st.from, skill)
            local r = guide.recipes[st.spell]
            local each = costs and costs[st.spell]
            local crafts = r and CP.Guide.Crafts(r, from, st.to) or math.huge
            if not each or crafts == math.huge or not doable(guide, st.spell, from, learned, dead) then return nil, points end
            total = total + each * crafts
            points = points + (st.to - from)
        end
    end
    return total, points
end

-- True when route `new` replaces the shown route `old` (both plan steps from `skill`, locked
-- steps marked): the old one can't be done, covers other skill points, or costs at least
-- BETTER_BY more than the new one over the unlocked steps.
-- The disenchant step of `steps` as a string: it always follows the greens there are now.
local function deskillOf(steps)
    for _, st in ipairs(steps or {}) do
        if st.spell == CP.Deskill.SPELL then return st.from .. "-" .. st.to end
    end
    return ""
end

function Plan.Better(guide, old, new, skill, costs, dead, learned)
    -- A plan that moves or drops a locked step never wins.
    for _, st in ipairs(old or {}) do
        if st.locked then
            local kept = false
            for _, nt in ipairs(new or {}) do
                if nt.spell == st.spell and nt.from == st.from and nt.to == st.to then kept = true end
            end
            if not kept then return false end
        end
    end
    if deskillOf(old) ~= deskillOf(new) then return true end
    local was, wasPoints = Plan.RouteCost(guide, old, skill, costs, dead, learned)
    local now, nowPoints = Plan.RouteCost(guide, new, skill, costs, dead, learned)
    if not was then return true end
    if not now then return false end
    if wasPoints ~= nowPoints then return true end
    return now <= was * (1 - Plan.BETTER_BY)
end

-- The solved `plan` with the locked steps of `c` in their saved place: each free step cut
-- where a locked one sits.
local function merge(guide, plan, c, locks, skill)
    local spans = {}
    for i in pairs(locks) do spans[#spans + 1] = i end
    table.sort(spans)
    local out, k, done = {}, 1, skill
    local function emit()
        local st = thawOne(c.steps[spans[k]], skill)
        st.locked = true
        out[#out + 1] = st
        done = math.max(done, st.to)
        k = k + 1
        return st.to
    end
    for _, st in ipairs(plan) do
        -- What a locked step already covers stays its.
        local from = math.max(st.from, done)
        while from < st.to do
            while spans[k] and math.max(c.steps[spans[k]][1], skill) <= from do
                from = math.max(from, emit())
            end
            if from >= st.to then break end
            local stop = spans[k] and math.min(math.max(c.steps[spans[k]][1], skill), st.to) or st.to
            if from == st.from and stop == st.to then
                out[#out + 1] = st
            else
                out[#out + 1] = CP.Guide.StepPart(guide, st, from, stop)
            end
            from = stop
        end
    end
    while spans[k] do emit() end
    return out
end

-- The shown plan profession `p` holds to under settings `ctx`, or nil for a fresh solve: none
-- saved, another version's, the skill below it, or back from other settings with the skill or
-- the known recipes moved since this one was shown, or a guess (Plan.Shut's unread solve) the
-- read recipes prove wrong. The plan shown just before the current settings (`c.left`) holds
-- even when the skill or the known recipes moved: a setting turned and back is no real change
-- (owner, 2026-11-23).
local function heldPlan(all, ctx, p, learned, pending, guess)
    local c = all[ctx]
    local v = c and c.version
    if not (c and c.steps and (v == Plan.COMMIT_VERSION or pending and (v == 2 or v == 3 or v == 4))) then return nil end
    if c.guess and not guess and c.learned ~= setKey(learned) then return nil end
    if p.skill < (c.skill or 0) then return nil end
    if not (c.shown or c.left) and (c.skill ~= p.skill or c.learned ~= setKey(learned)) then return nil end
    return c
end

-- Points fixed by `c`'s locked steps, and the skills where a step must start.
local function fixedOf(c, locks, skill)
    if not (c and next(locks)) then return nil, nil end
    local fixed, cuts = {}, {}
    for i in pairs(locks) do
        local f = c.steps[i]
        local from = math.max(f[1], skill)
        for s = from, f[2] - 1 do fixed[s] = f[3] end
        cuts[from], cuts[f[2]] = true, true
    end
    return fixed, cuts
end

-- True when saved steps `steps` break decision 0008 rule 1: a maker row or a row with a keep whose
-- count, played from its start, ends more than STALE_SLACK past its end while the maker still gives points there; or a row
-- using a prep material whose maker gives points at the row's start, with no earlier row making it.
function Plan.Stale(guide, steps, learned)
    local prep, craftOnly, made = guide.prep or {}, guide.craftOnly or {}, {}
    learned = learned or {}
    for _, f in ipairs(steps or {}) do
        local r = guide.recipes[f[3]]
        if r then
            local keeps = (f[6] or 0) > 0 or prep[r.makes] or craftOnly[r.makes]
            if r.makes and keeps and CP.Guide.Chance(r, f[2]) > 0
                and CP.Solver.Play(r, f[1], f[9] or f[5] or 0) > f[2] + Plan.STALE_SLACK then
                return true
            end
            for _, pair in ipairs(r.reagents) do
                local id = prep[pair[1]]
                local maker = id and guide.recipes[id]
                if maker and not made[pair[1]] and (learned[id] or maker.learn <= f[1])
                    and CP.Guide.Chance(maker, f[1]) > 0 then
                    return true
                end
            end
            if r.makes then made[r.makes] = true end
        end
    end
    return false
end

-- Version 2, 3 and 4 contexts dropped by the one-time check, per profession (the simulator's `locked` reads it).
Plan.Dropped = {}

-- True when a plan of guide `id` saved under settings `ctx` priced its crafts with Enchanting's
-- disenchant credit: the player (`skills`) has Enchanting, the guide makes greens that disenchant, and
-- "Plan for Enchanting" was on.
local function tookCredit(id, guide, ctx, skills)
    if id == CP.Shared.ENCHANTING or not skills[CP.Shared.ENCHANTING] then return false end
    if ctx:find("deEnchant=false", 1, true) then return false end
    return CP.Shared.Disenchants(guide)
end

-- True when saved plan `c` has a step from `skill` on that only a gathered material out of the
-- player's reach (Sourcing.Reach) let in under "Gather it yourself". Plans saved before the reach
-- rule (owner, 2026-11-27) counted a gathered material at any skill and level.
local function outOfReach(guide, c, skill, learned)
    local skills = skillsFor(guide)
    local blind = CP.Sourcing.Filter(guide, learned, true, skills)
    local reached = CP.Sourcing.Filter(guide, learned, true, skills, CP.Sourcing.PlayerReach())
    for _, f in ipairs(c.steps or {}) do
        local r = f[2] > skill and guide.recipes[f[3]]
        if r and blind(f[3], r) and not reached(f[3], r) then return true end
    end
    return false
end

-- Each version 2, 3 or 4 saved plan of profession `id`, checked once. Before version 5 the credit read
-- Enchanting's needs as last saved, so a plan that took it may have been made without it: that plan is
-- dropped. Otherwise a version 4 plan is re-marked as the current version, and a version 2 or 3 plan is
-- re-marked when it obeys decision 0008 rule 1. A dropped plan goes with the last plan's memo, so the next
-- solve starts afresh. The credit question needs the skill list: until it lists profession `id`, a plan
-- that obeys rule 1 keeps its version and is held as it stands. Returns true while that wait lasts.
-- A current plan saved before the reach rule (no `reach` mark) is checked once too, at `skill`: one
-- that leans on a gathered material out of reach is dropped, else it is marked.
local function upgrade(id, guide, learned, skill)
    local all, dropped = committedFor(id), false
    local skills = CP.Sourcing.PlayerSkills()
    local pending = not skills[id]
    -- The reach check waits for the rank of every gathering profession the player has.
    local ranks, unranked = CP.Gather.Skills(), false
    for line in pairs(skills) do
        if (CP.Sourcing.IsGathering(line) or line == CP.Gather.FISHING) and not ranks[line] then unranked = true end
    end
    for ctx, c in pairs(all) do
        local v = c.version
        if v == 2 or v == 3 or v == 4 then
            local clean = c.steps and (v == 4 or not Plan.Stale(guide, c.steps, learned))
            if clean and pending then
                -- Decided once the skill list is read.
            elseif clean and not tookCredit(id, guide, tostring(ctx), skills) then
                c.version = Plan.COMMIT_VERSION
            else
                all[ctx] = nil
                dropped = true
            end
        end
        if all[ctx] and c.version == Plan.COMMIT_VERSION and not c.reach and not pending and not unranked then
            if tostring(ctx):find("collect=true", 1, true) and CP.db.collect and outOfReach(guide, c, skill, learned) then
                all[ctx] = nil
                dropped = true
            else
                c.reach = true
            end
        end
    end
    if dropped then
        if CP.charDB.lastPlan then CP.charDB.lastPlan[id] = nil end
        Plan.Dropped[id] = (Plan.Dropped[id] or 0) + 1
    end
    return pending
end

-- Profession `p`'s saved plan before the solve: the one to hold to (or nil) and its locks.
function Plan.Hold(p, guide, learned, dead, guess)
    local pending = upgrade(p.id, guide, learned, p.skill)
    local all = committedFor(p.id)
    local c = heldPlan(all, Plan.Context(p.id), p, learned, pending, guess)
    local locks = c and Plan.Locks(c, guide, p.skill, learned, dead) or {}
    return c, locks
end

-- The plan profession `p` shows. `plan` (and its `plain` twin) are the solve made around
-- `c`'s locked steps (Plan.Hold), `costs` its per-craft costs. The new unlocked steps replace
-- the shown ones when Plan.Better says so; a limited pattern then takes in the step before it
-- (Plan.LimitedOrs, never across a locked step). Returns the plan as shown, its plain twin and
-- its "or" rows when they were found here (else nil).
function Plan.Commit(guide, p, learned, dead, plan, plain, costs, c, locks, base)
    local all = committedFor(p.id)
    local ctx = Plan.Context(p.id)
    local skill = p.skill
    local candidate = c and merge(guide, plan, c, locks, skill) or plan
    local take = not c or Plan.Better(guide, thaw(c.steps, skill, nil, locks), candidate, skill, costs, dead, learned)
    local ors
    local invested = {}
    for i in pairs(c and locks or {}) do invested[Plan.StepKey(c.steps[i])] = true end
    if take then
        local shaped
        shaped, ors = Plan.LimitedOrs(base, candidate)
        local steps = freeze(guide, shaped)
        -- The "or" rows by the index each step has once saved.
        local at, n, out = {}, 0, {}
        for i, st in ipairs(shaped) do
            if st.entry or st.spell then
                n = n + 1
                at[i] = n
            end
        end
        for i, sides in pairs(ors or {}) do
            if at[i] then out[at[i]] = sides end
        end
        ors = out
        local was = c
        c = { version = Plan.COMMIT_VERSION, ctx = ctx, steps = steps, plain = plain and freeze(guide, plain) or nil,
              made = was and was.made or 0, curKey = was and was.curKey, alias = was and was.alias, reach = true }
        all[ctx] = c

        -- The new plan's own locks are saved, so the next solve with nothing moved saves the same.
        c.invested = invested
        invested = {}
        for i in pairs(Plan.Locks(c, guide, skill, learned, dead)) do invested[Plan.StepKey(c.steps[i])] = true end
    end
    c.skill, c.learned, c.invested = skill, setKey(learned), invested
    -- The current step: a new one starts its crafts at 0.
    c.current = nil
    for i, f in ipairs(c.steps) do
        if f[2] > skill then
            c.current = i
            local key = Plan.StepKey(f)
            if key ~= c.curKey then c.curKey, c.made = key, 0 end
            -- Its crafts used up before its end: the rest is counted again from the skill.
            local r = guide.recipes[f[3]]
            if (c.made or 0) >= (f[9] or 0) and r then
                local rest = CP.Guide.Crafts(r, skill, f[2])
                if rest < math.huge then f[9] = (c.made or 0) + math.max(1, rest) end
            end
            break
        end
    end
    -- A switch of settings marks the plan it leaves; the mark lasts until the next switch.
    local switched = false
    for k, other in pairs(all) do
        if other.shown and k ~= ctx then switched = true end
    end
    for k, other in pairs(all) do
        if switched then other.left = other.shown and k ~= ctx or nil end
        other.shown = k == ctx or nil
    end
    c.left = nil
    return thaw(c.steps, skill, c, locks and not take and locks or nil), c.plain and thaw(c.plain, skill) or nil,
        take and ors or nil
end

-- A saved step's crafts now: the current step's count less the crafts made of it since it
-- became current (read at draw time, as a craft solves nothing); else `st.crafts`.
function Plan.StepCrafts(st)
    local c = st and st.committed
    if not (c and st.first) then return st and st.crafts end
    return math.max(1, (st.full or st.crafts) - (c.made or 0))
end

-- The plan the open and the shut window share, for profession `p` ({ id, skill, max }):
-- the solve around the locked steps, cut at rank caps, a limited pattern's "or" rows, side
-- crafts and fallbacks. `dead` comes from the live list (Plan.Dead), nil with the window shut.
-- Returns a `live`-shaped table without the recipe list.
-- `guess`: `learned` is a guess (an unread profession). The plans saved from it are marked so, and
-- a solve from a read list that knows other recipes neither holds to them nor leans on them.
local function build(guide, p, learned, dead, guess)
    CP.charDB.lastPlan = CP.charDB.lastPlan or {}
    local held, allow, opts = Plan.Held(guide), allowFor(guide, learned, dead), solverOpts(guide)
    local price = priceFor()
    opts.plain = plainWorld(guide, learned, dead, allow, opts.credit, price, opts.deShapedBy)
    local c, locks = Plan.Hold(p, guide, learned, dead, guess)
    opts.fixed, opts.cuts = fixedOf(c, locks, p.skill)

    -- Greens to disenchant fill only the points no locked step covers.
    local spans = {}
    for i in pairs(locks or {}) do
        local f = c.steps[i]
        spans[#spans + 1] = { math.max(f[1], p.skill), f[2] }
    end
    opts.fixed, opts.cuts = CP.Deskill.Fix(guide, p, opts.fixed, opts.cuts, spans)
    opts.maker = makerAllow(guide, learned, dead)
    local saved = CP.charDB.lastPlan[p.id]
    if saved and saved.guess and not guess and saved.guess ~= setKey(learned) then saved = nil end
    local memo, ctx, state, base = Plan.Leans(saved, guide, p, learned, opts)
    local plan, costs = CP.Solver.Plan(guide, p.skill, learned, price, allow,
        Plan.Expand(base), Plan.WithoutRare(guide, held), opts)
    local plain = plan.plain
    -- No step climbs past a cap the player hasn't trained past.
    plan = CP.Guide.SplitAtCaps(guide, plan, p.max)
    plain = plain and CP.Guide.SplitAtCaps(guide, plain, p.max)
    memo[ctx] = { state = state, base = base, plan = Plan.Pack(plan) }
    local packed = Plan.Pack(plan)
    packed.memo, packed.guess = memo, guess and setKey(learned) or nil
    CP.charDB.lastPlan[p.id] = packed
    local shell = { prof = p, guide = guide, learned = learned, dead = dead or {} }
    local ors
    plan, plain, ors = Plan.Commit(guide, p, learned, dead, plan, plain, costs, c, locks, shell)
    local shown = committedFor(p.id)[Plan.Context(p.id)]
    if shown then shown.guess = guess or nil end
    local causes = opts.plain and opts.plain.causes
    local live = { prof = p, guide = guide, learned = learned, dead = dead or {}, credit = opts.credit,
                   plain = plain, causes = causes, shapedBy = shapedBy(guide, plan, plain, causes), costs = costs }
    -- Its "or" rows: the ones the commit just found, else found again for the plan shown.
    if ors then
        live.plan, live.ors = plan, ors
    else
        live.plan, live.ors = Plan.LimitedOrs(live, plan)
    end
    live.sides = Plan.Sides(guide, live.plan, learned, held, allow)
    Plan.AddFallbacks(live)
    return live
end

function Plan.Solve(p, recipes)
    local guide = CP.Guide.For(p)
    local learned = Prof.Learned(recipes)
    local alias = guide and Plan.Alias(guide, recipes, learned) or {}
    local dead = guide and Plan.Dead(guide, recipes, alias) or {}
    local live = guide and build(guide, p, learned, dead) or { prof = p, learned = learned, sides = {}, dead = dead }
    live.recipes, live.alias = recipes, alias
    -- The player's own spell for the committed current step, so its crafts count.
    local c = Plan.Committed(p.id)
    local cur = c and c.steps and c.steps[c.current or 1]
    if cur then c.alias = alias[cur[3]] end
    if guide and CP.VendorWatch then CP.VendorWatch.Update(live) end
    if guide then
        CP.Gather.SaveNeeds(live)
        CP.GatherList.Changed()
    end
    return live
end

-- The same plan as Plan.Current for a profession whose window is closed: skill from
-- the skill list, recipes known as of the last time its window was open (none yet
-- means trainer recipes are planned as to-be-trained). Returns a `live`-shaped table.
-- It differs from the open window's only where the live list is needed: recipes the
-- game marks grey (Plan.Dead) as of the last read, the live spell a guide recipe is crafted through
-- (Plan.Alias; the saved list already holds the guide ids) and craftable counts.
-- `guess` as build's. `dead`: the grey recipes the last read saved (Plan.SaveKnown), or nil.
function Plan.Offline(guide, id, skill, max, learned, guess, dead)
    return build(guide, { id = id, skill = skill, max = max }, learned, dead, guess)
end

-- Profession `id`'s plan while its window is shut, shaped like Plan.Current's: the skill
-- from the skill list, the recipes known when its window was last open. Gathering
-- professions get no guide; their tab rows come from the skill alone. Nil when the
-- player hasn't got it. Cached until the skill, the known recipes, the held counts the
-- solve reads, Enchanting's needs (Plan.CreditKey) or Plan.Invalidate change it.
local shut = {}

-- Plans solved with nothing saved (Plan.Shut's `peek`), per profession, cached the same way.
local peeks = {}

-- Professions whose guide recipes were asked of the spellbook this session.
local booked = {}

-- The solve caches as they stand, and putting them back: the simulator's `orderfree` check
-- solves every guide twice and must leave no trace.
local function copyOf(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function refill(t, from)
    for k in pairs(t) do t[k] = nil end
    for k, v in pairs(from) do t[k] = v end
end

function Plan.Caches()
    return { epoch = epoch, sureEpoch = sureEpoch, shut = copyOf(shut), peeks = copyOf(peeks), cached = cached,
             lastKey = lastKey, readRev = copyOf(readRev), booked = copyOf(booked) }
end

function Plan.SetCaches(c)
    refill(shut, c.shut)
    refill(peeks, c.peeks)
    refill(readRev, c.readRev)
    refill(booked, c.booked)
    epoch, sureEpoch, cached, lastKey = c.epoch, c.sureEpoch, c.cached, c.lastKey
end

-- The held craft-only and prep counts (Plan.Held without rare byproducts), as a string.
-- `withRare` adds the rare byproducts, so the string covers all of Plan.Held, as every
-- plan's side crafts read it. Bag changes that leave them alone keep the cached plan.
local heldParts = {}

function Plan.HeldKey(guide, withRare)
    local n = 0
    local function add(item)
        local c = CP.Purchases.Have(item)
        if c > 0 then
            n = n + 1
            heldParts[n] = item .. "x" .. c
        end
    end
    -- Enchanting's plan reads the greens there are to disenchant (Deskill.Supply).
    if guide == CP.Guides[CP.Deskill.ENCHANTING] then
        n = n + 1
        heldParts[n] = "de:" .. CP.Deskill.Key()
    end
    for _, set in ipairs({ guide.craftOnly or {}, guide.prep or {} }) do
        for item in pairs(set) do
            local info = guide.items and guide.items[item]
            if withRare or not (info and info[5]) then add(item) end
        end
    end
    if withRare then
        heldParts[n + 1] = "|"
        n = n + 1
        for item, info in pairs(guide.items or {}) do
            if info[5] then add(item) end
        end
    end
    return table.concat(heldParts, ",", 1, n)
end

-- Known recipes ------------------------------------------------------------------
-- The game's recipe list says what the player knows, whichever window shows it, one
-- ProfLost doesn't recognise too. Each settled read of the player's own profession is saved
-- (charDB.learned) and marks it read (charDB.recipesRead), so shut and unrecognised
-- windows plan from it. Before any read, recipes the spellbook knows join the list, but
-- only a read says a recipe is unknown: an unread profession offers nothing to buy.

Plan.OPEN_ONCE = "Open %s once so ProfLost can read your recipes"

function Plan.ForgetBook() booked = {} end

CP:On("NEW_RECIPE_LEARNED", Plan.ForgetBook)
CP:On("PLAYER_ENTERING_WORLD", Plan.ForgetBook)

-- True when profession `id`'s known recipes have been read from its recipe list.
function Plan.Read(id)
    return (CP.charDB and CP.charDB.recipesRead and CP.charDB.recipesRead[id]) == true
end

-- "Open Cooking once so ProfLost can read your recipes" for an unread `live`, else nil.
function Plan.OpenOnce(live)
    if not (live and live.unread) then return nil end
    return Plan.OPEN_ONCE:format(live.prof and live.prof.name or "the profession")
end

-- Saves `learned` (a set) as profession `key`'s known recipes, read from its list, and `grey`
-- (a set, optional) as the guide recipes that list showed grey (Plan.Dead). A shut solve reads
-- both, so it plans from what the open window plans from. A recipe stays grey as the skill
-- rises, so the saved set holds until the next read. True when that changed what was saved.
local function save(key, learned, grey)
    local db = CP.charDB
    -- Each set as a sorted list, and whether it equals the list saved under `field`.
    local lists, same = {}, {}
    for field, set in pairs({ learned = learned, grey = grey }) do
        local list = {}
        for id in pairs(set) do list[#list + 1] = id end
        table.sort(list)
        local old = db[field] and db[field][key]
        local eq = old ~= nil and #old == #list
        for i = 1, eq and #list or 0 do
            if old[i] ~= list[i] then eq = false break end
        end
        lists[field], same[field] = list, eq
    end
    local read = db.recipesRead and db.recipesRead[key]
    if read and same.learned and (not grey or same.grey) then return false end
    if grey then
        db.grey = db.grey or {}
        db.grey[key] = lists.grey
    end
    db.learned = db.learned or {}
    db.learned[key] = lists.learned
    CP.charDB.recipesRead = CP.charDB.recipesRead or {}
    CP.charDB.recipesRead[key] = true
    readRev[key] = (readRev[key] or 0) + 1
    return true
end
Plan.SaveKnown = save

local lastRead

-- Reads the open profession's known recipes into the saved list, once its list settles.
function Plan.Remember()
    if not CP.charDB or not Prof.IsOwn() or Prof.Changing() then return end
    local p = Prof.Current()
    local key = guideKeyOf(p)
    if not key then return end
    local recipes = Prof.Recipes(p)
    if recipes == lastRead or not Prof.Settled(p) then return end
    lastRead = recipes
    local learned = Prof.Learned(recipes)
    local guide = CP.Guides[key]
    local alias = Plan.Alias(guide, recipes, learned)
    -- A recognised window's plan reads the list itself; an unrecognised one shows the shut plan,
    -- and Next up and the launcher follow that plan's step at once.
    if save(key, learned, Plan.Dead(guide, recipes, alias)) and not (CP.Window and CP.Window.ProfessionOpen()) then
        local shut = Plan.Shut(key)
        if shut and shut.plan then
            CP.Gather.SaveNeeds({ guide = shut.guide, prof = shut.prof, plan = shut.plan, learned = shut.learned })
        end
        if CP.Panel then CP.Panel.Changed() end
    end
end

for _, event in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED" }) do
    CP:On(event, Plan.Remember)
end

-- Guide recipes the spellbook says are known join profession `id`'s saved list, once a
-- session.
local function fromBook(id, guide)
    if booked[id] then return end
    local list = CP.charDB.learned and CP.charDB.learned[id] or {}
    local have = {}
    for _, spell in ipairs(list) do have[spell] = true end
    local added = false
    for spell in pairs(guide.recipes) do
        if Prof.SpellKnown(spell) then
            if not have[spell] then
                list[#list + 1] = spell
                have[spell], added = true, true
            end
        end
    end
    if added then
        CP.charDB.learned = CP.charDB.learned or {}
        CP.charDB.learned[id] = list
        readRev[id] = (readRev[id] or 0) + 1
    end
    booked[id] = true
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

-- `solve()` run on copies of profession `id`'s saved plan and last plan (with its memo); the saved
-- tables, Plan.Dropped and an absent `committed` or `lastPlan` come back as they were, an error too.
-- Also returns what the solve saved, with what it started from and each saved plan's craft count
-- (the cast counter writes those in place), so Plan.Shut can take it over.
local function apart(id, solve)
    local db = CP.charDB
    local committed, lastPlan, dropped = db.committed, db.lastPlan, Plan.Dropped[id]
    local all, last = committed and committed[id], lastPlan and lastPlan[id]
    if all then committed[id] = deepCopy(all) end
    if last then lastPlan[id] = deepCopy(last) end
    local ok, live = pcall(solve)
    local wrote = { from = { committed, lastPlan, all, last, dropped }, made = {},
                    all = db.committed and db.committed[id], last = db.lastPlan and db.lastPlan[id],
                    dropped = Plan.Dropped[id] }
    for ctx, c in pairs(all or {}) do wrote.made[ctx] = tostring(c.made) .. ":" .. tostring(c.curKey) end
    if committed then committed[id] = all else db.committed = nil end
    if lastPlan then lastPlan[id] = last else db.lastPlan = nil end
    Plan.Dropped[id] = dropped
    if not ok then error(live, 0) end
    return live, wrote
end

-- `peek`: the plan as a shut solve would show it, with nothing saved. Plan.Shut's own plan when it is
-- current, else a solve kept apart from it that leaves the saved plan, its memo and Plan.Dropped as
-- they were. Another guide's disenchant credit reads Enchanting this way, so solving that guide never
-- changes Enchanting's own guide.
function Plan.Shut(id, peek)
    local info = Prof.SkillLine(id)
    if not info or info.isHeader then return nil end
    -- The rank alone, as the open window's (Prof.Current): a modifier lifts no skill-up or step.
    local skill = info.rank or 0
    if skill <= 0 then return nil end
    local max = info.maxRank or skill
    local guide = CP.Guides and CP.Guides[id]
    if guide and not Plan.Read(id) then fromBook(id, guide) end
    local unread = guide ~= nil and not Plan.Read(id)
    local known = CP.charDB.learned and CP.charDB.learned[id] or {}
    local key = table.concat({ skill, max, #known, readRev[id] or 0, tostring(unread), tostring(CP.db.collect),
        tostring(CP.db.fishCook), tostring(CP.db.deEnchant), enchantingKey(),
        guide and Plan.HeldKey(guide, true) or "",
        guide and Plan.CreditKey(id) or "", guide and Prof.SpecKey(guide) or "", Prof.OvertimeRank(),
        guide and Plan.ReachKey(guide) or "" }, ":")
    local hit = shut[id]
    if hit and hit.key == key then return hit.live end
    hit = peeks[id]
    if hit and hit.key == key then
        if peek then return hit.live end
        -- A peek with the same inputs already solved this plan. While the saved plans are still the
        -- ones it started from, what it saved apart is what solving again would save.
        local db, w = CP.charDB, hit.wrote
        local from = w and w.from
        local same = from and db.committed == from[1] and db.lastPlan == from[2] and Plan.Dropped[id] == from[5]
            and (db.committed and db.committed[id]) == from[3] and (db.lastPlan and db.lastPlan[id]) == from[4]
        if same then
            local n = 0
            for ctx, c in pairs(from[3] or {}) do
                n = n + 1
                if w.made[ctx] ~= tostring(c.made) .. ":" .. tostring(c.curKey) then same = false end
            end
            for _ in pairs(w.made) do n = n - 1 end
            same = same and n == 0
        end
        if same then
            if w.all then
                db.committed = db.committed or {}
                db.committed[id] = w.all
            end
            if w.last then
                db.lastPlan = db.lastPlan or {}
                db.lastPlan[id] = w.last
            end
            Plan.Dropped[id] = w.dropped
            peeks[id] = nil
            shut[id] = { key = key, live = hit.live }
            return hit.live
        end
    end

    local learned, recipes = {}, {}
    for _, spell in ipairs(known) do
        learned[spell] = true
        recipes[#recipes + 1] = { id = spell, learned = true, craftable = 0 }
    end
    -- The recipes the last read showed grey: the open window's `dead`.
    local saved = not unread and CP.charDB.grey and CP.charDB.grey[id]
    local dead
    if saved then
        dead = {}
        for _, spell in ipairs(saved) do dead[spell] = true end
    end
    local function solve()
        return guide and Plan.Offline(guide, id, skill, max, learned, unread, dead)
            or { prof = { id = id, skill = skill, max = max }, learned = learned }
    end
    local live, wrote
    if peek then live, wrote = apart(id, solve) else live = solve() end
    live.prof.name = (guide and guide.name) or info.name or ""
    live.prof.ids = { id }
    live.recipes, live.alias, live.offline = recipes, {}, true
    live.sides, live.dead = live.sides or {}, live.dead or {}
    live.unread = unread or nil
    if peek then peeks[id] = { key = key, live = live, wrote = wrote } else shut[id] = { key = key, live = live } end
    return live
end

-- A main step on a pattern the player hasn't got (bought, dropped or rep-locked) gets
-- an "or" fallback: the recipe the plan would use without it, when that one is known
-- or comes from a trainer, so there's always something to do if the pattern can't be had.
Plan.MIN_FALLBACK = 5   -- a step shorter than this gets no fallback: it's over in a few crafts

-- An unlearned limited-stock vendor pattern leading step `st`, else nil.
local function limitedStep(live, st)
    local r = st.spell and live.guide.recipes[st.spell]
    return r and r.limited and r.pattern and not live.learned[st.spell] and r or nil
end

-- "Or" rows for an unlearned limited pattern on `st`: up to ALTERNATIVES recipes the plan
-- would use over its range from known and trainer recipes alone. A row counts crafts from
-- where it gives points (`lo`) to where it greys or the step ends (`upto`).
local function limitedSides(live, st, r)
    local out = {}
    for _, alt in ipairs(Plan.Alternatives(live, { spell = st.spell, recipe = r, from = st.from, to = st.to }, true)) do
        local lo = math.max(st.from, alt.recipe.learn or 0)
        local upto = math.min(st.to, alt.recipe.grey)
        local crafts = lo < upto and CP.Guide.Crafts(alt.recipe, lo, upto) or 0
        if (alt.learned or CP.Guide.SourceWord(alt.recipe) == "trainer") and crafts > 0 and crafts < math.huge then
            out[#out + 1] = { spell = alt.spell, recipe = alt.recipe, learned = alt.learned, fallback = true,
                              limited = true, crafts = crafts, lo = lo, upto = upto }
        end
    end
    return out
end

-- True when a step over `from`-`to` would cross a rank's cap, which Guide.SplitAtCaps
-- cuts apart.
local function crossesRank(guide, maxSkill, from, to)
    for _, rank in ipairs(guide.ranks or {}) do
        if (maxSkill or 0) <= rank.cap and to > rank.cap and from < rank.cap then return true end
    end
    return false
end

-- True when limited step `st` (recipe `r`) taking in `prev` would change what a maker was sized for
-- (decision 0008 rule 9): `prev` makes a prep or craft-only product, or the joined step uses more of
-- one than the two steps it replaces.
local function joinMovesMakers(guide, prev, st, r)
    local prep, craftOnly = guide.prep or {}, guide.craftOnly or {}
    local function made(item) return prep[item] or craftOnly[item] end
    local pr = guide.recipes[prev.spell]
    if not pr or (pr.makes and made(pr.makes)) then return true end

    local joined = CP.Guide.Crafts(r, prev.from, st.to)
    local own, before = CP.Guide.Crafts(r, st.from, st.to), CP.Guide.Crafts(pr, prev.from, prev.to)
    if joined == math.huge or own == math.huge or before == math.huge then return true end
    local more = {}
    for _, pair in ipairs(r.reagents) do
        if made(pair[1]) then more[pair[1]] = (more[pair[1]] or 0) + pair[2] * (joined - own) end
    end
    for _, pair in ipairs(pr.reagents) do
        if made(pair[1]) then more[pair[1]] = (more[pair[1]] or 0) - pair[2] * before end
    end
    for _, n in pairs(more) do
        if n > 1e-9 then return true end
    end
    return false
end

-- Limited-stock patterns stay the main step, and their "or" rows cover the same range.
-- A step right before one, on a recipe that is one of its "or" rows, joins the pattern's
-- step when the pattern already gives points there; the "or" row covers it instead. A
-- step the player is working through (under way) never joins, and neither does one whose join
-- would change a maker's count (joinMovesMakers).
-- Returns the plan and { [step index] = { side... } }. `live` needs guide, learned and
-- dead; `live.prof.max` keeps a joined step from crossing a rank's cap.
function Plan.LimitedOrs(live, plan)
    local out, ors = {}, {}
    local maxSkill = live.prof and live.prof.max
    for _, st in ipairs(plan or {}) do
        local r = limitedStep(live, st)
        local sides = r and limitedSides(live, st, r)
        local prev = out[#out]
        -- A step under way (`since`) holds to its end, as Solver.Plan's current step does, and a
        -- locked step (Plan.Locks) keeps its range.
        while sides and not plan.frozen and not st.locked and prev and prev.spell and not prev.since
            and not prev.locked and prev.from >= r.learn
            and CP.Guide.Chance(r, prev.from) > 0 and not crossesRank(live.guide, maxSkill, prev.from, st.to) do
            local joins = false
            for _, side in ipairs(sides) do
                if side.spell == prev.spell then joins = true end
            end
            if not joins or joinMovesMakers(live.guide, prev, st, r) then break end
            st = CP.Guide.StepPart(live.guide, st, prev.from, st.to)
            out[#out] = nil
            ors[#out + 1] = nil
            sides = limitedSides(live, st, r)
            prev = out[#out]
        end
        out[#out + 1] = st
        if sides and #sides > 0 then ors[#out] = sides end
    end
    return out, ors
end

function Plan.AddFallbacks(live)
    if not live.ors then live.plan, live.ors = Plan.LimitedOrs(live, live.plan) end
    for i, st in ipairs(live.plan or {}) do
        local r = st.spell and live.guide.recipes[st.spell]
        local nextSpell = live.plan[i + 1] and live.plan[i + 1].spell
        local ors = live.ors[i]
        if ors then
            -- Under a side craft already there, they follow it.
            local first = live.sides[i] or ors[1]
            first.more = first.more or {}
            for _, side in ipairs(ors) do
                if side ~= first then first.more[#first.more + 1] = side end
            end
            live.sides[i] = first
        elseif r and not live.learned[st.spell] and CP.Guide.SourceWord(r) == "pattern" and not live.sides[i]
            and not r.limited and st.to - st.from >= Plan.MIN_FALLBACK then
            for _, alt in ipairs(Plan.Alternatives(live, { spell = st.spell, recipe = r, from = st.from, to = st.to }, true)) do
                -- Counted up to where it greys out inside the step; one that gives no point here is no fallback.
                -- The next step's own recipe is no fallback: the guide moves to it anyway.
                local upto = math.min(st.to, alt.recipe.grey)
                local crafts = CP.Guide.Crafts(alt.recipe, st.from, upto)
                if alt.spell ~= nextSpell and (alt.learned or CP.Guide.SourceWord(alt.recipe) == "trainer")
                    and crafts < math.huge and crafts > 0 then
                    live.sides[i] = { spell = alt.spell, recipe = alt.recipe, learned = alt.learned, fallback = true,
                                      crafts = crafts, upto = upto }
                    break
                end
            end
        end
    end
    Plan.AddFishSides(live)
end

-- True when main step recipe `spell` needs a pattern the player hasn't learned. Only
-- beside such a step may an "or" row be green: the player may not get the pattern, and
-- the row is then the only way on. Beside a known or trainer recipe it ends where it greens.
function Plan.PatternOnly(live, spell)
    local r = spell and live.guide.recipes[spell]
    return r ~= nil and not live.learned[spell] and CP.Guide.SourceWord(r) ~= "trainer"
end

-- The fish recipes the plan would use with fish allowed, each as an "or" row under the
-- main step it overlaps (Blackmouth Oil under 80-100).
function Plan.AddFishSides(live)
    if not (live.plan and fishAside(live.guide)) then return end
    local guide = live.guide
    local allow = allowFor(guide, live.learned, live.dead, true)
    local any = false
    for id, r in pairs(guide.recipes) do
        if usesFish(guide, r) and allow(id, r) then any = true break end
    end
    if not any then return end
    local opts = solverOpts(guide)
    opts.fillGaps = false
    local from = live.plan[1] and live.plan[1].from or 1
    local fishPlan = CP.Solver.Plan(guide, from, live.learned, priceFor(), allow, nil, Plan.Held(guide), opts)
    for _, fs in ipairs(fishPlan) do
        local r = fs.spell and guide.recipes[fs.spell]
        if r and usesFish(guide, r) then
            for i, st in ipairs(live.plan) do
                local main = st.spell and guide.recipes[st.spell]
                if main and not live.sides[i] and not usesFish(guide, main) and fs.from < st.to and fs.to > st.from then
                    local lo, upto = math.max(st.from, fs.from), math.min(st.to, fs.to, r.grey)
                    if not Plan.PatternOnly(live, st.spell) then upto = math.min(upto, CP.Solver.GreenFrom(r)) end
                    local crafts = lo < upto and CP.Guide.Crafts(r, lo, upto) or 0
                    if crafts > 0 and crafts < math.huge then
                        live.sides[i] = { spell = fs.spell, recipe = r, learned = live.learned[fs.spell] == true,
                                          fallback = true, withFish = true, crafts = crafts, upto = upto }
                    end
                    break
                end
            end
        end
    end
end

-- What the plan would use over `step`'s range without its recipe: up to
-- ALTERNATIVES recipes, { recipe, spell, learned }, in plan order. With `reachable`, only
-- known and trainer recipes count, as an "or" row needs: another pattern could be missing too.
function Plan.Alternatives(live, step, reachable)
    local allow = allowFor(live.guide, live.learned, live.dead)
    local without = function(id, r)
        if reachable and not (live.learned[id] or CP.Guide.SourceWord(r) == "trainer") then return false end
        return id ~= step.spell and allow(id, r)
    end

    local function solve(fill)
        local opts = solverOpts(live.guide)
        opts.fillGaps = fill
        -- Gap filling never hands back the step's own recipe, one no trainer or vendor of the
        -- player's side teaches, nor (with `reachable`) one neither known nor trained. All are
        -- locked out.
        local locked, side = opts.locked, CP.Sourcing.Side()
        opts.locked = function(id, r)
            return id == step.spell or not CP.Sourcing.CanLearn(live.guide, id, r, live.learned, side)
                or (reachable and not (live.learned[id] or CP.Guide.SourceWord(r) == "trainer"))
                or (locked ~= nil and locked(id, r))
        end
        local steps = CP.Solver.Plan(live.guide, step.from, live.learned, priceFor(), without, nil, Plan.Held(live.guide), opts)
        local out, seen = {}, {}
        for _, st in ipairs(steps) do
            if st.from >= step.to then break end
            if st.spell and not seen[st.spell] then
                seen[st.spell] = true
                out[#out + 1] = { spell = st.spell, recipe = live.guide.recipes[st.spell], learned = live.learned[st.spell] == true }
                if #out == ALTERNATIVES then break end
            end
        end
        return out
    end
    -- The recipes the filter allows; where they plan nothing over the step, the gap fillers the
    -- main plan would use too (an Alchemist without Herbalism plans herb recipes that way).
    local any = false
    for id, r in pairs(live.guide.recipes) do
        if (r.step or live.learned[id]) and r.learn < step.to and r.grey > step.from and without(id, r) then
            any = true
            break
        end
    end
    local out = any and solve(false) or {}
    if #out == 0 and CP.db.collect == true then out = solve(true) end
    return out
end

-- What an unlearned limited pattern's step card says, else nil. It names the patterns the
-- plan would use instead, "A (pattern)"; with "or" rows under the step, known and trainer
-- recipes stand there.
Plan.LIMITED_ORS = 'Limited stock. If it\'s sold out, craft an "or" row below.'
Plan.LIMITED_NONE = "Limited stock: may be sold out, and nothing else covers this range."

function Plan.AlternativesText(live, step)
    local r = step.recipe or live.guide.recipes[step.spell]
    if not (r and r.limited and r.pattern) or live.learned[step.spell] then return nil end
    local shown, any = {}, false
    local side = step.planIndex and live.sides and live.sides[step.planIndex]
    if side then
        shown[side.spell], any = true, true
        for _, s in ipairs(side.more or {}) do shown[s.spell] = true end
    end
    -- The plan keeps each answer, as Plan.Current's and Plan.Shut's keys cover what the
    -- solve reads.
    live.alts = live.alts or {}
    local k = step.spell .. ":" .. step.from .. ":" .. step.to
    local alts = live.alts[k] or Plan.Alternatives(live, step)
    live.alts[k] = alts
    local names = {}
    for _, alt in ipairs(alts) do
        if not (shown[alt.spell] or any and (alt.learned or CP.Guide.SourceWord(alt.recipe) == "trainer")) then
            names[#names + 1] = alt.recipe.name .. (alt.learned and "" or (" (%s)"):format(CP.Guide.SourceWord(alt.recipe)))
        end
    end
    if #names == 0 then return any and Plan.LIMITED_ORS or Plan.LIMITED_NONE end
    local lead = any and 'Limited stock. If it\'s sold out, craft an "or" row below, or ' or "Limited stock. If sold out: "
    return lead .. table.concat(names, ", ")
end
