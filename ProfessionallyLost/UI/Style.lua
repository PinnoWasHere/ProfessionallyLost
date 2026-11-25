local _, CP = ...
if CP.stopped then return end

-- ProfLost's look is Daylight UI's: every window, control, bar and text colour comes
-- from its public API (DaylightUI/API.md), so ProfLost matches whatever font, accent
-- and colours the player picked. Nothing of Daylight UI is copied here. Without its
-- API (the headless tests) the same calls make plain, unstyled frames.

local Style = {}
CP.Style = Style

local WHITE = "Interface\\Buttons\\WHITE8x8"
local DAYLIGHT = "DaylightUI"   -- the addon's global, a required dependency; not a game API

-- Daylight UI's API, or nil without it.
function Style.Daylight()
    local addon = _G[DAYLIGHT]
    local API = addon and addon.API
    return API and API.major == 1 and API or nil
end

-- A file in Daylight UI's media folder, by path: API.Media (API 1.7) when it has it, else
-- the folder spelled out.
local MEDIA_DIR = "Interface\\AddOns\\DaylightUI\\Media\\"
function Style.Media(file)
    local API = Style.Daylight()
    if API and type(API.Media) == "function" then
        local ok, path = pcall(API.Media, file)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    return MEDIA_DIR .. file
end

-- Colour roles. Filled from Daylight UI's colours and accent below; these values are
-- only what the plain frames show without it.
Style.color = {
    title    = { 1, 1, 1 },
    text     = { 0.95, 0.93, 0.9 },
    label    = { 0.76, 0.71, 0.62 },
    muted    = { 0.55, 0.51, 0.45 },
    good     = { 0.55, 0.85, 0.55 },
    warn     = { 0.95, 0.72, 0.32 },
    bad      = { 0.93, 0.36, 0.3 },
    accent   = { 0.12, 0.56, 1 },
    hover    = { 1, 1, 1, 0.05 },
    selected = { 0.12, 0.56, 1, 0.14 },
}

-- The game's own recipe difficulty colours, for recipe names.
Style.difficulty = {
    [0] = { 1, 0.5, 0.25 },     -- orange
    [1] = { 1, 0.87, 0.33 },    -- yellow
    [2] = { 0.55, 0.85, 0.55 }, -- green
    [3] = { 0.55, 0.51, 0.45 }, -- grey
}

local RULE = { 1, 1, 1, 0.06 }
local SIZES = { tiny = 10, small = 12, body = 13, head = 15, title = 18 }

local function fill(t, c) t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

local roles = setmetatable({}, { __mode = "k" })   -- font string -> its Style.color table
local inked = setmetatable({}, { __mode = "k" })   -- font strings a Daylight UI look colours
local bases = setmetatable({}, { __mode = "k" })   -- scalable font string -> its unscaled size

-- The text size setting's range. Columns measure their text at any size; the guide
-- window's widest is 520 px times the size (Panel.Cap).
Style.SCALE_MIN, Style.SCALE_MAX = 0.85, 1.15

local function scale()
    local s = CP.db and CP.db.textScale or 1
    return math.max(Style.SCALE_MIN, math.min(Style.SCALE_MAX, s))
end

local function sizeTo(fs)
    local path, _, flags = fs:GetFont()
    if path and bases[fs] then fs:SetFont(path, bases[fs] * scale(), flags or "") end
end
local accents = {}                                 -- painters for accent-coloured pieces

local function accentColor()
    local a = Style.color.accent
    return a[1], a[2], a[3]
end

-- Daylight UI's text colours and accent, poured into Style.color's own tables so every
-- later SetTextColor reads them; strings made earlier are recoloured.
local ROLE = { title = "TITLE", text = "TEXT", label = "LABEL", muted = "OFF", good = "GOOD", warn = "WARN", bad = "BAD" }
function Style.Repaint()
    local API = Style.Daylight()
    if not API then return end
    local C = API.Colors and API.Colors() or {}
    for role, key in pairs(ROLE) do
        local c, mine = C[key], Style.color[role]
        if c and mine then mine[1], mine[2], mine[3] = c[1], c[2], c[3] end
    end
    if API.Accent then
        local r, g, b = API.Accent()
        local a, sel = Style.color.accent, Style.color.selected
        a[1], a[2], a[3] = r, g, b
        sel[1], sel[2], sel[3] = r, g, b
    end
    for fs, c in pairs(roles) do
        if not inked[fs] then fs:SetTextColor(unpack(c)) end
    end
    for _, paint in ipairs(accents) do paint() end
    -- The player's font may have changed under "general".
    if Style.ApplyFont then Style.ApplyFont() end
end

do
    local API = Style.Daylight()
    if API then
        Style.Repaint()
        if API.On then API.On("StyleChanged", Style.Repaint, CP.name) end
    end
end

-- Runs `paint` after each Style.Repaint, once the role colours are poured in.
function Style.OnRepaint(paint)
    accents[#accents + 1] = paint
end

-- A texture in the player's accent, kept in it when the accent changes.
local function accentTexture(parent, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    local function paint() t:SetColorTexture(accentColor()) end
    accents[#accents + 1] = paint
    paint()
    return t
end
Style.AccentTexture = accentTexture

-- Tints `t` (a white ring texture) with the player's accent, and keeps it in step with the
-- accent. Daylight UI's own painter is used when it is loaded.
function Style.AccentRing(t)
    local function paint()
        local core = rawget(_G, DAYLIGHT)
        local St = type(core) == "table" and core.Style
        if type(St) == "table" and type(St.PaintAccent) == "function" and pcall(St.PaintAccent, t, 1) then return end
        t:SetVertexColor(accentColor())
    end
    accents[#accents + 1] = paint
    paint()
end

-- Windows ----------------------------------------------------------------------

-- The accent line along a window's top, as Daylight UI's profession window draws it
-- (Windows/Frame.lua, Win.Lines and Win.Repaint): Win.LINE px tall, 6 px in from each
-- side, 2 px down, in the accent gradient at 0.7 alpha.
Style.TOP_LINE = { height = 2, inset = 6, y = 2, alpha = 0.7 }

-- A window's content edge: Daylight UI's Win.EDGE (Windows/Frame.lua). Its rules under a
-- header run this far in from each side, so they stay off the border.
Style.CONTENT_EDGE = 16

-- The two-line header both ProfLost windows share (the guide's title bar, the gathering panel's
-- header). Line 1 (`head`, 15 px) starts `top` px down and line 2 (`small`, 12 px) `gap` px
-- under it; the header ends `bottom` px under line 2. The first item starts `left` px in, the
-- last control's box ends `right` px in (a 12 px glyph in a 16 px box ends 15 px in, as
-- Daylight UI's close does), and the logo and controls centre on the two lines, `mid` px
-- down, as Daylight UI's full header (Win.Header) centres its close and portrait. `top` is
-- its Win.TITLE_Y, `left` its Win.EDGE, `gap` Style.LEADING. Header lines keep these sizes at
-- every text size (Style.HeaderText), so the two headers line up side by side.
local HEADER = { left = 16, right = 13, top = 12, gap = 3, bottom = 12, line1 = "head", line2 = "small" }
HEADER.px1, HEADER.px2 = SIZES.head, SIZES.small
HEADER.line2Top = HEADER.top + HEADER.px1 + HEADER.gap
HEADER.height = HEADER.line2Top + HEADER.px2 + HEADER.bottom
HEADER.mid = (HEADER.top + HEADER.height - HEADER.bottom) / 2
Style.HEADER = HEADER

local function daylightCore()
    local addon = rawget(_G, DAYLIGHT)
    return type(addon) == "table" and addon or nil
end

-- Daylight UI's window parts (Windows/Parts.lua) when it has `name`, else nil.
local function daylightParts(name)
    local core = Style.Daylight() and daylightCore()
    local Parts = core and type(core.Win) == "table" and core.Win.Parts
    return type(Parts) == "table" and type(Parts[name]) == "function" and Parts or nil
end

-- A faint 1 px line on `parent` in `layer`: Daylight UI's Parts.Rule when loaded, else ours.
-- The caller anchors it.
local function rule(parent, layer)
    local Parts = daylightParts("Rule")
    if Parts then
        local ok, t = pcall(Parts.Rule, parent)
        if ok and t then return t end
    end
    local t = parent:CreateTexture(nil, layer)
    fill(t, RULE)
    t:SetHeight(1)
    return t
end

-- Paints `t` as Daylight UI paints its top line: its Style.PaintAccent when loaded.
local function paintTopLine(t, alpha)
    local a = alpha or Style.TOP_LINE.alpha
    local core = daylightCore()
    local St = core and core.Style
    if type(St) == "table" and type(St.PaintAccent) == "function" and pcall(St.PaintAccent, t, a) then return end
    local r, g, b = accentColor()
    t:SetVertexColor(r, g, b, a)
end
Style.PaintTopLine = paintTopLine

local function topLine(frame)
    local L = Style.TOP_LINE
    local core = daylightCore()
    local h = core and type(core.Win) == "table" and tonumber(core.Win.LINE) or L.height
    local t = frame:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    t:SetHeight(h)
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", L.inset, -L.y)
    t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -L.inset, -L.y)
    accents[#accents + 1] = function() paintTopLine(t) end
    paintTopLine(t)
    return t
end

-- Daylight UI's shell frames that skin ours, by the frame skinned.
local skins = {}
Style.skins = skins

local function track(frame, s)
    if s then skins[frame] = s end
    return s
end

-- Keeps only the top `shown` px of `anchor` on screen. A window hangs from the top of an
-- anchor sized for its largest height, so /dui unlock shows that size; the clamp lets
-- the unused part below run off the bottom edge. `left` and `right` widen the kept
-- rect past the anchor's sides, for what hangs beside it (the attached gathering panel).
function Style.ClampTop(anchor, shown, left, right)
    local h = anchor:GetHeight() or 0
    local below = math.max(0, h - (shown or h))
    anchor.profLostClampBelow = below
    anchor.profLostClampLeft, anchor.profLostClampRight = left or 0, right or 0
    anchor:SetClampRectInsets(-(left or 0), right or 0, 0, below)
end

-- The strata every ProfLost window stands in. Action bars, nameplates and world markers draw
-- in MEDIUM and below, and so do Daylight UI's own windows. The game's and Daylight UI's
-- dialogs, popups and menus draw in DIALOG and up, and tooltips in TOOLTIP. HIGH sits
-- between the two.
Style.WINDOW_STRATA = "HIGH"
Style.STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                 FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

-- Puts every shell one level under its frame and its corner caps ten above, as Daylight
-- UI makes them. A move of a frame to a very high or low level clamps its descendants'
-- levels and leaves a shell over the content.
function Style.Restack()
    for frame, s in pairs(skins) do
        local level = frame:GetFrameLevel()
        s:SetFrameLevel(math.max(0, level - 1))
        if s.over then s.over:SetFrameLevel(level + 10) end
    end
end

-- Window opacity. The setting's default leaves a shell on Daylight UI's own window
-- opacity (window = true); any other value is passed as that shell's bgAlpha. Without
-- Daylight UI the fallback fill takes the value, or FALLBACK_ALPHA at the default.
Style.OPACITY_DEFAULT = 0.85
Style.FALLBACK_ALPHA = 0.9
local backs = setmetatable({}, { __mode = "k" })   -- frame -> { skin = function, fill = texture }

-- The alpha to pass as bgAlpha, or nil to follow Daylight UI.
function Style.WindowAlpha()
    local v = CP.db and tonumber(CP.db.windowOpacity)
    if not v or math.abs(v - Style.OPACITY_DEFAULT) < 0.001 then return nil end
    return math.max(0.2, math.min(1, v))
end

local function backOpts(opts)
    opts.window = true
    opts.bgAlpha = Style.WindowAlpha()
    return opts
end

-- Repaints every window background at the current setting.
function Style.ApplyOpacity()
    for _, b in pairs(backs) do
        if b.skin then b.skin() end
        if b.fill then
            local a = Style.WindowAlpha() or Style.FALLBACK_ALPHA
            b.fill:SetColorTexture(0.08, 0.08, 0.09, a)
        end
    end
end

-- The window shell: Daylight UI's, redrawn on resize as its API asks, the accent line
-- along the top as its profession window draws it, and a rule under the tab row at `tabsY`.
-- `fixed` keeps the shell off the opacity setting.
function Style.Shell(frame, tabsY, fixed)
    local API = Style.Daylight()
    if API then
        local function skin()
            local o = { window = true }
            if not fixed then backOpts(o) end
            frame.__shell = track(frame, API.Skin(frame, o)) or frame.__shell
        end
        skin()
        frame:HookScript("OnSizeChanged", skin)
        if not fixed then backs[frame] = { skin = skin } end
    else
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT")
        bg:SetPoint("BOTTOMRIGHT")
        bg:SetColorTexture(0.08, 0.08, 0.09, (not fixed and Style.WindowAlpha()) or Style.FALLBACK_ALPHA)
        frame.__shell = bg
        if not fixed then backs[frame] = { fill = bg } end
    end
    frame.__line = topLine(frame)
    if tabsY then
        local t = rule(frame, "BORDER")
        t:SetPoint("TOPLEFT", Style.CONTENT_EDGE, -(tabsY - 2))
        t:SetPoint("TOPRIGHT", -Style.CONTENT_EDGE, -(tabsY - 2))
        frame.__rule = t
    end
end

-- Shows or hides a frame's own shell (border, shadow, background): off while the frame
-- sits inside a shell that already frames it (the shared gathering shell).
function Style.ShellShown(frame, shown)
    if frame.__shell then frame.__shell:SetShown(shown) end
end

-- Shows or hides a shell's accent line along its top.
function Style.LineShown(frame, shown)
    if frame.__line then frame.__line:SetShown(shown) end
end

-- A small shell for a tab on a window's edge: Daylight UI's, with a border of
-- `borderPx(px)` for the player's border width `px`, redrawn on resize.
function Style.TabShell(frame, borderPx)
    local API = Style.Daylight()
    if API then
        local function skin() track(frame, API.Skin(frame, backOpts({ borderPx = borderPx }))) end
        skin()
        frame:HookScript("OnSizeChanged", skin)
        backs[frame] = { skin = skin }
        return
    end
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.09, Style.WindowAlpha() or Style.FALLBACK_ALPHA)
    backs[frame] = { fill = bg }
end

-- Inner cards, by frame: { bg, edge, lit, round }. The lit top line spans the card and
-- wears the accent at CARD_LIT.alpha, painted as the window's top line is.
Style.cards = setmetatable({}, { __mode = "k" })
Style.CARD_LIT = { height = 1, alpha = 0.7 }
Style.CARD_PLAIN = { 0, 0, 0, 0.35 }

-- Daylight UI's card pieces (Options/Widgets.lua): its Widgets table with Round, and the
-- COLORS card and cardEdge. Nil without them.
function Style.CardKit()
    local core = Style.Daylight() and daylightCore()
    local W = core and core.Widgets
    if type(W) ~= "table" then return nil end
    local C = W.COLORS
    if type(C) ~= "table" or not (C.card and C.cardEdge) then return nil end
    return W, C
end

local function tint(t, c) t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end

-- An inner card inside a window (the step details), in Daylight UI's options-card
-- colours (Widgets.COLORS card and cardEdge) but square, to sit with the square buttons,
-- and softened: the fill at CARD_FILL of its alpha, a 1 px edge, and an accent line along
-- its whole top. It has no window shell, so no shadow, bevel or band. Without Daylight UI
-- it is a plain dark fill.
Style.CARD_FILL = 0.55     -- share of the card colour's alpha the fill keeps
Style.CARD_EDGE = 0.6      -- share of the edge colour's alpha the outline keeps

local function edgeLine(frame, a, b, horizontal)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetPoint(a, frame, a, 0, 0)
    t:SetPoint(b, frame, b, 0, 0)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    return t
end
function Style.Card(frame)
    local look = {}
    local _, C = Style.CardKit()
    if C then
        look.bg = frame:CreateTexture(nil, "BACKGROUND")
        look.bg:SetAllPoints(frame)
        look.bg:SetColorTexture(C.card[1], C.card[2], C.card[3], (C.card[4] or 1) * Style.CARD_FILL)
        look.edges = {
            edgeLine(frame, "TOPLEFT", "TOPRIGHT", true),
            edgeLine(frame, "BOTTOMLEFT", "BOTTOMRIGHT", true),
            edgeLine(frame, "TOPLEFT", "BOTTOMLEFT"),
            edgeLine(frame, "TOPRIGHT", "BOTTOMRIGHT"),
        }
        local e = C.cardEdge
        for _, t in ipairs(look.edges) do t:SetColorTexture(e[1], e[2], e[3], (e[4] or 1) * Style.CARD_EDGE) end
        local lit = frame:CreateTexture(nil, "BORDER", nil, 1)
        lit:SetTexture(WHITE)
        lit:SetHeight(Style.CARD_LIT.height)
        lit:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        lit:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        local function paint() paintTopLine(lit, Style.CARD_LIT.alpha) end
        accents[#accents + 1] = paint
        paint()
        look.lit, look.paintLit = lit, paint
        look.square = true
    else
        look.bg = frame:CreateTexture(nil, "BACKGROUND")
        look.bg:SetAllPoints()
        fill(look.bg, Style.CARD_PLAIN)
    end
    Style.cards[frame] = look
    return look
end

-- An opaque surface for lists that sit over other content.
function Style.Popup(frame)
    local API = Style.Daylight()
    if API then return track(frame, API.Skin(frame, {})) end
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.13, 0.13, 0.15, 1)
end

-- Text ---------------------------------------------------------------------------

-- A font string in the player's font at a size role ("tiny", "small", "body",
-- "head", "title"), coloured by a Style.color role that follows Daylight UI's colours.
-- It follows the text size setting unless `fixed` (the title bar and tab labels,
-- which sit in fixed widths).
function Style.Text(parent, size, color, fixed)
    local API = Style.Daylight()
    local fs
    if API then
        fs = API.Text(parent, SIZES[size] and size or "body")
        -- Daylight UI picks the font by where the string sits; ProfLost's font setting wins.
        local path = Style.FontFile()
        local _, px, flags = fs:GetFont()
        if path and px then fs:SetFont(path, px, flags or "") end
    else
        fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    end
    color = color or Style.color.text
    roles[fs] = color
    if not fixed then
        local _, px = fs:GetFont()
        if px then
            bases[fs] = (tonumber(px) or 0) > 0 and px or SIZES[size] or SIZES.body
            sizeTo(fs)
        end
    end
    fs:SetTextColor(unpack(color))
    fs:SetJustifyH("LEFT")
    return fs
end

-- The "|cffrrggbb" escape for a colour table (Style.color.muted...), so typed-in codes
-- follow Daylight UI's colours.
function Style.Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- The text size setting, as a factor.
Style.TextScale = scale

-- Font strings held at one px size whatever the text size or Daylight UI's font scale.
local pinned = setmetatable({}, { __mode = "k" })

-- Holds `fs` at `px`, or at the size it was pinned to. Daylight UI's own font repaint can
-- reset it, so its header calls this again on each layout.
function Style.Pin(fs, px)
    px = px or pinned[fs]
    if not px then return end
    pinned[fs] = px
    local path, cur, flags = fs:GetFont()
    if path and cur ~= px then fs:SetFont(path, px, flags or "") end
end

-- A header line's font string (Style.HEADER): line 1 or 2, pinned to its size.
function Style.HeaderText(parent, line, color)
    local fs = Style.Text(parent, HEADER["line" .. line], color, true)
    Style.Pin(fs, HEADER["px" .. line])
    fs:SetWordWrap(false)
    return fs
end

-- The text size setting changed: every scalable string takes the new size.
function Style.ApplyScale()
    for fs in pairs(bases) do sizeTo(fs) end
    if CP.Emit then CP:Emit("ProfLost_FONT") end
end

-- The file of the font setting (CP.db.font, a Daylight UI font key), or nil before the
-- saved settings or without Daylight UI. "general" follows the player's Daylight UI font.
function Style.FontFile()
    local API = Style.Daylight()
    if not (API and type(API.FontFile) == "function" and CP.db) then return nil end
    return API.FontFile(CP.db.font or "general")
end

-- The font setting on every ProfLost string, at its current size. Strings made later take
-- the same file (Style.Text), so the measuring gauge and the strings it measures agree.
function Style.ApplyFont()
    local path = Style.FontFile()
    if not path then return end
    for fs in pairs(roles) do
        local _, px, flags = fs:GetFont()
        px = pinned[fs] or px
        if px then fs:SetFont(path, px, flags or "") end
    end
    if CP.Emit then CP:Emit("ProfLost_FONT") end
end

-- Fitting text --------------------------------------------------------------------

-- Player-facing text fits or wraps; it never ends in "...". Short numeric columns
-- (skill ranges, counts, yards) stay on one line, as wide as their widest text in the
-- current font. Names in list rows (Style.OneLine) stay on one line and may end in
-- "...". Look.Check reports any other truncated string, and a wrapped column.

local gauge = CreateFrame("Frame", nil, UIParent)
gauge:Hide()
local gauges = {}   -- size role, or "fixed <role>" -> a hidden string in that role's current font
Style.columns = setmetatable({}, { __mode = "k" })   -- numeric column strings
Style.cut = setmetatable({}, { __mode = "k" })       -- list-row names that may end in "..."

-- The gauge takes the guide window's scale. Glyph widths round to whole pixels at the drawn
-- size, so a string measured at another scale can come out a pixel short and be cut.
local gaugeScale = 1
local function matchScale()
    local f = CP.Panel and CP.Panel.frame
    if not (f and f.GetEffectiveScale) then return end
    local base = tonumber(UIParent:GetEffectiveScale()) or 0
    local want = base > 0 and (tonumber(f:GetEffectiveScale()) or 0) / base or 0
    if want > 0 and math.abs(want - gaugeScale) > 0.001 then
        gaugeScale = want
        gauge:SetScale(want)
    end
end
Style.GaugeScale = function() matchScale() return gaugeScale end

-- `text`'s width in px in size role `size`'s current font and text size. `fixed` measures
-- at the role's own size, as header lines (Style.HeaderText) draw.
function Style.Measure(text, size, fixed)
    if not text or text == "" then return 0 end
    matchScale()
    size = SIZES[size] and size or "body"
    local key = fixed and "fixed " .. size or size
    if not gauges[key] then
        gauges[key] = Style.Text(gauge, size, nil, fixed)
        if fixed then Style.Pin(gauges[key], SIZES[size]) end
    end
    local g = gauges[key]
    if fixed then Style.Pin(g) end
    g:SetText(text)
    local w = g.GetUnboundedStringWidth and g:GetUnboundedStringWidth() or g:GetStringWidth()
    return math.ceil(tonumber(w) or 0)
end

-- The widest of `texts` in size role `size`.
function Style.Widest(texts, size)
    local w = 0
    for _, text in ipairs(texts) do w = math.max(w, Style.Measure(text, size)) end
    return w
end

-- `fs` is a numeric column: one line, never wrapped. Its width comes from Style.Widest.
function Style.Column(fs)
    fs:SetWordWrap(false)
    Style.columns[fs] = true
    return fs
end

-- `fs` is a name in a list row: one line, cut with "..." when too long. The row's pick
-- or the step card shows it whole.
function Style.OneLine(fs)
    fs:SetWordWrap(false)
    Style.cut[fs] = true
    return fs
end

-- `word` broken into pieces no wider than `room`, a letter at a time.
local function breakWord(word, size, room, pieces, measure)
    local cur = ""
    for ch in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if cur ~= "" and measure(cur .. ch, size) > room then
            pieces[#pieces + 1] = cur
            cur = ch
        else
            cur = cur .. ch
        end
    end
    return cur
end

-- `text` split at spaces into lines no wider than `room` in size role `size`. A word
-- wider than `room` alone breaks inside itself. `measure(text, size)` stands in for
-- Style.Measure when given.
function Style.Lines(text, size, room, measure)
    measure = measure or Style.Measure
    local pieces, cur = {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
        local try = cur == "" and word or (cur .. " " .. word)
        if measure(try, size) <= room then
            cur = try
        else
            if cur ~= "" then pieces[#pieces + 1] = cur end
            cur = measure(word, size) > room and breakWord(word, size, room, pieces, measure) or word
        end
    end
    if cur ~= "" then pieces[#pieces + 1] = cur end
    return pieces
end

-- A line's height in size role `size`: the font's size plus leading.
Style.LEADING = 3
function Style.LineHeight(size)
    return math.ceil((SIZES[size] or SIZES.body) * scale()) + Style.LEADING
end

-- Controls -----------------------------------------------------------------------

local keepHover

-- A hover tint on `button`, `inset` px in from its edges. With Daylight UI it is its row
-- hover: Parts.HI's white, eased in and out by Parts.Light, snapped off when the button
-- hides. Without it, the game's highlight layer at Style.color.hover.
-- Later OnEnter and OnLeave scripts run after the light (keepHover).
local function hoverTint(button, inset)
    local Parts = daylightParts("Light")
    local t
    if Parts then
        t = button:CreateTexture(nil, "BACKGROUND", nil, 4)
        t:SetTexture(WHITE)
        local c = type(Parts.HI) == "table" and Parts.HI or Style.color.hover
        t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        t:Hide()
    else
        t = button:CreateTexture(nil, "HIGHLIGHT")
        fill(t, Style.color.hover)
    end
    t:SetPoint("TOPLEFT", inset, -inset)
    t:SetPoint("BOTTOMRIGHT", -inset, inset)
    if not Parts then return t end
    local function light(on, instant) pcall(Parts.Light, t, on, instant) end
    local prior = { OnEnter = button:GetScript("OnEnter"), OnLeave = button:GetScript("OnLeave") }
    button:SetScript("OnEnter", function(self, ...)
        light(true)
        if prior.OnEnter then return prior.OnEnter(self, ...) end
    end)
    button:SetScript("OnLeave", function(self, ...)
        light(false)
        if prior.OnLeave then return prior.OnLeave(self, ...) end
    end)
    button:HookScript("OnHide", function() light(false, true) end)
    keepHover(button)
    return t
end

-- Hover tint for rows and flat buttons.
function Style.Interactive(button)
    button.hoverTex = hoverTint(button, 0)
end

-- The picked row's look. Daylight UI's own pick (Windows/Parts.lua, Parts.PickLine) is a
-- white wash plus the accent at 0.16, which a purple accent hides. This keeps its two
-- layers, strengthens both, and adds an accent hairline above and below. The step list's
-- current-step marker is a bar down the left edge, so the pick never draws one.
Style.PICK = { white = 0.14, wash = 0.22, line = 1 }

Style.pickRows = setmetatable({}, { __mode = "k" })

function Style.PickRow(button, on)
    local P = Style.PICK
    if not button.pickFill then
        button.pickFill = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        button.pickFill:SetAllPoints()
        fill(button.pickFill, { 1, 1, 1, P.white })
        button.pickWash = button:CreateTexture(nil, "BACKGROUND", nil, 2)
        button.pickWash:SetAllPoints()
        button.pickWash:SetTexture(WHITE)
        accents[#accents + 1] = function() paintTopLine(button.pickWash, P.wash) end
        paintTopLine(button.pickWash, P.wash)
        button.pickTop = accentTexture(button, "OVERLAY")
        button.pickTop:SetPoint("TOPLEFT")
        button.pickTop:SetPoint("TOPRIGHT")
        button.pickTop:SetHeight(P.line)
        button.pickBottom = accentTexture(button, "OVERLAY")
        button.pickBottom:SetPoint("BOTTOMLEFT")
        button.pickBottom:SetPoint("BOTTOMRIGHT")
        button.pickBottom:SetHeight(P.line)
        Style.pickRows[button] = true
    end
    on = on and true or false
    button.picked = on
    button.pickFill:SetShown(on)
    button.pickWash:SetShown(on)
    button.pickTop:SetShown(on)
    button.pickBottom:SetShown(on)
end

-- A control's face (a dropdown, a box): Daylight UI's shell, with a hover tint.
function Style.Control(button)
    local API = Style.Daylight()
    if API then API.Skin(button, { noBevel = true }) end
    button.hoverTex = hoverTint(button, 1)
end

-- Buttons ----------------------------------------------------------------------------

-- Every ProfLost button is Daylight UI's own, the one its Talents window's Builds button
-- and the craft strip's Stop use (API.Button; Options/Widgets.lua W.DressButton): a dark
-- face in a warm band, an accent trace that runs round it on hover, a pressed fill and
-- its click sound. Without Daylight UI the same layers are flat and the trace fades in.
Style.BUTTON_H = 22
Style.BUTTON_PAD = 32     -- room around a label, as W.DressButton's FitWidth leaves
Style.BUTTON_OFF = 0.45   -- label alpha while off
Style.BUTTON_FADE = 0.12  -- seconds the plain trace eases over
Style.BUTTON_FACE = { 0.11, 0.11, 0.12 }
Style.BUTTON_DOWN = { 0.07, 0.07, 0.08 }
Style.BUTTON_BAND = { 0.24, 0.22, 0.2 }

-- Daylight UI's Motion.Tween when it is loaded, else nil.
local function motion()
    local addon = _G[DAYLIGHT]
    local M = type(addon) == "table" and addon.Motion
    return type(M) == "table" and type(M.Tween) == "function" and M or nil
end

-- Daylight UI's click sound when it is loaded, else the game's menu click.
local function clickSound()
    local addon = _G[DAYLIGHT]
    local sound = type(addon) == "table" and addon.Sound
    if type(sound) == "table" and type(sound.Play) == "function" then return sound.Play("click") end
    local kit = type(SOUNDKIT) == "table" and SOUNDKIT.IG_MAINMENU_OPTION
    if kit and PlaySound then PlaySound(kit) end
end
Style.Click = clickSound

-- The plain look on button `b`, with the same calls Daylight UI's buttons answer:
-- b.text, b.Hover(on), b.SetActive(on), b.SetOff(off), b.Paint().
local function dressPlain(b)
    local function layer(sub, inset)
        local t = b:CreateTexture(nil, "BACKGROUND", nil, sub)
        t:SetTexture(WHITE)
        t:SetPoint("TOPLEFT", inset, -inset)
        t:SetPoint("BOTTOMRIGHT", -inset, inset)
        return t
    end
    b.outline = layer(-8, 0)
    b.trace = layer(-7, 0)
    b.band = layer(-6, 1)
    b.face = layer(-5, 3)
    if not b.text then
        b.text = Style.Text(b, "body")
        b.text:SetPoint("CENTER")
        b.text:SetJustifyH("CENTER")
    end
    b.glow, b.glowKey = 0, {}

    function b.Paint()
        local band, face = Style.BUTTON_BAND, b.down and not b.off and Style.BUTTON_DOWN or Style.BUTTON_FACE
        local r, g, bl = accentColor()
        b.outline:SetVertexColor(0, 0, 0, 1)
        b.band:SetVertexColor(band[1], band[2], band[3], 1)
        b.face:SetVertexColor(face[1], face[2], face[3], 1)
        b.trace:SetVertexColor(r, g, bl, b.off and 0 or (b.active and 1 or b.glow))
        local t = b.active and Style.color.title or Style.color.text
        b.text:SetTextColor(t[1], t[2], t[3], b.off and Style.BUTTON_OFF or 1)
    end
    accents[#accents + 1] = b.Paint

    local function ease(to)
        local M = motion()
        if M and b:IsVisible() then
            M.Tween(b.glowKey, b.glow, to, Style.BUTTON_FADE, function(v) b.glow = v; b.Paint() end)
        else
            if M then M.Tween(b.glowKey, to, to, 0, function() end) end
            b.glow = to
            b.Paint()
        end
    end
    function b.Hover(on)
        if not on then b.down = false end
        ease(on and 1 or 0)
    end
    function b.SetActive(on)
        b.active = on and true or nil
        b.Paint()
    end
    function b.SetOff(off)
        b.off = off and true or nil
        b:SetEnabled(not b.off)
        b.Paint()
    end
    b:SetScript("OnEnter", function() b.Hover(true) end)
    b:SetScript("OnLeave", function() b.Hover(false) end)
    b:SetScript("OnMouseDown", function() b.down = true; b.Paint() end)
    b:SetScript("OnMouseUp", function() b.down = false; b.Paint() end)
    b:HookScript("OnHide", function()
        b.down, b.glow = false, 0
        b.Paint()
    end)
    b:HookScript("PostClick", clickSound)
    b.Paint()
end

-- The caller's OnEnter and OnLeave run after the button's own hover, which a plain
-- SetScript would drop.
function keepHover(b)
    local base = { OnEnter = b:GetScript("OnEnter"), OnLeave = b:GetScript("OnLeave") }
    local own = {}
    local setScript = b.SetScript
    function b:SetScript(kind, fn)
        if kind == "OnEnter" or kind == "OnLeave" then
            own[kind] = fn
            return
        end
        return setScript(self, kind, fn)
    end
    for _, kind in ipairs({ "OnEnter", "OnLeave" }) do
        setScript(b, kind, function(self, ...)
            if base[kind] then base[kind](self, ...) end
            if own[kind] then return own[kind](self, ...) end
        end)
    end
end

-- The calls every ProfLost button answers, whichever look it wears.
local function finish(b)
    b.label = b.text
    if b.label.SetWordWrap then b.label:SetWordWrap(false) end
    keepHover(b)
    -- On: the trace stays lit, as while a menu is open under the button.
    function b.SetOn(on)
        b.on = on and true or nil
        if type(b.SetActive) == "function" then b.SetActive(b.on) end
    end
    return b
end

-- A button `width` wide and `height` tall (BUTTON_H) with label `b.label` (also `b.text`).
-- b.SetOff(off) dims it and stops its clicks; b.SetOn(on) keeps its trace lit.
function Style.Button(parent, width, height)
    local API = Style.Daylight()
    local h = height or Style.BUTTON_H
    local b
    if API and type(API.Button) == "function" then
        b = API.Button(parent, "", h)
    else
        b = CreateFrame("Button", nil, parent)
        b:SetHeight(h)
        dressPlain(b)
    end
    if width then b:SetWidth(width) end
    return finish(b)
end

-- Dresses an existing button (a secure template ProfLost can't make through the API) in the
-- same look: Daylight UI's W.DressButton when it is loaded, else the plain one.
function Style.Dress(b)
    local addon = _G[DAYLIGHT]
    local W = type(addon) == "table" and addon.Widgets
    if Style.Daylight() and type(W) == "table" and type(W.DressButton) == "function" and pcall(W.DressButton, b, "") then
        return finish(b)
    end
    dressPlain(b)
    return finish(b)
end

-- A window's close X in a `size` px box: Daylight UI's own (API.Close), else a plain
-- "x". `onClick()` runs on click. It has no tooltip.
function Style.Close(parent, onClick, size)
    local API = Style.Daylight()
    if API and type(API.Close) == "function" then
        return API.Close(parent, function() onClick() end, size)
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.label = Style.Text(b, "head", Style.color.muted, true)
    b.label:SetPoint("CENTER")
    b.label:SetText("x")
    b:SetScript("OnClick", function() onClick() end)
    return b
end

-- A bottom-right corner grip that resizes `frame` with its top-left held still: Daylight
-- UI's window grip (Win.Grip) when loaded, else the game's chat-frame grabber. opts:
--   min = { w, h }       the least size
--   start()              a drag begins
--   resized(w, h)        each step of the drag, the size the mouse asks for
--   done(w, h)           the drop, with the frame's size
--   reset()              a right-click
Style.GRIP = { size = 12, inset = 4 }
local GRABBER = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

function Style.Grip(frame, opts)
    local core = daylightCore()
    local Win = core and core.Win
    if Style.Daylight() and type(Win) == "table" and type(Win.Grip) == "function" then
        local ok, grip = pcall(Win.Grip, frame, {
            min = opts.min,
            place = function() opts.done(frame:GetWidth(), frame:GetHeight()) end,
            resized = function(w, h, live) if live then opts.resized(w, h) end end,
            reset = opts.reset,
        })
        if ok and grip then
            -- Win.Grip sets grip.grab once a drag starts.
            grip:HookScript("OnMouseDown", function() if grip.grab then opts.start() end end)
            return grip
        end
    end

    local G = Style.GRIP
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(G.size, G.size)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -G.inset, G.inset)
    grip:SetNormalTexture(GRABBER .. "Up")
    grip:SetHighlightTexture(GRABBER .. "Highlight")
    grip:SetPushedTexture(GRABBER .. "Down")

    -- The cursor in the frame's own units.
    local function cursor()
        local x, y = GetCursorPosition()
        local s = frame:GetEffectiveScale()
        if type(s) ~= "number" or s <= 0 then s = 1 end
        return (tonumber(x) or 0) / s, (tonumber(y) or 0) / s
    end
    local function step()
        local g = grip.grab
        if not g then return end
        local x, y = cursor()
        opts.resized(g.w + x - g.x, g.h + g.y - y)
    end
    local function stop()
        if not grip.grab then return end
        step()
        grip.grab = nil
        grip:SetScript("OnUpdate", nil)
        opts.done(frame:GetWidth(), frame:GetHeight())
    end
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local x, y = cursor()
        grip.grab = { x = x, y = y, w = frame:GetWidth() or 0, h = frame:GetHeight() or 0 }
        opts.start()
        grip:SetScript("OnUpdate", step)
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not grip.grab then return opts.reset() end
        stop()
    end)
    frame:HookScript("OnHide", stop)
    return grip
end

-- Unlearned recipes in the step lists: they can't be picked in the profession window.
Style.UNLEARNED_ALPHA = 0.45

-- A soft tick for a recipe that did show in the profession window.
function Style.Tick()
    local addon = _G[DAYLIGHT]
    local sound = type(addon) == "table" and addon.Sound
    if type(sound) == "table" and type(sound.Play) == "function" then return clickSound() end
    local kit = type(SOUNDKIT) == "table" and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    if kit and PlaySound then PlaySound(kit) end
end

-- Daylight UI's buttons dim themselves (SetOff), matching its own windows. Style.IsOn
-- reads back what was set.
function Style.IsOn(b) return b.cpOn ~= false end

function Style.SetEnabled(b, on)
    b.cpOn = on and true or false
    if type(b.SetOff) == "function" then return b.SetOff(not on) end
    b:SetEnabled(on)
    b.label:SetTextColor(unpack(on and Style.color.text or Style.color.muted))
end

-- Fades and pulses ---------------------------------------------------------------------

-- Daylight UI's three speeds in seconds; API.Speed holds them when it is loaded.
Style.SPEED = { FAST = 0.12, NORMAL = 0.2, SLOW = 0.4 }
Style.FADE_STEP = 1 / 30    -- seconds between steps of the plain fade

-- The plain ease-out without Daylight UI: step(v) from `from` to `to` over `dur` seconds on
-- a timer, one at a time under `key`; a new one replaces the last.
local ownTweens = setmetatable({}, { __mode = "k" })

local function ownTween(key, from, to, dur, step)
    if ownTweens[key] then ownTweens[key]:Cancel() end
    ownTweens[key] = nil
    if dur <= 0 or from == to then return step(to) end
    step(from)
    local t = 0
    ownTweens[key] = C_Timer.NewTicker(Style.FADE_STEP, function(self)
        t = t + Style.FADE_STEP
        local u = math.min(1, t / dur)
        step(from + (to - from) * (1 - (1 - u) ^ 3))
        if u >= 1 then
            self:Cancel()
            ownTweens[key] = nil
        end
    end)
end

-- The plain fade without Daylight UI.
local function ownFade(region, to, dur)
    local from = region:GetAlpha() or 1
    if not region:IsShown() then dur = 0 end
    ownTween(region, from, to, dur, function(v) region:SetAlpha(v) end)
end

-- Eases `region` to `alpha` over `speed` ("FAST", "NORMAL", "SLOW" or seconds) with
-- Daylight UI's API.Fade, else the plain fade.
function Style.Fade(region, alpha, speed)
    local API = Style.Daylight()
    if API and type(API.Fade) == "function" then return API.Fade(region, alpha, speed) end
    local dur = type(speed) == "number" and speed or Style.SPEED[speed] or Style.SPEED.NORMAL
    ownFade(region, alpha, dur)
end

-- Shows `region` from clear to full, as Daylight UI's windows appear.
function Style.FadeIn(region)
    region:SetAlpha(0)
    region:Show()
    Style.Fade(region, 1, "NORMAL")
end

Style.PULSE = 0.9       -- seconds each way of a pulse
Style.PULSE_LOW = 0.45  -- the alpha a pulse dips to

-- False while the player turned Daylight UI's motion off; its fades then jump.
local function motionOn()
    local API = Style.Daylight()
    if API and type(API.MotionOn) == "function" then return API.MotionOn() ~= false end
    local M = motion()
    return not (M and type(M.On) == "function" and M.On() == false)
end

-- A slow breath between full and PULSE_LOW until turned off, made of Style.Fade calls.
-- Off eases back to full. With Daylight UI's motion off it stays at full.
function Style.Pulse(region, on)
    if on and not motionOn() then on = false end
    if not on then
        if not region.profLostPulse then return end
        region.profLostPulse:Cancel()
        region.profLostPulse = nil
        return Style.Fade(region, 1, "FAST")
    end
    if region.profLostPulse then return end
    local low = true
    region.profLostPulse = C_Timer.NewTicker(Style.PULSE, function()
        Style.Fade(region, low and Style.PULSE_LOW or 1, Style.PULSE)
        low = not low
    end)
end

-- Marks `b` as the one thing to press: Daylight UI's main-button look (API.MainButton, 1.8)
-- while it has it, else a pulse. `b.cpUrged` reads back what was set.
function Style.Urge(b, on)
    on = on and true or false
    if b.cpUrged == on then return end
    b.cpUrged = on
    local API = Style.Daylight()
    if API and type(API.MainButton) == "function" then return API.MainButton(b, on) end
    Style.Pulse(b, on)
end

function Style.Pulsing(region) return region.profLostPulse ~= nil end

-- A green tint over a row whose recipe pattern the player holds but has not learned.
-- Every tinted row breathes from one shared ticker, which stops when none is left.
Style.OWNED = { alpha = 0.2 }
Style.ownedRows = setmetatable({}, { __mode = "k" })   -- row -> true while it pulses
Style.ownedDriver = nil

function Style.StopOwnedDriver()
    if Style.ownedDriver then Style.ownedDriver:Cancel() end
    Style.ownedDriver = nil
end

local function ownedStep()
    local low = Style.ownedLow
    Style.ownedLow = not low
    local any = false
    for row in pairs(Style.ownedRows) do
        if row:IsVisible() and row.ownTint then
            any = true
            Style.Fade(row.ownTint, low and Style.PULSE_LOW or 1, Style.PULSE)
        else
            Style.ownedRows[row] = nil
        end
    end
    if not any then Style.StopOwnedDriver() end
end

function Style.OwnedRow(row, on)
    if on and not row.ownTint then
        row.ownTint = row:CreateTexture(nil, "BACKGROUND", nil, 3)
        row.ownTint:SetAllPoints()
        local function paint()
            local c = Style.color.good
            row.ownTint:SetColorTexture(c[1], c[2], c[3], Style.OWNED.alpha)
        end
        accents[#accents + 1] = paint
        paint()
    end
    on = on and true or false
    row.owned = on
    if not row.ownTint then return end
    row.ownTint:SetShown(on)
    row.ownTint:SetAlpha(1)
    if not on then
        Style.ownedRows[row] = nil
        return
    end
    if not motionOn() then return end
    Style.ownedRows[row] = true
    if not Style.ownedDriver then
        Style.ownedLow = true
        Style.ownedDriver = C_Timer.NewTicker(Style.PULSE, ownedStep)
    end
end

-- Icons --------------------------------------------------------------------------------

-- Daylight UI's Widgets table when it has `name`, else nil.
local function widget(name)
    local core = Style.Daylight() and daylightCore()
    local W = core and core.Widgets
    if type(W) == "table" and type(W[name]) == "function" then return W end
end

-- One of Daylight UI's Media icons, tinted (W.Icon), as its ticks and marks are made.
-- Nil without Daylight UI.
local function daylightIcon(parent, file, size, color, layer)
    local W = widget("Icon")
    return W and W.Icon(parent, file, size, color, layer) or nil
end

-- A bare icon button. With Daylight UI it is the one its window headers use
-- (W.IconButton, Win.HeaderIcon): its Media `icon` in the label ink, the accent on
-- hover, a bump on press and its click sound. Our `tip(self)` shows at once in place of
-- its delayed name. Without it: the `own` art at `size`, muted, the accent on hover, the
-- same click sound.
-- spec: icon, own, size, box (the hit box with Daylight UI, else `size`), art (ProfLost's own
-- art drawn in both looks, a path), onClick(self, button), tip(self), name() (a tooltip's
-- title and line: Daylight UI's own, after its rest; the game's at once without it).
-- b.icon.file names the art shown.
function Style.IconButton(parent, spec)
    local W = widget("IconButton")
    if W then
        local b = W.IconButton(parent, spec.icon, spec.name, spec.onClick, spec.box)
        if spec.art then b.icon:SetTexture(spec.art) end
        if spec.tip then b:HookScript("OnEnter", spec.tip) end
        b.icon.file = spec.art or spec.icon
        b.daylight = true
        return b
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(spec.size, spec.size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(spec.art or spec.own)
    b.icon.file = spec.art or spec.own
    function b.Paint(over)
        local c = over and Style.color.accent or Style.color.muted
        b.icon:SetVertexColor(c[1], c[2], c[3])
    end
    b:SetScript("OnEnter", function(self)
        b.Paint(true)
        if spec.tip then spec.tip(self) end
        if spec.name then
            local title, line = spec.name()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(title, 1, 1, 1)
            if line then GameTooltip:AddLine(line, nil, nil, nil, true) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        b.Paint(false)
        GameTooltip_Hide()
    end)
    b:SetScript("OnClick", function(self, button) spec.onClick(self, button) end)
    b:HookScript("PostClick", clickSound)
    b.Paint(false)
    return b
end

-- A text link in `size` text. With Daylight UI it is its own (Widgets.Link): quiet text
-- that turns the accent on hover as an underline grows, and its click sound. Without it:
-- accent text and the same click sound. b.label is the text; b.SetLabel(text) sets it and
-- sizes the link to it. The caller anchors it by one side and sets OnClick.
function Style.Link(parent, size)
    local W = widget("Link")
    if W then
        local ok, b = pcall(W.Link, parent, SIZES[size or "small"])
        if ok and b then
            b.label = b.text
            b.daylight = true
            return b
        end
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(18)
    b.label = Style.Text(b, size or "small", Style.color.accent)
    b.label:SetPoint("LEFT")
    function b.SetLabel(text)
        b.label:SetText(text or "")
        local w = b.label:GetStringWidth()
        b:SetWidth(type(w) == "number" and w > 0 and w or 200)
    end
    b:HookScript("PostClick", clickSound)
    return b
end

-- A done tick: Daylight UI's (ui-check.png through W.Icon, as its options and installer
-- draw theirs) in the good ink, else the game's ready-check mark.
Style.CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
function Style.Check(parent, size)
    local t = daylightIcon(parent, "ui-check.png", size, Style.color.good, "OVERLAY")
    if t then return t end
    t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Style.CHECK)
    t:SetSize(size, size)
    return t
end

-- An expand / collapse mark. With Daylight UI it is its tree-node chevron (ui-chevron.png
-- through W.Icon, in the label ink), pointing down while open and right while closed, as
-- its profession window's Parts rows turn theirs. Without it: a plus or minus from two
-- accent bars. `t:SetOpen(true)` shows it open.
Style.CHEVRON_CLOSED = math.pi / 2

function Style.Toggle(parent, size)
    local t = CreateFrame("Frame", nil, parent)
    size = size or 10
    t:SetSize(size, size)
    local chevron = daylightIcon(t, "ui-chevron.png", size, Style.color.label)
    if chevron then
        chevron:SetPoint("CENTER")
        t.chevron = chevron
        function t:SetOpen(open)
            self.open = open and true or false
            self.angle = open and 0 or Style.CHEVRON_CLOSED
            chevron:SetRotation(self.angle)
        end
        t:SetOpen(false)
        return t
    end
    local bar = math.max(2, math.floor(size / 5 + 0.5))
    local across = accentTexture(t, "ARTWORK")
    across:SetSize(size, bar)
    across:SetPoint("CENTER")
    local down = accentTexture(t, "ARTWORK")
    down:SetSize(bar, size)
    down:SetPoint("CENTER")
    t.across, t.down = across, down
    function t:SetOpen(open)
        self.open = open and true or false
        down:SetShown(not open)
    end
    t:SetOpen(false)
    return t
end

-- A padlock in a `size` px box, through the icon button (Style.IconButton): Daylight UI's
-- ui-lock.png and ui-unlock.png, ours without it. `locked()` says which shows; a click runs
-- `toggle()`. b.icon.file names the art shown; b.Sync() shows the state again.
Style.LOCK_ICONS = {
    daylight = { "ui-lock.png", "ui-unlock.png" },
    own = { CP.MEDIA .. "Lock", CP.MEDIA .. "Unlock" },
}

function Style.LockButton(parent, size, locked, toggle)
    local b
    b = Style.IconButton(parent, { icon = Style.LOCK_ICONS.daylight[1], own = Style.LOCK_ICONS.own[1],
        size = size, box = size, onClick = function() toggle(); b.Sync() end })
    function b.Sync()
        local icons = b.daylight and Style.LOCK_ICONS.daylight or Style.LOCK_ICONS.own
        local file = locked() and icons[1] or icons[2]
        if b.daylight then b.SetIcon(file) else b.icon:SetTexture(file) end
        b.icon.file = file
    end
    -- `locked()` may not exist yet when the button is made, so it shows its state on show.
    b:HookScript("OnShow", b.Sync)
    return b
end

-- The fold button in a `size` px box: the chevron icon button turned down while open and
-- right while closed, as Style.Toggle turns it. Without Daylight UI's icon button it is a
-- plain button holding that mark. b.mark:SetOpen(open) shows the state.
function Style.FoldButton(parent, size, onClick)
    if widget("IconButton") then
        local b = Style.IconButton(parent, { icon = "ui-chevron.png", size = size, box = size, onClick = onClick })
        b.mark = {}
        function b.mark:SetOpen(open)
            self.open = open and true or false
            b.icon:SetRotation(open and 0 or Style.CHEVRON_CLOSED)
        end
        b.mark:SetOpen(false)
        return b
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.mark = Style.Toggle(b, 10)
    b.mark:SetPoint("CENTER")
    b:SetScript("OnClick", function(self, button) onClick(self, button) end)
    b:HookScript("PostClick", clickSound)
    return b
end

-- A small map-pin button for "set a waypoint". `onClick(self)` runs on click. It has no
-- tooltip. With Daylight UI it is its icon button with its map pin
-- (ui-data-location.png, its InfoPanel's location icon); else the game's map pin.
local PIN_ATLAS = "Waypoint-MapPin-Untracked"
local PIN_FALLBACK = "Interface\\Icons\\INV_Misc_Map_01"
Style.PIN = 16

function Style.PinButton(parent, onClick)
    if widget("IconButton") then
        local b = Style.IconButton(parent, { icon = "ui-data-location.png", onClick = onClick })
        b:SetSize(Style.PIN, Style.PIN)
        return b
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    if C_Texture.GetAtlasInfo(PIN_ATLAS) then t:SetAtlas(PIN_ATLAS) else t:SetTexture(PIN_FALLBACK) end
    b:SetHighlightTexture(PIN_FALLBACK, "ADD")
    b:GetHighlightTexture():SetAlpha(0.25)
    b:SetScript("OnClick", onClick)
    b:HookScript("PostClick", clickSound)
    return b
end

-- A one-line number box in the player's font, on a control face.
function Style.NumberBox(parent, width)
    -- Daylight UI's own text box, numeric; its Enter clears focus, callers add theirs.
    local API = Style.Daylight()
    if API and API.Input then
        local box = API.Input(parent, { numeric = true })
        if box and box.SetText then
            box:SetSize(width, 22)
            if box.SetMaxLetters then box:SetMaxLetters(3) end
            if box.SetJustifyH then box:SetJustifyH("CENTER") end
            return box
        end
    end
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, 22)
    e:SetAutoFocus(false)
    e:SetNumeric(true)
    e:SetMaxLetters(3)
    e:SetJustifyH("CENTER")
    e:SetFontObject(GameFontHighlight)
    local API = Style.Daylight()
    if API and API.Font then e:SetFont(API.Font(), SIZES.body, "") end
    e:SetTextColor(unpack(Style.color.text))
    e:SetTextInsets(4, 4, 0, 0)
    Style.Control(e)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

-- Lines and bars ------------------------------------------------------------------

-- The line under a list row.
function Style.Rule(row)
    local t = rule(row, "BORDER")
    t:SetPoint("BOTTOMLEFT")
    t:SetPoint("BOTTOMRIGHT")
    return t
end

function Style.Divider(parent)
    return rule(parent, "ARTWORK")
end

-- A progress bar: Daylight UI's, with its gradient fill.
function Style.Bar(parent, height)
    local API = Style.Daylight()
    local bar
    if API then
        bar = API.Bar(parent)
    else
        bar = CreateFrame("StatusBar", nil, parent)
        bar:SetStatusBarTexture(WHITE)
        bar:GetStatusBarTexture():SetVertexColor(accentColor())
    end
    bar:SetHeight(height or 8)
    return bar
end

-- The craft strip's progress bar. With Daylight UI it is its own craft bar: the pill bar
-- (Widgets.Bar) in the accent (Widgets.BarAccent), repainted when the accent changes.
-- Without it: a 4px bar, a faint track, and a fill from a dark to a full accent.
Style.ACCENT_BAR_H = 4
Style.ACCENT_BAR_TRACK = { 1, 1, 1, 0.07 }
Style.ACCENT_BAR_DIM = 0.55
local ROUND_SLICE = 10

local function pill(bar, layer)
    local t = bar:CreateTexture(nil, layer)
    if Style.Daylight() then
        t:SetTexture(Style.Media("ui-round.png"))
        if t.SetTextureSliceMargins then
            t:SetTextureSliceMargins(ROUND_SLICE, ROUND_SLICE, ROUND_SLICE, ROUND_SLICE)
            if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
                t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
            end
        end
    else
        t:SetTexture(WHITE)
    end
    return t
end

function Style.AccentBar(parent, height)
    local W = widget("Bar")
    if W and type(W.BarAccent) == "function" then
        local bar = W.Bar(parent, height)
        local function paint() pcall(W.BarAccent, bar) end
        accents[#accents + 1] = paint
        paint()
        return bar
    end
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height or Style.ACCENT_BAR_H)
    bar:SetStatusBarTexture(WHITE)
    bar:GetStatusBarTexture():SetAlpha(0)
    bar.track = pill(bar, "BACKGROUND")
    bar.track:SetAllPoints()
    local c = Style.ACCENT_BAR_TRACK
    bar.track:SetVertexColor(c[1], c[2], c[3], c[4])
    bar.fill = pill(bar, "ARTWORK")
    bar.fill:SetAllPoints(bar:GetStatusBarTexture())
    local function paint()
        local r, g, b = accentColor()
        local k = Style.ACCENT_BAR_DIM
        if bar.fill.SetGradient and CreateColor then
            bar.fill:SetVertexColor(1, 1, 1, 1)
            bar.fill:SetGradient("HORIZONTAL", CreateColor(r * k, g * k, b * k, 1), CreateColor(r, g, b, 1))
        else
            bar.fill:SetVertexColor(r, g, b, 1)
        end
    end
    accents[#accents + 1] = paint
    paint()
    return bar
end

-- A text tab's look as Daylight UI's own tabs (spellbook pages, shop, talent sets):
-- Widgets.TabLook gives tan text at rest, light on hover, the accent when picked, and an
-- underline that grows from the middle. Returns its state table (s.Pick(on, animate),
-- s.Paint(over)), or nil without Daylight UI.
-- The look owns the label's colour: Style.Repaint leaves it alone and repaints the look
-- instead, so a picked tab keeps the accent from the first paint, not only after a hover.
function Style.TabLook(b, text)
    local core = Style.Daylight() and daylightCore()
    local W = core and core.Widgets
    if not (W and type(W.TabLook) == "function") then return nil end
    local s = {}
    W.TabLook(b, s, text, {})
    inked[text] = true
    b:HookScript("OnEnter", function() s.Paint(true) end)
    b:HookScript("OnLeave", function() s.Paint(false) end)
    b:HookScript("OnShow", function() s.Paint(b:IsMouseOver() == true) end)
    Style.OnRepaint(function() s.Paint(b:IsMouseOver() == true) end)
    return s
end

-- A click target laid over font string `fs`, so the text itself is the control: Daylight UI's
-- tab ink on it (brighter on hover, Style.TabLook), `onClick` on a click, `tip(self)` on hover.
-- Hidden until shown.
function Style.TextSwitch(parent, fs, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", fs, "TOPLEFT")
    b:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT")
    b.text = fs
    b:SetScript("OnClick", onClick)
    if tip then
        b:SetScript("OnEnter", tip)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
    Style.TabLook(b, fs)
    b:Hide()
    return b
end

-- The picked tab's underline, in the player's accent.
function Style.Mark(tab, width, height)
    local m = CreateFrame("Frame", nil, tab)
    m:SetPoint("BOTTOMLEFT", 8, 0)
    m:SetPoint("BOTTOMRIGHT", -8, 0)
    m:SetHeight(height or 2)
    local t = accentTexture(m)
    t:SetAllPoints()
    return m
end

-- Scroll bars --------------------------------------------------------------------

-- Every ProfLost list scrolls with Daylight UI's own bar when it is loaded: Widgets.Scroll
-- (Options/Widgets.lua), the bar its options panel, profession window and spellbook use.
-- It is a 4 px pill on a faint track beside the list, shown while the list overflows,
-- lit on hover or scroll, and it glides on the wheel. The game's bar stays underneath
-- as the fallback and shows only without Daylight UI.
--
-- Each entry of Style.scrolls:
--   name, list        what a look problem calls it, and the frame that scrolls
--   owner, parent, x  the frame Daylight UI's bar runs beside, its parent, its offset
--   plain             the game's bar (MinimalScrollBar or a ScrollFrame template's)
--   read, write       at, max, view and a jump, for lists that aren't ScrollFrames
--   wheel, onWheel    the frame taking the wheel, and its handler without Daylight UI
--   restore           shows the game's bar again when Daylight UI leaves
--   dui, kit, active  Daylight UI's bar, the Widgets table that made it, whether it's on
Style.scrolls = {}
Style.SCROLL_GAP = 4   -- px between a list and the game's bar

-- Daylight UI's Widgets table when it has Scroll and SCROLL, else nil.
function Style.ScrollKit()
    local W = widget("Scroll")
    if W and type(W.SCROLL) == "table" then return W end
end

local function adopt(e, W)
    if not W then
        e.active = false
        if e.dui then e.dui:Hide() end
        if e.plain then e.restore() end
        return
    end
    if not e.dui or e.kit ~= W then
        if e.dui then e.dui:Hide() end
        local x = e.x
        if type(x) == "function" then x = x(W) end
        e.dui = W.Scroll(e.owner, { parent = e.parent, x = x, step = e.step, wheel = false,
                                    read = e.read, write = e.write })
        e.kit = W
    end
    e.active = true
    if e.plain then e.plain:Hide() end
    e.dui:SetShown(e.list:IsShown())
    e.dui.Update()
end

-- Daylight UI arrived or left: every bar follows. `W` false drops its bars.
function Style.AdoptScrolls(W)
    if W == nil then W = Style.ScrollKit() end
    for _, e in ipairs(Style.scrolls) do adopt(e, W or nil) end
end

local function register(e)
    e.restore = e.restore or function() e.plain:Show() end
    if e.plain then
        e.plain:HookScript("OnShow", function(self) if e.active then self:Hide() end end)
    end

    -- Daylight UI's bar hangs beside the list, not in it, so it shows and hides with it.
    e.list:HookScript("OnShow", function()
        if e.active then
            e.dui:Show()
            e.dui.Update()
        end
    end)
    e.list:HookScript("OnHide", function() if e.dui then e.dui:Hide() end end)
    local own = e.onWheel or e.wheel:GetScript("OnMouseWheel")
    e.wheel:EnableMouseWheel(true)
    e.wheel:SetScript("OnMouseWheel", function(self, delta)
        if e.active then return e.dui.Wheel(delta) end
        if own then own(self, delta) end
    end)
    Style.scrolls[#Style.scrolls + 1] = e
    adopt(e, Style.ScrollKit())
    return e
end

-- The px a list gives up at its right for the bar beside it.
function Style.ScrollRoom(e)
    local W = e.active and Style.ScrollKit()
    if W then return W.SCROLL.width + (W.SCROLL.gap or 0) end
    return (e.plain and e.plain:GetWidth() or 0) + Style.SCROLL_GAP
end

local function num(f, method)
    local fn = f[method]
    local v = type(fn) == "function" and fn(f) or nil
    return type(v) == "number" and v or 0
end

-- A ScrollBox list (WowScrollBoxList) set up with `view`, its bar beside it in `parent`.
-- Returns the entry; entry.plain is the game's bar.
function Style.ListScroll(name, box, view, parent)
    local plain = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    plain:SetPoint("TOPLEFT", box, "TOPRIGHT", Style.SCROLL_GAP, 0)
    plain:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", Style.SCROLL_GAP, 0)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, plain, view)
    return register({
        name = name, list = box, owner = box, parent = parent, plain = plain, wheel = box,
        read = function()
            return num(box, "GetDerivedScrollOffset"), num(box, "GetDerivedScrollRange"), num(box, "GetVisibleExtent")
        end,
        write = function(v) if type(box.ScrollToOffset) == "function" then box:ScrollToOffset(v, true) end end,
    })
end

-- A ScrollFrame made from UIPanelScrollFrameTemplate. Daylight UI's bar reads the frame
-- itself; the template's bar is the fallback.
function Style.FrameScroll(name, scroll, parent)
    return register({ name = name, list = scroll, owner = scroll, parent = parent, plain = scroll.ScrollBar,
                      wheel = scroll })
end

-- A list that pages its own rows (the gathering list), counted in rows. spec: name, list,
-- plain (the game's bar, placed and driven by the caller), read, write, step, onWheel,
-- restore. Daylight UI's bar sits along the right edge of the game's.
function Style.PagedScroll(spec)
    spec.owner, spec.parent, spec.wheel = spec.plain, spec.list, spec.list
    spec.x = function(W) return -W.SCROLL.width end
    return register(spec)
end
