-- visual: what the harness doesn't keep about frames, so ProfLost's look check
-- (Look.Check, UI/LookCheck.lua) runs headless: rects, frame levels, strata, alpha and
-- scale, text widths, children, and Daylight UI's window skins.
--
-- Modelled:
--   * [guess] Rects from anchors, in screen pixels: every SetPoint form; a later point of the same
--     name replaces an earlier one; two points on an axis set the size, one point and a
--     size place it; offsets and sizes scale with the region. UIParent is SCREEN.
--   * [guess] SetAllPoints made during the scene (TOPLEFT and BOTTOMRIGHT on the target).
--   * [guess] Frame levels: a frame never given one sits one over its parent. SetFrameLevel moves
--     every descendant that has a level of its own by the same amount, clamped to
--     0..MAX_LEVEL, as the client shifts children with their parent.
--   * [guess] Strata from the nearest frame that set one, else MEDIUM. Alpha and scale multiply
--     down the parents (an instance's own GetAlpha, as craftworld's, counts).
--   * [guess] Textures, font strings, lines and masks have no GetEffectiveAlpha or
--     GetEffectiveScale, as in the game client (Daylight UI's Tour.boxOf guards the same).
--     A region's rect is in its parent's units. Visual.RegionMethods(true) gives them back.
--   * [docs] Each WowScrollBoxList list carries the template's DragDelegate (Blizzard_SharedXML
--     ScrollBox.xml): a shown child frame with no anchors and no size, so no rect.
--     Visual.Unplace(frame) gives any frame no rect.
--   * [guess] SetToplevel and IsToplevel: a frame's own flag, false until set during the scene.
--   * [docs] Raise puts a frame one level over every other shown frame in its strata, its
--     descendants moving with it; Lower puts it at 0. A click raises the nearest toplevel frame
--     at or above the clicked one (SetToplevel: "raises itself when clicked").
--     Visual.Click(frame) is that click; Visual.Over(a, b) is true when `a` draws over `b`.
--   * [guess] OnSizeChanged: a known frame's SetWidth, SetHeight or SetSize that changes its size fires
--     the script at once with the new size. A size that follows from anchors fires nothing.
--   * [guess] Font strings: LETTER px a letter (colour codes take none) at TEXT_PX, scaled by the
--     font's size and by FACES[its font file]. Unless sized, a string is as tall as its lines,
--     TEXT_H a line at TEXT_PX scaled by the font's size, as the client's string height is. A string
--     is bounded when it has a width or anchors on both sides; bounded and wrapping
--     (SetWordWrap, on by default) it breaks greedily at spaces, and "\n" always breaks.
--     IsTruncated: a line wider than its bound while not wrapping, a word wider than its
--     bound, more lines than SetMaxLines allows, or lines taller than a set height.
--     Scroll bars made from MinimalScrollBar take its template's width, SCROLL_BAR_W.
--   * [guess] GetChildren and GetRegions: the frames and regions ProfLost keeps a reference to
--     (Visual.Learn walks its UI modules) plus every frame made during the scene.
--   * [docs] Daylight UI's skins (its Style.Shell behind API.Skin): Visual.Skin swaps each window
--     shell's plain back for a stand-in made as Daylight UI makes one: a child frame on
--     the frame's rect one level under it, with its corner caps (`over`) ten over it.
-- Guesses and gaps:
--   * [guess] The harness drops SetAllPoints made at load, so a region with no anchors and no
--     size fills its parent; every such region in ProfLost is a SetAllPoints.
--   * [guess] SetParent keeps a frame's own level (the harness's SetParent can't be watched).
--   * [guess] GetWidth and GetHeight keep the harness's stored sizes, not the anchors' result.
--   * [guess] Frames ProfLost holds only in locals are missing from GetChildren.
--   * [guess] No mouse, no clipping, no draw order inside a level, no textures' pixels.
--
--   Visual.begin()       before the other worlds, so their frames are known
--   Visual.Skin()        Daylight UI's skins on the guide window, the shared shell and the sheet
--   Visual.Reload()      the state a /reload leaves, then login's placing and showing
--   Visual.Check(label)  Look.Check's lines, prefixed by `label`; fails the test on any
--   Visual.Within(fn)    a scene for `fn` alone, inside a test that goes on (the simulator)

Visual = { SCREEN = { 1920, 1080 }, LETTER = 7.5, TEXT_H = 13, TEXT_PX = 13, MAX_LEVEL = 10000, SCROLL_BAR_W = 8,
           FACE = "Fonts\\FRIZQT__.TTF",
           -- Each font file's width against FACE's, the faces daylightworld's FontFile names.
           FACES = { ["Fonts\\FRIZQT__.TTF"] = 1, ["Fonts\\MORPHEUS.TTF"] = 1.3, ["Fonts\\ARIALN.TTF"] = 0.85 } }

local CP = ProfLost
local M

local function st(o) return rawget(o, 0) end
local function isWidget(v)
    return type(v) == "table" and type(rawget(v, 0)) == "table" and rawget(v, 0).type ~= nil
end
local REGION = { Texture = true, FontString = true, Line = true, MaskTexture = true }
local function isRegion(o) return REGION[st(o).type] == true end
local function parentOf(o) return st(o).parent end

-- Known widgets --------------------------------------------------------------------------

local MODULES = { "Panel", "Window", "GatherPanel", "GatherList", "GuideTab", "ShopTab", "DisenchantTab",
                  "Host", "BugReport", "ScanButton", "Crafting", "Style" }

-- A frame's size set during the scene fires its OnSizeChanged with the new size, as the client
-- does once a frame's size changes. Each known frame's SetWidth, SetHeight and SetSize are
-- wrapped for the scene. One call per change; a handler that sizes the same frame again doesn't
-- fire it twice over.
local sizing = {}

local function watchSize(o)
    if isRegion(o) or type(o.GetScript) ~= "function" then return end
    for _, name in ipairs({ "SetWidth", "SetHeight", "SetSize" }) do
        local set = o[name]
        if type(set) == "function" and rawget(o, name) == nil then
            World.set(o, name, function(self, ...)
                local ow, oh = self:GetWidth(), self:GetHeight()
                set(self, ...)
                local w, h = self:GetWidth(), self:GetHeight()
                if sizing[self] or (math.abs((ow or 0) - (w or 0)) < 0.001 and math.abs((oh or 0) - (h or 0)) < 0.001) then
                    return
                end
                local fn = self:GetScript("OnSizeChanged")
                if not fn then return end
                sizing[self] = true
                local ok, err = pcall(fn, self, w, h)
                sizing[self] = nil
                if not ok then error(err, 0) end
            end)
        end
    end
end

local function register(o)
    if M.seen[o] then return end
    M.seen[o] = true
    M.known[#M.known + 1] = o
    M.kids = nil
    watchSize(o)
end

-- Every widget ProfLost's UI modules reach, with their parents.
function Visual.Learn()
    local tables = {}
    local visit
    local function add(o, path)
        if not M.names[o] or #path < #M.names[o] then M.names[o] = path end
        if M.seen[o] then return end
        register(o)
        for k, v in pairs(o) do
            if k ~= 0 then visit(v, 3, path .. "." .. tostring(k)) end
        end
        local p = parentOf(o)
        if p then add(p, path .. ":parent") end
    end
    function visit(v, depth, path)
        if type(v) ~= "table" or tables[v] then return end
        if isWidget(v) then return add(v, path) end
        if depth <= 0 then return end
        tables[v] = true
        for k, x in pairs(v) do
            visit(k, depth - 1, path)
            visit(x, depth - 1, path .. "." .. tostring(k))
        end
    end
    -- Style.columns, Style.cut and Style.pickRows index strings and rows without holding
    -- them: the strays other test files left in them are no part of the scene.
    tables[CP.Style.columns] = true
    tables[CP.Style.cut] = true
    tables[CP.Style.pickRows] = true
    for _, name in ipairs(MODULES) do visit(CP[name], 4, name) end
end

-- The regions and frames each known widget keeps in its own fields (a row's `name`,
-- `range`...), made after Learn, so their parents list them.
function Visual.LearnFields()
    local i = 1
    while M.known[i] do
        local o = M.known[i]
        for k, v in pairs(o) do
            if k ~= 0 and isWidget(v) and not M.seen[v] then
                M.names[v] = M.names[v] or ((M.names[o] or "?") .. "." .. tostring(k))
                register(v)
            end
        end
        i = i + 1
    end
end

-- The parent index lasts one tick of the clock, or one Look.Check: a SetParent can't be watched.
local function children(f, regions)
    if M.kidsAt ~= T.clock() then M.kids = nil end
    if not M.kids then
        M.kidsAt = T.clock()
        M.kids, M.regions = {}, {}
        for _, o in ipairs(M.known) do
            local p = parentOf(o)
            if p then
                local into = isRegion(o) and M.regions or M.kids
                into[p] = into[p] or {}
                table.insert(into[p], o)
            end
        end
    end
    return unpack((regions and M.regions or M.kids)[f] or {})
end

-- Levels, strata, alpha, scale --------------------------------------------------------------

local function clamp(n) return math.max(0, math.min(Visual.MAX_LEVEL, n)) end

local function levelOf(o)
    if o == nil or o == UIParent then return 0 end
    local own = M.level[o]
    if own then return own end
    local p = parentOf(o)
    if p == nil then return 0 end
    return clamp(levelOf(p) + 1)
end

local function under(o, top)
    local p = parentOf(o)
    while p do
        if p == top then return true end
        p = parentOf(p)
    end
    return false
end

local function setLevel(o, n)
    n = clamp(math.floor(tonumber(n) or 0))
    local delta = n - levelOf(o)
    M.level[o] = n
    if delta == 0 then return end
    for _, d in ipairs(M.known) do
        if M.level[d] and d ~= o and under(d, o) then M.level[d] = clamp(M.level[d] + delta) end
    end
end

local function strataOf(o)
    while o do
        if M.strata[o] then return M.strata[o] end
        o = parentOf(o)
    end
    return "MEDIUM"
end

local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                      FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function raise(o)
    local strata, top = strataOf(o), 0
    for _, d in ipairs(M.known) do
        if d ~= o and type(d.Raise) == "function" and not under(d, o) and d:IsShown()
            and strataOf(d) == strata then
            top = math.max(top, levelOf(d))
        end
    end
    setLevel(o, top + 1)
end

-- A click on `frame`: the nearest toplevel frame at or above it comes to the front.
function Visual.Click(frame)
    local o = frame
    while o and o ~= UIParent do
        if M.top[o] then return raise(o) end
        o = parentOf(o)
    end
end

-- True when `a` draws over `b`: a higher strata, or the same strata and a higher level.
function Visual.Over(a, b)
    local sa, sb = STRATA_RANK[strataOf(a)] or 0, STRATA_RANK[strataOf(b)] or 0
    if sa ~= sb then return sa > sb end
    return levelOf(a) > levelOf(b)
end

local function alphaOf(o) return M.alpha[o] or 1 end
local function scaleOf(o) return M.scale[o] or 1 end

local function effective(o, method)
    local v = 1
    while o do
        local x = o[method](o)
        v = v * (tonumber(x) or 1)
        o = parentOf(o)
    end
    return v
end

-- Rects -------------------------------------------------------------------------------------

local FRACTION = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local lineHeight, layout   -- below, with wrapping

local function plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- A font string's font file and size.
local function fontOf(fs)
    local f = M and M.font[fs]
    local px = f and tonumber(f.px) or 0
    return f and f.path ~= "" and f.path or Visual.FACE, px > 0 and px or Visual.TEXT_PX
end

-- px a letter in `fs`'s font.
local function letter(fs)
    local path, px = fontOf(fs)
    return Visual.LETTER * px / Visual.TEXT_PX * (Visual.FACES[path] or 1)
end

local function span(fs, s) return math.ceil(#s * letter(fs)) end

-- `fs`'s text as its lines: "\n" breaks, nothing else.
local function paragraphs(fs)
    local out = {}
    for line in (plain(st(fs).text) .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    return out
end

-- The widest of its lines.
local function textWidth(fs)
    local w = 0
    for _, line in ipairs(paragraphs(fs)) do w = math.max(w, span(fs, line)) end
    return w
end

-- A region's own size, in its own units.
local function sizeOf(o)
    local w, h = st(o).width or 0, st(o).height or 0
    local given = M.intrinsic[o]
    if given then
        if w <= 0 then w = given[1] end
        if h <= 0 then h = given[2] end
    end
    if st(o).type == "FontString" then
        if w <= 0 then w = textWidth(o) end
        if h <= 0 then h = lineHeight(o) end   -- resolve counts its lines once it has a width
    end
    return w, h
end

-- Its anchors, the last of each point name winning.
local function pointsOf(o)
    local byName, order = {}, {}
    for _, p in ipairs(st(o).points) do
        local name = tostring(p[1]):upper()
        if not byName[name] then order[#order + 1] = name end
        byName[name] = p
    end
    local out = {}
    for _, name in ipairs(order) do out[#out + 1] = byName[name] end
    return out
end

-- point, relative region, relative point, x, y from one SetPoint's arguments.
local function parse(o, p)
    local point = tostring(p[1]):upper()
    local rel, relPoint, x, y = parentOf(o), point, 0, 0
    if type(p[2]) == "number" then
        x, y = p[2], p[3] or 0
    else
        if p[2] ~= nil then rel = type(p[2]) == "string" and rawget(_G, p[2]) or p[2] end
        if type(p[3]) == "string" then
            relPoint, x, y = p[3]:upper(), p[4] or 0, p[5] or 0
        elseif type(p[3]) == "number" then
            x, y = p[3], p[4] or 0
        end
    end
    return point, rel, relPoint, tonumber(x) or 0, tonumber(y) or 0
end

local busy = {}

-- left, bottom, right, top in screen pixels, or nil.
local function resolve(o)
    if o == UIParent then return 0, 0, Visual.SCREEN[1], Visual.SCREEN[2] end
    if busy[o] or M.unplaced[o] then return nil end
    busy[o] = true
    local k = effective(o, "GetScale")
    local w, h = sizeOf(o)
    w, h = w * k, h * k
    local pts = pointsOf(o)
    local l, b, r, t
    if #pts == 0 then
        local p = parentOf(o)
        if w <= 0 and h <= 0 and p then l, b, r, t = resolve(p) end
        busy[o] = nil
        return l, b, r, t
    end
    local hx, vy = {}, {}
    for _, pt in ipairs(pts) do
        local point, rel, relPoint, x, y = parse(o, pt)
        local rl, rb, rr, rt
        if rel == nil then rl, rb, rr, rt = 0, 0, Visual.SCREEN[1], Visual.SCREEN[2]
        else rl, rb, rr, rt = resolve(rel) end
        local f, rf = FRACTION[point], FRACTION[relPoint]
        if not (rl and f and rf) then
            busy[o] = nil
            return nil
        end
        hx[#hx + 1] = { f[1], rl + rf[1] * (rr - rl) + x * k }
        vy[#vy + 1] = { f[2], rb + rf[2] * (rt - rb) + y * k }
    end
    busy[o] = nil
    -- Both edges set the span. Else a size places it from an edge (a centre point last),
    -- and two points of different kinds set it.
    local function axis(list, size)
        local edge = {}
        for _, a in ipairs(list) do
            if a[1] ~= 0.5 then edge[a[1]] = a[2] end
        end
        if edge[0] and edge[1] then return edge[0], edge[1] end
        if size > 0 or #list == 1 then
            local a = list[1]
            for _, c in ipairs(list) do
                if c[1] ~= 0.5 then a = c break end
            end
            local lo = a[2] - a[1] * size
            return lo, lo + size
        end
        for i = 2, #list do
            local a, c = list[1], list[i]
            if a[1] ~= c[1] then
                local span = (c[2] - a[2]) / (c[1] - a[1])
                local lo = a[2] - a[1] * span
                return lo, lo + span
            end
        end
        return list[1][2], list[1][2]
    end
    l, r = axis(hx, w)
    -- An unsized string is as tall as its lines at the width it resolved to.
    if st(o).type == "FontString" and (st(o).height or 0) <= 0 and not M.intrinsic[o] then
        local sides = {}
        for _, a in ipairs(hx) do sides[a[1]] = true end
        local room = (st(o).width or 0) > 0 and st(o).width or (sides[0] and sides[1] and (r - l) / k) or false
        h = lineHeight(o) * math.max(1, #(layout(o, room))) * k
    end
    b, t = axis(vy, h)
    return l, b, r, t
end
Visual.Resolve = resolve

-- Wrapping ------------------------------------------------------------------------------------

-- The width a font string's lines must fit, in its own units, or nil when it grows to its text.
local function bound(fs)
    local w = st(fs).width or 0
    if w > 0 then return w end
    local sides = {}
    for _, p in ipairs(pointsOf(fs)) do
        local f = FRACTION[tostring(p[1]):upper()]
        if f then sides[f[1]] = true end
    end
    if not (sides[0] and sides[1]) then return nil end
    local l, _, r = resolve(fs)
    if not l then return nil end
    return (r - l) / effective(fs, "GetScale")
end

-- SetWordWrap lasts across scenes, as a string keeps it. The recorder is installed when this
-- file loads and stays, so a call made in a test with no scene (a pooled row's SetWordWrap(false))
-- still counts. A string never told wraps unless Style.Column marked it.
Visual.wrap = setmetatable({}, { __mode = "k" })
T.stub("FontString:SetWordWrap", function(self, on) Visual.wrap[self] = on and true or false end)

local function wraps(fs)
    local on = Visual.wrap[fs]
    if on == nil then return not CP.Style.columns[fs] end
    return on
end

-- Its lines as drawn, and whether any of them can't fit (a word wider than the bound).
-- `room` is the bound when the caller knows it, false for none.
function layout(fs, room)
    if room == nil then room = bound(fs) end
    room = room or nil
    local out, over = {}, false
    for _, para in ipairs(paragraphs(fs)) do
        if not room or not wraps(fs) then
            out[#out + 1] = para
            if room and span(fs, para) > room + 0.5 then over = true end
        else
            local cur = ""
            for word in para:gmatch("%S+") do
                local try = cur == "" and word or (cur .. " " .. word)
                if span(fs, try) <= room + 0.5 then
                    cur = try
                else
                    if cur ~= "" then out[#out + 1] = cur end
                    cur = word
                    if span(fs, word) > room + 0.5 then over = true end
                end
            end
            out[#out + 1] = cur
        end
    end
    return out, over
end

function lineHeight(fs)
    local _, px = fontOf(fs)
    return Visual.TEXT_H * px / Visual.TEXT_PX
end

local function truncated(fs)
    if (st(fs).text or "") == "" then return false end
    local lines, over = layout(fs)
    if over then return true end
    local most = M.maxLines[fs] or 0
    if most > 0 and #lines > most then return true end
    local h = st(fs).height or 0
    return h > 0 and #lines * lineHeight(fs) > h + 0.5
end
Visual.Truncated = truncated

-- Patches -------------------------------------------------------------------------------------

local FRAME_KINDS = { "Frame" }
local REGION_KINDS = { "Region" }

local function stub(path, fn)
    T.stub(path, fn)
    M.stubs[#M.stubs + 1] = path
end

local function own(o, l, b, r, t)
    if not l then return nil end
    local k = effective(o, "GetScale")
    return l / k, b / k, r / k, t / k
end

-- Each scroll box's DragDelegate, made once.
local delegates = {}

-- One region of each kind, made once, whose method tables RegionMethods edits.
local samples

-- Gives the region kinds GetEffectiveAlpha and GetEffectiveScale, or takes them away, for
-- the rest of the scene.
function Visual.RegionMethods(on)
    samples = samples or { UIParent:CreateTexture(), UIParent:CreateFontString(), UIParent:CreateLine(),
                           UIParent:CreateMaskTexture() }
    for _, o in ipairs(samples) do
        local methods = getmetatable(o).__index
        if not M.regionMethods then M.regionMethods = {} end
        local keep = M.regionMethods[methods] or {
            GetEffectiveAlpha = rawget(methods, "GetEffectiveAlpha"),
            GetEffectiveScale = rawget(methods, "GetEffectiveScale"),
        }
        M.regionMethods[methods] = keep
        for name, fn in pairs(keep) do World.set(methods, name, on and fn or nil) end
    end
end

-- `frame` resolves to no rect, as a frame with no anchors and no size does in the client.
function Visual.Unplace(frame)
    M.unplaced[frame] = true
end

function Visual.begin()
    M = { level = {}, strata = {}, alpha = {}, scale = {}, known = {}, seen = {}, stubs = {}, names = {}, intrinsic = {},
          font = {}, maxLines = {}, top = {}, unplaced = {} }
    Visual.state = M
    World.onEnd(function()
        for _, path in ipairs(M.stubs) do T.stub(path, nil) end
    end)

    for _, kind in ipairs(FRAME_KINDS) do
        stub(kind .. ":SetFrameLevel", function(self, n) setLevel(self, n) end)
        stub(kind .. ":GetFrameLevel", function(self) return levelOf(self) end)
        stub(kind .. ":SetFrameStrata", function(self, s) M.strata[self] = s end)
        stub(kind .. ":GetFrameStrata", function(self) return strataOf(self) end)
        stub(kind .. ":SetToplevel", function(self, on) M.top[self] = on and true or false end)
        stub(kind .. ":IsToplevel", function(self) return M.top[self] == true end)
        stub(kind .. ":Raise", function(self) raise(self) end)
        stub(kind .. ":Lower", function(self) setLevel(self, 0) end)
        stub(kind .. ":GetChildren", function(self) return children(self) end)
        stub(kind .. ":GetNumChildren", function(self) return select("#", children(self)) end)
        stub(kind .. ":GetRegions", function(self) return children(self, true) end)
    end
    for _, kind in ipairs({ "Frame", "Region" }) do
        stub(kind .. ":SetAlpha", function(self, a) M.alpha[self] = tonumber(a) or 1 end)
        stub(kind .. ":GetAlpha", function(self) return alphaOf(self) end)
        stub(kind .. ":GetEffectiveAlpha", function(self) return effective(self, "GetAlpha") end)
        stub(kind .. ":SetScale", function(self, s) M.scale[self] = tonumber(s) or 1 end)
        stub(kind .. ":GetScale", function(self) return scaleOf(self) end)
        stub(kind .. ":GetEffectiveScale", function(self) return effective(self, "GetScale") end)
    end
    stub("ScriptRegion:GetLeft", function(self) local l = own(self, resolve(self)) return l end)
    stub("ScriptRegion:GetBottom", function(self) local _, b = own(self, resolve(self)) return b end)
    stub("ScriptRegion:GetRight", function(self) local _, _, r = own(self, resolve(self)) return r end)
    stub("ScriptRegion:GetTop", function(self) local _, _, _, t = own(self, resolve(self)) return t end)
    stub("ScriptRegion:GetRect", function(self)
        local l, b, r, t = own(self, resolve(self))
        if not l then return nil end
        return l, b, r - l, t - b
    end)
    stub("ScriptRegion:GetCenter", function(self)
        local l, b, r, t = own(self, resolve(self))
        if not l then return nil end
        return (l + r) / 2, (b + t) / 2
    end)
    stub("ScriptRegionResizing:SetAllPoints", function(self, rel)
        rel = rel or parentOf(self)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
        self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
    end)
    stub("FontString:GetUnboundedStringWidth", function(self) return textWidth(self) end)
    stub("FontString:GetStringWidth", function(self)
        local w = st(self).width or 0
        local need = textWidth(self)
        return w > 0 and math.min(w, need) or need
    end)
    for _, kind in ipairs({ "FontInstance", "FontString" }) do
        stub(kind .. ":SetFont", function(self, path, px)
            M.font[self] = { path = path, px = px }
            return true
        end)
        stub(kind .. ":GetFont", function(self)
            local path, px = fontOf(self)
            return path, px, ""
        end)
    end
    stub("FontString:CanWordWrap", function(self) return wraps(self) end)
    stub("FontString:SetMaxLines", function(self, n) M.maxLines[self] = tonumber(n) or 0 end)
    stub("FontString:GetMaxLines", function(self) return M.maxLines[self] or 0 end)
    stub("FontString:GetNumLines", function(self)
        if (st(self).text or "") == "" then return 0 end
        return #(layout(self))
    end)
    stub("FontString:GetStringHeight", function(self)
        if (st(self).text or "") == "" then return 0 end
        return #(layout(self)) * lineHeight(self)
    end)
    stub("FontString:IsTruncated", function(self) return truncated(self) end)
    -- Text colours set during the scene; one set before it reads white.
    local colors = setmetatable({}, { __mode = "k" })
    for _, kind in ipairs({ "FontInstance", "FontString" }) do
        stub(kind .. ":SetTextColor", function(self, r, g, b, a) colors[self] = { r, g, b, a or 1 } end)
        stub(kind .. ":GetTextColor", function(self)
            local c = colors[self] or { 1, 1, 1, 1 }
            return c[1], c[2], c[3], c[4]
        end)
    end
    World.set(UIParent, "GetWidth", function() return Visual.SCREEN[1] end)
    World.set(UIParent, "GetHeight", function() return Visual.SCREEN[2] end)

    -- Frames made during the scene are known as they are made.
    local create = CreateFrame

    -- [guess] Every frame made during the scene is known to Visual, with the level one over its parent.
    World.set(_G, "CreateFrame", function(...)
        local f = create(...)
        register(f)
        return f
    end)
    Visual.Learn()
    -- MinimalScrollBar's template width (Blizzard_SharedXML MinimalScrollBar.xml).
    for _, e in ipairs(CP.Style.scrolls) do
        if e.plain then M.intrinsic[e.plain] = { Visual.SCROLL_BAR_W, 0 } end
    end
    -- Each WowScrollBoxList's DragDelegate, as the template makes it.
    for _, e in ipairs(CP.Style.scrolls) do
        local box = e.list
        if type(box.GetDerivedScrollOffset) == "function" then
            local d = delegates[box] or create("Frame", nil, box)
            delegates[box] = d
            rawset(box, "DragDelegate", d)
            register(d)
            M.unplaced[d] = true
            M.names[d] = (M.names[box] or "box") .. ".DragDelegate"
            d:Show()
        end
    end
    World.onEnd(function()
        for _, d in pairs(delegates) do d:Hide() end
    end)
    Visual.RegionMethods(false)
    -- Problem lines name a frame by where ProfLost keeps it.
    local check = CP.Look.Check
    World.set(CP.Look, "Check", function(...)
        Visual.LearnFields()
        M.kids = nil
        return check(...)
    end)
    local label = CP.Look.Label
    World.set(CP.Look, "Label", function(f)
        return f and f[0] and (f[0].name or M.names[f]) or label(f)
    end)
    -- Every scalable string takes its size role's size, as at login (Plugin.Sync).
    CP.Style.ApplyScale()
end

-- Daylight UI's skins ---------------------------------------------------------------------------

-- A stand-in for the skin Daylight UI's Style.Shell makes on `frame`: a child on its rect
-- one level under it, its corner caps ten over it, in place of our plain back.
local function skin(frame)
    local S = CP.Style
    local plainBack = frame.__shell
    local s = CreateFrame("Frame", nil, frame)
    s:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    s:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    s:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    s.over = CreateFrame("Frame", nil, s)
    s.over:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    s.over:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    s.over:SetFrameLevel(frame:GetFrameLevel() + 10)
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    register(s.bg)
    s:SetShown(plainBack == nil or plainBack:IsShown())
    if plainBack then plainBack:Hide() end
    M.names[s], M.names[s.over] = M.names[frame] and (M.names[frame] .. ".__shell") or "skin", "skin.over"
    World.set(frame, "__shell", s)
    World.set(S.skins, frame, s)
    World.onEnd(function()
        if plainBack then plainBack:SetShown(s:IsShown()) end
        s:Hide()
    end)
    return s
end

function Visual.Skin()
    local P, GP = CP.Panel, CP.GatherPanel
    for _, f in ipairs({ P.frame, GP.shell, GP.sheet }) do skin(f) end
end

-- A reload ----------------------------------------------------------------------------------------

-- What a /reload leaves: the guide window hidden, the gathering parts unplaced and the sheet
-- in its clip, as the files make them. Then PLAYER_LOGIN places both anchors (no Daylight
-- UI mover) and PLAYER_ENTERING_WORLD shows what is wanted.
function Visual.Reload()
    local P, W, GP, S = CP.Panel, CP.Window, CP.GatherPanel, CP.Style
    P.frame:Hide()
    if GP.sheet:GetParent() ~= GP.clip then GP.sheet:SetParent(GP.clip) end
    GP.sheet:SetScale(1)
    S.ShellShown(GP.sheet, false)
    S.LineShown(GP.sheet, false)
    GP.closeButton:Hide()
    GP.grip:Hide()
    for _, f in ipairs({ GP.shell, GP.clip, GP.sheet, GP.tab, GP.seam, P.frame, W.anchor, GP.anchor }) do
        f:ClearAllPoints()
    end
    GP.clip:SetWidth(0.01)
    GP.side, GP.goal, GP.p = nil, nil, 0
    W.PlaceAnchor()
    GP.PlaceAnchor()
    W.Update()
end

-- A visual scene inside a running test ---------------------------------------------------------------

-- Runs `fn` in a visual scene begun now and ended when it returns, so a long test (a
-- simulator run) can measure its windows for a moment: the scene's closers and patches come
-- off, newest first, and the test's own stay.
function Visual.Within(fn)
    local patches, ends = #World.patches, #World.ends
    Visual.begin()
    local ok, err = pcall(fn)
    while #World.ends > ends do
        local closed, why = pcall(table.remove(World.ends))
        if ok and not closed then ok, err = false, why end
    end
    while #World.patches > patches do
        local p = table.remove(World.patches)
        rawset(p.t, p.key, p.old)
    end
    Visual.state = nil
    if not ok then error(err, 0) end
end

-- Checking ------------------------------------------------------------------------------------------

-- Look.Check's lines for the state named `label`.
function Visual.Problems(label)
    local out = {}
    for _, line in ipairs(CP.Look.Check()) do out[#out + 1] = label .. ": " .. line end
    return out
end

-- Fails the test with every broken rule, each prefixed by `label`.
function Visual.Check(label)
    local lines = Visual.Problems(label)
    T.ok(#lines == 0, ("%d look problems\n  %s"):format(#lines, table.concat(lines, "\n  ")))
end
