-- Impromptu crafts (owner, 2026-11-22): a fixed area right above the step card lists learned
-- recipes that still give points and that spare raw loot in the bags makes now. Spare means
-- beyond what the plan still needs. The plan, its rows and the pick never move.

local CP = ProfLost
local GT = CP.GuideTab
local LW = 165
local DUROTAR = 1411
local SKILL = 60
local LIGHT_LEATHER, COARSE_THREAD, CURED_LIGHT_HIDE = 2318, 2320, 4231
local SPARE = 12

-- Every trainer and starting recipe up to SKILL.
local function known()
    local out = {}
    for id, r in pairs(CP.Guides[LW].recipes) do
        if (r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= SKILL then out[#out + 1] = id end
    end
    return out
end

local function scene(bags)
    Visual.begin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    DaylightWorld.begin({ craftWindow = false })
    CraftWorld.begin({ professions = { [LW] = { rank = SKILL, max = 75, known = known() } }, bags = bags or {} })
    World.set(CP.db, "collect", false)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.db, "windowPoint", CP.db.windowPoint)
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel.frame:Show()
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    T.advance(1)
end

-- What the plan still needs of `item`, across every guide.
local function need(item) return (CP.Gather.Needs())[item] or 0 end

local function rowKeys()
    local out = {}
    for _, row in ipairs(GT.ui.rows or {}) do out[#out + 1] = tostring(row.key) .. ":" .. tostring(row.spell) end
    return table.concat(out, ",")
end

local function shownRows(area)
    local out = {}
    for _, r in ipairs(area and area.rows or {}) do
        if r:IsShown() then out[#out + 1] = r end
    end
    return out
end

T.test("spare raw loot lists learned recipes above the step card; plan needs are never offered", function()
    scene()
    local area = GT.ui.impromptu
    T.ok(area ~= nil, "the guide has an impromptu area")
    if not area then return end
    T.ok(area:IsShown(), "the area shows in Single view")
    local emptyH = area:GetHeight()
    T.ok(emptyH >= 2 * GT.RowHeight(), "the area holds at least two step rows")
    T.eq(#shownRows(area), 0, "empty bags offer nothing")
    T.ok(area.empty:IsShown(), "the muted line stands in for the rows")

    -- The area sits between the step list and the card.
    local d = GT.ui.details
    T.ok(area:GetBottom() >= d:GetTop() - 0.5, "the area sits above the step card")
    T.ok(GT.ui.scroll:GetBottom() >= area:GetTop() - 0.5, "the step list ends above the area")

    -- Exactly what the plan needs: nothing is spare.
    local planRows = rowKeys()
    local leather, thread = need(LIGHT_LEATHER), need(COARSE_THREAD)
    T.ok(leather > 0 and thread > 0, "the plan needs Light Leather and Coarse Thread")
    CraftWorld.SetBag(LIGHT_LEATHER, leather)
    CraftWorld.SetBag(COARSE_THREAD, thread)
    T.advance(1)
    T.eq(#shownRows(area), 0, "materials the plan needs are never offered")
    T.eq(area:GetHeight(), emptyH, "the area keeps its height")

    -- Spare leather and thread, and plenty of a made intermediate.
    CraftWorld.SetBag(LIGHT_LEATHER, leather + SPARE)
    CraftWorld.SetBag(COARSE_THREAD, thread + SPARE)
    CraftWorld.SetBag(CURED_LIGHT_HIDE, 50)
    T.advance(1)
    local rows = shownRows(area)
    T.ok(#rows >= 1, "spare loot lists at least one craft")
    T.ok(#rows <= area.max, "no more rows than the area holds")
    T.eq(area:GetHeight(), emptyH, "the area keeps its height with rows")
    T.ok(not area.empty:IsShown(), "the muted line hides")
    T.eq(rowKeys(), planRows, "the plan's rows are unchanged")
    Visual.Check("impromptu rows")

    local guide = CP.Guides[LW]
    local inPlan = {}
    for _, row in ipairs(GT.ui.rows) do if row.spell then inPlan[row.spell] = true end end
    local spare = { [LIGHT_LEATHER] = SPARE, [COARSE_THREAD] = SPARE }
    local lastPts
    for _, r in ipairs(rows) do
        local it = r.item
        local recipe = guide.recipes[it.guideID]
        T.ok(recipe ~= nil, "a guide recipe: " .. tostring(it.guideID))
        T.ok(GT.ui.live.learned[it.guideID] == true, recipe.name .. " is learned")
        T.ok(CP.Guide.Chance(recipe, SKILL) > 0, recipe.name .. " still gives points")
        T.ok(not inPlan[it.guideID], recipe.name .. " is not a plan step")
        local cover = math.huge
        for _, pair in ipairs(recipe.reagents) do
            T.ok(pair[1] ~= CURED_LIGHT_HIDE, recipe.name .. " uses no made intermediate")
            if pair[1] ~= COARSE_THREAD then cover = math.min(cover, math.floor((spare[pair[1]] or 0) / pair[2])) end
        end
        T.ok(it.crafts >= 1 and it.crafts <= cover,
            ("%s: %d crafts within the spare loot's %d"):format(recipe.name, it.crafts, cover))
        T.ok(r.name:GetText() == recipe.name, "the row names " .. recipe.name)
        T.ok((r.info:GetText() or ""):find(tostring(it.crafts), 1, true) ~= nil, "the row shows its craft count")
        T.ok(r.craft:IsShown() and CP.Style.IsOn(r.craft), "the row's Craft button is on")
        T.ok(not lastPts or it.perCraft <= lastPts + 1e-9, "best points per craft first")
        lastPts = it.perCraft
    end

    -- Craft crafts the row's recipe as the card's buttons do, and picks nothing in the plan.
    local pickBefore = GT.PickKey()
    local first = rows[1]
    CraftWorld.Press(first.craft)
    local casts = CraftWorld.state.casts or {}
    local last = casts[#casts]
    T.ok(last ~= nil and (last.id == first.item.spell or last[1] == first.item.spell),
        "Craft asks for " .. tostring(first.item.spell))
    T.eq(GT.PickKey(), pickBefore, "the plan's pick is unchanged")
    CP.Crafting.Stop()
    CraftWorld.Close()
end)

T.test("with the window shut, an impromptu row's button opens the profession", function()
    local leather, thread
    scene()
    leather, thread = need(LIGHT_LEATHER), need(COARSE_THREAD)
    CraftWorld.SetBag(LIGHT_LEATHER, leather + SPARE)
    CraftWorld.SetBag(COARSE_THREAD, thread + SPARE)
    CraftWorld.Close()
    CP.Panel:Refresh()
    T.advance(1)
    local rows = shownRows(GT.ui.impromptu)
    T.ok(#rows >= 1, "the shut window still lists the spare-loot crafts")
    if rows[1] then
        T.eq(rows[1].craft.label:GetText(), "Open", "the button says Open, as the card's does")
    end
end)

T.test("vendor goods never limit an impromptu craft; the row says what to buy", function()
    scene()
    local leather = need(LIGHT_LEATHER)
    CraftWorld.SetBag(LIGHT_LEATHER, leather + SPARE)
    T.advance(1)
    local rows = shownRows(GT.ui.impromptu)
    T.ok(#rows >= 1, "spare leather lists a craft with no thread in the bags")
    local guide = CP.Guides[LW]
    local bought = false
    for _, r in ipairs(rows) do
        local text = r.info:GetText() or ""
        for _, pair in ipairs(guide.recipes[r.item.guideID].reagents) do
            if pair[1] == COARSE_THREAD then
                bought = true
                T.ok(text:find("buy " .. (r.item.crafts * pair[2]) .. " ", 1, true) ~= nil,
                    r.item.name .. " says what to buy: " .. text)
            end
        end
    end
    T.ok(bought, "a listed craft uses Coarse Thread")

    -- Vendor goods alone never list a recipe.
    CraftWorld.SetBag(LIGHT_LEATHER, 0)
    CraftWorld.SetBag(COARSE_THREAD, 500)
    T.advance(1)
    T.eq(#shownRows(GT.ui.impromptu), 0, "thread alone lists nothing")
    CraftWorld.Close()
end)

T.test("folded, the impromptu area stands between the header and the step card and counts in the height", function()
    local P = CP.Panel
    scene()
    local leather, thread = need(LIGHT_LEATHER), need(COARSE_THREAD)
    CraftWorld.SetBag(LIGHT_LEATHER, leather + SPARE)
    CraftWorld.SetBag(COARSE_THREAD, thread + SPARE)
    T.advance(1)
    local area = GT.ui.impromptu
    local openShown = #shownRows(area)
    T.ok(openShown >= 1, "spare loot lists a craft")
    World.set(CP.db, "windowCollapsed", true)
    P:Refresh()
    T.advance(1)
    T.ok(P.folded, "the window is folded")
    T.ok(area:IsShown(), "the area shows folded")
    T.eq(#shownRows(area), openShown, "with the same rows")
    local r = shownRows(area)[1]
    T.ok(r.craft:IsShown() and CP.Style.IsOn(r.craft), "and a Craft button")
    local d = GT.ui.details
    T.ok(area:GetBottom() >= d:GetTop() - 0.5, "the area sits above the step card")
    T.ok(not GT.ui.scroll:IsShown(), "still no step list")
    local without = 44 + (GT.ui.headerExtra or 0) + d:GetHeight()
    T.eq(GT.FoldedHeight(), without + area:GetHeight() + 8, "the folded height counts the area and its gap")
    Visual.Check("impromptu folded")
end)

-- Cooking: a meat, an egg and a fish recipe that are learned and still give points.
local COOK = 185
local COOK_SKILL = 40
local WOLF_MEAT, SMALL_EGG, SMALLFISH, BOAR_MEAT, SPICES = 2672, 6889, 6291, 769, 2678
local CHARRED, SPICED, EGG_BAKE, SMALLFISH_COOK, BOAR_COOK = 2538, 2539, 8604, 7751, 2540

local function cookScene(bags)
    Visual.begin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    DaylightWorld.begin({ craftWindow = false })
    CraftWorld.begin({
        professions = { [COOK] = { rank = COOK_SKILL, max = 75,
            known = { CHARRED, SPICED, BOAR_COOK, EGG_BAKE, SMALLFISH_COOK } } },
        bags = bags or {},
    })
    World.set(CP.db, "collect", false)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.Open(COOK)
    T.advance(1)
    CP.Panel.frame:Show()
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    T.advance(1)
end

local function byGuideID(rows)
    local out = {}
    for _, r in ipairs(rows) do out[r.item.guideID] = r end
    return out
end

T.test("Cooking: spare meat, an egg and a fish each list a craft; vendor spice says what to buy", function()
    cookScene()
    local area = GT.ui.impromptu
    T.ok(area ~= nil and area:IsShown(), "the Cooking guide has an impromptu area")
    if not area then return end
    T.eq(#shownRows(area), 0, "empty bags offer nothing")

    -- Meat: one plain recipe and one that also wants spice.
    CraftWorld.SetBag(WOLF_MEAT, 6)
    T.advance(1)
    local rows = byGuideID(shownRows(area))
    T.ok(rows[CHARRED] ~= nil, "Stringy Wolf Meat lists Charred Wolf Meat")
    T.ok(rows[SPICED] ~= nil, "Stringy Wolf Meat lists Spiced Wolf Meat")
    if rows[CHARRED] then
        T.eq(rows[CHARRED].item.crafts, 6, "six meat make six Charred Wolf Meat")
        T.ok(not (rows[CHARRED].info:GetText() or ""):find("buy", 1, true), "no spice needed, nothing to buy")
    end
    if rows[SPICED] then
        local item = rows[SPICED].item
        T.eq(#item.buy, 1, "one thing to buy")
        T.eq(item.buy[1].itemID, SPICES, "it is the spice")
        T.eq(item.buy[1].count, item.crafts, "one spice per craft")
        T.ok((rows[SPICED].info:GetText() or ""):find("buy " .. item.crafts .. " ", 1, true) ~= nil,
            "the row says buy " .. item.crafts)
    end

    -- Spice already in the bags is not bought again.
    CraftWorld.SetBag(SPICES, 50)
    T.advance(1)
    rows = byGuideID(shownRows(area))
    T.ok(rows[SPICED] ~= nil and #rows[SPICED].item.buy == 0, "spice in the bags needs no buying")

    -- An egg.
    CraftWorld.SetBag(WOLF_MEAT, 0)
    CraftWorld.SetBag(SPICES, 0)
    CraftWorld.SetBag(SMALL_EGG, 4)
    T.advance(1)
    rows = byGuideID(shownRows(area))
    T.ok(rows[EGG_BAKE] ~= nil, "a Small Egg lists Herb Baked Egg")
    if rows[EGG_BAKE] then
        T.eq(rows[EGG_BAKE].item.crafts, 4, "four eggs make four crafts")
        T.ok((rows[EGG_BAKE].info:GetText() or ""):find("buy 4 ", 1, true) ~= nil, "the row says to buy 4 spices")
    end

    -- A fish.
    CraftWorld.SetBag(SMALL_EGG, 0)
    CraftWorld.SetBag(SMALLFISH, 5)
    T.advance(1)
    rows = byGuideID(shownRows(area))
    T.ok(rows[SMALLFISH_COOK] ~= nil, "Raw Brilliant Smallfish lists Brilliant Smallfish")
    if rows[SMALLFISH_COOK] then T.eq(rows[SMALLFISH_COOK].item.crafts, 5, "five fish make five crafts") end

    -- Spice alone lists nothing.
    CraftWorld.SetBag(SMALLFISH, 0)
    CraftWorld.SetBag(SPICES, 200)
    T.advance(1)
    T.eq(#shownRows(area), 0, "spice alone lists nothing")
    CraftWorld.Close()
end)

T.test("Cooking: what the plan still needs is never offered", function()
    cookScene()
    local area = GT.ui.impromptu
    local boar = need(BOAR_MEAT)
    T.ok(boar > 0, "the Cooking plan needs Chunk of Boar Meat")
    CraftWorld.SetBag(BOAR_MEAT, boar)
    T.advance(1)
    T.eq(CP.Impromptu.Spare(BOAR_MEAT, boar), 0, "nothing of the boar meat is spare")
    T.eq(#shownRows(area), 0, "the plan's own meat lists nothing")

    -- Spare is only what lies beyond the need, and the plan's own step stays with the step card.
    CraftWorld.SetBag(BOAR_MEAT, boar + 3)
    T.advance(1)
    T.eq(CP.Impromptu.Spare(BOAR_MEAT, boar), 3, "three boar meat are spare")
    for _, r in ipairs(shownRows(area)) do
        T.ok(r.item.guideID ~= BOAR_COOK, "the plan's own step is left to the step card")
    end

    -- Wolf meat the plan does not need is offered in full.
    CraftWorld.SetBag(BOAR_MEAT, 0)
    CraftWorld.SetBag(WOLF_MEAT, need(WOLF_MEAT) + 2)
    T.advance(1)
    local rows = byGuideID(shownRows(area))
    T.ok(rows[CHARRED] ~= nil and rows[CHARRED].item.crafts == 2, "the two spare Wolf Meat are offered")
    CraftWorld.Close()
end)

T.test("All mode: a crafting card carries its best impromptu craft; none, no line and no height", function()
    cookScene()
    World.onEnd(function() CP.Window.SetMode("one") end)
    CraftWorld.SetBag(WOLF_MEAT, need(WOLF_MEAT) + 6)
    T.advance(1)
    local best = CP.Impromptu.List(GT.ui.live, 1)[1]
    T.ok(best ~= nil, "Single view has a best craft")
    CP.Window.SetMode("all")
    T.advance(1)
    local card = GT.ui.cardList[1]
    T.ok(card ~= nil, "Cooking has a card")
    if not (card and best) then return end
    local line = card.impLine or ""
    T.ok(line:find(best.name, 1, true) ~= nil, "the line names the craft: " .. line)
    T.ok(line:find(("x%d"):format(best.crafts), 1, true) ~= nil, "the line gives the count: " .. line)
    T.eq(card.impCount, best.crafts, "the button crafts the row's count")

    local btn = CreateFrame("Button", nil, UIParent)
    GT.InitCard(btn, card)
    T.ok(btn.impLine and btn.impLine:IsShown(), "the card shows the line")
    T.ok(btn.impBtn and btn.impBtn:IsShown(), "and its button")
    T.eq(btn.impBtn.label:GetText(), "Craft", "the open profession's button reads Craft")

    local plain = GT.Card(GT.ui.live)
    plain.impLine = nil
    T.eq(GT.CardHeight(card) - GT.CardHeight(plain), GT.ImpromptuHeight(), "the line adds its height")

    CraftWorld.SetBag(WOLF_MEAT, 0)
    T.advance(1)
    CP.Window.SetMode("one")
    CP.Window.SetMode("all")
    T.advance(1)
    local bare = GT.ui.cardList[1]
    T.eq(bare.impLine, nil, "nothing spare: no line")
    T.eq(bare.height, GT.CardHeight(plain), "and no extra height")
    GT.InitCard(btn, bare)
    T.ok(not btn.impLine:IsShown() and not btn.impBtn:IsShown(), "the card hides both")
    CraftWorld.Close()
end)
