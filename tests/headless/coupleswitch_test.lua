-- The header's coupling switch (tester, 2026-11-18: "let me click on 'with enchanting' in the
-- ProfLost window to toggle between with/without"). A click turns "Plan for Enchanting" over;
-- the header reads "without Enchanting" while it is off, so a second click brings it back.

local CP = ProfLost
local GT = CP.GuideTab
local ENCHANTING, TAILOR, COOKING, FISHING = 333, 197, 185, 356
local LINEN = 2589

local function scene(profs)
    MapWorld.begin({ zone = 1429, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = profs, bags = { [LINEN] = 42 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    World.set(CP.db, "fishCook", true)
end

local function header() return (GT.ui.skillText:GetText() or ""):gsub("\n", " ") end

T.test("Tailoring with Enchanting: the header's switch turns Plan for Enchanting off and on", function()
    scene({ [ENCHANTING] = { rank = 1, max = 75 }, [TAILOR] = { rank = 1, max = 75 } })
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    CP.Panel:Refresh()
    T.ok(header():find("with Enchanting", 1, true) ~= nil, header())
    T.ok(GT.ui.switch:IsShown(), "the header is a switch")
    local before = header()

    local lines = GT.SwitchLines(GT.ui.live)
    T.eq(lines[1].text, "Plan for Enchanting: on")
    T.eq(lines[3].text, "Click to plan Tailoring without Enchanting.")

    GT.ui.switch:GetScript("OnClick")(GT.ui.switch)
    T.advance(1)
    CP.Panel:Refresh()
    T.eq(CP.db.deEnchant, false, "off")
    T.ok(header():find("without Enchanting", 1, true) ~= nil, header())
    T.ok(GT.ui.switch:IsShown(), "still a switch, to turn it back on")
    T.eq(GT.SwitchLines(GT.ui.live)[1].text, "Plan for Enchanting: off")

    GT.ui.switch:GetScript("OnClick")(GT.ui.switch)
    T.advance(1)
    CP.Panel:Refresh()
    T.eq(CP.db.deEnchant, true, "on again")
    T.eq(header(), before, "the header as it was")
    CraftWorld.Close()
end)

T.test("no switch where the setting cannot change the guide", function()
    scene({ [ENCHANTING] = { rank = 1, max = 75 }, [COOKING] = { rank = 1, max = 75 } })
    CraftWorld.Open(COOKING)
    T.advance(1)
    CP.Panel:Refresh()
    T.eq(#CP.Settings.Switches(COOKING), 0, "Cooking makes nothing that disenchants")
    T.ok(not GT.ui.switch:IsShown(), "no switch")
    CraftWorld.Close()
end)

T.test("Cooking with Fishing: Fish for Cooking is the switch", function()
    scene({ [FISHING] = { rank = 1, max = 75 }, [COOKING] = { rank = 1, max = 75 } })
    local list = CP.Settings.Switches(COOKING)
    T.eq(#list, 1)
    T.eq(list[1] and list[1].setting.key, "fishCook")
    T.eq(#CP.Settings.Switches(TAILOR), 0, "Fish for Cooking is Cooking's alone")
end)

T.test("Tailoring without Enchanting: the header names no Enchanting and offers no switch", function()
    scene({ [TAILOR] = { rank = 1, max = 75 } })
    CraftWorld.Open(TAILOR)
    T.advance(1)
    CP.Panel:Refresh()
    T.eq(#CP.Settings.Switches(TAILOR), 0, "no coupling switch without the profession")
    T.ok(not GT.ui.switch:IsShown(), "no switch")
    T.ok(header():find("Enchanting", 1, true) == nil, header())
    CraftWorld.Close()
end)
