-- Zone borders: every per-zone point goes through Gather.Inside, which asks the
-- continent map whose ground it is. The data lists a creature or node under every
-- zone rectangle holding its spawns, and most of Dustwallow sits inside the Barrens'.

local CP = ProfLost
local G, R = CP.Gather, CP.Route
local BARRENS, DUSTWALLOW = 1413, 1445
local RATCHET = { x = 0.63, y = 0.37 }
local HEAVY_LEATHER, THICK_LEATHER = 4234, 4304
local YOUNG_MURK_THRESHER = 4388   -- Dustwallow's coast, listed under the Barrens' rectangle too
local DEEP_DUSTWALLOW = { x = 0.72, y = 0.83 }   -- on the Barrens map

local function scene()
    MapWorld.begin({ zone = BARRENS, x = RATCHET.x, y = RATCHET.y, level = 40, side = "Horde" })
end

local function rowsFor(skills, wanted)
    local rows = {}
    for _, row in ipairs(G.ForZone(BARRENS, skills, { here = G.Farmable })) do
        if not wanted or wanted[row.itemID] then
            row.need, row.done = 100, false
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function zoneOf(x, y) return CP.Waypoint.MapPosZone(BARRENS, x, y) end

T.test("the fixture puts deep Dustwallow in Dustwallow and Ratchet in the Barrens", function()
    scene()
    T.eq(zoneOf(DEEP_DUSTWALLOW.x, DEEP_DUSTWALLOW.y), DUSTWALLOW)
    T.eq(zoneOf(RATCHET.x, RATCHET.y), BARRENS)
end)

T.test("Barrens grind spots for Heavy and Thick Leather all map to the Barrens", function()
    scene()
    local rows = rowsFor({ [G.SKINNING] = 233 }, { [HEAVY_LEATHER] = true, [THICK_LEATHER] = true })
    T.eq(#rows, 2, "both leathers are skinnable here")
    local w, h = G.ZoneSize(BARRENS)
    local spots = R.GrindSpots(R.Points(BARRENS, rows, nil, "mob", 40), w, h, nil, 3, RATCHET, BARRENS)
    T.eq(#spots, 3)
    for i, spot in ipairs(spots) do
        T.eq(zoneOf(spot.x, spot.y), BARRENS, "spot " .. i .. " centre")
        T.ok(spot.parts["Young Murk Thresher"] == nil, "spot " .. i .. " has no Dustwallow coast creature")
    end
    for _, row in ipairs(rows) do
        for _, src in ipairs(row.sources) do
            if src.kind == "mob" then
                for _, c in ipairs(G.Clusters(BARRENS, "mobs", src.entry)) do
                    T.eq(zoneOf(c[1], c[2]), BARRENS, src.name .. " spawn")
                end
            end
        end
    end
end)

T.test("Barrens herb and ore stops all map to the Barrens", function()
    scene()
    local rows = rowsFor({ [G.HERBALISM] = 233, [G.MINING] = 233 })
    local stops = R.Points(BARRENS, rows, nil, "node")
    T.ok(#stops > 10, "the Barrens has herb and ore stops")
    for i, s in ipairs(stops) do T.eq(zoneOf(s.x, s.y), BARRENS, "stop " .. i) end
end)

T.test("a Dustwallow-only creature never becomes a Barrens spot", function()
    scene()
    local raw = G.Decode(CP.GatherData.zones[BARRENS].mobs[YOUNG_MURK_THRESHER])
    T.ok(#raw > 0, "the data lists it under the Barrens' rectangle")
    T.eq(G.Spawns(BARRENS, "mobs", YOUNG_MURK_THRESHER), 0, "none of its spawns count for the Barrens")
    T.ok(not G.Farmable("mobs", YOUNG_MURK_THRESHER, BARRENS))
    T.ok(G.Spawns(DUSTWALLOW, "mobs", YOUNG_MURK_THRESHER) > 0, "its spawns count for Dustwallow")
    local m = CP.GatherData.mobs[YOUNG_MURK_THRESHER]
    local row = { itemID = HEAVY_LEATHER, need = 10, sources = { { kind = "mob", entry = YOUNG_MURK_THRESHER,
        name = m[1], chance = 77, prof = G.SKINNING, minLevel = m[2], maxLevel = m[3] } } }
    local w, h = G.ZoneSize(BARRENS)
    T.eq(#R.GrindSpots(R.Points(BARRENS, { row }, nil, "mob", 40), w, h, nil, 3, nil, BARRENS), 0)
end)

T.test("finds, peers' spots and GatherMate2 nodes across the border stay out", function()
    scene()
    local savedFinds, savedAddon, savedPeers = CP.db.finds, CP.GatherMate.Addon, CP.Peers.Mobs
    local inX, inY = RATCHET.x, RATCHET.y + 0.02
    local p = CP.Finds.Pack
    CP.db.finds = { [BARRENS] = {
        m = { [YOUNG_MURK_THRESHER] = { p(DEEP_DUSTWALLOW.x, DEEP_DUSTWALLOW.y), p(inX, inY) } },
        n = { ["Copper Vein"] = { p(DEEP_DUSTWALLOW.x, DEEP_DUSTWALLOW.y), p(inX, inY) } },
    } }
    CP.Peers.Mobs = function(zone)
        if zone ~= BARRENS then return {} end
        return { [YOUNG_MURK_THRESHER] = { { DEEP_DUSTWALLOW.x, DEEP_DUSTWALLOW.y, 1 }, { inX, inY, 1 } } }
    end
    local coord = function(x, y) return math.floor(x * 1e4 + 0.5) * 1e6 + math.floor(y * 1e4 + 0.5) * 100 end
    local packs = { [BARRENS] = { [coord(DEEP_DUSTWALLOW.x, DEEP_DUSTWALLOW.y)] = 201, [coord(0.5, 0.5)] = 201 } }
    CP.GatherMate.Addon = function()
        return {
            GetNodesForZone = function(_, zone, nodeType)
                return pairs(nodeType == "Mining" and packs[zone] or {})
            end,
            GetNameForNode = function(_, nodeType, id) return nodeType == "Mining" and id == 201 and "Copper Vein" end,
        }
    end
    CP.GatherMate.Reset()
    local ok, err = pcall(function()
        local veins = CP.GatherMate.Nodes(BARRENS)["Copper Vein"]
        T.eq(#veins, 2, "GatherMate2's Barrens vein and the player's, not the Dustwallow ones")
        for _, c in ipairs(veins) do T.eq(zoneOf(c[1], c[2]), BARRENS) end
        local mobs = G.Clusters(BARRENS, "mobs", YOUNG_MURK_THRESHER)
        T.eq(#mobs, 2, "the player's and the peers' Barrens spot only")
        for _, c in ipairs(mobs) do T.eq(zoneOf(c[1], c[2]), BARRENS) end
    end)
    CP.db.finds, CP.GatherMate.Addon, CP.Peers.Mobs = savedFinds, savedAddon, savedPeers
    CP.GatherMate.Reset()
    T.ok(ok, err)
end)

T.test("a grind spot whose middle crosses the border moves to its best stop", function()
    scene()
    local w, h = G.ZoneSize(BARRENS)
    -- Two stops either side of a point the map puts in Dustwallow; the richer one leads.
    local a = { x = DEEP_DUSTWALLOW.x - 0.004, y = DEEP_DUSTWALLOW.y, value = 3, parts = {}, items = {} }
    local b = { x = DEEP_DUSTWALLOW.x + 0.004, y = DEEP_DUSTWALLOW.y, value = 1, parts = {}, items = {} }
    local saved = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone, x)
        return (x == a.x or x == b.x) and zone or saved(zone, x, DEEP_DUSTWALLOW.y)
    end
    local ok, err = pcall(function()
        local spot = R.GrindSpots({ a, b }, w, h, nil, 1, nil, BARRENS)[1]
        T.eq({ spot.x, spot.y }, { a.x, a.y })
        local loose = R.GrindSpots({ a, b }, w, h, nil, 1)[1]
        T.ok(loose.x ~= a.x, "without a zone the spot keeps its middle")
    end)
    CP.Waypoint.MapPosZone = saved
    G.ResetClusters()
    T.ok(ok, err)
end)

T.test("a cluster rebuild asks the map once per point, and a second rebuild not at all", function()
    scene()
    local live, calls = CP.Waypoint.MapPosZone, 0
    CP.Waypoint.MapPosZone = function(...)
        calls = calls + 1
        return live(...)
    end
    local ok, err = pcall(function()
        local points = 0
        local z = CP.GatherData.zones[BARRENS]
        for _, kind in ipairs({ "mobs", "nodes" }) do
            for _, packed in pairs(z[kind]) do points = points + #G.Decode(packed) end
        end
        local skills = { [G.SKINNING] = 233, [G.HERBALISM] = 233, [G.MINING] = 233, [G.FISHING] = 150 }
        -- Each spawn once, and each merged stop once.
        G.ResetClusters()
        local stops = #R.Points(BARRENS, rowsFor(skills))
        T.ok(calls > 0 and calls <= points + stops,
            ("first rebuild: %d calls for %d spawns and %d stops"):format(calls, points, stops))
        calls = 0
        G.ResetClusters()
        R.Points(BARRENS, rowsFor(skills))
        T.eq(calls, 0, "second rebuild")
    end)
    CP.Waypoint.MapPosZone = live
    G.ResetClusters()
    T.ok(ok, err)
end)

T.test("each kind of Barrens spawn the map puts across the border drops out, and only those", function()
    scene()
    local z = CP.GatherData.zones[BARRENS]
    local dropped, kept = {}, {}
    local function kindOf(kind, entry)
        if kind == "mobs" then return "creature" end
        return CP.GatherData.nodes[entry][4] == G.FISHING and "pool" or "herb or ore"
    end
    for _, kind in ipairs({ "mobs", "nodes" }) do
        for entry, packed in pairs(z[kind]) do
            local k = kindOf(kind, entry)
            local inside = G.Clusters(BARRENS, kind, entry)
            for _, c in ipairs(inside) do T.eq(zoneOf(c[1], c[2]), BARRENS, k .. " " .. entry) end
            kept[k] = (kept[k] or 0) + #inside
            dropped[k] = (dropped[k] or 0) + #G.Decode(packed) - #inside
        end
    end
    for _, k in ipairs({ "creature", "herb or ore" }) do
        T.ok((kept[k] or 0) > 0, k .. " spawns stay")
        T.ok((dropped[k] or 0) > 0, k .. " spawns across the border drop out")
    end
    T.ok((kept.pool or 0) > 0, "the Barrens keeps its pools")
    -- Mulgore's rectangle holds the Barrens' oasis pools.
    local MULGORE, DEVIATE_SCHOOL = 1412, 180658
    T.ok(#G.Decode(CP.GatherData.zones[MULGORE].nodes[DEVIATE_SCHOOL]) > 0, "the data lists them under Mulgore")
    T.eq(#G.Clusters(MULGORE, "nodes", DEVIATE_SCHOOL), 0, "no Deviate Fish pool counts for Mulgore")
    T.ok(#G.Clusters(BARRENS, "nodes", DEVIATE_SCHOOL) > 0, "they count for the Barrens")
end)

T.test("/proflost border reports both lookups", function()
    scene()
    local lines = G.BorderReport(BARRENS, RATCHET.x, RATCHET.y)
    T.eq(#lines, 3)
    T.ok(lines[1]:find("continent map says The Barrens", 1, true), lines[1])
    T.ok(lines[2]:find("Dustwallow Marsh", 1, true), lines[2])
end)
