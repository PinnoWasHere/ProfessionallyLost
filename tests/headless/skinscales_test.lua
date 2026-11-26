-- Skinning grind spots carry every skinned material, not only leather. A minor material
-- (scales, hides: typical chance under Gather.SKIN_MIN_CHANCE) counts at Gather.SkinFloor.
-- Real data case: Swamp of Sorrows, where Adolescent Whelp (34-35) and Dreaming Whelp
-- (35-36) skin Green Whelp Scale at 20.9% and 19.3% (cMaNGOS skinning loot 740 and 741).
-- Horde, Skinning 289, level 36.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local SKIN, LW = 393, 165
local SWAMP = 1435
local SCALE, MEDIUM, HEAVY, MEDIUM_HIDE, HEAVY_HIDE = 7392, 2319, 4234, 4232, 4235

local function scene(mode, needs, act)
    MapWorld.begin({ zone = SWAMP, x = 0.5, y = 0.5, level = 36, side = "Horde", shareSolves = true })
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.db, "routeMode", mode)
    World.set(CP.db, "skinSkip", nil)
    World.set(CP.db, "gatherClosed", nil)
    World.set(CP.db, "farmClosed", nil)
    World.set(CP.charDB, "gatherNeeds", needs and { [LW] = needs } or nil)
    World.set(CP.charDB, "gatherSoon", needs and { [LW] = needs } or nil)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN then return { skillID = id, rank = 289, modifier = 0, maxRank = 300 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.GatherPanel, "Showing", function() return true end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    GL.SetPanelProf(nil)
    G.ResetClusters()
    RM.Forget()
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
        G.ResetClusters()
    end)
    act()
end

local function settled()
    GL.Refresh()
    local frames = 0
    repeat
        T.advance(0.05, 0.05)
        frames = frames + 1
    until not (CP.GatherGuide.Warming() or RM.Solving() or RM.Passing()) or frames > 8000
    GL.Refresh()
    return (GL.Drawn())
end

-- The skinning route rows of the Swamp: { [itemID] = { [creature name] = chance } }.
local function skinRows()
    local out = {}
    for _, r in ipairs(GL.RouteRows(SWAMP, nil, true)) do
        for _, src in ipairs(r.sources) do
            if src.kind == "mob" and src.prof == SKIN then
                out[r.itemID] = out[r.itemID] or {}
                out[r.itemID][src.name] = src.chance
            end
        end
    end
    return out
end

-- Skinning grind spot heads in the panel, and whether one carries `item` in its drops
-- and its drop-chance icons.
local function skinSpots(lines)
    local out, on = {}, false
    for _, l in ipairs(lines) do
        if l.kind == "section" then on = l.key == SKIN
        elseif on and l.kind == "source" and l.spot then out[#out + 1] = l end
    end
    return out
end

local function showsItem(spots, item)
    local icon = GL.IconText(item, "")
    for _, l in ipairs(spots) do
        for _, a in pairs(l.spot.about) do
            if a.drops[item] and (l.info or ""):find(icon, 1, true) then return true end
        end
    end
    return false
end

T.test("the data holds the Swamp's whelps and their Green Whelp Scale", function()
    local names = {}
    for entry in pairs(CP.GatherData.zones[SWAMP].mobs) do
        local m = CP.GatherData.mobs[entry]
        if m and (m[1] == "Adolescent Whelp" or m[1] == "Dreaming Whelp") then
            local loot = G.SkinLoot(entry)
            for _, l in ipairs(loot or {}) do
                if l[1] == SCALE then names[m[1]] = l[2] end
            end
        end
    end
    T.ok(names["Adolescent Whelp"] and names["Adolescent Whelp"] < 35, tostring(names["Adolescent Whelp"]))
    T.ok(names["Dreaming Whelp"] and names["Dreaming Whelp"] < 35, tostring(names["Dreaming Whelp"]))
end)

T.test("a leather keeps the 35% floor; scales and hides count lower", function()
    T.eq(G.SkinFloor(MEDIUM), 35)
    T.eq(G.SkinFloor(HEAVY), 35)
    T.ok(G.SkinFloor(SCALE) < 19.3, "both whelps clear it: " .. G.SkinFloor(SCALE))
    T.ok(G.SkinFloor(HEAVY_HIDE) < 5, "Heavy Hide: " .. G.SkinFloor(HEAVY_HIDE))
    T.ok(G.SkinFloor(MEDIUM_HIDE) < 5, "Medium Hide: " .. G.SkinFloor(MEDIUM_HIDE))
end)

T.test("Farm: the whelps are Green Whelp Scale sources and hides are listed", function()
    scene("farm", nil, function()
        local rows = skinRows()
        T.ok(rows[SCALE] and rows[SCALE]["Adolescent Whelp"] and rows[SCALE]["Dreaming Whelp"],
            "both whelps skin the scale")
        T.ok(rows[MEDIUM_HIDE] or rows[HEAVY_HIDE], "a hide is listed")
        local menu = {}
        for _, m in ipairs(G.SkinMaterials(SWAMP, G.Skills())) do menu[m.item] = true end
        T.ok(menu[SCALE], "the Farm menu lists Green Whelp Scale")
    end)
end)

T.test("Farm: every material ticked, the spots' drop chances show the hides too", function()
    scene("farm", nil, function()
        local spots = skinSpots(settled())
        T.ok(#spots > 0, "Skinning spots drawn")
        T.ok(showsItem(spots, MEDIUM_HIDE) or showsItem(spots, HEAVY_HIDE), "a spot shows a hide")
    end)
end)

T.test("Farm: Green Whelp Scale ticked alone, the spots are the whelps'", function()
    scene("farm", nil, function()
        local skip = {}
        for _, m in ipairs(G.SkinMaterials(SWAMP, G.Skills())) do
            if m.item ~= SCALE then skip[m.item] = true end
        end
        World.set(CP.db, "skinSkip", skip)
        local spots = skinSpots(settled())
        T.ok(#spots > 0, "Skinning spots drawn")
        for _, l in ipairs(spots) do
            T.ok(showsItem({ l }, SCALE), "the spot's drop chances show Green Whelp Scale: " .. tostring(l.info))
        end
    end)
end)

T.test("Follow the guide: 60 Green Whelp Scale needed builds whelp grind spots", function()
    scene(nil, { [SCALE] = 60 }, function()
        local rows = skinRows()
        T.ok(rows[SCALE] and rows[SCALE]["Adolescent Whelp"], "the scale is routed")
        local needed
        for _, r in ipairs(G.Rows(SWAMP, G.Skills(), G.Needs(), function() return 0 end, function() return "" end,
            GL.ZONE_OPTS)) do
            if r.itemID == SCALE then needed = r end
        end
        T.ok(needed and GL.Listed(needed), "the checklist lists the scale with its whelps")
        local spots = skinSpots(settled())
        T.ok(showsItem(spots, SCALE), "a spot's drop chances show Green Whelp Scale")
    end)
end)

T.test("a common leather keeps the 35% rule", function()
    scene("farm", nil, function()
        local rows = skinRows()
        for name, chance in pairs(rows[MEDIUM] or {}) do T.ok(chance >= 35, name .. " " .. chance) end
        for name, chance in pairs(rows[HEAVY] or {}) do T.ok(chance >= 35, name .. " " .. chance) end
    end)
end)
