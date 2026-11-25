-- The step card lists every material of the step's recipe, however many it has (simulator
-- finding, 2026-11-16: Robe of the Archmage's card left out its seventh, Viridian Dye).

local CP = ProfLost
local TAILOR, ROBE, DYE = 197, 18457, 249431

T.test("a recipe with seven materials shows all seven on its card", function()
    local guide = CP.Guides[TAILOR]
    local r = guide.recipes[ROBE]
    T.eq(#r.reagents, 7, "Robe of the Archmage uses seven materials")
    local known = { ROBE }
    for id, rec in pairs(guide.recipes) do
        if rec.src == "trainer" or rec.src == "auto" then known[#known + 1] = id end
    end
    World.set(CP.db, "collect", false)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 296, max = 300, known = known } } })
    CraftWorld.Open(TAILOR)
    T.advance(1)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    local row
    for _, x in ipairs(CP.GuideTab.ui.rows or {}) do
        if x.spell == ROBE and not x.side then row = x end
    end
    T.ok(row ~= nil, "the guide leads with Robe of the Archmage at 296")
    if not row then return end
    CP.GuideTab.Pick(row)
    local d = CP.GuideTab.ui.details
    local shown = {}
    for _, line in ipairs(d.rows) do
        if line:IsShown() and line.itemID then shown[line.itemID] = true end
    end
    for _, pair in ipairs(r.reagents) do
        T.ok(shown[pair[1]], ("the card shows %s"):format(CP.ItemName(pair[1]) or pair[1]))
    end
    T.ok(shown[DYE], "Viridian Dye is on the card")
end)
