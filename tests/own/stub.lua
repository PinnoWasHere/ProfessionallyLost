-- The own fake game: a sandbox global table with the client's Lua helpers, game functions as
-- recording stubs, frames with widget methods, events, timers and OnUpdate on a fake clock.
--
-- Shapes it keeps (the worlds and tests read them):
--   * a widget is a table whose [0] holds its state (type, name, parent, shown, scripts,
--     attributes, points, width, height, children);
--   * a game function or widget method not modelled here records its call (G.calls[path]),
--     checks its argument classes and answers with the default of its declared return classes;
--   * a widget method the catalog does not list is nil, so calling it raises.
--
-- tests/own/catalog.lua (generated, tests/own/tools/gen_catalog.lua) names what the game has.

local here = (arg and arg[0] or ""):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."

local Catalog = dofile(here .. "/catalog.lua")

local G = {
    errors = {}, prints = {}, calls = {}, overrides = {}, undefined = {}, undefined_order = {},
    declared = {}, clock = 0, timers = {}, timer_seq = 0, frames = {}, onupdate = {},
    event_frames = {}, tests = {}, loaded = {},
}

local ENV
local unpack = unpack or table.unpack

---------------------------------------------------------------------------
-- Errors
---------------------------------------------------------------------------

local function record_error(context, message, trace)
    G.errors[#G.errors + 1] = { context = context, message = tostring(message), traceback = trace or "" }
end
G.record_error = record_error

local function traceback(err)
    return { msg = err, tb = debug.traceback(tostring(err), 2) }
end
G.traceback = traceback

-- Runs fn protected. An error is recorded, handed to the installed error handler, and false returns.
local function guarded(context, fn, ...)
    local args, n = { ... }, select("#", ...)
    local ok, res = xpcall(function() return fn(unpack(args, 1, n)) end, traceback)
    if not ok then
        record_error(context, res.msg, res.tb)
        if G.errorhandler then
            G.dispatching = true
            pcall(G.errorhandler, res.msg)
            G.dispatching = false
        end
        return false
    end
    return true
end
G.guarded = guarded

---------------------------------------------------------------------------
-- Argument classes, recording stubs
---------------------------------------------------------------------------

local CHECK = {
    number = function(v) return type(v) == "number" or (type(v) == "string" and tonumber(v) ~= nil) end,
    string = function(v) local t = type(v); return t == "string" or t == "number" end,
    boolean = function() return true end,
    table = function(v) return type(v) == "table" end,
    ["function"] = function(v) return type(v) == "function" end,
}
local DEFAULT = { number = 0, string = "", boolean = false }

local function split(s)
    local out = {}
    if s and s ~= "" then
        for part in (s .. ","):gmatch("([^,]*),") do out[#out + 1] = part end
    end
    return out
end

local parsed = {}
local function classes(s)
    local c = parsed[s]
    if not c then c = split(s); parsed[s] = c end
    return c
end

local function record_call(name, n, ...)
    local rec = G.calls[name]
    if not rec then rec = {}; G.calls[name] = rec end
    rec[#rec + 1] = { n = n, ... }
end

local new_object

local function default_returns(r, owner, key)
    if not r or #r == 0 then return end
    local out = {}
    for i, class in ipairs(r) do
        if class == "table" then
            out[i] = {}
        elseif class == "opaque" then
            out[i] = setmetatable({}, { __index = function(_, k)
                return function(...) record_call("<opaque>:" .. tostring(k), select("#", ...), ...) end
            end })
        elseif class:sub(1, 7) == "widget:" then
            -- A getter returns the same child each time.
            local kids = owner and owner[0] and owner[0].children
            local slot = (key or "?") .. "#" .. i
            if kids and kids[slot] then
                out[i] = kids[slot]
            else
                out[i] = new_object(class:sub(8), nil, owner)
                if kids then kids[slot] = out[i] end
            end
        else
            out[i] = DEFAULT[class]
        end
    end
    return unpack(out, 1, #r)
end

local function check_args(name, params, offset, ...)
    if not params then return end
    for i, p in ipairs(params) do
        local v = select(i + offset, ...)
        local nilable = p:sub(-1) == "?"
        local class = nilable and p:sub(1, -2) or p
        if class ~= "" then
            if v == nil then
                if not nilable and class ~= "boolean" then
                    error(("bad argument #%d to '%s' (%s expected, got no value)"):format(i, name, class), 3)
                end
            elseif CHECK[class] and not CHECK[class](v) then
                error(("bad argument #%d to '%s' (%s expected, got %s)"):format(i, name, class, type(v)), 3)
            end
        end
    end
end

local function make_stub(name, rets, params)
    local r = classes(rets)
    local p = params and classes(params)
    return function(...)
        check_args(name, p, 0, ...)
        record_call(name, select("#", ...), ...)
        local o = G.overrides[name]
        if o ~= nil then
            if type(o) == "function" then return o(...) end
            return o
        end
        return default_returns(r)
    end
end

local function set_path(root, path, value)
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    local t = root
    for i = 1, #parts - 1 do
        local nxt = rawget(t, parts[i])
        if type(nxt) ~= "table" then nxt = {}; rawset(t, parts[i], nxt) end
        t = nxt
    end
    rawset(t, parts[#parts], value)
end

local function get_path(root, path)
    local t = root
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = rawget(t, part)
    end
    return t
end
G.set_path, G.get_path = set_path, get_path

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local SCRIPTS, EVENTS = {}, {}
for _, n in ipairs(Catalog.scripts) do SCRIPTS[n] = true end
for _, n in ipairs(Catalog.events) do EVENTS[n] = true end

local WIDGET_METHODS, METATABLES = {}, {}
local LOWER = {}
for name in pairs(Catalog.types) do LOWER[name:lower()] = name end
local INTRINSICS = { eventframe = "Frame" }

local function canonical_type(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower()
    return LOWER[key] or (INTRINSICS[key] and LOWER[INTRINSICS[key]:lower()])
end

local core = {}

function new_object(objtype, name, parent)
    local obj = { [0] = { children = {} } }
    local st = obj[0]
    st.type, st.name, st.parent, st.shown = objtype, name, parent, true
    st.scripts, st.attributes, st.points, st.width, st.height = {}, {}, {}, 0, 0
    local mt = METATABLES[objtype] or METATABLES.Frame
    setmetatable(obj, mt)
    G.frames[#G.frames + 1] = obj
    st.idx = #G.frames
    if type(name) == "string" and name ~= "" then
        if parent and name:find("$parent", 1, true) then
            name = name:gsub("%$parent", (parent[0] and parent[0].name) or "")
            st.name = name
        end
        rawset(ENV, name, obj)
    end
    return obj
end
G.new_object = new_object

local function fire_script(obj, handler, ...)
    local fn = obj[0].scripts[handler]
    if fn then guarded(handler .. " of " .. (obj[0].name or obj[0].type), fn, obj, ...) end
end

function core:GetName() return self[0].name end
function core:GetDebugName() return self[0].name or ("<anonymous " .. self[0].type .. ">") end
function core:GetObjectType() return self[0].type end
function core:IsObjectType(t)
    if self[0].type == t then return true end
    for _, a in ipairs(Catalog.types[self[0].type] or {}) do
        if a == t then return true end
    end
    return false
end
function core:GetParent() return self[0].parent end
function core:SetParent(p) self[0].parent = p end

function core:RegisterEvent(event)
    if type(event) ~= "string" then
        error("Usage: " .. self:GetDebugName() .. ":RegisterEvent(event)", 2)
    end
    if not EVENTS[event] then
        error(("%s:RegisterEvent(): Attempt to register unknown event \"%s\""):format(self:GetDebugName(), event), 2)
    end
    local set = G.event_frames[event]
    if not set then set = {}; G.event_frames[event] = set end
    local had = set[self]
    set[self] = true
    return not had
end
function core:RegisterUnitEvent(event) return core.RegisterEvent(self, event) end
function core:UnregisterEvent(event)
    local set = G.event_frames[event]
    local had = set and set[self]
    if set then set[self] = nil end
    return had and true or false
end
function core:UnregisterAllEvents()
    for _, set in pairs(G.event_frames) do set[self] = nil end
end
function core:IsEventRegistered(event)
    local set = G.event_frames[event]
    return set and set[self] and true or false
end

-- Frames that have held an OnUpdate script, in creation order.
local function track_onupdate(obj)
    local st = obj[0]
    if st.onupdate_tracked then return end
    st.onupdate_tracked = true
    local list = G.onupdate
    local pos = #list + 1
    while pos > 1 and list[pos - 1][0].idx > st.idx do pos = pos - 1 end
    table.insert(list, pos, obj)
end

local function check_script(self, handler)
    if type(handler) ~= "string" or not SCRIPTS[handler] then
        error(("%s doesn't have a \"%s\" script"):format(self:GetDebugName(), tostring(handler)), 3)
    end
end
function core:SetScript(handler, fn)
    check_script(self, handler)
    if fn ~= nil and type(fn) ~= "function" then
        error("Usage: " .. self:GetDebugName() .. ":SetScript(\"type\", function)", 2)
    end
    self[0].scripts[handler] = fn
    if handler == "OnUpdate" and fn then track_onupdate(self) end
end
function core:GetScript(handler) return self[0].scripts[handler] end
function core:HasScript(handler) return SCRIPTS[handler] ~= nil end
function core:HookScript(handler, fn)
    check_script(self, handler)
    local prev = self[0].scripts[handler]
    if prev then
        self[0].scripts[handler] = function(...) prev(...); return fn(...) end
    else
        self[0].scripts[handler] = fn
    end
    if handler == "OnUpdate" and self[0].scripts[handler] then track_onupdate(self) end
end

function core:Show()
    if not self[0].shown then self[0].shown = true; fire_script(self, "OnShow") end
end
function core:Hide()
    if self[0].shown then self[0].shown = false; fire_script(self, "OnHide") end
end
function core:SetShown(v) if v then self:Show() else self:Hide() end end
function core:IsShown() return self[0].shown end
function core:IsVisible()
    local o = self
    while o do
        if not o[0].shown then return false end
        o = o[0].parent
    end
    return true
end

function core:SetAttribute(k, v)
    self[0].attributes[k] = v
    fire_script(self, "OnAttributeChanged", k, v)
end
function core:GetAttribute(k) return self[0].attributes[k] end
function core:SetText(t) self[0].text = t end
function core:GetText() return self[0].text end
function core:SetSize(w, h) self[0].width, self[0].height = w or 0, h or 0 end
function core:SetWidth(w) self[0].width = w or 0 end
function core:SetHeight(h) self[0].height = h or 0 end
function core:GetWidth() return self[0].width end
function core:GetHeight() return self[0].height end
function core:GetSize() return self[0].width, self[0].height end
function core:SetPoint(...) local p = self[0].points; p[#p + 1] = { ... } end
function core:ClearAllPoints() self[0].points = {} end
function core:GetNumPoints() return #self[0].points end
function core:GetPoint(i) local p = self[0].points[i or 1]; if p then return unpack(p) end end
function core:CreateTexture(name) return new_object("Texture", name, self) end
function core:CreateFontString(name) return new_object("FontString", name, self) end
function core:CreateLine(name) return new_object("Line", name, self) end
function core:CreateMaskTexture(name) return new_object("MaskTexture", name, self) end
function core:CreateAnimationGroup(name) return new_object("AnimationGroup", name, self) end
function core:AddMessage(msg) G.prints[#G.prints + 1] = tostring(msg) end

local function build_widget_methods()
    for objtype in pairs(Catalog.types) do WIDGET_METHODS[objtype] = {} end
    for objtype in pairs(Catalog.methods) do WIDGET_METHODS[objtype] = WIDGET_METHODS[objtype] or {} end
    for objtype, methods in pairs(WIDGET_METHODS) do
        local chain = { objtype }
        for _, a in ipairs(Catalog.types[objtype] or {}) do chain[#chain + 1] = a end
        for i = #chain, 1, -1 do
            for mname, rets in pairs(Catalog.methods[chain[i]] or {}) do
                local full = chain[i] .. ":" .. mname
                local r = classes(rets)
                methods[mname] = function(self, ...)
                    record_call(full, select("#", ...), ...)
                    local o = G.overrides[full]
                    if o ~= nil then
                        if type(o) == "function" then return o(self, ...) end
                        return o
                    end
                    return default_returns(r, self, full)
                end
            end
        end
        -- Modelled behaviour replaces the recording stub, only for methods the type has.
        for mname, fn in pairs(core) do
            if methods[mname] then methods[mname] = fn end
        end
        methods.GetDebugName = core.GetDebugName
        METATABLES[objtype] = { __index = methods }
    end
end

local function apply_templates(obj, templates)
    if type(templates) ~= "string" or templates == "" then return end
    for t in templates:gmatch("[^,%s]+") do
        local info = Catalog.templates[t]
        if not info then
            error(("CreateFrame(): Couldn't find inherited node \"%s\""):format(t), 3)
        end
        for _, mixin_name in ipairs(info) do
            local mixin = rawget(ENV, mixin_name)
            if type(mixin) == "table" then
                for k, v in pairs(mixin) do rawset(obj, k, v) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Events, timers, clock
---------------------------------------------------------------------------

-- G.strict_events (OWN_STRICT_EVENTS / PROFLOST_STRICT_EVENTS): an unknown event, or more arguments than the
-- documented payload, records an error naming the event and delivers nothing.
function G.fire(event, ...)
    if G.strict_events then
        local n, max = select("#", ...), Catalog.event_args and Catalog.event_args[event]
        local msg
        if not EVENTS[event] then
            msg = ("strict-events: %s is not an event of this flavor"):format(tostring(event))
        elseif max and n > max then
            msg = ("strict-events: %s fired with %d arguments, documented %d"):format(event, n, max)
        end
        if msg then
            record_error("strict event " .. tostring(event), msg, debug.traceback("", 2))
            return false
        end
    end
    local set = G.event_frames[event]
    local before = #G.errors
    if set then
        local list = {}
        for f in pairs(set) do list[#list + 1] = f end
        table.sort(list, function(a, b) return a[0].idx < b[0].idx end)
        for _, f in ipairs(list) do
            local fn = f[0].scripts.OnEvent
            if fn then guarded("OnEvent " .. event .. " on " .. f:GetDebugName(), fn, f, event, ...) end
        end
    end
    return #G.errors == before
end

local function add_timer(seconds, callback, iterations)
    G.timer_seq = G.timer_seq + 1
    local t = { due = G.clock + (seconds or 0), period = seconds or 0, cb = callback,
                left = iterations, seq = G.timer_seq, cancelled = false }
    G.timers[#G.timers + 1] = t
    local handle = {}
    function handle:Cancel() t.cancelled = true end
    function handle:IsCancelled() return t.cancelled end
    t.handle = handle
    return handle
end

-- Runs every timer due by the clock, earliest due first, then earliest made.
local function run_due_timers()
    while true do
        local best, at
        for i, t in ipairs(G.timers) do
            if t.cancelled then
                table.remove(G.timers, i)
                return run_due_timers()
            end
            if t.due <= G.clock + 1e-9 and (not best or t.due < best.due or (t.due == best.due and t.seq < best.seq)) then
                best, at = t, i
            end
        end
        if not best then return end
        table.remove(G.timers, at)
        guarded("C_Timer callback", best.cb, best.handle)
        best.left = best.left - 1
        if best.left > 0 and not best.cancelled then
            best.due = best.due + best.period
            G.timers[#G.timers + 1] = best
        end
    end
end

function G.advance(seconds, step)
    seconds = seconds or 0
    step = step or math.min(seconds, 0.1)
    if step <= 0 then step = seconds end
    local target = G.clock + seconds
    while G.clock < target - 1e-9 do
        local dt = math.min(step, target - G.clock)
        G.clock = G.clock + dt
        run_due_timers()

        -- Creation order. A frame older than the cursor waits for the next step; a newer one
        -- made by a handler fires in this step.
        local list, i, last = G.onupdate, 1, 0
        while list[i] do
            local f = list[i]
            i = i + 1
            if f[0].idx > last then
                last = f[0].idx
                if f[0].scripts.OnUpdate and f:IsVisible() then fire_script(f, "OnUpdate", dt) end
            end
        end
    end
    run_due_timers()
end

---------------------------------------------------------------------------
-- Lua helpers the client defines
---------------------------------------------------------------------------

local function strsplit(sep, str, limit)
    if str == nil then return end
    local out, start, count = {}, 1, 0
    while true do
        if limit and count == limit - 1 then out[#out + 1] = str:sub(start); break end
        local a
        for i = start, #str do
            if sep:find(str:sub(i, i), 1, true) then a = i; break end
        end
        if not a then out[#out + 1] = str:sub(start); break end
        out[#out + 1] = str:sub(start, a - 1)
        start = a + 1
        count = count + 1
    end
    return unpack(out)
end

local function strtrim(s, chars)
    chars = chars and ("[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]") or "%s"
    return (s:gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""))
end

-- 32-bit integer ops for a host without the `bit` library.
local function make_bit()
    local b = {}
    local function u(n) return math.floor(n) % 4294967296 end
    local function s(n) if n >= 2147483648 then return n - 4294967296 end return n end
    local function op(a, c, f)
        a, c = u(a), u(c)
        local r, p = 0, 1
        for _ = 1, 32 do
            if f(a % 2, c % 2) then r = r + p end
            a, c, p = math.floor(a / 2), math.floor(c / 2), p * 2
        end
        return s(r)
    end
    local function chain(f)
        local function go(a, c, ...)
            local r = op(a, c, f)
            if select("#", ...) > 0 then return go(r, ...) end
            return r
        end
        return go
    end
    b.band = chain(function(x, y) return x == 1 and y == 1 end)
    b.bor = chain(function(x, y) return x == 1 or y == 1 end)
    b.bxor = chain(function(x, y) return x ~= y end)
    b.bnot = function(a) return s(4294967295 - u(a)) end
    b.lshift = function(a, n) return s((u(a) * 2 ^ n) % 4294967296) end
    b.rshift = function(a, n) return s(math.floor(u(a) / 2 ^ n)) end
    b.arshift = function(a, n) return math.floor(s(u(a)) / 2 ^ n) end
    b.mod = function(a, c) return a % c end
    return b
end
G.make_bit = make_bit

local function deep_copy(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local c = {}
    seen[t] = c
    for k, v in pairs(t) do c[deep_copy(k, seen)] = deep_copy(v, seen) end
    return c
end

local HOST_G = getfenv(0)
local host_getfenv = getfenv

-- The client's global table is the addon environment; level 0 and any level that resolves to the
-- host's globals give it back.
local function client_getfenv(env)
    return function(f)
        if f == 0 then return env end
        if f == nil then f = 1 end
        if type(f) == "number" then f = f + 1 end
        local e = host_getfenv(f)
        if e == HOST_G then return env end
        return e
    end
end

local function lua_helpers(env)
    local s, t, m = string, table, math
    local bit = (not os.getenv("OWN_FORCE_BIT")) and rawget(HOST_G, "bit") or make_bit()
    local helpers = {
        string = s, table = t, math = m, coroutine = coroutine, bit = bit,
        select = select, type = type, pairs = pairs, ipairs = ipairs, next = next,
        tostring = tostring, tonumber = tonumber, unpack = unpack, pcall = pcall,
        -- The client's xpcall forwards extra arguments to f; stock 5.1 drops them.
        xpcall = function(f, handler, ...)
            local n, args = select("#", ...), { ... }
            return xpcall(function() return f(unpack(args, 1, n)) end, handler)
        end,
        error = error, assert = assert, setmetatable = setmetatable,
        getmetatable = getmetatable, rawget = rawget, rawset = rawset, rawequal = rawequal,
        setfenv = setfenv, getfenv = client_getfenv(env), loadstring = loadstring,
        collectgarbage = function() return 0 end, gcinfo = function() return 0 end,
        date = os.date, time = os.time, difftime = os.difftime,
        strlen = s.len, strsub = s.sub, strfind = s.find, strmatch = s.match, gsub = s.gsub,
        gmatch = s.gmatch, strupper = s.upper, strlower = s.lower, strrep = s.rep,
        strrev = s.reverse, strbyte = s.byte, strchar = s.char, format = s.format,
        strsplit = strsplit, strtrim = strtrim,
        strjoin = function(sep, ...) return t.concat({ ... }, sep) end,
        strconcat = function(...) return t.concat({ ... }) end,
        tinsert = t.insert, tremove = t.remove, sort = t.sort, getn = t.getn,
        abs = m.abs, ceil = m.ceil, floor = m.floor, max = m.max, min = m.min,
        sqrt = m.sqrt, random = m.random, mod = m.fmod, exp = m.exp, log = m.log,
        log10 = m.log10, fastrandom = m.random,
        wipe = function(tbl) for k in pairs(tbl) do tbl[k] = nil end return tbl end,
        tContains = function(tbl, v) for _, x in pairs(tbl) do if x == v then return true end end return false end,
        tInvert = function(tbl) local r = {} for k, v in pairs(tbl) do r[v] = k end return r end,
        CopyTable = function(tbl) return deep_copy(tbl) end,
        Mixin = function(obj, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do obj[k] = v end end return obj end,
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
            local line = t.concat(parts, " ")
            G.prints[#G.prints + 1] = line
            if G.stream then G.stream(line) end
        end,
        hooksecurefunc = function(a, b, c)
            local tbl, name, fn = a, b, c
            if type(a) == "string" then tbl, name, fn = env, a, b end
            local orig = tbl[name]
            if type(orig) ~= "function" then error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 2) end
            tbl[name] = function(...)
                local r = { orig(...) }
                fn(...)
                return unpack(r)
            end
        end,
        securecall = function(f, ...) if type(f) == "string" then f = env[f] end return f(...) end,
        securecallfunction = function(f, ...) return f(...) end,
        issecurevariable = function() return true end,
        geterrorhandler = function()
            return G.errorhandler or function(err)
                if not G.dispatching then record_error("errorhandler", err, debug.traceback(tostring(err), 2)) end
            end
        end,
        seterrorhandler = function(fn)
            if type(fn) ~= "function" then error("Usage: seterrorhandler(errfunc)", 2) end
            G.errorhandler = fn
        end,
        debugstack = function() return debug.traceback("", 2) end,
        debugprofilestop = function() return G.clock * 1000 end,
        GetTime = function() return G.clock end,
    }
    s.split = strsplit
    s.trim = strtrim
    helpers.CreateFromMixins = function(...) return helpers.Mixin({}, ...) end
    helpers.CreateAndInitFromMixin = function(mixin, ...)
        local o = helpers.Mixin({}, mixin)
        if o.Init then o:Init(...) end
        return o
    end
    return helpers
end

---------------------------------------------------------------------------
-- Environment
---------------------------------------------------------------------------

function G.setup()
    ENV = {}
    G.env = ENV
    rawset(ENV, "_G", ENV)

    for name, spec in pairs(Catalog.functions) do
        set_path(ENV, name, make_stub(name, spec[1], spec[2] or nil))
    end
    for name, values in pairs(Catalog.enums) do set_path(ENV, name, values) end
    for name, methods in pairs(Catalog.mixins) do
        local mixin = {}
        for _, mname in ipairs(methods) do mixin[mname] = make_stub(name .. ":" .. mname, "", nil) end
        set_path(ENV, name, mixin)
    end

    -- UI source globals: functions and namespaces record calls, tables are tables, constants keep values.
    local fx = Catalog.framexml
    for _, name in ipairs(fx.tables) do
        if type(rawget(ENV, name)) ~= "table" then rawset(ENV, name, {}) end
    end
    for name, returns in pairs(fx.functions) do
        if rawget(ENV, name) == nil then rawset(ENV, name, make_stub(name, returns and "opaque" or "", nil)) end
    end
    for owner, members in pairs(fx.namespaces) do
        for m, returns in pairs(members) do
            local path = owner .. "." .. m
            if get_path(ENV, path) == nil then set_path(ENV, path, make_stub(path, returns and "opaque" or "", nil)) end
        end
    end
    for name, value in pairs(fx.constants) do
        if rawget(ENV, name) == nil then rawset(ENV, name, value) end
    end

    -- The test persona. T.stub replaces any of these.
    local persona = {
        UnitName = function(unit) if unit == "player" then return "Testchar", nil end end,
        GetRealmName = "Testrealm", GetNormalizedRealmName = "Testrealm",
        UnitGUID = function(unit) if unit == "player" then return "Player-4440-0A1B2C3D" end end,
        UnitClass = function(unit) if unit == "player" then return "Warrior", "WARRIOR", 1 end end,
        UnitLevel = function(unit) if unit == "player" then return 80 end return 0 end,
        UnitRace = function(unit) if unit == "player" then return "Human", "Human", 1 end end,
        UnitFactionGroup = function(unit) if unit == "player" then return "Alliance", "Alliance" end end,
        GetLocale = "enUS",
        ["C_UIFileAsset.IsKnownFile"] = true,
        GetCVar = "0",
    }
    for name, v in pairs(persona) do
        if Catalog.functions[name] then G.overrides[name] = v end
    end

    for k, v in pairs(lua_helpers(ENV)) do rawset(ENV, k, v) end

    build_widget_methods()
    local function timer_check(name, seconds, cb)
        check_args(name, { "number", "function" }, 0, seconds, cb)
    end
    set_path(ENV, "C_Timer.After", function(seconds, cb)
        timer_check("C_Timer.After", seconds, cb)
        add_timer(seconds, cb, 1)
    end)
    set_path(ENV, "C_Timer.NewTimer", function(seconds, cb)
        timer_check("C_Timer.NewTimer", seconds, cb)
        return add_timer(seconds, cb, 1)
    end)
    set_path(ENV, "C_Timer.NewTicker", function(seconds, cb, iterations)
        timer_check("C_Timer.NewTicker", seconds, cb)
        return add_timer(seconds, cb, iterations or math.huge)
    end)
    rawset(ENV, "CreateFrame", function(frameType, name, parent, template)
        local objtype = canonical_type(frameType)
        if not objtype then
            error(("CreateFrame: Unknown frame type '%s'"):format(tostring(frameType)), 2)
        end
        local f = new_object(objtype, name, parent)
        apply_templates(f, template)
        if f.OnLoad then guarded("OnLoad of " .. f:GetDebugName(), f.OnLoad, f) end
        return f
    end)
    rawset(ENV, "GetBuildInfo", function()
        return Catalog.build.version, Catalog.build.build, "Nov 3 2026", tonumber(Catalog.build.interface)
    end)
    local font_type = WIDGET_METHODS.Font and "Font" or "Frame"
    for _, name in ipairs(Catalog.fonts) do
        if rawget(ENV, name) == nil then new_object(font_type, name, nil) end
    end
    rawset(ENV, "UIParent", new_object("Frame", "UIParent", nil))
    rawset(ENV, "WorldFrame", new_object("Frame", "WorldFrame", nil))
    rawset(ENV, "GameTooltip", new_object("GameTooltip", "GameTooltip", ENV.UIParent))
    rawset(ENV, "Minimap", new_object("Minimap", "Minimap", ENV.UIParent))

    -- The world map as map-pin libraries see it at load: a canvas and data providers.
    local worldMap = new_object("Frame", "WorldMapFrame", ENV.UIParent)
    local canvas = new_object("Frame", nil, worldMap)
    -- Blizzard_WorldMap's ScrollContainer: the map's scroll frame, which buttons on the map anchor to.
    rawset(worldMap, "ScrollContainer", new_object("Frame", nil, worldMap))
    rawset(worldMap, "pinPools", {})
    rawset(worldMap, "dataProviders", {})
    rawset(worldMap, "GetCanvas", function() return canvas end)
    rawset(worldMap, "GetMapID", function() return nil end)
    rawset(worldMap, "AddDataProvider", function(self, provider)
        self.dataProviders[provider] = true
        if provider.OnAdded then provider:OnAdded(self) end
    end)
    rawset(worldMap, "RemoveDataProvider", function(self, provider) self.dataProviders[provider] = nil end)
    rawset(worldMap, "RemoveAllPinsByTemplate", function() end)
    rawset(worldMap, "EnumeratePinsByTemplate", function() return function() end end)
    rawset(worldMap, "RemovePin", function() end)
    rawset(worldMap, "AcquirePin", function() end)
    rawset(ENV, "MapCanvasDataProviderMixin", {
        OnAdded = function(self, map) self.owningMap = map end,
        OnRemoved = function(self) self.owningMap = nil end,
        GetMap = function(self) return self.owningMap end,
        RemoveAllData = function() end,
        RefreshAllData = function() end,
        OnMapChanged = function(self) self:RefreshAllData() end,
    })
    rawset(ENV, "MapCanvasPinMixin", {})
    rawset(ENV, "WorldMapFrame", worldMap)
    worldMap:Hide()
    local chat = new_object("ScrollingMessageFrame", "ChatFrame1", ENV.UIParent)
    rawset(ENV, "DEFAULT_CHAT_FRAME", chat)
    rawset(chat, "AddMessage", core.AddMessage)

    for k in pairs(ENV) do G.declared[k] = true end
    setmetatable(ENV, {
        __index = function(_, k)
            if not G.undefined[k] then
                local info = debug.getinfo(3, "Sl")
                G.undefined[k] = info and (info.short_src .. ":" .. info.currentline) or "?"
                G.undefined_order[#G.undefined_order + 1] = k
            end
            return nil
        end,
    })
    return ENV
end

-- Loads one addon source chunk into the environment, as the client does.
function G.load(source, chunkname, addon_name, ns)
    local chunk, err = loadstring(source, "@" .. chunkname)
    if not chunk then
        record_error("syntax " .. chunkname, err, "")
        return false
    end
    setfenv(chunk, ENV)
    local ok = guarded("load " .. chunkname, chunk, addon_name, ns)
    if ok then G.loaded[#G.loaded + 1] = chunkname end
    return ok
end

G.Catalog = Catalog
G.core = core
return G
