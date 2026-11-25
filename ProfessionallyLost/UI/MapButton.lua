local _, CP = ...
if CP.stopped then return end

-- The world map's route button: the gathering panel's trail glyph (Style.IconButton) on a dark
-- round backdrop in the map's bottom-left corner, above any other addon's button already there
-- (found by position, no list of names; OpenMap's bar and NeedRoll's dice button sit there). A click shows or hides the route's line and stops on the world
-- map and minimap, saved raw as CP.db.routeOnMap. A route is a node loop or grind spots. The
-- route itself, its solves and the panel's route button never read it. The glyph is ProfLost's
-- teal to brass (CP.ACCENT) while the route shows and dimmed while hidden or when there is no
-- route here. The button hides only with "Icons on the map" off.

local S = CP.Style
local RouteMap = CP.RouteMap
local GatherList = CP.GatherList

local MapButton = {}
CP.MapButton = MapButton

-- The map's quest log toggle holds the scroll container's bottom right, and other addons
-- its top right.
MapButton.PLACE = { point = "BOTTOMLEFT", x = 8, y = 8 }
MapButton.STRATA = "DIALOG"   -- above the map's pins
MapButton.SIZE = 29           -- the round button across
MapButton.RIM_PX = 2          -- the gradient rim's width
MapButton.GLYPH = 16          -- the trail glyph inside it
MapButton.GAP = 4             -- kept clear of another button
MapButton.BAND = 160          -- only buttons this near the map's bottom edge are looked at
MapButton.MIN, MapButton.MAX_W, MapButton.MAX_H = 10, 240, 80   -- what counts as a button
MapButton.DISC = { 0, 0, 0, 0.85 }
MapButton.RIM = { 0.55, 0.55, 0.55, 0.9 }
local MEDIA = CP.MEDIA

local function rgb(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- The tooltip's title and line.
function MapButton.Tip()
    if not RouteMap.HasRoute() then
        return "Route: none here", "There is no route on the map here yet."
    end
    if RouteMap.LineShown() then
        return "Route: shown", "Click to hide the route's line and stops on the map."
    end
    return "Route: hidden", "Click to show the route's line and stops on the map."
end

-- Where the button goes: `rects` are other buttons' { left, bottom, right, top } in the map
-- container's units from its bottom-left corner. It starts at PLACE and moves up past each
-- button it would touch, so it never overlaps one. Returns x, y from that corner.
function MapButton.Slot(rects, size)
    local x, y = MapButton.PLACE.x, MapButton.PLACE.y
    for _ = 1, #rects + 1 do
        local moved = false
        for _, r in ipairs(rects) do
            local across = r[1] < x + size + MapButton.GAP and r[3] > x - MapButton.GAP
            local touches = r[2] < y + size + MapButton.GAP and r[4] > y - MapButton.GAP
            if across and touches then
                y = r[4] + MapButton.GAP
                moved = true
            end
        end
        if not moved then break end
    end
    return x, y
end

local map = _G.WorldMapFrame
if not map then return end
local corner = map.ScrollContainer or map

local b
local hovering = false

-- At rest once Daylight UI's hover paint has eased back (b.over) and the mouse is off.
local function atRest()
    return not hovering and (b.over or 0) == 0
end

-- Teal at the left to brass at the right, as the title's letters run.
local function gradient()
    if not (b.icon.SetGradient and CreateColor) then return end
    local r1, g1, b1 = rgb(CP.ACCENT[1])
    local r2, g2, b2 = rgb(CP.ACCENT[#CP.ACCENT])
    b.icon:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))
end

-- The gradient while the route shows. Hidden, the glyph is the plain label ink at full strength,
-- painted again on every call so a reopened map reads the same; with no route here it is faint.
function MapButton.Shade()
    local any = RouteMap.HasRoute()
    local on = RouteMap.LineShown() and any
    b.shade = on and "gradient" or "dim"
    b.icon:SetDesaturated(not on)
    b.icon:SetAlpha((on or not any) and (on and 1 or GatherList.ROUTE_OFF_ALPHA) or 1)
    if on then
        if atRest() then gradient() end
    elseif atRest() then
        b.icon:SetVertexColor(unpack(S.color.label))
    end
end

-- Shown with map icons on, then shaded.
function MapButton.Sync()
    b:SetShown(CP.db ~= nil and CP.db.mapIcons ~= false)
    MapButton.Shade()
end

b = S.IconButton(map, { icon = "ui-data-location.png", art = GatherList.ROUTE_ICON, size = MapButton.SIZE,
    box = MapButton.SIZE,
    name = MapButton.Tip,
    onClick = function(self, button)
        if button and button ~= "LeftButton" then return end
        CP.db.routeOnMap = not RouteMap.LineShown()
        RouteMap.LineChanged()
        if GameTooltip:GetOwner() == self then self:GetScript("OnEnter")(self) end
    end })
b:SetSize(MapButton.SIZE, MapButton.SIZE)
b.icon:ClearAllPoints()
b.icon:SetSize(MapButton.GLYPH, MapButton.GLYPH)
b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)

-- A full circle in ProfLost's gradient, with the dark disc 2 px inside it: a 2 px gradient rim.
-- Daylight UI's own circle while it is loaded.
local CIRCLE = S.Daylight() and S.Media("shape-circle.png") or (MEDIA .. "Dot")
b.rim = b:CreateTexture(nil, "BACKGROUND", nil, -2)
b.rim:SetPoint("CENTER")
b.rim:SetSize(MapButton.SIZE, MapButton.SIZE)
b.rim:SetTexture(CIRCLE)
b.rim:SetVertexColor(unpack(MapButton.RIM))
if b.rim.SetGradient and CreateColor then
    local r1, g1, b1 = rgb(CP.ACCENT[1])
    local r2, g2, b2 = rgb(CP.ACCENT[#CP.ACCENT])
    b.rim:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))
    b.rimGradient = true
end
b.disc = b:CreateTexture(nil, "BACKGROUND", nil, -1)
b.disc:SetPoint("CENTER")
b.disc:SetSize(MapButton.SIZE - 2 * MapButton.RIM_PX, MapButton.SIZE - 2 * MapButton.RIM_PX)
b.disc:SetTexture(CIRCLE)
b.disc:SetVertexColor(unpack(MapButton.DISC))

b:SetPoint(MapButton.PLACE.point, corner, MapButton.PLACE.point, MapButton.PLACE.x, MapButton.PLACE.y)
b:SetFrameStrata(MapButton.STRATA)
b:RegisterForClicks("LeftButtonUp")
MapButton.button = b

-- The button's hover paints the icon's colour; at rest the gradient goes back over it.
hooksecurefunc(b.icon, "SetVertexColor", function()
    if b.shade == "gradient" and atRest() then gradient() end
end)
b:HookScript("OnEnter", function() hovering = true end)
b:HookScript("OnLeave", function()
    hovering = false
    MapButton.Shade()
end)

-- The frames on the map that might be buttons: the map's, the container's and their children's
-- (NeedRoll's dice button is a child of a layer on the container).
local function candidates()
    local list = {}
    local function add(f)
        if type(f) == "table" and f ~= b then list[#list + 1] = f end
    end
    for _, f in ipairs(map.overlayFrames or {}) do add(f) end
    for _, parent in ipairs({ map, corner }) do
        if parent.GetChildren then
            for _, child in ipairs({ parent:GetChildren() }) do
                add(child)
                if child ~= b and child.GetChildren then
                    for _, kid in ipairs({ child:GetChildren() }) do add(kid) end
                end
            end
        end
    end
    return list
end

-- Other buttons' rects in the container's units from its bottom-left corner.
function MapButton.Others()
    local out = {}
    local cs = corner:GetEffectiveScale() or 1
    local cl, cb = corner:GetLeft(), corner:GetBottom()
    if not (cl and cb) then return out end
    for _, f in ipairs(candidates()) do
        pcall(function()
            if f.IsForbidden and f:IsForbidden() then return end
            if not (f.IsVisible and f:IsVisible()) then return end
            local l, bt, r, t = f:GetLeft(), f:GetBottom(), f:GetRight(), f:GetTop()
            if not (l and bt and r and t) then return end
            local s = f:GetEffectiveScale() or 1
            l, bt, r, t = (l * s - cl * cs) / cs, (bt * s - cb * cs) / cs, (r * s - cl * cs) / cs, (t * s - cb * cs) / cs
            local w, h = r - l, t - bt
            if w < MapButton.MIN or h < MapButton.MIN or w > MapButton.MAX_W or h > MapButton.MAX_H then return end
            if bt > MapButton.BAND or t < 0 then return end
            out[#out + 1] = { l, bt, r, t }
        end)
    end
    return out
end

-- Puts the button in the corner, clear of the others.
function MapButton.Place()
    if not (b:IsShown() and corner:GetLeft()) then return end
    local x, y = MapButton.Slot(MapButton.Others(), MapButton.SIZE)
    local k = (corner:GetEffectiveScale() or 1) / (b:GetEffectiveScale() or 1)
    b:ClearAllPoints()
    b:SetPoint(MapButton.PLACE.point, corner, MapButton.PLACE.point, x * k, y * k)
end

-- Other addons place their buttons on the map's events too, some a moment later.
local function placeSoon()
    MapButton.Place()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, MapButton.Place)
        C_Timer.After(0.4, MapButton.Place)
    end
end

map:HookScript("OnShow", function()
    MapButton.Sync()
    placeSoon()
end)
if corner.HookScript then corner:HookScript("OnSizeChanged", placeSoon) end
b:Hide()
