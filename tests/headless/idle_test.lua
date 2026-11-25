-- Idle work: which frames run an OnUpdate and which tickers repeat, in each resting state.
-- Daylight UI's own rule (DaylightUI tests/test_lag.lua): no OnUpdate runs while nothing
-- happens, unless it is on a list with its reason, and no ticker repeats faster than 0.1 s.
--
-- The harness keeps its frame list to itself. Its T.advance asks IsVisible of every frame
-- holding an OnUpdate script, through the frame's widget method table, so wrapping IsVisible
-- in every method table lists them all. A frame whose own table overrides IsVisible is missed.
-- Tickers made before this file loads are missed too; a static check pins every NewTicker call
-- in the source.

local CP = ProfLost
local W, P, GP = CP.Window, CP.Panel, CP.GatherPanel
local LW, TAILOR, MINING, HERBALISM = 165, 197, 186, 182
local DUROTAR = 1411
local FASTEST_TICKER = 0.1

-- Live scripts allowed in any state, by label, with why they can't wait for an event.
local ALLOW = {
    ["lib HereBeDragons-Pins-2.0.updateFrame"] = "HereBeDragons moves its minimap pins each frame while the minimap shows",
}

-- Files allowed a ticker faster than FASTEST_TICKER, with why.
local FAST_ALLOW = {
    ["UI/Style.lua"] = "the plain fade without Daylight UI (ownFade, a pulse's steps); with Daylight UI"
        .. " loaded API.Fade runs it",
}

-- Each state's own live scripts, exactly.
local EXPECT = {
    idle = {},
    ["idle, route off"] = {},
    ["guide window"] = {
        "GatherPanel.tab child Frame",   -- the fold tab's mouse check, each HOVER_EVERY while the tab shows
    },
    ["gathering panel"] = {
        "GatherPanel.tab child Frame",
    },
    walking = {
        "Minimap child Frame",           -- the route's minimap lines follow the player while anything moves
    },
    ["profession window"] = {
        "GatherPanel.tab child Frame",   -- the guide window stands free: nothing follows the profession window
    },
}

-- Frames IsVisible was asked about while `polling`.
local polling, polled = false, {}
local wrapped = {}

local function wrap(methods)
    if type(methods) ~= "table" or wrapped[methods] or type(methods.IsVisible) ~= "function" then return end
    local isVisible = methods.IsVisible
    wrapped[methods] = isVisible
    methods.IsVisible = function(self, ...)
        if polling then polled[self] = true end
        return isVisible(self, ...)
    end
end

local TYPES = { "Frame", "Button", "CheckButton", "EditBox", "EventFrame", "ScrollFrame", "Slider", "StatusBar",
                "GameTooltip", "Cooldown", "Model", "PlayerModel", "MessageFrame", "ScrollingMessageFrame",
                "SimpleHTML", "ColorSelect" }
for _, t in ipairs(TYPES) do
    local ok, f = pcall(CreateFrame, t)
    if ok and f then wrap(getmetatable(f).__index) end
end
for _, f in ipairs({ UIParent, Minimap, WorldMapFrame, GameTooltip, DEFAULT_CHAT_FRAME }) do
    wrap(getmetatable(f).__index)
end

-- Tickers made from here on: period, handle, and the addon line that made it.
local tickers = {}
local newTicker = C_Timer.NewTicker
C_Timer.NewTicker = function(seconds, fn, n)
    local handle = newTicker(seconds, fn, n)
    local where = "?"
    for line in debugstack():gmatch("[^\n]+") do
        local file = line:match("^%s*(%a+/[%w_]+%.lua:%d+)")
        if file and not file:find("^tests/") then
            where = file
            break
        end
    end
    tickers[#tickers + 1] = { period = seconds, handle = handle, where = where }
    return handle
end

-- Labels ---------------------------------------------------------------------------------

local function isFrame(v) return type(v) == "table" and type(rawget(v, 0)) == "table" and rawget(v, 0).type ~= nil end

-- Frames reachable from ProfLost's modules and the loaded libraries, by their shortest path.
local function index()
    local names, seen, queue = {}, {}, {}
    local function push(v, path, depth)
        if type(v) ~= "table" or seen[v] then return end
        seen[v] = true
        if isFrame(v) and not names[v] then names[v] = path end
        queue[#queue + 1] = { v, path, depth }
    end
    for k, v in pairs(CP) do
        if type(k) == "string" and type(v) == "table" and k ~= "GatherData" and k ~= "Guides" and k ~= "db"
            and k ~= "charDB" then
            push(v, k, 1)
        end
    end
    for major, lib in pairs(LibStub.libs) do push(lib, "lib " .. major, 1) end
    local head = 1
    while queue[head] do
        local v, path, depth = queue[head][1], queue[head][2], queue[head][3]
        head = head + 1
        if depth < 4 then
            local n = 0
            for k in pairs(v) do
                n = n + 1
                if n > 400 then break end
            end
            if n <= 400 then
                for k, x in pairs(v) do
                    if type(k) == "string" and type(x) == "table" then push(x, path .. "." .. k, depth + 1) end
                end
            end
        end
    end
    return names
end

local function label(f, names)
    local name = f:GetName()
    if name then return name end
    if names[f] then return names[f] end
    local parent = rawget(f, 0).parent
    local kind = rawget(f, 0).type
    if parent then return label(parent, names) .. " child " .. kind end
    return "unparented " .. kind
end

-- `--orders` runs every test file in one process, so earlier files' scenes can leave frames
-- behind: a craft strip on a world's old profession window, under an unnamed frame ProfLost
-- doesn't hold. Frames that held an OnUpdate before this file loaded and hang under such a
-- frame are theirs, not this file's.
local before = {}
polling = true
T.advance(0.01)
polling = false
for f in pairs(polled) do
    if rawget(f, 0).scripts.OnUpdate then before[f] = true end
end

local function leftover(f, names)
    return before[f] == true and label(f, names):find("^UIParent child") ~= nil
end

-- What runs now: labels of live OnUpdate scripts, and tickers under FASTEST_TICKER.
-- `during`, when given, runs before each tenth of a second of the half second looked at.
local function live(during)
    polled = {}
    polling = true
    for _ = 1, 5 do
        if during then during() end
        T.advance(0.1)
    end
    polling = false
    local names, out = index(), {}
    for f in pairs(polled) do
        local st = rawget(f, 0)
        if st and st.scripts.OnUpdate and f:IsVisible() and not leftover(f, names) then
            out[#out + 1] = label(f, names)
        end
    end
    table.sort(out)
    local fast = {}
    for _, t in ipairs(tickers) do
        if not t.handle:IsCancelled() and t.period < FASTEST_TICKER
            and not FAST_ALLOW[t.where:match("^[^:]+")] then
            fast[#fast + 1] = ("%s every %.3f s"):format(t.where, t.period)
        end
    end
    return out, fast
end

-- Checks state `name` against EXPECT and prints what runs.
local function check(name, during)
    local out, fast = live(during)
    local own = {}
    for _, l in ipairs(out) do
        if not ALLOW[l] then own[#own + 1] = l end
    end
    print(("idle %s: %s"):format(name, #out > 0 and table.concat(out, "; ") or "nothing"))
    T.eq(table.concat(own, "; "), table.concat(EXPECT[name], "; "), name .. ": live OnUpdate scripts (hide the"
        .. " frame when idle, or add it to EXPECT with why)")
    T.eq(table.concat(fast, ", "), "", name .. ": tickers faster than " .. FASTEST_TICKER .. " s")
end

-- Scenes -------------------------------------------------------------------------------

-- Logged in with crafting and gathering skills in Durotar, the route on, the guide window
-- closed, the gathering panel folded, no profession window.
local function login(route)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde", shareSolves = true })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 60, [HERBALISM] = 40 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", true)
    World.set(CP.db, "gatherOpen", false)
    World.set(CP.db, "route", route ~= false)
    World.onEnd(function()
        W.opened = false
        W.Update()
    end)
    CP.Gather.UpdateAllNeeds()
    W.Update()
    CP.GatherList.Changed()
    T.advance(5)
    T.ok(not P.frame:IsShown(), "the guide window is closed")
end

T.test("idle after login: nothing runs each frame", function()
    login()
    T.ok(CP.RouteLines.Has(DUROTAR), "a route in the zone")
    check("idle")
end)

-- The harness's minimap has no size or view, and HereBeDragons finds no world position and
-- keeps the zone an earlier file left: this walk gives all four, the position moving by
-- `step` yards each call.
local function walk(step)
    local HBD = LibStub("HereBeDragons-2.0")
    local wx = 1000
    World.set(HBD, "GetPlayerWorldPosition", function() return wx, 500, 1 end)
    World.set(HBD, "GetPlayerZone", function() return DUROTAR end)
    World.set(HBD, "GetWorldCoordinatesFromZone", function(_, x, y) return 1000 + (x - 0.5) * 300, 500 + (y - 0.5) * 300, 1 end)
    World.set(Minimap, "GetWidth", function() return 140 end)
    World.patch("C_Minimap.GetViewRadius", function() return 200 end)
    return function() wx = wx + step end
end

T.test("walking with a route: the minimap lines follow, then rest", function()
    login()
    local step = walk(2)
    T.fire("PLAYER_STARTED_MOVING")
    check("walking", step)
    local lines = select(2, CP.RouteLines.Counts())
    T.ok(lines > 0, "lines on the minimap")
    T.advance(1)
    check("idle")
    T.ok(CP.RouteLines.MiniFrame():IsVisible() and select(2, CP.RouteLines.Counts()) == lines,
        "resting keeps the lines on the minimap")
    check("walking", step)   -- a walk the poll finds, without a start event (a mouse turn, a flight)
end)

T.test("idle with the route off: nothing runs each frame", function()
    login(false)
    check("idle, route off")
end)

T.test("the guide window open: only the fold tab's mouse check", function()
    login()
    W.Open()
    T.advance(2)
    T.ok(P.frame:IsShown(), "open")
    check("guide window")
end)

T.test("the gathering panel open with a route: only the fold tab's check", function()
    login()
    GP.Open()
    T.advance(3)
    T.ok(GP.Showing(), "the gathering panel shows")
    T.ok(CP.RouteLines.Has(DUROTAR), "a route in the zone")
    check("gathering panel")
end)

T.test("a profession window open: only the guide window's own fold tab check", function()
    login()
    W.Open()
    CraftWorld.Open(LW)
    T.advance(2)
    T.ok(P.frame:IsShown(), "the guide window shows")
    check("profession window")
    CraftWorld.Close()
    T.advance(2)
    check("guide window")
end)
