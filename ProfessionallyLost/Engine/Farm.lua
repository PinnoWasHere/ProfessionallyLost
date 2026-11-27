local _, CP = ...
if CP.stopped then return end

-- Where to farm an item: the zone whose creatures and nodes give the most of it per
-- square kilometre, for what the player can gather and kill. Only sources the player's
-- skills unlock count (Cooking drops need none); creatures are weighed by kill speed.

local Farm = {}
CP.Farm = Farm

local G = CP.Gather
local SAFE_LEVELS = 3

-- item -> { { kind = "mobs" | "nodes", entry, prof, chance, level? } }, built once.
-- Creatures come from the data's farm index (item, entry, prof, chance, minLevel), so
-- no creature or its loot decodes; `level` is the creature's minimum level.
local index
local function sources(item)
    if not index then
        index = {}
        local D = CP.GatherData
        local farm = D.Index("farm")
        for i = 1, #farm, 5 do
            local entry, prof = farm[i + 1], farm[i + 2]
            if G.Gives(entry, prof) then
                local list = index[farm[i]] or {}
                index[farm[i]] = list
                list[#list + 1] = { kind = "mobs", entry = entry, prof = prof, chance = farm[i + 3], level = farm[i + 4] }
            end
        end
        local function add(key, kind, entry, prof)
            for _, l in ipairs(D.loot[key] or {}) do
                local list = index[l[1]] or {}
                index[l[1]] = list
                list[#list + 1] = { kind = kind, entry = entry, prof = prof, chance = l[2] }
            end
        end
        for entry, n in pairs(D.nodes) do
            if n[4] ~= G.FISHING then add(n[3], "nodes", entry, n[4]) end
        end
    end
    return index[item] or {}
end
Farm.Sources = sources

-- True when the player can take this source with `skills` (skill line -> rank).
local function usable(src, skills)
    local D = CP.GatherData
    if src.kind == "mobs" then
        if src.prof == G.COOKING then return true end
        local rank = skills[src.prof]
        return rank ~= nil and rank >= G.CorpseSkill(src.level)
    end
    local rank = skills[src.prof]
    return rank ~= nil and rank >= math.max(1, D.nodes[src.entry][2] or 1)
end

-- Raised when a background search ends, so a list waiting on it can ask again.
Farm.FOUND = "ProfLost_FARM_FOUND"

local cache = {}
local itemLists = {}   -- Farm.Items' answers by key
local job, generation, wanted = nil, 0, nil
local reach, nodeLevels   -- Farm.Reach's answers and the node levels it reads

function Farm.Reset()
    wipe(cache)
    wipe(itemLists)
    index, reach, nodeLevels = nil, nil, nil
    job, wanted = nil, nil
    generation = generation + 1
end

-- Bumped by each Farm.Reset, so a key built from Farm's answers knows when they may differ.
function Farm.Generation() return generation end

local OTHER_CONTINENT = 0.4   -- a zone across the sea: the boat or zeppelin costs more than half

-- True while the player stands on a starting isle (GatherGuide.START_ONLY).
local function onStart()
    local here = G.PlayerZone()
    return here ~= nil and CP.GatherGuide.START_ONLY[here] ~= nil
end

-- True when `zone` is a starting isle the player is not on: only a player standing there gets it.
local function startShut(zone)
    return CP.GatherGuide.START_ONLY[zone] ~= nil and not onStart()
end

local function keyOf(item, opts)
    local level, skills = opts.level or 1, opts.skills or {}
    local ranks = {}
    for line, rank in pairs(skills) do ranks[#ranks + 1] = line .. "=" .. rank end
    table.sort(ranks)
    return item .. ":" .. level .. ":" .. tostring(opts.side) .. ":" .. tostring(opts.continent) .. ":"
        .. tostring(onStart()) .. ":" .. table.concat(ranks, ",")
end

-- Every item the player can farm somewhere with `skills`: a source they can take that gives
-- it at `minChance` percent or more, from creatures at most SAFE_LEVELS above `level`.
-- Lowest item id first. Kept per skills, level and chance until Farm.Reset.
function Farm.Items(skills, level, minChance)
    local key = keyOf(0, { level = level, skills = skills }) .. ":" .. tostring(minChance)
    if itemLists[key] then return itemLists[key] end
    sources(0)
    local out = {}
    for item, list in pairs(index) do
        for _, src in ipairs(list) do
            local safe = src.kind ~= "mobs" or src.level <= (level or 1) + SAFE_LEVELS
            if src.chance >= (minChance or 0) and safe and usable(src, skills) then
                out[#out + 1] = item
                break
            end
        end
    end
    table.sort(out)
    itemLists[key] = out
    return out
end

-- Farm.Best's search, uncached. `tick` (optional) runs once per zone looked at.
local function search(item, opts, tick)
    local level, skills = opts.level or 1, opts.skills or {}
    local D = CP.GatherData
    local list = {}
    for _, src in ipairs(sources(item)) do
        if usable(src, skills) then list[#list + 1] = src end
    end
    local best
    for zone, z in pairs(#list > 0 and D.zones or {}) do
        if not z.inst and not CP.GatherGuide.SKIP[zone] and not G.EnemyHome(zone, opts.side)
            and not startShut(zone) and not (z.lvl and z.lvl[1] > level + SAFE_LEVELS) then
            local score = 0
            for _, src in ipairs(list) do
                if G.Holds(zone, src.kind, src.entry) and G.Farmable(src.kind, src.entry, zone) then
                    local weight = src.chance / 100
                    if src.kind == "mobs" then
                        local m = D.mobs[src.entry]
                        if m[2] > level + SAFE_LEVELS then weight = 0 end
                        weight = weight * CP.Route.KillSpeed((m[2] + m[3]) / 2, level)
                    end
                    if weight > 0 then
                        for _, c in ipairs(G.Clusters(zone, src.kind, src.entry)) do score = score + c[3] * weight end
                    end
                end
            end
            local area = (z.w and z.h and z.w * z.h or 1e6) / 1e6
            score = score / math.max(area, 1)
            if opts.continent and z.map ~= opts.continent then score = score * OTHER_CONTINENT end
            if score > 0 and (not best or score > best.score) then best = { zone = zone, score = score } end
        end
        if tick then tick() end
    end
    return best
end

-- The best zone for `item`: { zone, score }, or nil. `opts`: level, side, skills,
-- continent (the player's, optional).
function Farm.Best(item, opts)
    local key = keyOf(item, opts)
    if cache[key] ~= nil then return cache[key] or nil end
    local best = search(item, opts)
    cache[key] = best or false
    return best
end

-- A cold search asks the map about every spawn of every source zone, too much for an
-- item tooltip. Farm.Find answers from the cache only and searches in the background,
-- a slice a frame, the way the gathering guides find their zones.
Farm.WARM = { points = 300, frameMs = 4, clockEvery = 25, gap = 0.001 }

local start

-- One frame's work for job `j`, then the next slice on a later frame.
local function slice(j)
    if job ~= j then return end
    j.steps, j.start = 0, debugprofilestop()
    local ok, err = coroutine.resume(j.co)
    if job ~= j then return end
    if not ok then
        job = nil
        CP:Print(("Couldn't find farm zones. /proflost bug to report it (%s)."):format(tostring(err)))
    elseif coroutine.status(j.co) == "dead" then
        job = nil
        local queued = wanted
        wanted = nil
        if queued and cache[queued.key] == nil then start(queued.item, queued.opts, queued.key) end
        CP:Emit(Farm.FOUND)
    else
        C_Timer.After(Farm.WARM.gap, function() slice(j) end)
    end
end

start = function(item, opts, key)
    local gen, cfg = generation, Farm.WARM
    local j = { key = key }
    local function tick()
        j.steps = j.steps + 1
        if j.steps >= cfg.points
            or (j.steps % cfg.clockEvery == 0 and debugprofilestop() - j.start >= cfg.frameMs) then
            coroutine.yield()
        end
    end
    j.co = coroutine.create(function()
        CP.Gather.JobTick(tick)
        local best = search(item, opts, tick)
        if generation == gen then cache[key] = best or false end
    end)
    job = j
    C_Timer.After(cfg.gap, function() slice(j) end)
end

-- The best zone for `item` when it is already known: best, true. Otherwise nil, false,
-- and the search starts in the background (after the one running, if any).
function Farm.Find(item, opts)
    local key = keyOf(item, opts)
    local hit = cache[key]
    if hit ~= nil then return hit or nil, true end
    if not job then
        start(item, opts, key)
    elseif job.key ~= key then
        wanted = { item = item, opts = opts, key = key }
    end
    return nil, false
end

-- True while a background search runs.
function Farm.Warming()
    return job ~= nil
end

-- Nearest place to get an item ------------------------------------------------------

-- With no spot in the player's zone, the nearest this many zones by their middles that hold
-- a spot are measured, and the nearest of their spots wins.
Farm.NEAREST_ZONES = 3

-- `item`'s sources the player's professions take at some skill, as the Gathering panel's
-- sources: { kind = "mob" | "node", entry, name, prof, chance, skill, minLevel?, maxLevel? }.
-- Creatures count as its grind spots do: a skin at the item's Gather.SkinFloor or better,
-- other loot by Gather.GrindSource. Cooking's loot drops for anyone, so it needs no skill.
local function ownSources(item, skills)
    local D, out = CP.GatherData, {}
    for _, s in ipairs(sources(item)) do
        if s.prof == G.COOKING or skills[s.prof] ~= nil then
            if s.kind == "mobs" then
                local m = D.mobs[s.entry]
                local src = m and { kind = "mob", entry = s.entry, name = m[1], minLevel = m[2], maxLevel = m[3],
                    prof = s.prof, chance = s.chance, skill = s.prof == G.COOKING and 0 or G.CorpseSkill(m[2]) }
                local fits
                if s.prof == G.SKINNING then
                    fits = not G.SKIN_EXCLUDE[item] and s.chance >= G.SkinFloor(item)
                else
                    fits = src ~= nil and G.GrindSource(item, src)
                end
                if src and fits then out[#out + 1] = src end
            else
                local n = D.nodes[s.entry]
                out[#out + 1] = { kind = "node", entry = s.entry, name = n[1], prof = n[4], chance = s.chance,
                    skill = math.max(1, n[2] or 1), item = item }
            end
        end
    end
    return out
end

-- True when the player can get `item` themselves at some skill and level: a creature drop,
-- or a source of a gathering profession in `skills` (skill line -> rank).
function Farm.Gatherable(item, skills)
    return G.IsCloth(item) or #ownSources(item, skills) > 0
end

-- Reach: what a gathering profession needs to get an item itself --------------------

-- A node, pool or water counts as a source of an item at this chance per gather or better.
-- Skinning counts a creature as its grind spots do (Gather.SkinFloor).
Farm.REACH_MIN_CHANCE = 5

-- A zone the guide may count on for a gathered material: no instance, skipped zone or starting isle.
local function reachZone(zone, z)
    local GG = CP.GatherGuide
    return not z.inst and not (GG and (GG.SKIP[zone] or GG.START_ONLY[zone]))
end

-- Node entry -> the lowest level of the zones (reachZone) that place it (zone `lvl[1]`, 1 when
-- unknown), or nil when none does.
local function nodeLevel(entry)
    if not nodeLevels then
        nodeLevels = {}
        for zone, z in pairs(CP.GatherData.zones) do
            if reachZone(zone, z) then
                local low = z.lvl and z.lvl[1] or 1
                for code, id in (rawget(z, "has") or ""):gmatch("(%a)(%d+)") do
                    id = tonumber(id)
                    if code == "n" and (not nodeLevels[id] or low < nodeLevels[id]) then nodeLevels[id] = low end
                end
                if not rawget(z, "has") then
                    for id in pairs(z.nodes or {}) do
                        if not nodeLevels[id] or low < nodeLevels[id] then nodeLevels[id] = low end
                    end
                end
            end
        end
    end
    return nodeLevels[entry]
end

-- Fishing's sources of `item`: open water and pools, each { skill, level }. A bite lands while the
-- rank is above the water's base less 5 (Gather.LandChance).
local function fishReach(item, out)
    local D = CP.GatherData
    local function landsAt(base) return base - 4 end
    for zone, z in pairs(D.zones) do
        if z.fish and reachZone(zone, z) then
            local low = z.lvl and z.lvl[1] or 1
            for _, l in ipairs(D.loot[z.fish.loot] or {}) do
                if l[1] == item and l[2] >= Farm.REACH_MIN_CHANCE then
                    out[#out + 1] = { skill = math.max(1, landsAt(z.fish.base)), level = low }
                end
            end
        end
    end
    for entry, n in pairs(D.nodes) do
        if n[4] == G.FISHING then
            for _, l in ipairs(D.loot[n[3]] or {}) do
                if l[1] == item and l[2] >= Farm.REACH_MIN_CHANCE then
                    for zone, z in pairs(D.zones) do
                        if z.fish and reachZone(zone, z) and G.Holds(zone, "nodes", entry) then
                            out[#out + 1] = { skill = math.max(1, landsAt(z.fish.base)), level = z.lvl and z.lvl[1] or 1 }
                        end
                    end
                end
            end
        end
    end
    return out
end

-- What gathering profession `line` needs to get `item` itself, by the data: one { skill, level }
-- per source (the skill the source asks, and the lowest level of the creature or of the zones that
-- hold it), or nil when the data holds no source of the item for `line`. Kept until Farm.Reset.
function Farm.Reach(item, line)
    reach = reach or {}
    local key = item .. ":" .. line
    local hit = reach[key]
    if hit ~= nil then return hit or nil end
    local out = {}
    if line == G.FISHING then
        fishReach(item, out)
    else
        for _, src in ipairs(ownSources(item, { [line] = 0 })) do
            if src.prof == line then
                if src.kind == "mob" then
                    out[#out + 1] = { skill = src.skill, level = src.minLevel }
                elseif src.chance >= Farm.REACH_MIN_CHANCE and nodeLevel(src.entry) then
                    out[#out + 1] = { skill = src.skill, level = nodeLevel(src.entry) }
                end
            end
        end
    end
    reach[key] = #out > 0 and out or false
    return reach[key] or nil
end

-- True when `line` at `rank` gets `item` from a source a character of `level` may farm: a
-- creature at most Gather.FARM_SAFE_LEVELS above them, a node or water in a zone no further
-- above (Farm.Best's rule). Nil `level` judges the skill alone.
function Farm.Reaches(item, line, rank, level)
    for _, src in ipairs(Farm.Reach(item, line) or {}) do
        if rank >= src.skill and (not level or src.level <= level + G.FARM_SAFE_LEVELS) then return true end
    end
    return false
end

local function dataKind(src) return src.kind == "mob" and "mobs" or "nodes" end

-- Zones a place may be in, as Farm.Best's search takes them: no instance, capital, home
-- zone of the other faction, or starting isle the player is not on.
local function openZone(zone, z, side)
    return not z.inst and not CP.GatherGuide.SKIP[zone] and not G.EnemyHome(zone, side) and not startShut(zone)
end

-- The place `placeIn(zone)` finds in the player's zone, else the nearest of the places it
-- finds in the first NEAREST_ZONES zones of `zones` ({ zone, ... }) that have one, taken
-- nearest middle first. Nil when none has one.
local function nearestPlace(zones, placeIn)
    local here = G.PlayerZone()
    for _, z in ipairs(zones) do z.d = CP.Waypoint.Yards(z.zone, 0.5, 0.5) or math.huge end
    table.sort(zones, function(a, b)
        if (a.zone == here) ~= (b.zone == here) then return a.zone == here end
        if a.d ~= b.d then return a.d < b.d end
        return a.zone < b.zone
    end)
    local best, bestD, measured = nil, nil, 0
    for _, z in ipairs(zones) do
        local place = placeIn(z)
        if place then
            if z.zone == here then return place end
            local d = CP.Waypoint.Yards(z.zone, place.x, place.y) or math.huge
            if not bestD or d < bestD then best, bestD = place, d end
            measured = measured + 1
            if measured >= Farm.NEAREST_ZONES then break end
        end
    end
    return best
end

-- The Gathering panel's best grind spot or node patch for `list` in `zone`, ranked from the
-- player's spot when they stand on its continent, or nil.
local function spotIn(zone, item, list, level)
    local w, h = G.ZoneSize(zone)
    if not w then return nil end
    local row = { itemID = item, need = 1, sources = {} }
    for _, src in ipairs(list) do
        if G.Farmable(dataKind(src), src.entry, zone) then row.sources[#row.sources + 1] = src end
    end
    if #row.sources == 0 then return nil end
    local points = CP.Route.Points(zone, { row }, nil, nil, level)
    return CP.Route.GrindSpots(points, w, h, nil, 1, CP.Waypoint.PlayerOn(zone), zone)[1]
end

-- A spot as Farm.Nearest returns it. `chance` is the item's chance averaged over the
-- spot's creatures or nodes, as the panel's drop-chance line shows it.
local function placeOf(zone, spot, item)
    local low, high, sum, n = nil, nil, 0, 0
    for _, a in pairs(spot.about) do
        n = n + 1
        sum = sum + (a.drops[item] or 0)
        if a.minLevel then
            low, high = math.min(low or a.minLevel, a.minLevel), math.max(high or a.maxLevel, a.maxLevel)
        end
    end
    return { zone = zone, x = spot.x, y = spot.y, name = spot.name, prof = spot.prof, kind = low and "mob" or "node",
             low = low, high = high, chance = n > 0 and sum / n or 0, spot = spot }
end

-- Cloth: the Gathering panel's best cloth spot (Gather.Cloth) of the player's zone, else of
-- the nearest zones, or of `only` alone when given. Its `perKill` is the cloth a kill there.
-- With none, why: the lowest level whose bands are safe, else { kind = "none" }.
local function nearestCloth(item, level, side, only)
    local mine = side == "Alliance" and "A" or side == "Horde" and "H" or nil
    local zones, low = {}, nil
    for zone, z in pairs(CP.GatherData.zones) do
        local bands = (not only or zone == only) and openZone(zone, z, side) and z.cloth and z.cloth[item]
        if bands then
            zones[#zones + 1] = { zone = zone }
            for _, b in ipairs(bands) do
                if b[9] == nil or b[9] == mine then low = math.min(low or b[1], b[1]) end
            end
        end
    end
    local place = nearestPlace(zones, function(z)
        local c = G.Cloth(z.zone, item, level, side)
        local s = c and c.spots[1]
        return s and { zone = z.zone, x = s.x, y = s.y, name = s.name, kind = "mob", low = s.lo, high = s.hi,
                       perKill = c.perKill, spot = s }
    end)
    if place then return place end
    if low and not G.ClothSafe(low, level) then
        return nil, { kind = "level", need = low - G.FARM_SAFE_LEVELS }
    end
    return nil, { kind = "none" }
end

-- Why the player can take none of `own` now: { kind = "level", need, name } when a creature
-- is too high for their level (the lowest level that reaches one), else
-- { kind = "skill", prof, need, have, name } (the lowest skill that takes one).
local function blocked(own, skills)
    local byLevel, bySkill
    for _, src in ipairs(own) do
        local have = skills[src.prof] or 0
        if src.prof == G.COOKING or have >= src.skill then
            local need = src.minLevel - G.FARM_SAFE_LEVELS
            if not byLevel or need < byLevel.need then byLevel = { kind = "level", need = need, name = src.name } end
        elseif not bySkill or src.skill < bySkill.need then
            bySkill = { kind = "skill", prof = src.prof, need = src.skill, have = have, name = src.name }
        end
    end
    return byLevel or bySkill
end

-- The nearest place the player can get `item` now, by the Gathering panel's rules: creatures
-- at most Gather.FARM_SAFE_LEVELS above their level that they can loot or skin, nodes their
-- skill gathers, or cloth droppers (Gather.Cloth), in zones Farm.Best would send them to.
-- The best spot of their own zone wins; with none there, the nearest spot of the
-- NEAREST_ZONES nearest zones that have one.
-- `opts` (all optional): skills, level, side, and zone, which looks in that zone alone. Returns
-- { zone, x, y, name, kind = "mob" | "node", low, high, chance or perKill (cloth), prof, spot },
-- or nil and why: nil when no source suits their professions, else { kind = "level", need, name },
-- { kind = "skill", prof, need, have, name } or { kind = "none" } (no zone has a spot).
function Farm.Nearest(item, opts)
    opts = opts or {}
    local skills = opts.skills or G.Skills()
    local level = opts.level or G.PlayerLevel()
    local side = opts.side or UnitFactionGroup("player")
    if G.IsCloth(item) then return nearestCloth(item, level, side, opts.zone) end
    local own = ownSources(item, skills)
    if #own == 0 then return nil, nil end
    local now = {}
    for _, src in ipairs(own) do
        local skillOk = src.prof == G.COOKING or (skills[src.prof] or 0) >= src.skill
        if skillOk and (src.kind ~= "mob" or src.minLevel <= level + G.FARM_SAFE_LEVELS) then now[#now + 1] = src end
    end
    if #now == 0 then return nil, blocked(own, skills) end

    local zones = {}
    for zone, z in pairs(CP.GatherData.zones) do
        if (not opts.zone or zone == opts.zone) and openZone(zone, z, side) then
            local holds = {}
            for _, src in ipairs(now) do
                if G.Holds(zone, dataKind(src), src.entry) then holds[#holds + 1] = src end
            end
            if #holds > 0 then zones[#zones + 1] = { zone = zone, list = holds } end
        end
    end
    local place = nearestPlace(zones, function(z)
        local spot = spotIn(z.zone, item, z.list, level)
        return spot and placeOf(z.zone, spot, item)
    end)
    if place then return place end
    return nil, { kind = "none" }
end
