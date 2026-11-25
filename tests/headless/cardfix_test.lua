-- CARDFIX-01: card advice fixes (review items 14, 15 and 17).
--   14  a Daylight UI batch of another recipe never judges the shown step's end or count
--   15  an unlearned favor recipe's card names its favor vendor, not "World drop"
--   17  the item tooltip does not call a plan-made intermediate short or send the player to farm it

local CP = ProfLost
local GT = CP.GuideTab
local LW, TAILORING = 165, 197
local DUROTAR = 1411
local HEAVY_KIT, LIGHT_KIT_SPELL = 3780, 2152
local HEAVY_LEATHER, FINE_THREAD, LIGHT_LEATHER = 4234, 2321, 2318
local BOLT, LINEN = 2996, 2589

local function words() return GT.ui.details.sale:GetText() or "" end

T.test("14: a Daylight UI batch of another recipe is not judged against the shown step", function()
    DaylightWorld.begin({ plugin = true })
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = 136, max = 225 } },
                       bags = { [HEAVY_LEATHER] = 60, [FINE_THREAD] = 20, [LIGHT_LEATHER] = 60 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.Open(LW)
    T.advance(2)

    DaylightWorld.Create(LIGHT_KIT_SPELL, 40)
    T.advance(0.5)
    T.ok(CP.Crafting.Busy() and CP.Crafting.daylight, "Daylight UI's batch runs")
    local urged
    for _ = 1, 30 do
        CraftWorld.Cast()
        T.advance(0.2)
        CP.Panel:Refresh()
        local made = CP.Crafting.Progress()
        if made >= 23 then
            urged = words():find("Stop the batch", 1, true) ~= nil
            break
        end
    end
    T.ok(not urged, "no stop warning for a batch of a recipe the card is not on: " .. words())
    T.ok(not (GT.ui.details.making and GT.ui.details.making.stop.cpUrged), "Stop is not urged")
    DaylightWorld.Fire("CraftStopped")
    CraftWorld.Close()
end)

T.test("14: a batch of the card's own recipe is still judged against its step", function()
    DaylightWorld.begin({ plugin = true })
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = 136, max = 225 } },
                       bags = { [HEAVY_LEATHER] = 60, [FINE_THREAD] = 20 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.Open(LW)
    T.advance(2)

    DaylightWorld.Create(HEAVY_KIT, 8)
    T.advance(0.5)
    CP.Panel:Refresh()
    T.ok(type(CP.Crafting.stepEnd) == "number", "the card's own recipe is tracked")
    DaylightWorld.Fire("CraftStopped")
    CraftWorld.Close()
end)

T.test("15: a favor recipe's card names its favor vendor", function()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    DaylightWorld.begin({ craftWindow = false })
    CraftWorld.begin({ professions = { [LW] = { rank = 136, max = 225 } },
                       bags = { [HEAVY_LEATHER] = 60, [FINE_THREAD] = 20 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.Open(LW)
    T.advance(2)

    local how = "Schematic for 180 Merchant's Favor: Fritz Fizzle (A) or Fizzlefuse (H)"
    local recipe = { learn = 195, src = "favor", how = how, reagents = {}, name = "Forced" }
    GT.ui.live = GT.ui.live or {}
    local line = GT.LearnLine({ recipe = recipe })
    T.ok(line:find("Fizzle", 1, true) ~= nil, "the favor vendor line: " .. tostring(line))
    T.ok(line:find("World drop", 1, true) == nil, "not a world drop: " .. tostring(line))
    CraftWorld.Close()
end)

T.test("17: a bolt the plan makes is not short and not farmed on its tooltip", function()
    MapWorld.begin({ zone = DUROTAR, level = 5, side = "Horde" })
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == TAILORING then return { skillID = id, rank = 1, modifier = 0, maxRank = 75 } end
    end)
    World.set(CP.charDB, "gatherNeeds", {})
    CP.Gather.UpdateAllNeeds()
    local lines = CP.ItemTooltip.Lines(BOLT)
    T.ok(#lines >= 1, "the tooltip still names the need")
    for _, l in ipairs(lines) do
        T.ok(not l[1]:find("short", 1, true), "no short line: " .. l[1])
        T.ok(not l[1]:find("Farm", 1, true), "no farm line: " .. l[1])
    end
    local raw = CP.ItemTooltip.Lines(LINEN)
    local short
    for _, l in ipairs(raw) do if l[1]:find("short", 1, true) then short = true end end
    T.ok(short, "the raw cloth the bolts are made from is still short")
end)
