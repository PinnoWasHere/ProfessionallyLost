-- Creature tooltips: skinning drops and their chances.

local CP = ProfLost
local UT = CP.UnitTooltip
local BOAR = 113   -- Stonetusk Boar, skinnable
local GUID = "Creature-0-1-0-1-113-0000000001"
local LEVEL = UnitLevel("player")

T.test("the creature id comes from a creature GUID only", function()
    T.eq(UT.CreatureID(GUID), BOAR)
    T.eq(UT.CreatureID("Player-1-0ABC"), nil)
    T.eq(UT.CreatureID(nil), nil)
end)

T.test("blocks show skinning loot, likeliest first, only with Skinning", function()
    T.eq(#UT.Blocks(BOAR, {}), 0, "no Skinning, nothing to add")
    local blocks = UT.Blocks(BOAR, { [393] = 40 }, 6)
    T.eq(#blocks, 1)
    T.eq(blocks[1].name, "Skinning")
    T.eq(blocks[1].need, 1, "a level 6 corpse needs skill 1")
    T.ok(#blocks[1].items >= 1)
    for i = 2, #blocks[1].items do T.ok(blocks[1].items[i - 1].chance >= blocks[1].items[i].chance) end
    T.eq(UT.Blocks(BOAR, { [393] = 40 }, 30)[1].need, 150, "level 30 needs 150")
    T.eq(#UT.Blocks(99999999, { [393] = 300 }), 0, "unknown creature")
end)

T.test("the tooltip gets a Skinning line and one line per item", function()
    local lines = {}
    local tip = { AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "|" .. r end,
        AddLine = function(_, l) lines[#lines + 1] = l end, Show = function() end }
    World.patch("UnitGUID", function() return GUID end)
    World.patch("UnitLevel", function() return 6 end)
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id) if id == 393 then return { rank = 1 } end end)
    World.patch("C_Item.GetItemNameByID", function() return "Ruined Leather Scraps" end)
    T.ok(UT.Add(tip, "mouseover"))
    T.eq(lines[1], "Skinning", "the profession alone, no skill number")
    T.ok(lines[2]:find("%%$"), "chance on the right: " .. lines[2])

    -- An item the guides are short of is drawn in the accent, the rest in white.
    local colours = {}
    tip.AddDoubleLine = function(_, l, _, r, g, b) colours[#colours + 1] = { l, r, g, b } end
    local needs = ProfLost.Gather.Needs
    local first
    ProfLost.Gather.Needs = function()
        local out = {}
        if first then out[first] = 5 end
        return out
    end
    T.ok(UT.Add(tip, "mouseover"))
    T.eq({ colours[1][2], colours[1][3], colours[1][4] }, { 1, 1, 1 }, "nothing short: white")
    first = UT.Blocks(UT.CreatureID(GUID), { [393] = 1 }, 6)[1].items[1].item
    colours = {}
    T.ok(UT.Add(tip, "mouseover"))
    local a = ProfLost.Style.color.accent
    T.ok(colours[1][1]:find("short x5", 1, true) ~= nil, colours[1][1])
    T.eq({ colours[1][2], colours[1][3], colours[1][4] }, { a[1], a[2], a[3] }, "short: the accent")
    ProfLost.Gather.Needs = needs
    tip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "|" .. r end
    CP.db.unitTooltip = false
    lines = {}
    T.ok(not UT.Add(tip, "mouseover"), "off in settings")
    CP.db.unitTooltip = true
end)

T.test("the gathering skill's name is coloured like the game's own tooltips", function()
    local UT = ProfLost.UnitTooltip
    local function is(c, r, g, b) return math.abs(c[1] - r) < 0.01 and math.abs(c[2] - g) < 0.01 and math.abs(c[3] - b) < 0.01 end
    T.ok(is(UT.GatherColour(130, 140), 1, 0.13, 0.13), "below the need: red")
    T.ok(is(UT.GatherColour(150, 140), 1, 0.5, 0.25), "under 25 over: orange")
    T.ok(is(UT.GatherColour(170, 140), 1, 1, 0), "25-50 over: yellow")
    T.ok(is(UT.GatherColour(206, 140), 0.25, 0.75, 0.25), "50-100 over: green")
    T.ok(is(UT.GatherColour(260, 140), 0.5, 0.5, 0.5), "100+ over: grey")
end)

T.test("creatures Forever won't let be skinned drop out of the tooltip, guides and farm spots", function()
    local G = CP.Gather
    local CREEPER = 2565   -- Giant Plains Creeper: skinning loot in the data, not skinnable in game
    local saved = CP.db.skinSeen
    CP.db.skinSeen = nil
    local ok, err = pcall(function()
        T.eq(#UT.Blocks(CREEPER, { [393] = 300 }, 35), 0, "no Skinning block for the creeper")
        T.ok(not G.Gives(CREEPER, 393))
        T.ok(G.Gives(CREEPER, 185), "its Cooking drop still counts")
        CP.GatherGuide.Reset()
        for _, src in ipairs(CP.GatherGuide.Sources(393)) do T.ok(src.entry ~= CREEPER, "not a skinning target") end

        -- Learning: a looted boar corpse without the line, twice, means no; one with it means yes.
        T.ok(G.Skinnable(BOAR))
        G.LearnSkin(BOAR, false, "corpse-1")
        G.LearnSkin(BOAR, false, "corpse-1")
        T.ok(G.Skinnable(BOAR), "one corpse, counted once, isn't enough")
        G.LearnSkin(BOAR, false, "corpse-2")
        T.ok(not G.Skinnable(BOAR), "two looted corpses without the line")
        G.LearnSkin(BOAR, true)
        T.ok(G.Skinnable(BOAR), "a corpse showing the line settles it")
        G.LearnSkin(BOAR, false, "corpse-3")
        T.ok(G.Skinnable(BOAR), "and stays settled")
    end)
    CP.db.skinSeen = saved
    CP.GatherGuide.Reset()
    T.ok(ok, err)
end)

T.test("a looted corpse's tooltip teaches skinnable or not", function()
    local G = CP.Gather
    local saved = CP.db.skinSeen
    CP.db.skinSeen = nil
    local lines = { "Stonetusk Boar", "Level 6" }
    local tip = { GetName = function() return "CPTestTip" end, NumLines = function() return #lines end }
    for i = 1, 3 do _G["CPTestTipTextLeft" .. i] = { GetText = function() return lines[i] end } end
    local dead, loot = UnitIsDead, CanLootUnit
    UnitIsDead = function() return true end
    CanLootUnit = function() return false end
    local ok, err = pcall(function()
        UT.Learn(tip, "mouseover", "c-a", BOAR)
        UT.Learn(tip, "mouseover", "c-b", BOAR)
        T.ok(not G.Skinnable(BOAR), "two looted corpses with no Skinnable line")
        lines[3] = _G.UNIT_SKINNABLE_LEATHER or "Skinnable"
        T.ok(UT.ShowsSkinnable(tip))
        UT.Learn(tip, "mouseover", "c-c", BOAR)
        T.ok(G.Skinnable(BOAR), "the line seen once: skinnable")
    end)
    UnitIsDead, CanLootUnit = dead, loot
    for i = 1, 3 do _G["CPTestTipTextLeft" .. i] = nil end
    CP.db.skinSeen = saved
    T.ok(ok, err)
end)

T.test("a corpse is read once however often its tooltip redraws, and known skinners never", function()
    local G = CP.Gather
    local saved, learn = CP.db.skinSeen, G.LearnSkin
    CP.db.skinSeen = nil
    local calls = 0
    G.LearnSkin = function(...) calls = calls + 1 return learn(...) end
    local tip = { GetName = function() return "CPTestTip2" end, NumLines = function() return 1 end }
    local dead, loot = UnitIsDead, CanLootUnit
    UnitIsDead = function() return true end
    CanLootUnit = function() return false end
    local ok, err = pcall(function()
        for _ = 1, 20 do UT.Learn(tip, "mouseover", "redraw-1", BOAR) end
        T.eq(calls, 1, "twenty redraws, one read")
        CP.db.skinSeen = { [BOAR] = true }
        UT.Learn(tip, "mouseover", "redraw-2", BOAR)
        T.eq(calls, 1, "a creature known skinnable isn't read")
        CanLootUnit = function() return true end
        CP.db.skinSeen = nil
        UT.Learn(tip, "mouseover", "redraw-3", BOAR)
        UT.Learn(tip, "mouseover", "redraw-3", BOAR)
        T.eq(calls, 1, "loot still on it: nothing learned yet")
    end)
    UnitIsDead, CanLootUnit, G.LearnSkin = dead, loot, learn
    CP.db.skinSeen = saved
    T.ok(ok, err)
end)
