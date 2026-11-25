-- GatherMate2 nodes feeding the checklist and routes, with a stand-in GatherMate2.

local CP = ProfLost
local GM, G = CP.GatherMate, CP.Gather
local ZEPHRAS, BARRENS = 2665, 1413   -- Zephras Isle's second map has no spawn data
local COPPER_VEIN, COPPER_ORE = 201, 2770

local function fake(db, names)
    return {
        GetNodesForZone = function(_, zone, nodeType) return pairs(db[nodeType] and db[nodeType][zone] or {}) end,
        GetNameForNode = function(_, nodeType, id) return names[nodeType] and names[nodeType][id] end,
    }
end

local function with(addon, pack, fn)
    local orig = GM.Addon
    GM.Addon = function() return addon end
    GatherMateData2MineDB = pack
    GM.Reset()
    local ok, err = pcall(fn)
    GM.Addon = orig
    GatherMateData2MineDB = nil
    GM.Reset()
    if not ok then error(err, 0) end
end

T.test("GatherMate2 coordinates decode to zone-map x, y", function()
    local x, y = GM.Decode(3570284000)
    T.eq(x, 0.357)
    T.eq(y, 0.284)
end)

T.test("nodes merge GatherMate2's own finds and the data pack, without duplicates", function()
    local addon = fake({ Mining = { [BARRENS] = { [5000500000] = COPPER_VEIN } } },
        { Mining = { [COPPER_VEIN] = "Copper Vein" } })
    with(addon, { [BARRENS] = { [5000500000] = COPPER_VEIN, [6000600000] = COPPER_VEIN } }, function()
        local nodes = GM.Nodes(BARRENS)
        T.eq(#nodes["Copper Vein"], 2, "the shared spot counts once")
        T.eq(nodes["Copper Vein"][1][3], 1)
    end)
end)

T.test("a zone the vanilla data lacks gets nodes from GatherMate2", function()
    T.eq(#G.ForZone(ZEPHRAS, { [G.MINING] = 300 }), 0, "nothing without GatherMate2")
    local addon = fake({ Mining = { [ZEPHRAS] = { [4000400000] = COPPER_VEIN, [4100410000] = COPPER_VEIN } } },
        { Mining = { [COPPER_VEIN] = "Copper Vein" } })
    -- Forever's new zones: the map can't place a point, so recorded finds stay.
    local mapPos = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function() return nil end
    with(addon, nil, function()
        local rows = G.ForZone(ZEPHRAS, { [G.MINING] = 1 }, { here = G.InZone })
        local copper
        for _, r in ipairs(rows) do if r.itemID == COPPER_ORE then copper = r end end
        T.ok(copper ~= nil, "Copper Ore from recorded veins")
        local entry = copper.sources[1].entry
        T.eq(#G.Clusters(ZEPHRAS, "nodes", entry), 2, "both recorded veins are route stops")
    end)
    CP.Waypoint.MapPosZone = mapPos
    G.ResetClusters()
end)

T.test("recorded finds add to the weight of matching spawn spots", function()
    local mapPos = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(z) return z end
    G.ResetClusters()
    local entry
    for e, n in pairs(CP.GatherData.nodes) do
        if n[1] == "Copper Vein" and CP.GatherData.zones[BARRENS].nodes[e] then entry = e end
    end
    local before = #G.Clusters(BARRENS, "nodes", entry)
    local first = G.Decode(CP.GatherData.zones[BARRENS].nodes[entry])[1]
    local coord = math.floor(first[1] * 10000 + 0.5) * 1000000 + math.floor(first[2] * 10000 + 0.5) * 100
    local addon = fake({ Mining = { [BARRENS] = { [coord] = COPPER_VEIN } } }, { Mining = { [COPPER_VEIN] = "Copper Vein" } })
    with(addon, nil, function()
        local after = G.Clusters(BARRENS, "nodes", entry)
        T.eq(#after, before + 1)
        local rows = { { itemID = COPPER_ORE, need = 10, sources = { { kind = "node", entry = entry, chance = 100, prof = G.MINING, name = "Copper Vein" } } } }
        local stops = CP.Route.Points(BARRENS, rows)
        local top = 0
        for _, s in ipairs(stops) do top = math.max(top, s.value) end
        T.ok(top >= first[3] + 1, "the confirmed spot carries the extra find")
    end)
    CP.Waypoint.MapPosZone = mapPos
    G.ResetClusters()
end)

T.test("recorded finds the map places in another zone are left out", function()
    local mapPos = CP.Waypoint.MapPosZone
    -- Everything east of x = 0.5 on the Barrens map lies in another zone.
    CP.Waypoint.MapPosZone = function(z, x) return x > 0.5 and 9999 or z end
    local addon = fake({ Mining = { [ZEPHRAS] = { [4000400000] = COPPER_VEIN, [8000400000] = COPPER_VEIN } } },
        { Mining = { [COPPER_VEIN] = "Copper Vein" } })
    local ok, err = pcall(with, addon, nil, function()
        local entry
        for e, n in pairs(CP.GatherData.nodes) do
            if n[1] == "Copper Vein" and (not entry or e < entry) then entry = e end
        end
        local list = G.Clusters(ZEPHRAS, "nodes", entry)
        T.eq(#list, 1, "only the vein inside the zone")
        T.ok(list[1][1] < 0.5)
    end)
    CP.Waypoint.MapPosZone = mapPos
    G.ResetClusters()
    T.ok(ok, err)
end)
