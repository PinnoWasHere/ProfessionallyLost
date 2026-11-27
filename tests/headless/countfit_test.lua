-- Have / need counts show whole in the compact guide window: the step card's material
-- counts never cut, even when the measuring gauge reads a count narrower than it draws
-- (another face, another scale), and a string made after the font setting draws in ProfLost's
-- font, as the gauge measures it. Fonts come from the visual world (tests/world/visual.lua).

local CP = ProfLost
local W, P, GP, GT, S = CP.Window, CP.Panel, CP.GatherPanel, CP.GuideTab, CP.Style
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR = 1411

local function settle() T.advance(0.5) end

local function scene()
    Visual.begin()
    DaylightWorld.begin({ plugin = true })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowCollapsedAll", nil)
    World.set(CP.db, "collect", true)
    World.set(CP.db, "gatherAttached", true)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherSide", "right")
    World.set(CP.db, "windowHeight", CP.DEFAULTS.windowHeight)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 900 })
    World.set(CP.db, "font", "general")
    World.set(CP.db, "textScale", 1)
    World.set(CP.charDB, "guideMode", "one")
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.onEnd(function()
        -- The window re-measures in the saved font and size, which World.set restores after this.
        CP.db.font, CP.db.textScale = "general", 1
        CraftWorld.Close()
        S.ApplyScale()
        S.ApplyFont()
        W.SetFolded(false)
        GP.anchor:ClearAllPoints()
        W.Update()
        P:Refresh()
        settle()
        -- The guide's width need was measured for this test's step; the world ends without
        -- another refresh, so the next test would start at that width.
        P.SetNeed("guide", nil)
        P.ApplyWidth()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    W.Pick(LW)
    W.SetFolded(true)
    P:Refresh()
    settle()
    -- The first craft step is picked, so the card lists its materials.
    World.set(CP.charDB, "guidePicks", {})
    for _, row in ipairs(GT.ui.rows) do
        if row.spell and not (row.rank or row.train) then
            CP.charDB.guidePicks[LW] = row.key
            break
        end
    end
    P:Refresh()
    settle()
end

-- The step card's shown material rows.
local function shownRows()
    local out = {}
    for _, line in ipairs(GT.ui.details.rows) do
        if line:IsShown() then out[#out + 1] = line end
    end
    return out
end

T.test("the folded step card's have / need counts show whole when the gauge reads them short", function()
    scene()
    T.ok(P.folded, "the window is folded")
    -- A gauge in another face or at another scale reads every text 4 px short.
    local measure = S.Measure
    World.set(S, "Measure", function(text, size, fixed)
        return math.max(0, measure(text, size, fixed) - 4)
    end)
    P:Refresh()
    settle()
    local rows = shownRows()
    T.ok(#rows > 0, "the card shows material rows")
    for _, line in ipairs(rows) do
        local text = line.count:GetText() or ""
        T.ok(text:find("^%d+ / %d+$") ~= nil, "a have / need count: " .. text)
        T.eq(line.count:IsTruncated(), false, ("the count %q shows whole"):format(text))
    end
    Visual.Check("folded, a short gauge")
end)

T.test("the step card's tags line up left of the widest count", function()
    scene()
    local rows = shownRows()
    T.ok(#rows > 1, "two or more material rows")
    local counts = {}
    for _, line in ipairs(rows) do counts[#counts + 1] = line.count:GetText() end
    local widest = S.Widest(counts, "small")
    for _, line in ipairs(rows) do
        local gap = line:GetRight() - line.tag:GetRight()
        T.ok(math.abs(gap - (widest + GT.COUNT_GAP)) < 0.5,
            ("the tag ends %.1f px left of the row's right edge, not %d"):format(gap, widest + GT.COUNT_GAP))
        T.ok(line.count:GetLeft() >= line.tag:GetRight() + GT.COUNT_GAP - 0.5, "the count starts right of its tag's gap")
    end
end)

-- The header with three coupled professions at the smallest text size: the window stops at
-- its cap, so the skill text breaks onto lines beside the name, the count whole on the last.
for _, size in ipairs({ 0.85, 1, 1.15 }) do
    T.test(("the header's skill count stays whole and clear of the name at text size %.2f"):format(size), function()
        scene()
        World.set(GT, "WithText", function() return "with Enchanting, Herbalism, Skinning" end)
        CP.Settings.Set("textScale", size)
        P:Refresh()
        -- The client fires OnSizeChanged on the window's new height; the harness doesn't.
        local resized = P.frame:GetScript("OnSizeChanged")
        if resized then resized(P.frame, P.frame:GetWidth(), P.frame:GetHeight()) end
        settle()
        local ui = GT.ui
        local text = ui.skillText:GetText()
        T.ok(text:find("Skinning") ~= nil, "the header names the coupled professions: " .. text)
        local last = text:match("([^\n]*)$")
        T.ok(last:find("%d+ / %d+$") ~= nil, ("the count is whole on the last line: %q"):format(text))
        local nameRight = ui.prof:GetLeft() + ui.prof:GetUnboundedStringWidth()
        T.ok(ui.skillText:GetLeft() >= nameRight - 0.5,
            ("the skill text starts at %.1f, right of the name's end at %.1f: %q"):format(ui.skillText:GetLeft(), nameRight, text))
        T.ok(ui.skillText:GetRight() <= P.frame:GetRight() + 0.5, "the skill text ends inside the window")
        T.ok(ui.bar:GetTop() <= ui.skillText:GetBottom() + 0.5,
            ("the bar (top %.1f) sits below the skill text (bottom %.1f)"):format(ui.bar:GetTop(), ui.skillText:GetBottom()))
        Visual.Check(("the header at %.2f"):format(size))
    end)
end

T.test("a string made after the font setting draws in ProfLost's font", function()
    scene()
    CP.Settings.Set("font", "wide")
    settle()
    local fs = S.Text(UIParent, "small")
    T.eq((fs:GetFont()), DaylightWorld.FONT_FILES.wide, "the new string's font file")
    fs:SetText("12 / 20")
    T.eq(S.Measure("12 / 20", "small"), math.ceil(fs:GetUnboundedStringWidth()), "the gauge measures it as it draws")
    fs:Hide()
end)
