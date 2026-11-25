-- The craft strip's Stop: a secure /stopcasting button over the visible one, on
-- Daylight UI's Win.Caster when it is loaded and on our own button without it.

local CP = ProfLost
local C = CP.Crafting

local function strip()
    local parent = CreateFrame("Frame", nil, UIParent)
    parent:SetSize(300, 40)
    parent:SetPoint("CENTER")
    local s = C.Strip(parent)
    s:SetAllPoints(parent)
    parent:Show()
    s:Show()
    -- The headless client lays nothing out; give Stop a place on screen.
    s.stop.GetLeft = function() return 100 end
    s.stop.GetBottom = function() return 50 end
    s.stop.GetWidth = function() return 72 end
    s.stop.GetHeight = function() return 22 end
    s.stop.GetEffectiveScale = function() return 1 end
    UIParent.GetEffectiveScale = function() return 1 end
    return s
end

local function origin(b)
    local _, _, _, x, y = b:GetPoint()
    return x, y
end

World.onEnd(function() UIParent.GetEffectiveScale = nil end)

local function busy(n)
    C.count, C.total = n, n
end

T.test("without Daylight UI, Stop has our own secure /stopcasting button over it", function()
    busy(5)
    local s = strip()
    s:GetScript("OnUpdate")(s)
    local b = C.overlay and C.overlay.button
    T.ok(b, "the overlay exists")
    T.ok(b:GetAttribute("type") ~= nil, "secure")
    T.eq(b:GetAttribute("type"), "macro")
    T.eq(b:GetAttribute("macrotext"), "/stopcasting")
    T.eq(b:GetParent(), UIParent, "never a child of our panel")
    T.ok(b:IsShown(), "shown over Stop")
    T.eq({ b:GetWidth(), b:GetHeight() }, { 72, 22 })
    T.eq({ origin(b) }, { 100, 50 }, "at Stop's corner")
    s:Hide()
    T.ok(not b:IsShown(), "gone with the strip")
    busy(0)
end)

T.test("in combat the overlay does not change; it follows after combat", function()
    busy(5)
    local s = strip()
    s:GetScript("OnUpdate")(s)
    local b = C.overlay.button
    World.patch("InCombatLockdown", function() return true end)
    s:Hide()
    T.ok(b:IsShown(), "no hide in combat")
    s:Show()
    s.stop.GetLeft = function() return 105 end
    s:GetScript("OnUpdate")(s)
    T.eq({ origin(b) }, { 100, 50 }, "no move in combat")
    World.patch("InCombatLockdown", function() return false end)
    s:Hide()
    T.ok(not b:IsShown(), "hidden once out of combat")
    busy(0)
end)

T.test("a click on the overlay ends the batch; so does an interrupt", function()
    busy(5)
    local s = strip()
    s:GetScript("OnUpdate")(s)
    local b = C.overlay.button
    b:GetScript("PostClick")(b, "LeftButton")
    T.ok(not C.Busy(), "Stop clears the batch")
    busy(5)
    T.fire("UNIT_SPELLCAST_INTERRUPTED", "player")
    T.ok(not C.Busy(), "an interrupt clears it too")
    s:Hide()
end)

T.test("with Daylight UI, Stop rides its Win.Caster with /stopcasting", function()
    DaylightWorld.begin({})
    busy(5)
    local s = strip()
    s:GetScript("OnUpdate")(s)
    local c = DaylightWorld.state.casters[1]
    T.ok(c and c.button, "Daylight's caster made the overlay")
    T.eq(c.button:GetAttribute("type1"), "macro")
    T.eq(c.button:GetAttribute("macrotext1"), "/stopcasting")
    T.eq(c.button.row, s.stop, "over Stop")
    c.spec.post()
    T.ok(not C.Busy(), "its click ends the batch")
    busy(0)
    s:Hide()
end)

-- Simulator finding, 2026-11-16 (controls, roundtrip): the step card kept the strip and its
-- secure Stop after the batch ended, when the card had moved to a row without craft buttons.
T.test("the step card's strip follows the batch: on a stop row it goes once the batch ends", function()
    local LW, KIT, LIGHT_LEATHER = 165, 2152, 2318
    MapWorld.begin({ zone = 1411, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 45 }, bags = { [LIGHT_LEATHER] = 20 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.Open(LW)
    T.advance(2)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    local ui = CP.GuideTab.ui
    local d = ui.details
    local stop
    for _, row in ipairs(ui.rows) do
        if row.rank or row.train then stop = row break end
    end
    T.ok(stop ~= nil, "Leatherworking at 45 has a stop row")
    C.Start(KIT, 3)
    T.advance(0.5)
    T.ok(d.making:IsShown(), "the strip shows while the batch runs")
    CP.GuideTab.Pick(stop)
    T.advance(0.5)
    while CraftWorld.Cast() do T.advance(3) end
    T.advance(1)
    T.ok(not C.Busy(), "the batch is over")
    T.ok(not d.making:IsShown(), "no strip once the batch ended")
    local b = C.overlay and C.overlay.button
    T.ok(not (b and b:IsShown()), "no live secure Stop")
    CraftWorld.Close()
end)
