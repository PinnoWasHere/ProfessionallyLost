-- A batch running past its step's end (owner, 2026-11-18: Heavy Armor Kit, batch 7 of 8 with the
-- skill past the step's 155): the step card says to stop and Stop is the main action. The batch is
-- never stopped for the player.

local CP = ProfLost
local GT = CP.GuideTab
local LW = 165
local DUROTAR = 1411
local KIT = 3780
local HEAVY_LEATHER, FINE_THREAD = 4234, 2321

local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    DaylightWorld.begin({ craftWindow = false })
    CraftWorld.begin({ professions = { [LW] = { rank = 136, max = 225 } },
                       bags = { [HEAVY_LEATHER] = 60, [FINE_THREAD] = 20 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.Open(LW)
    T.advance(2)
end

local function words() return GT.ui.details.sale:GetText() or "" end

T.test("a batch past its step's end warns on the card and lights Stop; nothing stops it", function()
    scene()
    CP.Crafting.Start(KIT, 8)
    T.advance(0.5)
    local stepEnd = CP.Crafting.stepEnd
    T.ok(type(stepEnd) == "number", "the batch noted the step's end")
    T.ok(words():find("Stop the batch", 1, true) == nil, "no warning inside the step")
    T.ok(not GT.ui.details.making.stop.cpUrged, "Stop plain inside the step")

    CraftWorld.SetSkill(LW, stepEnd, 225)
    CP.Panel:Refresh()
    T.advance(0.5)
    T.ok(CP.Crafting.Busy(), "the batch still runs")
    T.ok(words():find("Stop the batch", 1, true) ~= nil, "the card says to stop: " .. words())
    T.ok(GT.ui.details.making.stop.cpUrged == true, "Stop is highlighted")

    CP.Crafting.Stop()
    CP.Panel:Refresh()
    T.advance(0.5)
    T.ok(words():find("Stop the batch", 1, true) == nil, "the warning goes with the batch")
    T.ok(not CP.Crafting.Overshoot(stepEnd), "no overshoot with no batch")
    CraftWorld.Close()
end)
