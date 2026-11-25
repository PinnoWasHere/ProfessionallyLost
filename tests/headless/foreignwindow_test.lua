-- Another addon's profession window (playtester, 1.2.0: Cooking open in a window ProfLost
-- doesn't know by name, the guide card read Open and the craft button never came). The
-- game's trade skill is open, so the card crafts. Linked, guild and NPC windows still read
-- Open, and data the game keeps after the window shut counts as shut.

local CP = ProfLost
local W, P = CP.Window, CP.Panel
local TAILOR = 197
local DUROTAR = 1411

-- Tailoring, read once in the game's window and shut, picked in One mode.
local function tailoring()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
    end)
    CraftWorld.Open(TAILOR)
    CraftWorld.Close()
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(TAILOR)
    P.tabs.guide.button:GetScript("OnClick")()
    return CP.GuideTab.ui
end

-- Opens Tailoring in another addon's window, with every material for the step in the bags.
local function openForeign(ui)
    CraftWorld.Open(TAILOR, nil, "foreign")
    local recipe = ui.details.craftOne.recipeID or ui.details.craftAll.recipeID
    for _, pair in ipairs(CP.Guides[TAILOR].recipes[recipe].reagents or {}) do CraftWorld.SetBag(pair[1], 200) end
    T.advance(0.1)
    return recipe
end

T.test("another addon's window on your own profession: the card crafts", function()
    local ui = tailoring()
    local recipe = openForeign(ui)
    local d = ui.details
    T.eq(CP.Host.Holder(), "game", "the open trade skill, whoever draws it")
    T.ok(not ui.live.offline, "the guide reads the open profession")
    T.eq(W.OpenID(), TAILOR)
    T.eq(d.craftOne.label:GetText(), "Craft 1", "the craft button, not Open")
    T.ok(d.craftOne:IsShown() and CP.Style.IsOn(d.craftOne), "Craft 1 is live")
    d.craftOne:GetScript("OnClick")(d.craftOne)
    T.eq(#CraftWorld.Asked(), 0, "no OpenTradeSkill")
    T.eq(#CraftWorld.state.casts, 1, "it crafts")
    T.eq(CraftWorld.state.casts[1].id, recipe)
end)

T.test("another addon's window shut: the card reads Open again", function()
    local ui = tailoring()
    openForeign(ui)
    CraftWorld.Close()
    T.eq(W.OpenID(), nil)
    T.eq(ui.details.craftAll.label:GetText(), "Open")
end)

T.test("data the game keeps after the window shut is no open window", function()
    local ui = tailoring()
    World.patch("C_TradeSkillUI.GetBaseProfessionInfo", function()
        return { professionID = TAILOR, professionName = "Tailoring", skillLevel = 60, maxSkillLevel = 75,
                 parentProfessionID = 0 }
    end)
    T.ok(CP.Professions.IsOwn(), "the data still names Tailoring")
    T.eq(W.OpenID(), nil, "but no window is open")
    T.eq(ui.details.craftAll.label:GetText(), "Open")
end)

for _, case in ipairs({
    { "IsTradeSkillLinked", "another player's linked recipes" },
    { "IsTradeSkillGuild", "the guild's list" },
    { "IsNPCCrafting", "an NPC's crafting" },
}) do
    T.test(("%s in another addon's window: the card reads Open"):format(case[2]), function()
        local ui = tailoring()
        World.patch("C_TradeSkillUI." .. case[1], function() return true end)
        openForeign(ui)
        T.ok(not CP.Professions.IsOwn())
        T.eq(W.OpenID(), nil)
        T.eq(ui.details.craftAll.label:GetText(), "Open")
        T.eq(#CraftWorld.state.casts, 0)
    end)
end

-- Daylight UI's window counts through its craft API (GetCraftProfession).
T.test("Daylight UI's own window: the card crafts", function()
    local ui = tailoring()
    DaylightWorld.begin({ plugin = true })
    CraftWorld.Open(TAILOR)
    local recipe = ui.details.craftOne.recipeID
    for _, pair in ipairs(CP.Guides[TAILOR].recipes[recipe].reagents or {}) do CraftWorld.SetBag(pair[1], 200) end
    T.advance(0.1)
    T.eq(CP.Host.Holder(), "daylight")
    T.eq(W.OpenID(), TAILOR)
    T.eq(ui.details.craftOne.label:GetText(), "Craft 1")
end)
