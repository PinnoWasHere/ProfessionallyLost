-- Farm picks stay in Farm mode. The Farm menu's ticks (herbs and ore by name, leathers by
-- item) and Farm's folded sections are remembered for the next visit to Farm, and Follow
-- the guide never reads them: its rows, needs, grind spots, route, Next up and the menu's
-- Following lines are what they are with nothing unticked (owner report 2026-11-16: a
-- Skinning 233 Leatherworker in Desolace lost the whole Skinning section).

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local HBD = LibStub("HereBeDragons-2.0")
local SKIN, HERB, MINE = 393, 182, 186
local LW, ALCHEMY, BS = 165, 171, 164
local DESOLACE, DUROTAR = 1443, 1411
local HEAVY, THICK = 4234, 4304
local PEACEBLOOM, COPPER = 2447, 2770

-- The player in `spec.zone` at `spec.level` with gathering ranks `spec.skills`, the guides'
-- needs `spec.needs`, Follow the guide, nothing unticked, Next up open.
local function scene(spec)
    MapWorld.begin({ zone = spec.zone, x = 0.5, y = 0.5, level = spec.level, side = "Horde" })
    World.set(HBD, "GetWorldCoordinatesFromZone", function(_, x, y, z) return x * 1000 + z, y * 1000, 1 end)
    for _, key in ipairs({ "routeMode", "routeSkip", "skinSkip", "gatherClosed", "farmClosed" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.charDB, "gatherNeeds", spec.needs)
    World.set(CP.charDB, "gatherSoon", nil)
    World.set(GL, "nextOpen", true)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = spec.skills[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    G.ResetClusters()
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
        G.ResetClusters()
    end)
end

-- The route menu as the player opens it: radios by mode, checks in order.
local function menu()
    local m = { radios = {}, checks = {} }
    local root = {}
    local function entry(rec)
        function rec:SetResponse(r) self.response = r end
        function rec:SetEnabled(on) self.enabled = on end
        return rec
    end
    function root.CreateTitle(_, text) return entry({ text = text }) end
    function root.CreateRadio(_, text, get, set, data)
        m.radios[data] = entry({ text = text, get = get, set = set, data = data })
        return m.radios[data]
    end
    function root.CreateCheckbox(_, text, get, set, data)
        m.checks[#m.checks + 1] = entry({ text = text, get = get, set = set, data = data })
        return m.checks[#m.checks]
    end
    function root.CreateButton(_, text, fn) return entry({ text = text, fn = fn }) end
    World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    GL.RouteMenu(UIParent)
    return m
end

local function pickMode(mode)
    menu().radios[mode].set(mode)
    T.advance(0.1)
end

-- Unticks each Farm check whose data is in `which`; returns how many.
local function untick(which)
    local n = 0
    for _, c in ipairs(menu().checks) do
        if which[c.data] and c.get(c.data) then
            c.set(c.data)
            n = n + 1
        end
    end
    return n
end

-- Clicks the drawn section row `key`, as the player does.
local function clickSection(key)
    local _, rows = GL.Drawn()
    for _, r in ipairs(rows) do
        if r:IsShown() and r.line and r.line.kind == "section" and r.line.key == key then
            r:GetScript("OnClick")(r, "LeftButton")
            return true
        end
    end
    return false
end

-- What the panel shows and the route follows in `zone`, after the route has solved.
local function view(zone)
    GL.Refresh()
    local frames = 0
    repeat
        T.advance(0.05, 0.05)
        frames = frames + 1
    until not CP.GatherGuide.Warming() or frames > 4000
    T.advance(5)
    GL.Refresh()
    local out = { lines = {}, route = {}, spots = {}, following = GL.Following(zone), sections = {}, items = {} }
    for _, l in ipairs((GL.Drawn())) do
        out.lines[#out.lines + 1] = table.concat({ l.kind, tostring(l.text), tostring(l.info), tostring(l.closed) }, "|")
        if l.kind == "section" then out.sections[l.key] = l.closed and "closed" or "open" end
        if l.kind == "item" then out.items[l.row.itemID] = true end
    end
    for _, r in ipairs(GL.RouteRows(zone, nil, true)) do
        local names = {}
        for _, s in ipairs(r.sources) do names[#names + 1] = s.name end
        table.sort(names)
        out.route[#out.route + 1] = r.itemID .. ":" .. table.concat(names, ",")
    end
    table.sort(out.route)
    for _, s in ipairs((RM.Spots())) do out.spots[#out.spots + 1] = ("%.4f,%.4f"):format(s.x, s.y) end
    return out
end

local function routeHas(v, prefix)
    for _, r in ipairs(v.route) do
        if r:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- Two views equal, or a failure naming the first part and entry that differ.
local function same(a, b, what)
    for _, part in ipairs({ "lines", "route", "spots", "following" }) do
        local x, y = a[part], b[part]
        for i = 1, math.max(#x, #y) do
            if x[i] ~= y[i] then
                T.ok(false, ("%s: %s #%d was %s, now %s"):format(what, part, i, tostring(x[i]), tostring(y[i])))
                return
            end
        end
    end
    T.eq(b.sections, a.sections, what .. ": sections")
end

-- The screenshot's character: Skinning 233 in Desolace, Leatherworking needing Heavy and Thick.
local LEATHER = { zone = DESOLACE, level = 40, skills = { [SKIN] = 233 },
                  needs = { [LW] = { [HEAVY] = 319, [THICK] = 405 } } }

T.test("leathers unticked in Farm leave Follow the guide's Skinning section, spots and route whole", function()
    scene(LEATHER)
    local before = view(DESOLACE)
    T.eq(before.sections[SKIN], "open", "the guide shows its Skinning section")
    T.ok(before.items[HEAVY], "Heavy Leather's needs row")
    T.ok(before.items[THICK], "Thick Leather's needs row")
    T.ok(routeHas(before, HEAVY .. ":") and routeHas(before, THICK .. ":"), "both leathers on the route")
    T.ok(#before.spots > 0, "grind spots on the map")
    T.eq(before.sections.next, nil, "the panel draws no Next up")

    pickMode("farm")
    T.eq(untick({ [HEAVY] = true, [THICK] = true }), 2, "both leathers unticked in Farm")
    pickMode("level")
    same(before, view(DESOLACE), "Follow the guide after Farm picks")
end)

T.test("herbs and ore unticked in Farm leave Follow the guide's needs and loop whole", function()
    scene({ zone = DUROTAR, level = 20, skills = { [HERB] = 50, [MINE] = 50 },
            needs = { [ALCHEMY] = { [PEACEBLOOM] = 20 }, [BS] = { [COPPER] = 30 } } })
    local before = view(DUROTAR)
    T.ok(before.sections[HERB] == "open" and before.sections[MINE] == "open", "Herbalism and Mining sections")
    T.ok(routeHas(before, PEACEBLOOM .. ":") and routeHas(before, COPPER .. ":"), "the needs on the route")
    local nodes = 0
    for _, r in ipairs(before.route) do if r:sub(1, 1) == "-" then nodes = nodes + 1 end end
    T.ok(nodes > 0, "nodes that still give skill on the loop")

    pickMode("farm")
    local every = {}
    for _, c in ipairs(menu().checks) do every[c.data] = true end
    T.ok(every["Peacebloom"] and every["Copper Vein"], "the Farm menu lists them")
    T.ok(untick(every) >= 2, "every herb and ore unticked in Farm")
    pickMode("level")
    same(before, view(DUROTAR), "Follow the guide after Farm picks")
end)

T.test("back in Farm the picks and folds are as the player left them", function()
    scene(LEATHER)
    pickMode("farm")
    untick({ [HEAVY] = true, [THICK] = true })
    local farm = view(DESOLACE)
    T.eq(farm.sections[SKIN], "open", "Farm's Skinning section, for the leathers still ticked")
    T.ok(clickSection(SKIN), "Farm's Skinning section folded")
    farm = view(DESOLACE)
    T.eq(farm.sections[SKIN], "closed")

    pickMode("level")
    local guide = view(DESOLACE)
    T.eq(guide.sections[SKIN], "open", "a Farm fold leaves the guide's section open")
    T.ok(clickSection(SKIN), "the guide's own fold works")
    T.eq(view(DESOLACE).sections[SKIN], "closed")
    T.ok(clickSection(SKIN))
    T.eq(view(DESOLACE).sections[SKIN], "open", "and unfolds")

    pickMode("farm")
    for _, c in ipairs(menu().checks) do
        T.eq(c.get(c.data), not (c.data == HEAVY or c.data == THICK), "tick of " .. tostring(c.text))
    end
    same(farm, view(DESOLACE), "Farm after a visit to the guide")
    T.ok(not routeHas(farm, HEAVY .. ":") and not routeHas(farm, THICK .. ":"), "Farm routes no unticked leather")
end)
