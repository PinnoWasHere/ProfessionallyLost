-- Follow-ups to the profession ranks: a craft step past the skill cap offers no craft and
-- ProfLost Buy buys nothing for it, each saying why; the gathering panel's Next up names the
-- rank to train; the All card and the launcher tooltip carry the level warning.

local CP = ProfLost
local G, GT, B = CP.Guide, CP.GuideTab, CP.Buying
local LW = 165
local CAP_TEXT = "Skill capped at 150. Train Expert Leatherworking first."
local LEVEL_TEXT = "Expert Leatherworking needs level 20 (you're 18)"

-- The guide window on Leatherworking at `skill` / `max`, its profession window open.
-- `stocked`: every guide recipe known and 200 of each material in the bags, so only the
-- cap can grey a craft button.
local function open(skill, max, level, stocked)
    MapWorld.begin({ zone = 1411, level = level or 40, side = "Horde" })
    local prof, bags = { rank = skill, max = max }, {}
    if stocked then
        prof.known = {}
        for id, r in pairs(CP.Guides[LW].recipes) do
            prof.known[#prof.known + 1] = id
            for _, pair in ipairs(r.reagents or {}) do bags[pair[1]] = 200 end
        end
    end
    CraftWorld.begin({ professions = { [LW] = prof }, bags = bags })
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.Open(LW)
    T.advance(0.5)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    return GT.ui.rows, GT.ui.details
end

local function firstRow(rows, test)
    for _, row in ipairs(rows) do
        if test(row) then return row end
    end
end

local function craftRow(row) return row.spell and row.recipe and not (row.rank or row.train or row.side) end

local function pickAndShow(row)
    GT.Pick(row)
    return GT.ui.details
end

-- 1. Craft buttons past the cap -----------------------------------------------------------

T.test("Guide.PastCap names the rank a step at or past the cap waits on", function()
    local guide = CP.Guides[LW]
    T.eq(G.PastCap(guide, 150, 140, 150).name, "Expert Leatherworking", "a step from the cap")
    T.eq(G.PastCap(guide, 145, 150, 150).name, "Expert Leatherworking", "the player at the cap")
    T.eq(G.PastCap(guide, 145, 140, 150), nil, "a step through the cap from below")
    T.eq(G.PastCap(guide, 160, 160, 225), nil, "trained")
    T.eq(G.CapText(G.PastCap(guide, 150, 150, 150)), CAP_TEXT)
    T.eq(G.CapText(CP.Guides[185].ranks[2]), "Skill capped at 150. Read Expert Cookbook first.", "a book")
end)

T.test("a row past the cap picked by hand greys Craft 1, Available and Craft all with the reason", function()
    local rows = open(140, 150, nil, true)
    local past = firstRow(rows, function(r) return craftRow(r) and r.from >= 150 end)
    T.ok(past ~= nil, "a step past 150 in the list")
    local d = pickAndShow(past)
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do
        T.ok(not CP.Style.IsOn(b), "off")
        T.eq(b.tip, CAP_TEXT)
    end

    -- The step up to the cap, from below it, still crafts by the usual rules.
    local through = firstRow(rows, function(r) return craftRow(r) and r.from < 150 and r.to == 150 end)
    T.ok(through ~= nil, "a step up to 150")
    d = pickAndShow(through)
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do
        T.ok(b.tip ~= CAP_TEXT, "no cap reason below the cap")
    end
    T.ok(CP.Style.IsOn(d.craftOne), "Craft 1 on: the bags hold the materials")
    CraftWorld.Close()
end)

T.test("at the cap every craft row picked by hand is greyed with the reason", function()
    local rows = open(150, 150, nil, true)
    local row = firstRow(rows, craftRow)
    T.ok(row ~= nil)
    local d = pickAndShow(row)
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do
        T.ok(not CP.Style.IsOn(b), "off")
        T.eq(b.tip, CAP_TEXT)
    end
    CraftWorld.Close()
end)

T.test("the All card for a step past the cap greys its craft buttons with the reason", function()
    open(140, 150, nil, true)
    local live = CP.Plan.Current()
    local past = {}
    for k, v in pairs(live) do past[k] = v end
    past.plan = { { spell = 3780, from = 150, to = 154, crafts = 4, cost = 0 } }
    local card = GT.Card(past)
    T.eq(card.capped, CAP_TEXT)
    T.eq(card.need, CAP_TEXT, "the need line says why")
    T.eq(card.ready, nil)
    local btn = CreateFrame("Button", nil, UIParent)
    GT.InitCard(btn, card)
    for _, b in ipairs({ btn.one, btn.avail, btn.craft }) do
        T.ok(not CP.Style.IsOn(b), "off")
        T.eq(b.tip, CAP_TEXT)
    end

    -- The same button on a card below the cap drops the reason.
    local fresh = GT.Card(live)
    T.eq(fresh.capped, nil)
    GT.InitCard(btn, fresh)
    T.ok(btn.one.tip == nil and btn.avail.tip ~= CAP_TEXT, "no stale reason")
    CraftWorld.Close()
end)

-- 2. ProfLost Buy past the cap -----------------------------------------------------------------

-- A merchant stocking every material `row` uses, behind the game's MerchantFrame.
local function merchantFor(row)
    local slots = {}
    for _, r in ipairs(row.recipe.reagents) do slots[#slots + 1] = { r[1], 10 } end
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i][1] end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        local s = slots[i]
        return s and { price = s[2], stackCount = 1, numAvailable = -1, isPurchasable = true }
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    World.patch("GetMoney", function() return 100000000 end)
    World.set(B, "open", true)
    World.set(_G, "MerchantFrame", CreateFrame("Frame", nil, UIParent))
    World.onEnd(function()
        if B.open then T.fire("MERCHANT_CLOSED") end
    end)
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
end

T.test("Buy at the cap offers nothing for the current step and its tooltip says why", function()
    local rows = open(150, 150)
    local row = firstRow(rows, craftRow)
    merchantFor(row)
    T.eq(#B.vendor.lines, 0, "no materials for a step past the cap")
    T.eq(B.Reason(), CAP_TEXT)
    local said = {}
    World.set(GameTooltip, "AddLine", function(_, text) said[#said + 1] = text end)
    B.Button():GetScript("OnEnter")(B.Button())
    T.ok(table.concat(said, "\n"):find(CAP_TEXT, 1, true) ~= nil, table.concat(said, "\n"))
    CraftWorld.Close()
end)

T.test("Buy for a row past the cap picked by hand buys nothing for it", function()
    local rows = open(140, 150)
    local past = firstRow(rows, function(r) return craftRow(r) and r.from >= 150 end)
    GT.Pick(past)
    merchantFor(past)
    T.eq(#B.vendor.lines, 0, "nothing for the row past 150")
    T.eq(B.Reason(), CAP_TEXT)
    CraftWorld.Close()
end)

T.test("Buy for a row below the cap picked by hand buys its materials", function()
    local rows = open(140, 150)
    local below = firstRow(rows, function(r) return craftRow(r) and r.from < 150 end)
    GT.Pick(below)
    merchantFor(below)
    T.ok(#B.vendor.lines > 0, "materials for the row below the cap")
    T.eq(#B.capped, 0)
    CraftWorld.Close()
end)

-- 3. Next up at the cap ---------------------------------------------------------------------

T.test("Next up at the cap reads Train Expert Leatherworking (skill capped at 150)", function()
    open(150, 150, 18)
    local live = CP.Plan.Current()
    local st = CP.Gather.NextStep(live.guide, live.prof, live.plan, live.learned)
    T.ok(st.rank ~= nil, "the rank")
    World.set(CP.charDB, "nextStep", { [LW] = st })
    World.set(CP.GatherList, "nextOpen", true)
    World.set(CP.Launcher, "GatherLines", function() return {} end)
    local lines = CP.GatherList.NextLines()
    local line
    for i, l in ipairs(lines) do
        if l.text == "Leatherworking" then line = lines[i + 1] end
    end
    T.ok(line ~= nil, "Leatherworking listed")
    T.eq(line.text, "Train Expert Leatherworking")
    T.eq(line.tip[1], "Train Expert Leatherworking (skill capped at 150)")
    T.eq(line.tip[2], LEVEL_TEXT, "the level warning under it")
    CraftWorld.Close()
end)

-- 4. The level warning on the All card and the launcher tooltip --------------------------

local function launcherLines()
    local said = {}
    local tip = {}
    function tip:AddDoubleLine(left, right) said[#said + 1] = left .. " | " .. tostring(right) end
    function tip:AddLine(text) said[#said + 1] = text end
    CP.Launcher.Steps(tip)
    return table.concat(said, "\n")
end

T.test("at the cap the All card and the launcher tooltip carry the level warning", function()
    open(150, 150, 18)
    local live = CP.Plan.Current()
    local card = GT.Card(live)
    T.eq(card.need, "Skill capped at 150. " .. LEVEL_TEXT)
    World.set(CP.charDB, "nextStep", { [LW] = CP.Gather.NextStep(live.guide, live.prof, live.plan, live.learned) })
    World.set(CP.Launcher, "GatherLines", function() return {} end)
    local text = launcherLines()
    T.ok(text:find("Train Expert Leatherworking | capped at 150", 1, true) ~= nil, text)
    T.ok(text:find(LEVEL_TEXT, 1, true) ~= nil, text)

    -- A saved rank step follows the level now, not the level it was saved at.
    MapWorld.SetLevel(20)
    T.ok(launcherLines():find("needs level", 1, true) == nil, "level 20: no warning")
    CraftWorld.Close()
end)

T.test("below the cap, past 125, the All card and the launcher tooltip carry the level warning", function()
    open(130, 150, 18)
    local live = CP.Plan.Current()
    local card = GT.Card(live)
    T.ok(card.need:find(LEVEL_TEXT, 1, true) ~= nil, card.need)
    T.eq(card.needColor, CP.Style.color.warn)
    World.set(CP.charDB, "nextStep", { [LW] = CP.Gather.NextStep(live.guide, live.prof, live.plan, live.learned) })
    World.set(CP.Launcher, "GatherLines", function() return {} end)
    T.ok(launcherLines():find(LEVEL_TEXT, 1, true) ~= nil)
    CraftWorld.Close()

    open(130, 150, 20)
    T.ok(GT.Card(CP.Plan.Current()).need:find("needs level", 1, true) == nil, "level 20: none")
    CraftWorld.Close()
end)
