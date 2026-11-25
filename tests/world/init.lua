-- The headless game's frame: what every world builds on. Loaded first, before the
-- worlds and every test file (tests/world/order.txt).
--
-- A world replaces game functions for one test with World.patch. Each patch keeps
-- the harness stub it covers and calls it first, so argument checks and T.calls
-- still work; the world's answer is what the addon gets. World.finish puts every
-- patch back in reverse order, and T.test calls it after each test, so a world
-- never outlives the test that started it.

World = { patches = {}, ends = {} }

local function parent(path)
    local t = _G
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        local nxt = rawget(t, parts[i])
        if type(nxt) ~= "table" then
            nxt = {}
            rawset(t, parts[i], nxt)
        end
        t = nxt
    end
    return t, parts[#parts]
end

-- Sets `t[key] = value` until the test ends.
function World.set(t, key, value)
    table.insert(World.patches, { t = t, key = key, old = rawget(t, key) })
    rawset(t, key, value)
end

-- The keys of `t` in a fixed order: numbers, then strings, each ascending, then any other keys.
-- Lua 5.1 and LuaJIT walk a table in different orders, so a loop whose order reaches a trace line,
-- a violation or a choice walks World.keys(t), not pairs(t).
local KEY_RANK = { number = 1, string = 2 }

local function keyBefore(a, b)
    local ra, rb = KEY_RANK[type(a)] or 3, KEY_RANK[type(b)] or 3
    if ra ~= rb then return ra < rb end
    if ra == 3 then return false end
    return a < b
end

function World.keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, keyBefore)
    return out
end

-- A patch returns World.PASS to give the harness stub's own answer.
World.PASS = {}

local function pack(...) return { n = select("#", ...), ... } end
local NONE = { n = 0 }

local function answer(base, ...)
    if ... == World.PASS then return unpack(base, 1, base.n) end
    return ...
end

-- Replaces the game function at `path` ("C_Map.GetBestMapForUnit") with `fn` until
-- the test ends. The harness stub runs first; `fn`'s returns are the answer.
function World.patch(path, fn)
    local t, key = parent(path)
    local stub = rawget(t, key)
    local callStub = type(stub) == "function"
    World.set(t, key, function(...)
        return answer(callStub and pack(stub(...)) or NONE, fn(...))
    end)
end

-- Worlds tell each other what happened ("craft:show", line), for the test's length.
-- True when a listener answers true (a replacement window took the craft window).
World.listeners = {}

function World.listen(fn)
    World.listeners[#World.listeners + 1] = fn
end

function World.emit(what, ...)
    local taken = false
    for _, fn in ipairs(World.listeners) do
        if fn(what, ...) == true then taken = true end
    end
    return taken
end

-- Runs `fn` when the test ends, before the patches come off.
function World.onEnd(fn)
    World.ends[#World.ends + 1] = fn
end

-- True when the scene drew the windows; World.finish then redraws them on the restored settings.
World.redraw = false

-- Ends the scene: closers first (newest first), then every patch in reverse, then a redraw.
function World.finish()
    local ends = World.ends
    World.ends = {}
    for i = #ends, 1, -1 do ends[i]() end
    -- A gathering guide job started in this test never runs on into the next, and nothing
    -- waits for its signal.
    if ProfLost and ProfLost.GatherGuide then
        ProfLost.GatherGuide.Stop()
        ProfLost.GatherList.waitingZones = false
        ProfLost.GuideTab.waitingZones = false
    end
    -- The harness's T.stub keeps a call's identity, so map caches can't see a stub come off.
    if ProfLost and ProfLost.Waypoint then ProfLost.Waypoint.ForgetMaps() end
    for i = #World.patches, 1, -1 do
        local p = World.patches[i]
        rawset(p.t, p.key, p.old)
    end
    World.patches, World.listeners = {}, {}
    if World.redraw then
        World.redraw = false
        World.Redraw()
    end
    -- A test that ends its worlds part way through plays on in a fresh scope.
    if World.inTest then World.scope() end
end

-- Draws the windows on the restored settings. The redraw's own plan caches and learned data
-- go to copies, so the restored saved data stays as it was.
function World.Redraw()
    local CP = ProfLost
    if not (CP and CP.Window and type(CP.db) == "table") then return end
    local char, learned = CP.charDB, {}
    if type(char) == "table" then CP.charDB = CopyTable(char) end
    for _, key in ipairs(World.LEARNED) do
        learned[key] = CP.db[key]
        CP.db[key] = learned[key] and CopyTable(learned[key])
    end
    CP.Window.Update()
    CP.charDB = char
    for _, key in ipairs(World.LEARNED) do CP.db[key] = learned[key] end
end

-- The saved data a test's player learns as it plays: footprints, finds, beasts seen skinned.
World.LEARNED = { "footprints", "finds", "skinSeen" }

-- Each test plays a copy of the character's saved data and of what the player learns, so
-- the plans, picks and finds it writes end with it.
function World.scope()
    local CP = ProfLost
    if CP and type(CP.charDB) == "table" then World.set(CP, "charDB", CopyTable(CP.charDB)) end
    if CP and type(CP.db) == "table" then
        for _, key in ipairs(World.LEARNED) do
            World.set(CP.db, key, CP.db[key] and CopyTable(CP.db[key]))
        end
    end
end

World.inTest = false

-- Every test ends its worlds, pass or fail.
local test = T.test
function T.test(name, fn, opts)
    test(name, function()
        World.scope()
        World.inTest = true
        local ok, err = pcall(fn)
        World.inTest = false
        World.finish()
        if not ok then error(err, 0) end
    end, opts)
end
