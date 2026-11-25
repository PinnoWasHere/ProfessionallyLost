-- Skinning: a corpse the player has no loot rights on proves nothing, and a beast whose
-- levels need different skill says so (review items 8 and 18).

local CP = ProfLost
local G = CP.Gather
local UT = CP.UnitTooltip
local BOAR = 113          -- Stonetusk Boar, skinnable
local STORMHIDE = 3238    -- level 22-23: skill 110 at 22, 115 at 23
local BARRENS = 1413

T.test("a corpse someone else tapped is no proof the beast can't be skinned", function()
    local saved = CP.db.skinSeen
    CP.db.skinSeen = nil
    local lines = { "Stonetusk Boar", "Level 6" }
    local tip = { GetName = function() return "CPSkinLvlTip" end, NumLines = function() return #lines end }
    for i = 1, 2 do _G["CPSkinLvlTipTextLeft" .. i] = { GetText = function() return lines[i] end } end
    local dead, loot, tapped = UnitIsDead, CanLootUnit, UnitIsTapDenied
    UnitIsDead = function() return true end
    CanLootUnit = function() return false end
    UnitIsTapDenied = function() return true end
    local ok, err = pcall(function()
        UT.Learn(tip, "mouseover", "skinlvl-a", BOAR)
        UT.Learn(tip, "mouseover", "skinlvl-b", BOAR)
        UT.Learn(tip, "mouseover", "skinlvl-c", BOAR)
        T.ok(G.Skinnable(BOAR), "three corpses with no loot rights leave the beast skinnable")
        T.eq(CP.db.skinSeen and CP.db.skinSeen[BOAR], nil, "nothing recorded")

        UnitIsTapDenied = function() return false end
        UT.Learn(tip, "mouseover", "skinlvl-d", BOAR)
        UT.Learn(tip, "mouseover", "skinlvl-e", BOAR)
        T.ok(not G.Skinnable(BOAR), "the player's own looted corpses still count")
    end)
    UnitIsDead, CanLootUnit, UnitIsTapDenied = dead, loot, tapped
    for i = 1, 2 do _G["CPSkinLvlTipTextLeft" .. i] = nil end
    CP.db.skinSeen = saved
    G.SkinChanged()
    T.ok(ok, err)
end)

T.test("a level-ranged beast's source says which skill its levels need", function()
    local m = CP.GatherData.mobs[STORMHIDE]
    T.eq(G.CorpseSkill(m[2]), 110, "lowest level needs 110")
    T.eq(G.CorpseSkill(m[3]), 115, "highest level needs 115")
    local found
    for _, row in ipairs(G.ForZone(BARRENS, { [G.SKINNING] = 110 })) do
        for _, src in ipairs(row.sources or {}) do
            if src.kind == "mob" and src.entry == STORMHIDE and src.prof == G.SKINNING then found = src end
        end
    end
    T.ok(found, "still listed at Skinning 110")
    T.eq(found.skill, 110, "listing unchanged, label starts at the lowest level")
    T.eq(found.skillMax, 115, "and carries the skill its top level needs")
    local _, tip = CP.GatherList.SourceText(found)
    T.eq(tip[1], "Needs skill 110 to 115 to loot, by the corpse's level", "the label names the range")
    local _, flat = CP.GatherList.SourceText({ kind = "mob", name = "x", minLevel = 12, maxLevel = 12,
        skill = 20, skillMax = 20, chance = 50 })
    T.eq(flat[1], "Needs skill 20 to loot", "a single level keeps the plain label")
end)
