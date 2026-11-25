-- LEGIBLE-01: colour carries meaning in the guide. Step names keep their difficulty colour,
-- learned or not, in the Single view and on the All view's cards; row tags and prices are neutral, the card's
-- source and "While you're there" lines are label ink with text-ink numbers, and warn
-- marks warnings only.

local CP = ProfLost
local GT, S = CP.GuideTab, CP.Style
local W = CP.Window
local TAILOR, COOK = 197, 185
local DUROTAR = 1411

-- A Horde level-20 tailor at 45, far from Orgrimmar's trainers (as trip_test's scene).
local function scene()
    MapWorld.begin({ zone = DUROTAR, x = 0.52, y = 0.43, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 45, max = 75 }, [COOK] = { rank = 40, max = 75 } } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function()
        W.opened = false
        W.Update()
    end)
    W.Update()
    T.advance(0.1)
    for _, line in ipairs({ TAILOR, COOK }) do
        CraftWorld.Open(line)
        CraftWorld.Close()
    end
    W.Pick(TAILOR)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
end

local function button()
    local b = CreateFrame("Button", nil, GT.ui.scroll)
    b:SetSize(300, 24)
    World.onEnd(function() b:Hide() end)
    return b
end

local function craftRow()
    for _, r in ipairs(GT.ui.rows) do
        if r.recipe and r.spell and not (r.rank or r.train or r.side) then return r end
    end
end

local function copy(row, over)
    local c = {}
    for k, v in pairs(row) do c[k] = v end
    for k, v in pairs(over) do c[k] = v end
    return c
end

local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The harness keeps no text colour, so a font string's colour is recorded as it is set.
local function watch(fs)
    fs.SetTextColor = function(self, r, g, b) self.ink = { r, g, b } end
    fs.SetAlpha = function(self, a) self.alpha = a end
    World.onEnd(function() fs.SetTextColor, fs.SetAlpha = nil, nil end)
    return fs
end

local function same(a, b)
    return a and b and math.abs(a[1] - b[1]) < 1e-6 and math.abs(a[2] - b[2]) < 1e-6 and math.abs(a[3] - b[3]) < 1e-6
end

local function role(fs, name, what)
    T.ok(same(fs.ink, S.color[name]), what .. " is " .. name)
end

local function paint(row)
    local b = button()
    GT.PaintRow(b, row)
    watch(b.name)
    watch(b.info)
    GT.PaintRow(b, row)
    return b
end

local function difficulty(c)
    for _, d in pairs(S.difficulty) do
        if same(c, d) then return true end
    end
    return false
end

T.test("a step keeps its difficulty colour, learned or not, at full alpha", function()
    scene()
    local row = craftRow()
    T.ok(row ~= nil, "a craft row exists")
    if not row then return end
    local learned = paint(copy(row, { learned = true }))
    T.ok(difficulty(learned.name.ink), "learned name keeps a difficulty colour")
    local b = paint(copy(row, { learned = false }))
    T.ok(same(b.name.ink, learned.name.ink), "unlearned name keeps the same difficulty colour")
    T.eq(b.name.alpha, 1, "unlearned name is not dimmed")
    role(b.info, "label", "the source word")
end)

T.test("a stop row's tag is label ink and its price text ink, never warn", function()
    scene()
    local seen = 0
    for _, row in ipairs(GT.ui.rows) do
        if row.rank or row.train then
            local b = paint(row)
            seen = seen + 1
            T.ok(not same(b.info.ink, S.color.warn), "no warn on a stop row's tag")
            local priced = b.info:GetText():find("^%d+[gsc]") ~= nil
            role(b.info, priced and "text" or "label", "the tag " .. b.info:GetText())
        end
    end
    T.ok(seen > 0, "the guide has stop rows")
end)

T.test("a far trainer's card: the lead is label ink, the trip text ink, no warn", function()
    scene()
    local card
    for _, row in ipairs(GT.ui.rows) do
        if row.rank and row.rank.name == "Journeyman Tailoring" then card = row end
    end
    T.ok(card ~= nil, "Journeyman Tailoring row")
    if not card then return end
    local d = GT.ui.details
    watch(d.status)
    GT.Pick(card)
    local text = d.sale:GetText() or ""
    local label, body = S.Hex(S.color.label), S.Hex(S.color.text)
    T.ok(text:find(label .. "While you're there, |r" .. body, 1, true) ~= nil, "lead is label ink: " .. text)
    T.ok(text:find("Bring", 1, true) ~= nil, "the gold line is there")
    T.ok(text:find(S.Hex(S.color.warn), 1, true) == nil, "the trip carries no warn")
    role(d.status, "label", "the stop status")
end)

T.test("an unlearned step's card names its source in label ink with the skill in text ink", function()
    scene()
    local row = craftRow()
    if not row then return T.ok(false, "no craft row") end
    local d = GT.ui.details
    watch(d.status)
    GT.FillDetails(copy(row, { learned = false }))
    local status = d.status:GetText() or ""
    role(d.status, "label", "the source line")
    T.ok(status:find(S.Hex(S.color.text) .. "skill %d+|r") ~= nil, "skill number in text ink: " .. status)
    T.ok(status:find(S.Hex(S.color.warn), 1, true) == nil, "no warn in the source line: " .. plain(status))
end)

T.test("an All-view card's step reads in its recipe's difficulty colour", function()
    scene()
    local live = W.Live and W.Live(TAILOR)
    T.ok(live ~= nil, "the tailor's live state")
    if not live then return end
    local card = GT.Card(live)
    T.ok(card.stepColor ~= nil and difficulty(card.stepColor), "card step colour is a difficulty colour")
end)
