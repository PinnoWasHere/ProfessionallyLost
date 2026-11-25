-- Spawn points that hold one of several node kinds (Data/Gather.lua `mix`): the guide counts
-- each kind by its share, a route stop names the mix, and a red pin standing on the loop's
-- own spots folds into that stop.

local CP = ProfLost
local G = CP.Gather
local TIN, SILVER = 1732, 1733

-- No zone map in the harness: every cluster stays in the zone the data puts it in.
local function flatMap()
    World.set(CP.Waypoint, "MapPosZone", function(zone) return zone end)
    G.ResetClusters()
    World.onEnd(G.ResetClusters)
end

-- A zone and one of its mixes holding both Tin and Silver.
local function tinSilver()
    for zone, z in pairs(CP.GatherData.zones) do
        for _, m in ipairs(z.mix or {}) do
            if m[2][TIN] and m[2][SILVER] and z.nodes[TIN] and z.nodes[SILVER] then return zone, m end
        end
    end
end

T.test("the data ships shared spots, each kind's clusters at the mix's own positions", function()
    local zone, m = tinSilver()
    T.ok(zone ~= nil, "some zone has a Tin and Silver spot")
    local total = 0
    for _, p in pairs(m[2]) do total = total + p end
    T.ok(total > 0 and total <= 100.5, "a mix's shares sum to at most 100: " .. total)
    T.ok(m[3] == "db" or m[3] == "like" or m[3] == "even", "how: " .. tostring(m[3]))
    local tin = {}
    for _, c in ipairs(G.Decode(CP.GatherData.zones[zone].nodes[TIN])) do tin[c[1] .. ":" .. c[2]] = true end
    for _, c in ipairs(G.Decode(m[1])) do T.ok(tin[c[1] .. ":" .. c[2]], "Tin's clusters hold the mix's spot") end
end)

T.test("a shared spot counts toward each kind by its share", function()
    flatMap()
    local zone, m = tinSilver()
    local spots = G.Mixes(zone)
    for _, entry in ipairs({ TIN, SILVER }) do
        local raw, weighted = 0, 0
        for _, c in ipairs(G.Decode(CP.GatherData.zones[zone].nodes[entry])) do
            local spot = spots[entry] and spots[entry][math.floor(c[1] * 8463 + 0.5) * 100000 + math.floor(c[2] * 8463 + 0.5)]
            raw = raw + c[3]
            weighted = weighted + (spot and c[3] * spot.odds[entry] / 100 or c[3])
        end
        T.ok(math.abs(G.Spawns(zone, "nodes", entry) - weighted) < 1e-6,
            ("entry %d: %.2f weighted of %d spawns"):format(entry, G.Spawns(zone, "nodes", entry), raw))
        T.ok(weighted < raw, "the shared spots count for less than whole spawns")
    end
    local shared
    for _, c in ipairs(G.Clusters(zone, "nodes", SILVER)) do shared = shared or c.mix end
    T.ok(shared ~= nil and shared.odds[SILVER] ~= nil, "a shared cluster carries its mix")
    T.ok(m[2][SILVER] > 0)
end)

T.test("the mix reads as the kinds and their odds, likeliest first", function()
    T.eq(G.MixText({ odds = { [TIN] = 80, [SILVER] = 20 }, how = "db" }), "Tin Vein 80% · Silver Vein 20%")
    T.eq(G.MixText({ odds = { [TIN] = 50, [SILVER] = 50 }, how = "even" }),
        "Silver Vein 50% · Tin Vein 50% (odds unknown, split evenly)")
end)

T.test("a route stop on a shared spot names the mix", function()
    flatMap()
    local zone = tinSilver()
    local function row(entry)
        local n = CP.GatherData.nodes[entry]
        return { itemID = -entry, need = 1,
                 sources = { { kind = "node", entry = entry, name = n[1], skill = n[2], chance = 100, prof = n[4] } } }
    end
    local loop = CP.Route.Points(zone, { row(TIN) }, nil, "node")
    local mixed
    for _, stop in ipairs(loop) do
        if stop.mixes then mixed = stop break end
    end
    T.ok(mixed ~= nil, "a Tin stop stands on a shared spot")
    local lines = CP.RouteMap.MixLines(mixed)
    T.ok(#lines >= 1 and lines[1]:find("Tin Vein", 1, true) ~= nil, "its tooltip line: " .. tostring(lines[1]))
end)

T.test("the gathering panel's node lines show what a spot may spawn", function()
    flatMap()
    local zone = tinSilver()
    local tip = {}
    CP.GatherList.AddMixTip(tip, zone, { kind = "node", entry = TIN })
    T.eq(tip[1], "Some spots here spawn one of:")
    T.ok(tip[2] and tip[2]:find("Silver Vein", 1, true) ~= nil, "a mix line: " .. tostring(tip[2]))
    local none = {}
    CP.GatherList.AddMixTip(none, zone, { kind = "mob", entry = 1 })
    T.eq(#none, 0, "creatures share no spots")
end)
