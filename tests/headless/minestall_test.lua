-- A first stretch never sends a herbalist or miner where most finds give nothing: below
-- GG.MIN_YIELD skill points per node found, the guide asks for a level instead (simulator
-- finding, 2026-11-21: a level 35 miner at 275 sent from Desolace to Riverglades for 275-280,
-- where Truesilver is 7% of the ore; 40 finds gave no point).

local CP = ProfLost
local G, GG = CP.Gather, CP.GatherGuide
local HERB, MINE = 182, 186
local DUROTAR, BARRENS, DESOLACE, ELWYNN, WESTFALL, ARATHI = 1411, 1413, 1443, 1429, 1436, 1417
local RIVERGLADES = 2548

local function rows(line, skill, level, side, here)
    MapWorld.begin({ zone = here, level = level, side = side, shareSolves = true })
    return GG.Rows({ line = line, skill = skill, max = 300, level = level, side = side, zone = here })
end

-- Skill points per node found in `zone` at `skill`, over every node of `line` the zone holds.
local function yield(line, zone, skill)
    local ups, all = 0, 0
    for _, src in ipairs(GG.Sources(line)) do
        local n = 0
        for _, c in ipairs(G.Clusters(zone, src.kind, src.entry)) do n = n + c[3] end
        all = all + n
        ups = ups + n * GG.Chance(skill, src.req)
    end
    return all > 0 and ups / all or 0
end

local function firstRow(list)
    for _, r in ipairs(list) do
        if r.gather and not r.side then return r end
    end
end

T.test("a level 35 miner at 275 is asked to level, not sent to Riverglades", function()
    for _, c in ipairs({ { "Horde", DESOLACE }, { "Alliance", ARATHI } }) do
        local r = firstRow(rows(MINE, 275, 35, c[1], c[2]))
        T.ok(r ~= nil, c[1] .. ": a gather row")
        local where = ("%s %d-%d %s"):format(c[1], r.from, r.to, MapWorld.ZoneName(r.gather.zone))
        T.ok(r.gather.zone ~= RIVERGLADES, where)
        T.ok(r.levelGate ~= nil and r.levelGate.need > 35, where .. ": a level row")
    end
    T.ok(yield(MINE, RIVERGLADES, 275) < GG.MIN_YIELD,
        ("Riverglades pays %.3f a find at 275"):format(yield(MINE, RIVERGLADES, 275)))
end)

T.test("the stretch before it still mines Desolace, and stops where the level row starts", function()
    local list = rows(MINE, 270, 35, "Horde", DESOLACE)
    local r = firstRow(list)
    T.eq(r.gather.zone, DESOLACE)
    T.ok(r.levelGate == nil, "Desolace pays at 270")
    for _, row in ipairs(list) do
        if row.gather and not row.side and not row.levelGate and row.from < 295 then
            T.ok(row.gather.zone ~= RIVERGLADES, ("%d-%d reads Riverglades"):format(row.from, row.to))
        end
    end
end)

-- True when some zone, at any level, pays at `skill`. Mining at 225-229 has none (Mithril
-- turns green before Truesilver opens), and the guide keeps the green zones in reach.
local function somewherePays(line, skill, level, side)
    return GG.LevelGate(line, skill, level, nil, side, nil, nil, nil, true) ~= nil
end

T.test("every first stretch pays at least GG.MIN_YIELD a find, or asks for a level", function()
    local cases = {
        { "Horde", 10, DUROTAR }, { "Horde", 20, BARRENS }, { "Horde", 35, DESOLACE },
        { "Alliance", 10, ELWYNN }, { "Alliance", 20, WESTFALL }, { "Alliance", 35, ARATHI },
    }
    local checked = 0
    for _, line in ipairs({ MINE, HERB }) do
        for _, c in ipairs(cases) do
            for skill = 1, 295, 5 do
                local r = firstRow(rows(line, skill, c[2], c[1], c[3]))
                if r and not r.levelGate and somewherePays(line, r.from, c[2], c[1]) then
                    checked = checked + 1
                    local y = yield(line, r.gather.zone, r.from)
                    T.ok(y >= GG.MIN_YIELD, ("%d %s level %d skill %d: %s pays %.3f a find"):format(
                        line, c[1], c[2], skill, MapWorld.ZoneName(r.gather.zone), y))
                end
            end
        end
    end
    T.ok(checked > 100, "stretches checked: " .. checked)
end)

T.test("a level 60 character keeps its zones when none pays", function()
    local r = firstRow(rows(MINE, 275, 60, "Horde", DESOLACE))
    T.ok(r ~= nil and r.levelGate == nil, "a zone, never a level row past 60")
end)
