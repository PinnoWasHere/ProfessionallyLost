-- Farm is zone-specific. Its menu lists only the leathers this zone's beasts drop, with no
-- other zone named, and its panel keeps the Skinning section, with the zone's grind spots,
-- whenever a beast the player can skin here drops a ticked leather. Nothing from another
-- zone shows (no Nearby zones section). Ticks stay saved across zones. Scene: the owner's
-- Alliance character in Arathi Highlands, Skinning 258, every leather ticked.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local SKIN, COOK, FISH = 393, 185, 356
local ARATHI, BADLANDS = 1417, 1418
local MEDIUM_LEATHER, HEAVY_LEATHER = 2319, 4234

local function scene(mode, zone, level, act)
    MapWorld.begin({ zone = zone, x = 0.5, y = 0.5, level = level, side = "Alliance", shareSolves = true })
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.db, "routeMode", mode)
    World.set(CP.db, "skinSkip", nil)
    World.set(CP.db, "gatherClosed", nil)
    World.set(CP.db, "farmClosed", nil)
    World.set(CP.charDB, "gatherNeeds", nil)
    World.set(CP.charDB, "gatherSoon", nil)
    local ranks = { [SKIN] = 258, [COOK] = 5, [FISH] = 5 }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = ranks[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
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

local function spotsOf(lines, prof)
    local out, on = {}, false
    for _, l in ipairs(lines) do
        if l.kind == "section" then on = l.key == prof
        elseif on and l.kind == "source" and l.spot then out[#out + 1] = l end
    end
    return out
end

local function describe(lines)
    local out = {}
    for _, l in ipairs(lines) do
        if l.kind == "section" then
            out[#out + 1] = "[" .. tostring(l.key) .. "]"
        elseif l.spot then
            local d = {}
            for n, a in pairs(l.spot.about) do
                for item in pairs(a.drops) do d[#d + 1] = n .. ":" .. item end
            end
            table.sort(d)
            out[#out + 1] = "spot(" .. table.concat(d, ",") .. ")"
        end
    end
    return table.concat(out, " ")
end

local function dropsItem(spots, item)
    for _, l in ipairs(spots) do
        for _, a in pairs(l.spot.about) do
            if a.drops[item] then return true end
        end
    end
    return false
end

local function hasSection(lines, key)
    for _, l in ipairs(lines) do
        if l.kind == "section" and l.key == key then return true end
    end
    return false
end

-- The items the zone's skinnable beasts drop that the player can skin, from the data alone.
local function zoneLeathers(zone)
    local out = {}
    for _, r in ipairs(G.SkinRows(zone, G.Skills(), {})) do out[r.itemID] = true end
    return out
end

T.test("Farm: Arathi keeps its Skinning section, Heavy Leather among the spots", function()
    scene("farm", ARATHI, 36, function()
        local lines = settled()
        local farm = spotsOf(lines, SKIN)
        T.ok(hasSection(lines, SKIN), "a Skinning section: " .. describe(lines))
        T.ok(#farm > 0, "Skinning spots: " .. describe(lines))
        T.ok(dropsItem(farm, HEAVY_LEATHER), "a spot drops Heavy Leather: " .. describe(lines))
    end)
end)

T.test("Farm: with only Heavy Leather ticked, the Skinning spots are the ones that drop it", function()
    scene("farm", ARATHI, 36, function()
        local skip = {}
        for _, e in ipairs(G.ContinentSkins({ ARATHI }, G.Skills(), 36, "Alliance")) do
            if e.item ~= HEAVY_LEATHER then skip[e.item] = true end
        end
        World.set(CP.db, "skinSkip", skip)
        local lines = settled()
        local farm = spotsOf(lines, SKIN)
        T.ok(#farm > 0, "Skinning spots: " .. describe(lines))
        for _, l in ipairs(farm) do
            T.ok(dropsItem({ l }, HEAVY_LEATHER), "every spot drops Heavy Leather: " .. describe(lines))
        end
    end)
end)

T.test("Farm: nothing from another zone, no Nearby zones section", function()
    scene("farm", ARATHI, 36, function()
        World.set(CP.db, "otherZones", true)
        local lines = settled()
        T.ok(not hasSection(lines, "nearby"), "no Nearby zones section: " .. describe(lines))
    end)
end)

T.test("Farm menu: only this zone's leathers, with no other zone named", function()
    scene("farm", ARATHI, 60, function()
        local here = zoneLeathers(ARATHI)
        T.ok(next(here) ~= nil, "Arathi has leathers")
        local list = GL.FarmLeathers(ARATHI, G.Skills())
        T.ok(#list > 0, "the menu lists leathers")
        for _, m in ipairs(list) do
            T.ok(here[m.item], "Arathi's beasts drop " .. tostring(m.item))
            T.eq(m.label, CP.ItemName(m.item) or ("item " .. m.item), "no best zones after the item")
        end
        local seen = {}
        for _, m in ipairs(list) do seen[m.item] = true end
        T.ok(seen[MEDIUM_LEATHER] and seen[HEAVY_LEATHER], "Medium and Heavy Leather listed")
        T.eq(GL.TICKS_HEADER:find("every zone"), nil, "the header does not say every zone")
    end)
end)

T.test("Farm menu: ticks saved in one zone hold in another; each zone lists its own items", function()
    scene("farm", ARATHI, 36, function()
        World.set(CP.db, "skinSkip", { [HEAVY_LEATHER] = true })
        local arathi = GL.FarmLeathers(ARATHI, G.Skills())
        local badlands = GL.FarmLeathers(BADLANDS, G.Skills())
        local inBadlands = {}
        for _, m in ipairs(badlands) do inBadlands[m.item] = true end
        for _, m in ipairs(arathi) do
            T.eq(G.SkinUnticked(m.item), m.item == HEAVY_LEATHER, "tick state of " .. m.item)
        end
        T.ok(next(inBadlands) ~= nil, "Badlands lists its own leathers")
        T.eq(CP.db.skinSkip[HEAVY_LEATHER], true, "the Heavy Leather tick is still saved")
    end)
end)

T.test("Follow the guide: Arathi lists Skinning spots, unchanged", function()
    scene(nil, ARATHI, 36, function()
        World.set(CP.charDB, "gatherNeeds", { [SKIN] = { [HEAVY_LEATHER] = 40 } })
        World.set(CP.charDB, "gatherSoon", { [SKIN] = { [HEAVY_LEATHER] = 40 } })
        T.ok(#spotsOf(settled(), SKIN) > 0, "Follow lists Skinning spots")
    end)
end)

T.test("ContinentSkins over two zones ranks each leather's zones best first", function()
    scene("farm", ARATHI, 36, function()
        local both = 0
        for _, e in ipairs(G.ContinentSkins({ ARATHI, BADLANDS }, G.Skills(), 36, "Alliance")) do
            if #e.zones == 2 then both = both + 1 end
        end
        T.ok(both > 0, "a leather scores in both zones")
    end)
end)
