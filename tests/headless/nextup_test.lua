-- Next up names what the current step needs, as its card does, with the step's shortfall
-- and what the plan still needs to the cap (playtester report on 1.0.0, Stormwind). A vendor
-- good counts only when it is all the step lacks (Mote of Magic, owner decision).

local CP = ProfLost
local ENCHANTING, TAILOR = 333, 197
local MOTE, DUST, LINEN, BOLT_ITEM = 247786, 10940, 2589, 2996
local INFERIOR_STAMINA, DUST_TO_MOTES = 7418, 1245320

local function itemName(id) return CP.ItemName(id) or ("item " .. id) end

-- The Next up line under `profession`, and the launcher tooltip's right text for it.
local function nextUp(profession)
    World.set(CP.GatherList, "nextOpen", true)
    World.set(CP.Launcher, "GatherLines", function() return {} end)
    local lines, line = CP.GatherList.NextLines(), nil
    for i, l in ipairs(lines) do
        if l.text == profession then line = lines[i + 1] end
    end
    local right
    local tip = {}
    function tip:AddDoubleLine(left, r) if left:find("^" .. profession) then right = r end end
    function tip:AddLine() end
    CP.Launcher.Steps(tip)
    return line, right
end

local function open(line, rank, bags)
    CraftWorld.begin({ professions = { [line] = { rank = rank, max = 75 } }, bags = bags })
    CraftWorld.Open(line)
    T.advance(1)
    local live = CP.Plan.Current()
    return live, CP.Gather.NextStep(live.guide, live.prof, live.plan, live.learned)
end

-- Enchanting at 1 in Stormwind with no motes. Forever's ItemSparse says Mote of Magic is
-- "Available from enchanting vendors." at 10 copper; the data marks it sold by the
-- Enchanting Supplies vendors (owner decision, option A). The bags hold the Runed Copper Rod
-- the enchants need, so no tool line leads the card.
local COPPER_ROD = 6218
local function stormwind(bags)
    MapWorld.begin({ zone = 1453, x = 0.6, y = 0.7, level = 10, side = "Alliance" })
    return open(ENCHANTING, 1, bags or { [COPPER_ROD] = 1 })
end

T.test("Mote of Magic is a vendor good sold by the Enchanting Supplies vendors", function()
    local guide = CP.Guides[ENCHANTING]
    local it = guide.items[MOTE]
    T.eq(it[1], 10, "10 copper")
    T.eq(it[2], true, "sold without limit")
    T.eq(it.seller, "Enchanting Supplies")
    T.ok(it.vendors and #it.vendors > 0, "its vendors")
    local names = {}
    for _, n in ipairs(it.vendors or {}) do names[#names + 1] = guide.npcs[n] and guide.npcs[n][1] or "?" end
    T.ok(table.concat(names, ","):find("Jessara Cordell", 1, true) ~= nil, table.concat(names, ","))
    T.eq(guide.prep[MOTE], nil, "never made from dust on demand")
end)

T.test("Enchanting's Next up says to buy the motes when they are all the step lacks", function()
    local live, st = stormwind()
    T.eq(st.spell, INFERIOR_STAMINA, "the current step: " .. st.name)
    local crafts = CP.Guide.Crafts(live.guide.recipes[INFERIOR_STAMINA], 1, st.to)
    T.eq(st.item, MOTE, "the step's own material")
    T.eq(st.short, crafts, "one mote a craft")
    T.eq(st.make, nil, "bought, not made from Strange Dust")
    T.eq(st.buy and st.buy.price, 10)
    local line, launcher = nextUp("Enchanting")
    T.ok(line ~= nil, "Enchanting listed")
    T.eq(line.text, ("Buy Mote of Magic x%d"):format(crafts))
    T.eq(launcher, line.text, "the launcher tooltip says the same")
    T.eq(CP.GuideTab.Card(live).need, line.text, "the All-mode card says the same")
    local tip = table.concat(line.tip, " / ")
    T.ok(tip:find("Sold by Enchanting Supplies vendors, 10c each", 1, true) ~= nil, tip)
    -- The map fixture's rectangles put her spot in Elwynn Forest, which overlaps Stormwind.
    T.ok(tip:find("Nearest: Jessara Cordell, ", 1, true) ~= nil, tip)
    CraftWorld.Close()
end)

T.test("Enchanting's step card says to buy motes at an Enchanting Supplies vendor", function()
    stormwind()
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.charDB, "guideMode", "one")
    CP.Window.Update()
    CP.Window.Pick(ENCHANTING)
    CP.Panel:Refresh()
    T.advance(0.1)
    local row
    for _, r in ipairs(CP.GuideTab.ui.rows or {}) do
        if r.spell == INFERIOR_STAMINA and not r.side then row = r end
    end
    T.ok(row ~= nil and row.learned, "the current step's row")
    CP.GuideTab.Pick(row)
    T.advance(0.1)
    local d = CP.GuideTab.ui.details
    local tag
    for _, l in ipairs(d.rows) do
        if l:IsShown() and l.itemID == MOTE then tag = l.tag:GetText() end
    end
    T.eq(tag, "buy " .. row.crafts, "the mote row says how many to buy")
    local note = d.sale:GetText() or ""
    T.ok(note:find("^Buy Mote of Magic at an Enchanting Supplies vendor: Jessara Cordell, ") ~= nil, note)
    -- Its wording depends on what is equipped, which other test files may leave.
    T.ok(note:find("\n%S") ~= nil, "the enchant's own line follows: " .. note)
    CraftWorld.Close()
end)

T.test("Buy for guide offers the step's motes at an Enchanting Supplies vendor", function()
    local live = stormwind()
    World.set(CP.charDB, "guideMode", "one")
    CP.Window.Pick(ENCHANTING)
    local crafts = CP.Guide.Crafts(live.guide.recipes[INFERIOR_STAMINA], 1, live.plan[1].to)
    VendorWorld.begin({ money = 100000 })
    VendorWorld.Open({ entry = 1318, name = "Jessara Cordell", items = { { item = 6217, price = 124 }, { item = MOTE, price = 10 } } })
    T.advance(1)
    local lines = CP.Buying.Wants()
    local mote
    for _, l in ipairs(lines) do
        if l.itemID == MOTE then mote = l end
    end
    T.ok(mote ~= nil, "Mote of Magic offered")
    T.eq(mote and mote.count, crafts, "one a craft")
    T.eq(mote and mote.cost, 10 * crafts)
    VendorWorld.Close()
    CraftWorld.Close()
end)

T.test("the Enchanting plan buys motes at 10 copper rather than making them from dust", function()
    local guide = CP.Guides[ENCHANTING]
    for _, collect in ipairs({ true, false }) do
        World.set(CP.db, "collect", collect)
        local plan = CP.Plan.Offline(guide, "motes" .. tostring(collect), 1, 300, {}).plan
        local mode = collect and "collect" or "buy"
        T.eq(plan[1].spell, INFERIOR_STAMINA, mode .. ": the first step uses motes")
        for _, st in ipairs(plan) do
            T.ok(st.spell ~= DUST_TO_MOTES, mode .. ": no Dust to Motes step")
        end
    end
end)

T.test("with Strange Dust in the bags, the motes are still bought", function()
    local _, st = stormwind({ [DUST] = 20 })
    T.eq(st.item, MOTE)
    T.ok(st.buy ~= nil, "buy, not make")
    CraftWorld.Close()
end)

T.test("Tailoring's Next up gives the step's shortfall, then what the plan needs to the cap", function()
    local live, st = open(TAILOR, 22, { [LINEN] = 10 })
    T.eq(st.item, LINEN, "the current step's cloth: " .. st.name)
    -- The step's crafts as its card counts them: the bolts later steps keep, when more.
    local keep = 0
    for i, ps in ipairs(live.plan) do
        if ps.spell == st.spell and ps.to == st.to then
            local k = CP.Guide.Keeps(live.guide, live.plan, CP.Plan.Held(live.guide))[i]
            keep = k and k.count or 0
        end
    end
    local stepNeed = 2 * math.max(CP.Guide.Crafts(live.guide.recipes[st.spell], 22, st.to), keep)
    T.eq(st.short, stepNeed - 10, "short for this step")
    T.eq(st.target, 75)
    -- Cloth for every bolt the plan uses: the bolt step's own, and two a bolt for the
    -- bolts later steps use beyond those.
    local entries = CP.Queue.Build(live.guide, 22, 75, 75, live.plan, live.learned)
    local use, made = {}, 0
    for _, m in ipairs(CP.Queue.Materials(entries)) do use[m.itemID] = m.need end
    for _, e in ipairs(entries) do
        if e.kind == "craft" and e.recipe.makes == BOLT_ITEM then made = made + e.crafts end
    end
    local total = use[LINEN] + 2 * math.max(0, math.ceil((use[BOLT_ITEM] or 0) - made))
    -- The step's own count already holds the kept bolts' cloth, so the cap's need is no less.
    T.ok(total >= stepNeed, ("the plan's cloth %d against the step's %d"):format(total, stepNeed))
    local line, launcher = nextUp("Tailoring")
    T.eq(line.text, ("Linen Cloth x%d"):format(stepNeed - 10))
    T.eq(launcher, line.text, "the launcher tooltip says the same")
    T.eq(line.tip[2], ("%d Linen Cloth short for this step"):format(stepNeed - 10))
    T.eq(line.tip[3], ("%d more by skill 75"):format(total - 10))
    T.eq(itemName(LINEN), "Linen Cloth")
    CraftWorld.Close()
end)

T.test("Next up's line shows the step's shortfall only; the plan's count is in the tip", function()
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 22, max = 75 } }, bags = {} })
    local function name() return "Heavy Leather" end
    -- Empty bags: the plan's need is the count still to get.
    local both = { item = LINEN, short = 57, target = 225, needs = { [LINEN] = 316 } }
    T.eq(CP.Gather.NeedText(both, name), "Heavy Leather x57")
    T.eq(CP.Gather.NeedTip(both, name)[2], "316 more by skill 225")
    T.eq(CP.Gather.NeedText({ item = LINEN, short = 57 }, name), "Heavy Leather x57")
    T.eq(#CP.Gather.NeedTip({ item = LINEN, short = 57 }, name), 1, "no plan count, no tip line")
    T.eq(CP.Gather.NeedText({ item = LINEN, short = 5, buy = {} }, name), "Buy Heavy Leather x5")
    T.eq(CP.Gather.NeedText({ item = LINEN, short = 0, needs = { [LINEN] = 316 }, target = 225 }, name), nil,
        "nothing short for the step: no need line, whatever the plan needs")
    CraftWorld.Close()
end)
