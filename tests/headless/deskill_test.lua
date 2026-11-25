-- Disenchanting gives Enchanting skill-ups (DESKILL-01). Forever's client data has Disenchant
-- (spell 13262) on Enchanting's skill line with SkillLineAbility row 7316: learned at 1, orange
-- below 20, grey from 60, one point a skill-up. The guide plans the greens the player can
-- disenchant as a skill-up step ahead of the crafts that cost materials, counted with the
-- crafts' chance model, and the dust they give feeds the later steps.

local CP = ProfLost
local ENCHANTING = 333
local DUROTAR = 1411
local SPELL = 13262
local GLOVES = 4307           -- Heavy Linen Gloves: green, item level 15, disenchant group 1
local LATE = 4308             -- a green at item level 22 here: needs skill 25 to disenchant
local DUST, LESSER = 10940, 10938

-- The rule as the client data gives it (SkillLineAbility 7316).
local YELLOW, GREY = 20, 60

-- A fresh Horde enchanter at 1/75 holding `gloves` greens (and `late` ones), the window open.
-- `prices`: auction prices by item, through DaylightMogul.
local function scene(gloves, late, prices)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 } },
                       bags = { [GLOVES] = gloves or nil, [LATE] = late or nil },
                       items = { [GLOVES] = { 2, 15, 4, 1, 1, 1, 0 }, [LATE] = { 2, 22, 4, 1, 1, 1, 0 } } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    World.set(_G, "DaylightMogul", prices and { API = { Price = function(id) return prices[id] end } } or nil)
    World.patch("InCombatLockdown", function() return false end)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    return CP.Plan.Current()
end

-- The main rows: stops and "or" rows left out.
local function steps(live)
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        if row.spell and not (row.rank or row.train or row.side) then out[#out + 1] = row end
    end
    return out
end

local function describe(rows)
    local parts = {}
    for i, row in ipairs(rows) do
        if i > 4 then break end
        parts[#parts + 1] = ("%s %s-%s x%s"):format(tostring(row.spell), tostring(row.from), tostring(row.to),
            tostring(row.crafts))
    end
    return table.concat(parts, "; ")
end

-- The skill `n` disenchants reach from `from`, point by point: below yellow every one gives a
-- point, from yellow to grey the chance falls linearly.
local function reach(from, n)
    local x, left = from, n
    while left > 1e-9 do
        local s = math.floor(x)
        local p = s >= GREY and 0 or s < YELLOW and 1 or (GREY - s) / (GREY - YELLOW)
        if p <= 0 then break end
        local step = (s + 1 - x) / p
        if left >= step then left, x = left - step, s + 1 else x, left = x + left * p, 0 end
    end
    return math.floor(x + 1e-9)
end

T.test("a fresh enchanter's greens make the first steps, before any craft that costs materials", function()
    local live = scene(12)
    local rows = steps(live)
    T.ok(#rows >= 2, "rows: " .. describe(rows))
    local first, second = rows[1], rows[2]
    T.eq(first.spell, SPELL, "the first step disenchants: " .. describe(rows))
    T.eq(first.from, 1, "from the skill")
    T.eq(first.to, 13, "12 orange disenchants give 12 points: " .. describe(rows))
    T.eq(first.crafts, 12, "one green a point")
    T.eq(second.from, first.to, "the crafts start where disenchanting stops")
    T.ok(#second.recipe.reagents > 0, "the next step costs materials")
    for i = 2, #rows do T.ok(rows[i].spell ~= SPELL, "disenchanting is one step") end

    local range, name, info = CP.GuideTab.RowTexts(first)
    T.eq(range, "1-13")
    T.eq(name, "Disenchant greens")
    T.eq(info, "12 greens")

    local card = CP.GuideTab.Card(live)
    T.eq(card.step, "Disenchant greens  1-13")
    T.eq(card.need, "Disenchant 12 greens; the Disenchant tab lists them")
    T.eq(card.spell, nil, "no craft button casts Disenchant from the guide")
end)

T.test("without greens the guide crafts from the start", function()
    local rows = steps(scene(0))
    T.ok(#rows > 0)
    T.eq(rows[1].from, 1)
    for _, row in ipairs(rows) do T.ok(row.spell ~= SPELL, "no disenchant step: " .. describe(rows)) end
end)

T.test("disenchanting stops where the data greys it, counted with the crafts' chance", function()
    local n = 70
    local want = reach(1, n)
    T.ok(want > YELLOW and want < GREY, "the model reaches into the yellow and green bands: " .. want)
    local rows = steps(scene(n))
    T.eq(rows[1].spell, SPELL, describe(rows))
    T.eq(rows[1].to, want, describe(rows))
    T.ok(rows[1].crafts <= n, "never more greens than held")
    T.eq(rows[2].from, want)
    T.eq(reach(1, 500), GREY, "grey ends it: the green from 59 still gives the last point")
end)

T.test("a green the skill can't disenchant yet waits for the skill", function()
    local rows = steps(scene(0, 5))
    for _, row in ipairs(rows) do T.ok(row.spell ~= SPELL, "item level 22 needs 25: " .. describe(rows)) end
    -- With 30 that the skill can take, the item level 22 ones join once the skill reaches 25.
    rows = steps(scene(30, 5))
    T.eq(rows[1].spell, SPELL)
    T.eq(rows[1].to, reach(1, 35), describe(rows))
end)

T.test("a green worth more sold is not planned for skill-ups", function()
    -- The gloves sell for 8g; their dust is worth a few silver.
    local rows = steps(scene(12, nil, { [GLOVES] = 80000, [DUST] = 1000, [LESSER] = 2000 }))
    for _, row in ipairs(rows) do T.ok(row.spell ~= SPELL, describe(rows)) end
end)

T.test("the dust the greens give feeds the steps after them", function()
    local live = scene(12)
    local guide, Q = live.guide, CP.Queue
    local entries = Q.Build(guide, 1, 75, 75, live.plan, live.learned)
    local gross = 0
    for _, e in ipairs(entries) do
        if e.kind == "craft" then
            for _, pair in ipairs(e.recipe.reagents) do
                if pair[1] == DUST then gross = gross + pair[2] * e.crafts end
            end
        end
    end
    T.ok(gross > 0, "the plan to 75 uses Strange Dust")
    local need = 0
    for _, m in ipairs(Q.Materials(entries)) do
        if m.itemID == DUST then need = m.need end
    end
    -- Group 1: 80% for 1.5 Strange Dust a green, 14.4 from 12, rounded to the nearest.
    T.ok(math.abs(need - math.max(0, gross - 14)) < 1e-6,
        ("need %s, gross %s"):format(tostring(need), tostring(gross)))
end)

T.test("the step's details say what to do and what it gives, with nothing to craft", function()
    local live = scene(12)
    local first = steps(live)[1]
    T.eq(first.spell, SPELL)
    local GT = CP.GuideTab
    local d = GT.ui.details
    GT.FillDetails(first)
    T.eq(d.title:GetText(), "Disenchant greens")
    T.eq(d.status:GetText(), "1-13  ·  Disenchant 12 greens; the Disenchant tab lists them")
    -- Group 1 per green: 1.2 Strange Dust and 0.3 Lesser Magic Essence, rounded to the nearest.
    local gives = d.sale:GetText()
    T.ok(gives:find("14 Strange Dust", 1, true) ~= nil and gives:find("4 Lesser Magic Essence", 1, true) ~= nil, gives)
    T.ok(not d.craftAll:IsEnabled(), "no craft button casts Disenchant")
    CP.GuideTab.FillDeskillDetails(first)
    T.eq(d.status:GetText(), "1-13  ·  Disenchant 12 greens; the Disenchant tab lists them")
end)
