-- The player's own gathering finds (Engine/Finds.lua).

local CP = ProfLost
local Finds = CP.Finds
local RIVERGLADES = 2548

local function withSpells(fn)
    local names = { [2366] = "Herb Gathering", [2575] = "Mining", [8613] = "Skinning",
                    [2368] = "Herb Gathering", [133] = "Fireball" }
    local spell, zone, pos = C_Spell.GetSpellName, CP.Waypoint.PlayerZone, C_Map.GetPlayerMapPosition
    local guid, uname = UnitGUID, UnitName
    local saved = CP.db.finds
    CP.db.finds = nil
    World.set(CP.db, "seenMobs", nil)
    World.onEnd(function() T.advance(CP.GatherMate.SETTLE + 1) end)   -- settles the queued finds timer
    C_Spell.GetSpellName = function(id) return names[id] end
    CP.Waypoint.PlayerZone = function() return RIVERGLADES end
    local at = { 0.5, 0.5 }
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return at[1], at[2] end } end
    UnitGUID = function(unit) return unit == "target" and "Creature-0-1-2-3-99001-0000" or nil end
    UnitName = function(unit) return unit == "target" and "Riverglade Croc" or nil end
    local ok, err = pcall(fn, at)
    C_Spell.GetSpellName, CP.Waypoint.PlayerZone, C_Map.GetPlayerMapPosition = spell, zone, pos
    UnitGUID, UnitName = guid, uname
    CP.db.finds = saved
    CP.GatherMate.Reset()
    T.ok(ok, err)
end

T.test("a herb picked, a vein mined and a beast skinned are saved where the player stood", function()
    withSpells(function(at)
        Finds.Sent("player", "Peacebloom", "cast1", 2368)
        Finds.Succeeded("player", "cast1")
        T.eq(#Finds.Nodes(RIVERGLADES).Peacebloom, 1, "a higher rank's spell counts by name")
        Finds.Sent("player", "Peacebloom", "cast2", 2366)
        Finds.Succeeded("player", "cast2")
        T.eq(#Finds.Nodes(RIVERGLADES).Peacebloom, 1, "the same spot again: not a new find")
        at[1] = 0.6
        Finds.Sent("player", "Copper Vein", "cast3", 2575)
        Finds.Succeeded("player", "cast3")
        T.eq(#Finds.Nodes(RIVERGLADES)["Copper Vein"], 1)
        Finds.Sent("player", "Riverglade Croc", "cast4", 8613)
        Finds.Succeeded("player", "cast4")
        T.eq(#Finds.Mobs(RIVERGLADES)[99001], 1, "skinned: the creature id from its GUID")
        Finds.Sent("player", "Peacebloom", "cast5", 133)
        Finds.Succeeded("player", "cast5")
        Finds.Sent("player", "Silverleaf", "cast6", 2366)
        Finds.Succeeded("player", "other")
        T.eq(Finds.Nodes(RIVERGLADES).Silverleaf, nil, "another spell, or a cast that isn't ours: nothing")
        local x, y = unpack(Finds.Nodes(RIVERGLADES)["Copper Vein"][1])
        T.ok(math.abs(x - 0.6) < 1e-4 and math.abs(y - 0.5) < 1e-4, "the spot round-trips")
        T.advance(CP.GatherMate.SETTLE + 1)
        T.eq(#CP.GatherMate.Nodes(RIVERGLADES)["Copper Vein"], 1, "the checklist and route see it once finds settle")
        local zones, nodes, mobs = Finds.Count()
        T.eq(zones, 1) T.eq(nodes, 2) T.eq(mobs, 1)
    end)
end)

T.test("new finds don't rebuild caches one by one: they settle together, or on a zone change", function()
    local GM, G = CP.GatherMate, CP.Gather
    local resets = 0
    local reset = G.ResetClusters
    G.ResetClusters = function() resets = resets + 1 end
    local ok, err = pcall(function()
        GM.Added()
        GM.Added()
        GM.Added()
        T.eq(resets, 0, "nothing rebuilt per find")
        T.ok(GM.Pending())
        T.advance(GM.SETTLE + 1)
        T.eq(resets, 1, "one rebuild once they settle")
        GM.Added()
        T.fire("ZONE_CHANGED_NEW_AREA")
        T.eq(resets, 2, "a zone change takes them in at once")
        T.advance(GM.SETTLE + 1)
        T.eq(resets, 2, "and the timer then has nothing left to do")
    end)
    G.ResetClusters = reset
    T.ok(ok, err)
end)
