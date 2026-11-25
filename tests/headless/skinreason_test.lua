-- Why a zone gets no skinning grind spot: Gather.SkinReason walks SkinRows' filters in
-- order and names the first that leaves nothing, and /proflost zones prints it on a zone
-- with rows but no spot. Also: creatures the world DB spawns through creature_spawn_entry
-- (Mulgore's kodos, Un'Goro's gorillas) are in the data.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local HBD = LibStub("HereBeDragons-2.0")
local SKIN, FISH = 393, 356
local DUROTAR, MULGORE, BARRENS, UNGORO, SILITHUS = 1411, 1412, 1413, 1449, 1451
local LIGHT, MEDIUM, HEAVY, THICK = 2318, 2319, 4234, 4304

-- Scene: the player in Durotar at `spec.level` (38) with Skinning `spec.skin` (233) and
-- Fishing `spec.fish` (none), guide needs `spec.needs`, mode `spec.mode`, and only
-- `spec.ticked` ticked (all when nil). Spawns stay in their data zone unless `spec.owner`
-- names the zone the map puts every point in.
local function scene(spec, act)
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = spec.level or 38, side = "Horde" })
    World.set(HBD, "GetWorldCoordinatesFromZone", function(_, x, y, z) return x * 1000 + z, y * 1000, 1 end)
    local was = { CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.db.skinSkip }
    CP.db.route = true
    CP.db.otherZones = spec.others or false
    CP.db.routeMode = spec.mode
    CP.charDB.gatherNeeds = spec.needs and { [165] = spec.needs } or nil
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN then return { skillID = id, rank = spec.skin or 233, modifier = 0 } end
        if id == FISH and spec.fish then return { skillID = id, rank = spec.fish, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local mapPos, replan = CP.Waypoint.MapPosZone, G.UpdateAllNeeds
    G.UpdateAllNeeds = function() end
    CP.Waypoint.MapPosZone = function(z) return spec.owner or z end
    G.ResetClusters()
    local ok, err = pcall(function()
        if spec.ticked then
            CP.db.skinSkip = {}
            for _, zone in ipairs({ DUROTAR, BARRENS }) do
                for _, m in ipairs(G.SkinMaterials(zone, G.Skills())) do
                    if not spec.ticked[m.item] then CP.db.skinSkip[m.item] = true end
                end
            end
        end
        act()
    end)
    CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.db.skinSkip, CP.charDB.gatherNeeds = false, nil, nil, nil, nil
    RM.Update(false, {})
    T.advance(1)
    CP.Waypoint.MapPosZone, G.UpdateAllNeeds = mapPos, replan
    G.ResetClusters()
    -- Set back last: a redraw with the route on under this scene's map answers would cache them.
    CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.db.skinSkip = was[1], was[2], was[3], was[4]
    T.ok(ok, err)
end

local function has(text, part)
    T.ok(text and text:find(part, 1, true), tostring(text))
end

T.test("a zone with skinning rows has no reason", function()
    scene({ mode = "farm", ticked = { [LIGHT] = true } }, function()
        T.eq(GL.SkinReason(DUROTAR), nil)
    end)
end)

T.test("follow the guide: the guides need none of the zone's leathers", function()
    scene({ needs = { [HEAVY] = 40, [THICK] = 40 } }, function()
        has(GL.SkinReason(DUROTAR), "follow the guide: the guides need none of ")
        T.eq(GL.SkinReason(BARRENS), nil, "the Barrens has Heavy Leather beasts")
    end)
end)

T.test("farming: no ticked leather at the threshold", function()
    scene({ mode = "farm", ticked = { [THICK] = true } }, function()
        -- Durotar has no Thick Leather; its menu's 35%+ leathers are unticked.
        has(GL.SkinReason(DUROTAR), "skinnable beasts; none yields a ticked leather at 35%+")
    end)
    scene({ mode = "farm", ticked = { [783] = true } }, function()
        -- Light Hide drops at 5% or so: listed with its best chance.
        has(GL.SkinReason(DUROTAR), "none yields a ticked leather at 35%+ (best ")
    end)
end)

T.test("farming: every source of a ticked leather is too high", function()
    scene({ mode = "farm", level = 20, ticked = { [THICK] = true } }, function()
        has(GL.SkinReason(BARRENS), ("all above level %d (lowest "):format(20 + G.FARM_SAFE_LEVELS))
    end)
end)

T.test("every beast needs more Skinning than the player has", function()
    scene({ mode = "farm", skin = 100 }, function()
        has(GL.SkinReason(SILITHUS), "all need Skinning ")
        has(GL.SkinReason(SILITHUS), "(yours 100)")
    end)
end)

T.test("the game puts every spawn in another zone", function()
    scene({ mode = "farm", owner = BARRENS }, function()
        has(GL.SkinReason(DUROTAR), "none inside the zone's border")
    end)
end)

T.test("no Skinning", function()
    scene({ mode = "farm", skin = 0, fish = 100 }, function()
        T.eq(GL.SkinReason(DUROTAR), "no Skinning")
    end)
end)

-- Follow the guide: the checklist's fishing rows count as rows, and Farm routes none of them.
T.test("/proflost zones says why a zone with rows has no grind spot", function()
    scene({ others = true, fish = 150, needs = { [LIGHT] = 40 } }, function()
        GL.RouteOnly()
        T.advance(5)
        local before = #T.prints()
        SlashCmdList.PROFLOST("zones")
        local empty, spotted = 0, 0
        for i = before + 1, #T.prints() do
            local line = tostring(T.prints()[i])
            if line:find(": [1-9]%d* rows, 0 grind spots") then
                empty = empty + 1
                has(line, "; no skinning spot: ")
            elseif line:find(" grind spots", 1, true) then
                spotted = spotted + 1
                T.ok(not line:find("no skinning spot", 1, true), line)
            end
        end
        T.ok(empty > 0, "a zone with fishing rows and no spot")
        T.ok(spotted > 0, "a zone with spots")
    end)
end)

T.test("creatures spawned through creature_spawn_entry are in the data", function()
    local D = CP.GatherData
    for entry, zone in pairs({ [2972] = MULGORE, [2973] = MULGORE, [2974] = MULGORE, [6514] = UNGORO, [6516] = UNGORO }) do
        T.ok(D.mobs[entry] and D.mobs[entry][4][SKIN], "skinnable entry " .. entry)
        T.ok(D.zones[zone].mobs[entry], ("entry %d spawns in zone %d"):format(entry, zone))
    end
end)
