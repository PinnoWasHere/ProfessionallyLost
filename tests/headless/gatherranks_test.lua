-- Gathering ranks ask the level the game asks: a trainer row's reqlevel (classic-db) where it
-- gives one, else the rank spell's own level (Journeyman 10, Expert 20, Artisan 35). Artisan
-- Fishing has a trainer too, Katoom the Angler (Horde), learnable from 200 (simulator
-- cross-check, 2026-11-16).

local CP = ProfLost
local F = CP.Fishing
local HERB, MINE, SKIN = 182, 186, 393
local KATOOM, NAT_PAGLE = 14740, 12919

local function levels(line)
    local out = {}
    for _, r in ipairs(CP.GatherData.ranks[line]) do out[#out + 1] = r.level or 0 end
    return table.concat(out, ",")
end

T.test("Herbalism, Mining and Skinning ranks ask levels 10, 20 and 35", function()
    T.eq(levels(HERB), "10,20,35", "Herbalism")
    T.eq(levels(MINE), "10,20,35", "Mining")
    T.eq(levels(SKIN), "10,20,35", "Skinning")
end)

T.test("Journeyman Fishing asks level 10, the Expert book 20, Artisan 35", function()
    T.eq(F.RankFor(75, "Horde").level, 10, "Journeyman")
    T.eq(F.RankFor(150, "Horde").level, 20, "the Expert book")
    T.eq(F.RankFor(225, "Horde").level, 35, "Katoom's Artisan")
    T.eq(F.RankFor(225, "Alliance").level, 35, "the Artisan quest")
end)

T.test("Artisan Fishing: Katoom trains the Horde from 200, Nat Pagle's quest serves both at 225", function()
    local horde, alliance = F.RankFor(225, "Horde"), F.RankFor(225, "Alliance")
    T.eq(horde.kind, "trainer")
    T.eq(horde.npcs[1], KATOOM)
    T.eq(horde.at, 200)
    T.eq(F.RankName(horde), "Artisan Fishing")
    T.eq(alliance.kind, "quest")
    T.eq(alliance.npcs[1], NAT_PAGLE)
    T.eq(F.RankFor(225).kind, "quest", "without a side, the rank every side can learn")
    T.eq(F.RankStep(225, 225, "Horde").kind, "trainer")
end)

T.test("a Horde angler's guide shows the Artisan trainer at 200, an Alliance one the quest at 225", function()
    local function rankRow(side)
        MapWorld.begin({ zone = side == "Horde" and 1411 or 1429, level = 40, side = side })
        for _, r in ipairs(CP.GatherGuide.Rows({ line = 356, skill = 190, max = 225, level = 40, side = side })) do
            if r.fishRank and r.fishRank.skill == 225 then return r end
        end
    end
    local h, a = rankRow("Horde"), rankRow("Alliance")
    T.eq(h and h.fishRank.kind, "trainer")
    T.eq(h and h.from, 200)
    T.eq(h and h.name, "Artisan Fishing")
    T.eq(a and a.fishRank.kind, "quest")
    T.eq(a and a.from, 225)
end)
