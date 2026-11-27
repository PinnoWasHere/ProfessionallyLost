-- The gathering panel lists the map's own grind spots: the same spots under the same
-- numbers, each naming its creatures and levels. Farm lists no guide item. Follow the
-- guide lists the guide's items, a hide too, though no creature here skins it often. Scene:
-- Stonetalon's Charred Vale, Skinning 233, the guide short of Heavy Leather.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local SKIN, STONETALON, DESOLACE = 393, 1442, 1443
local HEAVY_LEATHER, HEAVY_HIDE, MEDIUM = 4234, 4235, 2319

local function scene(mode, act)
    MapWorld.begin({ zone = STONETALON, x = 0.33, y = 0.68, level = 30, side = "Horde", shareSolves = true })
    local was = { CP.db.otherZones, CP.db.route, CP.db.routeMode }
    CP.db.route, CP.db.otherZones, CP.db.routeMode = true, true, mode
    CP.charDB.gatherNeeds = { [165] = { [HEAVY_LEATHER] = 319, [HEAVY_HIDE] = 20, [MEDIUM] = 50 } }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN then return { skillID = id, rank = 233, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 3 end)
    World.set(CP.GatherPanel, "Showing", function() return true end)
    local mapPos, replan = CP.Waypoint.MapPosZone, G.UpdateAllNeeds
    G.UpdateAllNeeds = function() end
    CP.Waypoint.MapPosZone = function(z) return z end
    G.ResetClusters()
    local ok, err = pcall(act)
    CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.charDB.gatherNeeds = false, nil, nil, nil
    RM.Update(false, {})
    T.advance(1)
    CP.Waypoint.MapPosZone, G.UpdateAllNeeds = mapPos, replan
    G.ResetClusters()
    -- Set back last: a redraw with the route on under this scene's map answers would cache them.
    CP.db.otherZones, CP.db.route, CP.db.routeMode = was[1], was[2], was[3]
    T.ok(ok, err)
end

-- The list after the zone's solve and the other zones' pass have ended.
local function settled()
    GL.Refresh()
    for _ = 1, 60 do
        T.advance(1)
        if not RM.ZonesReport()[1]:find("running", 1, true) then break end
    end
    T.advance(1)
    return (GL.Drawn())
end

local function spotLines(lines)
    local out = {}
    for _, l in ipairs(lines) do
        if l.kind == "source" and l.spot then out[#out + 1] = l end
    end
    return out
end

T.test("Farm: the panel lists the map's grind spots under the map's numbers", function()
    scene("farm", function()
        local lines = settled()
        local spots, zone = RM.Spots()
        T.eq(zone, STONETALON)
        T.ok(#spots > 0, "the map has grind spots")
        local listed = spotLines(lines)
        T.eq(#listed, #spots, "one row a spot, drawn without another refresh")
        for i, l in ipairs(listed) do
            T.eq(l.spot, spots[i], "row " .. i .. " is the map's spot " .. i)
            T.eq(l.rank, ("#%d"):format(spots[i].rank))
            local low, high = math.huge, 0
            for _, a in pairs(spots[i].about) do low, high = math.min(low, a.minLevel), math.max(high, a.maxLevel) end
            T.eq(l.text, low == high and ("Level %d"):format(low) or ("Level %d-%d"):format(low, high),
                "the spot's whole level range, no creature name")
            T.eq(l.info, nil, "the chances sit on their own line, not beside the header")
            T.eq(l.tip, nil, "no hover text: the panel holds it")
            T.ok(l.pin ~= nil, "a waypoint")
        end
    end)
end)

T.test("Follow the guide: the same rows for the spots that mode draws", function()
    scene(nil, function()
        local lines = settled()
        local spots = RM.Spots()
        local listed = spotLines(lines)
        T.eq(#listed, #spots)
        for i, l in ipairs(listed) do T.eq(l.spot, spots[i]) end
    end)
end)


-- The guide items listed: cloth rows are Farm's sellable cloth, no guide item (cloth_test.lua).
local function itemIDs(lines)
    local ids = {}
    for _, l in ipairs(lines) do
        if l.kind == "item" and not l.cloth then ids[l.row.itemID] = true end
    end
    return ids
end

T.test("Farm lists no guide item; Follow the guide lists a hide from the creatures that yield it most", function()
    scene("farm", function()
        local lines = settled()
        T.eq(itemIDs(lines), {}, "Farm: grind spots only")
        for _, l in ipairs(lines) do
            T.ok(not (l.kind == "section" and (l.key == "next" or l.key == G.FISHING)),
                "no Next up, no fishing plan: " .. tostring(l.text))
        end
    end)
    scene(nil, function()
        local ids = itemIDs(settled())
        T.ok(ids[MEDIUM], "Medium Leather drops often in Stonetalon")
        T.ok(ids[HEAVY_HIDE], "Heavy Hide is listed though no creature here skins it at 35%")
        for _, l in ipairs(GL.Drawn()) do
            T.ok(not (l.text or ""):find("Rare here", 1, true), "no line about it either")
        end
    end)
end)

T.test("Farm lists the herbs and ore the loop visits", function()
    scene("farm", function()
        local lines = GL.NodeLines(STONETALON, { [182] = 150, [186] = 150 })
        T.ok(#lines > 0, "Stonetalon has herbs and ore")
        local last = 0
        for _, l in ipairs(lines) do
            T.ok(l.prof == 182 or l.prof == 186)
            T.ok(l.skill >= last and l.skill <= 150, "gatherable now, lowest skill first")
            last = l.skill
            T.ok(l.info:find("^skill %d+ · %d+ nodes?$") ~= nil, l.info)
        end
    end)
end)

T.test("a click opens a grind spot: each creature with its levels and drop chances", function()
    scene("farm", function()
        settled()
        local lines, rows, offset = GL.Drawn()
        local hit
        for i, r in ipairs(rows) do
            local l = r:IsShown() and lines[offset + i]
            if l and l.kind == "source" and l.spot then hit = r break end
        end
        T.ok(hit ~= nil, "a grind spot row is drawn")
        local spot = hit.line.spot
        T.eq(hit.line.fold, false, "closed at first")
        local function under()
            local out, at = {}, nil
            for _, l in ipairs((GL.Drawn())) do
                if l.spot == spot then at = l end
                if at and l.spotOf == at and l.creature then out[#out + 1] = l end
            end
            return out
        end
        T.eq(#under(), 0, "closed: no creature lines under it")
        hit:GetScript("OnClick")(hit)
        T.ok(GL.SpotOpen(STONETALON, spot), "open")
        local opened = under()
        local kinds = 0
        for _ in pairs(spot.parts) do kinds = kinds + 1 end
        T.eq(#opened, kinds, "one line a creature")
        for _, l in ipairs(opened) do
            T.eq(l.text, l.creature, "the creature's name")
            T.ok(spot.parts[l.creature] ~= nil and l.info:find("^%d+") ~= nil, "its levels beside it: " .. tostring(l.info))
        end

        -- Every row of the hovered spot lights, and none stays lit after.
        local lit = {}
        local _, rows2 = GL.Drawn()
        for _, r in ipairs(rows2) do
            World.set(r, "LockHighlight", function(self) lit[self] = true end)
            World.set(r, "UnlockHighlight", function(self) lit[self] = nil end)
        end
        local head
        for _, r in ipairs(rows2) do
            if r:IsShown() and r.line.spot == spot then head = r end
        end
        head:GetScript("OnEnter")(head)
        local count = 0
        for r in pairs(lit) do
            count = count + 1
            T.eq(r.line.spotOf, head.line, "only the spot's own rows")
        end
        T.eq(count, kinds + 1, "the chances line and each creature row light with the hovered first row")
        head:GetScript("OnLeave")(head)
        T.eq(next(lit), nil, "none after the mouse leaves")

        opened[1].click()
        T.ok(not GL.SpotOpen(STONETALON, spot), "a click on a creature line closes it")
    end)
end)

T.test("the solve's end asks for one rebuild per change of spots, whoever builds the lines", function()
    scene("farm", function()
        settled()
        local asked = 0
        World.set(GL, "Changed", function() asked = asked + 1 end)
        -- A list builder that never notes the spots it drew (fishing_test swaps one in).
        World.set(GL, "spotSig", "stale")
        GL.RouteSolved()
        GL.RouteSolved()
        GL.RouteSolved()
        T.eq(asked, 1, "one rebuild, not one per call")
    end)
end)

T.test("a spot's chance is the average over its creatures, a creature without the drop counting 0", function()
    local spot = { parts = { Stormer = 2, Courser = 1 }, about = {
        Stormer = { minLevel = 18, maxLevel = 19, drops = { [2318] = 72 } },
        Courser = { minLevel = 22, maxLevel = 23, drops = { [2318] = 44, [2319] = 49 } } } }
    T.eq(GL.SpotLevels(spot), "Level 18-23")
    T.eq(GL.SpotChances(spot), GL.IconText(2318, "58%") .. "  " .. GL.IconText(2319, "25%"))
end)

T.test("a source row with hover lines shows them", function()
    local shown = {}
    World.set(GameTooltip, "SetOwner", function() end)
    World.set(GameTooltip, "SetText", function(_, t) shown[#shown + 1] = t end)
    World.set(GameTooltip, "AddLine", function(_, t) shown[#shown + 1] = t end)
    World.set(GameTooltip, "Show", function() end)
    scene(nil, function()
        settled()
        local lines, rows, offset = GL.Drawn()
        local item
        for i, r in ipairs(rows) do
            local l = r:IsShown() and lines[offset + i]
            if l and l.kind == "item" then item = r break end
        end
        T.ok(item ~= nil, "a guide item is drawn")
        item:GetScript("OnClick")(item)
        lines, rows, offset = GL.Drawn()
        local hit
        for i, r in ipairs(rows) do
            local l = r:IsShown() and lines[offset + i]
            if l and l.kind == "source" and not l.spot and l.tip then hit = r break end
        end
        T.ok(hit ~= nil, "its sources are drawn")
        hit:GetScript("OnEnter")(hit)
        T.eq(shown, hit.line.tip)
        item:GetScript("OnClick")(item)
    end)
end)

T.test("Farm: every grind spot shows its drop chances on a second line, whatever their count", function()
    scene("farm", function()
        local lines = settled()
        local spots = RM.Spots()
        T.ok(#spots > 0, "spots to check")
        for i, spot in ipairs(spots) do
            local chances = GL.SpotChances(spot)
            local at
            for j, l in ipairs(lines) do
                if l.spot == spot then at = j end
            end
            T.ok(at ~= nil, "spot " .. i .. " is drawn")
            local head, under = lines[at], lines[at + 1]
            T.eq(head.info, nil, "spot " .. i .. ": nothing in the right column")
            T.eq(under and under.text, chances, "spot " .. i .. ": its chances on the next line")
            T.eq(under and under.spotOf, head, "spot " .. i .. ": that line belongs to the spot")
            T.eq(under and under.indent, 56, "spot " .. i .. ": indented like a wrapped info")
            local twice = 0
            for _, l in ipairs(lines) do
                if l.spotOf == head and l.text == chances then twice = twice + 1 end
            end
            T.eq(twice, 1, "spot " .. i .. ": the chances show once")
        end
    end)
end)
