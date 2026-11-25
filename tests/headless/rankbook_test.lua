-- Book and quest ranks: LearnGate says to read the book or do the quest, with the rank's own
-- skill requirement, and Queue.Cost counts a book rank's price (addon pass 2026-11, items 1 and 20).

local CP = ProfLost
local LW, COOKING, FIRST_AID = 165, 185, 129
local GOLDTHORN_TEA, MAGEWEAVE_BANDAGE = 13028, 10841

local function gate(id, spell, skill, max)
    local g = CP.Guides[id]
    return CP.Guide.LearnGate(g.recipes[spell], { id = id, skill = skill, max = max, name = g.name })
end

local function rankNamed(id, name)
    for _, r in ipairs(CP.Guides[id].ranks) do
        if r.name == name then return r end
    end
end

T.test("a book rank says to read the book, at the rank's own skill", function()
    local g = gate(COOKING, GOLDTHORN_TEA, 140, 150)
    T.eq(g.label, "Read Expert Cookbook")
    T.eq(g.tip, "Needs the Expert Cookbook first (skill 125), then Cooking 175.")
end)

T.test("a quest rank says to do the quest", function()
    local g = gate(FIRST_AID, MAGEWEAVE_BANDAGE, 220, 225)
    T.eq(g.label, "Do Triage")
    T.eq(g.tip, "Needs the quest Triage first (Artisan First Aid, skill 225), then First Aid 240.")
end)

T.test("a trainer rank gives its own skill, not the cap", function()
    local lw = CP.Guides[LW]
    local recipe
    for _, r in pairs(lw.recipes) do
        if r.src == "trainer" and r.learn > 75 and r.learn <= 100 then recipe = r break end
    end
    T.ok(recipe ~= nil, "a trainer recipe past 75")
    local g = CP.Guide.LearnGate(recipe, { id = LW, skill = 60, max = 75, name = "Leatherworking" })
    T.eq(g.label, "Train Journeyman Leatherworking")
    T.ok(g.tip:find("(skill 50)", 1, true) ~= nil, g.tip)
end)

T.test("Queue.Cost counts a book rank's price as training, and a quest rank as free", function()
    local guide = CP.Guides[COOKING]
    local book = rankNamed(COOKING, "Expert Cookbook")
    local trainer = rankNamed(COOKING, "Journeyman Cooking")
    local quest = rankNamed(COOKING, "Artisan Cooking")
    local entries = {
        { kind = "rank", rank = book },
        { kind = "rank", rank = trainer },
        { kind = "rank", rank = quest },
    }
    local total, materials, training = CP.Queue.Cost(guide, entries, {}, function() return nil end)
    T.eq(training, book.price + trainer.fee)
    T.eq(materials, 0)
    T.eq(total, book.price + trainer.fee)
end)
