-- The guide window after the owner's 0.2.9-beta test: Open
-- with DaylightMogul's window and with Daylight UI's window opening late, the trace saying
-- why Daylight UI reports nothing, row clicks that never open a shut window, the title
-- bar and tab row, the top accent line, every button as Daylight UI's own, and the
-- gathering panel's drag.

local CP = ProfLost
local W, P, S, Host = CP.Window, CP.Panel, CP.Style, CP.Host
local LW, TAILOR = 165, 197
local DUROTAR = 1411

-- Leatherworking and Tailoring, Tailoring's window opened once and shut; the free window
-- on Tailoring in One mode.
local function shutTailoring()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
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
    -- The guide keeps an earlier test's pick on the same profession: start on the current step.
    for _, r in ipairs(CP.GuideTab.ui.rows or {}) do
        if r.current then
            CP.GuideTab.Pick(r)
            break
        end
    end
    return CP.GuideTab.ui
end

local function click(b) b:GetScript("OnClick")(b) end

-- Prints since `from`, joined.
local function printed(from)
    local out = {}
    for i = from + 1, #T.prints() do out[#out + 1] = tostring(T.prints()[i]) end
    return table.concat(out, "\n")
end

local function traceOn()
    World.onEnd(function() CP.trace.open = nil end)
    CP.trace.open = true
end

-- Open with DaylightMogul's window ------------------------------------------------------

-- The owner's trace: Daylight UI loaded with DaylightMogul, whose window replaces Daylight
-- UI's. "Daylight nil" on every line, and the pick spent on OpenRecipe in the game's
-- hidden window.
T.test("DaylightMogul's window: the trace says why Daylight UI is nil, and the pick skips the hidden game window", function()
    DaylightWorld.begin({ plugin = true, mogul = true })
    MogulWorld.begin({ craftWindow = true })
    local ui = shutTailoring()
    traceOn()
    local recipe = ui.details.craftAll.recipeID
    local from = #T.prints()
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)
    T.advance(0.3)
    local text = printed(from)
    T.ok(text:find("Daylight nil %(its window is off because DaylightMogul's window owns professions%)") ~= nil,
        "the reason in:\n" .. text)
    T.ok(text:find("window mogul") ~= nil, "which window the player sees, in:\n" .. text)
    T.ok(text:find("no call to select recipe") ~= nil, "what became of the pick, in:\n" .. text)
    T.ok(text:find("OpenRecipe") == nil, "no OpenRecipe into the game's hidden window, in:\n" .. text)
    T.eq(CraftWorld.Selected(), nil, "the game's window was left alone")
    T.eq(W.PendingPick(), nil, "the pick is spent once the window shows the profession")
    T.eq(CraftWorld.Asked()[1], TAILOR, "the window was opened")
end)

T.test("DaylightMogul with a select call: the pick lands through it", function()
    DaylightWorld.begin({ plugin = true, mogul = true })
    MogulWorld.begin({ craftWindow = true, select = true })
    local ui = shutTailoring()
    local recipe = ui.details.craftAll.recipeID
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)
    T.advance(0.3)
    T.eq(MogulWorld.state.selected, recipe, "Mogul's window selected the step's recipe")
    T.eq(CraftWorld.Selected(), nil, "not the game's")
end)

-- Open with Daylight UI's window late ----------------------------------------------------

T.test("Daylight UI's window on but slow to open: the pick waits for it instead of the game's window", function()
    DaylightWorld.begin({ plugin = true, lag = 1.5 })
    local ui = shutTailoring()
    traceOn()
    -- A learned step, so Daylight UI's list holds it whatever earlier files left behind.
    for _, r in ipairs(ui.rows) do
        if r.spell and r.learned and not (r.rank or r.train) then
            CP.GuideTab.Pick(r)
            break
        end
    end
    local recipe = ui.details.craftAll.recipeID
    T.ok(CraftWorld.Known(TAILOR, recipe), "a learned step")
    local from = #T.prints()
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)   -- the game's window and its events, 0.3 s
    T.ok(not DaylightWorld.state.window:IsShown(), "its window isn't up yet")
    T.eq(CraftWorld.Selected(), nil, "no OpenRecipe into the game's hidden window")
    T.ok(W.PendingPick() ~= nil, "the pick still waits")
    T.ok(printed(from):find("OpenRecipe") == nil, printed(from))
    T.advance(1.5)
    T.ok(DaylightWorld.state.window:IsShown())
    T.eq(DaylightWorld.state.selected, recipe, "selected in Daylight UI's window once it opened")
    T.eq(W.PendingPick(), nil)
end)

T.test("the trace names a missing plugin view and a shut window", function()
    T.ok(Host.DaylightWhy():find("no plugin view") ~= nil, Host.DaylightWhy())
    DaylightWorld.begin({ plugin = true })
    T.eq(Host.DaylightWhy(), "its window is shut or has no profession yet")
    shutTailoring()
    CraftWorld.Open(TAILOR)
    T.eq(Host.DaylightWhy(), nil, "nothing to explain with its window up")
    T.eq(Host.Holder(), "daylight")
    T.ok(Host.DaylightOwns() and not Host.MogulOwns(), "Daylight UI's window on, no Mogul")
end)

T.test("with DaylightMogul, Daylight UI's window is off and Mogul's holds the profession", function()
    DaylightWorld.begin({ plugin = true, mogul = true })
    MogulWorld.begin({ craftWindow = true })
    T.ok(Host.MogulOwns() and not Host.DaylightOwns())
    T.ok(not Host.MogulCanSelect(), "Mogul 0.1.1 has no select call")
    shutTailoring()
    CraftWorld.Open(TAILOR)
    T.eq(Host.Holder(), "mogul")
    T.ok(Host.DaylightWhy():find("DaylightMogul") ~= nil, Host.DaylightWhy())
end)

-- Row clicks -------------------------------------------------------------------------------

local function recipeRow(ui, learned)
    for _, r in ipairs(ui.rows) do
        if r.spell and not (r.rank or r.train) and r ~= ui.rows[1] and (learned == nil or r.learned == learned) then
            return r
        end
    end
end

T.test("a row click with the profession shut picks the row and never opens the window", function()
    local ui = shutTailoring()
    local row = recipeRow(ui)
    T.ok(row ~= nil)
    CP.GuideTab.Pick(row)
    T.eq(#CraftWorld.Asked(), 0, "no OpenTradeSkill")
    T.eq(W.PendingPick(), nil, "no pick waiting")
    T.eq(ui.details.craftAll.recipeID, row.spell, "the step card shows the row")
    T.eq(ui.details.craftAll.label:GetText(), "Open", "and its Open button still opens on request")
end)

T.test("a row click with the profession open selects there, the game's window or Daylight UI's", function()
    local ui = shutTailoring()
    CraftWorld.Open(TAILOR)
    local row = recipeRow(ui, true)
    CP.GuideTab.Pick(row)
    T.eq(CraftWorld.Selected(), row.spell, "the game's window")
    CraftWorld.Close()

    DaylightWorld.begin({ plugin = true })
    ui = shutTailoring()
    CraftWorld.Open(TAILOR)
    row = recipeRow(ui, true)
    CP.GuideTab.Pick(row)
    T.eq(DaylightWorld.state.selected, row.spell, "Daylight UI's window")
    T.eq(#CraftWorld.Asked(), 0)
end)

-- Title bar and tab row --------------------------------------------------------------------

-- Insets from the anchor each piece hangs by: left for TOPLEFT, right for TOPRIGHT, and down.
local function left(fr) local _, _, _, x = fr:GetPoint(1) return x end
local function right(fr) local _, _, _, x = fr:GetPoint(1) return -x end
local function top(fr) local _, _, _, _, y = fr:GetPoint(1) return -y end

T.test("the title bar keeps Daylight UI's insets, and the title shows in both views", function()
    shutTailoring()
    W.Update()
    T.advance(0.1)
    T.eq(left(P.logo), P.TITLE_INSET, "the logo starts 16 px in")
    T.eq(P.TITLE_INSET, 16)
    T.eq(right(W.closeButton), P.TITLE_EDGE, "the close box 13 px in, its 12 px X ending 15 px in")
    T.eq(P.TITLE_EDGE, 13)
    T.eq(P.TITLE_GAP, 6)
    for _, mode in ipairs({ "one", "all" }) do
        W.SetMode(mode)
        T.ok(P.title:IsShown(), mode .. ": the title shows on the free window")
        T.eq(P.title:GetText(), CP.Gradient("Professionally Lost"))
    end
    W.SetMode("one")
    CraftWorld.Open(LW)
    T.ok(P.title:IsShown(), "a profession window open: the title shows")
    CraftWorld.Close()
end)

T.test("View and the dropdown sit on the right of the tab row, View rightmost, and stay when folded", function()
    shutTailoring()
    W.Update()
    T.advance(0.1)
    local view, pick = W.switchButton, W.pickButton
    T.eq(view.label:GetText(), W.ViewLabel("one"), "One view: One lit")
    T.ok(top(view) >= P.TITLE_H and top(pick) >= P.TITLE_H, "both below the title bar")
    T.eq(right(view), P.ROW_EDGE, "View at the row's right edge")
    T.eq(right(pick), P.ROW_EDGE + view:GetWidth() + P.ROW_GAP, "the dropdown left of View")
    local pickLeft = P.WIDTH - right(pick) - pick:GetWidth()
    for _, k in ipairs(P.order) do
        local b = P.tabs[k].button
        if b:IsShown() then T.ok(left(b) + b:GetWidth() <= pickLeft, k .. " tab clear of the dropdown") end
    end
    click(view)
    T.eq(W.Mode(), "all")
    T.eq(view.label:GetText(), W.ViewLabel("all"))
    T.ok(not pick:IsShown(), "no dropdown in the All view")
    T.ok(W.Folded(), "All starts folded")
    T.ok(view:IsShown(), "folded, View stays")
    T.ok(not P.tabs.guide.button:IsShown(), "folded, the tabs go")
    click(view)
    T.eq(W.Mode(), "one")
end)

-- Buttons -----------------------------------------------------------------------------------

T.test("with Daylight UI every ProfLost button is its own button, with hover, sound and SetOff", function()
    DaylightWorld.begin({ plugin = true })
    local b = S.Button(UIParent, 80)
    T.ok(b.dressed, "API.Button")
    T.eq(b.label, b.text)
    local tipped = 0
    b:SetScript("OnEnter", function() tipped = tipped + 1 end)
    b:GetScript("OnEnter")(b)
    T.ok(b.lit, "hover lights its trace")
    T.eq(tipped, 1, "and the caller's hover still runs")
    b:GetScript("OnLeave")(b)
    T.ok(not b.lit)
    local sounds = DaylightWorld.state.sounds
    b:GetScript("PostClick")(b)
    T.eq(DaylightWorld.state.sounds, sounds + 1, "its click sound")
    S.SetEnabled(b, false)
    T.ok(b.off and not b:IsEnabled(), "SetEnabled dims it through SetOff")
    S.SetEnabled(b, true)
    b.SetOn(true)
    T.ok(b.active, "SetOn keeps it lit")
    b.SetOn(false)
    b:Hide()

    local secure = CreateFrame("Button", nil, UIParent)
    S.Dress(secure)
    T.ok(secure.dressed and secure.label ~= nil, "a secure button dressed through W.DressButton")
    secure:Hide()
end)

T.test("without Daylight UI the buttons keep the same calls: trace on hover, sound, SetOff", function()
    local b = S.Button(UIParent, 80)
    T.ok(not b.dressed and b.trace ~= nil, "the plain look")
    b:GetScript("OnEnter")(b)
    T.eq(b.glow, 1, "hover lights the trace")
    b:GetScript("OnLeave")(b)
    T.eq(b.glow, 0)
    S.SetEnabled(b, false)
    T.ok(b.off and not b:IsEnabled())
    b:Hide()
end)

T.test("the window's buttons all answer the same calls", function()
    local ui = shutTailoring()
    local d = ui.details
    local list = { d.craftOne, d.craftAvail, d.craftAll, W.switchButton, W.pickButton,
                   CP.Crafting.strip and CP.Crafting.strip.stop, CP.ShopTab and CP.ShopTab.ui and CP.ShopTab.ui.scan }
    for i, b in pairs(list) do
        T.ok(type(b.SetOff) == "function" and type(b.SetOn) == "function" and b.label ~= nil, "button " .. i)
    end
end)

-- Top accent line ---------------------------------------------------------------------------

T.test("the top accent line is Daylight UI's profession window's: 2 px, 6 px in, 2 px down, at 70%", function()
    for _, frame in ipairs({ P.frame, CP.GatherPanel.shell }) do
        local line = frame.__line
        T.ok(line ~= nil)
        T.eq(line:GetHeight(), S.TOP_LINE.height)
        local p1 = { line:GetPoint(1) }
        local p2 = { line:GetPoint(2) }
        T.eq(p1[1], "TOPLEFT")
        T.eq(p1[4], 6)
        T.eq(p1[5], -2)
        T.eq(p2[1], "TOPRIGHT")
        T.eq(p2[4], -6)
    end
    DaylightWorld.begin({ plugin = true })
    S.PaintTopLine(P.frame.__line)
    T.eq(DaylightWorld.state.accents[P.frame.__line], 0.7, "painted by Daylight UI's PaintAccent at 0.7")
end)

-- Gathering window drag ------------------------------------------------------------------------

T.test("dragging the gathering panel moves the window as the title bar does, and the lock holds it", function()
    shutTailoring()
    W.Update()
    local sheet = CP.GatherPanel.sheet
    local function drag()
        sheet:GetScript("OnDragStart")(sheet)
        sheet:GetScript("OnDragStop")(sheet)
    end
    CP.db.windowPoint = nil
    drag()
    T.ok(CP.db.windowPoint ~= nil, "saved like a title-bar drag")
    CP.db.windowLocked = true
    CP.db.windowPoint = nil
    drag()
    T.eq(CP.db.windowPoint, nil, "locked: no drag")
end)
