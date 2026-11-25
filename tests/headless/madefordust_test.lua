-- Gear a guide made for Enchanting's dust, on the Disenchant tab: Tailoring's Heavy Linen
-- Gloves step is credited for the dust it saves Enchanting, so the gloves it made are marked
-- and lead the queue even where selling pays more. A spare pair beside them keeps the plain
-- verdict, so the mark covers only the crafts the plan asked for.

local CP = ProfLost
local ENCHANTING, TAILOR = 333, 197
local LINEN, THREAD, BOLT, GLOVES, GLOVES_ITEM = 2589, 2320, 2963, 3840, 4307
local DUST, LESSER = 10940, 10938
local ELWYNN = 1429

-- Dust at 10s, the gloves at 8g: the plain verdict sells them.
local PRICES = { [DUST] = 1000, [LESSER] = 2000, [GLOVES_ITEM] = 80000 }

-- Enchanting 1/75 with its needs saved, Tailoring at `rank` on the gloves step.
local function scene(rank)
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 }, [TAILOR] = { rank = rank, max = 75 } },
                       bags = { [LINEN] = 60, [THREAD] = 4 },
                       items = { [GLOVES_ITEM] = { 2, 15, 4, 1, 26, 1, 0 } } })
    World.set(CP.db, "collect", true)
    -- The gloves step leads only without the settle pass, which puts the bolts first while they give
    -- points (decision 0008); this test is about the Disenchant tab's mark, not the plan's shape.
    World.set(CP.Solver, "SETTLE", false)
    World.set(_G, "DaylightMogul", { API = { Price = function(id) return PRICES[id] end } })
    World.patch("InCombatLockdown", function() return false end)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
end

-- The Tailoring step under way, from its open window.
local function currentStep()
    CraftWorld.Open(TAILOR)
    T.advance(1)
    local live = CP.Plan.Current()
    return live and live.plan and live.plan[1]
end

-- Crafts `n` of `spell` through the game's window, cast by cast.
local function craft(spell, n)
    C_TradeSkillUI.CraftRecipe(spell, n)
    for _ = 1, n do CraftWorld.Cast() end
    T.advance(0.5)
end

-- The Disenchant tab, freshly read, with Enchanting's window open.
local function tab()
    CraftWorld.Open(ENCHANTING)
    T.advance(0.5)
    local t = CP.Panel.tabs.disenchant
    if t.button and t.button:IsShown() then t.button:GetScript("OnClick")() end
    T.advance(0.2)
    t.refresh(t.content)
    return CP.DisenchantTab.State()
end

local function gloves(queue)
    local out = {}
    for _, it in ipairs(queue or {}) do
        if it.itemID == GLOVES_ITEM then out[#out + 1] = it end
    end
    return out
end

T.test("a pair made for dust is marked and leads; the spare pair still says sell", function()
    scene(30)
    local step = currentStep()
    T.eq(step and step.spell, GLOVES, "Tailoring's step under way is Heavy Linen Gloves")
    if not (step and step.spell == GLOVES) then return end
    -- The gloves need bolts: make two first, outside the step's count.
    craft(BOLT, 2)
    craft(GLOVES, 1)
    T.eq(CraftWorld.Bag(GLOVES_ITEM), 1, "one pair made on the step")
    CraftWorld.SetBag(GLOVES_ITEM, 2)
    CraftWorld.Close()
    T.advance(0.5)

    local queue, head, button = tab()
    local pairs2 = gloves(queue)
    T.eq(#pairs2, 2, "both pairs listed")
    if #pairs2 ~= 2 then return end
    local planned, spare = 0, 0
    for _, it in ipairs(pairs2) do
        if it.forDust then planned = planned + 1 else spare = spare + 1 end
    end
    T.eq(planned, 1, "one pair marked as made for dust")
    T.eq(spare, 1, "the spare pair is not marked")
    for _, it in ipairs(pairs2) do
        if it.forDust then
            T.ok(it.advice.verdict ~= "sell", "the planned pair is not told sell: " .. tostring(it.advice.verdict))
            T.ok(it.advice.sellBetter == true, "the planned pair still knows selling pays more")
            T.ok((it.advice.ah or 0) > (it.advice.de or 0), "both values stay on the advice")
        else
            T.eq(it.advice.verdict, "sell", "the spare pair keeps the plain verdict")
        end
    end
    T.ok(head and head.forDust, "the planned pair is the queue's head")
    T.ok(button.label:GetText():find("^Disenchant") and not button.label:GetText():find("anyway"),
        "the button disenchants it: " .. tostring(button.label:GetText()))

    -- Its row says so and keeps the gold tradeoff in view.
    local r = CreateFrame("Button", nil, UIParent)
    CP.DisenchantTab.InitRow(r, head)
    local detail = r.detail:GetText() or ""
    T.ok(detail:find(CP.DisenchantTab.DUST_MARK, 1, true) ~= nil, "the row is marked: " .. detail)
    T.ok(detail:find("Auction 7g", 1, true) ~= nil and detail:find("Disenchant ", 1, true) ~= nil,
        "both values show: " .. detail)
    r:Hide()

    -- The player can still ignore it.
    CP.DisenchantTab.ToggleIgnore(GLOVES_ITEM)
    local _, head2 = tab()
    T.ok(not (head2 and head2.itemID == GLOVES_ITEM), "an ignored pair is not the head")
    CraftWorld.Close()
end)

T.test("with Plan for Enchanting off, no pair is marked", function()
    scene(30)
    local step = currentStep()
    if not (step and step.spell == GLOVES) then
        T.ok(false, "Tailoring's step under way is Heavy Linen Gloves")
        return
    end
    craft(BOLT, 2)
    craft(GLOVES, 1)
    CraftWorld.Close()
    T.advance(0.5)
    World.set(CP.db, "deEnchant", false)
    local queue = tab()
    for _, it in ipairs(gloves(queue)) do
        T.ok(not it.forDust, "not marked")
        T.eq(it.advice.verdict, "sell")
    end
    CraftWorld.Close()
end)
