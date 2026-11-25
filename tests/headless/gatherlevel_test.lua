-- A gathering guide never sends a character where it can't work. While the first stretch is
-- capped by the character's own level, its zones and Skinning's creatures stay within
-- GG.Workable(level); past that the stretch asks for the level the next zone needs, as
-- "reach level N" (simulator finding, 2026-11-16: a level 10 skinner sent to the Barrens'
-- level 15-20 creatures at skill 101-120, and a level 10 miner to Ashenvale at 101).

local CP = ProfLost
local GG = CP.GatherGuide
local MINE, SKIN = 186, 393
local DUROTAR, ELWYNN, BADLANDS = 1411, 1429, 1418

local function rows(line, skill, max, level, side, here)
    MapWorld.begin({ zone = here, level = level, side = side, shareSolves = true })
    GG.Reset()
    return GG.Rows({ line = line, skill = skill, max = max, level = level, side = side, zone = here })
end

local function low(zone)
    local lvl = GG.ZONE_LEVELS[zone] or CP.GatherData.zones[zone].lvl
    return lvl and lvl[1] or 1
end

-- Every first-stretch row (within 25 points of `skill`) works at `level`, or asks for a level.
local function checkReach(label, list, skill, level)
    local bound = GG.Workable(level)
    for _, r in ipairs(list) do
        if r.gather and not r.side and r.from < skill + 25 then
            local where = ("%s %d-%d %s"):format(label, r.from, r.to, MapWorld.ZoneName(r.gather.zone))
            if r.levelGate then
                T.ok(r.levelGate.need > level, where .. ": a level row asks a higher level")
                T.eq(GG.TargetNames(r.gather.targets, r.from, 2)[1], ("reach level %d"):format(r.levelGate.need), where)
            else
                T.ok(low(r.gather.zone) <= bound, ("%s: creatures from level %d, the bound is %d"):format(where, low(r.gather.zone), bound))
            end
            for _, t in ipairs(r.gather.targets) do
                T.ok(not t.level or t.level <= bound, ("%s names %s, level %d"):format(where, t.name, t.level or 0))
            end
        end
    end
end

T.test("a level 10 skinner at 121 is never sent to creatures it can't kill", function()
    local list = rows(SKIN, 121, 150, 10, "Horde", DUROTAR)
    checkReach("Horde skinning", list, 121, 10)
    list = rows(SKIN, 120, 150, 10, "Alliance", ELWYNN)
    checkReach("Alliance skinning", list, 120, 10)
end)

T.test("a level 10 miner at 101 mines within its level, on the other continent if need be", function()
    local list = rows(MINE, 101, 150, 10, "Horde", 1413)
    checkReach("Horde mining", list, 101, 10)
    local first
    for _, r in ipairs(list) do
        if r.gather then first = r break end
    end
    T.ok(first and not first.levelGate, "a zone it can work exists")
    T.ok(first and low(first.gather.zone) <= GG.Workable(10), "first zone " .. tostring(first and first.gather.zone))
end)

T.test("with nothing it can work, the stretch asks for the level the next zone needs", function()
    local list = rows(SKIN, 295, 300, 35, "Alliance", BADLANDS)
    local first
    for _, r in ipairs(list) do
        if r.gather then first = r break end
    end
    T.ok(first ~= nil, "a row")
    T.ok(first.levelGate ~= nil, "a level row")
    local need = first.levelGate.need
    T.ok(need > 35, "needs more than 35: " .. need)
    T.eq(first.levelGate.text, ("This stretch needs level %d (you're 35)"):format(need))
    T.eq(GG.TargetNames(first.gather.targets, first.from, 2)[1], ("reach level %d"):format(need))
    for _, t in ipairs(first.gather.targets) do
        T.ok(t.level <= GG.Workable(35), "no creature it can't kill: " .. t.name)
    end
    T.ok(GG.Spot(first.gather.zone, first.gather.targets) ~= nil, "the row still pins the zone")
    local nextUp = GG.Next(list, 295, 300)
    T.eq(nextUp.level, need, "GG.Next carries the level")
end)

-- Simulator finding, 2026-11-16: a level 10 skinner at 121 kept on green Sunscale Screechers in
-- the Barrens, and a level 35 one at 290 in the Badlands, with no level asked; both stalled.
T.test("a first stretch with only green targets in reach asks for a level instead", function()
    for _, case in ipairs({ { 121, 150, 10, "Horde", DUROTAR }, { 121, 150, 10, "Horde", 1413 },
                            { 290, 300, 35, "Alliance", BADLANDS } }) do
        local skill, max, level, side, here = unpack(case)
        local list = rows(SKIN, skill, max, level, side, here)
        local where = ("%s skinning %d at level %d"):format(side, skill, level)
        local first
        for _, r in ipairs(list) do
            if r.gather and not r.side then first = r break end
        end
        T.ok(first ~= nil, where .. ": a row")
        if first and not first.levelGate then
            local names = table.concat(GG.TargetNames(first.gather.targets, first.from, 2), ", ")
            T.ok(not names:find("(green)", 1, true), ("%s: the row reads %s"):format(where, names))
        end
    end
end)

T.test("a level 1 character's start keeps its neighbouring zones", function()
    -- Teldrassil has no ore: Darkshore (creatures from 11) is within GG.REACH.
    local list = rows(MINE, 1, 75, 1, "Alliance", 1438)
    local first
    for _, r in ipairs(list) do
        if r.gather then first = r break end
    end
    T.eq(first and first.gather.zone, 1439)
    T.eq(first and first.levelGate, nil)
end)
