local _, CP = ...
if CP.stopped then return end

-- Fishing leveling: where to fish for the current skill, how many catches the next
-- rank takes, and the rank steps (Journeyman trainer, Expert book, Artisan trainer or quest).
-- Skill-ups don't depend on the zone, so any water where every bite lands will do;
-- with the Cooking option, waters whose catch the Cooking guide needs come first.

local Fishing = {}
CP.Fishing = Fishing

Fishing.SKILL = 356

local RANK_NAME = { [75] = "Journeyman Fishing", [150] = "Expert Fishing", [225] = "Artisan Fishing" }
local SIDE = { Alliance = "A", Horde = "H" }

-- The rank that lifts cap `cap` for `side` ("Alliance" or "Horde"), or nil. Artisan has two:
-- Katoom the Angler trains Horde from 200, and Nat Pagle's quest serves both at 225. A rank
-- serves a side when one of its NPCs is that side's or neutral; without a side, only neutral
-- NPCs count. The one learnable soonest wins.
function Fishing.RankFor(cap, side)
    local data = CP.GatherData and CP.GatherData.fishing
    local best
    for _, rank in ipairs(data and data.ranks or {}) do
        if rank.skill == cap then
            local serves = false
            for _, e in ipairs(rank.npcs or {}) do
                local who = data.npcs[e] and data.npcs[e][2]
                if who == "N" or (side and who == SIDE[side]) then serves = true end
            end
            if serves and (not best or (rank.at or cap) < (best.at or cap)) then best = rank end
        end
    end
    return best
end

-- Chance of a skill-up per catch at `skill` (cMaNGOS): every catch below 75, then 25 / (skill - 50).
-- The Working Overtime perk multiplies it (Guide.Boost).
function Fishing.SkillUpChance(skill)
    if skill < 75 then return 1 end
    return CP.Guide.Boost(math.min(1, 25 / (skill - 50)))
end

-- Expected catches to go from `from` to `to`.
-- Fishing points `catches` give from `skill`, up to `cap` (the rank's limit).
function Fishing.GainFrom(skill, catches, cap)
    local s, n = skill, catches
    while n > 0 and s < (cap or 300) do
        local need = 1 / Fishing.SkillUpChance(s)
        if n < need then break end
        n, s = n - need, s + 1
    end
    return s - skill
end

function Fishing.CatchesTo(from, to)
    local total = 0
    for s = from, to - 1 do total = total + 1 / Fishing.SkillUpChance(s) end
    return math.floor(total + 0.5)
end

-- The rank step due at `skill` with cap `maxRank` (75, 150, 225) for `side`, or nil.
function Fishing.RankStep(skill, maxRank, side)
    if maxRank >= 300 or skill < maxRank then return nil end
    return Fishing.RankFor(maxRank, side)
end

function Fishing.RankName(rank)
    return RANK_NAME[rank.skill] or "the next rank"
end

-- True when `zone`'s water is within reach: its low level is at most `margin` above `level`.
-- The player's own zone gets at least what the character survives (GatherGuide.Workable) and
-- no more, as GatherGuide's other guides rule, because a trainer's errand can leave the
-- player in a zone far above them.
local function reachable(zone, z, level, here, margin)
    if not z.lvl then return true end
    local most = level + margin
    if zone == here then most = math.max(most, CP.GatherGuide.Workable(level)) end
    return z.lvl[1] <= most
end

-- Waters that land the most bites at `skill` (every bite once the skill allows; early on,
-- the easiest waters), in `continent` when given, as { { zone, base, land } }. The other
-- faction's ground (Gather.Territory, as the other gathering guides weigh it) is left out
-- while own or contested water lands as well; with none, it stays, `enemy` set.
local function waters(skill, level, side, here, continent, margin)
    local out, best, bestOk = {}, 0, 0
    for zone, z in pairs(CP.GatherData.zones) do
        if z.fish and reachable(zone, z, level, here, margin) and (not continent or z.map == continent)
            and not CP.Gather.EnemyHome(zone, side) then
            local land = CP.Gather.LandChance(skill, z.fish.base)
            if land > 0 then
                local enemy = side ~= nil and CP.Gather.Territory(zone, side) == "enemy"
                out[#out + 1] = { zone = zone, base = z.fish.base, land = land, enemy = enemy or nil }
                best = math.max(best, land)
                if not enemy then bestOk = math.max(bestOk, land) end
            end
        end
    end
    for i = #out, 1, -1 do
        if out[i].land < best or (out[i].enemy and bestOk >= best) then table.remove(out, i) end
    end
    table.sort(out, function(a, b)
        if a.base ~= b.base then return a.base > b.base end
        return a.zone < b.zone
    end)
    return out
end

-- The waters safe at `level` that land the most bites at `skill`, by fishing level,
-- highest first. `side` ("Alliance" or "Horde") skips the other faction's home zones.
-- `here` (optional) is the player's zone, always safe. A character under
-- GatherGuide.HOME_LEVEL below skill HOME_SKILL stays on `here`'s continent; with
-- nothing in reach there, the margin widens as GatherGuide does, then the continent goes.
function Fishing.Candidates(skill, level, side, here)
    local GG = CP.GatherGuide
    local out = waters(skill, level, side, here, nil, GG.SAFE_LEVELS)
    local home = here and CP.GatherData.zones[here]
    if not (home and level < GG.HOME_LEVEL and skill < GG.HOME_SKILL) then return out end
    out = waters(skill, level, side, here, home.map, GG.SAFE_LEVELS)
    for margin = GG.SAFE_LEVELS + GG.MARGIN_STEP, GG.MAX_MARGIN, GG.MARGIN_STEP do
        if #out > 0 then return out end
        out = waters(skill, level, side, here, home.map, margin)
    end
    if #out == 0 then out = waters(skill, level, side, here, nil, GG.MAX_MARGIN) end
    return out
end

-- The best water to catch `item` at `skill`: { zone, chance, land } or nil. Each
-- water's chance of the fish times its land chance, discounted by the trip like
-- Fishing.Plan (NEAR_YD away counts half). `distance(zone)` and `here` (the player's zone,
-- always safe; the game's by default) are optional. The other faction's ground counts only
-- when no other water has the fish.
function Fishing.WaterFor(item, skill, level, side, distance, here)
    local best, bestValue, enemyBest, enemyValue
    here = here or CP.Waypoint and CP.Waypoint.PlayerZone and CP.Waypoint.PlayerZone()
    for zone, z in pairs(CP.GatherData.zones) do
        if z.fish and not z.inst and reachable(zone, z, level, here, CP.GatherGuide.SAFE_LEVELS)
            and not CP.Gather.EnemyHome(zone, side) then
            local enemy = side ~= nil and CP.Gather.Territory(zone, side) == "enemy"
            local land = CP.Gather.LandChance(skill, z.fish.base)
            for _, l in ipairs(land > 0 and CP.GatherData.loot[z.fish.loot] or {}) do
                if l[1] == item then
                    local d = distance and distance(zone) or 0
                    local value = l[2] * land / (1 + (d or 0) / Fishing.NEAR_YD)
                    local found = { zone = zone, chance = l[2], land = land }
                    if enemy then
                        if not enemyValue or value > enemyValue then enemyBest, enemyValue = found, value end
                    elseif not bestValue or value > bestValue then
                        best, bestValue = found, value
                    end
                end
            end
        end
    end
    return best or enemyBest
end

-- Fish in `zone`'s water the Cooking guide still needs: { { item, chance, have, need } }.
function Fishing.Feeds(zone, needs, have)
    local z = CP.GatherData.zones[zone]
    local out = {}
    for _, l in ipairs(z and z.fish and CP.GatherData.loot[z.fish.loot] or {}) do
        local need = needs[l[1]]
        local got = have(l[1])
        if need and got < need then
            out[#out + 1] = { item = l[1], chance = l[2], have = got, need = need }
        end
    end
    table.sort(out, function(a, b) return a.chance > b.chance end)
    return out
end

local function feedScore(feeds)
    local score = 0
    for _, f in ipairs(feeds) do score = score + f.chance end
    return score
end

-- What to do next. `s` = { skill, mod, maxRank, level, zone, side, cook, needs, have, distance }:
-- `skill` is the fishing rank alone (rank steps, catches to go); `mod` (a lure or pole, default 0)
-- joins it only for the chance a bite lands. `needs` is the Cooking guide's { [item] = n }, `have(item)` counts the bags and
-- `distance(zone)` is how far the zone is (nil when unknown).
-- Returns { kind = "rank", rank } or { kind = "zone", zone, here, land, catches, feeds }
-- or { kind = "none" } when no safe water lands any bite.
Fishing.NEAR_YD = 1500

function Fishing.Plan(s)
    local rank = Fishing.RankStep(s.skill, s.maxRank, s.side)
    if rank then return { kind = "rank", rank = rank } end

    local list = Fishing.Candidates(s.skill + (s.mod or 0), s.level, s.side, s.zone)
    if #list == 0 then return { kind = "none" } end
    local here
    for _, c in ipairs(list) do
        c.feeds = s.cook and Fishing.Feeds(c.zone, s.needs or {}, s.have) or {}
        c.score = feedScore(c.feeds)
        c.distance = s.distance and s.distance(c.zone) or math.huge
        if c.zone == s.zone then here = c end
    end
    -- What a water feeds Cooking, discounted by the trip: NEAR_YD away counts half, and
    -- water across the sea only wins when nothing on this continent lands anything.
    for _, c in ipairs(list) do
        c.value = (1 + c.score) / (1 + c.distance / Fishing.NEAR_YD)
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        if a.zone == s.zone or b.zone == s.zone then return a.zone == s.zone end
        return a.distance < b.distance
    end)
    local pick = list[1]
    if here and (not s.cook or here.score >= pick.score) then pick = here end
    if here and here.value >= pick.value then pick = here end
    return {
        kind = "zone", zone = pick.zone, here = pick.zone == s.zone, land = pick.land,
        catches = Fishing.CatchesTo(s.skill, s.maxRank), feeds = pick.feeds,
    }
end

-- The biggest pool cluster in `zone` the game places there, as { x, y }, or nil.
function Fishing.Spot(zone)
    local z = CP.GatherData.zones[zone]
    local best
    for entry in pairs(z and z.nodes or {}) do
        local n = CP.GatherData.nodes[entry]
        if n and n[4] == Fishing.SKILL then
            for _, c in ipairs(CP.Gather.Clusters(zone, "nodes", entry)) do
                if not best or c[3] > best[3] then best = c end
            end
        end
    end
    return best and { best[1], best[2] } or nil
end
