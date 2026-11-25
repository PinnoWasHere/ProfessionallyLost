-- OpenTradeSkill needs the click's hardware event; outside one the game blocks it
-- (ADDON_ACTION_BLOCKED). Every Open is pressed here as a real click (CraftWorld.Press),
-- and each call must come inside the press, before any Panel refresh, while the pressed
-- button still shows. Timers, events and the follow never call it.

local CP = ProfLost
local W, P = CP.Window, CP.Panel
local LW, TAILOR = 165, 197
local DUROTAR = 1411

-- Leatherworking and Tailoring, both windows opened once so their recipes are saved,
-- then shut. One mode on Tailoring.
local function shutTailoring()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.SetMode("one")
        W.Update()
    end)
    CraftWorld.Open(LW)
    CraftWorld.Close()
    CraftWorld.Open(TAILOR)
    CraftWorld.Close()
    T.advance(1)
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(TAILOR)
    P.tabs.guide.button:GetScript("OnClick")()
    return CP.GuideTab.ui
end

-- Every OpenTradeSkill so far came inside a press, first thing, its button showing.
local function allInClicks(want)
    local opens = CraftWorld.Opens()
    T.eq(#opens, want, "OpenTradeSkill calls")
    for i, o in ipairs(opens) do
        T.ok(o.hw, ("call %d (%s) inside a click"):format(i, tostring(o.line)))
        T.ok(o.shown, ("call %d before the clicked button hid"):format(i))
        T.eq(o.refreshes, 0, ("call %d before any refresh"):format(i))
    end
end

-- The All mode card for `key`, as the card list draws it.
local function cardButton(ui, key)
    for _, card in ipairs(ui.cardList) do
        if card.key == key then
            local btn = CreateFrame("Button", nil, ui.cards)
            btn:SetSize(P.WIDTH, 62)
            CP.GuideTab.InitCard(btn, card)
            return btn, card
        end
    end
end

T.test("step card Open calls OpenTradeSkill inside the click, and the landing calls nothing more", function()
    local ui = shutTailoring()
    local d = ui.details
    T.eq(d.craftAll.label:GetText(), "Open")
    local recipe = d.craftAll.recipeID
    CraftWorld.Press(d.craftAll)
    allInClicks(1)
    T.advance(0.5)
    CraftWorld.Open(TAILOR)
    T.advance(W.PICK_SECONDS)
    T.eq(CraftWorld.Selected(), recipe, "the step's recipe is selected")
    allInClicks(1)
end)

T.test("a pick cancelled before its landing frame queues no retry", function()
    local ui = shutTailoring()
    CraftWorld.Press(ui.details.craftAll)
    T.ok(W.PendingPick(), "the Open click waits to land its pick")
    local retries = 0
    World.patch("C_Timer.After", function(delay)
        if delay == 0.2 then retries = retries + 1 end
        return World.PASS
    end)
    W.CancelPick()
    T.advance(0.5)
    T.eq(retries, 0, "no 0.2 s retry with nothing left to land")
end)

T.test("All mode card Open calls OpenTradeSkill before the switch to One Prof hides the card", function()
    local ui = shutTailoring()
    W.SetMode("all")
    local btn, card = cardButton(ui, TAILOR)
    T.ok(btn ~= nil and btn.craft:IsVisible(), "Tailoring's card shows")
    T.eq(btn.craft.label:GetText(), "Open")
    CraftWorld.Press(btn.craft)
    allInClicks(1)
    T.eq(W.Mode(), "one", "the guide switched to One Prof")
    T.eq(CP.charDB.guideProf, TAILOR, "on the card's profession")
    T.ok(not btn.craft:IsVisible(), "the card hid after the call")
    CraftWorld.Open(TAILOR)
    T.advance(W.PICK_SECONDS)
    T.eq(CraftWorld.Selected(), card.spell, "the card's step is selected")
    allInClicks(1)
end)

T.test("All mode card Open over another profession's window: one call, inside the click", function()
    local ui = shutTailoring()
    CraftWorld.Open(LW)
    W.SetMode("all")
    local btn = cardButton(ui, TAILOR)
    T.eq(btn.craft.label:GetText(), "Open")
    CraftWorld.Press(btn.craft)
    allInClicks(1)
    CraftWorld.Open(TAILOR)
    T.advance(W.PICK_SECONDS)
    T.eq(W.ChosenID(), TAILOR)
    allInClicks(1)
end)

T.test("a row click with the window on another profession calls OpenTradeSkill inside the click", function()
    local ui = shutTailoring()
    CraftWorld.Open(LW)
    W.Pick(TAILOR)
    T.ok(ui.live.offline, "Tailoring picked over the open Leatherworking")
    local row
    for _, r in ipairs(ui.rows) do
        if r.spell and r.learned and not (r.rank or r.train or r.side) then row = r break end
    end
    T.ok(row ~= nil, "a learned recipe row")
    local btn = CreateFrame("Button", nil, ui.scroll)
    btn:SetSize(P.WIDTH, 20)
    CP.GuideTab.InitRow(btn, row)
    CraftWorld.Press(btn)
    allInClicks(1)
    T.eq(CraftWorld.Asked()[1], TAILOR)
    CraftWorld.Open(TAILOR)
    T.advance(W.PICK_SECONDS)
    T.eq(CraftWorld.Selected(), row.spell, "the row's recipe is selected")
    allInClicks(1)
end)

T.test("the player opening another profession window calls nothing outside a click", function()
    shutTailoring()
    W.Pick(LW)
    T.advance(1)
    CraftWorld.Open(TAILOR)
    T.advance(W.PICK_SECONDS)
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(LW)
    T.advance(W.PICK_SECONDS)
    allInClicks(0)
end)

T.test("the open trace prints OpenTradeSkill's callers and names a blocked call with its stack", function()
    local ui = shutTailoring()
    World.set(CP.trace, "open", true)
    local from = #T.prints()
    CraftWorld.Press(ui.details.craftAll)
    local lines = table.concat(T.prints(), "\n", from + 1)
    local at = lines:find("OpenTradeSkill -> true true", 1, true)
    T.ok(at ~= nil, lines)
    local after = lines:sub(at)
    local n = 0
    for _ in after:gmatch("\n    from ") do n = n + 1 end
    T.eq(n, W.TRACE_STACK, "one line per caller")
    T.ok(after:find("\n    from UI/GuideTab.lua", 1, true) ~= nil, "the first names the step card's click")

    from = #T.prints()
    T.fire("ADDON_ACTION_BLOCKED", CP.name, "UNKNOWN()")
    lines = table.concat(T.prints(), "\n", from + 1)
    T.ok(lines:find("ADDON_ACTION_BLOCKED: UNKNOWN()", 1, true) ~= nil, lines)
    T.ok(select(2, lines:gsub("\n    ", "")) >= 1, "with the calls that led there")

    from = #T.prints()
    T.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "UNKNOWN()")
    T.eq(#T.prints(), from, "another addon's block says nothing")
    World.set(CP.trace, "open", nil)
    T.fire("ADDON_ACTION_BLOCKED", CP.name, "UNKNOWN()")
    T.eq(#T.prints(), from, "nothing with the trace off")
end)
