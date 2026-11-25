-- Fishing keeps to ground the character may stand on: the other faction's territory
-- (Gather.Territory, the Barrens for an Alliance angler) is left out while own or contested
-- water lands every bite as well (simulator finding, 2026-11-16: an Alliance angler sent to
-- the Barrens at skill 125).

local CP = ProfLost
local F, G, GG = CP.Fishing, CP.Gather, CP.GatherGuide
local BARRENS = 1413

local function fishZones(side, skill, max, level)
    local here = side == "Horde" and 1411 or 1429
    MapWorld.begin({ zone = here, level = level, side = side })
    local out = {}
    for _, r in ipairs(GG.Rows({ line = 356, skill = skill, max = max, level = level, side = side, zone = here })) do
        if r.fish then out[#out + 1] = r end
    end
    return out
end

T.test("an Alliance angler's guide never fishes the other faction's ground", function()
    for _, c in ipairs({ { 1, 75, 5 }, { 75, 150, 20 }, { 150, 225, 30 }, { 225, 300, 40 } }) do
        for _, r in ipairs(fishZones("Alliance", c[1], c[2], c[3])) do
            T.ok(G.Territory(r.fish.zone, "Alliance") ~= "enemy",
                ("Alliance from %d: %d-%d in zone %d"):format(c[1], r.from, r.to, r.fish.zone))
        end
    end
end)

T.test("the Barrens stays the Horde's water from 75, and drops out of the Alliance's", function()
    local function has(list, zone)
        for _, w in ipairs(list) do
            if w.zone == zone then return true end
        end
        return false
    end
    T.ok(has(F.Candidates(125, 99, "Horde"), BARRENS), "Horde at 125")
    T.ok(not has(F.Candidates(125, 99, "Alliance"), BARRENS), "Alliance at 125")
    T.ok(#F.Candidates(125, 99, "Alliance") > 0, "the Alliance still has water at 125")
end)

T.test("a fish's water for the Cooking guide is on ground the character may stand on", function()
    -- Every fish the Barrens' water holds, asked for by an Alliance angler at 125.
    local z = CP.GatherData.zones[BARRENS]
    for _, l in ipairs(CP.GatherData.loot[z.fish.loot] or {}) do
        local w = F.WaterFor(l[1], 125, 60, "Alliance", nil, 1429)
        if w and w.zone == BARRENS then
            -- Only when no other water has that fish.
            local other
            for zone, oz in pairs(CP.GatherData.zones) do
                if zone ~= BARRENS and oz.fish and not oz.inst and G.Territory(zone, "Alliance") ~= "enemy" then
                    for _, ol in ipairs(CP.GatherData.loot[oz.fish.loot] or {}) do
                        if ol[1] == l[1] and G.LandChance(125, oz.fish.base) > 0 then other = zone end
                    end
                end
            end
            T.eq(other, nil, ("item %d: the Barrens while zone %s has it"):format(l[1], tostring(other)))
        end
    end
end)
