-- A known vendor recipe is never planned as a pattern to buy (playtest, 1.0.0): Cooking
-- 40/75 with Brilliant Smallfish known was told to buy its pattern. ProfLost saved the known
-- recipes only from a window it recognised, so another addon's profession window, or none
-- opened yet, planned every pattern recipe as unlearned.

local CP = ProfLost
local W, P, GT, Plan = CP.Window, CP.Panel, CP.GuideTab, CP.Plan
local COOKING, FISHING, SMALLFISH = 185, 356, 7751
local SMALLFISH_PATTERN = 6325
local DUROTAR = 1411

local function trainerKnown(line, skill)
    local out = {}
    for id, r in pairs(CP.Guides[line].recipes) do
        if (r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= skill then out[#out + 1] = id end
    end
    return out
end

-- Cooking 40/75 with Brilliant Smallfish known; Fishing up, so fish cost next to nothing
-- and the plan leads with Brilliant Smallfish, as the playtester's did.
-- `book`: what C_SpellBook.IsSpellKnown answers ("known" by the character's recipes, else
-- false for every spell).
local function scene(book)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    local known = trainerKnown(COOKING, 40)
    known[#known + 1] = SMALLFISH
    CraftWorld.begin({ professions = { [COOKING] = { rank = 40, max = 75, known = known }, [FISHING] = 40 } })
    local set = {}
    for _, id in ipairs(known) do set[id] = true end
    World.patch("C_SpellBook.IsSpellKnown", function(id) return book == "known" and set[id] == true end)
    Plan.ForgetBook()
    World.onEnd(Plan.ForgetBook)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.charDB, "guideMode", "one")
end

-- Another addon's profession window, one ProfLost doesn't know, stands in for the game's.
local function otherWindow()
    World.listen(function(what) if what == "craft:show" then return true end end)
end

local function show()
    W.Update()
    W.Pick(COOKING)
    P:Refresh()
    T.advance(0.1)
end

local function smallfishRow()
    for _, row in ipairs(GT.ui.rows or {}) do
        if row.spell == SMALLFISH and not row.side then return row end
    end
end

-- The plan leads with Brilliant Smallfish, learned, and its card never says to buy it.
local function plannedKnown(where)
    local row = smallfishRow()
    T.ok(row ~= nil, where .. ": the plan uses Brilliant Smallfish")
    if not row then return end
    T.ok(row.learned, where .. ": Brilliant Smallfish learned")
    GT.Pick(row)
    T.advance(0.1)
    local status = GT.ui.details.status:GetText() or ""
    T.ok(not status:find("Buy the pattern"), where .. ": " .. status)
    T.eq(GT.ui.details.craftAll.label:GetText() ~= "Buy pattern", true, where .. ": no Buy pattern button")
    for _, p in ipairs(CP.Buying.PatternsFor(W.Live())) do
        T.ok(p.itemID ~= SMALLFISH_PATTERN, where .. ": Buy for guide skips its pattern")
    end
end

T.test("game's window open: a known Brilliant Smallfish is planned learned", function()
    scene()
    CraftWorld.Open(COOKING)
    show()
    plannedKnown("game's window")
end)

T.test("another addon's window open, fresh install: the recipe list is read anyway", function()
    scene()
    otherWindow()
    CraftWorld.Open(COOKING)
    show()
    T.eq(W.ProfessionOpen(), true, "the open trade skill counts")
    T.ok(Plan.Read(COOKING), "the list counts as read")
    plannedKnown("other window")
end)

T.test("window shut after one open: the saved list still knows it", function()
    scene()
    CraftWorld.Open(COOKING)
    CraftWorld.Close()
    show()
    T.eq(W.ProfessionOpen(), false)
    plannedKnown("shut")
end)

T.test("never opened, spellbook answers: its recipes count as known, but not as a read", function()
    scene("known")
    show()
    T.eq(Plan.Read(COOKING), false, "only the recipe list says what is unknown")
    plannedKnown("spellbook")
end)

T.test("never opened, spellbook silent: the step says to open Cooking, not to buy", function()
    scene()
    show()
    local live = W.Live()
    T.ok(live and live.unread, "the shut plan knows it hasn't read the recipes")
    local row = smallfishRow()
    T.ok(row ~= nil and not row.learned, "Brilliant Smallfish leads, not known to ProfLost")
    GT.Pick(row)
    T.advance(0.1)
    T.eq(GT.ui.details.status:GetText(), Plan.OPEN_ONCE:format("Cooking"))
    T.eq(GT.ui.details.craftAll.label:GetText(), "Open")
    local recipePatterns = {}
    for _, r in pairs(CP.Guides[COOKING].recipes) do
        if r.pattern then recipePatterns[r.pattern] = true end
    end
    for _, p in ipairs(CP.Buying.PatternsFor(live)) do
        T.ok(not recipePatterns[p.itemID], "Buy for guide offers no recipe pattern: " .. p.itemID)
    end
    local card = GT.Card(live)
    T.eq(card.need, Plan.OPEN_ONCE:format("Cooking"))
    T.ok(card.unread, "the card's button reads Open, not Buy pattern")

    -- Opening Cooking once reads the list: the step turns into a craft.
    CraftWorld.Open(COOKING)
    CraftWorld.Close()
    show()
    plannedKnown("after one open")
end)

T.test("a window shut before its list arrived leaves the profession unread", function()
    scene()
    CraftWorld.Open(COOKING, "list")
    show()
    CraftWorld.Close()
    show()
    T.eq(Plan.Read(COOKING), false, "an empty list never counts as a read")
    T.ok(W.Live().unread, "still unread")
end)

-- Every guide: each vendor, drop, reputation or quest recipe the character knows is
-- planned known once its list is read through a window ProfLost doesn't recognise.
T.test("every guide's pattern recipes, known, are read as known", function()
    for line, guide in pairs(CP.Guides) do
        MapWorld.begin({ zone = DUROTAR, level = 60, side = "Horde" })
        local known, patterns = {}, {}
        for id, r in pairs(guide.recipes) do
            known[#known + 1] = id
            if CP.Guide.SourceWord(r) ~= "trainer" then patterns[#patterns + 1] = id end
        end
        CraftWorld.begin({ professions = { [line] = { rank = 1, max = 300, known = known } } })
        World.patch("C_SpellBook.IsSpellKnown", function() return false end)
        Plan.ForgetBook()
        otherWindow()
        CraftWorld.Open(line)
        CraftWorld.Close()
        local live = Plan.Shut(line)
        T.ok(live and not live.unread, guide.name .. ": read")
        local missed = {}
        for _, id in ipairs(patterns) do
            if not (live and live.learned[id]) then missed[#missed + 1] = id end
        end
        T.eq(#missed, 0, guide.name .. " patterns planned unlearned: " .. table.concat(missed, ","))
        World.finish()
    end
end)
