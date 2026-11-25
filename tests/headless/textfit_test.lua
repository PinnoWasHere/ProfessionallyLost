-- Text fits: the guide window grows for its title bar, tab row and columns in the current
-- font up to its cap, numeric columns stay one line as wide as their widest text, guide step
-- names stay one line cut with "..." (Style.OneLine), Shop names do too,
-- and the gathering panel keeps short infos (yards) on the first line. Fonts come from the visual world's model (tests/world/visual.lua): two
-- faces (daylightworld's "general" and "wide") at two text sizes.

local CP = ProfLost
local W, P, GP, GT, S = CP.Window, CP.Panel, CP.GatherPanel, CP.GuideTab, CP.Style
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR = 1411

local FACES = { "general", "wide" }
local SCALES = { 0.85, 1.15 }

local function settle() T.advance(0.5) end

local function scene(spec)
    spec = spec or {}
    Visual.begin()
    DaylightWorld.begin({ plugin = true, craftWindow = spec.pane })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowCollapsedAll", nil)
    World.set(CP.db, "collect", true)
    World.set(CP.db, "gatherAttached", true)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherSide", "right")
    World.set(CP.db, "windowHeight", CP.DEFAULTS.windowHeight)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 900 })
    World.set(CP.db, "font", "general")
    World.set(CP.db, "textScale", 1)
    World.set(CP.charDB, "guideMode", "one")
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.onEnd(function()
        CraftWorld.Close()
        S.ApplyScale()
        S.ApplyFont()
        GP.anchor:ClearAllPoints()
        W.Update()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    W.Pick(LW)
    P:Refresh()
    settle()
end

-- The player's font and text size, through the options' own rows.
local function font(face, size)
    CP.Settings.Set("font", face)
    CP.Settings.Set("textScale", size)
    settle()
end

-- Rows drawn as the list draws them: one button per item, stacked in `list`, each as tall
-- as `height(item)` says, painted by `init(button, item)`.
local function paint(list, items, init, height)
    local y, made = 0, {}
    for i, item in ipairs(items) do
        local b = CreateFrame("Button", nil, list)
        b:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
        b:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -y)
        b:SetHeight(height(item))
        init(b, item)
        y = y + height(item)
        made[i] = b
    end
    World.onEnd(function() for _, b in ipairs(made) do b:Hide() end end)
    return made
end

local function guideRows()
    return paint(GT.ui.scroll, GT.ui.rows, GT.PaintRow, GT.RowHeight)
end

local function width(fs, text) return P.TextWidth(fs, text) end

-- The window --------------------------------------------------------------------------------

-- The widest need of the title bar, the tab row and the guide rows, at least 356, at most the cap.
local function wanted()
    local w = P.BASE_WIDTH
    for _, key in ipairs({ "title", "row", "guide" }) do w = math.max(w, math.ceil(P.needs[key] or 0)) end
    return math.min(w, P.Cap())
end

T.test("the window is 356 px or what its title bar and rows need, with the full title", function()
    scene()
    T.ok(P.needs.title and P.needs.row and P.needs.guide, "all three parts say what they need")
    T.eq(P.WIDTH, wanted())
    T.eq(P.frame:GetWidth(), P.WIDTH)
    T.eq(P.titleText, P.TITLE_FULL)
    T.ok(not P.title:IsTruncated(), "the title isn't truncated")
    -- Rows that need less leave it at 356.
    P.SetNeed("guide", 100)
    P.ApplyWidth()
    T.eq(P.WIDTH, math.max(P.BASE_WIDTH, math.ceil(math.max(P.needs.title, P.needs.row))), "the rest fits in 356")
    P:Refresh()
    settle()
    Visual.Check("default font")
end)

T.test("a wide font at the largest text size fits the title bar and columns, up to the cap", function()
    scene()
    font("wide", 1.15)
    local cap = math.floor(P.MAX_WIDTH * 1.15 + 0.5)
    T.eq(P.Cap(), cap)
    T.eq(P.WIDTH, wanted(), "what the title bar, tab row and columns need")
    T.ok(P.WIDTH >= P.BASE_WIDTH and P.WIDTH <= cap, ("%d px, between %d and %d"):format(P.WIDTH, P.BASE_WIDTH, cap))
    T.eq(P.frame:GetWidth(), P.WIDTH, "the frame")
    T.eq(W.anchor:GetWidth(), P.WIDTH, "the mover's anchor")
    T.ok(P.titleText == P.TITLE_FULL or P.titleText == P.TITLE_SHORT, "the title: " .. tostring(P.titleText))
    T.ok(not P.title:IsTruncated(), "the title isn't truncated")
    for _, b in ipairs({ W.pickButton, W.switchButton }) do
        T.ok(width(b.label) <= b:GetWidth() - W.ROW_PAD_LEAST, b.label:GetText() .. " fits its button")
        T.ok(not b.label:IsTruncated(), b.label:GetText() .. " isn't truncated")
    end
    Visual.Check("wide font, 1.15")
end)

T.test("the width follows a font change back, and a text size change", function()
    scene()
    local plain, title = P.WIDTH, P.needs.title
    font("wide", 1.15)
    T.ok(P.needs.title > title, "the wide face needs more for the title bar")
    T.eq(P.WIDTH, wanted())
    font("general", 1)
    T.eq(P.WIDTH, plain, "the default font: back")
    T.eq(P.needs.title, title)
    font("wide", 0.85)
    T.eq(P.WIDTH, wanted())
    T.ok(P.WIDTH <= P.Cap(), "within the smaller cap")
end)

-- Only a name's longest word may widen it: a name wraps at spaces.
T.test("recipe names never widen the window past their longest word", function()
    scene()
    font("wide", 1.15)
    local need = GT.Measure(GT.ui.rows)
    local base
    for _, r in ipairs(GT.ui.rows) do
        if r.recipe and not (r.rank or r.train or r.side) then base = base or r end
    end
    local recipe = setmetatable({ name = ("Nightscape Headband of Length "):rep(6) }, { __index = base.recipe })
    local rows = { { key = 999, from = 175, to = 196, crafts = base.crafts, learned = base.learned, spell = base.spell, recipe = recipe } }
    for _, r in ipairs(GT.ui.rows) do rows[#rows + 1] = r end
    T.eq(GT.Measure(rows), need, "a longer name: the same need")
    local C = GT.COLUMNS
    local words = {}
    for _, r in ipairs(GT.ui.rows) do
        local _, name = GT.RowTexts(r)
        for w in name:gmatch("%S+") do words[#words + 1] = w end
    end
    T.eq(need, C.left + GT.ui.rangeW + C.gap + C.edge + GT.ui.infoW + C.edge + S.PIN + C.edge
        + math.max(math.ceil(GT.NAME_MIN * 1.15), S.Widest(words, "body")) + C.list + 2 * P.BODY_PAD,
        "the columns, the pin and NAME_MIN or the longest word")
end)

-- A window forced wider than the title bar needs, as a long title or a wide font would.
local function widen(px)
    P.SetNeed("test", px)
    World.onEnd(function() P.SetNeed("test", nil) end)
    P:Refresh()
    settle()
end

T.test("a profession change measures its own rows", function()
    scene()
    font("wide", 1.15)
    local need = GT.Measure(GT.ui.rows)
    T.eq(P.needs.guide, need, "Leatherworking's rows")
    W.Pick(TAILOR)
    P:Refresh()
    settle()
    T.eq(P.needs.guide, (GT.Measure(GT.ui.rows)), "Tailoring's rows")
end)

T.test("a title too long for the widest window reads ProfLost, never truncated", function()
    scene()
    World.set(P, "TITLE_FULL", ("Professionally Lost "):rep(4))
    P:Refresh()
    settle()
    T.eq(P.WIDTH, P.Cap(), "the window grows to its cap and stops")
    T.eq(P.titleText, P.TITLE_SHORT)
    T.ok(P.title:IsShown() and not P.title:IsTruncated(), "ProfLost shows whole")
end)

T.test("the attached gathering panel sits against the wider window and the shell frames both", function()
    scene()
    font("wide", 1.15)
    widen(P.BASE_WIDTH + 60)
    T.ok(P.WIDTH > P.BASE_WIDTH)
    T.ok(GP.Showing() and GP.p == 1, "the panel is out")
    local l, _, r = Visual.Resolve(P.frame)
    local sl = Visual.Resolve(GP.sheet)
    T.eq(sl, r, "the panel starts at the window's right edge")
    local hl, _, hr = Visual.Resolve(GP.shell)
    T.eq({ hl, hr - hl }, { l, P.WIDTH + GP.WIDTH }, "one shell around both")
    Visual.Check("wide font, panel attached")
end)

T.test("with Daylight UI's profession window open, a wide font widens the free window", function()
    scene({ pane = true })
    CraftWorld.Open(LW)
    settle()
    T.ok(CP.Host.DaylightWindow(), "Daylight UI's window is up")
    font("wide", 1.15)
    widen(P.BASE_WIDTH + 60)
    T.ok(P.WIDTH > P.BASE_WIDTH)
    T.eq(DaylightWorld.state.paneWidth, nil, "no pane asked for")
    Visual.Check("wide font, Daylight UI's window open")
end)

-- The step list's columns --------------------------------------------------------------------

for _, face in ipairs(FACES) do
    for _, size in ipairs(SCALES) do
        T.test(("the range and info columns are one line, as wide as their widest text: %s, %.2f"):format(face, size), function()
            scene()
            font(face, size)
            local rows = GT.ui.rows
            T.ok(#rows > 3, "rows to draw")
            local ranges, infos = {}, {}
            for i, row in ipairs(rows) do
                local range, _, info = GT.RowTexts(row)
                ranges[i], infos[i] = range, info
            end
            local C = GT.COLUMNS
            local orW = C.arrowX + C.arrow + C.orGap + S.Measure("or", "small") - C.left
            T.eq(GT.ui.rangeW, math.max(S.Widest(ranges, "small"), orW), "the range column")
            T.eq(GT.ui.infoW, S.Widest(infos, "small"), "the info column")
            for i, b in ipairs(guideRows()) do
                for _, col in ipairs({ b.range, b.info }) do
                    T.ok(not col:CanWordWrap(), "no word wrap")
                    T.ok(not col:IsTruncated(), ("row %d: %q fits"):format(i, col:GetText() or ""))
                    T.ok((col:GetNumLines() or 0) <= 1, ("row %d: %q on one line"):format(i, col:GetText() or ""))
                end
                -- The name is one line that may end in "...", and fits the row's height.
                T.ok(S.cut[b.name], "the name may be cut")
                T.ok(not b.name:CanWordWrap(), "the name does not wrap")
                T.ok((b.name:GetStringHeight() or 0) <= b:GetHeight() + 0.5,
                    ("row %d: %q's lines fit its row"):format(i, b.name:GetText() or ""))
            end
            Visual.Check(("%s, %.2f, step rows"):format(face, size))
        end)
    end
end

T.test("the range column measures again after a font change", function()
    scene()
    local plain = GT.ui.rangeW
    font("wide", 1)
    T.ok(GT.ui.rangeW > plain, ("wider in the wide face (%d, was %d)"):format(GT.ui.rangeW, plain))
    font("general", 1.15)
    T.ok(GT.ui.rangeW > plain, "wider at a larger size")
    font("general", 1)
    T.eq(GT.ui.rangeW, plain, "back")
end)

T.test("a recipe name too long for its row stays on one line in a row of ROW_H", function()
    scene()
    local name = "Nightscape Headband of the Very Long Recipe Name That Never Ends In Any Font"
    local base
    for _, r in ipairs(GT.ui.rows) do
        if r.recipe and not (r.rank or r.train or r.side) then base = base or r end
    end
    local recipe = setmetatable({ name = name }, { __index = base.recipe })
    local row = { key = 999, from = 175, to = 196, crafts = base.crafts, learned = base.learned, spell = base.spell, recipe = recipe }
    T.eq(GT.RowHeight(row), 24, "one line high")
    local b = paint(GT.ui.scroll, { row }, GT.PaintRow, GT.RowHeight)[1]
    T.eq(b.name:GetText(), name, "the whole name is set")
    T.ok(not b.name:CanWordWrap(), "no word wrap")
    T.ok(b.name:GetNumLines() <= 1, "on one line")
    T.ok(b.name:GetStringHeight() <= b:GetHeight() + 0.5, "inside its row")
    T.eq(b.range:GetNumLines(), 1, "the range stays one line")
    T.ok(not b.range:IsTruncated(), "the range whole")
    Visual.Check("a cut recipe name")
end)

-- The gathering panel's short infos ---------------------------------------------------------------

T.test("a spot keeps its yards right-aligned on the first line; only the name wraps", function()
    local GL = CP.GatherList
    local saved = GL.Measure
    GL.Measure = function(text) return #text * 9 end
    local ok, err = pcall(function()
        local spot = { kind = "plan", indent = 34, text = "Light Leather, Medium Leather, Heavy Leather, Thick Hide",
                       info = "4.3k yd", pin = function() end }
        local out = GL.Wrap({ spot }, false)
        T.ok(#out >= 2, "the name takes more lines")
        T.ok(not spot.wrapped, "the yards stay on the first line")
        for i = 2, #out do
            T.eq(out[i].kind, "cont")
            T.ok(not out[i].text:find("yd", 1, true), "no line of its own for the yards: " .. out[i].text)
        end
        local room = GL.width - 34 - 20 - 8 - #"4.3k yd" * 9
        T.ok(#spot.text * 9 <= room, "the first piece leaves the yards their room")
    end)
    GL.Measure = saved
    T.ok(ok, err)
end)

-- The gathering panel's kinds of line, each with a long name and its short or long info.
local function gatherLines()
    local GL, pin = CP.GatherList, function() end
    local saved = GL.Lines
    GL.Lines = function()
        return {
            { kind = "plan", indent = 34, muted = false, textColor = S.color.text, pin = pin, info = "4.3k yd",
              text = "Light Leather, Medium Leather, Heavy Leather, Thick Leather" },
            { kind = "item", open = false, info = "82 / 14",
              row = { itemID = 2318, name = "Light Leather of a Remarkably Long Name", soonDone = true } },
            { kind = "item", open = false, info = "14 / 14",
              row = { itemID = 2319, name = "Medium Leather Gathered Every Last Piece Done", done = true } },
            { kind = "vendor", text = "Andrew Hilbert", info = "Silverpine Forest (43.2, 40.7)", pin = pin },
            { kind = "pattern", text = "Pattern: Nightscape Headband of the Long Night", info = "skill 205" },
        }
    end
    World.onEnd(function()
        GL.Lines = saved
        GL.Refresh()
    end)
    GL.Refresh()
    settle()
end

for _, face in ipairs(FACES) do
    for _, size in ipairs(SCALES) do
        T.test(("the gathering panel's rows hold their infos on one line: %s, %.2f"):format(face, size), function()
            scene()
            font(face, size)
            gatherLines()
            local _, rows = CP.GatherList.Drawn()
            local shown = 0
            for _, r in ipairs(rows) do
                if r:IsShown() then
                    shown = shown + 1
                    if (r.info:GetText() or "") ~= "" then
                        T.ok(not r.info:CanWordWrap() and r.info:GetNumLines() == 1, "info " .. r.info:GetText())
                    end
                    T.ok(not r.name:IsTruncated(), "name " .. tostring(r.name:GetText()))
                end
            end
            T.ok(shown > 0, "rows drawn")
            Visual.Check(("%s, %.2f, gathering panel"):format(face, size))
        end)
    end
end

-- The other lists ------------------------------------------------------------------------------

T.test("the disenchant button names the item when it fits, else reads Disenchant", function()
    scene()
    local DT = CP.DisenchantTab
    local _, _, b = DT.State()
    T.ok(b ~= nil, "the button exists")
    World.set(P, "TextWidth", function(fs, text) if text then fs:SetText(text) end return #(fs:GetText() or "") * 7 end)
    local room = P.WIDTH - 2 * P.BODY_PAD - DT.LABEL_PAD
    local fits = ("x"):rep(math.floor(room / 7) - #"Disenchant: ")
    local long = ("x"):rep(math.floor(room / 7))
    for _, case in ipairs({ { fits, "Disenchant: " .. fits }, { long, "Disenchant" } }) do
        DT.Arm({ name = case[1], bag = 0, slot = 1, itemID = 1 })
        T.eq(b.label:GetText(), case[2])
    end
    DT.Arm(nil)
end)

T.test("a disenchant row's long name stays one line; only its detail wraps", function()
    scene()
    local DT = CP.DisenchantTab
    local it = { name = ("Glimmering Long Name "):rep(6), ilvl = 25,
                 advice = { de = 2400, vendor = 4500, ah = 10000, verdict = "de" },
                 yield = { { count = 1.6, item = 10940 } } }
    DT.Measure({ it })
    T.eq(it.lines.name, nil, "the name doesn't break")
    local extra = it.lines.detail and select(2, it.lines.detail:gsub("\n", "")) or 0
    T.eq(it.height, 34 + extra * S.LineHeight("small"), "only the detail's lines add height")
end)

T.test("a shop row's long name stays one line; the cost column takes its widest price", function()
    scene()
    local ST = CP.ShopTab
    local rows = {
        { itemID = 2318, have = 1, need = 20, left = 19, price = 123456, mail = 0, vendor = false },
        { itemID = 2319, have = 0, need = 5, left = 5, price = 50, mail = 0, vendor = true },
    }
    World.set(CP, "ItemName", function(id) return id == 2318 and ("Light Leather of Great Length "):rep(5) or "Thread" end)
    ST.Measure(rows)
    T.eq(ST.ui.costW, math.max(S.Measure(CP.Pricing.Format(123456 * 19), "small"), S.Measure(CP.Pricing.Format(250), "small")))
    T.eq(rows[1].lines, nil, "the long name doesn't break")
    T.eq(ST.RowHeight(rows[1]), 22, "one row high")
    local b = paint(ST.ui.scroll, rows, ST.InitRow, ST.RowHeight)[1]
    T.ok(S.cut[b.name] and not b.name:CanWordWrap(), "one line, may end in ...")
end)
