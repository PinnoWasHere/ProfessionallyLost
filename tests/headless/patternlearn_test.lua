-- A pattern in the bags: the step card's button reads "Learn pattern" and its click uses
-- the pattern through a secure /use overlay (UI/PatternLearn.lua). Learning, caught with
-- no profession window open, flips the card to Open at once.

local CP = ProfLost
local W, P, GT, PL = CP.Window, CP.Panel, CP.GuideTab, CP.PatternLearn
local LW = 165
local DUROTAR = 1411

-- Leatherworking at `skill`, its window opened once so its known recipes are saved, then
-- shut; the free guide window open on it, shown in combat too.
local function scene(skill)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = skill or 100 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "gatherHideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function()
        PL.Release()
        PL.pending = nil
        W.Update()
    end)
    CraftWorld.Open(LW)
    CraftWorld.Close()
    W.Update()
    W.Pick(LW)
    P:Refresh()
    T.advance(0.1)
end

-- The first unlearned step, its recipe made a vendor pattern (item PATTERN) learnable at
-- `learnAt` for the test, picked.
local PATTERN = 2555
local function patternRow(learnAt)
    for _, row in ipairs(GT.ui.rows) do
        local r = row.recipe
        if r and not row.learned and not (row.rank or row.train or row.side) then
            World.set(r, "pattern", PATTERN)
            World.set(r, "src", "vendor")
            World.set(r, "learn", learnAt)
            GT.Pick(row)
            T.advance(0.1)
            return row
        end
    end
end

local function card() return GT.ui.details.craftAll end

local function refresh()
    P:Refresh()
    T.advance(0.1)
end

-- The headless client lays nothing out: give the button a place on screen.
local function placed(b)
    World.set(b, "GetLeft", function() return 100 end)
    World.set(b, "GetBottom", function() return 50 end)
    World.set(b, "GetWidth", function() return 96 end)
    World.set(b, "GetHeight", function() return 22 end)
    World.set(b, "GetEffectiveScale", function() return 1 end)
    World.set(UIParent, "GetEffectiveScale", function() return 1 end)
end

T.test("a learnable pattern in the bags reads Learn pattern; its overlay uses the item", function()
    scene(100)
    local row = patternRow(100)
    T.ok(row ~= nil, "a pattern step at or below the skill")
    local b = card()
    T.ok(b.label:GetText() ~= PL.LABEL, "no pattern in the bags: " .. tostring(b.label:GetText()))
    CraftWorld.SetBag(row.recipe.pattern, 1)
    refresh()
    T.eq(b.label:GetText(), PL.LABEL)
    T.ok(CP.Style.IsOn(b), "enabled")
    T.eq(b.usePattern and b.usePattern.item, row.recipe.pattern)
    placed(b)
    b:GetScript("OnEnter")(b)
    local o = PL.Overlay()
    local secure = o.button
    T.ok(secure ~= nil, "the secure overlay exists")
    T.eq(secure:GetAttribute("type"), "macro")
    T.eq(secure:GetAttribute("macrotext"), "/use item:" .. row.recipe.pattern)
    T.eq(secure:GetParent(), UIParent, "never a child of our panel")
    T.ok(secure:IsShown(), "laid over the button")
    -- The visible button's own click does nothing: the overlay takes it.
    local asked = #CraftWorld.state.asked
    b:GetScript("OnClick")(b, "LeftButton")
    T.eq(#CraftWorld.state.asked, asked, "no craft, no waypoint")
end)

T.test("using the pattern flips the card to Open with no profession window", function()
    scene(100)
    local row = patternRow(100)
    CraftWorld.SetBag(row.recipe.pattern, 1)
    refresh()
    local b = card()
    placed(b)
    b:GetScript("OnEnter")(b)
    local secure = PL.Overlay().button
    secure:GetScript("PostClick")(secure, "LeftButton")
    T.eq(PL.pending and PL.pending.spell, row.spell, "the click waits for the learn")
    CraftWorld.SetBag(row.recipe.pattern, 0)   -- the pattern is used up: learned
    T.advance(0.2)
    T.ok(not CraftWorld.Opened(), "no profession window opened")
    local known = CP.charDB.learned[LW]
    local has = false
    for _, id in ipairs(known) do if id == row.spell then has = true end end
    T.ok(has, "saved as learned")
    T.eq(b.label:GetText(), "Open", "the card offers Open, as for any known recipe")
    T.eq(b.usePattern, nil)
    T.ok(not secure:IsShown(), "the overlay is gone")
end)

T.test("the game's learn event alone flips the card", function()
    scene(100)
    local row = patternRow(100)
    CraftWorld.SetBag(row.recipe.pattern, 1)
    refresh()
    T.eq(card().label:GetText(), PL.LABEL)
    T.fire("NEW_RECIPE_LEARNED", row.spell)
    T.advance(0.2)
    T.eq(card().label:GetText(), "Open")
end)

T.test("the learn line in chat flips the card after a click", function()
    scene(100)
    local row = patternRow(100)
    CraftWorld.SetBag(row.recipe.pattern, 1)
    refresh()
    PL.pending = { spell = row.spell, item = row.recipe.pattern, count = 1, at = GetTime() }
    T.fire("CHAT_MSG_SYSTEM", "You have learned how to create a new item: " .. row.recipe.name .. ".")
    T.advance(0.2)
    T.eq(card().label:GetText(), "Open")
    T.fire("CHAT_MSG_SYSTEM", "You have learned how to create a new item: Anything.")
    T.eq(PL.pending, nil, "nothing waits after")
end)

T.test("a pattern above the skill keeps its greyed gate; in combat Learn pattern greys with the reason", function()
    scene(60)
    local row = patternRow(70)
    T.ok(row ~= nil, "a pattern step above the skill")
    CraftWorld.SetBag(row.recipe.pattern, 1)
    refresh()
    local b = card()
    T.eq(b.label:GetText(), "At " .. row.recipe.learn)
    T.ok(not CP.Style.IsOn(b), "greyed")

    scene(100)
    row = patternRow(100)
    CraftWorld.SetBag(row.recipe.pattern, 1)
    World.patch("InCombatLockdown", function() return true end)
    T.fire("PLAYER_REGEN_DISABLED")
    refresh()
    b = card()
    T.eq(b.label:GetText(), PL.LABEL)
    T.ok(not CP.Style.IsOn(b), "greyed in combat")
    T.eq(b.tip, PL.COMBAT_TIP)
    World.patch("InCombatLockdown", function() return false end)
    T.fire("PLAYER_REGEN_ENABLED")
    refresh()
    T.ok(CP.Style.IsOn(b), "back after combat")
end)

T.test("with Daylight UI the overlay is its Win.Caster with the same /use", function()
    DaylightWorld.begin({})
    scene(100)
    local row = patternRow(100)
    CraftWorld.SetBag(row.recipe.pattern, 1)
    refresh()
    local b = card()
    placed(b)
    b:GetScript("OnEnter")(b)
    local c
    for _, x in ipairs(DaylightWorld.state.casters) do
        if x.spec.name == "ProfLost_LearnPattern" then c = x end
    end
    T.ok(c and c.button, "Daylight's caster made the overlay")
    T.eq(c.button:GetAttribute("type1"), "macro")
    T.eq(c.button:GetAttribute("macrotext1"), "/use item:" .. row.recipe.pattern)
    T.eq(c.button.row, b, "over the button")
    c.spec.post(b)
    T.eq(PL.pending and PL.pending.item, row.recipe.pattern, "its click waits for the learn")
end)
