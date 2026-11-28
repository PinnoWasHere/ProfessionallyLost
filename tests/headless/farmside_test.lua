-- Farm sources by faction (owner, 2026-11-27). "Enemy faction camps: yes": a creature hostile to one
-- faction alone is that faction's farm, as Tiragarde Keep's Kul Tiras Marines in Durotar are the
-- Horde's cloth. "Enemy territory: there's always an alternative spot": no guide, farm spot or pin
-- sends a character into the other faction's territory (AreaTable's FactionGroupMask, shipped as
-- GatherData.territory). The simulator's Alliance skinner was sent to the Barrens at Skinning 120.
-- Capital residents and town guards stay out for both factions (scripts/guidegen/farmable.py).
-- Real generated data.

local CP = ProfLost
local G, GG, Farm = CP.Gather, CP.GatherGuide, CP.Farm
local SKIN, HERB, MINE = 393, 182, 186
local DUROTAR, BARRENS, ELWYNN, HILLSBRAD, ASHENVALE = 1411, 1413, 1429, 1424, 1440
local LINEN = 2589
local SAILOR = 3128
local ROYAL_GUARD = 1756   -- Stormwind Royal Guard: a Stormwind resident (capital)

local function none() return 0 end

-- A character of `side` at `level` in `zone`; every cluster stays in the zone the data puts it in.
local function scene(zone, side, level)
    MapWorld.begin({ zone = zone, side = side, level = level })
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    G.ResetClusters()
    World.onEnd(function()
        G.ResetClusters()
        MapWorld.SettleGuides()
    end)
end

local function kulTiras(name) return name ~= nil and name:find("^Kul Tiras") ~= nil end

T.test("Durotar's cloth holds the Kul Tiras camp for the Horde alone", function()
    local bands = CP.GatherData.zones[DUROTAR].cloth[LINEN]
    local horde
    for _, b in ipairs(bands) do
        for _, a in ipairs(b[7]) do
            if kulTiras(a[1]) then
                T.eq(b[9], "H", "a band of " .. a[1] .. " is the Horde's alone")
                horde = true
            end
        end
    end
    T.ok(horde, "a Durotar Linen band names the Kul Tiras creatures")
    for _, side in ipairs({ "Horde", "Alliance" }) do
        scene(DUROTAR, side, 8)
        local c = G.Cloth(DUROTAR, LINEN, 8, side)
        local seen = false
        for _, s in ipairs(c and c.spots or {}) do seen = seen or kulTiras(s.name) end
        T.eq(seen, side == "Horde", side .. ": a Durotar Linen spot at the Kul Tiras camp")
    end
end)

T.test("a creature the data gives one faction is that faction's farm alone", function()
    T.ok(next(CP.GatherData.sides or {}) ~= nil, "the data names creatures only one faction farms")
    scene(DUROTAR, "Alliance", 8)
    World.set(CP.GatherData, "sides", { [SAILOR] = "H" })
    T.eq(G.ForSide(SAILOR), false, "an Alliance character does not farm a Horde-only creature")
    T.eq(G.Gives(SAILOR, SKIN), false)
    scene(DUROTAR, "Horde", 8)
    World.set(CP.GatherData, "sides", { [SAILOR] = "H" })
    T.eq(G.ForSide(SAILOR), true, "the Horde does")
end)

T.test("the Barrens are Horde territory by the data; Hillsbrad is contested", function()
    T.eq(CP.GatherData.territory and CP.GatherData.territory[BARRENS], "H", "AreaTable gives the Barrens to the Horde")
    T.eq(G.EnemyGround(BARRENS, "Alliance"), true)
    T.eq(G.EnemyGround(BARRENS, "Horde"), false)
    T.eq(G.EnemyGround(HILLSBRAD, "Alliance"), false)
    T.eq(G.EnemyGround(HILLSBRAD, "Horde"), false)
    T.eq(G.Territory(BARRENS, "Alliance"), "enemy")
    T.eq(G.Territory(1433, "Horde"), "theirs", "Redridge is contested ground the Alliance levels on")
end)

T.test("an Alliance gatherer's guide never sends them into the Barrens", function()
    scene(ELWYNN, "Alliance", 13)
    for _, line in ipairs({ SKIN, HERB, MINE }) do
        for _, c in ipairs({ { 1, 5 }, { 90, 13 }, { 120, 14 }, { 150, 20 }, { 175, 22 }, { 225, 35 } }) do
            local list = GG.Rows({ line = line, skill = c[1], max = 300, level = c[2], side = "Alliance",
                                   zone = ELWYNN, needs = {}, have = none })
            for _, r in ipairs(list) do
                if r.gather then
                    T.ok(r.gather.zone ~= BARRENS, ("line %d from %d at level %d: %d-%d in the Barrens"):format(
                        line, c[1], c[2], r.from or 0, r.to or 0))
                end
            end
        end
    end
end)

T.test("Farm's spots and pins never send an Alliance character into the Barrens", function()
    scene(ASHENVALE, "Alliance", 20)
    local skills = { [SKIN] = 150, [HERB] = 150, [MINE] = 150, [185] = 150 }
    local checked = 0
    for _, item in ipairs({ 2318, 2319, 4232, 785, 2450, 2771, 2772, LINEN, 2592 }) do
        local best = Farm.Best(item, { level = 20, side = "Alliance", skills = skills })
        if best then
            checked = checked + 1
            T.ok(best.zone ~= BARRENS, "Farm.Best for item " .. item .. " is the Barrens")
        end
        local place = Farm.Nearest(item, { level = 20, side = "Alliance", skills = skills })
        if place then
            checked = checked + 1
            T.ok(place.zone ~= BARRENS, "Farm.Nearest for item " .. item .. " is the Barrens")
        end
    end
    T.ok(checked > 4, "the items have places to farm")
end)

T.test("a capital resident is no farm for either faction", function()
    T.eq(CP.GatherData.mobs[ROYAL_GUARD], nil)
    T.eq((CP.GatherData.sides or {})[ROYAL_GUARD], nil)
    for zone, z in pairs(CP.GatherData.zones) do
        for item, bands in pairs(z.cloth or {}) do
            for _, b in ipairs(bands) do
                for _, a in ipairs(b[7]) do
                    T.ok(a[1] ~= "Stormwind Royal Guard", ("zone %d item %d: a band names the Royal Guard"):format(zone, item))
                end
            end
        end
    end
end)
