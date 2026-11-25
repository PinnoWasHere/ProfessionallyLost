-- Third in-game round: drawn +/- toggles, the checklist scroll bar, the pattern
-- popup's snooze.

local CP = ProfLost

-- The guide window open, as a profession window finds it. Returns the undo.
local function windowOpen()
    local was = CP.db.windowClosed
    CP.db.windowClosed = nil
    CP.Window.Update()
    -- The window is drawn again on the restored setting once the test ends.
    World.redraw = true
    return function() CP.db.windowClosed = was end
end

T.test("a toggle draws a plus when closed and a minus when open", function()
    local t = CP.Style.Toggle(UIParent, 10)
    T.ok(t.across:IsShown(), "the bar across is always there")
    T.ok(t.down:IsShown(), "closed: plus")
    t:SetOpen(true)
    T.ok(not t.down:IsShown(), "open: minus")
    T.eq(t.open, true)
    t:SetOpen(false)
    T.ok(t.down:IsShown(), "closed again: plus")
end)

T.test("the checklist scroll bar stays hidden when every line fits", function()
    -- A list of its own, with nothing to gather, not one an earlier test drew.
    MapWorld.begin({})
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function() return nil end)
    World.set(CP.charDB, "gatherNeeds", {})
    World.set(CP.charDB, "gatherZone", nil)
    CP.GatherList.Refresh()
    local bar = CP.GatherList.scrollBar
    T.ok(bar ~= nil, "made with the checklist")
    T.ok(not bar:IsShown(), "nothing to scroll: no bar")
    T.ok(CP.GatherList.RoomRows() >= 1, "at least one row always fits")
end)

T.test("the zone's patterns sit collapsed in the checklist, pulse when new, then show a red count", function()
    local GL = CP.GatherList
    local saved = { time = GetTime, popup = StaticPopupDialogs["ProfLost_VENDOR_HERE"] }
    local now = 1000
    GetTime = function() return now end
    local found = {
        { buy = { name = "Strider Stew", skill = 50, item = 1 }, target = { name = "Kilxx", continent = 1, x = 1, y = 1 } },
        { buy = { name = "Deviate Scale Cloak", skill = 65, item = 2, limited = true },
          target = { name = "Kalldan", continent = 1, x = 2, y = 2 } },
    }
    local current = { zone = 1413, found = found }
    local ok, err = pcall(function()
        T.eq(saved.popup, nil, "no popup any more")
        GL.Notify(#found)
        local lines = GL.PatternLines(current)
        T.eq(#lines, 1, "collapsed: just the header")
        T.eq(lines[1].text, "Patterns to buy here")
        T.ok(lines[1].pulse, "new patterns: the header pulses")
        T.eq(lines[1].badge, nil, "no count while pulsing")
        now = now + 21
        lines = GL.PatternLines(current)
        T.ok(not lines[1].pulse, "the pulse ends")
        T.eq(lines[1].badge, "2", "then a red count")
        GL.patternsOpen, GL.unseen = true, 0   -- what clicking the header does
        lines = GL.PatternLines(current)
        T.eq(lines[1].badge, nil, "opened: the count clears")
        T.eq(lines[2].kind, "vendor")
        T.eq(lines[3].text, "Strider Stew")
        T.ok(lines[1].pin ~= nil and lines[2].pin ~= nil, "mark all, or one vendor")
        local limited
        for _, l in ipairs(lines) do if l.kind == "pattern" and l.limited then limited = l end end
        T.ok(limited and limited.text == "Deviate Scale Cloak", "limited stock is flagged")
        T.eq(limited.itemID, 2, "pattern rows carry the pattern item for their tooltip")
        GL.Notify(1)
        T.ok(not GL.patternsOpen, "a new zone starts collapsed again")
        T.ok(GL.PatternLines(current)[1].pulse, "and pulses again")
    end)
    GetTime = saved.time
    GL.pulseUntil, GL.unseen, GL.patternsOpen = 0, 0, false
    T.ok(ok, err)
end)

-- Simulator finding, 2026-11-16 (controls, roundtrip): the setting off and on lost the count.
T.test("Pattern vendors off and on keeps the unseen count; another zone does not", function()
    local GL, VW = CP.GatherList, CP.VendorWatch
    local now, zone, seen = 1000, 1413, {}
    World.set(VW, "current", VW.current)
    World.set(_G, "GetTime", function() return now end)
    World.set(CP.Waypoint, "PlayerZone", function() return zone end)
    World.set(VW, "Find", function(z)
        local out = {}
        for i = 1, 2 do
            local tag = i .. ":" .. z
            out[i] = { buy = { name = "Pattern " .. i, skill = 50, item = i }, tag = tag, new = not seen[tag],
                       target = { name = "Kilxx", continent = 1, x = 1, y = 1 } }
            seen[tag] = true
        end
        return out
    end)
    World.set(CP.db, "vendorAlerts", true)
    World.onEnd(function() GL.pulseUntil, GL.unseen, GL.patternsOpen = 0, 0, false end)
    local function badge() return GL.PatternLines(VW.current)[1].badge end

    VW.Check()
    now = now + 21
    T.eq(badge(), "2", "two unseen patterns, counted once the pulse ends")
    CP.Settings.Set("vendorAlerts", false)
    T.eq(VW.current, nil, "off: no patterns listed")
    CP.Settings.Set("vendorAlerts", true)
    now = now + 21
    T.eq(badge(), "2", "on again: the same count")

    -- A zone whose patterns were all seen before shows no count carried from the last zone.
    zone = 1411
    VW.Check()
    now = now + 21
    T.eq(badge(), "2", "a new zone counts its own")
    zone = 1413
    VW.Check()
    T.eq(badge(), nil, "back in the first zone: nothing new, no count carried over")
end)

-- Simulator finding, 2026-11-17 (controls, roundtrip): a profession's first plan filled its watch
-- list, but the zone's patterns showed only after the next zone change or window close.
T.test("a watch list that changes re-reads the zone's patterns", function()
    local GL, VW = CP.GatherList, CP.VendorWatch
    local LW = 165
    local buy = { name = "Pattern 1", skill = 50, item = 1 }
    World.set(CP.Waypoint, "PlayerZone", function() return 1413 end)
    World.set(CP.charDB, "vendorWatch", nil)
    World.set(CP.db, "vendorAlerts", true)
    World.set(VW, "current", VW.current)
    World.set(CP.Guide, "VendorBuys", function() return { buy } end)
    World.set(VW, "Find", function(z)
        local watched = CP.charDB.vendorWatch and CP.charDB.vendorWatch[LW]
        if not watched then return {} end
        return { { buy = buy, tag = "1:" .. z, new = true, target = { name = "Kilxx", continent = 1, x = 1, y = 1 } } }
    end)
    World.onEnd(function()
        VW.current = nil
        GL.pulseUntil, GL.unseen, GL.patternsOpen = 0, 0, false
    end)

    T.advance(6)   -- a zone check already on its way runs first
    VW.Check()
    T.eq(VW.current, nil, "nothing watched yet")
    VW.Update({ guide = CP.Guides[LW], learned = {}, prof = { max = 75 } })
    T.advance(0.1)
    T.ok(VW.current ~= nil and #VW.current.found == 1, "the new pattern is listed")
end)

T.test("the pattern popup groups by vendor and colours limited stock in the accent", function()
    local a = { name = "Kilxx", continent = 1, x = 1, y = 1 }
    local b = { name = "Kalldan", continent = 1, x = 2, y = 2 }
    local found = {
        { buy = { name = "Strider Stew", skill = 50, item = 1 }, target = a },
        { buy = { name = "Deviate Scale Cloak", skill = 65, item = 2, limited = true }, target = b },
        { buy = { name = "Bristle Whisker Catfish", skill = 100, item = 3 }, target = a },
    }
    local groups = CP.VendorWatch.ByVendor(found)
    T.eq(#groups, 2, "one group per vendor")
    T.eq(#groups[1].buys, 2, "Kilxx sells two")
    local text = CP.VendorWatch.Text(found)
    local c = CP.Style.color.accent
    local hex = ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
    T.ok(text:find(hex .. "Deviate Scale Cloak", 1, true) ~= nil, "limited stock in the accent")
    T.ok(text:find("Mark all 2 vendors", 1, true) ~= nil, "offers every vendor at once")
end)

T.test("a vendor waypoint target carries its creature display id for the portrait pin", function()
    local guide = CP.Guides[185]
    local entry, npc
    for e, n in pairs(guide.npcs) do
        if n.display then entry, npc = e, n break end
    end
    T.ok(npc ~= nil, "guides carry display ids")
    local zone = CP.Waypoint.SpawnZone(npc[3][1])
    if zone then
        local t = CP.Waypoint.InZone({ entry }, guide.npcs, zone)
        if t then T.eq(t.display, npc.display) end
    end
end)

T.test("Mark on map picks the nearest vendor from the player's map position", function()
    local W, saved = CP.Waypoint, {}
    local function vec(x, y) return { GetXY = function() return x, y end } end
    saved.locate, saved.place, saved.pos = W.Locate, W.Place, C_Map.GetPlayerMapPosition
    local spots = { Far = { 0.9, 0.9 }, Near = { 0.45, 0.6 } }
    W.Locate = function(t) return 1413, vec(spots[t.name][1], spots[t.name][2]) end
    local placed
    W.Place = function(t, quiet) placed = t.name; saved.quiet = quiet; return true end
    saved.show = StaticPopup_Show
    local shown
    StaticPopup_Show = function(which, text) shown = { which, text } end
    C_Map.GetPlayerMapPosition = function() return vec(0.44, 0.59) end
    local found = {
        { buy = { name = "A", skill = 1, item = 1 }, target = { name = "Far", x = 1, y = 1 } },
        { buy = { name = "B", skill = 2, item = 2 }, target = { name = "Near", x = 2, y = 2 } },
    }
    local said
    local print0 = CP.Print
    CP.Print = function(_, msg) said = msg end
    local ok, err = pcall(CP.VendorWatch.MarkAll, found, 1413)
    CP.Print = print0
    W.Locate, W.Place, C_Map.GetPlayerMapPosition = saved.locate, saved.place, saved.pos
    StaticPopup_Show = saved.show
    CP.VendorWatch.ClearPins()
    T.ok(ok, err)
    T.eq(placed, "Near")
    T.eq(saved.quiet, true, "Place stays quiet: the one chat line below says it")
    T.eq(shown, nil, "no popup")
    T.ok(said and said:find("^Waypoints set for 2 vendors") ~= nil, "plural for two vendors: " .. tostring(said))
end)

T.test("pins come off one at a time, all at once, or on talking to the vendor", function()
    local W, VW, saved = CP.Waypoint, CP.VendorWatch, {}
    local function vec(x, y) return { GetXY = function() return x, y end } end
    local spots = { A = { 0.5, 0.5 }, B = { 0.6, 0.6 }, C = { 0.9, 0.9 } }
    saved.locate, saved.place, saved.pos, saved.show = W.Locate, W.Place, C_Map.GetPlayerMapPosition, StaticPopup_Show
    saved.clear = C_Map.ClearUserWaypoint
    local placed, cleared = {}, 0
    W.Locate = function(t) return 1413, vec(spots[t.name][1], spots[t.name][2]) end
    W.Place = function(t) placed[#placed + 1] = t.name; return true end
    C_Map.GetPlayerMapPosition = function() return vec(0.5, 0.5) end
    C_Map.ClearUserWaypoint = function() cleared = cleared + 1 end
    StaticPopup_Show = function() end
    local function mark()
        return VW.MarkAll({
            { buy = { name = "a", skill = 1, item = 1 }, target = { name = "A", x = 1, y = 1, entry = 11 } },
            { buy = { name = "b", skill = 2, item = 2 }, target = { name = "B", x = 2, y = 2, entry = 22 } },
            { buy = { name = "c", skill = 3, item = 3 }, target = { name = "C", x = 3, y = 3, entry = 33 } },
        }, 1413)
    end
    local ok, err = pcall(function()
        mark()
        T.eq(placed[#placed], "A", "nearest first")
        T.ok(VW.Visited(11), "talking to A removes its pin")
        T.eq(placed[#placed], "B", "the arrow moves to the next nearest")
        T.eq(#VW.Marked(), 2)
        VW.Remove(VW.Marked()[2])
        T.eq(#VW.Marked(), 1, "right-click removes one")
        T.eq(cleared, 0, "the waypoint stays while a pin is left")
        VW.Remove(VW.Marked()[1])
        T.eq(cleared, 1, "the last pin gone clears the waypoint")
        mark()
        VW.RemoveAll()
        T.eq(#VW.Marked(), 0)
        T.eq(cleared, 2, "remove all clears the waypoint")
    end)
    W.Locate, W.Place, C_Map.GetPlayerMapPosition, StaticPopup_Show = saved.locate, saved.place, saved.pos, saved.show
    C_Map.ClearUserWaypoint = saved.clear
    VW.ClearPins()
    T.ok(ok, err)
end)

T.test("leaving the zone removes the pins and the waypoint, staying keeps them", function()
    local W, VW, saved = CP.Waypoint, CP.VendorWatch, {}
    local function vec(x, y) return { GetXY = function() return x, y end } end
    saved.locate, saved.place, saved.pos, saved.show = W.Locate, W.Place, C_Map.GetPlayerMapPosition, StaticPopup_Show
    saved.clear, saved.zone, saved.alerts = C_Map.ClearUserWaypoint, W.PlayerZone, CP.db.vendorAlerts
    local zone, cleared = 1413, 0
    W.Locate = function() return 1413, vec(0.5, 0.5) end
    W.Place = function() return true end
    W.PlayerZone = function() return zone end
    C_Map.GetPlayerMapPosition = function() return vec(0.4, 0.4) end
    C_Map.ClearUserWaypoint = function() cleared = cleared + 1 end
    StaticPopup_Show = function() end
    CP.db.vendorAlerts = false  -- the clear runs even with pattern alerts off
    local ok, err = pcall(function()
        VW.MarkAll({ { buy = { name = "a", skill = 1, item = 1 }, target = { name = "A", continent = 1, x = 1, y = 1 } } }, 1413)
        T.eq(#VW.Marked(), 1)

        T.fire("ZONE_CHANGED")  -- a subzone move inside the Barrens
        T.advance(3)
        T.eq(#VW.Marked(), 1, "same zone: pins stay")
        T.eq(cleared, 0, "same zone: waypoint stays")

        zone = 1411
        T.fire("ZONE_CHANGED_NEW_AREA")
        T.advance(3)
        T.eq(#VW.Marked(), 0, "left the zone: pins gone")
        T.eq(cleared, 1, "left the zone: waypoint cleared")
        T.eq(VW.marked, nil)
    end)
    W.Locate, W.Place, C_Map.GetPlayerMapPosition, StaticPopup_Show = saved.locate, saved.place, saved.pos, saved.show
    C_Map.ClearUserWaypoint, W.PlayerZone, CP.db.vendorAlerts = saved.clear, saved.zone, saved.alerts
    VW.ClearPins()
    T.ok(ok, err)
end)

T.test("a secret unit token or GUID is skipped, never passed to UnitGUID", function()
    local saved = { secret = issecretvalue, guid = UnitGUID, on = CP.db.unitTooltip }
    local passed
    issecretvalue = function(v) return v == "SECRET" end
    UnitGUID = function(unit)
        passed = unit
        if unit == "SECRET" then error("secret values are only allowed during untainted execution") end
        return "SECRET"
    end
    CP.db.unitTooltip = true
    local ok, err = pcall(function()
        T.eq(CP.UnitTooltip.Add(GameTooltip, "SECRET"), false, "secret token: nothing added")
        T.eq(passed, nil, "UnitGUID never sees the secret token")
        T.eq(CP.UnitTooltip.Add(GameTooltip, "mouseover"), false, "secret GUID: nothing added")
        T.eq(passed, "mouseover")
    end)
    issecretvalue, UnitGUID, CP.db.unitTooltip = saved.secret, saved.guid, saved.on
    T.ok(ok, err)
end)

T.test("inside Razorfen Kraul the checklist lists what the dungeon's creatures give", function()
    local G = CP.Gather
    local saved = { inside = IsInInstance, info = GetInstanceInfo }
    IsInInstance = function() return true, "party" end
    -- Outdoor zones looked up here would cache empty: the harness has no zone maps.
    saved.mapPos = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(z) return z end
    G.ResetClusters()
    GetInstanceInfo = function() return "Razorfen Kraul", "party", 1, "Normal", 5, 0, false, 47 end
    local ok, err = pcall(function()
        local zone = G.PlayerZone()
        T.eq(zone, G.INSTANCE + 47, "the instance's own key")
        T.ok(G.IsInstance(zone))
        local rows = G.ForZone(zone, { [G.SKINNING] = 194 }, { here = G.InZone })
        local skins = 0
        for _, row in ipairs(rows) do
            if row.prof == G.SKINNING then skins = skins + 1 end
        end
        T.ok(skins > 0, "skinnable creatures in RFK: " .. skins .. " items")
        for _, z in ipairs(CP.GatherGuide.Zones(G.SKINNING, 194) or {}) do
            T.ok(not G.IsInstance(z.zone), "gathering guides never pick a dungeon")
        end
    end)
    IsInInstance, GetInstanceInfo, CP.Waypoint.MapPosZone = saved.inside, saved.info, saved.mapPos
    G.ResetClusters()
    T.ok(ok, err)
    T.ok(not G.IsInstance(1413), "outdoor zones are not instances")
end)

T.test("a running batch shows Making X of N with a bar and Stop, not three Crafting buttons", function()
    local C = CP.Crafting
    local saved = { count = C.count, total = C.total, stop = StopTradeSkillRepeat }
    local stopped = false
    StopTradeSkillRepeat = function() stopped = true end
    local ok, err = pcall(function()
        C.count, C.total = 12, 15
        local made, total = C.Progress()
        T.eq(made, 3)
        T.eq(total, 15)
        local strip = C.Strip(UIParent)
        strip:Update()
        local plain = strip.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        T.eq(plain, "Making 4 of 15", "counts the one in progress")
        T.eq(strip.stop.label:GetText(), "Stop")
        strip.stop:GetScript("OnClick")(strip.stop)
        T.ok(stopped, "Stop ends the repeat")
    end)
    C.count, C.total, StopTradeSkillRepeat = saved.count, saved.total, saved.stop
    T.ok(ok, err)
end)

T.test("in Silverpine, fishing to 75 stays on the continent even when Mulgore feeds Cooking", function()
    local SILVERPINE, TIRISFAL, MULGORE, LONGJAW = 1421, 1420, 1412, 6289
    local far = { [MULGORE] = 1e9 }
    local plan = CP.Fishing.Plan({
        skill = 1, maxRank = 75, level = 15, zone = SILVERPINE, side = "Horde", cook = true,
        needs = { [LONGJAW] = 49 }, have = function() return 0 end,
        distance = function(z) return far[z] or (z == TIRISFAL and 900 or z == SILVERPINE and 0 or 2500) end,
    })
    T.ok(plan.zone ~= MULGORE, "not across the sea: zone " .. tostring(plan.zone))
end)

T.test("clicking a grind spot on the map sets a waypoint there", function()
    local saved = CP.Waypoint.PlaceOnMap
    local placed
    CP.Waypoint.PlaceOnMap = function(zone, x, y) placed = { zone, x, y } end
    local ok, err = pcall(function()
        local pin = CP.RouteMap.TestPin({ x = 0.3, y = 0.4, rank = 1, name = "Wolves", items = {}, parts = {} }, 1421)
        pin:GetScript("OnMouseUp")(pin, "LeftButton")
        T.eq(placed and placed[1], 1421)
        T.eq(placed and placed[2], 0.3)
        T.eq(placed and placed[3], 0.4)
    end)
    CP.Waypoint.PlaceOnMap = saved
    T.ok(ok, err)
end)

T.test("a row too long for the checklist moves its info to a line below", function()
    local GL = CP.GatherList
    local saved = GL.Measure
    GL.Measure = function(text) return #text * 9 end   -- 7 px a character
    local ok, err = pcall(function()
        local vendor = { kind = "vendor", text = "Andrew Hilbert", info = "Silverpine Forest (43.2, 40.7)", pin = function() end }
        local short = { kind = "pattern", text = "Smoked Bear Meat", info = "skill 40" }
        local out = GL.Wrap({ vendor, short }, false)
        T.eq(#out, 3, "the vendor takes two lines")
        T.eq(out[2].kind, "cont")
        T.eq(out[2].text, "Silverpine Forest (43.2, 40.7)", "location on the second line")
        T.eq(out[2].of, vendor, "clicks and tooltips act on the vendor")
        T.ok(vendor.wrapped, "the first line drops its info")
        T.eq(out[3], short, "a row that fits stays one line")
    end)
    GL.Measure = saved
    T.ok(ok, err)
end)

T.test("a name too long for the checklist breaks at spaces beside its short info", function()
    local GL = CP.GatherList
    local saved = GL.Measure
    GL.Measure = function(text) return #text * 9 end
    local ok, err = pcall(function()
        local line = { kind = "plan", text = "First Aid 180: Heavy Silk Bandage to 210", info = "need 65" }
        local out = GL.Wrap({ line }, false)
        T.ok(#out >= 2, "name split: " .. #out .. " lines")
        T.ok(not line.wrapped, "the info stays on the first line")
        local room = GL.width - 18 - 8 - #"need 65" * 9
        T.ok(#line.text * 9 <= room, "first piece fits beside the info: " .. line.text)
        local joined = { line.text }
        for i = 2, #out do
            T.ok(out[i].text ~= "need 65", "no line of its own for the info")
            joined[#joined + 1] = out[i].text
        end
        T.eq(table.concat(joined, " "), "First Aid 180: Heavy Silk Bandage to 210", "no words lost")
        T.eq(out[2].color, CP.Style.color.accent, "wrapped pieces keep the line's colour")
    end)
    GL.Measure = saved
    T.ok(ok, err)
end)

T.test("reopening the window reuses the plan until something changes", function()
    local P = CP.Plan
    local saved = { cur = CP.Professions.Current, rec = CP.Professions.Recipes, solve = P.Solve }
    local solves = 0
    CP.Professions.Current = function() return { id = 185, skill = 5, max = 75 } end
    CP.Professions.Recipes = function() return {} end
    P.Solve = function() solves = solves + 1; return { n = solves } end
    local ok, err = pcall(function()
        P.Invalidate()
        P.Current(); P.Current()
        T.eq(solves, 1, "second open: no new solve")
        P.Invalidate()
        P.Current()
        T.eq(solves, 2, "after a change: solved again")
    end)
    CP.Professions.Current, CP.Professions.Recipes, P.Solve = saved.cur, saved.rec, saved.solve
    P.Invalidate()
    T.ok(ok, err)
end)

T.test("the disenchant button lives outside the panel, so the panel never turns protected", function()
    -- In game: the secure button inside the panel made DaylightUI's close blocked in combat.
    CP.Panel.tabs.disenchant.refresh(CP.Panel.tabs.disenchant.content)
    local _, _, button = CP.DisenchantTab.State()
    T.ok(button ~= nil, "built")
    T.eq(button:GetParent(), UIParent, "parented to UIParent")
    local p = button
    local inside = false
    while p do
        if p == CP.Panel.frame then inside = true end
        p = p:GetParent()
    end
    T.ok(not inside, "not a descendant of the panel")
end)

T.test("Mark on map survives a map position with x but no y", function()
    -- In game (BugGrabber): VendorWatch.lua "arithmetic on local 'py' (a nil value)".
    local W, saved = CP.Waypoint, {}
    local function vec(x, y) return { GetXY = function() return x, y end } end
    saved.locate, saved.place, saved.pos, saved.show = W.Locate, W.Place, C_Map.GetPlayerMapPosition, StaticPopup_Show
    W.Locate = function(t) return 1413, vec(t.name == "Bad" and 0.5 or 0.4, t.name ~= "Bad" and 0.4 or nil) end
    W.Place = function() return true end
    StaticPopup_Show = function() end
    C_Map.GetPlayerMapPosition = function() return vec(0.44, nil) end
    local found = {
        { buy = { name = "A", skill = 1, item = 1 }, target = { name = "Bad", continent = 1, x = 1, y = 1 } },
        { buy = { name = "B", skill = 2, item = 2 }, target = { name = "Good", continent = 1, x = 2, y = 2 } },
    }
    local ok, err = pcall(CP.VendorWatch.MarkAll, found, 1413)
    W.Locate, W.Place, C_Map.GetPlayerMapPosition, StaticPopup_Show = saved.locate, saved.place, saved.pos, saved.show
    CP.VendorWatch.ClearPins()
    T.ok(ok, err)
end)

T.test("Tailoring at 260 with Mining, Herbalism and First Aid: the guide plans the open window's profession", function()
    local Prof, P = CP.Professions, CP.Panel
    MapWorld.begin({ zone = 1413, level = 50, side = "Horde" })
    CraftWorld.begin({ professions = { [197] = 260, [186] = 160, [182] = 160, [129] = 160 } })
    World.onEnd(windowOpen())
    CP.Gather.UpdateAllNeeds()
    CraftWorld.Open(197)
    local cur = Prof.Current()
    T.eq({ cur.id, cur.skill, cur.max }, { 197, 260, 300 })
    T.ok(Prof.IsOwn(), "the open window is the player's own profession")
    local learned, any = 0, 0
    for _, r in ipairs(Prof.Recipes()) do
        any = any + 1
        if r.learned then learned = learned + 1 end
    end
    T.ok(any > 100 and learned > 20, ("recipes %d, learned %d"):format(any, learned))
    local live = CP.Plan.Current()
    T.ok(live and live.plan and #live.plan > 0, "a plan for the open profession")
    T.ok(P.frame:IsShown(), "the guide window shows")
    T.ok(#CP.GuideTab.ui.rows > 0, "the Guide tab has rows")
    T.eq(CP.Sourcing.PlayerSkills(), { [197] = true, [186] = true, [182] = true, [129] = true },
        "the profession list and the skill list together")
    T.eq(CP.Gather.Skills(), { [186] = 160, [182] = 160 }, "gathering skills from the skill list")
    T.eq(CP.Gather.MaxRank(186), 225)
    T.ok((CP.Shared.Tag(197, 4306) or ""):find("First Aid") ~= nil, "Silk Cloth shows First Aid's share beside Tailoring")
    CraftWorld.Close()
    T.ok(P.frame:IsShown(), "closing the profession window leaves the guide window standing")
end)

T.test("opening a gathering profession shows its gathering guide", function()
    MapWorld.begin({ zone = 1421, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [186] = 100, [165] = 100 } })
    MapWorld.SettleGuides({ 186 })
    CraftWorld.Open(186)
    T.eq(CP.Professions.Current().name, "Mining")
    T.ok(CP.Panel.frame:IsShown())
    local rows = CP.GuideTab.ui.rows
    T.ok(#rows > 0, "Mining rows")
    local gathering = 0
    for _, r in ipairs(rows) do
        if r.gather or r.gatherRank then gathering = gathering + 1 end
    end
    T.eq(gathering, #rows, "every row a gathering stretch or a rank")
    CraftWorld.Open(165)
    T.eq(CP.Professions.Current().name, "Leatherworking", "a tab to another profession")
    T.ok(CP.GuideTab.ui.rows[1].recipe ~= nil, "crafting rows again")
end)

T.test("Daylight UI's craft window: the guide window stays free under UIParent", function()
    local Host, P = CP.Host, CP.Panel
    local panel = P.frame
    DaylightWorld.begin({ plugin = true })
    MapWorld.begin()
    CraftWorld.begin({ professions = { [165] = 100 } })
    World.onEnd(windowOpen())
    CraftWorld.Open(165)
    T.ok(Host.DaylightWindow(), "Daylight UI's window lists Leatherworking")
    T.eq(DaylightWorld.state.paneWidth, nil, "no pane asked for")
    T.ok(panel:GetParent() == UIParent and panel:IsShown(), "the guide window stands free")
    T.ok(CP.GatherPanel.shell:IsShown(), "the shared shell around it")
    CraftWorld.Close()
    T.ok(not Host.DaylightWindow())
    T.ok(panel:GetParent() == UIParent and panel:IsShown(), "still free and shown")
end)

T.test("with Daylight UI's window up, picking a step selects its recipe there, and their picks move the guide", function()
    local Host, Prof = CP.Host, CP.Professions
    local handlers, selected, listed = {}, {}, nil
    local me = { On = function(event, fn) handlers[event] = fn end }
    local api = { SelectCraftRecipe = function(id) selected[#selected + 1] = id return true end,
                  GetCraftProfession = function() return listed end }
    -- Tailoring open and drawn, so the guide has a profession to pick rows in.
    MapWorld.begin()
    CraftWorld.begin({ professions = { [197] = 60 } })
    World.onEnd(windowOpen())
    CraftWorld.Open(197)
    T.ok(Prof.IsOwn(), "the player's own Tailoring")
    World.set(Host.view, "me", Host.view.me)
    World.set(Host.view, "api", Host.view.api)
    T.ok(Host.UseDaylight(me, api), "its Craft events registered")
    Prof.Open(7836)
    T.eq(#selected, 0, "its window shut: the game's window is used")
    listed = 197
    handlers.CraftShown()
    Prof.Open(7836)
    T.eq(selected[1], 7836, "its window up: it selects the recipe")

    -- Their list picked a recipe: the guide follows to its row, once. The panel holds
    -- still, so the rows below stay the ones drawn.
    World.set(CP.Panel, "Refresh", function() end)
    local ui = CP.GuideTab.ui
    World.set(ui, "live", { alias = {} })
    World.set(ui, "rows", { { key = "step1", spell = 100 }, { key = "side1", side = true, spell = 200 },
                            { key = "step2", spell = 200 } })
    T.ok(CP.GuideTab.Follow(200), "a main step before its or-row")
    ui.rows = { { key = "step1", spell = 100 }, { key = "side1", side = true, spell = 200 }, { key = "step2", spell = 200 } }
    T.ok(not CP.GuideTab.Follow(200), "already picked: our own pick echoing back")
    T.ok(not CP.GuideTab.Follow(999), "a recipe no row has")
    listed = nil
    handlers.CraftHidden()
end)

T.test("Daylight UI's recipe lines: guide steps get an accent bar, the current one full", function()
    local CR = CP.CraftRows
    local painter
    local holders = {}
    local me = { Paint = function(kind, fn) T.eq(kind, "craftrow") painter = fn return {} end }
    local api = { Attach = function(line)
        holders[line] = holders[line] or CreateFrame("Frame", nil, line)
        return holders[line]
    end }
    local old = CR.Marks()
    T.ok(not CR.UseDaylight({}, api), "no Paint: nothing")
    T.ok(CR.UseDaylight(me, api), "a Daylight UI with Paint")
    local a, b, c = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
    CR.Set({ [10] = "current", [20] = "step" })
    painter(a, {}, { recipeID = 10 })
    painter(b, {}, { recipeID = 20 })
    painter(c, {}, { recipeID = 30 })
    T.ok(holders[a].cpBar:IsShown(), "current step marked")
    T.ok(holders[b].cpBar:IsShown(), "later step marked")
    T.ok(not holders[c].cpBar:IsShown(), "a recipe the guide doesn't use: no bar")
    CR.Set({ [30] = "current" })
    T.ok(not holders[a].cpBar:IsShown() and holders[c].cpBar:IsShown(), "the guide moving repaints the lines on show")
    painter(c, {}, nil)
    T.ok(not holders[c].cpBar:IsShown(), "a line with no info yet: no bar")
    CR.Set(old)
end)

T.test("Daylight UI's Create button drives the craft strip, and the game's cast events stand aside", function()
    local C = CP.Crafting
    local handlers = {}
    T.ok(C.UseDaylight({ On = function(event, fn) handlers[event] = fn end }))
    handlers.CraftStarted(7836, 5)
    T.ok(C.Busy(), "busy from their Create")
    T.ok(not C.ShowStrip(), "their window shows the progress, so our strip stays hidden")
    T.eq(select(2, C.Progress()), 5)
    handlers.CraftMade(7836, 2, 5)
    T.eq((C.Progress()), 2, "two made")
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 7836)
    T.eq((C.Progress()), 2, "the game's cast event doesn't count twice")
    handlers.CraftStopped(7836, 3, 5)
    T.ok(not C.Busy(), "stopped")
    handlers.CraftMade(7836, 4, 5)
    T.ok(not C.Busy(), "a stray made after stopping changes nothing")
end)

T.test("a tick plays only when Daylight UI confirms the recipe shows", function()
    local Prof, Host = CP.Professions, CP.Host
    local select = Host.SelectRecipe
    local sound, kits = _G.PlaySound, _G.SOUNDKIT
    local played = 0
    _G.PlaySound = function() played = played + 1 end
    _G.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856 }
    local ok, err = pcall(function()
        Host.SelectRecipe = function() return true end
        T.ok(Prof.Open(7836), "shown")
        Host.SelectRecipe = function() return false end
        T.ok(not Prof.Open(7836), "not shown: no answer from the game's call")
        CP.Style.Tick()
        T.eq(played, 1)
    end)
    Host.SelectRecipe, _G.PlaySound, _G.SOUNDKIT = select, sound, kits
    T.ok(ok, err)
end)
