local _, CP = ...
if CP.stopped then return end

-- Where to farm an item: the zone whose creatures and nodes give the most of it per
-- square kilometre, for what the player can gather and kill. Only sources the player's
-- skills unlock count (Cooking drops need none); creatures are weighed by kill speed.

local Farm = {}
CP.Farm = Farm

local G = CP.Gather
local SAFE_LEVELS = 3

-- item -> { { kind = "mobs" | "nodes", entry, prof, chance } }, built once.
local index
local function sources(item)
    if not index then
        index = {}
        local D = CP.GatherData
        local function add(key, kind, entry, prof)
            for _, l in ipairs(D.loot[key] or {}) do
                local list = index[l[1]] or {}
                index[l[1]] = list
                list[#list + 1] = { kind = kind, entry = entry, prof = prof, chance = l[2] }
            end
        end
        for entry, m in pairs(D.mobs) do
            for prof, key in pairs(m[4]) do
                if G.Gives(entry, prof) then add(key, "mobs", entry, prof) end
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
        return rank ~= nil and rank >= G.CorpseSkill(D.mobs[src.entry][2])
    end
    local rank = skills[src.prof]
    return rank ~= nil and rank >= math.max(1, D.nodes[src.entry][2] or 1)
end

-- Raised when a background search ends, so a list waiting on it can ask again.
Farm.FOUND = "ProfLost_FARM_FOUND"

local cache = {}
local itemLists = {}   -- Farm.Items' answers by key
local job, generation, wanted = nil, 0, nil

function Farm.Reset()
    wipe(cache)
    wipe(itemLists)
    index = nil
    job, wanted = nil, nil
    generation = generation + 1
end

local OTHER_CONTINENT = 0.4   -- a zone across the sea: the boat or zeppelin costs more than half

local function keyOf(item, opts)
    local level, skills = opts.level or 1, opts.skills or {}
    local ranks = {}
    for line, rank in pairs(skills) do ranks[#ranks + 1] = line .. "=" .. rank end
    table.sort(ranks)
    return item .. ":" .. level .. ":" .. tostring(opts.side) .. ":" .. tostring(opts.continent) .. ":"
        .. table.concat(ranks, ",")
end

-- Every item the player can farm somewhere with `skills`: a source they can take that gives
-- it at `minChance` percent or more, from creatures at most SAFE_LEVELS above `level`.
-- Lowest item id first. Kept per skills, level and chance until Farm.Reset.
function Farm.Items(skills, level, minChance)
    local key = keyOf(0, { level = level, skills = skills }) .. ":" .. tostring(minChance)
    if itemLists[key] then return itemLists[key] end
    sources(0)
    local D, out = CP.GatherData, {}
    for item, list in pairs(index) do
        for _, src in ipairs(list) do
            local safe = src.kind ~= "mobs" or D.mobs[src.entry][2] <= (level or 1) + SAFE_LEVELS
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
            and not (z.lvl and z.lvl[1] > level + SAFE_LEVELS) then
            local score = 0
            for _, src in ipairs(list) do
                if z[src.kind] and z[src.kind][src.entry] and G.Farmable(src.kind, src.entry, zone) then
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
