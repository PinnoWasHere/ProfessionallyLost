-- A maker sized again leaves its row ending where its count plays to (decision 0008 rule 2).
-- Property finding rowpoints-6dc9aa70a9: a Horde Engineer at 225 with empty bags got "Mithril Casing
-- 225-236 ~20 crafts", which plays to 237.1. Trimming the casing row to 236 gave the Unstable Trigger
-- run 236-238, and sizing the trigger again moved two points to the bomb, so the casing count the
-- row keeps rose from 18 to 20 after the row was sized.

local CP = ProfLost
local W, GT = CP.Window, CP.GuideTab
local ENGINEERING = 202
local DUROTAR = 1411
local CASING = 12599

local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 60, side = "Horde" })
    CraftWorld.begin({ professions = { [ENGINEERING] = { rank = 225, max = 300 } } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    World.set(CP.db, "fishCook", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
        GT.Forget()
    end)
    CraftWorld.Open(ENGINEERING)
    CraftWorld.Close()
    W.Update()
    W.Pick(ENGINEERING)
    CP.Panel:Refresh()
    T.advance(0.1)
end

T.test("the casing row plays to its end after the trigger is sized again", function()
    scene()
    local row
    for _, r in ipairs(GT.ui.rows) do
        if r.spell == CASING and not (r.side or r.rank or r.train) then row = r end
    end
    T.ok(row ~= nil, "the plan has the casing row")
    if not row then return end
    local ended = CP.Solver.Play(row.recipe, row.from, row.crafts)
    T.ok(math.abs(ended - row.to) <= 1, ("%s %d-%d ~%d crafts plays to %.2f"):format(row.recipe.name, row.from, row.to,
        row.crafts, ended))
end)
