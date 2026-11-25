-- Forever's new zones carry GatherLite's node positions.

local CP = ProfLost
local G, GG = CP.Gather, CP.GatherGuide
local HERB, MINE = 182, 186
local HYJAL, ZEPHRAS, RIVERGLADES, SHENDRALAS = 2482, 2521, 2548, 2652

-- Node names in a zone's data, with their spawn totals.
local function spawnsByName(zone)
    local out = {}
    for entry, packed in pairs(CP.GatherData.zones[zone].nodes or {}) do
        local name = CP.GatherData.nodes[entry][1]
        for _, c in ipairs(G.Decode(packed)) do out[name] = (out[name] or 0) + c[3] end
    end
    return out
end

local EXPECTED = {
    [RIVERGLADES] = { "Wild Steelbloom", "Kingsblood", "Liferoot", "Khadgar's Whisker", "Stranglekelp",
                      "Goldthorn", "Tin Vein", "Silver Vein", "Iron Deposit", "Gold Vein",
                      "Mithril Deposit", "Truesilver Deposit" },
    [SHENDRALAS] = { "Bruiseweed", "Grave Moss", "Iron Deposit", "Mithril Deposit" },
    [ZEPHRAS] = { "Silverleaf", "Peacebloom", "Earthroot", "Mageroyal", "Copper Vein" },
    -- Hyjal's own nodes (Heavy Thorium Vein, Demonsage, Hyjal Silphium) have no entry in the data.
    [HYJAL] = { "Rich Thorium Vein", "Dreamfoil", "Mountain Silversage" },
}

-- Vanilla nodes that spilled into the new zones from their old neighbours' rectangles.
-- No zone may hold one of its own forbidden names; upstream may add other standard nodes.
local SPILL = {
    [RIVERGLADES] = { "Black Lotus", "Firebloom", "Dreamfoil", "Plaguebloom", "Sungrass", "Purple Lotus",
                      "Ghost Mushroom", "Golden Sansam", "Arthas' Tears", "Blindweed", "Gromsblood",
                      "Mountain Silversage", "Rich Thorium Vein", "Small Thorium Vein", "Dark Iron Deposit",
                      "Peacebloom", "Silverleaf", "Copper Vein" },
    [SHENDRALAS] = { "Black Lotus", "Firebloom", "Dreamfoil", "Plaguebloom", "Sungrass", "Peacebloom",
                     "Silverleaf", "Copper Vein", "Rich Thorium Vein", "Small Thorium Vein" },
    [ZEPHRAS] = { "Black Lotus", "Firebloom", "Dreamfoil", "Plaguebloom", "Sungrass", "Iron Deposit",
                  "Mithril Deposit", "Rich Thorium Vein", "Small Thorium Vein" },
    [HYJAL] = { "Peacebloom", "Silverleaf", "Earthroot", "Copper Vein", "Tin Vein" },
}

-- Names of `have` (name -> spawns) that `list` forbids.
local function spilled(have, list)
    local out = {}
    for _, name in ipairs(list) do
        if have[name] then out[#out + 1] = name end
    end
    return out
end

T.test("the new zones have GatherLite's herbs and ore, and none of the spill-over", function()
    for zone, names in pairs(EXPECTED) do
        local have = spawnsByName(zone)
        for _, name in ipairs(names) do T.ok((have[name] or 0) > 0, zone .. " has " .. name) end
        T.eq(spilled(have, SPILL[zone]), {}, "zone " .. zone .. " holds no vanilla spill-over")
    end
    local river = spawnsByName(RIVERGLADES)
    T.eq(river["Black Lotus"], nil, "vanilla spill-over is gone")
    T.eq(river.Firebloom, nil)
    T.ok(river["Iron Deposit"] >= 50, "Iron Deposit spawns: " .. tostring(river["Iron Deposit"]))
    T.ok(CP.GatherData.zones[HYJAL].mobs ~= nil, "creatures stay as they were")
end)

T.test("new zone clusters decode onto the zone map", function()
    for zone in pairs(EXPECTED) do
        for _, packed in pairs(CP.GatherData.zones[zone].nodes) do
            for _, c in ipairs(G.Decode(packed)) do
                T.ok(c[1] >= 0 and c[1] <= 1 and c[2] >= 0 and c[2] <= 1 and c[3] >= 1, "cluster in range")
            end
        end
    end
    local z = CP.GatherData.zones[ZEPHRAS]
    T.eq(z.map, 2991)
    T.ok(z.w > 5000 and z.h > 3000, "Zephras Isle's size comes from its map")
end)

T.test("the guide no longer skips zones with real data", function()
    T.eq(GG.SKIP[RIVERGLADES], nil)
    T.eq(GG.SKIP[SHENDRALAS], nil)
    T.eq(GG.SKIP[ZEPHRAS], nil)
    T.eq(GG.SKIP[HYJAL], nil)
    local orig = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end
    G.ResetClusters()
    local found
    for _, z in ipairs(GG.Zones(HERB, 150, nil, nil, "Alliance")) do
        if z.zone == RIVERGLADES then found = z end
    end
    CP.Waypoint.MapPosZone = orig
    G.ResetClusters()
    T.ok(found ~= nil, "Riverglades is a candidate for Herbalism 150")
end)

T.test("a Riverglades checklist and route at 150 list its real nodes", function()
    MapWorld.begin({ zone = RIVERGLADES, x = 0.5, y = 0.5, level = 38, side = "Alliance" })
    local skills = { [HERB] = 150, [MINE] = 150 }
    local rows = G.ForZone(RIVERGLADES, skills, { here = G.InZone })
    local names = {}
    for _, r in ipairs(rows) do
        for _, s in ipairs(r.sources) do names[s.name] = true end
    end
    T.ok(names.Kingsblood and names.Liferoot and names["Iron Deposit"], "checklist lists Riverglades' nodes")
    T.eq(names["Black Lotus"], nil)
    local route = G.SkillRows(RIVERGLADES, skills)
    local routeNames = {}
    for _, r in ipairs(route) do routeNames[r.sources[1].name] = true end
    T.ok(routeNames.Liferoot and routeNames.Kingsblood, "route rows: orange and yellow herbs")
    local stops = CP.Route.Points(RIVERGLADES, route)
    T.ok(#stops >= 20, "route stops: " .. #stops)
    for _, s in ipairs(stops) do
        T.eq(CP.Waypoint.MapPosZone(RIVERGLADES, s.x, s.y), RIVERGLADES, "every stop is inside Riverglades")
    end
end)

T.test("Hyjal is a gathering zone for level 60 and not for a low level", function()
    local orig = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end
    G.ResetClusters()
    local function has(line, skill, level)
        for _, z in ipairs(GG.Zones(line, skill, level, nil, "Horde")) do
            if z.zone == HYJAL then return true end
        end
        return false
    end
    T.ok(not has(MINE, 260, 60), "Hyjal ore needs skill 275, so Mining 260 has no target there")
    T.ok(has(MINE, 280, 60), "Mining 280 at 60 considers Hyjal")
    T.ok(has(HERB, 280, 60), "Herbalism 280 at 60 considers Hyjal")
    T.ok(not has(MINE, 280, 30), "a level 30 is not sent to Hyjal")
    T.ok(not has(HERB, 280, 40), "a level 40 is not sent to Hyjal")
    CP.Waypoint.MapPosZone = orig
    G.ResetClusters()
end)

-- The rule behind "Dreamfoil alone is too sparse": a zone needs GG.MIN_SPAWNS skill-giving
-- spawns. Hyjal's spawn counts are replaced, so newer data can't move the line: Dreamfoil
-- (the only herb Hyjal gives at Herbalism 270) has `n` spawns on one node entry.
T.test("a zone needs GG.MIN_SPAWNS skill-giving spawns to be a candidate", function()
    local orig, clusters = CP.Waypoint.MapPosZone, G.Clusters
    CP.Waypoint.MapPosZone = function(zone) return zone end
    local dreamfoil
    for entry in pairs(CP.GatherData.zones[HYJAL].nodes) do
        if CP.GatherData.nodes[entry][1] == "Dreamfoil" and (not dreamfoil or entry < dreamfoil) then dreamfoil = entry end
    end
    local function candidate(n)
        G.Clusters = function(zone, kind, entry, tick)
            if zone ~= HYJAL then return clusters(zone, kind, entry, tick) end
            return entry == dreamfoil and kind == "nodes" and { { 0.5, 0.5, n } } or {}
        end
        GG.Forget()
        G.ResetClusters()
        for _, z in ipairs(GG.Zones(HERB, 270, 60, nil, "Horde")) do
            if z.zone == HYJAL then return true end
        end
        return false
    end
    local ok, err = pcall(function()
        T.ok(dreamfoil ~= nil, "Hyjal has a Dreamfoil node entry")
        T.ok(not candidate(GG.MIN_SPAWNS - 1), "one spawn under the minimum: not a candidate")
        T.ok(candidate(GG.MIN_SPAWNS), "at the minimum: a candidate")
        T.ok(candidate(GG.MIN_SPAWNS * 3), "well above it: a candidate")
    end)
    G.Clusters, CP.Waypoint.MapPosZone = clusters, orig
    GG.Forget()
    G.ResetClusters()
    T.ok(ok, err)
end)

T.test("Hyjal is an or row under the stretches its nodes cover", function()
    local function rows(line, skill)
        return GG.Rows({ line = line, skill = skill, max = 300, level = 60, side = "Horde", zone = 1411,
                         needs = {}, have = function() return 0 end })
    end
    for _, c in ipairs({ { MINE, 280, "Rich Thorium Vein" }, { HERB, 280, "Dreamfoil" } }) do
        local list = rows(c[1], c[2])
        local main, alt = list[1], list[2]
        T.ok(main.gather and not main.side, "the main pick comes first")
        T.ok(main.gather.zone ~= HYJAL, "Hyjal is not the main pick here")
        T.ok(alt and alt.side and alt.gather.zone == HYJAL, "an or row for Hyjal follows")
        T.ok(alt.gathers and alt.gathers > 0 and alt.to == main.to, "it has gathers and the band's end")
        local names = {}
        for _, t in ipairs(alt.gather.targets) do names[t.name] = true end
        T.ok(names[c[3]], "it lists " .. c[3])
    end
    for _, r in ipairs(rows(MINE, 200)) do
        T.ok(not (r.side and r.gather.zone == HYJAL and r.from < 275), "no Hyjal row below its ore")
    end
end)

T.test("in Hyjal at 280 the checklist and route use Hyjal's nodes", function()
    MapWorld.begin({ zone = HYJAL, x = 0.5, y = 0.5, level = 60, side = "Horde" })
    local skills = { [HERB] = 280, [MINE] = 280 }
    local rows = G.ForZone(HYJAL, skills, { here = G.InZone })
    local names = {}
    for _, r in ipairs(rows) do
        for _, s in ipairs(r.sources) do names[s.name] = true end
    end
    T.ok(names["Rich Thorium Vein"] and names["Dreamfoil"] and names["Mountain Silversage"],
        "checklist lists Hyjal's nodes")
    local route = G.SkillRows(HYJAL, skills)
    T.ok(#route > 0, "route rows exist")
    local stops = CP.Route.Points(HYJAL, route)
    T.ok(#stops >= 10, "route stops: " .. #stops)
    for _, s in ipairs(stops) do
        T.ok(s.x >= 0 and s.x <= 1 and s.y >= 0 and s.y <= 1, "stop on the zone map")
    end
end)
