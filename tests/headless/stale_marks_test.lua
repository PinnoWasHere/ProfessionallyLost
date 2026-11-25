-- Review items 39 and 40: Daylight UI's recipe-line step marks
-- follow the guide in every mode and tab, and the All-mode Craft all tooltip shows the current
-- material counts.

local CP = ProfLost
local W, P = CP.Window, CP.Panel
local LW = 165
local DUROTAR = 1411
local THREAD = 2320

local function scene(rank, mode)
    MapWorld.begin({ zone = DUROTAR, level = 40, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = rank, max = 225 } } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowPoint", CP.db.windowPoint)
    World.set(CP.charDB, "guideMode", mode or "one")
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
        T.advance(0.1)
    end)
    W.Update()
    T.advance(0.1)
    CraftWorld.Open(LW)
    T.advance(0.3)
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function current(marks)
    for id, m in pairs(marks) do if m == "current" then return id end end
end

-- The marks One mode would draw for the state now: the control the other modes must match.
local function oneModeMarks()
    local keep = CP.charDB.guideMode
    W.SetMode("one")
    P:Refresh()
    T.advance(0.1)
    local marks = copy(CP.CraftRows.Marks())
    W.SetMode(keep)
    return marks
end

local function sameMarks(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

local function show(label, m)
    local parts = {}
    for id, v in pairs(m) do parts[#parts + 1] = id .. "=" .. v end
    table.sort(parts)
    return label .. " {" .. table.concat(parts, ",") .. "}"
end

local function pastTheStep(from, to)
    CraftWorld.SetSkill(LW, to)
    T.fire("ProfLost_SKILLS")
    T.advance(0.5)
    return from
end

T.test("item 39: All mode moves the recipe-line marks when the step moves on", function()
    scene(136, "one")
    P.tabs.guide.button:GetScript("OnClick")()
    T.advance(0.2)
    local before = copy(CP.CraftRows.Marks())
    T.ok(current(before) ~= nil, "One mode marks a current step")
    W.SetMode("all")
    P:Refresh()
    T.advance(0.2)
    pastTheStep(136, 156)
    local after = copy(CP.CraftRows.Marks())
    local want = oneModeMarks()
    T.ok(after[current(before)] ~= "current", "the finished step is not current any more: " .. show("after", after))
    T.ok(sameMarks(after, want), show("All mode", after) .. " matches " .. show("One mode", want))
end)

T.test("item 39: the marks follow while another tab is current", function()
    scene(136, "one")
    P.tabs.guide.button:GetScript("OnClick")()
    T.advance(0.2)
    local before = copy(CP.CraftRows.Marks())
    T.ok(current(before) ~= nil, "a current step")
    World.set(CP.db, "collect", false)
    P.tabs.shop.button:GetScript("OnClick")()
    T.advance(0.2)
    T.ok(P.current ~= "guide", "another tab is current")
    pastTheStep(136, 156)
    local after = copy(CP.CraftRows.Marks())
    local want = oneModeMarks()
    T.ok(after[current(before)] ~= "current", show("after", after))
    T.ok(sameMarks(after, want), show("other tab", after) .. " matches " .. show("One mode", want))
end)

T.test("item 39: the marks follow while the guide window is shut", function()
    scene(136, "one")
    P.tabs.guide.button:GetScript("OnClick")()
    T.advance(0.2)
    local before = copy(CP.CraftRows.Marks())
    T.ok(current(before) ~= nil, "a current step")
    P.frame:Hide()
    T.ok(not P.frame:IsShown(), "the window is shut")
    pastTheStep(136, 156)
    local after = copy(CP.CraftRows.Marks())
    P.frame:Show()
    T.advance(0.5)
    T.ok(after[current(before)] ~= "current", "shut window: " .. show("after", after))
end)

T.test("item 40: the All-mode Craft all tooltip shows the current material counts", function()
    scene(60, "all")
    P.tabs.guide.button:GetScript("OnClick")()
    P:Refresh()
    T.advance(0.2)
    local ui = CP.GuideTab.ui
    local card = ui.cardList[1]
    T.ok(card and card.reagents, "a card with reagents")
    local function tipOf(c)
        local text
        for _, r in ipairs(c.reagents) do
            if r.itemID == THREAD then text = (r.need or 0) * (c.crafts or 1) - (r.have or 0) end
        end
        return text
    end
    local short = tipOf(card)
    T.ok(short and short > 0, "thread is short")
    CraftWorld.SetBag(THREAD, 3)
    T.advance(0.5)
    local fresh = ui.cardList[1]
    T.eq(tipOf(fresh), short - 3, "the list holds the new count")
    T.ok(fresh ~= card, "the card list was rebuilt, not kept")
end)
