-- What a skinning cast gave is saved per creature (Engine/Finds.lua), and the creature's tooltip
-- shows it where the shipped data has no block (UI/UnitTooltip.lua).

local CP = ProfLost
local Finds, UT = CP.Finds, CP.UnitTooltip
local RIVERGLADES = 2548
local TALLSTRIDER = 99002          -- not in the shipped data
local BOAR = 113                   -- in the shipped data, skinnable
local LEATHER, SCRAPS = 2318, 7073

-- Plays out the finds timer on the harness clock, not the scene's frozen GetTime.
local realTime = GetTime
local function settleFinds()
    local frozen = GetTime
    GetTime = realTime
    T.advance(CP.GatherMate.SETTLE + 1)
    GetTime = frozen
end

local function scene(creature, name)
    World.set(CP.db, "finds", {})
    World.set(CP.db, "gatherLoot", nil)
    World.set(CP.db, "seenMobs", nil)
    World.set(CP.db, "unitTooltip", true)
    World.onEnd(function()
        settleFinds()
        CP.GatherMate.Reset()
    end)
    World.set(C_Spell, "GetSpellName", function(id) return id == 8613 and "Skinning" or nil end)
    World.set(CP.Waypoint, "PlayerZone", function() return RIVERGLADES end)
    World.set(C_Map, "GetPlayerMapPosition", function() return { GetXY = function() return 0.5, 0.5 end } end)
    World.set(_G, "UnitGUID", function() return "Creature-0-1-2-3-" .. creature .. "-0000" end)
    World.set(_G, "UnitName", function() return name end)
    World.set(_G, "GetTime", function() return 100 end)
end

-- Plays one skin cast, then a loot window holding `items` ({ item id, ... }).
local function skin(items, cast)
    World.set(_G, "GetNumLootItems", function() return #items end)
    World.set(_G, "GetLootSlotType", function() return 1 end)
    World.set(_G, "GetLootSlotLink", function(slot) return "|cff1eff00|Hitem:" .. items[slot] .. "::::::::|h[x]|h|r" end)
    Finds.Sent("player", "Roving Tallstrider", cast, 8613)
    Finds.Succeeded("player", cast)
    T.fire("LOOT_READY")
    T.fire("LOOT_OPENED")
end

T.test("a skin cast saves the items looted per creature, once per loot window", function()
    scene(TALLSTRIDER, "Roving Tallstrider")
    skin({ LEATHER, SCRAPS }, "c1")
    skin({ LEATHER }, "c2")
    local rec = Finds.Loot(TALLSTRIDER, "skin")
    T.eq(rec.n, 2, "two casts")
    T.eq(rec.items[LEATHER], 2)
    T.eq(rec.items[SCRAPS], 1)
    T.eq(Finds.Loot(TALLSTRIDER, "herb"), nil)
    T.fire("LOOT_READY")
    T.eq(Finds.Loot(TALLSTRIDER, "skin").n, 2, "a loot window with no cast behind it adds nothing")
end)

T.test("recorded loot is capped", function()
    scene(TALLSTRIDER, "Roving Tallstrider")
    World.set(Finds, "LOOT_ITEMS", 2)
    skin({ 1, 2, 3 }, "c1")
    local n = 0
    for _ in pairs(Finds.Loot(TALLSTRIDER, "skin").items) do n = n + 1 end
    T.eq(n, 2, "items beyond the cap are dropped")
    World.set(Finds, "LOOT_CREATURES", 1)
    scene(TALLSTRIDER + 1, "Other")
    skin({ 1 }, "c2")
    T.eq(Finds.Loot(TALLSTRIDER + 1, "skin"), nil, "no new creature past the cap")
end)

T.test("the tooltip shows a block built from the recordings where the data has none", function()
    scene(TALLSTRIDER, "Roving Tallstrider")
    World.set(CP.Gather, "RECORDED_MIN_SKINS", 2)
    T.eq(CP.GatherData.mobs[TALLSTRIDER], nil)
    skin({ LEATHER, SCRAPS }, "c1")
    skin({ LEATHER }, "c2")
    local blocks = UT.Blocks(TALLSTRIDER, { [393] = 50 }, 10)
    T.eq(#blocks, 1)
    T.eq(blocks[1].name, "Skinning")
    T.eq(blocks[1].note, "from 2 of your skins")
    T.eq(blocks[1].items[1].item, LEATHER)
    T.eq(blocks[1].items[1].chance, 100)
    T.eq(blocks[1].items[2].item, SCRAPS)
    T.eq(blocks[1].items[2].chance, 50)
    T.eq(#UT.Blocks(TALLSTRIDER, {}, 10), 0, "no Skinning, nothing shown")

    local lines = {}
    local tip = { AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "|" .. r end,
        AddLine = function(_, l) lines[#lines + 1] = l end, Show = function() end }
    World.patch("UnitLevel", function() return 10 end)
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id) if id == 393 then return { rank = 50 } end end)
    World.patch("C_Item.GetItemNameByID", function() return "Item" end)
    T.ok(UT.Add(tip, "mouseover"))
    T.eq(lines[1], "Skinning")
    T.ok(lines[2]:find("from 2 of your skins", 1, true), lines[2])
    T.ok(lines[3]:find("100%%"), lines[3])
end)

T.test("a creature with shipped data is unchanged by recordings", function()
    scene(BOAR, "Stonetusk Boar")
    local before = UT.Blocks(BOAR, { [393] = 40 }, 6)
    skin({ LEATHER }, "c1")
    local after = UT.Blocks(BOAR, { [393] = 40 }, 6)
    T.eq(#after, 1)
    T.eq(after[1].note, nil)
    T.eq(#after[1].items, #before[1].items)
    T.eq(after[1].items[1].chance, before[1].items[1].chance)
end)

T.test("herbs and ore from a creature are not recorded", function()
    scene(TALLSTRIDER, "Roving Tallstrider")
    World.set(C_Spell, "GetSpellName", function(id) return id == 2366 and "Herb Gathering" or nil end)
    World.set(_G, "GetNumLootItems", function() return 1 end)
    World.set(_G, "GetLootSlotType", function() return 1 end)
    World.set(_G, "GetLootSlotLink", function() return "|cff1eff00|Hitem:2447::::::::|h[x]|h|r" end)
    Finds.Sent("player", "Roving Tallstrider", "h1", 2366)
    Finds.Succeeded("player", "h1")
    T.fire("LOOT_READY")
    T.fire("LOOT_OPENED")
    T.eq(Finds.Loot(TALLSTRIDER, "herb"), nil, "no herb record")
end)
