-- Disenchanting, tested without the profession: the baked data, the advice on selling,
-- the bag queue, the Disenchant tab's secure button through casts, failures and combat,
-- and Level-as-you-go costs for Enchanting materials.

local CP = ProfLost
local DE, D = CP.Disenchant, CP.DisenchantData
local DUST, LESSER, GREATER, SHARD = 10940, 10938, 10939, 10978
local SOUL, VISION, DREAM = 11083, 11137, 11176
local SPELL = 13262

local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end

-- Data --------------------------------------------------------------------------------

T.test("every group the data points at exists and yields something", function()
    local used = {}
    for _, g in pairs(D.items) do used[g] = true end
    for _, q in pairs(D.bands) do
        for _, list in pairs(q) do
            for _, b in ipairs(list) do used[b[2]] = true end
        end
    end
    for g in pairs(used) do
        T.ok(D.groups[g] and #D.groups[g] > 0, "group " .. g)
    end
end)

T.test("bands cover item levels 1 to 100 for greens and blues, in order", function()
    for _, q in ipairs({ 2, 3 }) do
        for _, kind in ipairs({ "armor", "weapon" }) do
            local list = D.bands[q][kind]
            T.ok(#list > 0, q .. kind)
            for i = 2, #list do T.ok(list[i][1] > list[i - 1][1], "rising item levels") end
            T.eq(list[#list][1], 100, "the last band reaches 100")
        end
    end
end)

T.test("each disenchant group yields only Enchanting materials", function()
    -- Classic's dusts, essences, shards and the Nexus Crystal.
    local mats = {}
    for _, id in ipairs({ 10940, 11083, 11137, 11176, 16204,
        10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203,
        10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725 }) do mats[id] = true end
    for g, rows in pairs(D.groups) do
        for _, r in ipairs(rows) do
            T.ok(mats[r[1]], ("group %d gives item %d"):format(g, r[1]))
        end
    end
end)

T.test("the bands agree with the data's own items almost always", function()
    -- The band fallback decides items Forever added; it should match known items.
    local seen, same = 0, 0
    for item, group in pairs(D.items) do
        seen = seen + 1
        -- Without quality, ilvl and kind here, compare on the group's main material only.
        local found = false
        for _, q in ipairs({ 2, 3 }) do
            for _, kind in ipairs({ "armor", "weapon" }) do
                for _, b in ipairs(D.bands[q][kind]) do
                    if b[2] == group then found = true end
                end
            end
        end
        if found then same = same + 1 end
        if seen >= 2000 then break end
    end
    T.ok(same / seen > 0.9, ("%d of %d items' groups appear in a band"):format(same, seen))
end)

T.test("green armor by level gives the right dust", function()
    local function main(ilvl)
        return DE.Yield(DE.Group(999999, 2, ilvl, 4))[1].item
    end
    T.eq(main(10), DUST)
    T.eq(main(22), DUST)
    T.eq(main(33), SOUL)
    T.eq(main(43), VISION)
    T.eq(main(48), DREAM)
    T.eq(main(58), 16204, "Illusion Dust")
end)

T.test("low greens: Strange Dust 80% for 1-2, essence the rest", function()
    local y = DE.Yield(1)
    T.eq(y[1].item, DUST)
    T.ok(near(y[1].count, 1.2), "0.8 x 1.5")
    T.eq(y[2].item, LESSER)
    T.ok(near(y[2].count, 0.3), "0.2 x 1.5")
end)

-- Skill -------------------------------------------------------------------------------

T.test("skill to disenchant at each boundary", function()
    local cases = {
        { 5, 2, 1 }, { 20, 2, 1 }, { 21, 2, 25 }, { 25, 2, 25 }, { 26, 2, 50 }, { 45, 2, 125 }, { 60, 2, 200 },
        { 25, 3, 25 }, { 26, 3, 50 }, { 40, 3, 100 }, { 63, 3, 225 },
    }
    for _, c in ipairs(cases) do T.eq(DE.Skill(c[1], c[2]), c[3], ("ilvl %d quality %d"):format(c[1], c[2])) end
    T.eq(DE.Skill(40, 4), nil, "epics are left alone")
    T.eq(DE.Skill(40, 1), nil, "whites can't be disenchanted")
end)

-- Advice -------------------------------------------------------------------------------

local PRICES = { [DUST] = 1000, [LESSER] = 2000, [GREATER] = 6000, [SHARD] = 5000 }
local function price(item) return PRICES[item] end
local function name() return "Strange Dust" end

T.test("advice: disenchant, sell to a vendor, sell at auction, or no prices", function()
    -- Group 1 is worth 1.2 x 10s + 0.3 x 20s = 18s.
    local de = DE.Advice({ group = 1, vendor = 500 }, price, name)
    T.eq(de.verdict, "de")
    T.ok(near(de.de, 1800))
    T.ok(de.text:find("18s"), de.text)

    local vendor = DE.Advice({ group = 1, vendor = 4500 }, price, name)
    T.eq(vendor.verdict, "sell")
    T.ok(vendor.text:find("Vendor pays 45s") and vendor.text:find("buy Strange Dust"), vendor.text)

    local ah = DE.Advice({ group = 1, vendor = 500, ah = 9000 }, price, name)
    T.eq(ah.verdict, "sell")
    T.ok(ah.text:find("at auction"), ah.text)

    local none = DE.Advice({ group = 1, vendor = 4500 }, function() return nil end, name)
    T.eq(none.verdict, "unknown")
    T.ok(none.text:find("vendor 45s"), none.text)
end)

T.test("advice: within 10% stays a disenchant", function()
    T.eq(DE.Advice({ group = 1, vendor = 1980 }, price).verdict, "de", "19.8s vs 18s")
    T.eq(DE.Advice({ group = 1, vendor = 1990 }, price).verdict, "sell", "19.9s is past 10%")
end)

T.test("advice: one material without a price gives a floor verdict", function()
    local partial = function(item) return item == DUST and 1000 or nil end
    local a = DE.Advice({ group = 1, vendor = 100 }, partial)
    T.eq(a.verdict, "de")
    T.eq(a.floor, true)
end)

-- Queue ------------------------------------------------------------------------------

local function item(id, slot, ilvl, extra)
    local it = { bag = 0, slot = slot, itemID = id, name = "I" .. id, quality = 2, ilvl = ilvl, classID = 4, vendor = 100 }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
end

T.test("the queue: skill, kind and quality filters", function()
    local q = DE.Queue({
        item(1, 1, 15),
        item(2, 2, 23),                          -- needs 25
        item(3, 3, 15, { classID = 15 }),        -- not gear
        item(4, 4, 15, { quality = 4 }),         -- epic
        item(5, 5, 15, { quality = 1 }),         -- white
        item(6, 6, 24, { quality = 3 }),         -- blue, needs 25
    }, 20, {}, price, function() return nil end)
    T.eq(#q, 1)
    T.eq(q[1].itemID, 1)
    T.eq(#DE.Queue({ item(2, 2, 23), item(6, 6, 24, { quality = 3 }) }, 25, {}, price, function() end), 2, "both at 25")
end)

T.test("the queue: disenchant first by value, unknowns, then sell, ignored last", function()
    local ah = function(id) return id == 30 and 50000 or nil end
    local items = {
        item(10, 1, 12),                          -- worth 18s
        item(20, 2, 18),                          -- group 2: more dust and greater essence
        item(30, 3, 12),                          -- sells for 5g at auction
        item(40, 4, 12, { vendor = 100 }),        -- ignored
    }
    local q = DE.Queue(items, 300, { [40] = true }, price, ah, nil, true)
    local order = {}
    for _, it in ipairs(q) do order[#order + 1] = it.itemID end
    T.eq(table.concat(order, ","), "20,10,30,40")
    T.ok(q[4].ignored)
end)

T.test("a bound item is never priced at auction", function()
    local q = DE.Queue({ item(50, 1, 12, { bound = true }) }, 300, {}, price, function() return 999999 end)
    T.eq(q[1].advice.ah, nil)
    T.eq(q[1].advice.verdict, "de")
end)

-- Bags ---------------------------------------------------------------------------------

local bag

local function stubBags()
    World.patch("C_Container.GetContainerNumSlots", function(b) return b == 0 and 4 or 0 end)
    World.patch("C_Container.GetContainerItemInfo", function(b, s) return b == 0 and bag[s] or nil end)
    World.patch("C_Item.GetItemInfo", function(id)
        if id == 900099 then return nil end   -- not loaded yet
        local ilvl = id == 900013 and 40 or 12
        return "Green " .. id, "item:" .. id, 2, ilvl, 10, "Armor", "Cloth", 1, "INVTYPE_CHEST", 1, 50, 4
    end)
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id) return id == 333 and { rank = 50, modifier = 0 } or nil end)
    World.patch("InCombatLockdown", function() return false end)
end

local function slotItem(id, bound)
    return { itemID = id, quality = 2, hyperlink = "item:" .. id, isBound = bound or false, iconFileID = 1 }
end

T.test("bag reading skips items whose data hasn't loaded, and asks for them", function()
    bag = { [1] = slotItem(900011), [2] = slotItem(900099) }
    stubBags()
    T.reset_calls()
    local items = DE.Bags()
    T.eq(#items, 1)
    T.eq(items[1].itemID, 900011)
    T.eq(items[1].ilvl, 12)
    T.eq(items[1].vendor, 50)
    T.eq(items[1].classID, 4)
    local asked = T.calls("C_Item.RequestLoadItemDataByID")
    T.eq(#asked, 1)
    T.eq(asked[1][1], 900099, "asked for the missing item")
end)

-- The tab's refresh saves an Enchanting plan, a pick and the ignore list on the character.
-- Each test starts without them and gets them back as it found them when it ends. A refresh
-- the casts queue runs before that, so it cannot land in the next test.
local function fresh()
    World.onEnd(function() T.advance(2) end)
    for _, key in ipairs({ "deIgnore", "committed", "lastPlan", "guidePicks" }) do
        World.set(CP.charDB, key, nil)
    end
end

-- Tab ----------------------------------------------------------------------------------

local function tab()
    local t = CP.Panel.tabs.disenchant
    t.refresh(t.content)
    return CP.DisenchantTab.State()
end

local function aimedAt(button)
    return button:GetAttribute("type"), button:GetAttribute("spell"), button:GetAttribute("target-bag"),
        button:GetAttribute("target-slot")
end

T.test("the button casts Disenchant on the head item, never a macro that could equip it", function()
    fresh()
    bag = { [1] = slotItem(900011), [2] = slotItem(900012) }
    stubBags()
    local _, head, button = tab()
    local kind, spell, b, s = aimedAt(button)
    T.eq(kind, "spell")
    T.eq(spell, tostring(SPELL))
    T.eq(b, head.bag)
    T.eq(s, head.slot)
    T.eq(button:GetAttribute("macrotext"), nil)
    T.eq(button:GetAttribute("useOnKeyDown"), false, "one action per click")
end)

T.test("while a disenchant casts the button does nothing; after it, the next item", function()
    fresh()
    bag = { [1] = slotItem(900011), [2] = slotItem(900012) }
    stubBags()
    local _, head, button = tab()
    local first = head.slot
    T.fire("UNIT_SPELLCAST_START", "player", "cast", SPELL)
    T.eq(button:GetAttribute("type"), nil, "a second press mid-cast does nothing")
    bag[first] = nil
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", SPELL)
    T.advance(0.2)
    local _, head2 = tab()
    T.ok(head2 and head2.slot ~= first, "moved on")
    T.eq(select(4, aimedAt(button)), head2.slot)
end)

T.test("a failed or interrupted disenchant aims at the same item again", function()
    fresh()
    bag = { [1] = slotItem(900011) }
    stubBags()
    local _, head, button = tab()
    for _, ev in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        T.fire("UNIT_SPELLCAST_START", "player", "cast", SPELL)
        T.fire(ev, "player", "cast", SPELL)
        T.advance(0.2)
        tab()
        T.eq(select(4, aimedAt(button)), head.slot, ev)
    end
end)

T.test("other spells and other units leave the button alone", function()
    fresh()
    bag = { [1] = slotItem(900011) }
    stubBags()
    local _, _, button = tab()
    T.fire("UNIT_SPELLCAST_START", "player", "cast", 133)
    T.eq(button:GetAttribute("type"), "spell")
    T.fire("UNIT_SPELLCAST_START", "target", "cast", SPELL)
    T.eq(button:GetAttribute("type"), "spell")
end)

T.test("in combat the button keeps its aim and says so; after combat it's armed", function()
    fresh()
    bag = { [1] = slotItem(900011), [2] = slotItem(900012) }
    stubBags()
    local _, head, button = tab()
    local slot = head.slot
    World.patch("InCombatLockdown", function() return true end)
    bag[slot] = nil
    tab()
    T.eq(select(4, aimedAt(button)), slot, "no attribute changes in combat")
    T.ok(button.label:GetText():find("combat"), button.label:GetText())
    World.patch("InCombatLockdown", function() return false end)
    T.fire("PLAYER_REGEN_ENABLED")
    local _, head2 = tab()
    T.eq(select(4, aimedAt(button)), head2.slot)
end)

T.test("picking a row makes it next", function()
    fresh()
    bag = { [1] = slotItem(900011), [2] = slotItem(900012), [3] = slotItem(900013) }
    stubBags()
    local queue, head = tab()
    local other
    for _, it in ipairs(queue) do if it ~= head then other = it end end
    CP.DisenchantTab.Pick(other)
    local _, head2, button = tab()
    T.eq(head2.itemID, other.itemID)
    T.eq(select(4, aimedAt(button)), other.slot)
end)

T.test("ignoring an item takes it out of the queue for good, and back on request", function()
    fresh()
    bag = { [1] = slotItem(900011), [2] = slotItem(900012) }
    stubBags()
    local _, head = tab()
    CP.DisenchantTab.ToggleIgnore(head.itemID)
    T.ok(CP.charDB.deIgnore[head.itemID], "saved per character")
    local queue, head2 = tab()
    T.eq(#queue, 1)
    T.ok(head2.itemID ~= head.itemID)
    CP.DisenchantTab.ShowIgnored(true)
    local all = tab()
    T.eq(#all, 2, "shown again")
    local _, head3 = tab()
    T.ok(not head3.ignored, "an ignored item is never the head")
    CP.DisenchantTab.ShowIgnored(false)
    CP.DisenchantTab.ToggleIgnore(head.itemID)
    T.eq(#(tab()), 2, "back in")
end)

T.test("nothing to disenchant disables the button", function()
    fresh()
    bag = {}
    stubBags()
    local queue, head, button, summary = tab()
    T.eq(#queue, 0)
    T.eq(head, nil)
    T.eq(button:GetAttribute("type"), nil)
    T.ok(summary:find("No greens"), summary)
end)

T.test("a row draws its yield, values and a warning for a dear item", function()
    fresh()
    bag = { [1] = slotItem(900011) }
    stubBags()
    DaylightMogul = { API = { Price = function(id)
        if id == DUST then return 1000 elseif id == LESSER then return 2000 elseif id == 900011 then return 80000 end
    end } }
    local queue = tab()
    local it = queue[1]
    T.eq(it.advice.verdict, "sell", "8g at auction beats 18s of dust")
    local r = CreateFrame("Button", nil, UIParent)
    CP.DisenchantTab.InitRow(r, it)
    T.ok(r.warn:IsShown(), "warning shown")
    T.ok(r.detail:GetText():find("Disenchant 18s"), r.detail:GetText())
    T.ok(r.detail:GetText():find("Auction 7g"), "8g less the 5% cut, shown as 7g 60s")
    DaylightMogul = nil
end)

-- Level-as-you-go -------------------------------------------------------------------

T.test("Level-as-you-go costs dust by world drops, or cheaper through crafted greens", function()
    local ench = CP.Guides[333]
    local dust = ench.items[DUST]
    T.ok(dust[4] > 5, "world drops: many kills per dust")
    World.patch("GetProfessions", function() return nil end)
    local world = CP.Pricing.GetCollect(DUST, dust)
    T.eq(world, dust[4])
    World.patch("GetProfessions", function() return 1 end)
    World.patch("GetProfessionInfo", function() return nil, nil, nil, nil, nil, nil, 197 end)   -- Tailoring
    local crafted = CP.Pricing.GetCollect(DUST, dust)
    T.ok(crafted < world, ("Tailoring greens: %.1f vs %.1f"):format(crafted, world))
end)

T.test("an Enchanting plan runs to the end in both modes, cheaper with a crafting profession", function()
    local ench = CP.Guides[333]
    local function total(steps)
        local n = 0
        for _, st in ipairs(steps) do
            T.ok(st.spell ~= nil, "no gap at " .. st.from)
            n = n + (st.cost or 0)
        end
        return n
    end
    World.patch("GetProfessions", function() return nil end)
    local alone = total(CP.Solver.Plan(ench, 1, {}, CP.Pricing.GetCollect))
    World.patch("GetProfessions", function() return 1 end)
    World.patch("GetProfessionInfo", function() return nil, nil, nil, nil, nil, nil, 197 end)
    local tailor = total(CP.Solver.Plan(ench, 1, {}, CP.Pricing.GetCollect))
    T.ok(tailor < alone, ("%.0f effort with Tailoring vs %.0f alone"):format(tailor, alone))
    total(CP.Solver.Plan(ench, 1, {}, CP.Pricing.Get))
end)
