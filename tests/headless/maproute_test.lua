-- The world map's route button: ProfLost's trail glyph on the map that shows or hides the
-- route's line and stops on the world map and minimap (CP.db.routeOnMap). It leaves the
-- route itself alone: the panel's route button, CP.db.route, the grind spots and the solves.
-- Teal to brass while the route shows, dimmed while hidden or when there is no route here, gone
-- with "Icons on the map" off. A route is a node loop or grind spots. Hiding it removes the
-- stops, the grind spots and their lines. Scene as in mapicons_test.

local CP = ProfLost
local RM = CP.RouteMap
local GL = CP.GatherList
local MB = CP.MapButton
local Pins = LibStub("HereBeDragons-Pins-2.0")

-- Route pins live now, split into stops and grind spots, by wrapping the library's calls.
local live = { world = {}, mini = {} }

local function track()
    live.world, live.mini = {}, {}
    local saved = {}
    for _, name in ipairs({ "AddWorldMapIconMap", "AddMinimapIconMap", "RemoveAllWorldMapIcons",
                            "RemoveAllMinimapIcons" }) do
        saved[name] = Pins[name]
    end
    local function add(kind, name)
        Pins[name] = function(self, ref, icon, ...)
            if ref == "ProfLost_Route" then live[kind][icon] = true end
            return saved[name](self, ref, icon, ...)
        end
    end
    local function removeAll(kind, name)
        Pins[name] = function(self, ref, ...)
            if ref == "ProfLost_Route" then live[kind] = {} end
            return saved[name](self, ref, ...)
        end
    end
    add("world", "AddWorldMapIconMap")
    add("mini", "AddMinimapIconMap")
    removeAll("world", "RemoveAllWorldMapIcons")
    removeAll("mini", "RemoveAllMinimapIcons")
    World.onEnd(function()
        for name, fn in pairs(saved) do Pins[name] = fn end
    end)
end

-- Stop pins and grind pins live on the world map and minimap.
local function counts()
    local c = { stops = 0, grind = 0 }
    for _, kind in ipairs({ "world", "mini" }) do
        for icon in pairs(live[kind]) do
            if icon.spot then c.grind = c.grind + 1 else c.stops = c.stops + 1 end
        end
    end
    return c
end

local function scene(act, needs)
    MapWorld.begin({ zone = 1411, x = 0.5, y = 0.5, level = 20, side = "Horde", shareSolves = true })
    track()
    World.set(CP.db, "route", true)
    World.set(CP.db, "mapIcons", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.db, "routeOnMap", nil)
    CP.charDB.gatherNeeds = needs or { [165] = { [2318] = 200 }, [164] = { [2771] = 100 } }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == 393 or id == 186 then return { skillID = id, rank = 120, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.Gather, "UpdateAllNeeds", function() end)
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    CP.Gather.ResetClusters()
    World.onEnd(function()
        CP.db.route = false
        RM.Update(false, {})
        T.advance(1)
        CP.Gather.ResetClusters()
    end)
    act()
end

local function update()
    GL.RouteOnly()
    T.advance(5)
end

local function click(b)
    b:GetScript("OnClick")(b, "LeftButton")
end

T.test("the button sits on the world map with the gathering panel's trail glyph", function()
    local b = MB.button
    T.ok(b ~= nil, "made at load")
    T.eq(b:GetParent(), WorldMapFrame, "on the world map")
    local point, rel = b:GetPoint(1)
    T.eq(point, MB.PLACE.point)
    T.eq(rel, WorldMapFrame.ScrollContainer or WorldMapFrame, "in the map's corner")
    T.eq(b.icon.file, GL.ROUTE_ICON, "the panel's route glyph")
    T.eq(CP.DEFAULTS.routeOnMap, true, "the route shows by default")
end)

T.test("a click hides only the map's route line and stops; the panel's route stays", function()
    scene(function()
        update()
        local b = MB.button
        T.ok(b:IsShown(), "shown with a route")
        local before = counts()
        T.ok(before.stops > 0 and before.grind > 0, ("drawn: %d stops, %d grind"):format(before.stops, before.grind))
        T.ok(CP.RouteLines.Has(1411), "a route line")
        local panelShown = GL.head.route:IsShown()

        click(b)
        T.eq(CP.db.routeOnMap, false, "saved as false")
        local after = counts()
        T.eq(after.stops, 0, "stop pins gone")
        T.eq(after.grind, 0, "grind spots gone too")
        T.ok(not CP.RouteLines.Has(1411), "route line gone")
        T.eq(CP.db.route, true, "the route itself stays on")
        T.ok(GL.RouteOn(), "the panel's route button still reads on")
        T.eq(GL.head.route:IsShown(), panelShown, "the panel's button unchanged")
        T.ok(RM.Status() ~= nil, "the solve is kept")
        T.ok(b:IsShown(), "the button stays to bring it back")

        click(b)
        T.eq(CP.db.routeOnMap, true)
        T.eq(counts().stops, before.stops, "stops back")
        T.eq(counts().grind, before.grind, "grind spots back")
        T.ok(CP.RouteLines.Has(1411), "line back")
    end)
end)

T.test("the panel's route button leaves the map button's choice alone", function()
    scene(function()
        update()
        click(MB.button)
        GL.head.route:GetScript("OnClick")(GL.head.route, "LeftButton")
        T.eq(CP.db.route, false, "the panel turned the route off")
        T.eq(CP.db.routeOnMap, false, "the map's choice kept")
        GL.head.route:GetScript("OnClick")(GL.head.route, "LeftButton")
        T.eq(CP.db.routeOnMap, false)
    end)
end)

T.test("the glyph is in ProfLost's gradient while the route shows and dimmed while hidden", function()
    scene(function()
        update()
        local b = MB.button
        local grads = {}
        World.set(_G, "CreateColor", function(r, g, b2, a) return { r, g, b2, a } end)
        World.set(b.icon, "SetGradient", function(_, orient, lo, hi) grads[#grads + 1] = { orient, lo, hi } end)
        MB.Sync()
        T.eq(b.shade, "gradient")
        local g = grads[#grads]
        T.ok(g ~= nil, "a gradient set")
        T.eq(g[1], "HORIZONTAL")
        local function hex(c) return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
            math.floor(c[3] * 255 + 0.5)) end
        T.eq(hex(g[2]), CP.ACCENT[1], "teal at the left")
        T.eq(hex(g[3]), CP.ACCENT[#CP.ACCENT], "brass at the right")

        -- Daylight UI's hover paint ends at rest; the gradient comes back over it.
        local n = #grads
        b.icon:SetVertexColor(1, 1, 1, 1)
        T.ok(#grads > n, "the gradient is painted again at rest")

        click(b)
        T.eq(b.shade, "dim")
        n = #grads
        b.icon:SetVertexColor(1, 1, 1, 1)
        T.eq(#grads, n, "no gradient while hidden")

        -- Hidden reads as the plain label ink at full strength, the same after the map reopens.
        local ink, alpha
        World.set(b.icon, "SetVertexColor", function(_, r, g2, b3) ink = { r, g2, b3 } end)
        World.set(b.icon, "SetAlpha", function(_, a) alpha = a end)
        MB.Shade()
        T.eq(alpha, 1, "hidden: full strength")
        T.ok(ink and ink[1] == CP.Style.color.label[1] and ink[2] == CP.Style.color.label[2], "hidden: the label ink")
        ink = nil
        MB.Sync()
        T.eq(alpha, 1, "after the map reopens: still full strength")
        T.ok(ink ~= nil, "after the map reopens: the ink is painted again")
    end)
end)

T.test("hidden only with Icons on the map off", function()
    scene(function()
        update()
        local b = MB.button
        T.ok(b:IsShown())
        CP.Settings.Save("mapIcons", false)
        T.ok(not b:IsShown(), "icons off: hidden")
        CP.Settings.Save("mapIcons", true)
        T.advance(5)
        T.ok(b:IsShown(), "icons on: back")
    end)
end)

T.test("shown with grind spots and no node loop", function()
    scene(function()
        World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
            if id == 393 then return { skillID = id, rank = 120, modifier = 0 } end
            return nil
        end)
        CP.Gather.ResetClusters()
        update()
        local c = counts()
        T.eq(c.stops, 0, "no stops")
        T.ok(c.grind > 0, "grind spots drawn")
        T.ok(RM.HasRoute(), "grind spots are a route")
        T.ok(MB.button:IsShown(), "button shown")
        T.eq(MB.button.shade, "gradient", "not dimmed")
        T.eq(MB.Tip(), "Route: shown")

        click(MB.button)
        T.eq(counts().grind, 0, "grind spots hidden")
        T.ok(MB.button:IsShown(), "button stays")
        T.eq(CP.db.route, true, "panel route untouched")
        click(MB.button)
        T.ok(counts().grind > 0, "grind spots back")
    end, { [165] = { [2318] = 200 } })
end)

T.test("shown dimmed with no route at all, and the tooltip says so", function()
    scene(function()
        update()
        CP.db.route = false
        RM.Update(false, {})
        T.ok(not RM.HasRoute())
        local b = MB.button
        T.ok(b:IsShown(), "still shown so players find it")
        T.eq(b.shade, "dim", "dimmed")
        local title, hint = MB.Tip()
        T.eq(title, "Route: none here")
        T.ok(hint:find("no route", 1, true), hint)
    end)
end)

T.test("the choice survives a reload", function()
    scene(function()
        update()
        click(MB.button)
        T.eq(rawget(ProfLostDB, "routeOnMap"), false, "in the saved variables")
        RM.Forget()
        update()
        T.eq(counts().stops, 0, "no stops after a fresh solve")
        T.ok(not CP.RouteLines.Has(1411))
        T.eq(MB.button.shade, "dim")
    end)
end)

T.test("the tooltip names the state and what a click does", function()
    scene(function()
        update()
        local title, hint = MB.Tip()
        T.eq(title, "Route: shown")
        T.ok(hint:find("hide", 1, true), hint)
        CP.db.routeOnMap = false
        title, hint = MB.Tip()
        T.eq(title, "Route: hidden")
        T.ok(hint:find("show", 1, true), hint)
    end)
end)

-- Other addons' buttons in the map's bottom-left corner (OpenMap's bar, NeedRoll's dice button).
-- Rects are { left, bottom, right, top } from the container's bottom-left corner.
local function overlaps(x, y, size, r)
    return r[1] < x + size and r[3] > x and r[2] < y + size and r[4] > y
end

local OTHERS = {
    { 14, 14, 54, 54 },   -- OpenMap's toggle
    { 10, 10, 36, 36 },   -- NeedRoll's dice button
}

T.test("the button keeps clear of other addons' buttons in the corner", function()
    local x, y = MB.Slot({}, MB.SIZE)
    T.eq(x, MB.PLACE.x, "alone it keeps its corner")
    T.eq(y, MB.PLACE.y)
    for _, r in ipairs(OTHERS) do
        x, y = MB.Slot({ r }, MB.SIZE)
        T.ok(not overlaps(x, y, MB.SIZE, r), ("clear of %d,%d,%d,%d at %d,%d"):format(r[1], r[2], r[3], r[4], x, y))
    end
    x, y = MB.Slot(OTHERS, MB.SIZE)
    for _, r in ipairs(OTHERS) do T.ok(not overlaps(x, y, MB.SIZE, r), "clear of both") end
    T.eq(x, MB.PLACE.x, "stacked up the left edge")
    T.ok(y > 54, "above the highest")
end)

T.test("placed on the real map, it moves off a button found in a layer on the container", function()
    scene(function()
        update()
        local b = MB.button
        local corner = WorldMapFrame.ScrollContainer or WorldMapFrame
        local function rect(f, l, bt, r, t)
            World.set(f, "GetLeft", function() return l end)
            World.set(f, "GetBottom", function() return bt end)
            World.set(f, "GetRight", function() return r end)
            World.set(f, "GetTop", function() return t end)
            World.set(f, "GetEffectiveScale", function() return 1 end)
            World.set(f, "IsVisible", function() return true end)
        end
        local layer = CreateFrame("Frame", nil, corner)
        local dice = CreateFrame("Frame", nil, layer)
        rect(corner, 100, 200, 900, 700)
        rect(layer, 100, 200, 900, 700)         -- a layer across the map: not a button
        rect(dice, 110, 210, 136, 236)          -- 10,10 in, 26 wide
        World.set(layer, "GetChildren", function() return dice end)
        World.set(corner, "GetChildren", function() return layer end)
        World.set(WorldMapFrame, "GetChildren", function() end)
        World.set(b, "GetEffectiveScale", function() return 1 end)
        MB.Place()
        local _, _, _, x, y = b:GetPoint(1)
        T.ok(not overlaps(x, y, MB.SIZE, { 10, 10, 36, 36 }), ("at %s,%s"):format(tostring(x), tostring(y)))
        T.ok(y >= 36, "above the dice button")
    end)
end)

T.test("the button sits on a dark round backdrop", function()
    local b = MB.button
    T.eq(b:GetWidth(), MB.SIZE, "round button size")
    T.ok(b.disc ~= nil, "a backdrop")
    local r, g, bl, a = unpack(MB.DISC)
    T.ok(r == 0 and g == 0 and bl == 0 and a >= 0.8, "black and mostly opaque")
    T.ok(b.rim ~= nil, "a rim")
    T.eq(MB.SIZE, 29, "29 px across")
    T.eq(MB.RIM_PX, 2, "a 2 px rim")
    T.eq(b.rim:GetWidth(), MB.SIZE, "the rim fills the button")
    T.eq(b.disc:GetWidth(), MB.SIZE - 2 * MB.RIM_PX, "the disc sits inside the rim")
    T.ok(b.rimGradient == true, "the rim carries ProfLost's gradient")
    T.ok(MB.GLYPH < MB.SIZE, "the glyph sits inside the disc")
end)
