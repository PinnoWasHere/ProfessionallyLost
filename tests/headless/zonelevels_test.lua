-- A zone's level range comes from the creatures a gatherer fights there: no critters, event
-- triggers, city NPCs, elites or rares, and each spawn in the one zone rectangle it sits
-- deepest in (the gathering data's zone_levels). Duskwood read 8-28 with its rabbits,
-- and a level 10 herbalist was sent there (simulator finding, 2026-11-16).

local CP = ProfLost

-- uiMapID -> { lowest the low end may be, highest the low end may be }, from the classic
-- database's own creature levels (the gathering truth, 20th percentile).
local LOW = {
    [1431] = { 20, 23, "Duskwood" },
    [1428] = { 45, 49, "Burning Steppes" },
    [1443] = { 29, 33, "Desolace" },
    [1444] = { 39, 43, "Feralas" },
    [1452] = { 52, 56, "Winterspring" },
    [1413] = { 8, 11, "The Barrens" },
}

T.test("zone level ranges leave critters and triggers out", function()
    for zone, want in pairs(LOW) do
        local lvl = CP.GatherData.zones[zone].lvl
        T.ok(lvl[1] >= want[1] and lvl[1] <= want[2],
            ("%s low end %d, want %d-%d"):format(want[3], lvl[1], want[1], want[2]))
    end
end)

T.test("a zone's high end counts its own creatures, not an overlapping zone's", function()
    -- The Barrens' rectangle holds most of Dustwallow Marsh (36-41).
    local lvl = CP.GatherData.zones[1413].lvl
    T.ok(lvl[2] <= 25, ("The Barrens high end %d"):format(lvl[2]))
end)
