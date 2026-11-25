local _, CP = ...
if CP.stopped then return end

-- The rules every shown ProfLost window keeps, checked against the live frames. Hidden
-- `/proflost check look` prints each broken rule, or "look ok". The headless suite runs the
-- same check in every state it reaches (tests/headless/visual_test.lua).
--
-- Each shown window (the guide window, the detached Gathering window):
--   * stands inside the screen with a real size;
--   * has exactly one shown shell covering it (its own or the shared gathering shell) and
--     exactly one top accent line along it;
--   * shows at full alpha outside a fade;
--   * holds no shown frame without a size.
-- Every Daylight skin on a shown window sits under the window's content, its corner caps
-- over it. The guide's title bar and tab row keep their controls apart and inside it. Its
-- anchor's top is its top; the detached panel's anchor is its rect. Attached, the
-- Gathering window and the shared shell are the guide window's height. An inner card (the
-- step details) wears no window shell.
-- Rules (the tab row's, the seam by the Gathering window) stay inside the window's inner
-- rect, Style.CONTENT_EDGE in from each side. The guide's title bar and the gathering
-- panel's header keep Style.HEADER's two-line layout: its left and right padding, its top
-- padding above line 1 and bottom padding under line 2, and the logo and controls centred
-- on the two lines. Side by side, the gathering header's lines are level with the title
-- bar's and both end at the same height. Paddings and insets are in each window's own
-- units, so they hold at any UI scale or window scale.
-- With Daylight UI loaded, every shown list scrolls with Daylight UI's own bar
-- (Widgets.Scroll) beside it, and the game's bar stays hidden.
-- Text fits or wraps: no shown font string is truncated, save list-row names
-- (Style.OneLine), and no numeric column wraps.

local Look = CP.Look
local S, P, W, GP = CP.Style, CP.Panel, CP.Window, CP.GatherPanel
local panel = P.frame
local ask = Look.Ask

Look.SLACK = 1           -- px a rect may miss by
Look.FULL_ALPHA = 0.99   -- a shown window's least effective alpha outside a fade
Look.LINE_Y = S.TOP_LINE.y
Look.LINE_INSET = S.TOP_LINE.inset
Look.WALK_DEPTH = 8      -- frames under a window walked this deep for sizes
Look.INNER = S.CONTENT_EDGE

-- The client's textures and font strings have no GetEffectiveScale or GetEffectiveAlpha.
-- A region's rect is in its parent's units, and its alpha multiplies into its parent's.

-- `f`'s effective scale, or its parent's for a region.
local function scaleOf(f)
    local k = ask(f, "GetEffectiveScale")
    if type(k) ~= "number" then
        local p = ask(f, "GetParent")
        k = p and ask(p, "GetEffectiveScale")
    end
    return type(k) == "number" and k > 0 and k or 1
end
Look.Scale = scaleOf

-- `f`'s effective alpha; 0 when it can't be read.
local function alphaOf(f)
    local a = ask(f, "GetEffectiveAlpha")
    if type(a) == "number" then return a end
    local own, p = ask(f, "GetAlpha"), ask(f, "GetParent")
    local up = p and ask(p, "GetEffectiveAlpha")
    if type(own) == "number" and type(up) == "number" then return own * up end
    return 0
end

-- A region's rect in screen pixels: left, bottom, right, top; nil when it has none.
local function rect(f)
    if type(f) ~= "table" then return nil end
    local l, b, w, h = ask(f, "GetRect")
    if type(l) ~= "number" or type(b) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return nil end
    local k = scaleOf(f)
    return { l * k, b * k, (l + w) * k, (b + h) * k }
end
Look.Rect = rect

local function fmt(r)
    if not r then return "no rect" end
    return ("%d,%d %dx%d"):format(math.floor(r[1] + 0.5), math.floor(r[2] + 0.5),
        math.floor(r[3] - r[1] + 0.5), math.floor(r[4] - r[2] + 0.5))
end

local function near(a, b) return math.abs(a - b) <= Look.SLACK end

-- True when rect `a` holds rect `b`, within SLACK.
local function covers(a, b)
    local k = Look.SLACK
    return a[1] <= b[1] + k and a[2] <= b[2] + k and a[3] >= b[3] - k and a[4] >= b[4] - k
end

-- A frame's name in a problem line.
function Look.Label(f)
    return ask(f, "GetDebugName") or tostring(f)
end

local function shows(f)
    return type(f) == "table" and ask(f, "IsVisible") == true and alphaOf(f) > 0.01
end

-- The screen in pixels.
local function screen()
    local w, h = ask(UIParent, "GetWidth"), ask(UIParent, "GetHeight")
    local k = ask(UIParent, "GetEffectiveScale") or 1
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
    return { 0, 0, w * k, h * k }
end

-- The shown windows, each with the shells and lines that may frame it, the frame whose
-- children are its content, and its anchor.
function Look.Windows()
    local out = {}
    if panel:IsVisible() then
        local shells = { own = panel.__shell, shared = GP.shell.__shell }
        out[#out + 1] = { name = "guide window", frame = panel, body = P.body, shells = shells,
                          lines = { own = panel.__line, shared = GP.shell.__line } }
    end
    if not GP.Attached() and GP.sheet:IsVisible() then
        out[#out + 1] = { name = "Gathering window", frame = GP.sheet, body = GP.body,
                          shells = { own = GP.sheet.__shell }, lines = { own = GP.sheet.__line } }
    end
    return out
end

-- True while Daylight UI's fade engine eases the guide window or holds it below full.
local function fading(win)
    if win.frame ~= panel then return false end
    local now, goal = Look.FadeState()
    return now ~= nil and (math.abs(now - (goal or now)) > 0.01 or now < Look.FULL_ALPHA)
end

local function sorted(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- One shell covers the window, one line runs along its top.
local function checkShell(win, r, add)
    local on, cover = {}, nil
    for _, key in ipairs(sorted(win.shells)) do
        local s = win.shells[key]
        if shows(s) then
            on[#on + 1] = key
            local sr = rect(s)
            if sr and covers(sr, r) then cover = sr end
        end
    end
    if #on ~= 1 then
        add("%s: %d shells show (%s), not one", win.name, #on, table.concat(on, ", "))
    elseif not cover then
        add("%s: its %s shell doesn't cover it (shell %s, window %s)", win.name, on[1],
            fmt(rect(win.shells[on[1]])), fmt(r))
    end
    local lines = {}
    for _, key in ipairs(sorted(win.lines)) do
        if shows(win.lines[key]) then lines[#lines + 1] = key end
    end
    if #lines ~= 1 then
        add("%s: %d top accent lines show (%s), not one", win.name, #lines, table.concat(lines, ", "))
        return cover
    end
    local line = win.lines[lines[1]]
    local lr = rect(line)
    local edge = cover or r
    local k = scaleOf(line)
    if not lr then
        add("%s: its top accent line has no rect", win.name)
    elseif not (near(lr[4], edge[4] - Look.LINE_Y * k) and near(lr[1], edge[1] + Look.LINE_INSET * k)
            and near(lr[3], edge[3] - Look.LINE_INSET * k)) then
        add("%s: its top accent line (%s) doesn't run along its top (%s)", win.name, fmt(lr), fmt(edge))
    end
    return cover
end

-- Daylight skins: under the window's content, their caps over it.
local function checkSkins(win, add)
    local content = ask(win.body, "GetFrameLevel")
    if type(content) ~= "number" then return end
    for _, key in ipairs(sorted(win.shells)) do
        local s = win.shells[key]
        if shows(s) and ask(s, "GetObjectType") ~= "Texture" then
            local level = ask(s, "GetFrameLevel")
            if type(level) == "number" and level >= content then
                add("%s: its %s skin is at level %d, not under its content at %d", win.name, key, level, content)
            end
            local over = s.over and ask(s.over, "GetFrameLevel")
            if type(over) == "number" and over <= content then
                add("%s: its %s skin's corner caps are at level %d, not over its content at %d", win.name, key, over, content)
            end
        end
    end
end

-- The game's scroll box template (ScrollBoxBaseTemplate) makes a DragDelegate child with no
-- anchors and no size. It only holds the drag-and-drop pools, so it shows with no rect.
local function dragDelegate(parent, c)
    return type(parent.GetDerivedScrollOffset) == "function" and parent.DragDelegate == c
end

-- Shown frames under `f` without a size.
local function checkSizes(win, add)
    local function walk(f, depth, path)
        for i, c in ipairs({ ask(f, "GetChildren") }) do
            if shows(c) and not dragDelegate(f, c) then
                local cr = rect(c)
                local name = Look.Label(c) or (path .. "/" .. i)
                if not cr then
                    add("%s: %s shows with no rect", win.name, name)
                elseif cr[3] - cr[1] < 0.5 or cr[4] - cr[2] < 0.5 then
                    add("%s: %s shows at zero size (%s)", win.name, name, fmt(cr))
                end
                if depth < Look.WALK_DEPTH then walk(c, depth + 1, path .. "/" .. i) end
            end
        end
    end
    walk(win.frame, 1, win.name)
end

-- Controls on one row: none overlaps another and all sit inside the window.
local function checkRow(label, items, r, add)
    local list = {}
    for _, it in ipairs(items) do
        if shows(it[2]) then
            local ir = rect(it[2])
            if ir then list[#list + 1] = { it[1], ir } end
        end
    end
    table.sort(list, function(a, b) return a[2][1] < b[2][1] end)
    for i, it in ipairs(list) do
        if it[2][1] < r[1] - Look.SLACK or it[2][3] > r[3] + Look.SLACK then
            add("%s: %s (%s) runs past the window (%s)", label, it[1], fmt(it[2]), fmt(r))
        end
        local nxt = list[i + 1]
        if nxt and nxt[2][1] < it[2][3] - 0.5 then
            add("%s: %s and %s overlap", label, it[1], nxt[1])
        end
    end
end

local function titleItems()
    local names = { [W.closeButton] = "close", [P.bugButton] = "bug", [W.foldButton] = "fold", [W.lockButton] = "lock" }
    local out = { { "logo", P.logo }, { "title", P.title } }
    for _, t in ipairs(P.titleButtons) do out[#out + 1] = { names[t.button] or "guest", t.button } end
    return out
end

local function rowItems()
    local out = {}
    for _, k in ipairs(P.order) do out[#out + 1] = { k .. " tab", P.tabs[k].button } end
    out[#out + 1] = { "View", W.switchButton }
    out[#out + 1] = { "dropdown", W.pickButton }
    return out
end

-- `r` shrunk by `px` on every side.
local function inset(r, px) return { r[1] + px, r[2] + px, r[3] - px, r[4] - px } end

-- The rules a window shows, each with the rect whose inner part must hold it and that
-- rect's frame.
function Look.Rules(win, r, cover)
    local out = {}
    if win.frame == panel then
        out[#out + 1] = { "tab row rule", panel.__rule, r, panel }
        if GP.Attached() and cover then out[#out + 1] = { "gathering seam", GP.seam, cover, GP.shell } end
    end
    return out
end

local function checkRules(win, r, cover, add)
    for _, rule in ipairs(Look.Rules(win, r, cover)) do
        local rr = shows(rule[2]) and rect(rule[2])
        if rr then
            local inner = inset(rule[3], Look.INNER * scaleOf(rule[4]))
            if not covers(inner, rr) then
                add("%s: its %s (%s) runs outside its inner rect (%s)", win.name, rule[1], fmt(rr), fmt(inner))
            end
        end
    end
end

-- A header's padding from `r`, in the window's own units at effective scale `k`: its first
-- item's left edge, its last control's right edge, its controls' and its logo's middles
-- (`mid`, `logo`), the space above line 1 (`top`) and under line 2 to the header's end
-- `ends` units down (`bottom`). `line1` and `line2` are those lines' screen rects, and
-- `ends` the header's end in screen pixels. Nil parts aren't shown.
local function pads(r, k, first, controls, line1, line2, ends, logo)
    local out = {}
    local fr = shows(first) and rect(first)
    if fr then out.left = (fr[1] - r[1]) / k end
    local right
    for _, c in ipairs(controls) do
        local cr = shows(c) and rect(c)
        if cr and (not right or cr[3] > right[3]) then right = cr end
    end
    if right then
        out.right = (r[3] - right[3]) / k
        out.mid = (r[4] - (right[2] + right[4]) / 2) / k
    end
    local lr = logo and shows(logo) and rect(logo)
    if lr then out.logo = (r[4] - (lr[2] + lr[4]) / 2) / k end
    out.line1 = shows(line1) and rect(line1) or nil
    out.line2 = shows(line2) and rect(line2) or nil
    if out.line1 then out.top = (r[4] - out.line1[4]) / k end
    if out.line2 and ends then out.bottom = (out.line2[2] - (r[4] - ends * k)) / k end
    out.ends = ends and r[4] - ends * k
    return out
end

-- The guide's title bar padding, or the Gathering window's header padding; nil while it
-- doesn't show.
function Look.HeaderPads(which)
    if which == "guide" then
        local r = shows(panel) and rect(panel)
        if not r then return nil end
        local controls = {}
        for _, t in ipairs(P.titleButtons) do controls[#controls + 1] = t.button end
        return pads(r, scaleOf(panel), P.logo, controls, P.title, P.version, P.TITLE_H, P.logo)
    end
    local L = CP.GatherList
    local r = shows(GP.sheet) and rect(GP.sheet)
    if not r then return nil end
    local k = scaleOf(GP.sheet)
    -- The header ends where the rows start.
    local lr = rect(L.frame)
    local ends = lr and (r[4] - lr[4]) / k + L.HeadHeight()
    return pads(r, k, L.head.title, { L.head.route, L.head.filter, GP.closeButton }, L.head.title, L.head.status, ends)
end

local function checkHeader(name, which, add)
    local got = Look.HeaderPads(which)
    if not got then return end
    local H = S.HEADER
    for _, side in ipairs({ "left", "right", "mid", "top", "bottom" }) do
        if got[side] and not near(got[side], H[side]) then
            add("%s: its header's %s padding is %.1f, not %d", name, side, got[side], H[side])
        end
    end
    if got.logo and not near(got.logo, H.mid) then
        add("%s: its logo centres %.1f px down, not on the two lines at %d", name, got.logo, H.mid)
    end
    return got
end

-- Side by side, the gathering header's lines are level with the title bar's, and both end
-- at the same height.
local function checkLevel(guide, gather, add)
    if not (guide and gather) then return end
    for _, k in ipairs({ "line1", "line2" }) do
        local a, b = guide[k], gather[k]
        if a and b and not (near(a[4], b[4]) and near(a[2], b[2])) then
            add("Gathering window: its %s runs %.1f-%.1f, the title bar's %.1f-%.1f", k == "line1" and "line 1" or "line 2",
                b[4], b[2], a[4], a[2])
        end
    end
    if guide.ends and gather.ends and not near(guide.ends, gather.ends) then
        add("Gathering window: its header ends at %.1f, the title bar at %.1f", gather.ends, guide.ends)
    end
end

-- Shown text fits or wraps: no font string under a window is truncated ("..."), save
-- list-row names (Style.OneLine), and no
-- numeric column (Style.Column, or text that reads as a number, count, range, price or
-- distance) takes more than one line.
Look.NUMERIC = "^[~%d][%d%s~%-/%.,%%%+kydgsc]*$"

local function numeric(fs, text)
    if S.columns[fs] then return true end
    local plainText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return plainText:match(Look.NUMERIC) ~= nil
end

local function checkTexts(win, add)
    local function look(fs)
        if ask(fs, "GetObjectType") ~= "FontString" or not shows(fs) then return end
        local text = ask(fs, "GetText")
        if type(text) ~= "string" or text == "" then return end
        if ask(fs, "IsTruncated") == true and not S.cut[fs] then
            add("%s: %s is truncated (%q)", win.name, Look.Label(fs), text)
        end
        local lines = ask(fs, "GetNumLines")
        if numeric(fs, text) and type(lines) == "number" and lines > 1 then
            add("%s: the column %s wraps onto %d lines (%q)", win.name, Look.Label(fs), lines, text)
        end
    end
    local function walk(f, depth)
        for _, r in ipairs({ ask(f, "GetRegions") }) do look(r) end
        for _, c in ipairs({ ask(f, "GetChildren") }) do
            if shows(c) and depth < Look.WALK_DEPTH then walk(c, depth + 1) end
        end
    end
    walk(win.frame, 1)
end

-- Shown inner cards (Style.Card) wear no window shell, so no shadow or bevel.
local function checkCards(add)
    local list = {}
    for frame in pairs(S.cards) do
        if shows(frame) then list[#list + 1] = { tostring(Look.Label(frame) or "card"), frame } end
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    for _, c in ipairs(list) do
        if S.skins[c[2]] or c[2].__shell then
            add("%s: an inner card wears a window shell (shadow, bevel)", c[1])
        end
    end
end

-- Shown lists (Style.scrolls) scroll with the bar the loaded Widgets.Scroll made, sized
-- as its SCROLL says and running beside the list, and the game's bar stays hidden.
local function checkScrolls(add)
    local kit = S.ScrollKit()
    if not kit then return end
    for _, e in ipairs(S.scrolls) do
        if shows(e.list) then
            if not (e.active and e.dui and e.kit == kit) then
                add("%s: its scroll bar isn't Daylight UI's (Widgets.Scroll)", e.name)
            end
            if e.plain and shows(e.plain) then
                add("%s: the game's scroll bar shows", e.name)
            end
            local br, lr = e.dui and shows(e.dui) and rect(e.dui), rect(e.list)
            if br and lr then
                local k = ask(e.dui, "GetEffectiveScale") or 1
                if not near(br[3] - br[1], kit.SCROLL.width * k) then
                    add("%s: its scroll bar is %s, not Daylight UI's %d px", e.name, fmt(br), kit.SCROLL.width)
                end
                if br[1] < lr[1] - Look.SLACK or br[2] < lr[2] - Look.SLACK or br[4] > lr[4] + Look.SLACK then
                    add("%s: its scroll bar (%s) doesn't run beside it (%s)", e.name, fmt(br), fmt(lr))
                end
            end
        end
    end
end

-- A shown picked row has a visible pick of its own (white fill, accent wash, hairlines),
-- and none of those layers is the current-step marker's bar.
local function checkPicks(add)
    for btn in pairs(S.pickRows) do
        local row = tostring(btn.row and btn.row.key or "?")
        if btn.picked and shows(btn) then
            for _, t in ipairs({ btn.pickFill, btn.pickWash, btn.pickTop, btn.pickBottom }) do
                if t == btn.mark then add("row %s: its pick is the current-step marker", row) end
                if not t:IsShown() then
                    add("row %s: it is picked but its highlight is hidden", row)
                    break
                end
            end
            if S.PICK.white < 0.1 then
                add("the picked row's neutral fill (%.2f) is below the contrast floor", S.PICK.white)
            end
        elseif not btn.picked and btn.pickFill and btn.pickFill:IsShown() then
            add("row %s: an unpicked row still draws the pick", row)
        end
        if shows(btn) and btn.owned ~= nil and btn.ownTint and btn.ownTint:IsShown() ~= btn.owned then
            add("row %s: its owned-pattern tint is %s but the row is %s", row,
                btn.ownTint:IsShown() and "on" or "off", btn.owned and "owned" or "not owned")
        end
    end
end

-- Every broken rule as a line; empty when the look is right.
function Look.Check()
    local out = {}
    local function add(f, ...) out[#out + 1] = f:format(...) end
    local scr = screen()
    for _, win in ipairs(Look.Windows()) do
        local r = rect(win.frame)
        if not r then
            add("%s: shows with no rect", win.name)
        elseif r[3] - r[1] < 0.5 or r[4] - r[2] < 0.5 then
            add("%s: shows at zero size (%s)", win.name, fmt(r))
        else
            if scr and not covers(scr, r) then add("%s: runs off the screen (%s)", win.name, fmt(r)) end
            local cover = checkShell(win, r, add)
            checkRules(win, r, cover, add)
            if win.frame == panel then
                local guide = checkHeader(win.name, "guide", add)
                if GP.Attached() and GP.Showing() and GP.p == 1 then
                    checkLevel(guide, checkHeader("Gathering window", "gather", add), add)
                end
                checkRow("title bar", titleItems(), r, add)
                checkRow("tab row", rowItems(), r, add)
                local ar = rect(W.anchor)
                if not (ar and near(ar[4], r[4])) then
                    add("guide window: its anchor's top (%s) isn't its top (%s)", fmt(ar), fmt(r))
                end
                if GP.Attached() and shows(GP.shell) then
                    local sr = rect(GP.shell)
                    if sr and not near(sr[4] - sr[2], r[4] - r[2]) then
                        add("gathering shell: %d tall, not the guide window's %d", math.floor(sr[4] - sr[2] + 0.5),
                            math.floor(r[4] - r[2] + 0.5))
                    end
                    local cr = shows(GP.sheet) and rect(GP.clip)
                    if cr and cr[3] - cr[1] > 1 then
                        local hr = rect(GP.sheet)
                        if hr and not near(hr[4] - hr[2], r[4] - r[2]) then
                            add("Gathering window: %d tall, not the guide window's %d", math.floor(hr[4] - hr[2] + 0.5),
                                math.floor(r[4] - r[2] + 0.5))
                        end
                        if cover and not covers(cover, cr) then
                            add("Gathering window: the shared shell (%s) doesn't cover it (%s)", fmt(cover), fmt(cr))
                        end
                    end
                end
            else
                checkHeader(win.name, "gather", add)
                local ar = rect(GP.anchor)
                if not (ar and near(ar[1], r[1]) and near(ar[2], r[2]) and near(ar[3], r[3]) and near(ar[4], r[4])) then
                    add("Gathering window: its anchor (%s) isn't its rect (%s)", fmt(ar), fmt(r))
                end
            end
        end
        local alpha = ask(win.frame, "GetEffectiveAlpha")
        if type(alpha) == "number" and alpha < Look.FULL_ALPHA and not fading(win) then
            add("%s: effective alpha %.2f", win.name, alpha)
        end
        checkSkins(win, add)
        checkSizes(win, add)
        checkTexts(win, add)
    end
    checkCards(add)
    checkScrolls(add)
    checkPicks(add)
    return out
end

-- /proflost check look.
function Look.PrintCheck()
    local lines = Look.Check()
    if #lines == 0 then return CP:Print("look ok") end
    CP:Print(("look: %d problems"):format(#lines))
    for _, line in ipairs(lines) do print("  " .. line) end
end
