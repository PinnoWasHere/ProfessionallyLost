-- Farming is zone-specific (the map itself is in farmmap_test): the route filter lists only the leathers the player's zone gives, with no
-- other zone named; the gathering panel names no other zone.
-- Leveling stays as it was, checked against a snapshot taken before this change.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local SKIN = 393
local DUROTAR, MULGORE, BARRENS, ORGRIMMAR, KALIMDOR = 1411, 1412, 1413, 1454, 1414
local LIGHT, MEDIUM = 2318, 2319

-- Scene: the player in `spec.zone` at `spec.level`, Skinning and Mining at `spec.skill`,
-- mode `spec.mode`, other zones `spec.others`. `act(seen)` runs with every world-map and
-- minimap pin registration recorded in `seen`.
local function scene(spec, act)
    MapWorld.begin({ zone = spec.zone or DUROTAR, x = 0.5, y = 0.5, level = spec.level or 20, side = "Horde",
        shareSolves = true })
    -- No profession window open, so no earlier test's Tailoring (or any other) adds its needs.
    CraftWorld.begin({ professions = {} })
    local was = { CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.db.skinSkip }
    CP.db.route = true
    CP.db.otherZones = spec.others or false
    CP.db.routeMode = spec.mode
    CP.charDB.gatherNeeds = spec.needs or { [165] = { [LIGHT] = 200 }, [164] = { [2771] = 100 } }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN or id == 186 then return { skillID = id, rank = spec.skill or 120, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local mapPos, replan = CP.Waypoint.MapPosZone, G.UpdateAllNeeds
    G.UpdateAllNeeds = function() end
    CP.Waypoint.MapPosZone = function(z) return z end
    G.ResetClusters()
    local pins = LibStub("HereBeDragons-Pins-2.0")
    local seen = { world = {}, mini = {} }
    local addW, addM = pins.AddWorldMapIconMap, pins.AddMinimapIconMap
    pins.AddWorldMapIconMap = function(self, ref, icon, z, x, y, flag, ...)
        seen.world[#seen.world + 1] = { map = z, owner = icon.zone or z, x = x, y = y, alpha = icon.alpha,
            grind = icon.spot ~= nil, near = icon.near, spot = icon.spot }
        return addW(self, ref, icon, z, x, y, flag, ...)
    end
    pins.AddMinimapIconMap = function(self, ref, icon, z, ...)
        seen.mini[z] = (seen.mini[z] or 0) + 1
        return addM(self, ref, icon, z, ...)
    end
    function seen.reset() seen.world, seen.mini = {}, {} end
    -- Every draw clears the map first, so `seen` holds the last draw, whatever redraws came before it.
    local clear = RM.Clear
    World.set(RM, "Clear", function(...)
        seen.reset()
        return clear(...)
    end)
    local ok, err = pcall(act, seen)
    CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.db.skinSkip, CP.charDB.gatherNeeds = false, nil, nil, nil, nil
    RM.Update(false, {})
    T.advance(1)
    pins.AddWorldMapIconMap, pins.AddMinimapIconMap = addW, addM
    CP.Waypoint.MapPosZone, G.UpdateAllNeeds = mapPos, replan
    G.ResetClusters()
    -- Set back last: a redraw with the route on under this scene's map answers would cache them.
    CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.db.skinSkip = was[1], was[2], was[3], was[4]
    T.ok(ok, err)
end

-- The player's zone, then every other zone's pass to its end.
local function solveAll()
    GL.RouteOnly()
    T.advance(5)
    for _ = 1, 60 do
        if not RM.ZonesReport()[1]:find("running", 1, true) then break end
        T.advance(1)
    end
end

-- The route menu as built: titles, checkbox labels, buttons.
local function menu()
    local m = { titles = {}, checks = {}, buttons = {} }
    local root = {}
    local function entry(rec)
        function rec:SetResponse(r) self.response = r end
        return rec
    end
    function root.CreateTitle(_, text) m.titles[#m.titles + 1] = text end
    function root.CreateRadio(_, text) return entry({ text = text }) end
    function root.CreateCheckbox(_, text, get, set, data)
        m.checks[#m.checks + 1] = entry({ text = text, get = get, set = set, data = data })
        return m.checks[#m.checks]
    end
    function root.CreateButton(_, text, fn)
        m.buttons[#m.buttons + 1] = entry({ text = text, fn = fn })
        return m.buttons[#m.buttons]
    end
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
    GL.RouteMenu(UIParent)
    return m
end

-- Leveling snapshot ----------------------------------------------------------------

-- djb2 over `text`, kept below 2^32.
local function hash(text)
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
    return h
end

local function pinText(seen)
    local out = {}
    for _, p in ipairs(seen.world) do
        out[#out + 1] = ("%d|%d|%.4f|%.4f|%.2f|%s"):format(p.map, p.owner, p.x, p.y, p.alpha or -1, p.grind and "g" or "s")
    end
    table.sort(out)
    local mini = {}
    for z, n in pairs(seen.mini) do mini[#mini + 1] = z .. "=" .. n end
    table.sort(mini)
    return table.concat(out, "\n") .. "\nmini " .. table.concat(mini, ",")
end

local function perMap(seen)
    local n = {}
    for _, p in ipairs(seen.world) do n[p.map] = (n[p.map] or 0) + 1 end
    local out = {}
    for z, c in pairs(n) do out[#out + 1] = z .. "=" .. c end
    table.sort(out)
    return table.concat(out, ",")
end

local function menuText(m)
    local out = {}
    for _, t in ipairs(m.titles) do out[#out + 1] = "T " .. t end
    for _, c in ipairs(m.checks) do out[#out + 1] = "C " .. c.text end
    for _, b in ipairs(m.buttons) do out[#out + 1] = "B " .. b.text end
    return table.concat(out, "\n")
end

-- The gathering list's lines without "Next up" and the vendor patterns, whose lines and
-- item names come from earlier test files' state: kind, text and info, no item names.
local function listText()
    GL.Refresh()
    local out = {}
    for _, l in ipairs((GL.Drawn())) do
        if l.key ~= "next" and l.key ~= "patterns" and l.kind ~= "vendor" and l.kind ~= "pattern" and not l.spotOf
            and not (l.kind == "cont" and l.of.spotOf) then
            local spot = l.kind == "source" and l.spot ~= nil
            out[#out + 1] = ("%s|%s|%s"):format(l.kind, l.kind == "item" and "" or spot and l.rank or tostring(l.text or ""),
                spot and "" or tostring(l.info or ""))
        end
    end
    return table.concat(out, " / ")
end

-- Everything Follow the guide shows in one scene: the map with other zones off and on,
-- the route menu in Durotar and Orgrimmar, and the gathering list.
local function levelingCapture()
    local parts = {}
    local saved = G.SKIN_MIN_CHANCE
    G.SKIN_MIN_CHANCE = 0.35
    local ok, err = pcall(function()
        scene({}, function(seen)
            solveAll()
            parts.off = pinText(seen)
            parts.offMaps = perMap(seen)
            seen.reset()
            CP.db.otherZones = true
            RM.Refresh()
            solveAll()
            parts.on = pinText(seen)
            parts.onMaps = perMap(seen)
            parts.menu = menuText(menu())
            parts.list = listText()
            MapWorld.Move(ORGRIMMAR, 0.5, 0.5)
            parts.cityMenu = menuText(menu())
        end)
    end)
    G.SKIN_MIN_CHANCE = saved
    T.ok(ok, err)
    return parts
end

-- Taken on 0.2.55-beta with SKIN_MIN_CHANCE at 0.35, before Farming went continent-wide:
-- the map with other zones off and on, and the gathering list. The menu is left out
-- because the owner renamed its radios and turned Follow the guide's ticks into one line
-- (gatherguide_test checks that menu). The pins per map are a floor: the same maps hold
-- pins and none holds fewer, so newer spawn data may add pins without breaking this.
local SNAPSHOT = {
    -- Only the player's zone (`off`) is hashed. The `on` map follows every zone's spawn
    -- data and loops, so each GatherLite release moves it; FLOORS holds it instead. Taken
    -- again 2026-11-24, when nodes above the player's skill left the map.
    off = "2473483147",
    -- The 0.2.55 list read "section|Next up|2 / section|Skinning 120|have / need / item||0 / 200".
    -- Taken again 2026-11-25: Skill-ups lists the beasts and ore that give points, and the
    -- leather's grind spots sit under For your guides with its row.
    list = "section|Skinning 120| / plan|Skill-ups| / source|Ashenvale Bear|skill 110 · lvl 21-22 · 9 spawns"
        .. " / source|Ghostpaw Runner|skill 100 · lvl 19-20 · 9 spawns / source|Barrens Kodo|skill 100 · lvl 19-20 · 4 spawns"
        .. " / source|Thunderhawk Hatchling|skill 100 · lvl 18-20 · 3 spawns / plan|For your guides|have / need / item||0 / 200"
        .. " / source|#1| / source|#2| / source|#3| / section|Mining 120| / plan|Skill-ups|"
        .. " / source|Silver Vein|skill 75 · 9 nodes",
}
-- Taken again 2026-11-24, when nodes above the player's skill left the map.
local FLOORS = {
    offMaps = { [1411] = 7, [1414] = 3 },
    onMaps = { [1411] = 7, [1412] = 15, [1413] = 17, [1414] = 46, [1438] = 3, [1439] = 12, [1440] = 25,
               [1441] = 22, [1442] = 16, [1443] = 14, [1444] = 3, [1445] = 22, [1448] = 19, [1452] = 10,
               [1454] = 3, [1456] = 3, [2652] = 3 },
}

-- "map=count,..." as perMap prints it, as { [map] = count }.
local function parseMaps(text)
    local out = {}
    for map, n in text:gmatch("(%d+)=(%d+)") do out[tonumber(map)] = tonumber(n) end
    return out
end

-- `floors` ({ [map] = least pins }) against `got` (a perMap string): the same maps hold
-- pins, each at or above its floor. Returns the problems found, or an empty list.
local function mapsAgainst(floors, got)
    local have, bad = parseMaps(got), {}
    for map, least in pairs(floors) do
        if not have[map] then
            bad[#bad + 1] = "no pins on map " .. map
        elseif have[map] < least then
            bad[#bad + 1] = ("map %d has %d pins, under %d"):format(map, have[map], least)
        end
    end
    for map in pairs(have) do
        if not floors[map] then bad[#bad + 1] = "pins on unexpected map " .. map end
    end
    table.sort(bad)
    return bad
end

T.test("follow the guide shows what leveling showed before farming went continent-wide", function()
    local parts = levelingCapture()
    local got = {}
    for _, k in ipairs({ "off", "on" }) do got[k] = hash(parts[k]) end
    got.list = parts.list
    for k, v in pairs(SNAPSHOT) do T.eq(tostring(got[k]), v, k) end
    for k, floors in pairs(FLOORS) do T.eq(table.concat(mapsAgainst(floors, parts[k]), "; "), "", k) end
end)

-- Farming map -----------------------------------------------------------------------

T.test("farming follows Other zones: off solves no other zone, on solves them", function()
    scene({ mode = "farm", others = false, level = 30, skill = 200 }, function()
        solveAll()
        T.ok(not RM.OthersOn(), "off")
        T.eq(#RM.Others(), 0, "no zone solved")
        T.ok(RM.ZonesReport()[1]:find("other zones off", 1, true), RM.ZonesReport()[1])
    end)
    scene({ mode = "farm", others = true, level = 30, skill = 200 }, function()
        solveAll()
        T.ok(RM.OthersOn(), "on in farming")
        T.ok(#RM.Others() >= 5, "zones solved: " .. table.concat(RM.Others(), ","))
    end)
    scene({ mode = "farm", others = true, level = 30, skill = 200 }, function()
        CP.db.routeMode = nil
        GL.RouteChanged()
        solveAll()
        T.ok(#RM.Others() >= 5, "follow the guide with the setting on solves them: " .. table.concat(RM.Others(), ","))
    end)
end)

T.test("farming keeps the level and skill limits on every zone's spots", function()
    scene({ mode = "farm", level = 15, skill = 75 }, function(seen)
        solveAll()
        local spots = 0
        for _, p in ipairs(seen.world) do
            if p.grind and p.spot.prof == SKIN then
                spots = spots + 1
                for name, a in pairs(p.spot.about or {}) do
                    T.ok(a.minLevel <= 15 + G.FARM_SAFE_LEVELS, ("%s (%d) in zone %d"):format(name, a.minLevel, p.owner))
                    T.ok(G.CorpseSkill(a.minLevel) <= 75, name .. " skinnable at 75")
                end
            end
        end
        T.ok(spots > 0, "spots drawn")
    end)
end)

-- Farm filter -----------------------------------------------------------------------

T.test("the farm filter in Orgrimmar lists only the leathers Orgrimmar's beasts drop, with no zone named", function()
    scene({ zone = ORGRIMMAR, mode = "farm", level = 40, skill = 300 }, function()
        local m = menu()
        local byItem = {}
        for _, c in ipairs(m.checks) do
            if type(c.data) == "number" then byItem[c.data] = c end
        end
        local here = {}
        for _, mat in ipairs(GL.FarmLeathers(ORGRIMMAR, G.Skills())) do here[mat.item] = mat end
        for item, c in pairs(byItem) do
            T.ok(here[item], "a leather this zone gives: " .. tostring(item))
            T.ok(not c.text:find("|c", 1, true), "no best zones after the item: " .. c.text)
            T.eq(c.response, MenuResponse.Refresh, "stays open")
        end
        for item in pairs(here) do T.ok(byItem[item], "listed: " .. tostring(item)) end
        T.eq(byItem[2934], nil, "no Ruined Leather Scraps")
        for _, mat in ipairs(GL.FarmLeathers(ORGRIMMAR, G.Skills())) do
            for _, z in ipairs(mat.zones) do T.eq(z, ORGRIMMAR, "only this zone") end
        end
        local item = next(byItem)
        if item then
            T.eq(byItem[item].set(item), MenuResponse.Refresh)
            T.ok(G.SkinSkipped(item), "unticked")
            T.ok(m.buttons[1].text:find("leather", 1, true), m.buttons[1].text)
        end
    end)
end)

T.test("a leather picked in one zone stays picked in another, and each zone lists its own", function()
    scene({ zone = DUROTAR, mode = "farm", level = 40, skill = 300 }, function()
        local durotar = GL.FarmLeathers(DUROTAR, G.Skills())
        T.ok(#durotar > 0, "Durotar lists leathers")
        CP.db.skinSkip = { [durotar[1].item] = true }
        local barrens = GL.FarmLeathers(BARRENS, G.Skills())
        for _, m in ipairs(barrens) do
            T.eq(G.SkinUnticked(m.item), m.item == durotar[1].item, "the pick is saved by item: " .. m.item)
        end
        T.eq(CP.db.skinSkip[durotar[1].item], true, "still saved")
    end)
end)
