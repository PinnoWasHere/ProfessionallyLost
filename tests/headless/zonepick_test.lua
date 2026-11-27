-- The gathering panel's zone pick: a click on the header's zone name opens a menu of every
-- outdoor zone, by continent, and a picked zone is the player's plan for where they are heading.
-- The panel lists it (rows, needs, skill-ups, fishing plan, vendor patterns, route on the world
-- map) until the player walks into it, picks Where I am or clicks back. What only makes sense
-- where the player stands stays with them: "Fish here", waypoint arrows and the minimap trail.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local Pins = LibStub("HereBeDragons-Pins-2.0")
local HERB, MINE = 182, 186
local ALCHEMY, BS = 171, 164
local DUROTAR, MULGORE, BARRENS, WINTERSPRING = 1411, 1412, 1413, 1452
local PEACEBLOOM, COPPER, TIN = 2447, 2770, 2771

-- Level 20 Horde with Herbalism and Mining at 50, the guides needing Peacebloom and Copper.
local function scene(spec)
    spec = spec or {}
    MapWorld.begin({ zone = spec.zone or DUROTAR, level = 20, side = "Horde", shareSolves = true,
                     instance = spec.instance, instanceName = spec.instanceName })
    for _, key in ipairs({ "routeMode", "routeSkip", "skinSkip", "gatherClosed", "farmClosed" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "route", true)
    World.set(CP.db, "mapIcons", true)
    World.set(CP.db, "routeOnMap", nil)
    World.set(CP.db, "otherZones", false)
    World.set(CP.charDB, "panelProf", nil)
    World.set(CP.charDB, "gatherZone", nil)
    World.set(CP.charDB, "gatherNeeds", spec.needs or { [ALCHEMY] = { [PEACEBLOOM] = 20 }, [BS] = { [COPPER] = 30 } })
    World.set(CP.charDB, "gatherSoon", nil)
    local skills = spec.skills or { [HERB] = 50, [MINE] = 50 }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = skills[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(GL, "away", false)
    World.set(GL, "here", nil)
    World.set(GL, "hereName", nil)
    G.ResetClusters()
    World.onEnd(function()
        CP.db.route = false
        RM.Update(false, {})
        T.advance(1)
        G.ResetClusters()
    end)
end

-- The game's context menu as the zone name opens it: { radios = { entry }, titles = { text } },
-- each radio { text, get, set, data, section }.
local function zoneMenu()
    local m = { radios = {}, titles = {} }
    local section = ""
    local root = {}
    local function entry(rec)
        function rec:SetResponse(r) self.response = r end
        function rec:SetEnabled() end
        return rec
    end
    function root.CreateTitle(_, text)
        m.titles[#m.titles + 1] = text
        section = text
        return entry({ text = text })
    end
    function root.CreateRadio(_, text, get, set, data)
        m.radios[#m.radios + 1] = entry({ text = text, get = get, set = set, data = data, section = section })
        return m.radios[#m.radios]
    end
    function root.CreateCheckbox() return entry({}) end
    function root.CreateButton() return entry({}) end
    World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    local b = GL.head.zone
    b:GetScript("OnClick")(b, "LeftButton")
    return m
end

local function radioFor(m, zone)
    for _, r in ipairs(m.radios) do
        if r.data == zone then return r end
    end
end

-- The item rows drawn now, as a sorted list of item ids.
local function itemRows()
    local out = {}
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "item" and l.row then out[#out + 1] = l.row.itemID end
    end
    table.sort(out)
    return out
end

local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- 1. The menu -------------------------------------------------------------------------

T.test("the zone name opens a menu: Where I am, then each continent's zones, the player's continent first", function()
    scene()
    GL.Refresh()
    local m = zoneMenu()
    T.eq(m.radios[1].text, GL.ZONE_HERE, "Where I am leads")
    T.eq(m.radios[1].data, false)
    T.ok(m.radios[1].get(m.radios[1].data), "and is picked while the panel follows the player")
    T.eq(m.titles[1], "Kalimdor", "the player's continent first")
    T.ok(#m.titles >= 2, "every continent with zones: " .. table.concat(m.titles, ", "))
    local seen = {}
    for _, r in ipairs(m.radios) do if r.data then seen[r.data] = r end end
    for zone in pairs(CP.GatherData.zones) do
        local info = not G.IsInstance(zone) and C_Map.GetMapInfo(zone)
        if info and info.mapType == 3 and RM.ContinentOf(zone) then
            T.ok(seen[zone] ~= nil, "every outdoor zone is offered: " .. info.name)
        end
    end
    T.eq(seen[DUROTAR].section, "Kalimdor")
end)

T.test("each continent lists its zones by name, with no ranking and nothing dimmed", function()
    scene()
    local m = zoneMenu()
    for _, c in ipairs(GL.ZoneChoices()) do
        for i = 2, #c.zones do
            T.ok(c.zones[i - 1].name <= c.zones[i].name, c.name .. " in name order at " .. c.zones[i].name)
        end
    end
    for _, r in ipairs(m.radios) do
        T.ok(not r.text:find("^|c"), "no line is dimmed whole: " .. plain(r.text))
        T.ok(not plain(r.text):lower():find("nothing", 1, true), "no line says nothing: " .. plain(r.text))
    end
end)

T.test("each zone's line hints the skill range it holds for the player's gathering skills", function()
    scene()
    local m = zoneMenu()
    local barrens = radioFor(m, BARRENS).text
    T.ok(barrens:find("^The Barrens  |c"), "the name, then the hint in the muted ink: " .. barrens)
    local hint = plain(barrens):sub(#"The Barrens  " + 1)
    T.eq(hint, GL.RangeText(BARRENS, G.MINING) .. " · " .. GL.RangeText(BARRENS, G.HERBALISM),
        "Mining's then Herbalism's range")
    local lo, hi = G.ZoneRange(BARRENS, G.MINING)
    T.ok(lo and hi and lo <= hi and hi <= 300, "a range within 1 to 300")
    T.ok(hint:find(("Mining %d"):format(lo), 1, true), hint)
    local ws = plain(radioFor(m, WINTERSPRING).text)
    T.ok(ws:find("Herbalism %d+") and ws:find("Mining %d+"), "a zone far above the skills still says what it holds: " .. ws)
end)

T.test("with no gathering skill, a zone's line names its biggest gathering profession", function()
    scene({ skills = {} })
    local seen = 0
    for _, c in ipairs(GL.ZoneChoices()) do
        for _, z in ipairs(c.zones) do
            if GL.ZoneHas(z.zone) then
                T.ok(z.hint ~= nil, "a hint for " .. z.name)
                T.ok(z.hint and not z.hint:find(" · ", 1, true), "one profession only: " .. tostring(z.hint))
                seen = seen + 1
            end
        end
    end
    T.ok(seen > 10, "zones with something to gather: " .. seen)
end)

T.test("Daylight UI's own menu shows the zones, and a pick from it plans that zone", function()
    scene()
    DaylightWorld.begin({ plugin = true })
    GL.Refresh()
    local b = GL.head.zone
    b:GetScript("OnClick")(b, "LeftButton")
    local menu = DaylightWorld.state.menu
    T.ok(menu ~= nil, "Daylight UI's menu opened")
    T.eq(menu.owner, b, "under the zone name")
    T.eq(GL.nativeMenu.owner, b)
    local key
    for k, e in pairs(GL.nativeMenu.entries) do
        if e.data == BARRENS then key = k end
        T.ok(e.kind ~= "title" or not tostring(e.text):find("^|c"), "continents are headings")
    end
    T.ok(key ~= nil, "the Barrens are a line")
    DaylightWorld.PickMenu(key)
    T.eq(CP.charDB.gatherZone, BARRENS, "picked")
    T.eq(GL.zone, BARRENS, "the panel lists it")
end)

-- 2. The pick is saved, and clears itself ----------------------------------------------

T.test("a pick is saved on the character and stays after a reload", function()
    scene()
    local m = zoneMenu()
    radioFor(m, BARRENS).set(BARRENS)
    T.eq(CP.charDB.gatherZone, BARRENS, "saved per character")
    T.ok(radioFor(zoneMenu(), BARRENS).get(BARRENS), "ticked in the menu")
    -- A reload keeps the saved variables and starts the panel's own state over.
    GL.away, GL.zone = false, nil
    GL.Refresh()
    T.eq(GL.zone, BARRENS, "listed again after the reload")
    T.ok(GL.away, "still a picked zone")
end)

T.test("walking into the picked zone clears the pick and the panel follows the player", function()
    scene()
    GL.SetZone(BARRENS)
    T.eq(GL.zone, BARRENS)
    MapWorld.Move(BARRENS, 0.5, 0.5)
    GL.Refresh()
    T.eq(CP.charDB.gatherZone, nil, "the pick cleared itself")
    T.eq(GL.zone, BARRENS, "the same zone, now the player's own")
    T.ok(not GL.away, "no longer away")
    MapWorld.Move(DUROTAR, 0.5, 0.5)
    GL.Refresh()
    T.eq(GL.zone, DUROTAR, "and it follows the player on")
end)

T.test("Where I am clears the pick; picking the zone the player is in stores nothing", function()
    scene()
    GL.Refresh()
    local m = zoneMenu()
    radioFor(m, MULGORE).set(MULGORE)
    T.eq(CP.charDB.gatherZone, MULGORE)
    m = zoneMenu()
    m.radios[1].set(m.radios[1].data)
    T.eq(CP.charDB.gatherZone, nil, "Where I am cleared it")
    T.eq(GL.zone, DUROTAR)
    radioFor(zoneMenu(), DUROTAR).set(DUROTAR)
    T.eq(CP.charDB.gatherZone, nil, "the player's own zone is not a pick")
    T.ok(not GL.away)
end)

-- 3. What the panel lists --------------------------------------------------------------

T.test("a picked zone's rows are the ones the player would see standing there", function()
    -- Tin grows in the Barrens, not in Durotar.
    scene({ zone = BARRENS, skills = { [MINE] = 100 }, needs = { [BS] = { [COPPER] = 30, [TIN] = 30 } } })
    GL.Refresh()
    local there = itemRows()
    T.ok(#there > 0, "the Barrens have rows")
    G.ResetClusters()
    MapWorld.Move(DUROTAR, 0.5, 0.5)
    GL.Refresh()
    local durotar = itemRows()
    GL.SetZone(BARRENS)
    T.eq(itemRows(), there, "the picked Barrens list as if the player stood there")
    T.ok(table.concat(there, ",") ~= table.concat(durotar, ","), "not Durotar's rows")
end)

T.test("moving within the player's own zone leaves a picked zone's list alone", function()
    scene()
    GL.SetZone(BARRENS)
    local changed = 0
    World.set(GL, "Changed", function() changed = changed + 1 end)
    MapWorld.Move(DUROTAR, 0.45, 0.45, { subZone = "Razor Hill" })
    GL.Moved()
    T.eq(changed, 0, "no rebuild for a move in Durotar")
    T.eq(GL.place, nil, "no place shown for the picked zone")
end)

T.test("Patterns to buy here follows the picked zone: its vendors, with where they stand", function()
    scene()
    World.set(CP.db, "vendorAlerts", true)
    World.set(CP.charDB, "vendorWatch", { [ALCHEMY] = { { item = 1, name = "A", skill = 10, npcs = {} } } })
    local buy = CP.charDB.vendorWatch[ALCHEMY][1]
    local vendor = { DUROTAR = { name = "Durotar Vendor", x = 1, y = 1 }, BARRENS = { name = "Barrens Vendor", x = 2, y = 2 } }
    World.set(CP.VendorWatch, "Find", function(zone)
        local v = zone == DUROTAR and vendor.DUROTAR or zone == BARRENS and vendor.BARRENS
        return v and { { buy = buy, target = v } } or {}
    end)
    World.set(CP.Waypoint, "Describe", function(t) return t.name .. " spot" end)
    World.set(GL, "patternsOpen", true)
    local function patterns()
        local out, inside = {}, false
        for _, l in ipairs((GL.Drawn())) do
            if l.kind == "section" then inside = l.key == "patterns" end
            if inside and l.kind == "vendor" then out[#out + 1] = l end
        end
        return out
    end
    World.set(CP.VendorWatch, "current", { zone = DUROTAR, found = { { buy = buy, target = vendor.DUROTAR } } })
    GL.Refresh()
    T.eq(patterns()[1] and patterns()[1].text, "Durotar Vendor", "where the player stands, its scan's")
    GL.SetZone(BARRENS)
    local list = patterns()
    T.eq(#list, 1)
    T.eq(list[1] and list[1].text, "Barrens Vendor", "the picked zone's vendor")
    T.eq(list[1] and list[1].info, "Barrens Vendor spot", "with where it stands")
    local marked, placed = 0, 0
    World.set(GL, "MarkOnMap", function() marked = marked + 1 end)
    World.set(CP.Waypoint, "Place", function() placed = placed + 1 end)
    World.set(CP.Waypoint, "Locate", function() return BARRENS, CreateVector2D(0.2, 0.2) end)
    list[1].pin()
    T.eq(placed, 0, "no waypoint arrow to a zone the player is not in")
    T.eq(marked, 1, "a mark on the map")
    for _, l in ipairs((GL.Drawn())) do
        if l.key == "patterns" then
            T.eq(l.pin, nil, "no mark-all waypoint from afar")
            T.eq(l.badge, nil, "the new-pattern count stays with the player's zone")
        end
    end
    World.set(CP.db, "vendorAlerts", false)
    GL.Refresh()
    T.eq(#patterns(), 0, "the vendor alerts off: none, as where the player stands")
end)

T.test("the fishing plan never says Fish here for a picked zone", function()
    scene()
    local plan = { kind = "zone", zone = BARRENS, here = true, land = 100, catches = 40, feeds = {} }
    World.set(GL, "away", false)
    T.ok(GL.FishLines(plan, BARRENS, 75)[1].text:find("^Fish here"), "the player's own zone")
    World.set(GL, "away", true)
    T.eq(GL.FishLines(plan, BARRENS, 75)[1].text, "Fish in The Barrens to 75", "a picked zone is named")
end)

T.test("a row's pin in a picked zone only marks the map: no arrow until the player is there", function()
    scene()
    local placed, marked = {}, {}
    World.set(CP.Waypoint, "PlaceOnMap", function(zone) placed[#placed + 1] = zone end)
    World.set(GL, "MarkOnMap", function(zone) marked[#marked + 1] = zone end)
    GL.SetZone(BARRENS)
    local pinned = 0
    for _, l in ipairs((GL.Drawn())) do
        for _, s in ipairs(l.kind == "item" and GL.SourceLines(l.row, GL.zone) or {}) do
            if s.pin then
                s.pin()
                pinned = pinned + 1
            end
        end
    end
    T.ok(pinned > 0, "rows with pins")
    T.eq(#placed, 0, "no waypoint arrow")
    T.ok(#marked > 0, "marked on the map")
    T.eq(marked[1], BARRENS)
    GL.SetZone(nil)
    placed, marked = {}, {}
    GL.PlaceAt(DUROTAR, 0.5, 0.5, "x")
    T.eq(#placed, 1, "the player's own zone gets its waypoint")
end)

T.test("the route filter's menu is for the picked zone, whose route it shapes", function()
    scene()
    GL.SetZone(BARRENS)
    local titles = {}
    local root = {}
    local function entry() return { SetResponse = function() end, SetEnabled = function() end } end
    function root.CreateTitle(_, text) titles[#titles + 1] = text; return entry() end
    function root.CreateRadio() return entry() end
    function root.CreateCheckbox() return entry() end
    function root.CreateButton() return entry() end
    World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    GL.RouteMenu(GL.head.filter)
    T.eq(titles[1], "Gathering route: The Barrens")
end)

T.test("inside an instance, a picked zone lists with its route as outdoors", function()
    scene({ instance = 389, instanceName = "Ragefire Chasm" })
    GL.SetZone(BARRENS)
    T.eq(GL.zone, BARRENS)
    T.ok(not GL.inside, "the picked zone is no instance")
    T.ok(GL.head.route:IsShown(), "its route button shows")
    T.eq(GL.hereName, "Ragefire Chasm", "the note names where the player is")
end)

-- 4. The header -----------------------------------------------------------------------

-- Room for a header line, as GatherList's own headWidth reckons it.
local function headRoom()
    local i = GL.headInset
    return GL.width - i.left - i.right - GL.headRoom - GL.HEAD_ICONS
end

T.test("the header names the picked zone; its note says where the player is, then back", function()
    scene()
    World.set(GL, "Measure", function(text) return #plain(text) * 7 end)
    GL.Refresh()
    T.eq(GL.head.title:GetText(), "Durotar")
    T.ok(not GL.head.back:IsShown(), "no back while the panel follows the player")
    GL.SetZone(BARRENS)
    T.eq(GL.head.title:GetText(), "The Barrens", "the picked zone's name")
    T.eq(GL.head.status:GetText(), "You're in Durotar · ", "where the player is")
    T.eq(GL.head.backText:GetText(), GL.BACK)
    T.ok(GL.head.back:IsShown(), "back is a control")
    T.eq(GL.head.back:GetWidth(), GL.Measure(GL.BACK, "small", true), "its click covers the word")
    T.eq(GL.PICKED_NOTE, nil, "no Planning ahead")
    T.eq(GL.head.zone:GetWidth(), math.min(headRoom(), GL.Measure("The Barrens", "head", true)),
        "the click covers the name")
    GL.head.back:GetScript("OnClick")(GL.head.back, "LeftButton")
    T.eq(CP.charDB.gatherZone, nil, "back follows the player again")
    T.eq(GL.zone, DUROTAR)
    T.ok(not GL.head.back:IsShown())
end)

T.test("the zone name says on hover that a click plans another zone; a long name keeps its click on the name", function()
    scene()
    World.set(GL, "Measure", function(text) return #text * 7 end)
    GL.Refresh()
    local b = GL.head.zone
    local owner, lines = nil, {}
    World.set(GameTooltip, "SetOwner", function(_, o) owner = o end)
    World.set(GameTooltip, "SetText", function(_, t) lines[#lines + 1] = t end)
    World.set(GameTooltip, "AddLine", function(_, t) lines[#lines + 1] = t end)
    World.set(GameTooltip, "Show", function() end)
    CP.GatherList.ZoneTip(b)
    T.eq(owner, b, "its own tooltip")
    T.eq(lines, GL.ZONE_TIP)
    local long = string.rep("W", 80)
    CP.GatherList.FitTitle(long, long)
    T.eq(b:GetWidth(), headRoom(), "never wider than the header's room")
end)

T.test("the note fits the header for every zone the player can stand in, and keeps back", function()
    scene()
    -- The stub's fixed-size header fonts measure 0; this reads 7 px a letter, wider than the real ones.
    World.set(GL, "Measure", function(text) return #plain(text) * 7 end)
    GL.SetZone(BARRENS)
    local kept = 0
    local room = headRoom()
    for zone in pairs(CP.GatherData.zones) do
        local info = not G.IsInstance(zone) and C_Map.GetMapInfo(zone)
        if info then
            GL.hereName = info.name
            GL.FitNote()
            local text = GL.head.status:GetText() .. GL.head.backText:GetText()
            T.ok(GL.Measure(text, "small", true) <= room, ("%q fits %d px"):format(text, room))
            T.ok(text:find(GL.BACK .. "$"), "the note ends in back: " .. text)
            if text:find(info.name, 1, true) then kept = kept + 1 end
        end
    end
    T.ok(kept > 0, "the player's own zone stays in the note where it fits")
    GL.hereName = string.rep("W", 60)
    GL.FitNote()
    local text = GL.head.status:GetText()
    T.ok(text:find("^You're in W+%.%.%. · $"), "a long name is cut short: " .. text)
end)

-- 5. The route ------------------------------------------------------------------------

-- Route pins added now, by map kind.
local function trackPins()
    local live = { world = 0, mini = 0 }
    for kind, name in pairs({ world = "AddWorldMapIconMap", mini = "AddMinimapIconMap" }) do
        local was = Pins[name]
        World.set(Pins, name, function(self, ref, ...)
            if ref == "ProfLost_Route" then live[kind] = live[kind] + 1 end
            return was(self, ref, ...)
        end)
    end
    for kind, name in pairs({ world = "RemoveAllWorldMapIcons", mini = "RemoveAllMinimapIcons" }) do
        local was = Pins[name]
        World.set(Pins, name, function(self, ref, ...)
            if ref == "ProfLost_Route" then live[kind] = 0 end
            return was(self, ref, ...)
        end)
    end
    return live
end

T.test("the picked zone's route draws on the world map, not the minimap, until the player is there", function()
    scene()
    local live = trackPins()
    GL.SetZone(BARRENS)
    T.advance(5)
    T.ok(RM.Away(), "drawn as a planned zone")
    T.ok(RM.Drawn()[BARRENS], "the Barrens' route is drawn")
    T.ok(not RM.Drawn()[DUROTAR], "Durotar's is not")
    T.ok(live.world > 0, "pins on the world map")
    T.eq(live.mini, 0, "no minimap pins")
    T.ok(CP.RouteLines.Has(BARRENS), "a line on the map")
    MapWorld.Move(BARRENS, 0.5, 0.5)
    GL.Refresh()
    T.advance(5)
    T.ok(not RM.Away(), "the player is there")
    T.ok(live.mini > 0, "the minimap trail shows now")
end)

T.test("the folded panel's route follows the pick too", function()
    scene()
    World.set(CP.charDB, "gatherZone", BARRENS)
    GL.RouteOnly()
    T.advance(5)
    T.ok(RM.Drawn()[BARRENS], "the picked zone's route")
    T.ok(RM.Away())
end)

-- 6. What the panel lists, by route mode --------------------------------------------------

local SKIN, LW = 393, 165
local LIGHT, MEDIUM, HEAVY, THICK = 2318, 2319, 4234, 4304

-- The owner's case: Skinning 272, Leatherworking 155 whose guide no longer needs Light or
-- Medium Leather (their saved needs, 2026-11-25), the Barrens picked from Durotar.
local function owner(mode, bags)
    scene({ skills = { [SKIN] = 272 }, needs = { [LW] = { [HEAVY] = 232, [THICK] = 405, [4291] = 147, [2605] = 16 } } })
    World.set(CP.db, "routeMode", mode)
    World.patch("C_Item.GetItemCount", function(item) return bags and bags[item] or 0 end)
    GL.SetZone(BARRENS)
    T.advance(5)
    GL.Refresh()
end

-- The Skinning section's lines, from its header (or its why line) to the next section.
local function section(key)
    local out, inside = {}, false
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "section" then inside = l.key == key end
        if inside or l.why == key then out[#out + 1] = l end
    end
    return out
end

T.test("Follow the guide lists only what a guide still needs: a material in hand drops off", function()
    scene({ zone = BARRENS, skills = { [MINE] = 100 }, needs = { [BS] = { [COPPER] = 30, [TIN] = 30 } } })
    World.patch("C_Item.GetItemCount", function(item) return item == COPPER and 40 or 0 end)
    MapWorld.Move(DUROTAR, 0.5, 0.5)
    GL.SetZone(BARRENS)
    local rows = itemRows()
    T.eq(rows, { TIN }, "Copper is in hand; Tin is still short")
end)

T.test("the owner's Barrens: skill-ups give points at 272, and leather rows and spots are guide needs only", function()
    owner(nil)
    local lines = section(SKIN)
    T.ok(#lines > 0, "a Skinning section")
    local still = {}
    for _, l in ipairs(lines) do
        if l.kind == "item" then
            T.ok(l.row.have < l.row.need, "a still-needed row: " .. l.row.itemID)
            still[l.row.itemID] = true
        end
    end
    local under
    for _, l in ipairs(lines) do
        if l.subhead then under = l.text end
        if l.spot then
            T.eq(under, GL.GUIDE_HEAD, "a grind spot sits under For your guides")
            for _, about in pairs(l.spot.about or {}) do
                for item in pairs(about.drops) do
                    T.ok(still[item], ("spot %s is for %d, which no guide still needs"):format(l.rank, item))
                end
            end
        elseif l.kind == "source" and under == GL.SKILLUPS_HEAD then
            T.ok(l.skill and CP.GatherGuide.Band(272, l.skill) > 0, "a skill-up at 272: " .. l.text)
        end
    end
    for _, l in ipairs(lines) do
        if l.kind == "item" then
            T.ok(l.row.itemID ~= LIGHT and l.row.itemID ~= MEDIUM, "no leather the guide no longer needs")
        end
    end
end)

T.test("with every leather in hand, Follow the guide shows no leather row or grind spot", function()
    owner(nil, { [HEAVY] = 300, [THICK] = 500 })
    for _, l in ipairs(section(SKIN)) do
        T.ok(l.kind ~= "item", "no row: " .. tostring(l.row and l.row.itemID))
        T.ok(not l.spot, "no grind spot")
        T.ok(l.text ~= GL.GUIDE_HEAD, "no guide heading")
    end
end)

T.test("a gathering skill with nothing here says why and names the guide's better zones", function()
    scene({ skills = { [SKIN] = 272, [MINE] = 50 }, needs = {} })
    MapWorld.Move(BARRENS, 0.5, 0.5)
    GL.SetZone(DUROTAR)
    for _ = 1, 30 do T.advance(1) end
    GL.Refresh()
    local skin, mine = section(SKIN), section(MINE)
    T.eq(skin[1] and skin[1].kind, "plan", "no Skinning section, a line")
    T.eq(skin[1] and skin[1].text, "Skinning: grey here at 272")
    T.ok(skin[2] and skin[2].text:find("^Better for you: "), "then the guide's zones: " .. tostring(skin[2] and skin[2].text))
    T.ok(skin[2] and not skin[2].text:find("Durotar", 1, true), "never the zone listed")
    T.ok(#mine > 0, "Mining at 50 gets a line too")
    for _, l in ipairs((GL.Drawn())) do
        T.ok(not tostring(l.text):lower():find("nothing", 1, true), "never says nothing: " .. tostring(l.text))
    end
    T.eq(GL.WhyText(WINTERSPRING, MINE, 50):match("^Mining: needs %d+ here %(you're 50%)$") ~= nil, true,
        GL.WhyText(WINTERSPRING, MINE, 50))
end)

T.test("Farm leads with what sells here and names no guide need", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return 100, item == MEDIUM and 9000 or 500 end)
    GL.Refresh()
    local drawn = GL.Drawn()
    T.eq(drawn[1] and drawn[1].text, GL.FARM_HEAD_PROFIT, "Profit leads")
    T.eq(drawn[2] and drawn[2].itemID, MEDIUM, "the dearest first")
    T.eq(drawn[2] and drawn[2].info, CP.Pricing.Format(9000) .. " ea (AH)", "an auction price says AH")
    for _, l in ipairs(drawn) do
        local text = (tostring(l.text) .. " " .. tostring(l.info)):lower()
        T.ok(not text:find("guide", 1, true) and not text:find("need", 1, true), "no guide word in Farm: " .. text)
        T.ok(not l.subhead or l.text ~= GL.SKILLUPS_HEAD, "no Skill-ups heading in Farm")
    end
end)

T.test("Farm: a price from the vendor says Vendor, none says no price yet", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return 100, nil end)
    GL.Refresh()
    local drawn = GL.Drawn()
    T.eq(drawn[2] and drawn[2].info, CP.Pricing.Format(100) .. " ea (Vendor)")
    World.set(CP.Pricing, "SaleValue", function(item) return nil, nil end)
    GL.Refresh()
    drawn = GL.Drawn()
    T.eq(drawn[2] and drawn[2].info, GL.FARM_NO_PRICE)
end)

T.test("Farm in a zone that sells for little shows its profit and points to better farm zones", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return 5, item == 8170 and 20000 or nil end)
    World.set(CP.Farm, "Items", function() return { LIGHT, 8170 } end)
    local asked
    World.set(CP.Farm, "Find", function(item)
        asked = item
        return { zone = WINTERSPRING, score = 1 }, true
    end)
    GL.Refresh()
    local drawn = GL.Drawn()
    T.eq(drawn[1] and drawn[1].text, GL.FARM_HEAD_PROFIT)
    T.eq(asked, 8170, "the better zone is the dearest material's")
    local better, at
    for i, l in ipairs(drawn) do
        if tostring(l.text):find("^Best farm") then better, at = l, i end
    end
    T.ok(better and better.text:find("Winterspring", 1, true), tostring(better and better.text))
    T.ok(better and better.text:find("^Best farm: Winterspring %(.*%)$") ~= nil,
        "location and material in the text: " .. tostring(better and better.text))
    T.eq(better and better.info, CP.Pricing.Format(20000) .. " ea (AH)", "price and source in the info column")
    T.ok(drawn[at + 1] == nil or drawn[at + 1].kind ~= "cont", "no wrapped continuation")
    T.eq(better and better.wrapped, nil, "the info stays beside the text")
    World.set(CP.Farm, "Find", function() return nil, false end)
    GL.Refresh()
    local waiting
    for _, l in ipairs((GL.Drawn())) do
        if tostring(l.text):find("^Best farm") then waiting = l end
    end
    T.eq(waiting and waiting.text, GL.FARM_BETTER:format(CP.GatherGuide.WARM.waiting), "while the search runs")
    T.eq(waiting and waiting.wrapped, nil, "one row while it runs")
end)

T.test("Farm: several Best farm zones light together when one is hovered", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return 5, item == 8170 and 90000 or item == 8171 and 80000 or nil end)
    World.set(CP.Farm, "Items", function() return { LIGHT, 8170, 8171 } end)
    World.set(CP.Farm, "Find", function(item)
        return { zone = item == 8170 and WINTERSPRING or MULGORE, score = 1 }, true
    end)
    GL.Refresh()
    local drawn, rows = GL.Drawn()
    local first, second
    for _, l in ipairs(drawn) do
        if tostring(l.text):find("^Best farm") then first = l end
    end
    for i, l in ipairs(drawn) do
        if l == first then second = drawn[i + 1] end
    end
    T.ok(first and second and second.kind == "plan" and second.info, "a second zone row follows the first: " .. tostring(first and first.text) .. " / " .. tostring(second and second.kind) .. " " .. tostring(second and second.text))
    local lit = {}
    for _, r in ipairs(rows) do
        World.set(r, "LockHighlight", function(self) lit[self] = true end)
        World.set(r, "UnlockHighlight", function(self) lit[self] = nil end)
    end
    local hover
    for _, r in ipairs(rows) do
        if r:IsShown() and r.line == first then hover = r end
    end
    hover:GetScript("OnEnter")(hover)
    local count, hasSecond = 0, false
    for r in pairs(lit) do
        count = count + 1
        if r.line == second then hasSecond = true end
    end
    T.ok(hasSecond, "the second zone row lights with the Best farm row")
    T.eq(count, 1, "only that row, the hovered one excepted")
    hover:GetScript("OnLeave")(hover)
end)

local function bestLine()
    for _, l in ipairs((GL.Drawn())) do
        if tostring(l.text):find("^Best farm") then return l.text end
    end
end

T.test("Farm: Profit is a section heading like the professions' and folds the same way", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return nil, item == 8170 and 20000 or 100 end)
    World.set(CP.Farm, "Items", function() return { LIGHT, 8170 } end)
    World.set(CP.Farm, "Find", function() return { zone = WINTERSPRING, score = 1 }, true end)
    GL.Refresh()
    local drawn = GL.Drawn()
    local head, skin
    for _, l in ipairs(drawn) do
        if l.kind == "section" and l.key == GL.PROFIT_KEY then head = l end
        if l.kind == "section" and l.key == SKIN then skin = l end
    end
    T.ok(head ~= nil and skin ~= nil, "both are sections")
    T.eq(head and head.indent, skin and skin.indent, "same indent")
    T.eq(head and head.subhead, nil, "not a subheading")
    T.ok(bestLine() ~= nil, "better zone listed while open")
    CP.db.farmClosed = { [GL.PROFIT_KEY] = true }
    GL.Refresh()
    drawn = GL.Drawn()
    T.eq(drawn[1].key, GL.PROFIT_KEY)
    T.eq(drawn[1].closed, true)
    T.eq(drawn[2].kind, "section", "its goods and better zones fold away")
    T.eq(bestLine(), nil)
    CP.db.farmClosed = nil
end)

T.test("Farm: cheap leather here and a dearer reachable zone shows Profit and a Best farm line", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return nil, item == 8170 and 20000 or 100 end)
    World.set(CP.Farm, "Items", function() return { LIGHT, 8170 } end)
    World.set(CP.Farm, "Find", function() return { zone = WINTERSPRING, score = 1 }, true end)
    GL.Refresh()
    T.eq(GL.Drawn()[1].text, GL.FARM_HEAD_PROFIT)
    T.ok(bestLine() and bestLine():find("Winterspring", 1, true), tostring(bestLine()))
end)

T.test("Farm: nothing reachable beats twice the best here, so Profit and no Best farm line", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return nil, item == 8170 and 150 or 100 end)
    World.set(CP.Farm, "Items", function() return { LIGHT, 8170 } end)
    World.set(CP.Farm, "Find", function() return { zone = WINTERSPRING, score = 1 }, true end)
    GL.Refresh()
    T.eq(GL.Drawn()[1].text, GL.FARM_HEAD_PROFIT)
    T.eq(bestLine(), nil, "no better zone")
end)

T.test("Farm: a zone the player's skills do not reach is never named", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return nil, item == 8170 and 20000 or 100 end)
    local asked
    World.set(CP.Farm, "Find", function(item, opts)
        asked = opts and opts.skills
        return nil, true
    end)
    GL.Refresh()
    T.ok(asked ~= nil, "Find gets the player's skills")
    T.eq(bestLine(), nil, "no zone named")
    local skills = { [SKIN] = 1 }
    T.ok(not CP.Farm.Find(8170, { level = 60, skills = skills, side = "Horde" }), "no Rugged Leather at Skinning 1")
end)

T.test("Farm: the higher of the auction and vendor price is shown and ranked", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return 900, 400 end)
    GL.Refresh()
    T.eq(GL.Drawn()[2].info, CP.Pricing.Format(900) .. " ea (Vendor)", "vendor beats the cheaper auction")
    World.set(CP.Pricing, "SaleValue", function(item) return 400, 900 end)
    GL.Refresh()
    T.eq(GL.Drawn()[2].info, CP.Pricing.Format(900) .. " ea (AH)", "auction beats the vendor")
end)

T.test("Farm: the heading says Prices Stale only for an auction price over a day old", function()
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return 100, 900 end)
    World.set(CP.Pricing, "AuctionAge", function() return 90000 end)
    GL.Refresh()
    T.eq(GL.Drawn()[1].text, GL.FARM_HEAD_STALE:format(1))
    World.set(CP.Pricing, "AuctionAge", function() return 3600 end)
    GL.Refresh()
    T.eq(GL.Drawn()[1].text, GL.FARM_HEAD_PROFIT, "fresh")
    World.set(CP.Pricing, "AuctionAge", function() return nil end)
    GL.Refresh()
    T.eq(GL.Drawn()[1].text, GL.FARM_HEAD_PROFIT, "no age given")
    World.set(CP.Pricing, "SaleValue", function(item) return 900, 100 end)
    World.set(CP.Pricing, "AuctionAge", function() return 90000 end)
    GL.Refresh()
    T.eq(GL.Drawn()[1].text, GL.FARM_HEAD_PROFIT, "vendor price is never stale")
end)

T.test("Farm: a stale heading says how old the oldest shown auction price is, in whole days", function()
    local DAY = 86400
    owner("farm")
    World.set(CP.Pricing, "SaleValue", function(item) return 100, 900 end)
    World.set(CP.Pricing, "AuctionAge", function() return DAY + 1 end)
    GL.Refresh()
    T.eq(GL.Drawn()[1].text, "Profit (Prices Stale - 1d old)", "just over a day reads 1d")
    -- Each shown good its own age; the heading names the oldest.
    local shown = {}
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "plan" and l.itemID then shown[#shown + 1] = l.itemID end
    end
    T.ok(#shown >= 2, "two or more goods shown: " .. #shown)
    local oldest = shown[#shown]
    World.set(CP.Pricing, "AuctionAge", function(item) return item == oldest and 3 * DAY + 600 or DAY + 60 end)
    GL.Refresh()
    T.eq(GL.Drawn()[1].text, "Profit (Prices Stale - 3d old)", "the oldest shown price")
    -- A better zone's auction price counts too.
    World.set(CP.Pricing, "SaleValue", function(item) return nil, item == 8170 and 20000 or 100 end)
    World.set(CP.Farm, "Items", function() return { LIGHT, 8170 } end)
    World.set(CP.Farm, "Find", function() return { zone = WINTERSPRING, score = 1 }, true end)
    World.set(CP.Pricing, "AuctionAge", function(item) return item == 8170 and 5 * DAY or 600 end)
    GL.Refresh()
    T.ok(bestLine() ~= nil, "a Best farm line")
    T.eq(GL.Drawn()[1].text, "Profit (Prices Stale - 5d old)", "the better zone's price is the oldest")
end)

T.test("a skill-up line shows the skill it gives points at, in the profession window's colour", function()
    scene({ skills = { [SKIN] = 272 }, needs = {} })
    local lines = CP.GatherList.SkillUpLines(BARRENS, SKIN, 272)
    T.ok(#lines > 0 and #lines <= GL.SKILLUP_LINES, "a few lines: " .. #lines)
    for _, l in ipairs(lines) do
        local skill, n = l.info:match("^skill (%d+) · lvl [%d-]+ · (%d+) spawns?$")
        T.ok(skill and n, l.info)
        T.eq(tonumber(skill), l.skill)
        T.eq(l.infoColor, RM.SKILL_COLOR[CP.GatherGuide.Difficulty(272, l.skill)], "its colour at 272")
        T.ok(l.pin ~= nil, "a pin to where it spawns most")
    end
    T.eq(#CP.GatherList.SkillUpLines(DUROTAR, SKIN, 272), 0, "Durotar's beasts are grey at 272")
end)

T.test("Farm's better zones come from what the player can farm: low beasts at level 20, high ones at 60", function()
    local skills = { [SKIN] = 272 }
    local low = CP.Farm.Items(skills, 20, GL.FARM_MIN_CHANCE)
    local high = CP.Farm.Items(skills, 60, GL.FARM_MIN_CHANCE)
    local function has(list, item)
        for _, i in ipairs(list) do if i == item then return true end end
        return false
    end
    T.ok(has(low, LIGHT), "Light Leather at level 20")
    for _, item in ipairs(low) do T.ok(has(high, item), "level 60 keeps what level 20 farms: " .. item) end
    T.ok(#high > #low, ("beasts far above level 20 add more at 60: %d against %d"):format(#high, #low))
    T.ok(has(high, 8170), "Rugged Leather at 60")
    T.ok(not has(CP.Farm.Items({}, 60, GL.FARM_MIN_CHANCE), LIGHT), "no Skinning, no leather")
end)

-- 7. Death, release and instances keep header and list on one zone ------------------------

local DESOLACE, FERALAS = 1443, 1444

-- The title names the listed zone, and every grind spot drawn is that zone's.
local function oneZone(tag)
    T.eq(GL.head.title:GetText(), C_Map.GetMapInfo(GL.zone).name, tag .. ": the title is the listed zone")
    local spots, at = RM.Spots()
    for _, l in ipairs((GL.Drawn())) do
        if l.spot then T.eq(at, GL.zone, tag .. ": a grind spot of the listed zone") end
    end
    return #spots
end

-- Owner's report, 2026-11-25: the Barrens picked in Farm, the player died, and afterwards the
-- panel listed the Barrens while the header named where the player stood (Shen'dralas). A ghost
-- or a spot by Dire Maul's courtyard can get no best map from the game; the zone under the spot
-- is then read from overlapping zone rectangles, and it can be the picked zone, which cleared
-- the pick as if the player had walked in.
for _, mode in ipairs({ "farm", false }) do
    T.test(("a pick survives death, release, a corpse run, a spirit healer and Dire Maul (%s)"):format(
        mode or "Follow the guide"), function()
        scene({ zone = DESOLACE, skills = { [SKIN] = 272 }, needs = { [LW] = { [HEAVY] = 232 } } })
        World.set(CP.db, "routeMode", mode or nil)
        World.set(CP.GatherPanel, "Showing", function() return true end)
        local dead = false
        World.set(_G, "UnitIsDeadOrGhost", function() return dead end)
        GL.SetZone(BARRENS)
        T.advance(5)
        T.ok(oneZone("picked") > 0, "the Barrens' grind spots")
        local function step(tag, fn)
            fn()
            T.advance(5)
            T.eq(CP.charDB.gatherZone, BARRENS, tag .. ": still picked")
            T.ok(GL.away and GL.zone == BARRENS, tag .. ": still listing the pick")
            oneZone(tag)
        end
        step("dead", function()
            dead = true
            T.fire("PLAYER_DEAD")
        end)
        step("released to a spot with no map", function()
            MapWorld.Move(FERALAS, 0.7, 0.5, { best = false, subZone = "Shen'dralas" })
            T.fire("PLAYER_ENTERING_WORLD")
        end)
        step("corpse run", function() MapWorld.Move(FERALAS, 0.6, 0.5) end)
        step("spirit healer", function()
            dead = false
            T.fire("PLAYER_UNGHOST")
            T.fire("PLAYER_ALIVE")
        end)
        step("Dire Maul's courtyard, no map", function() MapWorld.Move(FERALAS, 0.7, 0.5) end)
        local S = MapWorld.state
        step("inside Dire Maul", function()
            S.instance, S.instanceName = 429, "Dire Maul"
            T.fire("PLAYER_ENTERING_WORLD")
        end)
        step("out again, the map back", function()
            S.instance, S.instanceName = nil, nil
            MapWorld.Move(FERALAS, 0.6, 0.3, { best = FERALAS })
            T.fire("PLAYER_ENTERING_WORLD")
        end)
        T.ok(GL.head.status:GetText():find("Feralas", 1, true), GL.head.status:GetText())
        MapWorld.Move(BARRENS, 0.5, 0.5, { best = BARRENS })
        T.advance(5)
        T.eq(CP.charDB.gatherZone, nil, "walking into the Barrens, with the game's map saying so, clears it")
        oneZone("arrived")
    end)
end
