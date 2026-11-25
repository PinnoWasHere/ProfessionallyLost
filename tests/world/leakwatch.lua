-- The leak watch: names the test file that leaves shared state changed.
--
-- The single-process order runner (check.py --orders) loads every test file into one process. It puts
-- tests/world/leakmark.lua before the first test file and after each one. The first mark takes a
-- snapshot of the watched state and starts the timer watch. Each later mark compares the state with
-- the snapshot, records a failing test "leak watch #<n>" with one line per change, and takes a new
-- snapshot, so file n answers only for its own changes. test_orders.py turns #<n> into the file's
-- name, drops what tests/world/leak_allow.json excuses, and prints the rest.
--
-- The watch reports each changed WATCHED value (CP.db and CP.charDB among them) with its old and
-- new value, each module local in LOCALS, each global or C_ namespace function replaced, new or
-- removed, and each C_Timer.After, NewTimer or NewTicker timer still queued, with the lines that
-- queued it.
--
-- The harness gives tests no `debug` library, so a module local is read by calling its module's own
-- functions in a way that changes nothing (see LOCALS).
--
-- Other runs load this file with the worlds but never call Mark, so it costs them nothing.

LeakWatch = {}

-- Globals the watch itself writes.
LeakWatch.IGNORE_GLOBALS = {
    LeakWatch = true,
}

-- Global names left out of the watch, with why.
LeakWatch.IGNORE_PATTERNS = {
    -- The addon's named frames. It makes each on first use, or again after a test drops its cached
    -- frame, and a test cannot take back a CreateFrame.
    "^ProfLost_",
}

local function ignored(k)
    if LeakWatch.IGNORE_GLOBALS[k] then return true end
    if type(k) ~= "string" then return false end
    for _, p in ipairs(LeakWatch.IGNORE_PATTERNS) do
        if k:find(p) then return true end
    end
    return false
end

-- Lines one file may report. test_orders.py folds what the allow list leaves past its own limit.
LeakWatch.MAX_LINES = 60

-- How many keys below a watched root a reported path goes (CP.db.windowPoint.x, not deeper).
LeakWatch.DEPTH = 3

-- Characters a shown value may take before it is cut.
LeakWatch.VALUE_WIDTH = 60

-- Frames of the stack kept for a timer's origin.
LeakWatch.FRAMES = 6

local function frameShown(frame)
    return frame ~= nil and frame.IsShown ~= nil and frame:IsShown() or false
end

-- Route menu rebuilds the addon queued (GatherList.RebuildSoon, a C_Timer.After(0) after a mode
-- pick) that no test has run yet. The next test that advances the clock runs them, and each
-- rebuilds an open menu inside a test that never asked for it. The watch wraps RebuildSoon once and
-- counts the timers it queues until they fire.
LeakWatch.rebuildsQueued = 0

-- The harness's timer wrapped so each timer counts until it fires.
local function counting(after)
    return function(delay, fn)
        LeakWatch.rebuildsQueued = LeakWatch.rebuildsQueued + 1
        return after(delay, function(...)
            LeakWatch.rebuildsQueued = LeakWatch.rebuildsQueued - 1
            return fn(...)
        end)
    end
end

local function watchRebuilds()
    local GL = ProfLost.GatherList
    if LeakWatch.rebuildWatch or not (GL and GL.RebuildSoon) then return end
    local soon = GL.RebuildSoon
    LeakWatch.rebuildWatch = function(...)
        local after = C_Timer.After
        C_Timer.After = counting(after)
        local ok, err = pcall(soon, ...)
        C_Timer.After = after
        if not ok then error(err, 0) end
    end
    GL.RebuildSoon = LeakWatch.rebuildWatch
end

-- Module locals ---------------------------------------------------------------------------

-- A purse no test sets, so Buying.Money() returns the local purse whenever one is set.
local RICH = 2 ^ 50

local function rich() return RICH end

-- Buying.lua's `expected`, the purse after the purchases sent (ORDERLEAK-06). Buying.Money()
-- returns min(GetMoney(), expected) and clears it only when GetMoney() is at or below it, so with
-- GetMoney() answering RICH it reads the local and changes nothing.
local function purse()
    local B = ProfLost.Buying
    if not (B and B.Money) then return nil end
    local G = _G
    local money = rawget(G, "GetMoney")
    G.GetMoney = rich
    local ok, value = pcall(B.Money)
    G.GetMoney = money
    if ok and value < RICH then return value end
    return nil
end

-- Module locals the watch reads: a label and a probe. A probe returns the local's value and must
-- change nothing, because it runs between test files.
LeakWatch.LOCALS = {
    { "CP.Buying local expected (purse)", purse },
}

-- Watched state ---------------------------------------------------------------------------

-- The watched state: a label and how to read it now.
LeakWatch.WATCHED = {
    { "CP.db", function() return ProfLost.db end },
    { "CP.charDB", function() return ProfLost.charDB end },
    { "CP.VendorWatch.current", function() return ProfLost.VendorWatch and ProfLost.VendorWatch.current end },
    { "CP.Panel.frame shown", function() return ProfLost.Panel and frameShown(ProfLost.Panel.frame) end },
    { "CP.Panel.folded", function() return ProfLost.Panel and ProfLost.Panel.folded end },
    { "CP.Window.opened", function() return ProfLost.Window and ProfLost.Window.opened end },
    -- Work the addon queued for later and no test ran. The next test that advances the clock runs
    -- it, so it redraws or recounts inside a test that never asked for it. New finds wait out
    -- GatherMate.SETTLE in a C_Timer.After, then reset their zones and redraw the panel.
    { "CP.GatherMate.pending", function() return ProfLost.GatherMate and ProfLost.GatherMate.Pending() end },
    { "CP.GatherList.rebuilds queued", function() watchRebuilds(); return LeakWatch.rebuildsQueued end },
    -- The route map's drawn zone and its solves in flight. A solve resumes on an OnUpdate, so the
    -- next test that advances the clock finishes it and draws.
    { "CP.RouteMap drawn zone", function()
        local RM = ProfLost.RouteMap
        return RM and RM.Spots and select(2, RM.Spots())
    end },
    { "CP.RouteMap.Solving()", function() return ProfLost.RouteMap and ProfLost.RouteMap.Solving() end },
    { "CP.RouteMap.Passing()", function() return ProfLost.RouteMap and ProfLost.RouteMap.Passing() end },
    -- Background jobs still running. Their next slice runs in the next test that advances the clock.
    { "CP.GatherGuide.Warming()", function() return ProfLost.GatherGuide and ProfLost.GatherGuide.Warming() end },
    { "CP.Farm.Warming()", function() return ProfLost.Farm and ProfLost.Farm.Warming() end },
    -- The game's trade skill as the events and the reload's query left it (Window.ProfessionOpen).
    { "CP.Professions.tradeSkillOpen", function() return ProfLost.Professions and ProfLost.Professions.tradeSkillOpen end },
    -- Daylight UI's plugin view and API, handed over by Plugin.Start (Host.UseDaylight).
    { "CP.Host.view", function() return ProfLost.Host and ProfLost.Host.view end },
    { "CP.GatherPanel.opened", function() return ProfLost.GatherPanel and ProfLost.GatherPanel.opened end },
    { "CP.GatherPanel.brought", function() return ProfLost.GatherPanel and ProfLost.GatherPanel.brought end },
    { "CP.GatherPanel.shell shown", function() return ProfLost.GatherPanel and frameShown(ProfLost.GatherPanel.shell) end },
    { "CP.GatherPanel.sheet shown", function() return ProfLost.GatherPanel and frameShown(ProfLost.GatherPanel.sheet) end },
}

for _, l in ipairs(LeakWatch.LOCALS) do LeakWatch.WATCHED[#LeakWatch.WATCHED + 1] = l end

-- Queued timers ---------------------------------------------------------------------------

-- Every timer queued since the first mark and not yet fired or cancelled, by its entry.
LeakWatch.pending = {}

-- Counts checks. A timer belongs to the check after the one it was queued in.
LeakWatch.epoch = 0

local seq = 0
local stack = debugstack
local timerWatch = {}
local inside = false

-- Wraps one C_Timer function so each timer it queues is kept in `pending` until it fires its last
-- time or is cancelled. `rounds` gives how often a timer fires from the call's arguments.
local function watchTimer(api, rounds)
    local raw = C_Timer[api]
    local function queue(delay, fn, n)
        if inside or type(fn) ~= "function" then return raw(delay, fn, n) end
        seq = seq + 1
        local entry = { api = api, delay = delay, left = rounds(n), seq = seq, epoch = LeakWatch.epoch, stack = stack() }
        local pending = LeakWatch.pending
        pending[entry] = true
        local function run(...)
            entry.left = entry.left - 1
            if entry.left <= 0 then pending[entry] = nil end
            return fn(...)
        end
        inside = true
        local ok, handle = pcall(raw, delay, run, n)
        inside = false
        if not ok then
            pending[entry] = nil
            error(handle, 0)
        end
        if type(handle) == "table" and type(handle.Cancel) == "function" then
            local cancel = handle.Cancel
            handle.Cancel = function(self, ...)
                pending[entry] = nil
                return cancel(self, ...)
            end
        end
        return handle
    end
    timerWatch[api] = queue
    C_Timer[api] = queue
end

local function once() return 1 end
local function ticks(n) return n or math.huge end

local TIMER_APIS = { After = once, NewTimer = once, NewTicker = ticks }

-- Puts the timer watch on top of C_Timer. A test file that wrapped a C_Timer function for good gets
-- a fresh watch over its wrapper; the older watch below then passes its timers straight through.
local function watchTimers()
    for api, rounds in pairs(TIMER_APIS) do
        if C_Timer[api] ~= timerWatch[api] then watchTimer(api, rounds) end
    end
end

-- A source path from the stack, from the repository root down: "ProfessionallyLost/UI/Buying.lua".
-- The harness names addon files from the addon folder ("UI/Buying.lua") and test files as given.
local function sourcePath(src)
    if src:find("^tests/") then return src end
    for _, root in ipairs({ "/tests/", "/temp/" }) do
        local at = src:find(root, 1, true)
        if at then return src:sub(at + 1) end
    end
    if src:find("^%.%.%.") or src:find("^%a:") or src:find("^/") then return src end
    return "ProfessionallyLost/" .. src
end

local function inAddonOrWorld(path)
    return path:find("^ProfessionallyLost/") or path:find("^tests/world/") or path:find("^tests/rules/")
end

-- The lines that queued a timer, innermost first. They run up to the first test-file line after
-- the addon's own lines, so a test file's C_Timer wrapper does not stand in for the addon line.
local function origin(text)
    local out, addon = {}, false
    for src, line in text:gmatch("\n%s*([^\n]-):(%d+): in ") do
        if src:sub(1, 1) ~= "[" and not src:find("tests/world/leakwatch.lua", 1, true)
            and not src:find("tests/world/init.lua", 1, true) then
            local path = sourcePath(src)
            out[#out + 1] = path .. ":" .. line
            if inAddonOrWorld(path) then
                addon = true
            elseif addon then
                break
            end
            if #out >= LeakWatch.FRAMES then break end
        end
    end
    return table.concat(out, " < ")
end

-- Every timer queued since the last check and still pending, as report lines.
local function timerLines(out)
    local due = {}
    for entry in pairs(LeakWatch.pending) do
        if entry.epoch == LeakWatch.epoch then due[#due + 1] = entry end
    end
    table.sort(due, function(a, b) return a.seq < b.seq end)
    for _, e in ipairs(due) do
        out[#out + 1] = table.concat({ "timer", e.api, tostring(e.delay), origin(e.stack) }, "\t")
    end
end

-- State -----------------------------------------------------------------------------------

-- A deep copy of plain tables. Frames, tables with a metatable and functions keep their identity.
local function copy(v, seen)
    if type(v) ~= "table" or getmetatable(v) ~= nil then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, x in pairs(v) do out[k] = copy(x, seen) end
    return out
end

local function keyText(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then return "." .. k end
    return "[" .. tostring(k) .. "]"
end

-- A value as one short line of text.
local function show(v, depth)
    local t = type(v)
    local text
    if t == "string" then
        text = ("%q"):format(v)
    elseif t == "table" then
        if getmetatable(v) ~= nil then
            text = v.GetObjectType and ("<" .. tostring(v:GetObjectType()) .. ">") or "<object>"
        elseif (depth or 0) > 0 then
            text = "{...}"
        else
            local parts = {}
            for _, k in ipairs(World.keys(v)) do
                parts[#parts + 1] = (type(k) == "string" and k or ("[" .. tostring(k) .. "]")) .. "=" .. show(v[k], 1)
                if #parts > 8 then
                    parts[#parts + 1] = "..."
                    break
                end
            end
            text = "{" .. table.concat(parts, ", ") .. "}"
        end
    elseif t == "function" then
        text = "<function>"
    else
        text = tostring(v)
    end
    text = text:gsub("[\t\r\n]", " ")
    if #text > LeakWatch.VALUE_WIDTH then text = text:sub(1, LeakWatch.VALUE_WIDTH - 3) .. "..." end
    return text
end

-- True when `a` and `b` hold the same plain values. nil and an empty table count as the same.
local function same(a, b, seen)
    if a == b then return true end
    -- The addon makes some saved tables on first use (CP.db.finds = CP.db.finds or {}); an empty
    -- one holds what nil does.
    if a == nil and type(b) == "table" and next(b) == nil then return true end
    if b == nil and type(a) == "table" and next(a) == nil then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do
        if not same(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function plain(v) return type(v) == "table" and getmetatable(v) == nil end

local function at(t, k)
    if plain(t) then return t[k] end
    return nil
end

-- Appends a line for every place `a` (before) and `b` (now) differ, down to DEPTH keys below the root.
-- A place back at `p`, its value at the first mark, is left out: the file put back what an earlier
-- file left, and that earlier file was named.
local function diff(a, b, p, path, out, depth)
    if same(a, b) then return end
    if depth == 0 or not plain(a) or not plain(b) then
        if not same(p, b) then out[#out + 1] = table.concat({ "state", path, show(a), show(b) }, "\t") end
        return
    end
    for _, k in ipairs(World.keys(a)) do diff(a[k], b[k], at(p, k), path .. keyText(k), out, depth - 1) end
    for _, k in ipairs(World.keys(b)) do
        if a[k] == nil then diff(nil, b[k], at(p, k), path .. keyText(k), out, depth - 1) end
    end
end

-- The game's C_ namespaces' functions by "C_Name.Function", so a test that replaces one for good shows.
local function apiFunctions(out)
    for name, ns in pairs(_G) do
        if type(name) == "string" and name:find("^C_") and type(ns) == "table" then
            for k, v in pairs(ns) do
                if type(v) == "function" then out[name .. "." .. tostring(k)] = v end
            end
        end
    end
end

local function globalsNow()
    local now = {}
    for k, v in pairs(_G) do
        if not ignored(k) then now[k] = v end
    end
    apiFunctions(now)
    return now
end

local function snapshot()
    local state = {}
    for i, w in ipairs(LeakWatch.WATCHED) do state[i] = copy(w[2]()) end
    return { state = state, globals = globalsNow() }
end

-- Every changed key since `before`, in a fixed order, one tab-separated line each.
function LeakWatch.Changes(before)
    local out = {}
    local first = LeakWatch.first
    for i, w in ipairs(LeakWatch.WATCHED) do
        diff(before.state[i], w[2](), first.state[i], w[1], out, LeakWatch.DEPTH)
    end
    local now = globalsNow()
    for _, k in ipairs(World.keys(before.globals)) do
        if now[k] ~= before.globals[k] and now[k] ~= first.globals[k] then
            out[#out + 1] = "global\t" .. tostring(k) .. (now[k] == nil and "\tremoved" or "\treplaced")
        end
    end
    for _, k in ipairs(World.keys(now)) do
        if before.globals[k] == nil and first.globals[k] == nil then out[#out + 1] = "global\t" .. tostring(k) .. "\tnew" end
    end
    timerLines(out)
    return out
end

LeakWatch.marks = 0

-- Every change since the last check as one message, a line each, cut at MAX_LINES; nil when none.
-- Takes a new snapshot either way.
local function check()
    local changed = LeakWatch.before and LeakWatch.Changes(LeakWatch.before) or {}
    watchTimers()
    LeakWatch.epoch = LeakWatch.epoch + 1
    LeakWatch.before = snapshot()
    LeakWatch.first = LeakWatch.first or LeakWatch.before
    if #changed == 0 then return nil end
    local shown = {}
    for i = 1, math.min(#changed, LeakWatch.MAX_LINES) do shown[i] = changed[i] end
    if #changed > LeakWatch.MAX_LINES then
        shown[#shown + 1] = "more\t" .. (#changed - LeakWatch.MAX_LINES)
    end
    return table.concat(shown, "\n")
end

local test = T.test

-- Called between test files by leakmark.lua.
function LeakWatch.Mark()
    local n = LeakWatch.marks
    LeakWatch.marks = n + 1
    local message = check()
    if message and n > 0 then test("leak watch #" .. n, function() error(message, 0) end) end
end

-- With perTest set (test_orders.py --per-test), each test is checked as it ends, so a leak
-- names its test too: "leak watch #<file> test: <name>".
LeakWatch.perTest = false

-- After the first mark each test's name carries its file's number ("<name>\t#<n>"), so
-- test_orders.py can tell which file a failing test is in. It strips the tag before printing.
function T.test(name, fn, opts)
    test(LeakWatch.marks > 0 and type(name) == "string" and name .. "\t#" .. LeakWatch.marks or name, fn, opts)
    if LeakWatch.perTest and LeakWatch.before then
        local message = check()
        if message then
            test("leak watch #" .. LeakWatch.marks .. " test: " .. name, function() error(message, 0) end)
        end
    end
end
