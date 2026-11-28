-- The Tailoring card and Enchanting's dust count read one rounding (SCENE-02 finding F2:
-- 33 crafts x 3.75 Strange Dust showed x124 on one card and ~123 on the other).

local CP = ProfLost
local GT = CP.GuideTab
local ENCHANTING, TAILOR = 333, 197
local DUST = 10940

local function plan(prof)
    CraftWorld.Open(prof)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
end

local function showWindow()
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowCollapsedAll", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function() CP.Window.SetFolded(false) CP.Window.Update() end)
    CP.Window.SetFolded(false)
    CP.Window.Update()
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
end

T.test("Tailoring 95 with Enchanting 60: the Tailoring card note and Enchanting's tag give one dust count", function()
    MapWorld.begin({ zone = 1429, level = 30, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 60, max = 75 }, [TAILOR] = { rank = 95, max = 150 } } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    plan(ENCHANTING)
    plan(TAILOR)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    showWindow()
    CP.Window.Pick(TAILOR)
    CP.Panel:Refresh()
    local split = CP.Shared.DEIncomingSplit(DUST)
    T.ok(split.now > 0, "Tailoring's current step disenchants for dust")

    local shown
    for _, row in ipairs(GT.ui.rows) do
        if row.spell and not row.side and not (row.rank or row.train) then
            GT.Pick(row)
            T.advance(0.3)
            local n = (GT.ui.details.sale:GetText() or ""):match("Strange Dust x(%d+)")
            if n then shown = tonumber(n) break end
        end
    end
    T.ok(shown ~= nil, "the Tailoring card says how much dust it gives")
    T.eq(shown, split.now, "the card note and the Enchanting count agree")
    CraftWorld.Close()
end)

T.test("DERound rounds to the nearest", function()
    T.eq(CP.Shared.DERound(123.75), 124)
    T.eq(CP.Shared.DERound(123.25), 123)
    T.eq(CP.Shared.DERound(0), 0)
end)
