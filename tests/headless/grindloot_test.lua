-- Grind spots from creature loot: fish never form one, other loot needs
-- Gather.LOOT_MIN_CHANCE, skinning keeps its own threshold.

local CP = ProfLost
local G = CP.Gather
local LONGJAW, CATFISH, MEAT = 6289, 6291, 769

local function mob(prof, chance)
    return { kind = "mob", entry = 1, name = "Wrathtail Myrmidon", chance = chance, prof = prof }
end

T.test("the loot threshold is 25%", function()
    T.eq(G.LOOT_MIN_CHANCE, 0.25)
end)

T.test("a 5% fish from a creature forms no spot, even at a high chance", function()
    T.ok(CP.Pricing.IsFish(LONGJAW) and CP.Pricing.IsFish(CATFISH), "both are catches")
    T.ok(not G.GrindSource(LONGJAW, mob(185, 5)), "Raw Longjaw Mud Snapper 5%")
    T.ok(not G.GrindSource(CATFISH, mob(185, 5)), "Raw Bristle Whisker Catfish 5%")
    T.ok(not G.GrindSource(LONGJAW, mob(185, 80)), "fish at 80% still goes to Fishing")
end)

T.test("meat at 60% counts, meat at 5% does not, skinning is untouched", function()
    T.ok(not CP.Pricing.IsFish(MEAT), "Chunk of Boar Meat is no fish")
    T.ok(G.GrindSource(MEAT, mob(185, 60)))
    T.ok(not G.GrindSource(MEAT, mob(185, 5)))
    T.ok(G.GrindSource(2318, mob(G.SKINNING, 5)), "skinning is filtered in SkinRows")
    T.ok(G.GrindSource(LONGJAW, { kind = "pool", chance = 5 }), "non-creature sources pass")
end)

T.test("Route.Points drops low-chance creature rows and keeps the 60% ones", function()
    local rows = {
        { itemID = LONGJAW, need = 5, sources = { mob(185, 5) } },
        { itemID = MEAT, need = 5, sources = { mob(185, 60) } },
    }
    local seen = {}
    local points = CP.Route.Points(1411, rows, function() return { { 0.5, 0.5, 4 } } end, "mob", 40)
    for _, p in ipairs(points) do for item in pairs(p.items) do seen[item] = true end end
    T.ok(seen[MEAT], "meat spot")
    T.ok(not seen[LONGJAW], "no fish spot")
end)
