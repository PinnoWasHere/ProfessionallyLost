-- The vendor buy covers the whole step (owner's report on 1.1.0, 2026-11-18): Leatherworking 143,
-- Heavy Armor Kit 143-153, ~12 crafts, 58 Heavy Leather in the bags. The card read "Fine Thread
-- buy 11  0 / 12": the buy matched only the crafts the leather covers now (58 / 5 = 11). Owner's
-- choice: buy what the whole step needs, 12, since vendor goods are cheap and the rest is gathered.

local CP = ProfLost
local GT = CP.GuideTab
local LW = 165
local KIT, HEAVY, THREAD = 3780, 4234, 2321

T.test("Guide.VendorTopUp buys the whole step's vendor goods", function()
    local g = CP.Guides[LW]
    local reagents = {
        { itemID = HEAVY, name = "Heavy Leather", need = 5, have = 58 },
        { itemID = THREAD, name = "Fine Thread", need = 1, have = 0 },
    }
    local reach, buy = CP.Guide.VendorTopUp(g, reagents, 12)
    T.eq(reach, 11, "58 Heavy Leather cover 11 crafts now")
    T.eq(#buy, 1)
    T.eq(buy[1] and (buy[1].name .. " " .. buy[1].count), "Fine Thread 12", "the whole step's thread")
end)

T.test("the owner's card: Heavy Armor Kit at 143 with 58 Heavy Leather reads buy 12 for Fine Thread", function()
    MapWorld.begin({ zone = 1411, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = 143, max = 225 } }, bags = { [HEAVY] = 58 } })
    World.set(CP.db, "collect", true)
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel:Refresh()
    local kit
    for _, row in ipairs(GT.ui.rows) do
        if row.spell == KIT and not row.side and not kit then kit = row end
    end
    T.ok(kit ~= nil, "a Heavy Armor Kit step")
    if not kit then return end
    GT.Pick(kit)
    T.advance(0.5)
    local d = GT.ui.details
    local tag, count
    for _, l in ipairs(d.rows) do
        if l:IsShown() and l.itemID == THREAD then tag, count = l.tag:GetText(), l.count:GetText() end
    end
    local need = kit.crafts
    T.eq(count, ("0 / %d"):format(need), "the thread's count")
    T.eq(tag, ("buy %d"):format(need), "the buy covers the whole step")
    -- Next up names no vendor good while leather is short: it is bought on the way.
    local st = CP.Gather.NextStep(CP.Guides[LW], kit and { skill = 143, max = 225 }, CP.Plan.Current().plan, {})
    T.ok(st and st.item ~= THREAD, "Next up names the leather, not the thread")
    CraftWorld.Close()
end)
