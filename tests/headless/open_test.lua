-- The guide window, stage 2 (its spec, "Craft and Open"): Craft buttons
-- and recipe rows of a shut profession read Open. Open asks for the profession's window,
-- then selects the step's recipe once the window shows. It never crafts.

local CP = ProfLost
local W, P = CP.Window, CP.Panel
local LW, TAILOR = 165, 197
local DUROTAR = 1411

-- Leatherworking and Tailoring, Tailoring's window opened once so its known recipes
-- are saved, then shut. The window stands free and shows Tailoring in One mode.
local function shutTailoring()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
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

local function click(b) b:GetScript("OnClick")(b) end

-- The step's Open button --------------------------------------------------------------

T.test("a shut profession's step card reads Open; Open asks for the window and crafts nothing", function()
    local ui = shutTailoring()
    local d = ui.details
    T.ok(ui.live.offline, "Tailoring is shut")
    T.ok(d.craftAll:IsShown() and CP.Style.IsOn(d.craftAll), "one live button")
    T.eq(d.craftAll.label:GetText(), "Open")
    T.eq(d.craftAll.tip, nil, "an enabled Open has no tooltip")
    T.ok(not d.craftOne:IsShown() and not d.craftAvail:IsShown(), "Craft 1 and Available give way to it")
    local recipe = d.craftAll.recipeID
    T.ok(recipe ~= nil, "it carries the step's recipe")

    click(d.craftAll)
    T.eq(#CraftWorld.Asked(), 1)
    T.eq(CraftWorld.Asked()[1], TAILOR, "OpenTradeSkill for Tailoring")
    T.ok(W.PendingPick() ~= nil, "the pick waits for the window")
    T.eq(CraftWorld.Selected(), nil, "nothing selected yet")
    T.eq(#CraftWorld.state.casts, 0, "Open never crafts")

    CraftWorld.Open(TAILOR)
    T.eq(CraftWorld.Selected(), recipe, "the step's recipe is selected once the window shows")
    T.eq(W.PendingPick(), nil, "the pick is spent")
    T.eq(#CraftWorld.state.casts, 0, "still nothing crafted")
    T.ok(not ui.live.offline, "the Guide reads the open window now")
    T.eq(d.craftOne.label:GetText(), "Craft 1", "and the buttons read Craft again")
end)

T.test("the pick lands after the data-source event, not before", function()
    local ui = shutTailoring()
    local recipe = ui.details.craftAll.recipeID
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR, true)
    T.eq(CraftWorld.Selected(), nil, "the window shows without its data: no pick yet")
    T.ok(W.PendingPick() ~= nil, "still waiting")
    CraftWorld.DataArrives()
    T.eq(CraftWorld.Selected(), nil, "a frame after the event, not inside it")
    T.advance(0.05)
    T.eq(CraftWorld.Selected(), recipe, "selected once the data arrived")
end)

T.test("a pick expires after PICK_SECONDS", function()
    local ui = shutTailoring()
    click(ui.details.craftAll)
    T.advance(W.PICK_SECONDS - 1)
    T.ok(W.PendingPick() ~= nil, "still waiting just before")
    T.advance(2)
    T.eq(W.PendingPick(), nil, "lapsed")
    CraftWorld.Open(TAILOR)
    T.eq(CraftWorld.Selected(), nil, "a later opening selects nothing")
end)

T.test("with the window open on this profession, Craft works as before", function()
    local ui = shutTailoring()
    CraftWorld.Open(TAILOR)
    local d = ui.details
    T.ok(not ui.live.offline)
    local recipe = d.craftOne.recipeID
    for _, pair in ipairs(CP.Guides[TAILOR].recipes[recipe].reagents or {}) do CraftWorld.SetBag(pair[1], 200) end
    T.advance(0.1)
    P:Refresh()
    T.eq(d.craftOne.label:GetText(), "Craft 1")
    T.ok(d.craftOne:IsShown() and d.craftAvail:IsShown() and d.craftAll:IsShown(), "all three craft buttons")
    T.ok((d.craftAll.label:GetText() or ""):find("^Craft all") ~= nil, "the whole-step button is Craft all")
    T.eq(d.craftAll.openTo, nil, "no Open target")
    T.ok(CP.Style.IsOn(d.craftOne), "Craft 1 is live")
    click(d.craftOne)
    T.eq(#CraftWorld.Asked(), 0, "no OpenTradeSkill")
    T.eq(#CraftWorld.state.casts, 1)
    T.eq(CraftWorld.state.casts[1].id, recipe, "the step's recipe")
    T.eq(CraftWorld.state.casts[1].count, 1)
end)

T.test("a window on another profession: the step reads Open, and Open switches the window", function()
    local ui = shutTailoring()
    CraftWorld.Open(LW)
    W.Pick(TAILOR)
    T.ok(ui.live.offline, "Tailoring picked over the open Leatherworking")
    T.eq(ui.details.craftAll.label:GetText(), "Open")
    local recipe = ui.details.craftAll.recipeID
    click(ui.details.craftAll)
    T.eq(CraftWorld.Asked()[1], TAILOR)
    CraftWorld.Open(TAILOR)
    T.eq(CraftWorld.Selected(), recipe)
    T.eq(W.ChosenID(), TAILOR)
end)

-- Recipe rows -------------------------------------------------------------------------

T.test("a recipe row of a shut profession is picked in the guide; its window stays shut", function()
    local ui = shutTailoring()
    local row
    for _, r in ipairs(ui.rows) do
        if r.spell and not (r.rank or r.train) and r ~= ui.rows[1] then row = r break end
    end
    T.ok(row ~= nil, "a recipe row past the first")
    CP.GuideTab.Pick(row)
    T.eq(#CraftWorld.Asked(), 0, "no OpenTradeSkill")
    T.eq(ui.details.craftAll.recipeID, row.spell, "the row is picked")
    click(ui.details.craftAll)
    T.eq(CraftWorld.Asked()[1], TAILOR, "its Open button opens the window")
    CraftWorld.Open(TAILOR)
    T.eq(CraftWorld.Selected(), row.spell, "on its recipe")
    T.eq(#CraftWorld.state.casts, 0)
end)

T.test("an unlearned row is picked without opening the window; its waypoint stays", function()
    local ui = shutTailoring()
    local row
    for _, r in ipairs(ui.rows) do
        if r.spell and not r.learned and not (r.rank or r.train) then row = r break end
    end
    T.ok(row ~= nil, "Tailoring at 60 has an unlearned step")
    local target = CP.Guide.WaypointFor(row)
    CP.GuideTab.Pick(row)
    T.eq(#CraftWorld.Asked(), 0, "no OpenTradeSkill")
    T.eq(CP.Guide.WaypointFor(row), target, "the waypoint is unchanged")
end)

T.test("a row click with the window open selects, as before", function()
    local ui = shutTailoring()
    CraftWorld.Open(TAILOR)
    local row
    for _, r in ipairs(ui.rows) do
        if r.spell and r.learned and not (r.rank or r.train) then row = r break end
    end
    CP.GuideTab.Pick(row)
    T.eq(#CraftWorld.Asked(), 0, "no OpenTradeSkill")
    T.eq(CraftWorld.Selected(), row.spell)
end)

-- All mode cards ----------------------------------------------------------------------

T.test("All mode: a shut profession's card reads Open; the open one's has the craft buttons", function()
    local ui = shutTailoring()
    CraftWorld.Open(LW)
    W.SetMode("all")
    local byKey = {}
    for _, card in ipairs(ui.cardList) do byKey[card.key] = card end
    T.ok(byKey[TAILOR] and byKey[TAILOR].spell, "Tailoring has a step")

    local btn = CreateFrame("Button", nil, UIParent)
    CP.GuideTab.InitCard(btn, byKey[TAILOR])
    T.ok(btn.craft:IsShown())
    T.eq(btn.craft.label:GetText(), "Open")
    T.eq(btn.craft.openTo, TAILOR)
    click(btn.craft)
    T.eq(CraftWorld.Asked()[1], TAILOR)
    T.eq(#CraftWorld.state.casts, 0)
    T.eq(W.Mode(), "one", "Open from a card switches the guide to View One")
    T.eq(CP.charDB.guideProf, TAILOR, "on that card's profession")

    local open = CreateFrame("Button", nil, UIParent)
    CP.GuideTab.InitCard(open, byKey[LW])
    if byKey[LW].spell and byKey[LW].learned then
        T.eq(open.one.label:GetText(), "Craft 1", "the open profession crafts")
        T.ok(open.one:IsShown() and open.avail:IsShown(), "with Craft 1 and Available")
        T.eq(open.craft.openTo, nil)
    end
    CraftWorld.Open(TAILOR)
    T.eq(CraftWorld.Selected(), byKey[TAILOR].spell, "the card's step is selected")
end)

-- Simulator finding, 2026-11-16 (controls): a card drawn while its window was open kept its
-- craft buttons after another profession's window opened, and the game refused the craft.
T.test("All mode: a card's Craft pressed after another window opened, before a redraw, opens its window", function()
    local ui = shutTailoring()
    CraftWorld.Open(LW)
    W.SetMode("all")
    local card
    for _, c in ipairs(ui.cardList) do
        if c.key == LW then card = c end
    end
    T.ok(card and card.spell and card.learned, "Leatherworking's card has a learned step")
    local btn = CreateFrame("Button", nil, UIParent)
    CP.GuideTab.InitCard(btn, card)
    T.ok(btn.one:IsShown(), "drawn with the window open: Craft 1")
    CraftWorld.Open(TAILOR)
    local casts, asked = #CraftWorld.state.casts, #CraftWorld.Asked()
    for _, b in ipairs({ btn.one, btn.avail, btn.craft }) do
        click(b)
        T.eq(#CraftWorld.state.casts, casts, "no craft asked of the Tailoring window")
    end
    T.ok(#CraftWorld.Asked() > asked and CraftWorld.Asked()[#CraftWorld.Asked()] == LW,
        "the press opens Leatherworking's window, as Open does")
end)

-- One mode redraws the step card as the window opens, so its buttons never outlive the window.
T.test("One mode: the step card's Craft pressed right after another window opened asks only that window's craft", function()
    local ui = shutTailoring()
    CraftWorld.Open(TAILOR)
    T.advance(0.5)
    P:Refresh()
    local d = ui.details
    T.ok(d.craftOne:IsShown() and d.craftOne.recipeID ~= nil, "drawn with Tailoring open: Craft 1")
    local tailoring = d.craftOne.recipeID
    CraftWorld.Open(LW)
    local casts = #CraftWorld.state.casts
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do
        if b.recipeID and not b.openTo then click(b) end
    end
    for i = casts + 1, #CraftWorld.state.casts do
        local id = CraftWorld.state.casts[i].id
        T.ok(id ~= tailoring and CraftWorld.Known(LW, id), "only a Leatherworking craft is asked of its window: " .. tostring(id))
    end
end)

-- Daylight UI ---------------------------------------------------------------------------

T.test("in Daylight UI's window the pick lands through its own selection", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    local recipe = ui.details.craftAll.recipeID
    T.ok(CraftWorld.Known(TAILOR, recipe), "a learned step")
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)
    T.ok(CP.Host.DaylightWindow(), "Daylight UI's window lists Tailoring")
    T.eq(DaylightWorld.state.selected, recipe, "Daylight UI selected the step's recipe")
end)

-- Daylight UI's window keeps its own pick and refills its list a frame after the game's
-- data settles. The game's OpenRecipe never reaches it.

T.test("Daylight UI's window on another profession: Open switches it, and the pick lands once its list refills", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    CraftWorld.Open(LW)
    T.eq(DaylightWorld.state.craft, LW, "Daylight UI's window shows Leatherworking")
    W.Pick(TAILOR)
    local recipe = ui.details.craftAll.recipeID
    T.ok(CraftWorld.Known(TAILOR, recipe), "a learned step")
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)
    T.eq(DaylightWorld.state.craft, TAILOR, "its list refilled for Tailoring")
    T.eq(DaylightWorld.state.selected, recipe, "and it selected the step's recipe")
    T.eq(W.PendingPick(), nil, "the pick is spent")
end)

T.test("Daylight UI's window before its data: the pick waits for its list", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    local recipe = ui.details.craftAll.recipeID
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR, true)
    T.ok(not DaylightWorld.state.window:IsShown(), "no window until the data arrives")
    T.ok(W.PendingPick() ~= nil, "still waiting")
    CraftWorld.DataArrives()
    T.advance(0.3)
    T.eq(DaylightWorld.state.selected, recipe, "selected once its list holds Tailoring")
end)

T.test("Daylight UI's remembered pick for a profession gives way to the step's recipe", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    local recipe = ui.details.craftAll.recipeID
    CraftWorld.Open(TAILOR)
    local other
    for id in pairs(CP.Guides[TAILOR].recipes) do
        if id ~= recipe and CraftWorld.Known(TAILOR, id) then other = id break end
    end
    T.ok(other ~= nil, "another learned recipe")
    T.ok(CP.Host.SelectRecipe(other), "the player picks it in Daylight UI's window")
    CraftWorld.Close()
    W.Pick(TAILOR)
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)
    T.eq(DaylightWorld.state.selected, recipe, "the step's recipe, not the remembered one")
end)

-- Combat --------------------------------------------------------------------------------

T.test("combat: Open works in combat; with OPEN_IN_COMBAT off it greys with a reason", function()
    local ui = shutTailoring()
    local d = ui.details
    World.patch("InCombatLockdown", function() return true end)
    T.fire("PLAYER_REGEN_DISABLED")
    T.advance(0.05)
    T.ok(CP.Style.IsOn(d.craftAll), "OpenTradeSkill has no combat flag: Open stays live")
    click(d.craftAll)
    T.eq(CraftWorld.Asked()[1], TAILOR, "and asks in combat")

    World.set(W, "OPEN_IN_COMBAT", false)
    P:Refresh()
    T.ok(not CP.Style.IsOn(d.craftAll), "greyed")
    T.eq(d.craftAll.tip, W.OPEN_COMBAT_TIP, "with the reason on hover")
    T.ok(not W.OpenTo(TAILOR, d.craftAll.recipeID), "OpenTo refuses")
    local row
    for _, r in ipairs(ui.rows) do
        if r.spell and not (r.rank or r.train) then row = r break end
    end
    CP.GuideTab.Pick(row)
    T.eq(#CraftWorld.Asked(), 1, "a row click only selects the row")

    World.patch("InCombatLockdown", function() return false end)
    T.fire("PLAYER_REGEN_ENABLED")
    T.advance(0.05)
    T.ok(CP.Style.IsOn(d.craftAll), "live again after combat")
    T.eq(d.craftAll.tip, nil)
end)

-- Daylight UI's window opens as soon as the game names the profession, and reads its
-- list then (Craft.Changed never checks IsDataSourceChanging). Its later re-read on the
-- same profession tells plugins nothing.

T.test("Daylight UI's window opened before its recipe list: the pick waits until the list holds the recipe", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    local recipe = ui.details.craftAll.recipeID
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR, "list")
    T.ok(DaylightWorld.state.window:IsShown(), "its window is up on Tailoring")
    T.eq(DaylightWorld.state.craft, TAILOR)
    T.ok(W.PendingPick() ~= nil, "the pick still waits: its list is empty")
    CraftWorld.DataArrives()
    T.advance(0.3)
    T.eq(DaylightWorld.state.selected, recipe, "selected once its list holds the recipe")
    T.eq(W.PendingPick(), nil, "the pick is spent")
end)

T.test("Daylight UI's window changing its pick on its own just after landing gets the step's recipe back", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    local recipe = ui.details.craftAll.recipeID
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)
    T.eq(DaylightWorld.state.selected, recipe, "landed")
    local other
    for id in pairs(DaylightWorld.state.list) do
        if id ~= recipe then other = id break end
    end
    T.ok(other ~= nil, "another recipe in its list")
    -- A refill falling back to its first line, as Craft.fill does.
    DaylightWorld.state.selected = other
    DaylightWorld.Fire("CraftRecipeSelected", other)
    T.advance(0.05)
    T.eq(DaylightWorld.state.selected, recipe, "put back")
    T.advance(W.GUARD_SECONDS + 0.1)
    T.ok(CP.Host.SelectRecipe(other), "later, the player's own pick")
    T.advance(0.05)
    T.eq(DaylightWorld.state.selected, other, "stays")
end)

T.test("Daylight UI's window and an unlearned recipe: the pick ends at once instead of waiting", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    local row
    for _, r in ipairs(ui.rows) do
        if r.spell and not r.learned and not (r.rank or r.train) then row = r break end
    end
    CP.GuideTab.Pick(row)
    CraftWorld.Open(TAILOR)
    T.eq(W.PendingPick(), nil, "spent: there is nothing to select")
end)

T.test("/proflost trace open prints each step of an Open, and nothing while off", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    -- A learned step: an unlearned one reads Learn, not Open.
    for _, r in ipairs(ui.rows) do
        if r.spell and r.learned and not (r.rank or r.train or r.side) then CP.GuideTab.Pick(r) break end
    end
    World.onEnd(function() CP.trace.open = nil end)
    local before = #T.prints()
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)
    T.eq(#T.prints(), before, "off: silent")
    SlashCmdList.PROFLOST("trace open on")
    T.eq(CP.trace.open, true, "on")
    CraftWorld.Close()
    before = #T.prints()
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)
    local out = {}
    for i = before + 1, #T.prints() do out[#out + 1] = tostring(T.prints()[i]) end
    local text = table.concat(out, "\n")
    for _, want in ipairs({ "Open profession 197", "OpenTradeSkill", "TRADE_SKILL_SHOW", "Daylight CraftShown",
        "SelectCraftRecipe%(%d+%) %->", "Daylight selected" }) do
        T.ok(text:find(want) ~= nil, want .. " in:\n" .. text)
    end
    SlashCmdList.PROFLOST("trace open off")
    T.eq(CP.trace.open, nil)
end)
