-- The owner's round-10 feedback on the guide window: the tab row in Buy mode,
-- the bug report above every window, bag marks on Daylight UI's bags with their trace,
-- windows that reach the screen's bottom edge, and both windows back when the attach
-- setting changes.

local CP = ProfLost
local W, P, GP, S = CP.Window, CP.Panel, CP.GatherPanel, CP.Style
local NM = CP.NeededMarks
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR = 1411
local MEDIUM_LEATHER, LINEN = 2319, 2589

local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "gatherAttached", true)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherPanelClosed", nil)
    World.set(CP.db, "gatherPoint", nil)
    World.set(CP.db, "gatherSize", nil)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 800 })
    World.set(CP.charDB, "guideMode", "one")
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.onEnd(function()
        CP.db.gatherAttached = true
        GP.ModeChanged()
        T.fire("PLAYER_REGEN_ENABLED")
        W.opened = false
        GP.anchor:ClearAllPoints()
        W.Update()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
end

-- 1. The tab row --------------------------------------------------------------------------

-- The harness has no font engine: a wide stand-in, 7.5 px a letter. Colour codes take no room.
local LETTER = 7.5
local function wideText(fs, text)
    if text then fs:SetText(text) end
    local plain = (fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return math.ceil(#plain * LETTER)
end

-- The tab row's shown pieces as { name, left, right }, left to right.
local function rowRects()
    local out = {}
    for _, k in ipairs(P.order) do
        local b = P.tabs[k].button
        if b:IsShown() then
            local _, _, _, x = b:GetPoint(1)
            out[#out + 1] = { k, x, x + b:GetWidth() }
        end
    end
    for _, r in ipairs(P.rowButtons) do
        local b = r.button
        if b:IsShown() then
            local _, _, _, x = b:GetPoint(1)
            local right = P.WIDTH + x
            out[#out + 1] = { b == W.pickButton and "dropdown" or "switch", right - b:GetWidth(), right }
        end
    end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

T.test("the tab row fits every profession name, Buy mode or not, folded or not, auction house open or shut", function()
    scene()
    World.set(P, "TextWidth", wideText)
    -- Tabs measure their labels themselves.
    for _, k in ipairs(P.order) do
        local label = P.tabs[k].button.label
        World.set(label, "GetUnboundedStringWidth", function(self) return wideText(self) end)
    end
    local names = {}
    for id, guide in pairs(CP.Guides) do names[#names + 1] = { id = id, name = guide.name } end
    for id, name in pairs(CP.Launcher.GATHER_NAMES) do names[#names + 1] = { id = id, name = name } end
    for _, collect in ipairs({ false, true }) do
        World.set(CP.db, "collect", collect)
        for _, folded in ipairs({ false, true }) do
            World.set(CP.db, "windowCollapsed", folded or nil)
            for _, ah in ipairs({ false, true }) do
                if ah then AHWorld.begin() AHWorld.Open() end
                for _, e in ipairs(names) do
                    World.set(W, "Professions", function() return { { id = e.id, name = e.name, skill = 1 } } end)
                    World.set(W, "ChosenID", function() return e.id end)
                    P:Refresh()
                    local where = ("%s, %s, %s, auction house %s"):format(e.name, collect and "Level as you go" or "Buy",
                        folded and "folded" or "open", ah and "open" or "shut")
                    T.eq(W.pickButton.label:GetText(), e.name, where)
                    T.ok(P.TextWidth(W.pickButton.label) <= W.pickButton:GetWidth() - 8,
                        where .. ": the whole name fits inside the dropdown")
                    local rects = rowRects()
                    T.ok(rects[1][2] >= 0 and rects[#rects][3] <= P.WIDTH, where .. ": inside the window")
                    for i = 2, #rects do
                        local a, b = rects[i - 1], rects[i]
                        T.ok(b[2] - a[3] >= 2, ("%s: %s (%d-%d) and %s (%d-%d) keep apart"):format(
                            where, a[1], a[2], a[3], b[1], b[2], b[3]))
                    end
                    T.eq(#rects, (folded and 0 or (collect and 1 or 2)) + 2,
                        where .. ": the tabs, the dropdown and View, and nothing else")
                end
                if ah then AHWorld.Close() end
            end
        end
    end
end)

T.test("Scan sits on the auction house window, labelled, only while the auction house is open", function()
    scene()
    World.set(CP.db, "collect", false)
    T.eq(CP.ShopTab.ui.scan, nil, "not in the Shop tab")
    AHWorld.begin()
    AHWorld.Open()
    local b = CP.ScanButton.button
    T.ok(b:IsShown(), "open: the button")
    T.eq(b:GetParent(), AHWorld.window, "on the auction house window")
    T.eq(b.label:GetText(), CP.Gradient("Scan prices"), "with its label")
    AHWorld.Close()
    T.ok(not b:IsShown())
end)

-- 2. The bug report ---------------------------------------------------------------------------

T.test("the bug report opens above every window, Daylight UI's options included", function()
    local function said(path, value)
        for _, c in ipairs(T.calls(path)) do
            if c[1] == value then return true end
        end
        return false
    end
    CP.BugReport.Show()
    local win = _G.ProfLost_BugReport
    World.onEnd(function() win:Hide() end)
    T.eq(CP.BugReport.STRATA, "FULLSCREEN_DIALOG", "above Daylight UI's DIALOG options window")
    T.ok(said("Frame:SetFrameStrata", "FULLSCREEN_DIALOG"), "in that strata")
    T.ok(said("Frame:SetToplevel", true), "toplevel: a click brings it to the front")
    local raised = #T.calls("Frame:Raise")
    T.ok(raised >= 1, "raised as it opens")
    win:Hide()
    CP.BugReport.Show()
    T.ok(#T.calls("Frame:Raise") > raised, "and on every later opening")
end)

-- 3. Bag marks on Daylight UI's bags ------------------------------------------------------------

-- Daylight UI's Paint registry (DaylightUI/API.lua) and DaylightUI_Bags' slot reports
-- (Items.Report, Window.FillDirty), as their code reads. Interface only:
--   * Report.Made fires the painters on a new frame with what it shows (rowInfo);
--     later fills call Report.Painted right after Daylight UI's own paint.
--   * me.Paint paints every frame made so far at once, then each later paint.
--   * API.Attach gives the same child overlay for its own frames, nil for any other.
--   * A slot fills only when its bag changes: nothing repaints it otherwise.
local function bags()
    local made, info, painters, holders = {}, {}, {}, {}
    local api = {}
    function api.Attach(frame)
        if not made[frame] then return nil end
        if not holders[frame] then
            local h = CreateFrame("Frame", nil, frame)
            h:SetAllPoints(frame)
            holders[frame] = h
        end
        return holders[frame]
    end
    local function painted(frame)
        for _, fn in ipairs(painters) do fn(frame, { icon = frame.icon }, info[frame]) end
    end
    local me = {}
    function me.Paint(kind, fn)
        if kind ~= "bagslot" then return nil end
        painters[#painters + 1] = fn
        for frame in pairs(made) do fn(frame, { icon = frame.icon }, info[frame]) end
        return { painter = true }
    end
    local B = { api = api, me = me, made = made }
    -- Items.Fill then Items.Report for slot `bag`:`slot` holding `item` (nil: empty).
    function B.Fill(btn, bag, slot, item)
        info[btn] = { bag = bag, slot = slot, itemID = item }
        if not made[btn] then
            made[btn] = true
            return painted(btn)
        end
        painted(btn)
    end
    function B.Slot()
        local b = CreateFrame("Button", nil, UIParent)
        b.icon = b:CreateTexture()
        return b
    end
    return B
end

local function marked(B, btn)
    local h = B.api.Attach(btn)
    return h ~= nil and h.profLostMark ~= nil and h.profLostMark:IsShown()
end

local function marksScene(needs)
    World.set(CP.db, "neededMarks", true)
    World.set(CP.charDB, "gatherNeeds", needs)
    World.set(CP.trace, "marks", nil)
    World.set(NM.stats, "daylight", NM.stats.daylight)
    -- The skill list would recompute the needs on the next frame.
    World.set(CP.Gather, "UpdateAllNeeds", function() end)
end

T.test("Daylight UI's slots made before ProfLost asks get marked when it asks", function()
    marksScene({ [LW] = { [MEDIUM_LEATHER] = 10 } })
    local B = bags()
    local early, other = B.Slot(), B.Slot()
    B.Fill(early, 0, 1, MEDIUM_LEATHER)
    B.Fill(other, 0, 2, LINEN)
    T.ok(NM.UseDaylight(B.me, B.api))
    T.eq(NM.stats.daylight, "registered")
    T.ok(marked(B, early), "a needed item: marked on Daylight UI's overlay")
    T.eq(B.api.Attach(early).profLostMark.prof, LW)
    T.ok(not marked(B, other), "an item no guide needs: none")
    B.Fill(early, 0, 1, nil)
    T.ok(not marked(B, early), "emptied: the mark goes")
end)

T.test("a slot filled before its item was needed gets the mark when the needs change, with no refill", function()
    marksScene({})
    local B = bags()
    NM.UseDaylight(B.me, B.api)
    local slot = B.Slot()
    B.Fill(slot, 1, 4, MEDIUM_LEATHER)
    T.ok(not marked(B, slot), "nothing needs it yet")
    CP.charDB.gatherNeeds = { [LW] = { [MEDIUM_LEATHER] = 10 } }
    CP:Emit("ProfLost_NEEDS")
    T.advance(0.1)
    T.ok(marked(B, slot), "the guides' needs changed: repainted where it stands")
    CP.charDB.gatherNeeds = {}
    CP:Emit("ProfLost_NEEDS")
    T.advance(0.1)
    T.ok(not marked(B, slot), "and unmarked when no longer needed")
end)

T.test("a saved plan tells the bag marks its needs changed", function()
    scene()
    local heard = 0
    local listening = true
    World.onEnd(function() listening = false end)
    CP:On("ProfLost_NEEDS", function() if listening then heard = heard + 1 end end)
    local live = CP.Plan.Shut(LW)
    T.ok(live ~= nil and live.plan ~= nil, "a plan for the shut profession")
    CP.Gather.SaveNeeds(live)
    T.ok(heard >= 1, "ProfLost_NEEDS raised")
end)

T.test("trace marks: each paint and why, a summary on, capped lines a second, off stops it", function()
    marksScene({ [LW] = { [MEDIUM_LEATHER] = 10 } })
    local B = bags()
    NM.UseDaylight(B.me, B.api)
    local slot = B.Slot()
    B.Fill(slot, 0, 3, MEDIUM_LEATHER)
    T.advance(1.1)   -- a fresh second for the cap

    local from = #T.prints()
    SlashCmdList.PROFLOST("trace marks on")
    T.eq(CP.trace.marks, true, "on")
    local text = table.concat(T.prints(), "\n", from + 1)
    T.ok(text:find("Bag marks trace on: setting on, needs for 1 professions, Daylight UI paint registered", 1, true) ~= nil, text)
    T.ok(text:find("seen daylight 0:3 item 2319, drawn yes", 1, true) ~= nil, "each slot seen so far")

    T.advance(1.1)
    from = #T.prints()
    B.Fill(slot, 0, 3, LINEN)
    text = table.concat(T.prints(), "\n", from + 1)
    T.ok(text:find("daylight 0:3 item 2589, needed no, drawn no (not needed)", 1, true) ~= nil, text)
    B.Fill(slot, 0, 3, MEDIUM_LEATHER)
    text = table.concat(T.prints(), "\n", from + 1)
    T.ok(text:find("daylight 0:3 item 2319, needed Leatherworking, drawn yes", 1, true) ~= nil, text)

    local stray = CreateFrame("Button", nil, UIParent)
    B.made[stray] = nil
    from = #T.prints()
    NM.UseDaylight({ Paint = function(_, fn) fn(stray, {}, { bag = 2, slot = 1, itemID = MEDIUM_LEATHER }) return {} end },
        { Attach = function() return nil end })
    text = table.concat(T.prints(), "\n", from + 1)
    T.ok(text:find("daylight 2:1: API.Attach gave no overlay", 1, true) ~= nil, "a frame Daylight UI won't attach to says so")

    T.advance(1.1)
    from = #T.prints()
    for i = 1, NM.TRACE_PER_SECOND + 15 do B.Fill(B.Slot(), 1, i, MEDIUM_LEATHER) end
    T.eq(#T.prints() - from, NM.TRACE_PER_SECOND, "at most TRACE_PER_SECOND lines a second")
    T.advance(1.1)
    B.Fill(slot, 0, 3, MEDIUM_LEATHER)
    text = table.concat(T.prints(), "\n", from + 1)
    T.ok(text:find("(15 lines dropped)", 1, true) ~= nil, "then how many it dropped")

    SlashCmdList.PROFLOST("trace marks off")
    T.eq(CP.trace.marks, nil)
    from = #T.prints()
    B.Fill(slot, 0, 3, MEDIUM_LEATHER)
    T.eq(#T.prints() - from, 0, "off: silent")
end)

-- 5. Reaching the screen's bottom edge ---------------------------------------------------------

local function below(anchor)
    local last = T.calls("Frame:SetClampRectInsets")
    T.ok(#last > 0, "the clamp rect was set")
    return anchor.profLostClampBelow
end

T.test("the guide window's anchor keeps its largest size but clamps only the window's own height", function()
    scene()
    P:Refresh()
    local full = W.ExpandedHeight()
    T.eq(W.anchor:GetHeight(), full, "the mover still shows the largest window")
    W.SetFolded(true)
    local h = P.frame:GetHeight()
    T.ok(h < full, "folded: shorter than the anchor")
    T.eq(below(W.anchor), full - h, "the part under the window may leave the screen")
    W.SetFolded(false)
    T.eq(W.anchor.profLostClampBelow, full - P.frame:GetHeight(), "it follows the height")
    local c = T.calls("Frame:SetClampRectInsets")
    local last = c[#c]
    -- The sides reach over an attached gathering panel that is out (clamp_test).
    T.eq({ last[1], last[2], last[3], last[4] },
        { -W.anchor.profLostClampLeft, W.anchor.profLostClampRight, 0, W.anchor.profLostClampBelow }, "the bottom inset, and the panel's side")
end)

T.test("the detached gathering panel's anchor is the panel's size, so the clamp keeps all of it on screen", function()
    scene()
    World.set(GP.anchor, "GetLeft", function() return 420 end)
    World.set(GP.anchor, "GetTop", function() return 800 end)
    World.set(CP.GatherList, "NeedHeight", function() return 40 end)
    CP.Settings.Set("gatherAttached", false)
    GP.Fit()
    T.eq(GP.anchor:GetHeight(), GP.sheet:GetHeight(), "a short list: the anchor is no taller")
    T.eq(below(GP.anchor), 0)
end)

-- 6. The attach setting keeps closed windows closed (round 11 replaced "brings both back") ---------

T.test("attaching with the guide window closed keeps it closed", function()
    scene()
    World.set(GP.anchor, "GetLeft", function() return 420 end)
    World.set(GP.anchor, "GetTop", function() return 800 end)
    CP.Settings.Set("gatherAttached", false)
    W.Close()
    T.ok(not P.frame:IsShown(), "the guide window closed")
    T.ok(GP.sheet:IsVisible(), "the detached panel stays")
    CP.Settings.Set("gatherAttached", true)
    T.ok(not P.frame:IsShown(), "the guide window stays closed")
    T.eq(CP.db.windowClosed, true, "its close is kept")
    T.ok(GP.IsOpen(), "the panel, open while detached, is out once the guide opens")
end)

T.test("detaching with both closed keeps both closed", function()
    scene()
    World.set(GP.anchor, "GetLeft", function() return 420 end)
    World.set(GP.anchor, "GetTop", function() return 800 end)
    CP.db.gatherOpen = false
    W.Close()
    CP.Settings.Set("gatherAttached", false)
    T.ok(not P.frame:IsShown(), "the guide window stays closed")
    T.ok(not GP.sheet:IsVisible(), "the panel, folded while attached, stands closed")
    T.eq(CP.db.gatherPanelClosed, true)
    CP.Settings.Set("gatherAttached", true)
    T.ok(not P.frame:IsShown() and not GP.IsOpen(), "attaching again: still both closed")
end)
