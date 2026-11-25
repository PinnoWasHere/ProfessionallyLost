-- Work per craft of a batch with the profession window open, against the events the
-- client fires per craft (craftworld's Cast): no recipe re-read and no solve for a craft
-- that only moves counts, one list read and one solve for a craft with a skill-up, no
-- extra work from an open merchant, and a Stop overlay and strip text that change only
-- when what they show changes. The harness stubs collectgarbage to 0, so these count calls.

local CP = ProfLost
local LW = 165
local DUROTAR = 1411
local KIT = 2152              -- Light Armor Kit: 1 Light Leather; orange to 30, green from 45 to 60
local LIGHT_LEATHER = 2318
local COARSE_THREAD, FINE_THREAD = 2320, 2321
local BATCH = 10
local CAST = 3                -- seconds per craft, so the strip's OnUpdate runs 30 frames each

local function counter()
    local c = { infos = 0, lists = 0, plans = 0, solves = 0, wants = 0, slots = 0, texts = 0, formats = 0 }
    local solve, plan, wants = CP.Plan.Solve, CP.Solver.Plan, CP.Buying.Wants
    World.set(CP.Plan, "Solve", function(...)
        c.solves = c.solves + 1
        return solve(...)
    end)
    World.set(CP.Solver, "Plan", function(...)
        c.plans = c.plans + 1
        return plan(...)
    end)
    World.set(CP.Buying, "Wants", function(...)
        c.wants = c.wants + 1
        return wants(...)
    end)
    -- ProfLost's own reads only: Daylight UI's window re-reads its list on every
    -- TRADE_SKILL_LIST_UPDATE, and the profiler books that to Daylight UI.
    local TS = C_TradeSkillUI
    local all, info, recipes = TS.GetAllRecipeIDs, TS.GetRecipeInfo, CP.Professions.Recipes
    local ours = false
    World.set(CP.Professions, "Recipes", function(...)
        local was = ours
        ours = true
        local out = recipes(...)
        ours = was
        return out
    end)
    World.set(TS, "GetAllRecipeIDs", function(...)
        if ours then c.lists = c.lists + 1 end
        return all(...)
    end)
    World.set(TS, "GetRecipeInfo", function(...)
        if ours then c.infos = c.infos + 1 end
        return info(...)
    end)
    local slot = C_MerchantFrame.GetItemInfo
    World.set(C_MerchantFrame, "GetItemInfo", function(...)
        c.slots = c.slots + 1
        return slot(...)
    end)
    return c
end

local function copy(c)
    local out = {}
    for k, v in pairs(c) do out[k] = v end
    return out
end

local function minus(a, b)
    local out = {}
    for k, v in pairs(a) do out[k] = v - (b[k] or 0) end
    return out
end

local function shown(d)
    return ("%d recipe reads, %d lists, %d solves, %d Solver.Plan, %d wants, %d slot reads, %d overs, %d texts"):format(
        d.infos, d.lists, d.solves, d.plans, d.wants, d.slots, d.overs or 0, d.texts)
end

-- Steps and their "or" rows, every number exact.
local function dump(live)
    local out = {}
    for i, st in ipairs(live.plan or {}) do
        local side = live.sides and live.sides[i]
        out[#out + 1] = ("%d-%d:%s:%.17g:%.17g%s"):format(st.from, st.to, tostring(st.spell), st.crafts or 0,
            st.cost or 0, side and ("|" .. tostring(side.spell) .. ":" .. tostring(side.crafts)) or "")
    end
    return table.concat(out, ";")
end

-- Strips another test file left up on UIParent (stop_test) would hold the Stop overlay.
local function hideStrays()
    for _, f in ipairs({ UIParent:GetChildren() }) do
        for _, s in ipairs({ f:GetChildren() }) do
            if s.stop and s.bar and s:IsVisible() and f ~= CP.Panel.frame then f:Hide() end
        end
    end
end

-- Leatherworking at `skill` with its window open, Daylight UI loaded, the guide showing.
local function scene(skill, bags)
    hideStrays()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    DaylightWorld.begin({})
    CraftWorld.begin({ professions = { [LW] = skill }, bags = bags })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.Open(LW)
    T.advance(2)
    T.ok(CP.Plan.Current() ~= nil, "the open profession's plan")
end

-- A merchant selling leather and thread behind the game's MerchantFrame.
local function merchant()
    local slots = { { LIGHT_LEATHER, 50 }, { COARSE_THREAD, 10 }, { FINE_THREAD, 20 } }
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i][1] end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        local s = slots[i]
        return s and { price = s[2], stackCount = 1, numAvailable = -1, isPurchasable = true }
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    World.patch("GetMoney", function() return 100000000 end)
    World.set(_G, "MerchantFrame", CreateFrame("Frame", nil, UIParent))
    World.onEnd(function()
        if CP.Buying.open then T.fire("MERCHANT_CLOSED") end
    end)
    T.fire("MERCHANT_SHOW")
    T.advance(1)
end

-- The guide's step card strip, with Stop given a place on screen (the harness lays nothing out).
local function strip(c)
    local s = CP.GuideTab.ui.details.making
    s.stop.GetLeft = function() return 100 end
    s.stop.GetBottom = function() return 50 end
    s.stop.GetWidth = function() return 72 end
    s.stop.GetHeight = function() return 22 end
    s.stop.GetEffectiveScale = function() return 1 end
    local set = s.text.SetText
    s.text.SetText = function(self, ...)
        c.texts = c.texts + 1
        return set(self, ...)
    end
    return s
end

local function overs()
    local n = 0
    for _, x in ipairs(DaylightWorld.state.casters) do n = n + (x.overs or 0) end
    return n
end

-- A step row as drawn: its three texts, the "or" mark and the name's colour.
local function drawn(row)
    local b = CreateFrame("Button", nil, UIParent)
    CP.GuideTab.PaintRow(b, row)
    local c = {}
    b.name.SetTextColor = function(_, ...) c = { ... } end
    CP.GuideTab.PaintRow(b, row)
    b:Hide()
    local range, name, info = CP.GuideTab.RowTexts(row)
    return ("%s|%s|%s|%s|%.2f,%.2f,%.2f"):format(range, name, info, row.side and "or" or "",
        c[1] or -1, c[2] or -1, c[3] or -1)
end

local function drawnRows(rows)
    local out = {}
    for i, row in ipairs(rows) do out[i] = drawn(row) end
    return table.concat(out, "\n")
end

-- The step list a solve from a list read now draws, leaving every cache as it is.
local function freshRows()
    local TS, Prof = C_TradeSkillUI, CP.Professions
    local list = {}
    for _, id in ipairs(TS.GetAllRecipeIDs()) do
        local r = TS.GetRecipeInfo(id)
        list[#list + 1] = { id = id, name = r.name, icon = r.icon, learned = r.learned == true,
                            difficulty = r.relativeDifficulty, skillUps = r.numSkillUps or 0,
                            canSkillUp = r.canSkillUp == true, craftable = TS.GetCraftableCount(id) or 0 }
    end
    return drawnRows(CP.GuideTab.RowsOf(CP.Plan.Solve(Prof.Current(), list)))
end

-- After a craft: the step list drawn is what a solve from scratch draws.
local function sameRows(label)
    if CP.Window.Mode() ~= "one" then return end
    T.eq(drawnRows(CP.GuideTab.ui.rows or {}), freshRows(), label .. ": the rows are what a fresh solve draws")
end

-- Plays a batch of `n` of `spell`: per craft, the counts it cost. `each` runs after each cast.
-- After each craft's counts are taken, the drawn rows must equal a fresh solve's.
local function batch(c, spell, n, each)
    CP.Crafting.Start(spell, n)
    T.advance(0.5)
    local s = strip(c)
    T.ok(s:IsVisible(), "the making strip shows")
    local per = {}
    for i = 1, n do
        local before = copy(c)
        before.overs = overs()
        T.ok(CraftWorld.Cast(), "cast " .. i)
        if each then each(i) end
        T.advance(CAST)
        local now = copy(c)
        now.overs = overs()
        per[i] = minus(now, before)
        sameRows("craft " .. i)
    end
    T.advance(1)
    return per
end

-- The largest of each count over the batch, and the sums.
local function worst(per)
    local top, sum = {}, {}
    for _, d in ipairs(per) do
        for k, v in pairs(d) do
            top[k] = math.max(top[k] or 0, v)
            sum[k] = (sum[k] or 0) + v
        end
    end
    return top, sum
end

local function ids()
    local n = 0
    for _ in pairs(CP.Guides[LW].recipes) do n = n + 1 end
    return n
end

-- The vendor offer as a string.
local function offer()
    local out = {}
    for _, l in ipairs(CP.Buying.vendor.lines) do out[#out + 1] = l.itemID .. "x" .. l.count end
    for _, l in ipairs(CP.Buying.vendor.patterns) do out[#out + 1] = "p" .. l.itemID end
    return table.concat(out, ",")
end

-- The offer kept through the batch is what a rebuild from scratch gives.
local function freshOffer()
    local kept = offer()
    CP.Buying.Changed()
    T.eq(kept, offer(), "the offer is what a rebuild gives")
    return kept
end

-- After a batch: the plan, the current step and every count are what a fresh read gives.
local function fresh()
    local live = CP.Plan.Current()
    local plan = dump(live)
    local counts = {}
    for _, r in ipairs(live.recipes) do counts[#counts + 1] = r.id .. "=" .. r.craftable end
    local status = CP.GuideTab.ui.details.status:GetText() or ""
    CP.Professions.DropRecipes()
    CP.Plan.Invalidate()
    CP.Panel:Refresh()
    T.advance(0.2)
    local again = CP.Plan.Current()
    local truth = {}
    for _, r in ipairs(again.recipes) do
        T.eq(r.craftable, C_TradeSkillUI.GetCraftableCount(r.id), "the game's count for " .. r.id)
        truth[#truth + 1] = r.id .. "=" .. r.craftable
    end
    T.eq(plan, dump(again), "the plan is what a fresh solve gives")
    T.eq(table.concat(counts, ","), table.concat(truth, ","), "craftable counts are the game's")
    T.eq(status, CP.GuideTab.ui.details.status:GetText() or "", "the step card says what a fresh read says")
end

T.test("a craft that only moves counts reads no recipe, solves nothing, and keeps the overlay", function()
    scene(45, { [LIGHT_LEATHER] = 20 })
    local c = counter()
    local per = batch(c, KIT, BATCH)
    local top, sum = worst(per)
    print("no skill-up, per craft (worst): " .. shown(top))
    T.eq(CraftWorld.state.profs[LW].rank, 45, "green: no skill-up")
    T.eq(top.infos, 0, "no recipe re-read (" .. shown(top) .. ")")
    T.eq(top.solves, 0, "no plan solve")
    T.eq(top.plans, 0, "no Solver.Plan")
    T.ok(sum.overs <= 2, "the Stop overlay is laid once, not per frame: " .. sum.overs .. " over the batch")
    T.ok(top.texts <= 1, "the strip's text changes once per craft at most: " .. top.texts)
    T.eq(CraftWorld.Bag(LIGHT_LEATHER), 10, "ten kits made")
    fresh()
end)

T.test("a craft with a skill-up reads the list once and solves once", function()
    scene(1, { [LIGHT_LEATHER] = 20 })
    local c = counter()
    local before = CP.Plan.Current()
    local per = batch(c, KIT, BATCH)
    local top = worst(per)
    print("skill-up, per craft (worst): " .. shown(top))
    T.eq(CraftWorld.state.profs[LW].rank, 1 + BATCH, "a point per craft")
    T.ok(top.infos <= ids(), "at most one list read per skill-up: " .. top.infos .. " reads, " .. ids() .. " recipes")
    T.eq(top.solves, 1, "one plan solve per skill-up")
    T.ok(CP.Plan.Current() ~= before, "the plan follows the skill")
    fresh()
end)

T.test("an open merchant adds no recipe read, no solve and one offer per craft at most", function()
    scene(45, { [LIGHT_LEATHER] = 20, [COARSE_THREAD] = 5 })
    merchant()
    T.ok(CP.Buying.open, "the merchant is open")
    local c = counter()
    local per = batch(c, KIT, BATCH, function() T.fire("MERCHANT_UPDATE") end)
    local top = worst(per)
    print("merchant open, per craft (worst): " .. shown(top))
    T.eq(top.infos, 0, "no recipe re-read (" .. shown(top) .. ")")
    T.eq(top.plans, 0, "no Solver.Plan")
    T.ok(top.wants <= 1, "the offer is rebuilt once per craft at most: " .. top.wants)
    freshOffer()
    fresh()
end)

T.test("an open merchant with a skill-up still solves once per craft", function()
    scene(1, { [LIGHT_LEATHER] = 20, [COARSE_THREAD] = 5 })
    merchant()
    local first = offer()
    local c = counter()
    local per = batch(c, KIT, BATCH, function() T.fire("MERCHANT_UPDATE") end)
    local top = worst(per)
    print("merchant open with skill-ups, per craft (worst): " .. shown(top))
    T.eq(top.solves, 1, "one plan solve per skill-up")
    T.ok(top.infos <= ids(), "at most one list read per skill-up: " .. top.infos)
    T.ok(top.wants <= 1, "one offer per craft: " .. top.wants)
    -- Each craft spends a leather and a point of the step, so the leather to buy holds.
    T.eq(freshOffer(), first, "the offer after the batch")
    T.ok(first ~= "", "the offer has the step's leather: " .. first)
    fresh()
end)

T.test("All mode with a shut profession too: the batch costs its plan nothing", function()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    DaylightWorld.begin({})
    CraftWorld.begin({ professions = { [LW] = 45, [197] = 60 }, bags = { [LIGHT_LEATHER] = 20 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "all")
    CraftWorld.Open(LW)
    T.advance(2)
    merchant()
    local shut = CP.Plan.Shut(197)
    T.ok(shut ~= nil, "Tailoring's shut plan")
    local c = counter()
    CP.Crafting.Start(KIT, 5)
    T.advance(0.5)
    for _ = 1, 5 do
        CraftWorld.Cast()
        T.fire("MERCHANT_UPDATE")
        T.advance(CAST)
    end
    print("All mode, merchant open, 5 crafts: " .. shown(c))
    T.eq(c.plans, 0, "no Solver.Plan")
    T.eq(c.infos, 0, "no recipe re-read")
    T.ok(c.wants <= 5, "one offer per craft at most: " .. c.wants)
    T.eq(CP.Plan.Shut(197), shut, "Tailoring's plan held")
    freshOffer()
end)

T.test("after MERCHANT_CLOSED a bag change costs Buying nothing", function()
    scene(45, { [LIGHT_LEATHER] = 20 })
    merchant()
    T.fire("MERCHANT_CLOSED")
    T.advance(1)
    local c = counter()
    CraftWorld.SetBag(COARSE_THREAD, 3)
    T.fire("MERCHANT_UPDATE")
    T.advance(2)
    T.eq(c.wants, 0, "no offer rebuilt")
    T.eq(c.slots, 0, "no merchant slot read")
end)

T.test("a recipe learned mid-batch shows up learned", function()
    scene(45, { [LIGHT_LEATHER] = 20 })
    local c = counter()
    CP.Crafting.Start(KIT, 3)
    T.advance(0.5)
    CraftWorld.Cast()
    T.advance(CAST)
    local learned
    for id in pairs(CP.Guides[LW].recipes) do
        if not CraftWorld.Known(LW, id) and not learned then learned = id end
    end
    CraftWorld.Learn(LW, learned)
    CraftWorld.Cast()
    T.advance(CAST)
    local found
    for _, r in ipairs(CP.Plan.Current().recipes) do
        if r.id == learned then found = r end
    end
    T.ok(found and found.learned, "recipe " .. tostring(learned) .. " is learned in the kept list")
    T.ok(CP.Plan.Current().learned[learned], "and in the plan")
    T.ok(c.solves >= 1, "learning re-solves")
end)

T.test("the strip's OnUpdate sets no text and formats nothing while nothing changes", function()
    scene(45, { [LIGHT_LEATHER] = 20 })
    local c = counter()
    CP.Crafting.Start(KIT, 5)
    T.advance(0.5)
    local s = strip(c)
    local update = s:GetScript("OnUpdate")
    update(s, 0.02)
    local fmt = string.format
    World.set(string, "format", function(...)
        c.formats = c.formats + 1
        return fmt(...)
    end)
    local texts, laid = c.texts, overs()
    for _ = 1, 100 do update(s, 0.02) end
    T.eq(c.formats, 0, "no string.format per frame")
    T.eq(c.texts - texts, 0, "no SetText per frame")
    T.eq(overs() - laid, 0, "no overlay re-lay per frame")
    -- Stop moves: the overlay follows.
    s.stop.GetLeft = function() return 140 end
    update(s, 0.02)
    T.eq(overs() - laid, 1, "the overlay follows Stop when it moves")
    local b = DaylightWorld.state.casters[1].button
    T.eq(b.row, s.stop)
    -- Hidden under it (combat, the mouse leaving): laid again once it may be.
    b:Hide()
    update(s, 0.02)
    T.eq(overs() - laid, 2, "laid again after the overlay hid")
    T.ok(b:IsShown())
    -- In combat nothing is laid; once it ends the hidden overlay comes back.
    World.patch("InCombatLockdown", function() return true end)
    T.fire("PLAYER_REGEN_DISABLED")
    b:Hide()
    for _ = 1, 10 do update(s, 0.02) end
    T.eq(overs() - laid, 2, "no overlay call in combat")
    World.patch("InCombatLockdown", function() return false end)
    T.fire("PLAYER_REGEN_ENABLED")
    update(s, 0.02)
    T.eq(overs() - laid, 3, "laid once after combat")
    T.ok(b:IsShown(), "over Stop again")
    -- A second strip up at once leaves the overlay where it is, no tug of war per frame.
    local other = CP.Crafting.Strip(UIParent)
    other:Show()
    World.onEnd(function() other:Hide() end)
    for _ = 1, 10 do
        other:GetScript("OnUpdate")(other, 0.02)
        update(s, 0.02)
    end
    T.eq(overs() - laid, 3, "no re-lay while the first Stop shows")
    T.eq(b.row, s.stop, "still over the first Stop")
end)

T.test("a list update re-reads the list when its ids change or a recipe had no info yet", function()
    scene(45, { [LIGHT_LEATHER] = 20 })
    local c = counter()
    local TS = C_TradeSkillUI
    local all, info = TS.GetAllRecipeIDs, TS.GetRecipeInfo
    local function has(id)
        for _, r in ipairs(CP.Professions.Recipes()) do
            if r.id == id then return true end
        end
        return false
    end

    -- The kit gives no info on the first read.
    World.set(TS, "GetRecipeInfo", function(id, ...)
        if id == KIT then return nil end
        return info(id, ...)
    end)
    CP.Professions.DropRecipes()
    T.ok(not has(KIT), "the kit is missing while it gives no info")
    World.set(TS, "GetRecipeInfo", info)
    T.fire("TRADE_SKILL_LIST_UPDATE")
    T.ok(has(KIT), "the next list update reads it")

    -- The kit drops out of the game's ids.
    local reads = c.infos
    World.set(TS, "GetAllRecipeIDs", function(...)
        local ids = all(...)
        for i, id in ipairs(ids) do
            if id == KIT then
                table.remove(ids, i)
                break
            end
        end
        return ids
    end)
    T.fire("TRADE_SKILL_LIST_UPDATE")
    T.ok(not has(KIT), "a list update with other ids reads the list again")
    T.ok(c.infos > reads, "read again")
end)
