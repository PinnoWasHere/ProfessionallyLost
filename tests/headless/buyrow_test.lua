-- ProfLost Buy follows the selected guide row: its materials for its remaining crafts, less
-- what is held, and never the patterns, which get their own confirmation afterwards.

local CP = ProfLost
local W, B, GT = CP.Window, CP.Buying, CP.GuideTab
local LW, TAILOR = 165, 197
local THREAD, SALT, HEAVY_HIDE_SPELL = 2321, 4289, 3818
local ARMOR_SPELL, ARMOR_PATTERN = 4096, 13287   -- Raptor Hide Harness, a vendor pattern learnable at 140

local bought

local function shut(skill)
    MapWorld.begin({ zone = 1411, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = skill or 100, [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
        GT.Forget()
    end)
    CraftWorld.Open(LW)
    CraftWorld.Close()
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(LW)
    GT.Forget()
end

-- A merchant stocking `slots` ({ id, price }) behind the game's MerchantFrame.
local function merchant(slots)
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i][1] end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        local s = slots[i]
        return s and { price = s[2], stackCount = 1, numAvailable = -1, isPurchasable = true }
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    World.patch("GetMoney", function() return 100000000 end)
    bought = {}
    World.patch("BuyMerchantItem", function(i, n) bought[#bought + 1] = { i, n } end)
    World.set(B, "open", true)
    World.set(_G, "MerchantFrame", CreateFrame("Frame", nil, UIParent))
    World.onEnd(function()
        if B.open then T.fire("MERCHANT_CLOSED") end
    end)
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
end

local function click(b) b:GetScript("OnClick")(b) end

local function rows() return GT.RowsOf(W.LiveFor(LW)) end  -- the open window's plan, else the shut one

local function mainUsing(item)
    for _, row in ipairs(rows()) do
        if not row.side then
            for _, r in ipairs(row.recipe and row.spell and row.recipe.reagents or {}) do
                if r[1] == item then return row end
            end
        end
    end
end

-- Gives the first main step a side craft, Cured Heavy Hide for `crafts`; returns its row.
local function addSide(crafts)
    World.set(CP.Plan, "Sides", function(guide, steps)
        for i, st in ipairs(steps) do
            if st.spell then
                return { [i] = { spell = HEAVY_HIDE_SPELL, recipe = guide.recipes[HEAVY_HIDE_SPELL], learned = true, crafts = crafts } }
            end
        end
        return {}
    end)
    CP.Plan.Invalidate()
    CraftWorld.Open(LW)   -- only an open profession's plan carries side crafts
    T.advance(0.3)
    World.onEnd(function() CraftWorld.Close() end)
    for _, row in ipairs(rows()) do
        if row.side then return row end
    end
end

local function lineFor(item)
    for _, l in ipairs(B.vendor.lines) do
        if l.itemID == item then return l end
    end
end

T.test("the picked Cured Heavy Hide row at a Salt vendor: Salt for its 3 crafts, nothing else", function()
    shut(130)
    local side = addSide(3)
    GT.Pick(side)
    merchant({ { SALT, 50 }, { THREAD, 100 } })
    T.eq(#B.vendor.lines, 1, "only the row's own material")
    T.eq(B.vendor.lines[1].itemID, SALT)
    T.eq(B.vendor.lines[1].count, 9, "3 crafts at 3 Salt each")
    T.eq(lineFor(THREAD), nil, "no Fine Thread: the row doesn't use it")
    CraftWorld.SetBag(SALT, 2)
    T.advance(B.HELD_EVERY + B.CHECK_EVERY * 2)
    T.eq(B.vendor.lines[1].count, 7, "less the 2 held")
end)

T.test("a picked main step offers its own Fine Thread, not the whole guide's", function()
    shut(100)
    local row = mainUsing(THREAD)
    local per
    for _, r in ipairs(row.recipe.reagents) do
        if r[1] == THREAD then per = r[2] end
    end
    GT.Pick(row)
    merchant({ { THREAD, 100 } })
    T.eq(#B.vendor.lines, 1)
    T.eq(B.vendor.lines[1].count, per * row.crafts)
end)

T.test("picking another row while the merchant is open changes the offer", function()
    shut(130)
    local side = addSide(3)
    GT.Pick(mainUsing(THREAD))
    merchant({ { SALT, 50 }, { THREAD, 100 } })
    T.ok(lineFor(THREAD) ~= nil and lineFor(SALT) == nil, "Fine Thread for the main step")
    GT.Pick(side)
    T.advance(B.CHECK_EVERY * 2)
    T.ok(lineFor(SALT) ~= nil and lineFor(THREAD) == nil, "Salt once the side row is picked")
    T.eq(lineFor(SALT).count, 9)
    GT.Pick(mainUsing(THREAD))
    T.advance(B.CHECK_EVERY * 2)
    T.ok(lineFor(THREAD) ~= nil and lineFor(SALT) == nil, "and back")
end)

T.test("nothing picked: the current step; held enough: nothing to buy, with the reason", function()
    shut(100)
    local cur
    for _, row in ipairs(rows()) do
        if row.recipe and row.spell and not row.side then cur = row break end
    end
    merchant({ { THREAD, 100 } })
    local per
    for _, r in ipairs(cur.recipe.reagents) do
        if r[1] == THREAD then per = r[2] end
    end
    T.eq(lineFor(THREAD).count, per * cur.crafts, "the current step's thread")
    CraftWorld.SetBag(THREAD, per * cur.crafts + 5)
    T.fire("BAG_UPDATE_DELAYED")
    T.advance(B.CHECK_EVERY * 2)
    T.eq(#B.vendor.lines, 0)
    T.ok(B.Reason():find("You hold all this vendor sells", 1, true) ~= nil, tostring(B.Reason()))
end)

T.test("All mode with no pick takes each guided profession's current step", function()
    shut(100)
    World.set(CP.charDB, "guideMode", "all")
    merchant({ { THREAD, 100 } })
    T.ok(B.guided >= 2, "both professions are targets")
    T.ok(lineFor(THREAD) ~= nil, "the Leatherworking step's thread")
end)

T.test("the trace names the selected row and its needs", function()
    shut(130)
    GT.Pick(addSide(3))
    World.set(CP.trace, "buy", true)
    World.onEnd(function() World.set(CP.trace, "buy", nil) end)
    local from = #T.prints()
    merchant({ { SALT, 50 } })
    local text = table.concat(T.prints(), "\n", from + 1)
    T.ok(text:find("selected", 1, true) ~= nil and text:find("or Cured Heavy Hide (3 crafts)", 1, true) ~= nil, text)
    T.ok(text:find("need item 4289: need 9, have 0, buy 9", 1, true) ~= nil, text)
end)

-- Patterns ---------------------------------------------------------------------------------

local function armorRow()
    for _, row in ipairs(rows()) do
        if row.spell == ARMOR_SPELL then return row end
    end
end

local function patternLine()
    for _, l in ipairs(B.vendor.patterns) do
        if l.itemID == ARMOR_PATTERN then return l end
    end
end

T.test("materials first, then a second confirmation with the patterns and the skill each needs", function()
    shut(100)
    GT.Pick(mainUsing(THREAD))
    merchant({ { THREAD, 100 }, { ARMOR_PATTERN, 5000 } })
    local pat = patternLine()
    T.ok(pat ~= nil, "a pattern the player can't learn yet is offered")
    T.eq(pat.skill, 140)
    T.eq(lineFor(ARMOR_PATTERN), nil, "never among the materials")
    local b = B.Button()
    T.ok(CP.Style.IsOn(b), "on")
    b:GetScript("OnEnter")(b)
    click(b)
    T.ok(B.popup:IsShown() and B.popup.kind == "materials", "the materials first")
    T.ok(B.popup.lines[1]:GetText():find(ARMOR_PATTERN, 1, true) == nil)
    click(B.popup.all)
    T.advance(B.STEP * 10)
    for _, c in ipairs(bought) do T.eq(c[1], 1, "only thread so far") end
    T.ok(B.popup:IsShown() and B.popup.kind == "patterns", "then the patterns")
    T.ok(B.popup.lines[1]:GetText():find("learnable at 140", 1, true) ~= nil, B.popup.lines[1]:GetText())
    local took = #bought
    click(B.popup.all)
    T.eq(#bought, took + 1, "the pattern bought on its own click")
    T.eq(bought[#bought][1], 2)
end)

T.test("Skip on the pattern prompt buys nothing", function()
    shut(100)
    GT.Pick(mainUsing(THREAD))
    merchant({ { THREAD, 100 }, { ARMOR_PATTERN, 5000 } })
    click(B.Button())
    click(B.popup.all)
    T.advance(B.STEP * 10)
    local took = #bought
    T.eq(B.popup.kind, "patterns")
    T.eq(B.popup.cancel.label:GetText(), "Skip")
    click(B.popup.cancel)
    T.ok(not B.popup:IsShown())
    T.advance(B.STEP * 5)
    T.eq(#bought, took, "no pattern bought")
end)

T.test("no materials to buy: ProfLost Buy goes straight to the patterns", function()
    shut(100)
    GT.Pick(mainUsing(THREAD))
    merchant({ { ARMOR_PATTERN, 5000 } })
    T.eq(#B.vendor.lines, 0)
    local b = B.Button()
    T.ok(CP.Style.IsOn(b), "on with patterns alone: " .. tostring(B.Reason()))
    click(b)
    T.ok(B.popup:IsShown() and B.popup.kind == "patterns", "the pattern confirmation")
    T.ok(B.popup.lines[1]:GetText():find("learnable at 140", 1, true) ~= nil)
    click(B.popup.all)
    T.eq(#bought, 1)
end)

T.test("a learnable pattern says so", function()
    shut(140)
    merchant({ { ARMOR_PATTERN, 5000 } })
    T.eq(B.PatternText(patternLine()):find("learnable now", 1, true) ~= nil, true)
end)

T.test("a pattern for a recipe already known is skipped, window closed (saved list) or open", function()
    shut(100)
    merchant({ { ARMOR_PATTERN, 5000 } })
    T.ok(patternLine() ~= nil, "offered while unknown")
    T.fire("MERCHANT_CLOSED")
    CP.charDB.learned = CP.charDB.learned or {}
    World.set(CP.charDB.learned, LW, { ARMOR_SPELL })
    merchant({ { ARMOR_PATTERN, 5000 } })
    T.eq(patternLine(), nil, "known from the saved list with the window closed")
    T.fire("MERCHANT_CLOSED")
    World.set(CP.charDB.learned, LW, {})
    CraftWorld.Open(LW)
    CraftWorld.Learn(LW, ARMOR_SPELL)
    merchant({ { ARMOR_PATTERN, 5000 } })
    T.eq(patternLine(), nil, "known from the open window's list")
    CraftWorld.Close()
end)

T.test("a pattern in the bags is skipped", function()
    shut(100)
    CraftWorld.SetBag(ARMOR_PATTERN, 1)
    merchant({ { ARMOR_PATTERN, 5000 } })
    T.eq(patternLine(), nil)
end)

T.test("a pattern in the bank or the mail is skipped", function()
    shut(100)
    CraftWorld.SetBank(ARMOR_PATTERN, 1)
    merchant({ { ARMOR_PATTERN, 5000 } })
    T.eq(patternLine(), nil, "banked")
    T.fire("MERCHANT_CLOSED")
    CraftWorld.SetBank(ARMOR_PATTERN, 0)
    World.set(CP.charDB, "mail", { [ARMOR_PATTERN] = 1 })
    merchant({ { ARMOR_PATTERN, 5000 } })
    T.eq(patternLine(), nil, "in the mail")
end)
