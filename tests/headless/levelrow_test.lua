-- A gathering stretch capped by the character's level reads "<zone>: reach level N". Its step
-- card, Next up, the launcher and the All card all say the level, not "Go to <zone>".

local CP = ProfLost
local GG = CP.GatherGuide
local SKIN, BADLANDS = 393, 1418

-- Skinning 295/300 at level 35 in the Badlands, Alliance: the first stretch asks a level.
local function levelRows()
    MapWorld.begin({ zone = BADLANDS, level = 35, side = "Alliance", shareSolves = true })
    GG.Reset()
    local list = GG.Rows({ line = SKIN, skill = 295, max = 300, level = 35, side = "Alliance", zone = BADLANDS })
    World.set(CP.Gather, "Skills", function() return { [SKIN] = 295 } end)
    World.set(CP.Gather, "MaxRank", function() return 300 end)
    World.set(GG, "Ready", function() return true end)
    World.set(GG, "PlayerRows", function() return list end)
    for _, r in ipairs(list) do
        if r.gather and r.levelGate then return list, r end
    end
    return list, nil
end

local function zoneName(zone) return C_Map.GetMapInfo(zone).name end

T.test("the step card of a level row says the level", function()
    local _, row = levelRows()
    T.ok(row ~= nil, "a level row")
    if not row then return end
    local status = CP.GuideTab.GatherStatus(row)
    T.ok(status:find(("level %d"):format(row.levelGate.need), 1, true) ~= nil, "status: " .. status)
    T.ok(status:find("you're 35", 1, true) ~= nil, "status: " .. status)
end)

T.test("the launcher and Next up say the level, not Go to <zone>", function()
    local _, row = levelRows()
    if not row then return T.ok(false, "a level row") end
    local want = ("Level %d for %s"):format(row.levelGate.need, zoneName(row.gather.zone))
    local line
    for _, g in ipairs(CP.Launcher.GatherLines()) do
        if g.skill == 295 then line = g end
    end
    T.ok(line ~= nil, "a Skinning line")
    T.eq(line and line.right, want)
    T.eq(line and line.warn, true, "in the warning colour")
    World.set(CP.GatherList, "nextOpen", true)
    local texts = {}
    for _, l in ipairs(CP.GatherList.NextLines()) do texts[#texts + 1] = tostring(l.text) end
    local all = table.concat(texts, " | ")
    T.ok(all:find(want, 1, true) ~= nil, "Next up: " .. all)
    T.ok(not all:find("Go to", 1, true), "no Go to: " .. all)
end)

T.test("the All card says the level", function()
    local _, row = levelRows()
    if not row then return T.ok(false, "a level row") end
    local card = CP.GuideTab.Card({ prof = { id = SKIN, ids = { SKIN }, skill = 295, max = 300, name = "Skinning" } })
    T.ok(tostring(card.need):find(("level %d"):format(row.levelGate.need), 1, true) ~= nil,
        "card: " .. tostring(card.step) .. " / " .. tostring(card.need))
end)

-- Mining 275 at level 35: the row names the nearest level that opens a zone that pays, not
-- the best zone at any level (Winterspring, level 50). A Horde miner in Desolace gets
-- Tanaris (level 38). An Alliance miner in Arathi stays on the Eastern Kingdoms, where the
-- nearest zone opens at 39 and the window (GG.LEVEL_WINDOW) lets Searing Gorge (41) win on score.
local MINE, DESOLACE, ARATHI, TANARIS, SEARING = 186, 1443, 1417, 1446, 1427

local function mineLevelRow(side, here)
    MapWorld.begin({ zone = here, level = 35, side = side, shareSolves = true })
    GG.Reset()
    local list = GG.Rows({ line = MINE, skill = 275, max = 300, level = 35, side = side, zone = here })
    for _, r in ipairs(list) do
        if r.gather and not r.side and r.levelGate then return r end
    end
end

T.test("a Horde level row names the nearest paying zone", function()
    local row = mineLevelRow("Horde", DESOLACE)
    T.ok(row ~= nil, "a level row")
    if not row then return end
    local where = ("%d-%d %s level %d"):format(row.from, row.to, zoneName(row.gather.zone), row.levelGate.need)
    T.eq(row.gather.zone, TANARIS, where)
    T.ok(row.levelGate.need <= 40, where)
end)

T.test("an Alliance level row stays on its continent and within the window", function()
    local row = mineLevelRow("Alliance", ARATHI)
    T.ok(row ~= nil, "a level row")
    if not row then return end
    local where = ("%d-%d %s level %d"):format(row.from, row.to, zoneName(row.gather.zone), row.levelGate.need)
    T.eq(row.gather.zone, SEARING, where)
    T.ok(row.levelGate.need <= 41, where)
end)

T.test("GG.LevelNeed is the creature level less GG.SURVIVE, above the player", function()
    local z = { zone = TANARIS, targets = {} }
    T.eq(GG.LevelNeed(MINE, 35, z), 42 - GG.SURVIVE)
    T.eq(GG.LevelNeed(MINE, 50, z), 51, "never at or below the player's level")
end)
