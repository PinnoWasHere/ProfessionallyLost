-- A pattern held in the bags, bank or mail gets a card that says where it is, never
-- "Buy the pattern" or Go to vendor (BANKMAIL-01c). Covers the step row's card and the
-- separate pattern-stop card.

local CP = ProfLost
local W, GT, PL = CP.Window, CP.GuideTab, CP.PatternLearn
local LW = 165
local DUROTAR = 1411
local PATTERN = 2555

local function scene(skill, max)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = skill, max = max } } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "gatherHideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function()
        PL.Release()
        PL.pending = nil
        W.CancelPick()
        W.opened = false
        W.Update()
        GT.Forget()
    end)
    CraftWorld.Open(LW)
    CraftWorld.Close()
    W.Update()
    W.Pick(LW)
    CP.Panel:Refresh()
    T.advance(0.1)
end

local function refresh()
    CP.Panel:Refresh()
    T.advance(0.1)
end

-- The first unlearned step row made a vendor pattern, picked.
local function patternRow()
    for _, row in ipairs(GT.ui.rows) do
        local r = row.recipe
        if r and not row.learned and not (row.rank or row.train or row.side) then
            World.set(r, "pattern", PATTERN)
            World.set(r, "src", "vendor")
            World.set(r, "learn", 100)
            GT.Pick(row)
            T.advance(0.1)
            return row
        end
    end
end

local function noVendor(text, where)
    T.ok(not text:find("Buy the pattern", 1, true), where .. ": " .. text)
    T.ok(not text:find("Go to vendor", 1, true), where .. ": " .. text)
end

T.test("the step card names where a held pattern is", function()
    scene(100, 150)
    local row = patternRow()
    T.ok(row ~= nil, "a pattern step")
    local d = GT.ui.details
    T.ok(d.status:GetText():find("Buy the pattern", 1, true) ~= nil, "nothing held: buy it")
    CraftWorld.SetBank(PATTERN, 1)
    refresh()
    T.ok(d.status:GetText():find("In your bank", 1, true) ~= nil, d.status:GetText())
    noVendor(d.craftAll.label:GetText(), "bank button")
    CraftWorld.SetBank(PATTERN, 0)
    World.set(CP.Purchases, "InMail", function(item) return item == PATTERN and 1 or 0 end)
    refresh()
    T.ok(d.status:GetText():find("In your mail", 1, true) ~= nil, d.status:GetText())
    World.set(CP.Purchases, "InMail", function() return 0 end)
    CraftWorld.SetBag(PATTERN, 1)
    refresh()
    noVendor(d.status:GetText(), "bags status")
    T.ok(d.status:GetText():find("In your bags", 1, true) ~= nil, d.status:GetText())
    local label = d.craftAll.label:GetText()
    local gate = PL.Gate(row.recipe, W.LiveFor(LW).prof)
    T.ok(label == PL.LABEL or (gate ~= nil and label == gate.label), "bags button: " .. label)
end)

T.test("the pattern stop's card names where a held pattern is", function()
    scene(100, 150)
    local row = patternRow()
    T.ok(row ~= nil, "a pattern step")
    local stop = { skill = 100, recipes = { row.recipe }, spells = { row.spell }, fee = 0, pattern = true }
    local stopRow = { train = stop, at = 100, key = "test-pattern-stop" }
    local d = GT.ui.details
    GT.FillDetails(stopRow)
    T.ok(d.status:GetText():find("Get the pattern", 1, true) ~= nil, "nothing held: " .. d.status:GetText())
    T.eq(d.craftAll.label:GetText(), "Go to vendor", "nothing held: vendor button")
    CraftWorld.SetBank(PATTERN, 1)
    GT.FillDetails(stopRow)
    T.ok(d.status:GetText():find("In your bank", 1, true) ~= nil, d.status:GetText())
    noVendor(d.craftAll.label:GetText(), "stop button")
    CraftWorld.SetBank(PATTERN, 0)
    World.set(CP.Purchases, "InMail", function(item) return item == PATTERN and 1 or 0 end)
    GT.FillDetails(stopRow)
    T.ok(d.status:GetText():find("In your mail", 1, true) ~= nil, d.status:GetText())
    World.set(CP.Purchases, "InMail", function() return 0 end)
end)

-- Owner report, 2026-11-25: a pattern step's row said only "pattern", so the player couldn't
-- tell whether they had it. The row's info column says where it is, or to buy it.
T.test("a pattern step's row says whether the pattern is held", function()
    scene(100, 150)
    local row = patternRow()
    T.ok(row ~= nil, "a pattern step")
    local function info()
        refresh()
        for _, r in ipairs(GT.ui.rows) do
            if r.key == row.key then return select(3, GT.RowTexts(r)) end
        end
    end
    T.eq(info(), GT.PATTERN_WORDS.buy, "nothing held")
    CraftWorld.SetBank(PATTERN, 1)
    T.eq(info(), GT.PATTERN_WORDS.bank, "in the bank")
    CraftWorld.SetBank(PATTERN, 0)
    CraftWorld.SetBag(PATTERN, 1)
    T.eq(info(), GT.PATTERN_WORDS.bags, "in the bags")
    CraftWorld.SetBag(PATTERN, 0)
    World.set(row.recipe, "src", "pattern")
    T.eq(info(), GT.PATTERN_WORDS.drop, "a world drop not held")
end)
