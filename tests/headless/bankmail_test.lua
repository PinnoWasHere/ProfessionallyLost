-- Bank and mail count wherever the guide asks what the player holds (BANKMAIL-01): the step
-- card's counts and buy tag, a pattern held in the bank or mail, the disenchant credit for
-- Enchanting, and the item tooltip. The Shop tab already counts all three.

local CP = ProfLost
local W, GT, PL = CP.Window, CP.GuideTab, CP.PatternLearn
local LW, TAILOR, ENCHANTING = 165, 197, 333
local DUROTAR = 1411
local LIGHT_LEATHER, COARSE_THREAD, STRANGE_DUST = 2318, 2320, 10940
local PATTERN = 2555

-- `line` at `skill` (cap `max`), its window opened once and shut, the guide on One mode and
-- picked.
local function scene(line, skill, max)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [line] = { rank = skill, max = max } } })
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
    CraftWorld.Open(line)
    CraftWorld.Close()
    W.Update()
    W.Pick(line)
    CP.Panel:Refresh()
    T.advance(0.1)
end

local function rowUsing(item)
    for _, row in ipairs(GT.ui.rows) do
        if row.recipe and row.learned and row.spell and not (row.rank or row.train or row.side) then
            for _, r in ipairs(row.recipe.reagents or {}) do
                if r[1] == item then return row end
            end
        end
    end
end

local function pick(row)
    GT.Pick(row)
    T.advance(0.1)
end

-- The card's material line for `item`: { count, tag }.
local function line(item)
    for _, l in ipairs(GT.ui.details.rows) do
        if l:IsShown() and l.itemID == item then return { l.count:GetText(), l.tag:GetText() } end
    end
end

T.test("items 2 and 13: the step card counts the bank and buys only what it lacks", function()
    scene(LW, 60, 150)
    CraftWorld.SetBank(LIGHT_LEATHER, 60)
    CraftWorld.SetBank(COARSE_THREAD, 40)
    local row = rowUsing(COARSE_THREAD)
    T.ok(row ~= nil, "a step that uses thread and leather")
    pick(row)
    local crafts = math.floor(row.crafts + 0.5)
    local thread = line(COARSE_THREAD)
    T.eq(thread[1], ("40 / %d"):format(crafts * 2), "thread: the bank's 40 counted")
    T.eq(thread[2], ("buy %d"):format(crafts * 2 - 40), "buy only the shortfall")
    local leather = line(LIGHT_LEATHER)
    T.eq(leather[1]:match("^%d+"), "60", "leather: the bank's 60 counted")
    T.ok(leather[2]:find("bank", 1, true) ~= nil, "a bank hint on gathered materials: " .. tostring(leather[2]))
end)

T.test("item 2: thread in the bank covers a Tailoring step's buy tag", function()
    scene(TAILOR, 40, 75)
    CraftWorld.SetBank(COARSE_THREAD, 40)
    local row = rowUsing(COARSE_THREAD)
    T.ok(row ~= nil, "a thread step")
    pick(row)
    local thread = line(COARSE_THREAD)
    T.ok(thread[1]:find("^40 /") ~= nil, "bank counted: " .. tostring(thread[1]))
    T.ok(thread[2] ~= "buy " .. math.floor(row.crafts + 0.5), "not told to buy it all again: " .. tostring(thread[2]))
end)

-- The first unlearned step with its recipe made a vendor pattern, picked.
local function patternRow()
    for _, row in ipairs(GT.ui.rows) do
        local r = row.recipe
        if r and not row.learned and not (row.rank or row.train or row.side) then
            World.set(r, "pattern", PATTERN)
            World.set(r, "src", "vendor")
            World.set(r, "learn", 100)
            pick(row)
            return row
        end
    end
end

T.test("item 12: a pattern in the bank or mail is fetched, not bought again", function()
    scene(LW, 100, 150)
    local row = patternRow()
    T.ok(row ~= nil, "a pattern step")
    local b = GT.ui.details.craftAll
    T.eq(b.label:GetText(), "Go to vendor", "nothing held: go to the vendor")
    CraftWorld.SetBank(PATTERN, 1)
    CP.Panel:Refresh()
    T.advance(0.1)
    T.eq(b.label:GetText(), GT.FETCH_LABEL, "in the bank")
    T.ok(not GT.ui.details.status:GetText():find("Buy the pattern", 1, true), GT.ui.details.status:GetText())
    CraftWorld.SetBank(PATTERN, 0)
    World.set(CP.Purchases, "InMail", function(item) return item == PATTERN and 1 or 0 end)
    CP.Panel:Refresh()
    T.advance(0.1)
    T.eq(b.label:GetText(), GT.FETCH_LABEL, "in the mail")
end)

T.test("item 12: the All-mode card offers Learn pattern for a pattern in the bags, and Fetch from the bank", function()
    scene(LW, 100, 150)
    local row = patternRow()
    T.ok(row ~= nil, "a pattern step")
    local live = W.LiveFor(LW)
    -- The card's next step is that unlearned recipe.
    World.set(CP.Gather, "NextStep", function()
        return { name = row.recipe.name, from = row.from, to = row.to, spell = row.spell, learned = false, short = 0 }
    end)
    local card = GT.Card(live)
    T.ok(card.recipe ~= nil, "the card's step is an unlearned recipe")
    CraftWorld.SetBank(PATTERN, 1)
    card = GT.Card(live)
    T.ok(card.owned, "owned")
    T.eq((GT.CardLabels(card)).craft, GT.FETCH_LABEL, "bank")
    CraftWorld.SetBank(PATTERN, 0)
    CraftWorld.SetBag(PATTERN, 1)
    card = GT.Card(live)
    local label = (GT.CardLabels(card)).craft
    T.ok(label == PL.LABEL or card.gate ~= nil and label == card.gate.label, "bags: " .. tostring(label))
    T.ok(card.inBags, "in the bags")
end)

T.test("item 3: Enchanting's needs and the Disenchant note net out what the bank holds", function()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 53, max = 75 }, [TAILOR] = { rank = 66, max = 150 } } })
    World.set(CP.db, "collect", true)
    CraftWorld.Open(ENCHANTING)
    T.advance(0.5)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(0.5)
    local empty, sigEmpty = CP.Shared.EnchantingNeeds()
    T.ok(empty and (empty[STRANGE_DUST] or 0) > 0, "Enchanting needs dust with an empty bank")
    CraftWorld.SetBank(STRANGE_DUST, 5000)
    local full, sigFull = CP.Shared.EnchantingNeeds()
    T.ok(not (full and (full[STRANGE_DUST] or 0) > 0), "a bank holding all the dust leaves none owed")
    T.ok(sigEmpty ~= sigFull, "the signature moves, so plans solve again")
    -- The card's note reads the same net.
    World.set(CP.charDB, "gatherNeeds", { [ENCHANTING] = { [STRANGE_DUST] = 333 } })
    local recipe
    for _, r in pairs(CP.Guides[TAILOR].recipes) do
        for _, y in ipairs(CP.Shared.DEYield(r)) do
            if y.item == STRANGE_DUST then recipe = r end
        end
    end
    T.ok(recipe ~= nil, "a Tailoring recipe that disenchants into dust")
    World.set(GT.ui, "guide", CP.Guides[TAILOR])
    T.eq(GT.DEBest({ recipe = recipe }), nil, "no Disenchant note while the bank holds it")
    CraftWorld.SetBank(STRANGE_DUST, 0)
    T.ok(GT.DEBest({ recipe = recipe }) ~= nil, "the note stands with an empty bank")
end)

T.test("item 30: the item tooltip counts mail and pending purchases", function()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    World.set(CP.charDB, "gatherNeeds", { [LW] = { [LIGHT_LEATHER] = 20 } })
    World.set(CP.charDB, "mail", { [LIGHT_LEATHER] = 20 })
    World.set(CP.charDB, "bought", {})
    local lines = CP.ItemTooltip.Lines(LIGHT_LEATHER)
    T.eq(lines[#lines][1], "Have 20 · enough", "mail covers the need")
    World.set(CP.charDB, "mail", {})
    World.set(CP.charDB, "bought", { [LIGHT_LEATHER] = 12 })
    lines = CP.ItemTooltip.Lines(LIGHT_LEATHER)
    T.ok(lines[2][1]:find("short x8", 1, true) ~= nil, lines[2][1])
end)

T.test("the step card and Plan.Held count mail like the Shop", function()
    scene(LW, 60, 150)
    World.set(CP.charDB, "bought", {})
    World.set(CP.charDB, "mail", {})
    CraftWorld.SetBag(COARSE_THREAD, 4)
    local row = rowUsing(COARSE_THREAD)
    T.ok(row ~= nil, "a step that uses thread")
    pick(row)
    local crafts = math.floor(row.crafts + 0.5)
    T.eq(line(COARSE_THREAD)[1], ("4 / %d"):format(crafts * 2), "thread in the bags only")

    -- Sixteen mailed from an alt: the card reads what the Shop reads.
    World.set(CP.charDB, "mail", { [COARSE_THREAD] = 16 })
    CP.Panel:Refresh()
    T.advance(0.1)
    pick(row)
    T.eq(CP.Purchases.Have(COARSE_THREAD), 20, "Have: bags plus mail")
    local thread = line(COARSE_THREAD)
    T.eq(thread[1], ("20 / %d"):format(crafts * 2), "the card counts the mail too")
    T.ok(thread[2] ~= "buy " .. (crafts * 2 - 4), "not told to buy what the mail covers: " .. tostring(thread[2]))

    -- Mail is not bank stock: the bank tag stays out and the mail is named.
    CraftWorld.SetBag(LIGHT_LEATHER, 0)
    World.set(CP.charDB, "mail", { [LIGHT_LEATHER] = 7 })
    CP.Panel:Refresh()
    T.advance(0.1)
    pick(row)
    local leather = line(LIGHT_LEATHER)
    T.eq(leather[1]:match("^%d+"), "7", "leather: the mail's 7 counted")
    T.ok(leather[2]:find("bank", 1, true) == nil, "mail is not called bank: " .. tostring(leather[2]))
    T.eq(leather[2], GT.MAIL_TAG:format(7), "the card names the mail")

    -- The plan's held stock counts it as well.
    local guide = CP.Guides[LW]
    local item = next(guide.craftOnly or {}) or next(guide.prep or {})
    T.ok(item ~= nil, "the guide has a craft-only or prep item")
    World.set(CP.charDB, "mail", { [item] = 5 })
    T.eq(CP.Plan.Held(guide)[item], 5, "Plan.Held counts the mailed item")
    local key = CP.Plan.HeldKey(guide, true)
    World.set(CP.charDB, "mail", { [item] = 9 })
    T.ok(CP.Plan.HeldKey(guide, true) ~= key, "the held key moves with the mail, so the plan solves again")
end)
