-- ProfLost's map pins show only while a map holds them. HereBeDragons gives a released world
-- map pin to UIParent, hidden and unanchored; a map addon that hands it back there and shows
-- it (OpenMap's own view does) would put it in the middle of the screen. A pin given to
-- UIParent, or to no parent, goes to a hidden home instead, and a new pin starts there.
-- On the minimap, pins follow whatever minimap frame HereBeDragons holds: Blizzard's, one an
-- addon moved, resized, rescaled or made square, a HUD, or a replacement frame.

local CP = ProfLost
local RM = CP.RouteMap
local Pins = LibStub("HereBeDragons-Pins-2.0")

local SPOT = { x = 0.5, y = 0.5, rank = 1, of = 3, name = "Silithid Grub", items = {}, parts = {} }

-- A stand-in for HereBeDragons' world map pin, running the library's own acquire and release.
local function mapPin()
    local host = CreateFrame("Frame", nil, UIParent)
    for k, v in pairs(Pins.worldmapProviderPin) do
        if type(v) == "function" then host[k] = v end
    end
    host.UseFrameLevelType = function() end
    host.SetPosition = function() end
    return host
end

-- What a map addon does as its view ends: the pin goes back to the parent it had, centred
-- on it, and shows.
local function handBack(icon, parent)
    icon:SetParent(parent)
    icon:SetPoint("CENTER", parent, "CENTER")
    icon:Show()
end

local function pins()
    local vendor = { target = { name = "A" }, buys = { { name = "a", skill = 1, item = 1 } } }
    return {
        grind = RM.TestPin(SPOT, 1446),
        stop = RM.TestStop(),
        mini = RM.TestMiniStop(),
        vendor = CP.VendorWatch.TestPin(vendor),
    }
end

T.test("a new pin waits hidden until a map places it", function()
    for kind, f in pairs(pins()) do
        T.ok(f:GetParent() ~= UIParent and f:GetParent() ~= nil, kind .. " has a home")
        T.ok(not f:IsVisible(), kind .. " unseen before any map holds it")
    end
end)

T.test("a released world map pin handed back to UIParent stays hidden", function()
    for kind, f in pairs(pins()) do
        local host = mapPin()
        host:OnAcquired(f, 0.5, 0.5)
        T.eq(f:GetParent(), host, kind .. " on the map")
        T.ok(f:IsVisible(), kind .. " shows on the map")

        host:OnReleased()
        T.ok(not f:IsVisible(), kind .. " hidden after release")
        handBack(f, UIParent)
        T.ok(f:GetParent() ~= UIParent, kind .. " not on UIParent")
        T.ok(not f:IsVisible(), kind .. " not in the middle of the screen")

        handBack(f, nil)
        T.ok(not f:IsVisible(), kind .. " hidden with no parent")
        host:Hide()
    end
end)

T.test("the same pin placed again after a release shows on its map", function()
    local f = pins().grind
    local host = mapPin()
    host:OnAcquired(f, 0.5, 0.5)
    host:OnReleased()
    handBack(f, UIParent)
    host:OnAcquired(f, 0.5, 0.5)
    T.eq(f:GetParent(), host)
    T.ok(f:IsVisible())
    host:OnReleased()
    host:Hide()
end)

-- Minimap setups ------------------------------------------------------------------------
-- Each mock below stands for a kind of minimap addon. HereBeDragons places a pin on the
-- minimap frame it holds, at that frame's size, scale and shape, so the pin follows the
-- frame wherever an addon puts it.

local REF = "ProfLost_PinHome"
local YARDS = 40   -- the pin's distance from the player
local VIEW = 400   -- yards across the mock minimap

-- The Minimap's place, size, scale and parent, put back as the test ends.
local function keepMinimap()
    local mm = Pins.Minimap
    local was = { parent = mm:GetParent(), scale = mm:GetScale(), shown = mm:IsShown(), points = {} }
    was.w, was.h = mm:GetSize()
    for i = 1, mm:GetNumPoints() do was.points[i] = { mm:GetPoint(i) } end
    World.onEnd(function()
        mm:SetParent(was.parent)
        mm:SetScale(was.scale)
        mm:SetSize(was.w, was.h)
        mm:ClearAllPoints()
        for _, p in ipairs(was.points) do mm:SetPoint(unpack(p)) end
        mm:SetShown(was.shown)
        Pins:RemoveAllMinimapIcons(REF)
    end)
end

-- A grind pin YARDS from the player, and a function that runs HereBeDragons' own update
-- and returns the pin's anchor: point, frame, relative point, x, y.
local function placed()
    MapWorld.begin({ zone = 1411, x = 0.5, y = 0.5, level = 20, side = "Horde" })
    keepMinimap()
    -- Mock: the game's minimap at its default size, showing VIEW yards across.
    World.set(C_Minimap, "GetViewRadius", function() return VIEW / 2 end)
    Pins.Minimap:SetSize(140, 140)
    local HBD = LibStub("HereBeDragons-2.0")
    local x, y, instance = HBD:GetPlayerWorldPosition()
    T.ok(x and y and instance, "the player has a world position")
    local f = pins().grind
    T.ok(Pins:AddMinimapIconWorld(REF, f, instance, x, y - YARDS, true))
    return f, function()
        T.advance(2)
        return f:GetPoint(1)
    end
end

T.test("Blizzard's minimap: the pin sits on it, off its centre by the distance", function()
    local f, place = placed()
    local point, rel, _, ox, oy = place()
    T.eq(f:GetParent(), Pins.Minimap)
    T.eq(point, "CENTER")
    T.eq(rel, Pins.Minimap)
    -- 40 yards on a 400-yard, 140-pixel map is 14 pixels from the centre.
    local off = math.sqrt((ox or 0) ^ 2 + (oy or 0) ^ 2)
    T.ok(math.abs(off - 140 * YARDS / VIEW) < 1e-6, "off centre by the distance: " .. off)
    T.ok(f:IsVisible(), "shown")
end)

T.test("a moved, resized, rescaled square minimap (Daylight UI, ElvUI, Leatrix kind): the pin follows", function()
    local f, place = placed()
    local _, _, _, rx, ry = place()
    -- Mock: a panel a minimap addon moves the map into, square and twice the size.
    local panel = CreateFrame("Frame", nil, UIParent)
    World.onEnd(function() panel:Hide() end)
    local mm = Pins.Minimap
    local w, h = mm:GetSize()
    World.set(_G, "GetMinimapShape", function() return "SQUARE" end)
    mm:SetParent(panel)
    mm:ClearAllPoints()
    mm:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
    mm:SetSize(w * 2, h * 2)
    mm:SetScale(1.25)
    -- The game fires OnSizeChanged on a resize; the harness does not.
    local sized = mm:GetScript("OnSizeChanged")
    if sized then sized(mm, w * 2, h * 2) end
    local _, rel, _, ox, oy = place()
    T.eq(f:GetParent(), mm)
    T.eq(rel, mm)
    T.ok(math.abs(ox - rx * 2) < 1e-6 and math.abs(oy - ry * 2) < 1e-6,
        ("offset follows the size: %s,%s then %s,%s"):format(rx, ry, ox, oy))
    T.ok(f:IsVisible())
end)

T.test("a HUD minimap in the middle of the screen (FarmHud kind): the pin is on the HUD", function()
    local f, place = placed()
    -- Mock: a HUD frame over the screen centre that the minimap is moved into.
    local hud = CreateFrame("Frame", nil, UIParent)
    hud:SetPoint("CENTER", UIParent, "CENTER")
    World.onEnd(function() hud:Hide() end)
    local mm = Pins.Minimap
    mm:SetParent(hud)
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", hud, "CENTER")
    mm:SetScale(3)
    local _, rel = place()
    T.eq(rel, mm, "anchored to the minimap, not UIParent")
    T.ok(f:IsVisible())
    hud:Hide()
    T.ok(not f:IsVisible(), "gone with the HUD")
end)

T.test("a hidden minimap hides the pin, and it shows again with the minimap", function()
    local f, place = placed()
    place()
    Pins.Minimap:Hide()
    T.ok(not f:IsVisible(), "hidden")
    T.ok(f:GetParent() ~= UIParent)
    Pins.Minimap:Show()
    place()
    T.ok(f:IsVisible(), "back")
end)

T.test("a replacement minimap frame given to HereBeDragons carries the pin", function()
    local f, place = placed()
    place()
    -- Mock: a minimap addon's own Minimap-type frame, handed over with SetMinimapObject.
    local mine = CreateFrame("Frame", nil, UIParent)
    mine:SetSize(140, 140)
    local was = Pins.Minimap
    mine.GetZoom = function() return was:GetZoom() end
    mine.SetZoom = function() end
    local ok, err = pcall(function()
        Pins:SetMinimapObject(mine)
        local _, rel = place()
        T.eq(f:GetParent(), mine)
        T.eq(rel, mine)
        T.ok(f:IsVisible())
    end)
    Pins:SetMinimapObject(was)
    mine:Hide()
    T.ok(ok, err)
end)
