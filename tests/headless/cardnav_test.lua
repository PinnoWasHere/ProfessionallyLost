-- A step card's material the player gets themselves carries a waypoint pin to the nearest
-- place to get it (owner, 2026-11-27: Green Whelp Bracers at Leatherworking 165, "I want to
-- be able to click Green Whelp Scale with a waypoint icon and have it navigate me to it").
-- Real data: Adolescent Whelp (34-35) and Dreaming Whelp (35-36) skin Green Whelp Scale at
-- 20.9% and 19.3% (cMaNGOS skinning loot 740 and 741). Skinning a level 34 corpse takes 170.
-- The maps fixture's zone rectangles overlap at Deadwind Pass, Swamp of Sorrows and the
-- Blasted Lands, so each zone keeps the spawns its data lists (MapPosZone answers the zone).

local CP = ProfLost
local G, Farm, GT = CP.Gather, CP.Farm, CP.GuideTab
local LW, SKIN = 165, 393
local SWAMP, DEADWIND, BLASTED, DUSKWOOD, DUSTWALLOW = 1435, 1430, 1419, 1431, 1445
local SCALE, HEAVY, SILKEN = 7392, 4234, 4291
local BRACERS = 9202
local WHELPS = { ["Adolescent Whelp"] = true, ["Dreaming Whelp"] = true }

local function stand(zone, level, side, x, y)
    MapWorld.begin({ zone = zone, x = x or 0.5, y = y or 0.5, level = level, side = side or "Horde" })
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    G.ResetClusters()
end

local function creatures(place)
    local out = {}
    for name in pairs(place.spot.about) do out[#out + 1] = name end
    table.sort(out)
    return out
end

T.test("Swamp of Sorrows, Skinning 175, level 38: the whelps there", function()
    stand(SWAMP, 38)
    local place = Farm.Nearest(SCALE, { skills = { [SKIN] = 175 } })
    T.ok(place ~= nil, "a place is found")
    if not place then return end
    T.eq(place.zone, SWAMP, "the player's own zone wins")
    T.eq(place.kind, "mob")
    for _, name in ipairs(creatures(place)) do T.ok(WHELPS[name], "a whelp: " .. name) end
    T.ok(place.chance > 19 and place.chance < 21, "about 20%: " .. place.chance)
    T.eq(place.low, 34)
end)

-- Each whelp zone's own best spot, as the finder picks it for a player standing there.
local function ownSpot(zone)
    local was = G.PlayerZone
    World.set(G, "PlayerZone", function() return zone end)
    local place = Farm.Nearest(SCALE, { skills = { [SKIN] = 175 } })
    World.set(G, "PlayerZone", was)
    return place
end

T.test("Duskwood, no whelps: the nearest of the whelp zones' spots", function()
    stand(DUSKWOOD, 38)
    local place = Farm.Nearest(SCALE, { skills = { [SKIN] = 175 } })
    T.ok(place ~= nil, "a place is found")
    if not place then return end
    T.ok(place.zone ~= DUSKWOOD, "not Duskwood")
    local got = CP.Waypoint.Yards(place.zone, place.x, place.y)
    for _, zone in ipairs({ DEADWIND, SWAMP, BLASTED }) do
        local other = ownSpot(zone)
        T.ok(other and other.zone == zone, "the whelps of " .. zone)
        if other then
            T.ok(got <= CP.Waypoint.Yards(zone, other.x, other.y) + 1e-6, "no farther than the spot in " .. zone)
        end
    end
end)

T.test("another continent: still the whelps across the sea", function()
    stand(DUSTWALLOW, 38, "Alliance")
    local place = Farm.Nearest(SCALE, { skills = { [SKIN] = 175 } })
    T.ok(place and (place.zone == DEADWIND or place.zone == SWAMP or place.zone == BLASTED),
        "a whelp zone: " .. tostring(place and place.zone))
end)

T.test("level gate: the whelps are reachable from level 31", function()
    stand(SWAMP, 30)
    local place, why = Farm.Nearest(SCALE, { skills = { [SKIN] = 175 } })
    T.eq(place, nil, "level 30 is too low for a level 34 whelp")
    T.eq(why and why.kind, "level")
    T.eq(why and why.need, 31)
    T.eq(GT.NavWhy(why), "Needs level 31. Adolescent Whelp is too high for you yet.")
    MapWorld.SetLevel(31)
    T.ok(Farm.Nearest(SCALE, { skills = { [SKIN] = 175 } }) ~= nil, "level 31 reaches them")
end)

T.test("skill gate: Skinning 170 skins the level 34 whelp only", function()
    stand(SWAMP, 38)
    local place, why = Farm.Nearest(SCALE, { skills = { [SKIN] = 165 } })
    T.eq(place, nil, "Skinning 165 skins no whelp")
    T.eq(why and why.kind, "skill")
    T.eq(why and why.need, 170)
    T.eq(GT.NavWhy(why), "Needs Skinning 170 for Adolescent Whelp. You have 165.")
    place = Farm.Nearest(SCALE, { skills = { [SKIN] = 170 } })
    T.ok(place ~= nil, "Skinning 170 finds a place")
    if not place then return end
    T.eq(table.concat(creatures(place), ","), "Adolescent Whelp", "the level 35 Dreaming Whelp needs 175")
    T.eq(place.chance, 20.9)
end)

T.test("no Skinning, a vendor good: nothing to gather", function()
    T.eq(Farm.Gatherable(SCALE, {}), false, "the scale is skinned")
    T.eq(Farm.Gatherable(SCALE, { [SKIN] = 1 }), true, "any Skinning rank shows the way")
    T.eq(Farm.Gatherable(SILKEN, { [SKIN] = 300 }), false, "Silken Thread is bought")
    stand(SWAMP, 38)
    local place, why = Farm.Nearest(SILKEN, { skills = { [SKIN] = 300 } })
    T.eq(place, nil)
    T.eq(why, nil, "no source, no reason")
end)

T.test("cloth: the Gathering panel's best cloth spot, or the level that reaches one", function()
    MapWorld.begin({ zone = 1436, level = 15, side = "Alliance" })
    T.eq(Farm.Gatherable(2589, {}), true, "anyone loots cloth")
    local place = Farm.Nearest(2589, { skills = {} })
    T.ok(place and place.zone == 1436, "Linen Cloth in Westfall")
    if place then
        local best = G.Cloth(1436, 2589, 15, "Alliance").spots[1]
        T.ok(place.x == best.x and place.y == best.y, "the panel's first cloth spot")
        T.ok(GT.NavText(place, 2589):find("^Level %d+%-%d+ .+, Westfall, about [%d.]+ a kill$"), GT.NavText(place, 2589))
    end
    local none, why = Farm.Nearest(14047, { skills = {} })
    T.eq(none, nil, "no Runecloth at level 15")
    T.eq(why and why.kind, "level")
    T.ok(why and why.need > 15, "a higher level reaches it: " .. tostring(why and why.need))
end)

-- The Green Whelp Bracers card, as the owner saw it: Leatherworking 165, standing in the Swamp.
local function card(skin, level)
    stand(SWAMP, level or 38)
    local profs = { [LW] = { rank = 165, max = 225 } }
    if skin then profs[SKIN] = { rank = skin, max = 225 } end
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.begin({ professions = profs })
    CraftWorld.Learn(LW, BRACERS)
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    local row
    for _, r in ipairs(GT.ui.rows or {}) do
        if r.spell == BRACERS and not r.side then row = r end
    end
    T.ok(row ~= nil, "the guide has Green Whelp Bracers at 165")
    if not row then return nil end
    GT.Pick(row)
    local lines = {}
    for _, line in ipairs(GT.ui.details.rows) do
        if line:IsShown() and line.itemID then lines[line.itemID] = line end
    end
    return lines
end

local function captured()
    local out = { waypoints = {}, chat = {}, tip = {} }
    World.patch("C_Map.CanSetUserWaypointOnMap", function() return true end)
    World.patch("C_Map.SetUserWaypoint", function(p) out.waypoints[#out.waypoints + 1] = p end)
    World.patch("C_SuperTrack.SetSuperTrackedUserWaypoint", function() end)
    World.set(CP, "Print", function(_, msg) out.chat[#out.chat + 1] = msg end)
    World.patch("GameTooltip.SetText", function(_, text) out.tip[#out.tip + 1] = text end)
    World.patch("GameTooltip.AddLine", function(_, text) out.tip[#out.tip + 1] = text end)
    return out
end

T.test("card: Green Whelp Scale and Heavy Leather carry a pin, Silken Thread none", function()
    local lines = card(175)
    if not lines then return end
    T.ok(lines[SCALE] and lines[SCALE].pin:IsShown(), "Green Whelp Scale has a pin")
    T.ok(lines[HEAVY] and lines[HEAVY].pin:IsShown(), "Heavy Leather has a pin")
    T.ok(lines[SILKEN] and not lines[SILKEN].pin:IsShown(), "Silken Thread has no pin")
end)

T.test("card: the pin and the row set a waypoint to the whelps", function()
    local lines = card(175)
    if not lines then return end
    local out = captured()
    local want = Farm.Nearest(SCALE)
    T.ok(want and want.zone == SWAMP, "the whelps of the Swamp")
    if not want then return end
    CraftWorld.Press(lines[SCALE].pin)
    T.eq(#out.waypoints, 1, "the pin set a waypoint")
    local p = out.waypoints[1]
    T.eq(p and p.uiMapID, SWAMP)
    local x, y = p.position:GetXY()
    T.ok(math.abs(x - want.x) < 1e-9 and math.abs(y - want.y) < 1e-9, "at the spot")
    lines[SCALE]:GetScript("OnMouseUp")(lines[SCALE], "LeftButton")
    T.eq(#out.waypoints, 2, "a click on the row sets it too")
    lines[SILKEN]:GetScript("OnMouseUp")(lines[SILKEN], "LeftButton")
    T.eq(#out.waypoints, 2, "Silken Thread's row sets none")
    lines[SCALE].pin:GetScript("OnEnter")(lines[SCALE].pin)
    T.ok(out.tip[1] and out.tip[1]:find("^Level 34%-36 %a+ Whelp, Swamp of Sorrows, 20%% Green Whelp Scale$"),
        "the tip says where: " .. tostring(out.tip[1]))
end)

T.test("card: at Skinning 165 the pin says why and sets nothing", function()
    local lines = card(165)
    if not lines then return end
    local out = captured()
    T.ok(lines[SCALE].pin:IsShown(), "the pin still shows: the player has Skinning")
    lines[SCALE].pin:GetScript("OnEnter")(lines[SCALE].pin)
    T.eq(out.tip[1], "Needs Skinning 170 for Adolescent Whelp. You have 165.")
    CraftWorld.Press(lines[SCALE].pin)
    T.eq(#out.waypoints, 0, "no waypoint")
    T.eq(out.chat[1], "Needs Skinning 170 for Adolescent Whelp. You have 165.")
end)

T.test("card: without Skinning no material has a pin", function()
    local lines = card(nil)
    if not lines then return end
    T.ok(lines[SCALE] and not lines[SCALE].pin:IsShown(), "no pin on Green Whelp Scale")
    T.ok(lines[HEAVY] and not lines[HEAVY].pin:IsShown(), "no pin on Heavy Leather")
end)
