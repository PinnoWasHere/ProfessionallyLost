-- TRIP-01 and TRIP-01b: a step that sends the player to a far trainer or vendor says what else
-- that town offers the player right now (recipes and ranks trainable at the current skill and
-- level, other professions' trainers, patterns and vendor goods for later steps) and the gold
-- to bring. A near trainer's card adds nothing.

local CP = ProfLost
local W = CP.Window
local TAILOR, COOK = 197, 185
local DUROTAR = 1411

-- A Horde level-20 tailor at 45 with Cooking at 40. Magar, Orgrimmar's Tailoring trainer,
-- stands at the fixture's Durotar (49.4, 0.0); Zamja, its Cooking trainer, a short walk away.
local function scene(x, y)
    MapWorld.begin({ zone = DUROTAR, x = x, y = y, level = 20, side = "Horde" })
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

local function rankCard(name)
    local ui = CP.GuideTab.ui
    for _, row in ipairs(ui.rows) do
        if row.rank and row.rank.name == name then
            CP.GuideTab.Pick(row)
            -- The card inks the trip block with colour escapes (LEGIBLE-01); the text is what is pinned here.
            return ((ui.details.sale:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        end
    end
    T.ok(false, "no " .. name .. " row")
    return ""
end

local function has(text, part)
    T.ok(text:find(part, 1, true) ~= nil, ("%q in:\n%s"):format(part, text))
end

T.test("a far trainer's card lists what its town teaches for later steps, and the gold to bring", function()
    scene(0.52, 0.43)  -- Razor Hill, far from Orgrimmar's trainers
    local text = rankCard("Journeyman Tailoring")
    has(text, "Nearest: Magar")
    -- Bolt of Woolen Cloth and Woolen Cape are learnable at 55, the visit's skill. Double-stitched
    -- Woolen Shoulders (85) is past the 25 points ahead.
    has(text, "While you're there, train Bolt of Woolen Cloth, Woolen Cape")
    T.ok(not text:find("Double-stitched", 1, true), text)
    -- Cooking's next rank needs skill 50 and the player has 40, so Zamja adds nothing.
    T.ok(not text:find("Other trainers", 1, true), text)
    T.ok(not text:find(" at skill ", 1, true) and not text:find(" at level ", 1, true), text)
    -- The thread later Tailoring steps use.
    has(text, "Fine Thread x")
    T.ok(text:match("\nBring %S+.- for this trip$") ~= nil, text)
    local lines = select(2, text:gsub("\n", "")) + 1
    T.ok(lines <= 5, "Nearest plus at most four lines: " .. lines)
end)

T.test("a near trainer's card adds nothing", function()
    scene(0.494, 0.0)  -- beside Magar
    local text = rankCard("Journeyman Tailoring")
    has(text, "Nearest: Magar")
    T.ok(not text:find("While you're there", 1, true), text)
    T.ok(not text:find("Bring", 1, true), text)
end)

-- Trip.Offer and Trip.Text on a made-up guide: what counts, what a gate holds back, the gold.
T.test("the trip's offer counts town NPCs only, gates by skill and level, and totals the gold", function()
    MapWorld.begin({ zone = DUROTAR, x = 0.52, y = 0.43, level = 20, side = "Horde" })
    local PATTERN, THREAD, DYE, NAMED = 990001, 990002, 990003, 990004
    local guide = {
        npcs = {
            [1] = { "Here", "H", { { 1, 0, 0 } } },
            [2] = { "Far Away", "H", { { 1, 5000, 0 } } },
            [3] = { "Pattern Seller", "N", { { 1, 100, 0 } } },
            [4] = { "Other Side", "A", { { 1, 10, 0 } } },
        },
        items = { [PATTERN] = { 500, false }, [THREAD] = { 10, true }, [DYE] = { 50, true, vendors = { 2 } },
                  [NAMED] = { 20, true, vendors = { 3 } } },
    }
    local rank = { name = "Next Rank", kind = "trainer", skill = 60, cap = 150, fee = 1000, level = 30, npcs = { 1 } }
    local now = { name = "Now Recipe", src = "trainer", learn = 50, fee = 200, npcs = { 1 } }
    local soon = { name = "Soon Recipe", src = "trainer", learn = 70, fee = 300, npcs = { 1 } }
    local late = { name = "Late Recipe", src = "trainer", learn = 90, fee = 400, npcs = { 1 } }
    local away = { name = "Away Recipe", src = "trainer", learn = 50, fee = 50, npcs = { 2, 4 } }
    local pat = { name = "Sold Recipe", src = "vendor", learn = 80, npcs = { 3 }, pattern = PATTERN,
                  reagents = { { THREAD, 2 }, { DYE, 1 }, { NAMED, 1 } } }
    local rows = {
        { rank = rank },
        { train = { skill = 60, recipes = { now, soon, late, away } } },
        { spell = 1, recipe = pat, from = 80, to = 90, crafts = 5, learned = false },
    }
    local npc = { continent = 1, x = 0, y = 0, entry = 1 }
    World.set(CP.Waypoint, "PlayerWorld", function() return 1, 3000, 0 end)
    local offer = CP.Trip.Offer({ npc = npc, guide = guide, skill = 50, rows = rows, own = 100 }, {})
    local names = {}
    for _, it in ipairs(offer.train) do names[#names + 1] = it.name .. (it.gate and (" " .. it.gate) or "") end
    T.eq(table.concat(names, ", "), "Now Recipe")
    -- Only trainable items are listed and priced: own 100, Now Recipe 200, the pattern 500, thread 10 x 10,
    -- the named good 20 x 5. The dye's only seller is out of town.
    T.eq(offer.gold, 100 + 200 + 500 + 100 + 100)
    local text = CP.Trip.Text({ npc = npc, guide = guide, skill = 50, rows = rows, own = 100 }, {})
    T.ok(text ~= nil, "a far trip has a block")
    has(text, "While you're there, train Now Recipe\n")
    has(text, "Buy Sold Recipe pattern, item 990002 x10, item 990004 x5")
    has(text, "Bring " .. CP.Pricing.Format(1000) .. " for this trip")

    -- A rank the skill has reached but the level hasn't is left out; the skill-70 recipe comes in.
    offer = CP.Trip.Offer({ npc = npc, guide = guide, skill = 70, rows = rows, own = 0 }, {})
    names = {}
    for _, it in ipairs(offer.train) do names[#names + 1] = it.name end
    T.eq(table.concat(names, ", "), "Now Recipe, Soon Recipe")

    -- Another guided profession's trainer in town; its goods without named sellers don't count.
    -- Its recipe shows only when trainable now (Other Recipe, learn 1, at skill 1).
    local cook = { npcs = guide.npcs, items = guide.items }
    local other = { name = "Cooking", skill = 1, guide = cook, rows = {
        { train = { skill = 1, recipes = { { name = "Other Recipe", src = "trainer", learn = 1, fee = 5, npcs = { 1 } } } } },
        { spell = 2, recipe = { name = "Stew", reagents = { { THREAD, 1 } } }, from = 1, to = 10, crafts = 9, learned = true },
    } }
    offer = CP.Trip.Offer({ npc = npc, guide = guide, skill = 50, rows = {}, own = 0 }, { other })
    T.eq(#offer.others, 1)
    T.eq(offer.others[1].items[1].name, "Other Recipe")
    T.eq(#offer.buy, 0, "no goods from another profession's unnamed sellers")
    T.eq(offer.gold, 5)

    -- Near: no block.
    World.set(CP.Waypoint, "PlayerWorld", function() return 1, 10, 0 end)
    T.eq(CP.Trip.Text({ npc = npc, guide = guide, skill = 50, rows = rows, own = 100 }, {}), nil)
    -- Nothing more in town: no block either.
    World.set(CP.Waypoint, "PlayerWorld", function() return 1, 3000, 0 end)
    T.eq(CP.Trip.Text({ npc = npc, guide = guide, skill = 50, rows = {}, own = 100 }, {}), nil)
    -- Only recipes past the player's skill are in town: no block either.
    local future = { { rank = rank }, { train = { skill = 60, recipes = { soon, late } } } }
    T.eq(CP.Trip.Text({ npc = npc, guide = guide, skill = 50, rows = future, own = 100 }, {}), nil)
end)
