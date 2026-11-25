-- Grind spots on the continent map: each spot gets a zone-map pin and a continent-map pin,
-- the second placed by the game's world transforms (Waypoint.OnContinent), never by
-- HereBeDragons' zone-to-continent translation. Route lines on the continent follow the
-- same transform. /proflost pins prints both placements. Ruined Leather Scraps is never a
-- skinning material.

local CP = ProfLost
local RM, W = CP.RouteMap, CP.Waypoint
local HBD = LibStub("HereBeDragons-2.0")
local KALIMDOR, DUROTAR, BARRENS = 1414, 1411, 1413
local RUINED = 2934

-- Where a point of `zone`'s map sits on its continent map, from the fixture's rectangles
-- alone (tests/fixtures/maps.lua): { name, parent, type, instance, minX, minY, maxX, maxY }.
local function expected(zone, x, y)
    local z, c = WorldData.maps[zone], WorldData.maps[KALIMDOR]
    local wx = z[7] - y * (z[7] - z[5])
    local wy = z[8] - x * (z[8] - z[6])
    return (c[8] - wy) / (c[8] - c[6]), (c[7] - wx) / (c[7] - c[5])
end

local function near(a, b) return math.abs(a - b) < 1e-6 end

local function showMap(id)
    World.set(WorldMapFrame, "GetMapID", function() return id end)
    World.set(WorldMapFrame, "IsShown", function() return true end)
    for provider in pairs(WorldMapFrame.dataProviders or {}) do
        if type(provider) == "table" and provider.OnMapChanged then provider:OnMapChanged() end
    end
end

-- Scene: Durotar, level 20 Horde, skinning and mining needs, other zones on. `act(seen)`
-- runs with every world map pin registration in `seen`.
local function scene(act)
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = 20, side = "Horde", shareSolves = true })
    local was = { CP.db.otherZones, CP.db.route }
    CP.db.route, CP.db.otherZones = true, true
    CP.charDB.gatherNeeds = { [165] = { [2318] = 200 }, [164] = { [2771] = 100 } }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == 393 or id == 186 then return { skillID = id, rank = 120, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local mapPos, replan = W.MapPosZone, CP.Gather.UpdateAllNeeds
    CP.Gather.UpdateAllNeeds = function() end
    W.MapPosZone = function(z) return z end
    CP.Gather.ResetClusters()
    local pins = LibStub("HereBeDragons-Pins-2.0")
    local seen = {}
    local addW = pins.AddWorldMapIconMap
    pins.AddWorldMapIconMap = function(self, ref, icon, z, x, y, flag, ...)
        -- Pool frames are reused by the next redraw, so the spot is read now.
        seen[#seen + 1] = { zone = icon.zone, spot = icon.spot, map = z, x = x, y = y, flag = flag }
        return addW(self, ref, icon, z, x, y, flag, ...)
    end
    local ok, err = pcall(act, seen)
    CP.db.otherZones, CP.db.route = false, false
    RM.Update(false, {})
    T.advance(1)
    pins.AddWorldMapIconMap = addW
    W.MapPosZone, CP.Gather.UpdateAllNeeds = mapPos, replan
    CP.Gather.ResetClusters()
    -- Set back last: a redraw with the route on under this scene's map answers would cache them.
    CP.db.otherZones, CP.db.route = was[1], was[2]
    T.ok(ok, err)
end

local function draw()
    CP.GatherList.RouteOnly()
    T.advance(5)
end

T.test("a zone point lands on its continent where the fixture's rectangles put it", function()
    MapWorld.begin({ zone = DUROTAR })
    for _, zone in ipairs({ DUROTAR, BARRENS }) do
        for _, p in ipairs({ { 0, 0 }, { 0.5, 0.5 }, { 0.25, 0.8 }, { 1, 1 } }) do
            local top, cx, cy = W.OnContinent(zone, p[1], p[2])
            local ex, ey = expected(zone, p[1], p[2])
            T.eq(top, KALIMDOR, "on Kalimdor")
            T.ok(near(cx, ex) and near(cy, ey), ("%d at %.2f, %.2f: %.4f, %.4f, want %.4f, %.4f")
                :format(zone, p[1], p[2], cx, cy, ex, ey))
        end
    end
    local _, dx, dy = W.OnContinent(DUROTAR, 0.5, 0.5)
    local _, bx, by = W.OnContinent(BARRENS, 0.5, 0.5)
    T.ok(math.abs(dx - bx) > 0.01 or math.abs(dy - by) > 0.01, "two zones' middles are apart on the continent")
    T.eq(W.OnContinent(KALIMDOR, 0.5, 0.5), nil, "a continent has no continent above it")
    T.eq(W.OnContinent(999999, 0.5, 0.5), nil, "an unknown map has none")
end)

T.test("every grind spot gets a zone pin and a continent pin at the game's position", function()
    scene(function(seen)
        draw()
        T.ok(#RM.Others() >= 3, "other zones solved: " .. table.concat(RM.Others(), ","))
        local zonePins, contPins, spotsAt = {}, {}, {}
        for _, s in ipairs(seen) do
            if s.spot then
                T.eq(s.flag, nil, "a grind pin shows only on the map it is registered on")
                if s.map == s.zone then
                    zonePins[s.zone] = (zonePins[s.zone] or 0) + 1
                    T.eq(s.x, s.spot.x)
                    T.eq(s.y, s.spot.y)
                else
                    T.eq(s.map, KALIMDOR, "the continent pin sits on the continent map")
                    contPins[s.zone] = (contPins[s.zone] or 0) + 1
                    local ex, ey = expected(s.zone, s.spot.x, s.spot.y)
                    T.ok(near(s.x, ex) and near(s.y, ey), ("zone %d spot %d at %.4f, %.4f, want %.4f, %.4f")
                        :format(s.zone, s.spot.rank or 0, s.x, s.y, ex, ey))
                    spotsAt[#spotsAt + 1] = { zone = s.zone, x = s.x, y = s.y }
                end
            elseif s.map == KALIMDOR then
                T.ok(false, "no route stop on the continent map")
            end
        end
        for zone, n in pairs(zonePins) do
            T.eq(contPins[zone], n, "zone " .. zone .. ": one continent pin per zone pin")
        end
        T.ok((zonePins[DUROTAR] or 0) > 0 and (zonePins[BARRENS] or 0) > 0, "Durotar and the Barrens drawn")
        -- Each continent pin sits inside its own zone's box on the continent, and the zones'
        -- pins don't collapse onto one place. Zone rectangles overlap (Durotar's west edge
        -- lies in Mulgore's), so two zones may share a spot there.
        local places, zones = {}, {}
        for _, a in ipairs(spotsAt) do
            local x0, y0 = expected(a.zone, 0, 0)
            local x1, y1 = expected(a.zone, 1, 1)
            T.ok(a.x >= x0 - 1e-9 and a.x <= x1 + 1e-9 and a.y >= y0 - 1e-9 and a.y <= y1 + 1e-9,
                ("zone %d's pin at %.4f, %.4f is outside its box"):format(a.zone, a.x, a.y))
            places[("%.4f,%.4f"):format(a.x, a.y)] = true
            zones[a.zone] = true
        end
        local nPlaces, nZones = 0, 0
        for _ in pairs(places) do nPlaces = nPlaces + 1 end
        for _ in pairs(zones) do nZones = nZones + 1 end
        T.ok(nZones >= 3 and nPlaces >= nZones, ("%d zones on %d places"):format(nZones, nPlaces))
    end)
end)

T.test("route lines on the continent map follow the game's transform", function()
    scene(function()
        draw()
        T.ok(CP.RouteLines.Has(DUROTAR) and CP.RouteLines.Has(BARRENS), "loops kept")
        -- HereBeDragons' translation is not asked.
        World.set(HBD, "TranslateZoneCoordinates", function() error("HereBeDragons asked") end)
        showMap(BARRENS)
        local zoneLines = CP.RouteLines.Counts()
        T.ok(zoneLines > 0, "the Barrens' map has lines")
        showMap(KALIMDOR)
        local continentLines = CP.RouteLines.Counts()
        T.ok(continentLines > zoneLines, ("continent %d lines, Barrens %d"):format(continentLines, zoneLines))
        showMap(1415)
        T.eq((CP.RouteLines.Counts()), 0, "the Eastern Kingdoms map has none")
    end)
end)

T.test("/proflost zones counts each zone's continent pins", function()
    scene(function()
        World.set(HBD, "GetWorldCoordinatesFromZone", function(_, x, y, z) return x * 1000 + z, y * 1000, 1 end)
        draw()
        local pins, onContinent = RM.PinsByZone()
        local spots, here = RM.Spots()
        T.eq(pins[here], #spots, "zone pins")
        T.eq(onContinent[here], #spots, "continent pins")
        local text = table.concat(RM.ZonesReport(), "\n")
        T.ok(text:find(("Durotar %%(1411, yours%%): %%d+ rows, %%d+ grind spots, %d pins drawn, %d on the continent")
            :format(#spots, #spots)), text)
    end)
end)

T.test("/proflost pins prints spot 1 of each zone: zone, HereBeDragons and the game's continent spot", function()
    scene(function()
        draw()
        World.set(HBD, "TranslateZoneCoordinates", function(_, x, y) return 0.5, 0.5 end)
        local before = #T.prints()
        SlashCmdList.PROFLOST("pins")
        local out = {}
        for i = before + 1, #T.prints() do out[#out + 1] = tostring(T.prints()[i]) end
        local text = table.concat(out, "\n")
        T.ok(text:find("pins: world map ", 1, true), text)
        local spots = RM.Spots()
        local s = spots[1]
        local cx, cy = expected(DUROTAR, s.x, s.y)
        local want = ("Durotar (1411) spot 1 at %.1f, %.1f: HBD 50.0, 50.0; C_Map %.1f, %.1f on Kalimdor (1414)")
            :format(s.x * 100, s.y * 100, cx * 100, cy * 100)
        T.ok(text:find(want, 1, true), want .. "\n" .. text)
        T.ok(text:find("The Barrens (1413) spot 1 at ", 1, true), text)
        T.ok(text:find("Kalimdor %(1414%): HBD [%w]+ yd on instance [%w]+, C_Map 36800x24533 yd on instance 1"), text)
        local withSpots = 0
        for _, line in ipairs(RM.ZonesReport()) do
            if line:find(", [1-9]%d* grind spots") then withSpots = withSpots + 1 end
        end
        T.ok(withSpots >= 3, "zones with spots: " .. withSpots)
        T.ok(#out >= 2 + withSpots, "a line per zone with spots")
    end)
end)

T.test("Ruined Leather Scraps is never a skinning material or a grind spot's", function()
    scene(function()
        CP.db.routeMode = "farm"
        local ok, err = pcall(function()
            for _, zone in ipairs({ DUROTAR, BARRENS, 1412 }) do
                for _, m in ipairs(CP.Gather.SkinMaterials(zone, { [393] = 1 })) do
                    T.ok(m.item ~= RUINED, "zone " .. zone .. " lists Ruined Leather Scraps")
                end
                for _, r in ipairs(CP.Gather.SkinRows(zone, { [393] = 300 }, {
                        { itemID = RUINED, need = 20, have = 0 } })) do
                    T.ok(r.itemID ~= RUINED, "zone " .. zone .. " has a Ruined Leather Scraps row")
                end
            end
            T.ok(CP.Gather.SKIN_EXCLUDE[RUINED], "on the exclusion list")
            draw()
            for _, s in ipairs(RM.Spots()) do T.eq(s.items[RUINED], nil, "spot " .. (s.rank or 0)) end
        end)
        CP.db.routeMode = nil
        T.ok(ok, err)
    end)
end)
