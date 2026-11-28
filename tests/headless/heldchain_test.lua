-- Item tooltips count what the player holds at every stage of a conversion chain, bags and bank
-- alike (owner, 2026-11-27): the ore held under the bars it smelts into, the bolts or cured hides held
-- under the cloth or hides they are made from. The guide's rows are the reference: a maker row makes
-- what later steps need beyond its own skill-up crafts and the stock (Guide.Keeps).

local CP = ProfLost
local LW, TAILORING, BS = 165, 197, 164
local DUROTAR = 1411
local IRON_ORE, IRON_BAR = 2772, 3575
local SILK, SILK_BOLT = 4306, 4305
local RUGGED_HIDE, CURED_RUGGED = 8171, 15407

-- `held` as the game counts it: the bags, plus the bank when asked. `bank` holds bank-only items.
local function holding(held, bank)
    World.patch("C_Item.GetItemCount", function(id, withBank)
        return (held[id] or 0) + (withBank and bank and bank[id] or 0)
    end)
end

-- `line` at skill 1 with its needs to 300 saved, as the shut window saves them.
local function solved(line)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == line then return { skillID = id, rank = 1, modifier = 0, maxRank = 300 } end
    end)
    World.set(CP.charDB, "gatherNeeds", {})
    CP.Gather.UpdateAllNeeds()
    return CP.charDB.gatherNeeds[line] or {}
end

-- What the guide's rows use of `item` to 300: each row's crafts, kept crafts included.
local function rowsUse(line, item)
    local guide = CP.Guides[line]
    local live = CP.Plan.Shut(line)
    local keeps = CP.Guide.Keeps(guide, live.plan, CP.Plan.Held(guide))
    local n = 0
    for i, st in ipairs(live.plan) do
        local r = st.spell and guide.recipes[st.spell]
        if r then
            local crafts = math.max(st.crafts, CP.Guide.KeepCrafts(r, keeps[i] and keeps[i].count))
            for _, pair in ipairs(r.reagents) do
                if pair[1] == item then n = n + pair[2] * crafts end
            end
        end
    end
    return n
end

local function lineOf(item, pattern)
    for _, l in ipairs(CP.ItemTooltip.Lines(item)) do
        if l[1]:find(pattern) then return l[1] end
    end
end

T.test("Iron Ore: 30 bars and 40 ore held leave 30 ore to mine", function()
    World.set(CP.charDB, "gatherNeeds", { [BS] = { [IRON_BAR] = 100 } })
    World.patch("C_Item.GetItemNameByID", function(id) return id == IRON_BAR and "Iron Bar" or nil end)
    holding({ [IRON_BAR] = 30, [IRON_ORE] = 40 })
    T.eq(lineOf(IRON_ORE, "^Have "), "Have 30 · short x70 (40 ore held, mine 30)")
    holding({ [IRON_BAR] = 30, [IRON_ORE] = 70 })
    T.eq(lineOf(IRON_ORE, "^Have "), "Have 30 · short x70 (70 ore held, smelt them)")
    holding({ [IRON_BAR] = 30 })
    T.eq(lineOf(IRON_ORE, "^Have "), "Have 30 · short x70 (mine 70 ore)")
end)

T.test("Iron Ore: bars and ore held only in the bank count as held", function()
    World.set(CP.charDB, "gatherNeeds", { [BS] = { [IRON_BAR] = 100 } })
    World.patch("C_Item.GetItemNameByID", function(id) return id == IRON_BAR and "Iron Bar" or nil end)
    holding({}, { [IRON_BAR] = 30, [IRON_ORE] = 40 })
    T.eq(lineOf(IRON_ORE, "^Have "), "Have 30 · short x70 (40 ore held, mine 30)")
    T.eq(lineOf(IRON_BAR, "^Have "), "Have 30 · short x70")
end)

T.test("Silk Cloth: the bolts the guide's rows make beyond their points count, less the bolts held", function()
    MapWorld.begin({ zone = DUROTAR, level = 60, side = "Horde" })
    holding({})
    local needs = solved(TAILORING)
    local want = rowsUse(TAILORING, SILK)
    T.eq(needs[SILK], want, "the saved need is what the guide's rows use")
    T.eq(lineOf(SILK, "needs x"), ("Tailoring needs x%d"):format(want))

    holding({ [SILK_BOLT] = 100 }, { [SILK] = 50 })
    needs = solved(TAILORING)
    local fewer = rowsUse(TAILORING, SILK)
    T.ok(fewer < want, ("100 bolts held make fewer bolts: %d, not %d"):format(fewer, want))
    T.eq(needs[SILK], fewer)
    T.eq(lineOf(SILK, "^Have "), ("Have 50 · short x%d"):format(fewer - 50), "the silk in the bank counts")
end)

T.test("Rugged Hide: the cured hides the guide's rows make beyond their points count, less those held", function()
    MapWorld.begin({ zone = DUROTAR, level = 60, side = "Horde" })
    holding({})
    local needs = solved(LW)
    local want = rowsUse(LW, RUGGED_HIDE)
    T.eq(needs[RUGGED_HIDE], want, "the saved need is what the guide's rows use")

    holding({ [CURED_RUGGED] = 10 })
    needs = solved(LW)
    local fewer = rowsUse(LW, RUGGED_HIDE)
    T.ok(fewer < want, ("10 cured hides held: %d, not %d"):format(fewer, want))
    T.eq(needs[RUGGED_HIDE], fewer)
    T.eq(lineOf(RUGGED_HIDE, "needs x"), ("Leatherworking needs x%d"):format(fewer))
end)
