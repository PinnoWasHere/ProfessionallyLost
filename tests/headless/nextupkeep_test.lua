-- Next up counts what the step card counts. A step that makes items later steps keep shows
-- its crafts plus the keep on its row and card (Guide.Keeps), so Next up's shortfall covers
-- the keep too, and "Ready" holds only when the card is short of nothing to gather
-- (simulator finding, Tailoring 22 with 20 Linen Cloth and Blacksmithing 108).

local CP = ProfLost
local TAILOR = 197
local LINEN, BOLT_ITEM = 2589, 2996
local BOLT, ROBE = 2963, 7623

-- Tailoring at 22 with `bags`: the bolt step to 25, then a robe step that eats 93 bolts.
local function tailoring(bags)
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 22, max = 75 } }, bags = bags or {} })
    local guide = CP.Guides[TAILOR]
    local plan = {
        { spell = BOLT, from = 22, to = 25, crafts = CP.Guide.Crafts(guide.recipes[BOLT], 22, 25) },
        { spell = ROBE, from = 25, to = 55, crafts = 31 },
    }
    return guide, plan, { [BOLT] = true, [ROBE] = true }
end

-- The card's crafts for the plan's first step, by the card's own formula (GuideTab stepRows).
local function cardCrafts(guide, plan)
    local keeps = CP.Guide.Keeps(guide, plan, CP.Plan.Held(guide))
    return math.max(plan[1].crafts, keeps[1] and keeps[1].count or 0)
end

T.test("Next up's step shortfall counts the bolts later steps keep", function()
    local guide, plan, learned = tailoring({ [LINEN] = 20 })
    local crafts = cardCrafts(guide, plan)
    T.eq(crafts, 93, "the card makes the 93 bolts the robes keep")
    local st = CP.Gather.NextStep(guide, { skill = 22, max = 75 }, plan, learned)
    T.eq(st.spell, BOLT)
    T.eq(st.item, LINEN, "the step's own material")
    T.eq(st.short, 2 * crafts - 20, "the card's shortfall")
    T.eq(st.crafts, crafts, "the step carries the card's crafts")
    CraftWorld.Close()
end)

T.test("A saved step checked against the bags keeps the card's crafts", function()
    local guide, plan, learned = tailoring({ [LINEN] = 20 })
    local saved = CP.Gather.NextStep(guide, { skill = 22, max = 75 }, plan, learned)
    World.set(CP.charDB, "learned", { [TAILOR] = { BOLT, ROBE } })
    local st = CP.Gather.LiveStep(TAILOR, saved)
    T.eq(st.short, 2 * 93 - 20, "short of the kept bolts' cloth too")
    local text = CP.Gather.NeedText(st, function(id) return CP.ItemName(id) or tostring(id) end)
    T.ok(text ~= nil and text:find("^Linen Cloth x166") ~= nil, tostring(text))
    CraftWorld.Close()
end)

T.test("Next up says Ready only when the card is short of nothing", function()
    -- Enough cloth for the three skill crafts but not the kept bolts: not ready.
    local guide, plan, learned = tailoring({ [LINEN] = 6 })
    local st = CP.Gather.NextStep(guide, { skill = 22, max = 75 }, plan, learned)
    T.ok(st.short > 0, "short " .. tostring(st.short))
    CraftWorld.Close()
    -- The bolts are held: the robes keep from the bags, the card asks for three, and the
    -- six cloth cover them.
    guide, plan, learned = tailoring({ [LINEN] = 6, [BOLT_ITEM] = 93 })
    T.eq(cardCrafts(guide, plan), 3, "the held bolts cover the keep")
    st = CP.Gather.NextStep(guide, { skill = 22, max = 75 }, plan, learned)
    T.eq(st.short, 0, "ready")
    CraftWorld.Close()
end)
