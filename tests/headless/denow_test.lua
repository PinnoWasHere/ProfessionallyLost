-- Enchanting's card splits what another guide's disenchanting gives now from later (tester,
-- 2026-11-18: "I need 19 more [Strange Dust]. But tailoring only shows make 2 more").

local CP = ProfLost
local GT = CP.GuideTab
local ENCHANTING, TAILOR = 333, 197
local DUST = 10940

T.test("Enchanting 53 with Tailoring 66: the dust tag counts Tailoring's current step, the note the rest", function()
    MapWorld.begin({ zone = 1429, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 53, max = 75 }, [TAILOR] = { rank = 66, max = 150 } } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    -- The guide window open, unfolded, on the Guide tab, showing Enchanting.
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowCollapsedAll", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function() CP.Window.SetFolded(false) CP.Window.Update() end)
    CP.Window.SetFolded(false)
    CP.Window.Update()
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    CP.Window.Pick(ENCHANTING)
    CP.Panel:Refresh()
    for _, row in ipairs(GT.ui.rows) do
        if row.spell and not row.side and not (row.rank or row.train) then GT.Pick(row) break end
    end
    T.advance(0.3)

    local split = CP.Shared.DEIncomingSplit(DUST)
    T.ok(split.now + split.later > 0, "Tailoring disenchants for dust")
    local packed = CP.charDB.lastPlan[TAILOR]
    local first = CP.Guides[TAILOR].recipes[packed[1][3]]
    T.eq(split.nowStep and split.nowStep.recipe or first.name, first.name, "now is Tailoring's current step")

    local d = GT.ui.details
    local tag
    for _, l in ipairs(d.rows) do
        if l:IsShown() and l.itemID == DUST then tag = l.tag:GetText() end
    end
    T.eq(tag, ("~%d now"):format(split.now), "the tag")
    local sale = d.sale:GetText() or ""
    T.ok(sale:find("Strange Dust: ", 1, true) ~= nil, sale)
    if split.later > 0 then T.ok(sale:find(("~%d later"):format(split.later), 1, true) ~= nil, sale) end
    T.ok(not sale:find("from Tailoring$"), "no whole-plan count standing alone: " .. sale)
    CraftWorld.Close()
end)

T.test("with Plan for Enchanting off nothing is counted", function()
    World.set(CP.db, "deEnchant", false)
    local split = CP.Shared.DEIncomingSplit(DUST)
    T.eq({ split.now, split.later }, { 0, 0 })
end)
