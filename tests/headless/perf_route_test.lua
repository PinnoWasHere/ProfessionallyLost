-- The route's pacing and costs: grind spots, stop merging, item tooltips, find settling and
-- vendor checks give the same answers at a fraction of the work. Each equivalence test
-- runs a private copy of the earlier algorithm beside the addon's and wants deep equality.

local CP = ProfLost
local R, G = CP.Route, CP.Gather
local SKIN = 393
local BARRENS, DUROTAR, HILLSBRAD, SILVERPINE, ASHENVALE = 1413, 1411, 1424, 1421, 1440
local MEDIUM_LEATHER = 2319

-- Helpers ---------------------------------------------------------------------------

-- The first path where `a` and `b` differ, or nil. Numbers compare exactly.
local function diff(a, b, path, seen)
    path, seen = path or "", seen or {}
    if type(a) ~= type(b) then return path .. (": %s vs %s"):format(type(a), type(b)) end
    if type(a) ~= "table" then
        if a ~= b and not (a ~= a and b ~= b) then return path .. (": %s vs %s"):format(tostring(a), tostring(b)) end
        return nil
    end
    if seen[a] == b then return nil end
    seen[a] = b
    for k, v in pairs(a) do
        local d = diff(v, b[k], path .. "." .. tostring(k), seen)
        if d then return d end
    end
    for k in pairs(b) do
        if a[k] == nil then return path .. "." .. tostring(k) .. ": missing on the left" end
    end
    return nil
end

local function same(a, b, label)
    local d = diff(a, b)
    T.ok(d == nil, label .. (d and (" differs at " .. d) or ""))
end

-- A fixed-seed generator: 0 <= n < 1.
local function rng(seed)
    return function()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
    end
end

-- Zone rows built straight from the data: every creature drop and every herb or ore node
-- of `zone` the skill reaches (nodes up to 100 above it come in as `later`).
local function zoneRows(zone, skill)
    local D = CP.GatherData
    local z = D.zones[zone] or {}
    local rows, byItem = {}, {}
    local mobs, nodes = {}, {}
    for entry in pairs(z.mobs or {}) do mobs[#mobs + 1] = entry end
    for entry in pairs(z.nodes or {}) do nodes[#nodes + 1] = entry end
    table.sort(mobs)
    table.sort(nodes)
    for _, entry in ipairs(mobs) do
        local m = D.mobs[entry]
        for prof, key in pairs(m and m[4] or {}) do
            local need = prof == G.COOKING and 0 or G.CorpseSkill(m[2])
            if need <= skill then
                for _, l in ipairs(D.loot[key] or {}) do
                    local row = byItem[l[1]]
                    if not row then
                        row = { itemID = l[1], need = 10, sources = {} }
                        byItem[l[1]], rows[#rows + 1] = row, row
                    end
                    row.sources[#row.sources + 1] = { kind = "mob", entry = entry, name = m[1], minLevel = m[2],
                        maxLevel = m[3], skill = need, chance = l[2], prof = prof }
                end
            end
        end
    end
    for _, entry in ipairs(nodes) do
        local n = D.nodes[entry]
        if n and n[2] and (n[4] == G.HERBALISM or n[4] == G.MINING) and n[2] <= skill + 100 then
            local loot = D.loot[n[3]]
            rows[#rows + 1] = { itemID = -entry, need = 1, later = skill < n[2] or nil,
                sources = { { kind = "node", entry = entry, name = n[1], chance = 100, prof = n[4], skill = n[2],
                              item = loot and loot[1] and loot[1][1] } } }
        end
    end
    return rows
end

-- The earlier algorithms, kept here as the reference -----------------------------------

local sqrt = math.sqrt

local function refDist(a, b, w, h)
    local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
    return sqrt(dx * dx + dy * dy)
end

local function refGrindSpots(points, w, h, radius, count, from, zone)
    radius, count = radius or R.GRIND_YD, count or R.GRIND_SPOTS
    local dist = refDist
    local left, out = {}, {}
    for i, p in ipairs(points) do left[i] = p end
    while #out < count and #left > 0 do
        local best, bestValue
        for _, c in ipairs(left) do
            local v = 0
            for _, p in ipairs(left) do
                if dist(c, p, w, h) <= radius then v = v + (p.score or p.value) end
            end
            if from then v = v / (1 + dist(c, from, w, h) / R.NEAR_YD) end
            if not bestValue or v > bestValue then best, bestValue = c, v end
        end
        local spot = { x = 0, y = 0, value = 0, parts = {}, items = {}, about = {} }
        local top = -1
        for i = #left, 1, -1 do
            local p = left[i]
            if dist(best, p, w, h) <= radius then
                spot.x, spot.y = spot.x + p.x * p.value, spot.y + p.y * p.value
                spot.value = spot.value + p.value
                for k, v in pairs(p.parts or {}) do spot.parts[k] = (spot.parts[k] or 0) + v end
                for k, v in pairs(p.items or {}) do spot.items[k] = (spot.items[k] or 0) + v end
                for k, v in pairs(p.about or {}) do spot.about[k] = v end
                if p.value > top then top, spot.prof = p.value, p.prof end
                table.remove(left, i)
            end
        end
        spot.x, spot.y = spot.x / spot.value, spot.y / spot.value
        if zone and not CP.Gather.Inside(zone, spot.x, spot.y) then spot.x, spot.y = best.x, best.y end
        local reach = 0
        for _, p in ipairs(points) do
            if dist(best, p, w, h) <= radius then reach = math.max(reach, dist(spot, p, w, h)) end
        end
        spot.radius = math.max(60, reach + 40)
        local bestPart, bestItem = -1, -1
        for k, v in pairs(spot.parts) do
            if v > bestPart then bestPart, spot.name = v, k end
        end
        for k, v in pairs(spot.items) do
            if v > bestItem then bestItem, spot.itemID = v, k end
        end
        spot.name = spot.name or "creatures"
        out[#out + 1] = spot
        spot.rank = #out
    end
    return out
end

local function refMerge(points, w, h, radius)
    radius = radius or R.CLUSTER_YD
    local order = {}
    for i, p in ipairs(points) do order[i] = p end
    table.sort(order, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local cells = {}
    local function cellKey(cx, cy) return cx * 100000 + cy end
    for _, p in ipairs(order) do
        local k = cellKey(math.floor(p.x * w / radius), math.floor(p.y * h / radius))
        cells[k] = cells[k] or {}
        table.insert(cells[k], p)
    end
    local taken, out = {}, {}
    local r2 = radius * radius
    for _, lead in ipairs(order) do
        if not taken[lead] then
            local c = { sx = 0, sy = 0, value = 0, score = 0, best = -1, parts = {}, items = {}, about = {} }
            local cx, cy = math.floor(lead.x * w / radius), math.floor(lead.y * h / radius)
            for dx = -1, 1 do
                for dy = -1, 1 do
                    for _, p in ipairs(cells[cellKey(cx + dx, cy + dy)] or {}) do
                        local ex, ey = (p.x - lead.x) * w, (p.y - lead.y) * h
                        if not taken[p] and ex * ex + ey * ey <= r2 then
                            taken[p] = true
                            c.sx, c.sy = c.sx + p.x * p.value, c.sy + p.y * p.value
                            c.value = c.value + p.value
                            c.score = c.score + (p.score or p.value)
                            for k, v in pairs(p.parts or {}) do c.parts[k] = (c.parts[k] or 0) + v end
                            for k, v in pairs(p.items or {}) do c.items[k] = (c.items[k] or 0) + v end
                            for k, v in pairs(p.about or {}) do c.about[k] = v end
                            for m in pairs(p.mixes or {}) do
                                c.mixes = c.mixes or {}
                                c.mixes[m] = true
                            end
                            if p.value > c.best then c.best, c.prof, c.name, c.kind = p.value, p.prof, p.name, p.kind end
                        end
                    end
                end
            end
            if c.value > 0 then
                c.x, c.y = c.sx / c.value, c.sy / c.value
            else
                c.x, c.y = lead.x, lead.y
            end
            c.sx, c.sy, c.best = nil, nil, nil
            out[#out + 1] = c
        end
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    local grid2 = {}
    for _, c in ipairs(out) do
        local k = cellKey(math.floor(c.x * w / radius), math.floor(c.y * h / radius))
        grid2[k] = grid2[k] or {}
        table.insert(grid2[k], c)
    end
    local gone = {}
    for _, a in ipairs(out) do
        if not gone[a] then
            local cx, cy = math.floor(a.x * w / radius), math.floor(a.y * h / radius)
            local best, bestD
            for dx = -1, 1 do
                for dy = -1, 1 do
                    for _, b in ipairs(grid2[cellKey(cx + dx, cy + dy)] or {}) do
                        if b ~= a and not gone[b] then
                            local ex, ey = (a.x - b.x) * w, (a.y - b.y) * h
                            local d = ex * ex + ey * ey
                            if d <= r2 and (not bestD or d < bestD) then best, bestD = b, d end
                        end
                    end
                end
            end
            if best then
                local v = a.value + best.value
                a.x, a.y = (a.x * a.value + best.x * best.value) / v, (a.y * a.value + best.y * best.value) / v
                a.value, a.score = v, (a.score or 0) + (best.score or 0)
                for k, x in pairs(best.parts) do a.parts[k] = (a.parts[k] or 0) + x end
                for k, x in pairs(best.items) do a.items[k] = (a.items[k] or 0) + x end
                for k, x in pairs(best.about) do a.about[k] = x end
                for m in pairs(best.mixes or {}) do
                    a.mixes = a.mixes or {}
                    a.mixes[m] = true
                end
                gone[best] = true
            end
        end
    end
    local kept = {}
    for _, c in ipairs(out) do
        if not gone[c] then kept[#kept + 1] = c end
    end
    out = kept
    table.sort(out, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return out
end

local function refKeepInside(zone, stops, points, w, h)
    for _, s in ipairs(stops) do
        if not G.Inside(zone, s.x, s.y) then
            local best, bestD
            for _, p in ipairs(points) do
                local d = refDist(s, p, w, h)
                if (not bestD or d < bestD) and G.Inside(zone, p.x, p.y) then best, bestD = p, d end
            end
            if best then s.x, s.y = best.x, best.y end
        end
    end
    return stops
end

local function refPoints(zone, rows, only, level)
    local clusters = function(kind, entry) return G.Clusters(zone, kind, entry) end
    local byKey, out = {}, {}
    local later = only == "later"
    if later then only = "node" end
    for _, row in ipairs(rows) do
        if row.need and not row.done and (row.later == true) == later then
            for _, src in ipairs(row.sources) do
                if (src.kind == "mob" or src.kind == "node") and src.entry and (not only or src.kind == only)
                    and G.GrindSource(row.itemID, src) then
                    local kind = src.kind == "mob" and "mobs" or "nodes"
                    for i, c in ipairs(clusters(kind, src.entry)) do
                        local key = kind .. src.entry .. ":" .. i
                        local p = byKey[key]
                        if not p then
                            p = { x = c[1], y = c[2], value = 0, score = 0, prof = src.prof, name = src.name,
                                kind = src.kind, parts = {}, items = {}, about = {} }
                            byKey[key], out[#out + 1] = p, p
                        end
                        local v = c[3] * src.chance / 100
                        local mobLevel = src.minLevel and src.maxLevel and (src.minLevel + src.maxLevel) / 2
                        p.value = p.value + v
                        p.score = p.score + v * (src.kind == "mob" and R.KillSpeed(mobLevel, level) or 1)
                        p.parts[src.name] = (p.parts[src.name] or 0) + v
                        p.items[row.itemID] = (p.items[row.itemID] or 0) + v
                        local a = p.about[src.name] or { minLevel = src.minLevel, maxLevel = src.maxLevel, drops = {},
                                                         skill = src.skill, item = src.item or (row.itemID > 0 and row.itemID or nil) }
                        a.drops[row.itemID] = src.chance
                        p.about[src.name] = a
                        if c.mix then
                            p.mixes = p.mixes or {}
                            p.mixes[c.mix] = true
                        end
                    end
                end
            end
        end
    end
    local w, h = G.ZoneSize(zone)
    if not w then return out end
    return refKeepInside(zone, refMerge(out, w, h), out, w, h)
end

-- Random creature stops with ties, repeats and missing scores.
local function randomPoints(next, n, opts)
    opts = opts or {}
    local out = {}
    for i = 1, n do
        local p
        if opts.repeats and i > 3 and next() < 0.1 then
            local q = out[math.floor(next() * (i - 1)) + 1]
            p = { x = q.x, y = q.y, value = q.value, score = q.score, prof = q.prof }
        else
            p = { x = next(), y = next(), value = math.floor(next() * 5) + 1, prof = next() < 0.5 and SKIN or G.COOKING }
            if next() < 0.7 then p.score = p.value * (math.floor(next() * 4) + 1) / 2 end
        end
        local name = "Beast " .. math.floor(next() * 6)
        p.parts = { [name] = p.value }
        p.items = { [2318 + math.floor(next() * 3)] = p.value }
        p.about = { [name] = { minLevel = 10, maxLevel = 12, drops = { [2318] = 40 } } }
        out[i] = p
    end
    return out
end

-- GrindSpots (B15a) -----------------------------------------------------------------------

T.test("grind spots match the reference algorithm on real zones, skills and levels", function()
    local cases = {
        { BARRENS, "Horde", 150, 25 }, { BARRENS, "Alliance", 300, 40 }, { HILLSBRAD, "Alliance", 150, 28 },
        { HILLSBRAD, "Horde", 225, 35 }, { DUROTAR, "Horde", 60, 10 }, { SILVERPINE, "Horde", 100, 20 },
        { ASHENVALE, "Alliance", 200, 30 },
    }
    local compared = 0
    for _, c in ipairs(cases) do
        local zone, side, skill, level = c[1], c[2], c[3], c[4]
        MapWorld.begin({ zone = zone, x = 0.4, y = 0.6, level = level, side = side })
        local w, h = G.ZoneSize(zone)
        local mobs = R.Points(zone, zoneRows(zone, skill), nil, "mob", level)
        T.ok(#mobs > 20, ("%d: %d creature stops"):format(zone, #mobs))
        local from = { x = 0.4, y = 0.6 }
        for _, args in ipairs({ { nil, nil, nil, nil }, { nil, nil, from, zone }, { 300, 5, from, nil }, { 60, 1, nil, zone } }) do
            local label = ("%d skill %d level %d radius %s count %s%s%s"):format(zone, skill, level, tostring(args[1]),
                tostring(args[2]), args[3] and " from" or "", args[4] and " zone" or "")
            same(R.GrindSpots(mobs, w, h, args[1], args[2], args[3], args[4]),
                refGrindSpots(mobs, w, h, args[1], args[2], args[3], args[4]), label)
            compared = compared + 1
        end
    end
    T.eq(compared, 28)
end)

T.test("grind spots match the reference algorithm on random stops, with and without from and zone", function()
    MapWorld.begin({ zone = BARRENS, level = 30, side = "Horde" })
    local next = rng(20261115)
    local w, h = G.ZoneSize(BARRENS)
    for _, n in ipairs({ 0, 1, 2, 3, 7, 40, 150, 400 }) do
        for round = 1, 3 do
            local pts = randomPoints(next, n, { repeats = round > 1 })
            local from = round ~= 2 and { x = next(), y = next() } or nil
            local zone = round == 3 and BARRENS or nil
            local radius = ({ nil, 90, 400 })[round]
            local count = ({ nil, 4, 6 })[round]
            local label = ("n %d round %d"):format(n, round)
            same(R.GrindSpots(pts, w, h, radius, count, from, zone), refGrindSpots(pts, w, h, radius, count, from, zone), label)
        end
    end
    -- Stacked points, all on one spot and all at the same value: ties break the same way.
    local stack = {}
    for i = 1, 30 do stack[i] = { x = 0.5, y = 0.5, value = 1, parts = { ["Beast " .. i % 4] = 1 }, items = { [2318] = 1 } } end
    same(R.GrindSpots(stack, w, h), refGrindSpots(stack, w, h), "stacked")
    -- A grid exactly one radius apart, so every neighbour sits on the boundary.
    local edge, step = {}, 150 / w
    for i = 0, 9 do
        for j = 0, 9 do edge[#edge + 1] = { x = 0.2 + i * step, y = 0.2 + j * 150 / h, value = 1 + (i + j) % 2 } end
    end
    same(R.GrindSpots(edge, w, h), refGrindSpots(edge, w, h), "boundary grid")
    same(R.GrindSpots(edge, w, h, 0), refGrindSpots(edge, w, h, 0), "radius 0")
end)

-- Stops whose x reads are counted: each straight-line distance reads two x's.
local function counted(points)
    local reads = { n = 0 }
    local out = {}
    for i, p in ipairs(points) do
        out[i] = setmetatable({}, { __index = function(_, k)
            if k == "x" then reads.n = reads.n + 1 end
            return p[k]
        end })
    end
    return out, reads
end

T.test("grind spots on a 1,000-stop zone test far fewer distances than every pair", function()
    MapWorld.begin({ zone = BARRENS, level = 30, side = "Horde" })
    local next = rng(4242)
    local pts, reads = counted(randomPoints(next, 1000))
    local w, h = 5000, 5000
    R.GrindSpots(pts, w, h)
    -- Every pair once is 1,000,000 distances, 2,000,000 x reads; the old search made about 6,000,000.
    T.ok(reads.n < 100000, ("%d x reads for 1,000 stops"):format(reads.n))
end)

-- Merge and Points (B15b) --------------------------------------------------------------

T.test("merging stops ticks as it goes and merges exactly as before", function()
    for _, zone in ipairs({ BARRENS, HILLSBRAD, SILVERPINE }) do
        MapWorld.begin({ zone = zone, level = 30, side = "Horde" })
        local w, h = G.ZoneSize(zone)
        local raw = {}
        for _, row in ipairs(zoneRows(zone, 300)) do
            for _, src in ipairs(row.sources) do
                local kind = src.kind == "mob" and "mobs" or "nodes"
                for _, c in ipairs(G.Clusters(zone, kind, src.entry)) do
                    raw[#raw + 1] = { x = c[1], y = c[2], value = c[3] * src.chance / 100, prof = src.prof, name = src.name,
                        kind = src.kind, parts = { [src.name] = c[3] }, items = { [row.itemID] = c[3] }, about = {} }
                end
            end
        end
        local ticks = 0
        local merged = R.Merge(raw, w, h, nil, function() ticks = ticks + 1 end)
        same(merged, refMerge(raw, w, h), zone .. " merge")
        T.ok(ticks >= #raw, ("%d: %d ticks for %d points"):format(zone, ticks, #raw))
    end
end)

T.test("route points tick as they build and give the same stops as before", function()
    for _, c in ipairs({ { BARRENS, 150, 25 }, { HILLSBRAD, 200, 30 }, { DUROTAR, 75, 12 } }) do
        local zone, skill, level = c[1], c[2], c[3]
        MapWorld.begin({ zone = zone, level = level, side = "Horde" })
        local rows = zoneRows(zone, skill)
        for _, only in ipairs({ "mob", "node", "later" }) do
            local expect = refPoints(zone, rows, only, level)
            local ticks = 0
            local got = R.Points(zone, rows, nil, only, level, function() ticks = ticks + 1 end)
            same(got, expect, ("%d %s points"):format(zone, only))
            T.ok(#got == 0 or ticks >= #got, ("%d %s: %d ticks for %d stops"):format(zone, only, ticks, #got))
        end
    end
end)

T.test("a terrain grid ticks while it walks the zone's spawns", function()
    MapWorld.begin({ zone = HILLSBRAD, level = 30, side = "Horde" })
    local w, h = G.ZoneSize(HILLSBRAD)
    local ticks = 0
    local grid = CP.Terrain.Grid(HILLSBRAD, w, h, { side = "Horde", level = 30 }, function() ticks = ticks + 1 end)
    T.ok(grid, "a grid")
    T.ok(ticks > 100, ("%d ticks"):format(ticks))
end)

T.test("footprints are only taken with the route on, Herbalism or Mining, and out of combat", function()
    MapWorld.begin({ zone = HILLSBRAD, level = 30, side = "Horde" })
    local TR = CP.Terrain
    local mining, combat = true, false
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == G.MINING and mining then return { skillID = id, rank = 100, modifier = 0 } end
        if id == SKIN then return { skillID = id, rank = 100, modifier = 0 } end
        return nil
    end)
    World.set(_G, "InCombatLockdown", function() return combat end)
    local saved, route = CP.db.footprints, CP.db.route
    local ok, err = pcall(function()
        local function steps()
            CP.db.footprints = {}
            T.advance(TR.LEARN_EVERY * 3)
            return next(CP.db.footprints[HILLSBRAD] or {}) ~= nil
        end
        CP.db.route = true
        T.ok(TR.Wanted(), "route on with Mining")
        T.ok(steps(), "a footprint is taken")
        CP.db.route = false
        T.ok(not TR.Wanted() and not steps(), "none with the route off")
        CP.db.route, combat = true, true
        T.ok(not TR.Wanted() and not steps(), "none in combat")
        combat, mining = false, false
        T.ok(not TR.Wanted() and not steps(), "none with only Skinning")
    end)
    CP.db.footprints, CP.db.route = saved, route
    TR.Reset()
    T.ok(ok, err)
end)

-- Item tooltips (B3) ---------------------------------------------------------------------

T.test("an item tooltip on cold zone data asks the map nothing, then names the zone once found", function()
    MapWorld.begin({ zone = DUROTAR, level = 29, side = "Horde" })
    CraftWorld.begin({})
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN then return { skillID = id, rank = 194, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    CP.charDB.gatherNeeds = { [165] = { [MEDIUM_LEATHER] = 20 } }
    local asks, live = 0, CP.Waypoint.MapPosZone
    World.set(CP.Waypoint, "MapPosZone", function(...)
        asks = asks + 1
        return live(...)
    end)
    local lines = CP.ItemTooltip.Lines(MEDIUM_LEATHER)
    T.eq(asks, 0, "no map lookups from the tooltip")
    local text = {}
    for _, l in ipairs(lines) do text[#text + 1] = l[1] .. (l[2] and (" | " .. l[2]) or "") end
    text = table.concat(text, "\n")
    T.ok(text:find("needs x20", 1, true) ~= nil, text)
    T.ok(text:find(CP.GatherGuide.WARM.waiting, 1, true) ~= nil, "a placeholder while zones are found: " .. text)

    for _ = 1, 20000 do
        if not CP.Farm.Warming() then break end
        T.advance(0.02, 0.02)
    end
    T.ok(not CP.Farm.Warming(), "the search ends")
    local best = CP.Farm.Best(MEDIUM_LEATHER, { level = 29, side = "Horde", skills = G.Skills(),
        continent = (CP.Waypoint.PlayerWorld()) })
    T.ok(best ~= nil, "a farm zone")
    local name = C_Map.GetMapInfo(best.zone).name
    CP.charDB.gatherNeeds = { [165] = { [MEDIUM_LEATHER] = 20 } }
    local after = {}
    for _, l in ipairs(CP.ItemTooltip.Lines(MEDIUM_LEATHER)) do after[#after + 1] = l[1] end
    after = table.concat(after, "\n")
    T.ok(after:find("Farm in " .. name, 1, true) ~= nil, after)
    CP.charDB.gatherNeeds = nil
end)

-- Find settling (B4) ---------------------------------------------------------------------

T.test("a find settles into its own zone's caches; other zones keep theirs", function()
    MapWorld.begin({ zone = BARRENS, level = 30, side = "Horde" })
    -- Finds an earlier test left waiting settle now.
    T.fire("ZONE_CHANGED_NEW_AREA")
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    local saved = CP.db.finds
    CP.db.finds = {}
    local builds = {}
    local nodes = CP.Finds.Nodes
    World.set(CP.Finds, "Nodes", function(zone)
        builds[zone] = (builds[zone] or 0) + 1
        return nodes(zone)
    end)
    local ok, err = pcall(function()
        G.ResetClusters()
        local copper = G.NodeEntry("Copper Vein")
        local a1 = G.Clusters(BARRENS, "nodes", copper)
        local b1 = G.Clusters(DUROTAR, "nodes", copper)
        local mobB = G.Clusters(DUROTAR, "mobs", 3098)   -- Mottled Boar
        T.eq(builds[BARRENS], 1)
        T.eq(builds[DUROTAR], 1)
        builds = {}
        CP.Finds.Add(BARRENS, "n", "Copper Vein", 0.4321, 0.4321)
        T.advance(CP.GatherMate.SETTLE + 1)
        T.ok(not CP.GatherMate.Pending(), "settled")
        local a2 = G.Clusters(BARRENS, "nodes", copper)
        local b2 = G.Clusters(DUROTAR, "nodes", copper)
        T.eq(#a2, #a1 + 1, "the find joins its zone's clusters")
        T.eq(builds[BARRENS], 1, "the find's zone is rebuilt once")
        T.eq(builds[DUROTAR], nil, "another zone isn't rebuilt")
        T.ok(b2 == b1, "another zone's clusters are reused")
        T.ok(G.Clusters(DUROTAR, "mobs", 3098) == mobB, "and its creature clusters too")

        -- What the zones show after the settle is what a full rebuild gives.
        local skills = { [G.MINING] = 100, [G.HERBALISM] = 100, [SKIN] = 100 }
        local function shown()
            local out = {}
            for _, zone in ipairs({ BARRENS, DUROTAR }) do
                out[zone] = { rows = G.BuildZone(zone, skills, { here = G.Farmable }),
                              stops = R.Points(zone, zoneRows(zone, 100), nil, "node") }
            end
            return out
        end
        local settled = shown()
        G.ResetClusters()
        same(settled, shown(), "rows and stops after the settle")
    end)
    CP.db.finds = saved
    T.ok(ok, err)
end)

-- Vendor checks (B11) --------------------------------------------------------------------

T.test("a second vendor check in a row asks the map nothing", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde", count = true })
    CraftWorld.begin({})
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local guide = CP.Guides[165]
    local npcs = {}
    for entry, npc in pairs(guide.npcs or {}) do
        if (npc[2] == "H" or npc[2] == "N") and #(npc[3] or {}) > 0 then npcs[#npcs + 1] = entry end
    end
    table.sort(npcs)
    T.ok(#npcs > 3, "vendors to watch")
    CP.charDB.vendorWatch = { [165] = { { name = "Pattern Thing", item = 9001, skill = 1, npcs = npcs } } }
    local saved = CP.db.vendorAlerts
    CP.db.vendorAlerts = true
    local spawns = 0
    local spawnZone = CP.Waypoint.SpawnZone
    World.set(CP.Waypoint, "SpawnZone", function(at)
        spawns = spawns + 1
        return spawnZone(at)
    end)
    CP.VendorWatch.Check()
    local first, firstMap = spawns, MapWorld.calls.GetMapPosFromWorldPos or 0
    T.ok(first > 0 and firstMap > 0, ("the first check places spawns (%d, %d map calls)"):format(first, firstMap))
    spawns, MapWorld.calls = 0, {}
    CP.VendorWatch.Check()
    T.eq(spawns, 0, "the second check places none")
    T.eq(MapWorld.calls.GetMapPosFromWorldPos or 0, 0, "and asks the map for none")
    CP.db.vendorAlerts = saved
    CP.charDB.vendorWatch = nil
end)
