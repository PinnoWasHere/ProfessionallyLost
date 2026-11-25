-- The guide window after the owner's 0.2.10-beta test: the
-- "or" arrow left on reused rows, the window's alpha after a profession window closes,
-- row clicks landing in Daylight UI's window, and Learn for unlearned steps. Buy moved
-- to the vendor's window (round7_test.lua).

local CP = ProfLost
local W, P, Host, GP = CP.Window, CP.Panel, CP.Host, CP.GatherPanel
local LW, TAILOR = 165, 197
local DUROTAR = 1411
local MID = { rank = 150, max = 150 }

local function shutTailoring(tailorSpec)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = tailorSpec or 60 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowPoint", CP.db.windowPoint)
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
local function isOn(b) return CP.Style.IsOn(b) end

-- A recipe step: learned or not, with a waypoint target when `aimed`.
local function stepRow(ui, learned, aimed)
    for _, r in ipairs(ui.rows) do
        if r.spell and not (r.rank or r.train or r.side) and r.learned == learned
            and (not aimed or (CP.Guide.WaypointFor(r, ui.live and ui.live.prof) ~= nil
                and CP.Guide.LearnGate(r.recipe, ui.live.prof) == nil)) then
            return r
        end
    end
end

-- Records waypoints instead of placing them.
local function recordWaypoints()
    local placed = {}
    World.set(CP.Waypoint, "ToRecipe", function(guide, recipe) placed[#placed + 1] = recipe end)
    return placed
end

-- Alpha the harness doesn't keep: `f` remembers what it was given.
local function keepAlpha(f, start)
    local a = start or 1
    World.set(f, "SetAlpha", function(_, v) a = v end)
    World.set(f, "GetAlpha", function() return a end)
    World.set(f, "GetEffectiveAlpha", function() return a end)
end

-- 1. The "or" arrow on reused rows ---------------------------------------------------

T.test("a row reused from an \"or\" row drops its arrow, whatever it shows next", function()
    local ui = shutTailoring()
    local btn = CreateFrame("Button", nil, UIParent)
    local base = stepRow(ui, true)
    local side = { side = true, key = "side1", spell = base.spell, recipe = base.recipe, from = base.from, to = base.to,
                   crafts = 3, learned = true }
    CP.GuideTab.InitRow(btn, side)
    T.ok(btn.arrow:IsShown(), "an \"or\" row has its arrow")
    local kinds = {}
    for _, r in ipairs(ui.rows) do
        local kind = r.train and "trainer" or r.rank and "rank" or (r.spell and r.learned == false and "pattern")
            or (r.current and "current") or (r.spell and not r.side and "recipe")
        if kind and not kinds[kind] then kinds[kind] = r end
    end
    kinds.gather = { gather = { zone = DUROTAR, targets = {}, zones = {} }, from = 1, to = 50, current = true }
    kinds.quest = { gatherRank = nil, fishRank = { kind = "quest", npcs = {}, at = 0, level = 0 }, name = "Fishing",
                    from = 1, to = 75 }
    T.ok(kinds.trainer ~= nil or kinds.rank ~= nil, "a trainer or rank row to test with")
    for kind, row in pairs(kinds) do
        CP.GuideTab.InitRow(btn, side)
        CP.GuideTab.InitRow(btn, row)
        T.ok(not btn.arrow:IsShown(), kind .. " row: no arrow over its range text")
    end
end)

-- 2. Alpha after a profession window closes ------------------------------------------

-- Daylight UI fires CraftHidden as its window starts to fade out (Craft.shut: Win.Close
-- then TellShut); the window stays shown, fading, for Feel.CLOSE (0.25 s), then hides.
T.test("Daylight UI's window closing: the free window stays put at full alpha, its shell and gathering panel back", function()
    DaylightWorld.begin({ plugin = true })
    shutTailoring()
    keepAlpha(P.frame)
    keepAlpha(GP.clip, GP.p)
    local win = DaylightWorld.state.window
    local fade = 1
    win.GetAlpha = function() return fade end
    win.GetEffectiveAlpha = function() return fade end
    CraftWorld.Open(TAILOR)
    T.ok(Host.DaylightWindow(), "Daylight UI's window is up")
    DaylightWorld.state.craft = nil
    DaylightWorld.Fire("CraftHidden")
    for step = 1, 5 do
        fade = 1 - step * 0.2
        T.advance(0.05)
        T.eq(P.frame:GetAlpha(), 1, ("%.1f into the fade: the window keeps full alpha"):format(fade))
    end
    win:Hide()
    fade = 1
    T.advance(0.5)
    T.ok(P.frame:IsShown(), "standing free")
    T.eq(P.frame:GetParent(), UIParent)
    T.eq(P.frame:GetAlpha(), 1, "the window at full alpha")
    T.ok(GP.shell:IsShown(), "the shared shell (its background) shows")
    T.eq(GP.clip:GetAlpha(), GP.p, "the gathering panel at its slide's alpha")
    T.eq(GP.p, GP.IsOpen() and 1 or 0, "and the slide at rest")
end)

T.test("the game's window fading and closing: the guide window keeps full alpha with its shell", function()
    shutTailoring()
    keepAlpha(P.frame)
    CraftWorld.Open(TAILOR)
    local host = CraftWorld.state.frame
    World.set(host, "GetAlpha", function() return 0.5 end)
    T.advance(0.1)
    T.eq(P.frame:GetAlpha(), 1, "the profession window's alpha is its own")
    CraftWorld.Close()
    T.advance(0.5)
    T.ok(P.frame:IsShown(), "standing free")
    T.eq(P.frame:GetAlpha(), 1, "back at full alpha")
    T.ok(GP.shell:IsShown(), "the shared shell shows")
end)

-- 3. Row clicks with the window open -------------------------------------------------

T.test("a row click with Daylight UI's window open on the profession selects the recipe there", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    CraftWorld.Open(TAILOR)
    local row = stepRow(ui, true)
    T.ok(row ~= nil, "a learned step")
    CP.GuideTab.Pick(row)
    T.eq(DaylightWorld.state.selected, row.spell, "selected in Daylight UI's window")
    T.eq(CraftWorld.Selected(), nil, "not in the game's hidden window")
    T.eq(W.PendingPick(), nil, "landed at once")
end)

T.test("a row click while Daylight UI's list lags waits for it, as Open's pick does", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    CraftWorld.Open(TAILOR)
    local row = stepRow(ui, true)
    local before = DaylightWorld.state.selected
    -- Its list still holds another profession.
    DaylightWorld.state.craft = LW
    CP.GuideTab.Pick(row)
    T.ok(W.PendingPick() ~= nil, "waits")
    T.eq(DaylightWorld.state.selected, before, "nothing selected yet")
    T.eq(CraftWorld.Selected(), nil, "nothing spent on the game's hidden window")
    DaylightWorld.state.craft = TAILOR
    T.advance(W.PICK_POLL * 2)
    T.eq(DaylightWorld.state.selected, row.spell, "selected once the list caught up")
    T.eq(W.PendingPick(), nil)
    local key = row.key
    T.eq(CP.GuideTab.ui.details.title:GetText(), row.recipe.name, "the guide keeps the clicked row")
    T.ok(key ~= nil)
end)

T.test("a row click with the game's window open selects there; with it shut, opens nothing", function()
    local ui = shutTailoring()
    local row = stepRow(ui, true)
    CP.GuideTab.Pick(row)
    T.eq(#CraftWorld.Asked(), 0, "shut: no window asked for")
    T.eq(CraftWorld.Opened(), nil, "and none open")
    T.eq(CraftWorld.Selected(), nil)
    CraftWorld.Open(TAILOR)
    CP.GuideTab.Pick(row)
    T.eq(CraftWorld.Selected(), row.spell, "selected in the game's window")
end)

-- 4. Learn ---------------------------------------------------------------------------

T.test("an unlearned step reads Learn, shut or open: a waypoint to its trainer or vendor, no window", function()
    local ui = shutTailoring(MID)
    local placed = recordWaypoints()
    local row = stepRow(ui, false, true)
    T.ok(row ~= nil, "an unlearned step with a known trainer or vendor")
    local target = CP.Guide.WaypointFor(row)
    for _, open in ipairs({ false, true }) do
        if open then CraftWorld.Open(TAILOR) end
        local asked = #CraftWorld.Asked()
        CP.GuideTab.Pick(row)
        local b = ui.details.craftAll
        T.eq(b.label:GetText(), CP.GuideTab.LearnLabel(row.recipe), open and "window open" or "window shut")
        T.ok(b.label:GetText():find("^Go to ") ~= nil, "Go to trainer or vendor, not Learn")
        T.ok(b:IsShown() and isOn(b), "Learn is on")
        T.ok(not ui.details.craftOne:IsShown() and not ui.details.craftAvail:IsShown(), "one button")
        T.eq(b.tip, nil, "an enabled Learn has no tooltip")
        click(b)
        T.eq(placed[#placed], target, "the waypoint goes to the row pin's target")
        T.eq(#CraftWorld.Asked(), asked, "no profession window opened")
        T.eq(W.PendingPick(), nil, "no pick")
    end
end)

T.test("an unlearned step with no known trainer or vendor: Learn greys and says how to learn it", function()
    local ui = shutTailoring(MID)
    local row = stepRow(ui, false, true)
    World.set(CP.Guide, "WaypointFor", function() return nil end)
    CP.GuideTab.Pick(row)
    local b = ui.details.craftAll
    T.eq(b.label:GetText(), CP.GuideTab.LearnLabel(row.recipe))
    T.ok(not isOn(b), "greyed")
    T.eq(b.tip, CP.Guide.LearnText(row.recipe, CP.Guides[TAILOR]))
end)

T.test("All mode: a card whose step isn't learned reads Learn and sets the waypoint", function()
    -- Trained past 150: at 150/150 the card is the Expert rank (ranks_test.lua).
    local ui = shutTailoring({ rank = 150, max = 225 })
    local placed = recordWaypoints()
    local live = W.LiveFor(TAILOR)
    local unlearned = {}
    for k, v in pairs(live) do unlearned[k] = v end
    unlearned.learned = {}
    local card = CP.GuideTab.Card(unlearned)
    T.eq(card.learned, false, "the step isn't learned")
    T.ok(card.learn, "its trainer or vendor is known")
    local btn = CreateFrame("Button", nil, UIParent)
    CP.GuideTab.InitCard(btn, card)
    T.eq(btn.craft.label:GetText(), CP.GuideTab.LearnLabel(card.recipe))
    T.ok(btn.craft:IsShown() and isOn(btn.craft))
    local asked = #CraftWorld.Asked()
    click(btn.craft)
    T.eq(placed[#placed], card.learn)
    T.eq(#CraftWorld.Asked(), asked, "no profession window opened")
    -- The same card learned reads Open again.
    card.learned, card.learn = true, nil
    CP.GuideTab.InitCard(btn, card)
    T.eq(btn.craft.label:GetText(), "Open")
    T.eq(btn.craft.learnTo, nil)
end)

-- 5. Learn respects the player's skill -------------------------------------------------

local function gatedRow(ui, pred)
    for _, r in ipairs(ui.rows) do
        if r.recipe and not r.learned and not (r.rank or r.train or r.side) and pred(r.recipe) then return r end
    end
end

local function isVendor(r) return r.src == "vendor" or r.src == "reputation" end

T.test("LearnGate: trainer above the skill waits, a vendor pattern buys early, at the skill it clears", function()
    local G = CP.Guide
    local trainer = { src = "trainer", learn = 125, npcs = { 1 } }
    local vendor = { src = "vendor", learn = 125, npcs = { 1 } }
    local drop = { src = "drop", learn = 125, npcs = { 1 } }
    local prof = { skill = 100, max = 150, name = "Tailoring" }
    T.eq(G.LearnGate(trainer, prof).label, "At 125")
    T.eq(G.LearnGate(trainer, prof).tip, "Learnable at Tailoring 125")
    T.eq(G.LearnGate(vendor, prof).label, "Buy pattern")
    T.eq(G.LearnGate(drop, prof).label, "At 125")
    T.eq(G.WaypointFor({ recipe = trainer, learned = false }, prof), nil, "no waypoint to the trainer")
    T.ok(G.WaypointFor({ recipe = vendor, learned = false }, prof) ~= nil, "the vendor keeps its waypoint")
    T.eq(G.WaypointFor({ recipe = drop, learned = false }, prof), nil)
    prof.skill = 125
    T.eq(G.LearnGate(trainer, prof), nil)
    T.eq(G.LearnGate(vendor, prof), nil)
    T.ok(G.WaypointFor({ recipe = trainer, learned = false }, prof) ~= nil, "at the skill, the trainer")
end)

T.test("LearnGate: a recipe past the rank cap says which rank to train; a trainer's level gate", function()
    local G = CP.Guide
    local prof = { id = 197, skill = 70, max = 75, name = "Tailoring" }
    local g = G.LearnGate({ src = "trainer", learn = 125, npcs = { 1 } }, prof)
    T.eq(g.label, "Train Journeyman Tailoring")
    T.eq(G.LearnGate({ src = "trainer", learn = 160, npcs = { 1 } }, { id = 197, skill = 150, max = 150 }).label, "Train Expert Tailoring")
    T.eq(G.LearnGate({ src = "trainer", learn = 100, npcs = { 1 } }, prof).label, "Train Journeyman Tailoring")
    T.eq(G.LearnGate({ src = "trainer", learn = 60, level = 90, npcs = { 1 } }, prof).label, "Level 90")
    T.eq(G.LearnGate({ src = "trainer", learn = 60, level = 5, npcs = { 1 } }, prof), nil)
end)

T.test("a trainer recipe above the skill: the One card's Learn greys to At N, no waypoint, no row pin", function()
    local ui = shutTailoring({ rank = 60, max = 150 })
    local placed = recordWaypoints()
    local row = gatedRow(ui, function(r) return not isVendor(r) and r.src == "trainer" and r.learn > 60 and r.learn <= 150 end)
    T.ok(row ~= nil, "a trainer recipe above skill 60")
    CP.GuideTab.Pick(row)
    local b = ui.details.craftAll
    T.eq(b.label:GetText(), "At " .. row.recipe.learn)
    T.ok(not isOn(b), "greyed")
    T.ok(b.tip:find("Learnable at", 1, true) ~= nil, tostring(b.tip))
    click(b)
    T.eq(#placed, 0, "no waypoint call")
    T.eq(CP.Guide.WaypointFor(row, ui.live.prof), nil, "the row pin has no target")
    local btn = CreateFrame("Button", nil, UIParent)
    CP.GuideTab.InitRow(btn, row)
    T.ok(not btn.pin:IsShown(), "the row pin is hidden")
end)

T.test("a vendor pattern above the skill: Buy pattern sets the waypoint and the row pin stays", function()
    local ui = shutTailoring()
    local placed = recordWaypoints()
    local row = gatedRow(ui, function(r)
        return isVendor(r) and r.learn > 60 and r.npcs and #r.npcs > 0 end)
    T.ok(row ~= nil, "a vendor pattern above skill 60")
    CP.GuideTab.Pick(row)
    local b = ui.details.craftAll
    T.eq(b.label:GetText(), "Buy pattern")
    T.ok(isOn(b), "on")
    click(b)
    T.eq(placed[#placed], row.recipe, "the waypoint goes to the vendor")
    local btn = CreateFrame("Button", nil, UIParent)
    CP.GuideTab.InitRow(btn, row)
    T.ok(not btn.pin:IsShown(), "picked: the step card's pin stands for the row's")
    T.ok(ui.details.pin:IsShown(), "the details pin stays")
    CP.GuideTab.Forget()
    CP.GuideTab.InitRow(btn, row)
    T.ok(btn.pin:IsShown(), "not picked: the row pin shows")
end)

T.test("All mode: a card whose recipe needs more skill greys to its gate, or buys the pattern early", function()
    local ui = shutTailoring({ rank = 60, max = 150 })
    local placed = recordWaypoints()
    local live = W.LiveFor(TAILOR)
    local unlearned = {}
    for k, v in pairs(live) do unlearned[k] = v end
    unlearned.learned = {}
    local guide = CP.Guides[TAILOR]
    local function cardFor(pred)
        for spell, r in pairs(guide.recipes) do
            if r.npcs and #r.npcs > 0 and pred(r) then
                local card = CP.GuideTab.Card(unlearned)
                local target = CP.Guide.WaypointFor({ recipe = r, learned = false }, live.prof)
                card.spell, card.learned, card.recipe, card.guide = spell, false, r, guide
                card.learn, card.gate = target or false, CP.Guide.LearnGate(r, live.prof)
                card.gateLabel = card.gate and card.gate.label
                return card
            end
        end
    end
    local btn = CreateFrame("Button", nil, UIParent)
    local trainer = cardFor(function(r) return r.src == "trainer" and r.learn > 60 and r.learn <= 150 end)
    T.ok(trainer ~= nil, "a trainer recipe above skill 60")
    CP.GuideTab.InitCard(btn, trainer)
    T.eq(btn.craft.label:GetText(), "At " .. trainer.recipe.learn)
    T.ok(not isOn(btn.craft), "greyed")
    T.eq(trainer.learn, false, "no waypoint")
    click(btn.craft)
    T.eq(#placed, 0, "no waypoint call")
    local vendor = cardFor(function(r) return isVendor(r) and r.learn > 60 end)
    T.ok(vendor ~= nil, "a vendor pattern above skill 60")
    CP.GuideTab.InitCard(btn, vendor)
    T.eq(btn.craft.label:GetText(), "Buy pattern")
    T.ok(isOn(btn.craft), "on")
    click(btn.craft)
    T.eq(placed[#placed], vendor.recipe, "the waypoint goes to the vendor")
end)
