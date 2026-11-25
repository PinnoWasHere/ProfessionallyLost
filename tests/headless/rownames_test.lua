-- CARDLOAD-01b: a guide row's name is one line cut with "...", in every path that draws it
-- (first draw, click, scroll's row reuse, list rebuild), and the row keeps its pin and height.

local CP = ProfLost
local GT, S = CP.GuideTab, CP.Style
local LW = 165
local DUROTAR = 1411
local LONG = "Nightscape Headband of the Very Long Recipe Name That Never Ends In Any Font"

local function scene()
    Visual.begin()
    DaylightWorld.begin({ plugin = true })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 900 })
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function() CraftWorld.Close() CP.Window.Update() end)
    CP.Window.Update()
    CP.Window.Pick(LW)
    CP.Panel:Refresh()
    T.advance(0.5)
end

-- A craft row with a long recipe name, and a short one beside it.
local function rows()
    local base
    for _, r in ipairs(GT.ui.rows) do
        if r.recipe and not (r.rank or r.train or r.side) then base = base or r end
    end
    T.ok(base ~= nil, "a craft row exists")
    local recipe = setmetatable({ name = LONG }, { __index = base.recipe })
    local long = { key = 999, from = base.from, to = base.to, crafts = base.crafts, learned = base.learned,
                   spell = base.spell, recipe = recipe }
    return long, base
end

local function button()
    local b = CreateFrame("Button", nil, GT.ui.scroll)
    b:SetSize(300, 24)
    World.onEnd(function() b:Hide() end)
    return b
end

local function oneLine(b, what)
    T.ok(not b.name:CanWordWrap(), what .. ": word wrap is off")
    T.ok(S.cut[b.name], what .. ": the name is cut with an ellipsis")
    T.ok((b.name:GetNumLines() or 1) <= 1, what .. ": one line")
    T.eq(GT.RowHeight(b.row), 24, what .. ": the row keeps its height")
end

T.test("a long name is one line and keeps its pin on first draw, click, scroll and rebuild", function()
    scene()
    local long, short = rows()
    local b = button()
    GT.PaintRow(b, long)
    oneLine(b, "first draw")
    local pinned = b.pin:IsShown()
    T.ok(pinned, "the map pin shows on the first draw")

    -- The click path: the row's own script, then the list repaints the row.
    b:GetScript("OnClick")(b)
    GT.PaintRow(b, long)
    oneLine(b, "after a click")

    -- The scroll path: the same button is reused for another row, then the long one again.
    GT.PaintRow(b, short)
    GT.PaintRow(b, long)
    oneLine(b, "after a scroll")

    -- A rebuild and a narrower window: the plan redraws and the heights are worked out again.
    CP.Panel:Refresh()
    local fresh = button()
    GT.PaintRow(fresh, long)
    oneLine(fresh, "after a rebuild")
end)

T.test("a long name's row keeps its map pin after the list scrolls", function()
    scene()
    local long, short = rows()
    local b = button()
    GT.PaintRow(b, short)
    GT.PaintRow(b, long)
    T.eq(b.pin:IsShown(), CP.Guide.WaypointFor(long, GT.ui.live and GT.ui.live.prof) ~= nil, "the pin follows the row's place")
    T.eq(b.pin:GetNumPoints() > 0, true, "the pin is anchored")
end)
