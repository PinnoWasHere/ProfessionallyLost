local _, CP = ...
if CP.stopped then return end

-- Draws gathering loops as lines. The world map draws a zone's loop on its zone map and
-- every loop of a continent on the continent map, placed by Waypoint.ContinentTransform.
-- The minimap draws the loop in the player's zone, following HereBeDragons' own placement
-- (world coordinates, its rotation and zoom radii), so the lines meet the stop pins; each
-- segment is clipped to its edge.

local HBD = LibStub("HereBeDragons-2.0")

local RouteLines = {}
CP.RouteLines = RouteLines

-- Blizzard's map frames, and GetMinimapShape, which minimap addons define (it isn't game API).
local function worldMap() return _G.WorldMapFrame end
local function minimap() return _G.Minimap end

local WORLD_PX, MINI_PX = 2.5, 2     -- line thickness on screen
local MINI_FPS = 30                  -- minimap redraws per second, at most
local EDGE_PX = 2                    -- lines stop this far inside the minimap's edge

-- HereBeDragons-Pins' minimap view diameters in yards by zoom, for clients without
-- C_Minimap.GetViewRadius.
local VIEW = {
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 },
}

local loops = {}        -- [zone] = { points = { { x, y } }, color = { r, g, b } }

-- Line pools ---------------------------------------------------------------------

local function pool(parent)
    return { parent = parent, lines = {}, used = 0 }
end

local function acquire(p)
    p.used = p.used + 1
    local line = p.lines[p.used]
    if not line then
        line = p.parent:CreateLine(nil, "OVERLAY")
        p.lines[p.used] = line
    end
    line:Show()
    return line
end

local function release(p)
    for i = 1, #p.lines do p.lines[i]:Hide() end
    p.used = 0
end

-- World map ----------------------------------------------------------------------

local world   -- { frame, pool }, built on first use

-- `zone`'s loop in `mapID`'s coordinates: as is on its own map, through the game's world
-- transforms on its continent map (as the grind pins are), else nil. Kept on the loop
-- per map.
local function pointsOn(loop, zone, mapID)
    if zone == mapID then return loop.points end
    loop.on = loop.on or {}
    local got = loop.on[mapID]
    if got == nil then
        got = false
        local t = CP.Waypoint.ContinentTransform(zone)
        if t and t.map == mapID then
            got = {}
            for i, p in ipairs(loop.points) do
                got[i] = { x = t.ox + t.sx * p.x, y = t.oy + t.sy * p.y }
            end
        end
        loop.on[mapID] = got
    end
    return got or nil
end

local function drawWorld()
    if not world then return end
    release(world.pool)
    local map = worldMap()
    if not (map and map:IsShown()) then return end
    local mapID = map:GetMapID()
    if not mapID then return end
    local canvas = world.frame
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = canvas:GetEffectiveScale() / map:GetEffectiveScale()
    local thick = WORLD_PX / (scale > 0 and scale or 1)
    for zone, loop in pairs(loops) do
        local points = pointsOn(loop, zone, mapID)
        local n = points and #points or 0
        local c = loop.color
        for i = 1, n >= 2 and n or 0 do
            local a, b = points[i], points[i % n + 1]
            local line = acquire(world.pool)
            line:SetColorTexture(c[1], c[2], c[3], 0.9 * (loop.alpha or 1))
            line:SetThickness(thick)
            line:SetStartPoint("TOPLEFT", canvas, a.x * w, -a.y * h)
            line:SetEndPoint("TOPLEFT", canvas, b.x * w, -b.y * h)
        end
    end
end

local function buildWorld()
    local map = worldMap()
    if world or not (map and map.AddDataProvider and MapCanvasDataProviderMixin) then return end
    local canvas = map:GetCanvas()
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    frame:SetFrameLevel(canvas:GetFrameLevel() + 50)
    world = { frame = frame, pool = pool(frame) }
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RefreshAllData() drawWorld() end
    function provider:OnMapChanged() drawWorld() end
    function provider:OnCanvasScaleChanged() drawWorld() end
    function provider:OnCanvasSizeChanged() drawWorld() end
    function provider:RemoveAllData() release(world.pool) end
    map:AddDataProvider(provider)
end

-- Minimap ------------------------------------------------------------------------

local mini      -- { frame, pool }
local last = {}
local drawn = false   -- the last drawMini placed lines

local function rotating()
    return GetCVar("rotateMinimap") == "1"
end

local function viewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then return C_Minimap.GetViewRadius() end
    local zoom = minimap():GetZoom()
    local indoors = tonumber(GetCVar("minimapZoom")) == zoom and "outdoor" or "indoor"
    return (VIEW[indoors][zoom] or 400) / 2
end

-- Clips the segment p..q (pixels from the minimap's centre) to a circle of radius `r`,
-- or to a square of half-side `r`. Returns the visible part, or nil.
local function clip(px, py, qx, qy, r, square)
    local dx, dy = qx - px, qy - py
    local t0, t1 = 0, 1
    if square then
        -- Liang-Barsky against |x| <= r, |y| <= r.
        for _, e in ipairs({ { -dx, px + r }, { dx, r - px }, { -dy, py + r }, { dy, r - py } }) do
            local p, q = e[1], e[2]
            if p == 0 then
                if q < 0 then return nil end
            else
                local t = q / p
                if p < 0 then t0 = math.max(t0, t) else t1 = math.min(t1, t) end
            end
        end
    else
        -- |p + t d| = r, a quadratic in t.
        local a = dx * dx + dy * dy
        local b = 2 * (px * dx + py * dy)
        local c = px * px + py * py - r * r
        if a == 0 then
            if c > 0 then return nil end
        else
            local disc = b * b - 4 * a * c
            if disc < 0 then return nil end
            local s = math.sqrt(disc)
            t0 = math.max(t0, (-b - s) / (2 * a))
            t1 = math.min(t1, (-b + s) / (2 * a))
        end
    end
    if t0 > t1 then return nil end
    return px + t0 * dx, py + t0 * dy, px + t1 * dx, py + t1 * dy
end
RouteLines.Clip = clip

-- Redraws the minimap's lines when the player, the view or the loop moved, or `force`.
-- True when it drew.
local function drawMini(force)
    if not mini then return false end
    local x, y, instance = HBD:GetPlayerWorldPosition()
    local zone = HBD:GetPlayerZone()

    -- HereBeDragons names the best map, a continent where the game maps a spot to no zone.
    if not (zone and CP.GatherData.zones[zone]) and next(loops) then zone = CP.Gather.PlayerZone() end
    local loop = zone and loops[zone]
    if not x or not loop or loop.noMini or #loop.points < 2 or not minimap():IsVisible() then
        if drawn then release(mini.pool) end
        drawn, last.loop = false, nil
        return false
    end
    local facing = rotating() and GetPlayerFacing() or 0
    local radius = viewRadius()
    local Minimap = minimap()
    local mw = Minimap:GetWidth()
    if not force and last.x == x and last.y == y and last.facing == facing and last.radius == radius
        and last.mw == mw and last.loop == loop then
        return false
    end
    last.x, last.y, last.facing, last.radius, last.mw, last.loop = x, y, facing, radius, mw, loop
    drawn = true
    release(mini.pool)
    if not facing or radius <= 0 then return true end

    -- World positions of the loop, cached on the loop.
    if not loop.world then
        loop.world = {}
        for i, p in ipairs(loop.points) do
            local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(p.x, p.y, zone)
            loop.world[i] = wx and { wx, wy, inst } or false
        end
    end
    local half = mw / 2
    local px = half / radius            -- pixels per yard
    local sinF, cosF = math.sin(facing), math.cos(facing)
    local turn = rotating()
    local shapeOf = _G.GetMinimapShape
    local shape = type(shapeOf) == "function" and shapeOf() or nil
    local square = shape ~= nil and shape ~= "ROUND"
    local function place(w)
        local dx, dy = x - w[1], y - w[2]
        if turn then dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF end
        return dx * px, -dy * px
    end
    local c = loop.color
    local n = #loop.world
    for i = 1, n do
        local a, b = loop.world[i], loop.world[i % n + 1]
        if a and b and a[3] == instance and b[3] == instance then
            local ax, ay = place(a)
            local bx, by = place(b)
            local sx, sy, ex, ey = clip(ax, ay, bx, by, half - EDGE_PX, square)
            if sx then
                local line = acquire(mini.pool)
                line:SetColorTexture(c[1], c[2], c[3], 0.85)
                line:SetThickness(MINI_PX)
                line:SetStartPoint("CENTER", Minimap, sx, sy)
                line:SetEndPoint("CENTER", Minimap, ex, ey)
            end
        end
    end
    return true
end

-- The lines follow the player at MINI_FPS while anything moves. After STILL seconds with
-- nothing to redraw the frame drops its OnUpdate (it stays shown: it holds the lines), and
-- a check every POLL_EVERY seconds, or the player starting to move or turn, starts it
-- again. With no loop for the minimap neither runs.
RouteLines.STILL, RouteLines.POLL_EVERY = 0.5, 0.2
local poll, follow

local function stopPoll()
    if poll then poll:Cancel() end
    poll = nil
end

-- Follows the player again, if a loop can show on the minimap.
local function wake()
    if not mini then return end
    stopPoll()
    mini.still = 0
    local any = false
    for _, loop in pairs(loops) do
        if not loop.noMini then any = true end
    end
    mini.frame:SetScript("OnUpdate", any and follow or nil)
end
RouteLines.Wake = wake

local function rest()
    mini.frame:SetScript("OnUpdate", nil)
    stopPoll()
    poll = C_Timer.NewTicker(RouteLines.POLL_EVERY, function()
        if drawMini(false) then wake() end
    end)
end

local wait = 0
follow = function(_, elapsed)
    wait = wait - elapsed
    mini.still = mini.still + elapsed
    if wait > 0 then return end
    wait = 1 / MINI_FPS
    if drawMini(false) then
        mini.still = 0
    elseif mini.still >= RouteLines.STILL then
        rest()
    end
end

local function buildMini()
    local Minimap = minimap()
    if mini or not Minimap then return end
    local frame = CreateFrame("Frame", nil, Minimap)
    frame:SetAllPoints(Minimap)
    frame:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    mini = { frame = frame, pool = pool(frame), still = 0 }
end

CP:On("PLAYER_STARTED_MOVING", wake)
CP:On("PLAYER_STARTED_TURNING", wake)
CP:On("MINIMAP_UPDATE_ZOOM", wake)

-- API ----------------------------------------------------------------------------

local held = false

local function redraw()
    if held then return end
    drawWorld()
    drawMini(true)
    wake()
end

-- Shows `points` ({ { x, y } } on `zone`'s map, a closed loop) in `color`, replacing
-- that zone's loop. Nil or fewer than two points clears it. `opts.alpha` scales the
-- lines' opacity; `opts.noMini` keeps the loop off the minimap.
function RouteLines.Set(zone, points, color, opts)
    if not zone then return end
    if points and #points >= 2 then
        loops[zone] = { points = points, color = color or { 1, 1, 1 },
            alpha = opts and opts.alpha, noMini = opts and opts.noMini }
    else
        loops[zone] = nil
    end
    buildWorld()
    buildMini()
    redraw()
end

function RouteLines.Clear(zone)
    if zone then loops[zone] = nil else wipe(loops) end
    redraw()
end

-- Holds the redraws while `fn` sets many loops, then draws once.
function RouteLines.Batch(fn)
    held = true
    local ok, err = pcall(fn)
    held = false
    redraw()
    if not ok then error(err, 0) end
end

function RouteLines.Has(zone) return loops[zone] ~= nil end

-- True while `zone`'s loop may show on the minimap.
function RouteLines.OnMinimap(zone) return loops[zone] ~= nil and not loops[zone].noMini end

-- Line counts on each surface, for tests.
function RouteLines.Counts()
    return world and world.pool.used or 0, mini and mini.pool.used or 0
end

-- The frame holding the minimap's lines, for tests.
function RouteLines.MiniFrame() return mini and mini.frame end
