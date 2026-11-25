-- The addon's names and entry points: slash command, saved variables, addon compartment,
-- the gradient title and the chat prefix.

local CP = ProfLost

T.test("the addon answers to ProfLost: global, saved variables, slash command", function()
    T.eq(CP.name, "ProfessionallyLost")
    T.eq(_G.ProfLost, CP)
    T.eq(CP.db, _G.ProfLostDB)
    T.eq(CP.charDB, _G.ProfLostCharDB)
    T.eq(_G.SLASH_PROFLOST1, "/proflost")
    T.eq(type(SlashCmdList.PROFLOST), "function")
end)

T.test("the gradient runs teal to green to brass, one colour per letter, spaces plain", function()
    local g = CP.Gradient("Ab C")
    T.eq(g, "|cff1fb5a6A|r|cff6cc36fb|r |cffe0b43cC|r")
    local plain = CP.Gradient("DaylightUI Professionally Lost"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    T.eq(plain, "DaylightUI Professionally Lost")
end)

T.test("chat lines start with the public name in the accent gradient", function()
    local printed
    local was = _G.print
    _G.print = function(s) printed = s end
    CP:Print("hello")
    _G.print = was
    T.eq(printed, CP.Gradient("Professionally Lost") .. ": hello")
end)

T.test("the addon compartment takes the minimap button's clicks: guide, Shift gathering panel, right settings", function()
    local opened, said, toggled, gathered
    local wasOpen, wasPrint = C_TradeSkillUI.OpenTradeSkill, CP.Print
    local wasToggle, wasGather, wasShift = CP.Window.Toggle, CP.GatherPanel.ToggleShown, IsShiftKeyDown
    local shift = false
    C_TradeSkillUI.OpenTradeSkill = function(id) opened = id end
    CP.Print = function(_, msg) said = msg end
    CP.Window.Toggle = function() toggled = (toggled or 0) + 1 end
    CP.GatherPanel.ToggleShown = function() gathered = (gathered or 0) + 1 end
    _G.IsShiftKeyDown = function() return shift end

    ProfLost_Open("ProfLost", "LeftButton")
    T.eq(toggled, 1, "left-click shows or hides the guide window")
    T.eq(opened, nil, "it opens no profession window")

    shift = true
    ProfLost_Open("ProfLost", "LeftButton")
    T.eq(gathered, 1, "Shift-click: the gathering panel")
    shift = false

    ProfLost_Open("ProfLost", "RightButton")
    T.ok(said and said:find("pick ProfLost under Plugins", 1, true), "right-click: settings")

    -- The menu entry hands over its frame, not a mouse button: a left-click.
    ProfLost_Open("ProfLost", {})
    T.eq(toggled, 2)

    C_TradeSkillUI.OpenTradeSkill, CP.Print = wasOpen, wasPrint
    CP.Window.Toggle, CP.GatherPanel.ToggleShown, _G.IsShiftKeyDown = wasToggle, wasGather, wasShift
end)

T.test("the compartment tooltip names the addon and hides on leave", function()
    local title, shown, hidden
    local was = { text = GameTooltip.SetText, show = GameTooltip.Show, hide = _G.GameTooltip_Hide }
    GameTooltip.SetText = function(_, text) title = text end
    GameTooltip.Show = function() shown = true end
    _G.GameTooltip_Hide = function() hidden = true end
    ProfLost_OnEnter("ProfLost", UIParent)
    ProfLost_OnLeave()
    GameTooltip.SetText, GameTooltip.Show, _G.GameTooltip_Hide = was.text, was.show, was.hide
    T.eq(title, "Professionally Lost")
    T.ok(shown, "shown on enter")
    T.ok(hidden, "hidden on leave")
end)
