-- A character standing in a zone far above their level (a trainer's errand left them there)
-- is not kept fishing in it, with or without a lure (FISHRANK-01b). The own zone is safe only
-- up to what the character survives, as the other gathering guides rule.

local CP = ProfLost
local F, G, GG = CP.Fishing, CP.Gather, CP.GatherGuide
local FISH = 356
local STRANGLETHORN, HINTERLANDS = 1434, 1425
local LURE = 100

local function scene(zone, level, rank, mod, max)
    MapWorld.begin({ zone = zone, x = 0.5, y = 0.5, level = level, side = "Horde" })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "fishCook", false)
    World.set(CP.db, "routeSkip", nil)
    World.set(CP.charDB, "gatherNeeds", {})
    World.set(CP.charDB, "gatherSoon", {})
    World.set(CP.charDB, "guideMode", "one")
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        return id == FISH and { skillID = id, rank = rank, modifier = mod, maxRank = max } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
end

local function has(list, zone)
    for _, c in ipairs(list) do
        if c.zone == zone then return true end
    end
    return false
end

local function fishRow(rank, max)
    for _, r in ipairs(GG.PlayerRows(FISH, rank, max)) do
        if r.fish then return r end
    end
end

T.test("Candidates leaves out the zone a level 20 character stands in when it is far above them", function()
    T.ok(not has(F.Candidates(125 + LURE, 20, "Horde", STRANGLETHORN), STRANGLETHORN), "lured")
    T.ok(not has(F.Candidates(125, 20, "Horde", STRANGLETHORN), STRANGLETHORN), "bare")
end)

T.test("a zone within what the character survives stays safe as their own zone", function()
    local lvl = CP.GatherData.zones[STRANGLETHORN].lvl[1]
    T.ok(has(F.Candidates(125 + LURE, lvl - GG.SURVIVE, "Horde", STRANGLETHORN), STRANGLETHORN),
        "the own zone at the survivable edge")
end)

T.test("the plan and the Guide's current row leave Stranglethorn at level 20, rank 125, lured", function()
    local p = F.Plan({ skill = 125, mod = LURE, maxRank = 225, level = 20, zone = STRANGLETHORN, side = "Horde",
        have = function() return 0 end })
    T.ok(p.kind == "none" or p.zone ~= STRANGLETHORN, "the plan's water")
    scene(STRANGLETHORN, 20, 125, LURE, 225)
    local row = fishRow(125, 225)
    T.ok(row, "a fishing row")
    T.ok(row.fish.zone ~= STRANGLETHORN, "the row's water")
end)

T.test("the Guide's current row leaves the Hinterlands at level 35, rank 200, lured", function()
    scene(HINTERLANDS, 35, 200, LURE, 225)
    local row = fishRow(200, 225)
    T.ok(row, "a fishing row")
    T.ok(row.fish.zone ~= HINTERLANDS, "the row's water")
end)
