-- The "or" row under the step being crafted follows the skill and the bags: after every
-- craft of a batch, the guide shows what a fresh read at the same skill and bags shows.
-- The owner's sequence: Leatherworking 136, eight Heavy Armor Kits to 143 (one gives no
-- point), then three Cured Heavy Hides from the "or" row, green, no point.

local CP = ProfLost
local LW = 165
local DUROTAR = 1411
local KIT = 3780                -- Heavy Armor Kit: learn 125, yellow 145, grey 165
local CURE = 3818               -- Cured Heavy Hide: 1 Heavy Hide, 3 Salt; yellow 135, grey 145
local HEAVY_LEATHER, FINE_THREAD = 4234, 2321
local HEAVY_HIDE, SALT = 4235, 4289
local CAST = 3

-- A step row as drawn: range, name, info, "or", and the name's colour.
local function drawn(row)
    local b = CreateFrame("Button", nil, UIParent)
    CP.GuideTab.PaintRow(b, row)
    local c = {}
    b.name.SetTextColor = function(_, ...) c = { ... } end
    CP.GuideTab.PaintRow(b, row)
    b:Hide()
    local range, name, info = CP.GuideTab.RowTexts(row)
    return ("%s|%s|%s|%s|%.2f,%.2f,%.2f"):format(range, name, info, row.side and "or" or "",
        c[1] or -1, c[2] or -1, c[3] or -1)
end

-- What the guide shows: One mode's step rows and card status, All mode's cards.
local function shown()
    local out = {}
    if CP.Window.Mode() == "all" then
        for _, card in ipairs(CP.GuideTab.ui.cardList or {}) do
            out[#out + 1] = table.concat({ card.skill, card.step or "", card.need or "", tostring(card.crafts),
                tostring(card.craftable) }, "|")
        end
        return table.concat(out, "\n")
    end
    for _, row in ipairs(CP.GuideTab.ui.rows or {}) do out[#out + 1] = drawn(row) end
    out[#out + 1] = "card: " .. (CP.GuideTab.ui.details.status:GetText() or "")
    return table.concat(out, "\n")
end

-- What a fresh read at the same skill and bags shows.
local function fresh()
    CP.Professions.DropRecipes()
    CP.Plan.Invalidate()
    CP.Panel:Refresh()
    T.advance(0.2)
    return shown()
end

-- The "or" row for `spell`, as drawn, or "none".
local function orRow(spell)
    for _, row in ipairs(CP.GuideTab.ui.rows or {}) do
        if row.side and row.spell == spell then return drawn(row) end
    end
    return "none"
end

-- No "or" row is green beside a main step the player knows or can train: green shows
-- only beside a pattern they haven't got, where it may be the only way on.
local function noGreenOrs(label)
    local live, main = CP.Plan.Current(), nil
    local skill = live.prof.skill
    for _, row in ipairs(CP.GuideTab.ui.rows or {}) do
        if not row.side then
            if row.spell and not (row.rank or row.train) then main = row end
        elseif CP.Professions.DifficultyAt(row.recipe, math.max(skill, row.from)) == CP.Professions.GREEN then
            T.ok(main and CP.Plan.PatternOnly(live, main.spell),
                ("%s: %s is green beside %s"):format(label, row.recipe.name, main and main.recipe.name or "nothing"))
        end
    end
end

local function scene(spec)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    DaylightWorld.begin({ craftWindow = spec.game ~= true, plugin = spec.plugin })
    CraftWorld.begin({ professions = { [LW] = { rank = 136, max = 225 } }, late = spec.late,
                       bags = { [HEAVY_LEATHER] = 60, [FINE_THREAD] = 20, [HEAVY_HIDE] = spec.hides, [SALT] = 30 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", spec.mode or "one")
    CraftWorld.Open(LW)
    T.advance(2)
end

-- Crafts `n` of `spell`; after each, what shows must be what a fresh read shows.
local function craft(label, spell, n, miss)
    CP.Crafting.Start(spell, n)
    T.advance(0.5)
    for i = 1, n do
        if i == miss then CraftWorld.Miss() end
        T.ok(CraftWorld.Cast(), label .. " cast " .. i)
        T.advance(CAST)
        local now = shown()
        local skill = CraftWorld.state.profs[LW].rank
        local stale = {}
        for _, r in ipairs(CP.Plan.Current().recipes) do
            local game = C_TradeSkillUI.GetRecipeInfo(r.id).relativeDifficulty
            if r.difficulty ~= game then stale[#stale + 1] = ("%s %d->%d"):format(r.name, r.difficulty, game) end
        end
        T.eq(#stale, 0, ("%s %d at skill %d: the kept list has the game's colours: %s"):format(label, i, skill,
            table.concat(stale, ", ")))
        local truth = fresh()
        if now ~= truth then
            print(("%s %d at %d, hides %d\nshown:\n%s\nfresh:\n%s"):format(label, i, skill,
                CraftWorld.Bag(HEAVY_HIDE), now, truth))
        end
        T.eq(now, truth, ("%s %d at skill %d: what shows is what a fresh read shows"):format(label, i, skill))
        if CP.Window.Mode() == "one" then
            noGreenOrs(("%s %d at %d"):format(label, i, skill))
            local cure = orRow(CURE)
            if skill >= 140 then T.eq(cure, "none", ("%s %d at %d: no Cured Heavy Hide row once it is green"):format(label, i, skill)) end
        end
    end
end

local YELLOW_TEXT = ("%.2f,%.2f,%.2f"):format(unpack(CP.Style.difficulty[CP.Professions.YELLOW]))

local function sequence(name, spec)
    T.test(name, function()
        scene(spec)
        local one = (spec.mode or "one") == "one"
        if one then
            local cure = orRow(CURE)
            print(name .. ", at 136: " .. cure)
            T.ok(cure:find("|Cured Heavy Hide to 140|", 1, true), "at 136 the hide row runs to 140, where it greens: " .. cure)
            T.ok(cure:find(YELLOW_TEXT, 1, true), "in yellow: " .. cure)
        end
        craft("kit", KIT, 8, 4)
        T.eq(CraftWorld.state.profs[LW].rank, 143, "eight kits, seven points: 143")
        if one then print(name .. ", at 143: " .. orRow(CURE)) end
        craft("cure", CURE, 3)
        T.eq(CraftWorld.state.profs[LW].rank, 143, "green cures give no point")
        T.eq(CraftWorld.Bag(HEAVY_HIDE), spec.hides - 3, "three hides used")
    end)
end

-- Colours that land after the skill: the list read in between is read once more after the
-- list update, so a skill-up costs two list reads at most and a craft without one none.
T.test("colours that land after the skill cost one more list read, no more", function()
    scene({ hides = 10, late = "colours" })
    local TS, reads, inside = C_TradeSkillUI, 0, false
    local recipes, all = CP.Professions.Recipes, TS.GetAllRecipeIDs
    World.set(CP.Professions, "Recipes", function(...)
        inside = true
        local out = recipes(...)
        inside = false
        return out
    end)
    World.set(TS, "GetAllRecipeIDs", function(...)
        if inside then reads = reads + 1 end
        return all(...)
    end)
    CP.Crafting.Start(KIT, 8)
    T.advance(0.5)
    local per = {}
    for i = 1, 8 do
        local was, before = CraftWorld.state.profs[LW].rank, reads
        if i == 4 then CraftWorld.Miss() end
        CraftWorld.Cast()
        T.advance(CAST)
        per[#per + 1] = ("%d:%s%d"):format(i, CraftWorld.state.profs[LW].rank > was and "up " or "no ", reads - before)
        if CraftWorld.state.profs[LW].rank > was then
            T.ok(reads - before <= 2, ("craft %d, a skill-up: %d list reads"):format(i, reads - before))
        else
            T.eq(reads - before, 0, ("craft %d, no skill-up: no list read"):format(i))
        end
    end
    print("late colours, list reads per craft: " .. table.concat(per, ", "))
end)

for _, hides in ipairs({ 3, 10 }) do
    for _, late in ipairs({ false, "colours", "skill" }) do
        local tag = (" (%d hides, %s)"):format(hides, late or "data on time")
        sequence("Daylight UI's window, One view" .. tag, { hides = hides, late = late or nil })
        sequence("Daylight UI's window, All view" .. tag, { hides = hides, late = late or nil, mode = "all" })
        sequence("Daylight UI's pane, One view" .. tag, { hides = hides, late = late or nil, plugin = true })
        sequence("the game's window, One view" .. tag, { hides = hides, late = late or nil, game = true })
    end
end
