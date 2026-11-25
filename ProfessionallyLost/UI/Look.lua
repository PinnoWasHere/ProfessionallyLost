local _, CP = ...
if CP.stopped then return end

-- How the guide window looks right now: alphas, parents, strata, levels and which
-- shells show, for the window and its parts, and what draws over it. Hidden
-- `/proflost dump look` prints it; `/proflost watch look on` prints every change as it happens.
-- Each change of the window's alpha is logged, with the line that set it while watching.

local Look = { sets = {} }
CP.Look = Look

local panel = CP.Panel.frame
local Window, GP = CP.Window, CP.GatherPanel

-- Frames can answer with secret values, which can't be compared or computed on.
local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- The guide window's fade area in Daylight UI's engine (API.lua prefixes a plugin's keys).
Look.FADE_KEY = "plugin.ProfLost.guidewindow"

-- Alpha sets kept for the dump.
Look.KEEP = 6

-- Daylight UI's fade engine, or nil. Its State(key) gives now, goal, faded alpha, opacity.
local function fadeEngine()
    local addon = rawget(_G, "DaylightUI")
    local F = type(addon) == "table" and addon.Fade
    return type(F) == "table" and type(F.State) == "function" and F or nil
end

-- What the engine holds the window at: now and goal, or nil when it doesn't fade it.
function Look.FadeState()
    if not Window.managed.fade then return nil end
    local F = fadeEngine()
    if not F then return nil end
    local ok, now, goal = pcall(F.State, Look.FADE_KEY)
    if not (ok and type(now) == "number") then return nil end
    return now, goal
end

-- The first caller line outside this file: where an alpha came from.
local function caller()
    if type(debugstack) ~= "function" then return "?" end
    local ok, stack = pcall(debugstack, 3, 6, 0)
    if not (ok and type(stack) == "string") then return "?" end
    for line in stack:gmatch("[^\n]+") do
        local skip = line:find("Look.lua", 1, true) or line:find("[C]", 1, true)
            or line:find("^%s*stack traceback") or line:find("runtime.lua", 1, true)
        if not skip and line:find("%a") then
            return (line:gsub("^%s+", ""):gsub("Interface[\\/]AddOns[\\/]", ""))
        end
    end
    return "?"
end

-- Every change of the window's own alpha, newest last. The line that set it is read only
-- while the look watch is on; reading the stack on every fade step costs too much.
Look.UNTRACED = "(unread: /proflost watch look on names it)"

hooksecurefunc(panel, "SetAlpha", function(_, a)
    if isSecret(a) then return end
    local sets = Look.sets
    local last = sets[#sets]
    if last and last.alpha == a then return end
    local set = #sets >= Look.KEEP and table.remove(sets, 1) or {}
    set.alpha, set.at = a, GetTime()
    set.from = CP.trace.look and caller() or Look.UNTRACED
    sets[#sets + 1] = set
end)

-- Safe reads ------------------------------------------------------------------------

-- `ask` turns a secret answer into nil and counts it in Look.secrets, so a caller can
-- tell a frame it couldn't read.
Look.secrets = 0

-- Calls method `m` on `obj` guarded: its results, or nothing.
local function ask(obj, m, ...)
    local fn = type(obj) == "table" and obj[m]
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, obj, ...) }
    if not res[1] then return nil end
    local n = math.max(2, table.maxn(res))
    for i = 2, n do
        if isSecret(res[i]) then
            res[i] = nil
            Look.secrets = Look.secrets + 1
        end
    end
    return unpack(res, 2, n)
end
Look.Ask = ask

-- The dump ------------------------------------------------------------------------

local function nameOf(f)
    if f == nil then return "nil" end
    if f == UIParent then return "UIParent" end
    local name = ask(f, "GetName")
    if type(name) == "string" then return name end
    if f == panel then return "ProfLost_Panel" end
    for label, part in pairs(Look.Parts()) do
        if part == f then return label end
    end
    return tostring(f):gsub("^table: ", "frame ")
end

local function num(v)
    if isSecret(v) then return "secret" end
    return type(v) == "number" and ("%.2f"):format(v) or tostring(v)
end

-- The window's parts the dump reads, by label.
function Look.Parts()
    return {
        window = panel, body = CP.Panel.body, ownShell = panel.__shell, ownLine = panel.__line,
        shell = GP.shell, shellSkin = GP.shell.__shell, shellLine = GP.shell.__line,
        clip = GP.clip, sheet = GP.sheet, sheetShell = GP.sheet.__shell, sheetLine = GP.sheet.__line,
        gatherBody = GP.body, tab = GP.tab,
    }
end

Look.ORDER = { "window", "body", "ownShell", "ownLine", "shell", "shellSkin", "shellLine", "clip", "sheet",
               "sheetShell", "sheetLine", "gatherBody", "tab" }

-- One part's look: { shown, visible, alpha, effective, parent, strata, level }.
function Look.Of(f)
    if type(f) ~= "table" then return nil end
    local out = { shown = ask(f, "IsShown") == true, visible = ask(f, "IsVisible") == true, alpha = ask(f, "GetAlpha") }
    out.effective = ask(f, "GetEffectiveAlpha")
    out.parent = nameOf(ask(f, "GetParent"))
    out.strata = ask(f, "GetFrameStrata")
    out.level = ask(f, "GetFrameLevel")
    return out
end

-- Every part's look, by label.
function Look.State()
    local out = {}
    for label, f in pairs(Look.Parts()) do out[label] = Look.Of(f) end
    return out
end

-- The dump, line by line.
function Look.Lines()
    local s, lines = Look.State(), {}
    local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    add("scale %s, fade managed %s", num(ask(panel, "GetScale")), tostring(Window.managed.fade))
    for _, label in ipairs(Look.ORDER) do
        local p = s[label]
        if p then
            local level = p.level and (" %s/%d"):format(tostring(p.strata), p.level) or ""
            add("%s: %s, alpha %s, effective %s, parent %s%s", label, p.visible and "visible" or (p.shown and "shown" or "hidden"),
                num(p.alpha), num(p.effective), p.parent, level)
        end
    end
    local now, goal = Look.FadeState()
    add("Daylight fade: %s", now and ("now %s, goal %s"):format(num(now), num(goal)) or "not fading the window")
    for _, set in ipairs(Look.sets) do
        add("alpha %s at %.1f s ago from %s", num(set.alpha), GetTime() - set.at, set.from)
    end
    return lines
end

local function list(...) return { ... } end

-- A texture's look: shown, alpha, vertex colour and file.
local function textureLook(t)
    local r, g, b, a = ask(t, "GetVertexColor")
    local file = ask(t, "GetTextureFilePath") or ask(t, "GetTexture")
    return ("%s a%s rgba %s,%s,%s,%s %s"):format(ask(t, "IsShown") and "shown" or "hidden", num(ask(t, "GetAlpha")),
        num(r), num(g), num(b), num(a), tostring(file))
end

-- The textures directly on frame `f`.
local function texturesOf(f)
    local out = {}
    for _, r in ipairs(list(ask(f, "GetRegions"))) do
        if ask(r, "GetObjectType") == "Texture" then out[#out + 1] = r end
    end
    return out
end

local function childrenOf(f) return list(ask(f, "GetChildren")) end

-- The watch ---------------------------------------------------------------------------

-- Hidden: /proflost watch look on|off, for this session only. While on, every WATCH_EVERY
-- seconds the window's look is compared with the last one and each change goes to chat:
-- every frame under the window (shown, alpha, effective alpha, strata, level, parent,
-- scale), every texture of its shells, and profession-window events. Calls that change
-- the parts print with the code line that made them.
Look.WATCH_EVERY = 0.25
Look.WATCH_LINES = 12   -- changes printed per look; the rest are counted
Look.HOOK_LINES = 20    -- hooked calls printed per second; the rest are counted
Look.DEPTH = 6          -- frames under the window walked this deep

local watch = { ticker = nil, last = nil, hooked = {}, second = 0, printed = 0, held = 0 }
Look.watch = watch

function Look.Watching()
    return CP.trace.look == true
end

local function say(fmt, ...)
    CP.TraceLine("look", GetTime(), fmt, ...)
end

-- The shells whose textures the watch reads, by label.
local function shells()
    return { ownShell = panel.__shell, shellSkin = GP.shell.__shell, shell = GP.shell, tab = GP.tab }
end

-- The window's look as flat key -> text, for the watch to compare.
function Look.Snapshot()
    local out = {}
    local function frame(key, f, depth)
        if type(f) ~= "table" then return end
        out[key] = ("%s a%s e%s %s/%s parent %s scale %s"):format(
            ask(f, "IsShown") and (ask(f, "IsVisible") and "visible" or "shown") or "hidden",
            num(ask(f, "GetAlpha")), num(ask(f, "GetEffectiveAlpha")), tostring(ask(f, "GetFrameStrata")),
            tostring(ask(f, "GetFrameLevel")), nameOf(ask(f, "GetParent")), num(ask(f, "GetScale")))
        if depth >= Look.DEPTH then return end
        for i, c in ipairs(childrenOf(f)) do frame(key .. "/" .. i, c, depth + 1) end
    end
    frame("window", panel, 0)
    for label, s in pairs(shells()) do
        for i, t in ipairs(texturesOf(s)) do out[label .. ".tex" .. i] = textureLook(t) end
        for j, c in ipairs(childrenOf(s)) do
            for i, t in ipairs(texturesOf(c)) do out[label .. "/" .. j .. ".tex" .. i] = textureLook(t) end
        end
    end
    return out
end

-- The changes from `old` to `new`, as lines, sorted by key.
function Look.Changes(old, new)
    local keys, seen = {}, {}
    for k in pairs(new) do keys[#keys + 1] = k; seen[k] = true end
    for k in pairs(old) do if not seen[k] then keys[#keys + 1] = k end end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        if old[k] ~= new[k] then out[#out + 1] = ("%s: %s -> %s"):format(k, tostring(old[k]), tostring(new[k])) end
    end
    return out
end

function Look.Tick()
    if not Look.Watching() then return end
    local now = Look.Snapshot()
    if watch.last then
        local changes = Look.Changes(watch.last, now)
        for i = 1, math.min(#changes, Look.WATCH_LINES) do say("%s", changes[i]) end
        if #changes > Look.WATCH_LINES then say("... %d more changes", #changes - Look.WATCH_LINES) end
    end
    watch.last = now
end

-- A profession-window event or Daylight UI's, while watching.
function Look.Note(event, arg)
    if Look.Watching() then say("event %s %s", tostring(event), arg ~= nil and tostring(arg) or "") end
end

-- A hooked call on a part, with its caller; at most HOOK_LINES a second.
local function hooked(label, method, ...)
    if not Look.Watching() then return end
    local t = GetTime()
    if t - watch.second >= 1 then
        if watch.held > 0 then say("... %d more calls", watch.held) end
        watch.second, watch.printed, watch.held = t, 0, 0
    end
    if watch.printed >= Look.HOOK_LINES then
        watch.held = watch.held + 1
        return
    end
    watch.printed = watch.printed + 1
    local args = {}
    for i = 1, select("#", ...) do args[i] = num((select(i, ...))) end
    say("%s:%s(%s) from %s", label, method, table.concat(args, ", "), caller())
end

Look.FRAME_HOOKS = { "SetAlpha", "SetFrameStrata", "SetFrameLevel", "SetParent", "Show", "SetScale" }
Look.TEXTURE_HOOKS = { "SetVertexColor", "SetAlpha", "Show", "SetColorTexture" }

local function hookAll(label, obj, methods)
    if type(obj) ~= "table" or watch.hooked[obj] then return end
    watch.hooked[obj] = true
    for _, m in ipairs(methods) do
        if type(obj[m]) == "function" then
            hooksecurefunc(obj, m, function(_, ...) hooked(label, m, ...) end)
        end
    end
end

-- Hooks the parts and their shells' textures once, on the first watch. The hooks stay;
-- they print nothing while the watch is off.
function Look.HookParts()
    for label, f in pairs(Look.Parts()) do hookAll(label, f, Look.FRAME_HOOKS) end
    for label, s in pairs(shells()) do
        for i, t in ipairs(texturesOf(s)) do hookAll(label .. ".tex" .. i, t, Look.TEXTURE_HOOKS) end
    end
end

function Look.SetWatch(on, quiet)
    CP.SetTracing("look", on)
    if watch.ticker then watch.ticker:Cancel() end
    watch.ticker, watch.last = nil, nil
    if on then
        Look.HookParts()
        watch.last = Look.Snapshot()
        watch.ticker = C_Timer.NewTicker(Look.WATCH_EVERY, Look.Tick)
    end
    if not quiet then
        CP:Print("look watch " .. (on and "on: open and close the profession window, then paste what follows." or "off."))
    end
end

for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE" }) do
    CP:On(event, function() Look.Note(event) end)
end

-- What draws over the window ------------------------------------------------------------

-- `/proflost dump look` ends with every shown frame that overlaps the window or its
-- gathering panel and draws above it: a higher strata, or the same strata and a higher
-- level. Frames under the window count too when they draw above its content. Largest
-- overlap first, at most OVER_LINES.
Look.OVER_LINES = 20
Look.STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

-- A frame's rect in screen pixels: left, bottom, right, top, or nil.
local function screenRect(f)
    local l, b, w, h = ask(f, "GetRect")
    local k = ask(f, "GetEffectiveScale")
    if type(l) ~= "number" or type(b) ~= "number" or type(w) ~= "number" or type(h) ~= "number"
        or type(k) ~= "number" or w <= 0 or h <= 0 then return nil end
    return l * k, b * k, (l + w) * k, (b + h) * k
end

local function overlap(a, b)
    local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
    local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
    return (w > 0 and h > 0) and w * h or 0
end

-- True when `f` is the window or under it.
local function ours(f)
    for _ = 1, 30 do
        if f == nil then return false end
        if f == panel then return true end
        f = ask(f, "GetParent")
    end
    return false
end

-- The parent chain, nearest first, up to three names.
local function lineage(f)
    local names, p = {}, ask(f, "GetParent")
    while p and #names < 3 do
        names[#names + 1] = ask(p, "GetDebugName") or nameOf(p)
        p = ask(p, "GetParent")
    end
    return table.concat(names, " < ")
end

-- Its visible textures: how many, and the first two's colour and file.
local function paintOf(f)
    local n, shown = 0, {}
    for _, t in ipairs(texturesOf(f)) do
        if ask(t, "IsShown") and (ask(t, "GetAlpha") or 0) > 0 then
            n = n + 1
            if #shown < 2 then shown[#shown + 1] = textureLook(t) end
        end
    end
    return n, shown
end

-- Every frame drawing over the window, as { frame, area, line }, largest overlap first.
-- `frames` (optional) is the list to scan, else EnumerateFrames().
function Look.Over(frames)
    local targets = {}
    Look.skipped = 0
    for _, f in ipairs({ panel, GP.shell }) do
        if ask(f, "IsVisible") then
            local l, b, r, t = screenRect(f)
            if l then targets[#targets + 1] = { l, b, r, t } end
        end
    end
    if #targets == 0 then return {} end
    local strata = Look.STRATA[ask(panel, "GetFrameStrata") or "MEDIUM"] or 3
    local level = ask(panel, "GetFrameLevel") or 0
    local content = ask(CP.Panel.body, "GetFrameLevel") or level + 1
    if not frames then
        frames = {}
        local f = type(EnumerateFrames) == "function" and EnumerateFrames() or nil
        while f do
            frames[#frames + 1] = f
            f = EnumerateFrames(f)
        end
    end
    local out, skipped = {}, 0
    for _, f in ipairs(frames) do
        local seen = Look.secrets
        local mine = ours(f)
        if f ~= panel and ask(f, "IsVisible") and (ask(f, "GetEffectiveAlpha") or 0) > 0.01 then
            local fs = Look.STRATA[ask(f, "GetFrameStrata") or ""] or 0
            local fl = ask(f, "GetFrameLevel") or 0
            local above
            if mine then above = fs == strata and fl >= content
            else above = fs > strata or (fs == strata and fl > level) end
            local l, b, r, t = screenRect(f)
            if above and l then
                local area = 0
                for _, tg in ipairs(targets) do area = math.max(area, overlap({ l, b, r, t }, tg)) end
                local n, paint = paintOf(f)
                if area > 0 and (n > 0 or not mine) then
                    out[#out + 1] = { frame = f, area = area, line = ("%s%s [%s] %s/%d a%s e%s %dx%d, %d textures%s"):format(
                        mine and "(ours) " or "", ask(f, "GetDebugName") or nameOf(f), lineage(f),
                        tostring(ask(f, "GetFrameStrata")), fl, num(ask(f, "GetAlpha")), num(ask(f, "GetEffectiveAlpha")),
                        math.floor(r - l + 0.5), math.floor(t - b + 0.5), n,
                        #paint > 0 and (": " .. table.concat(paint, "; ")) or "") }
                end
            end
        end
        if Look.secrets ~= seen then skipped = skipped + 1 end
    end
    Look.skipped = skipped
    table.sort(out, function(x, y) return x.area > y.area end)
    return out
end

-- The overlap scan's lines for the dump.
function Look.OverLines(frames)
    local over, lines = Look.Over(frames), {}
    lines[1] = ("drawn over the window: %d frames"):format(#over)
    for i = 1, math.min(#over, Look.OVER_LINES) do lines[#lines + 1] = over[i].line end
    if #over > Look.OVER_LINES then lines[#lines + 1] = ("... %d more"):format(#over - Look.OVER_LINES) end
    if (Look.skipped or 0) > 0 then
        lines[#lines + 1] = ("skipped %d frames whose geometry or alpha is secret"):format(Look.skipped)
    end
    return lines
end

function Look.Dump()
    CP:Print("guide window look (paste this into the bug report):")
    for _, line in ipairs(Look.Lines()) do print("  " .. line) end
    for _, line in ipairs(Look.OverLines()) do print("  " .. line) end
end
