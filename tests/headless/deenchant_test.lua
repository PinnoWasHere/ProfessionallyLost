-- The Enchanting coupling: with Enchanting on the character, the other guides lower a
-- craft's cost by what disenchanting it saves Enchanting. A setting turns it off, and each
-- step it shaped says so on its row and card (playtester reports on 1.0.0).

local CP = ProfLost
local ENCHANTING, TAILOR, LW, BS, ENG = 333, 197, 165, 164, 202
local LINEN, BOLT, GLOVES = 2589, 2963, 3840
local ELWYNN = 1429

-- A character with Enchanting 1/75 whose window was opened once, so its needs are saved,
-- and profession `line` at `rank`. `de` is the setting, nil for its default.
local function withEnchanting(line, rank, bags, de)
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 }, [line] = { rank = rank, max = 75 } },
                       bags = bags })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", de)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    T.ok(CP.charDB.gatherNeeds and CP.charDB.gatherNeeds[ENCHANTING], "Enchanting's needs are saved")
end

local function alone(line, rank, bags)
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [line] = { rank = rank, max = 75 } }, bags = bags })
    World.set(CP.db, "collect", true)
end

local function dump(plan)
    local out = {}
    for _, st in ipairs(plan or {}) do
        out[#out + 1] = ("%d-%d:%s:%d"):format(st.from, st.to, tostring(st.spell), st.crafts or 0)
    end
    return table.concat(out, ";")
end

-- The shut plan of `line` at `skill`, from a fresh saved plan.
local function shutPlan(line, skill)
    return dump(CP.Plan.Offline(CP.Guides[line], line, skill, 300, {}).plan)
end

-- The options row for each coupling setting, as Daylight UI's page gets it.
local function optionRow(key)
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, it in ipairs(g.items) do
            if it.key == key then return it end
        end
    end
end

T.test("options: a coupling row is hidden without its profession and shown with it", function()
    local COOKING, FISHING = 185, 356
    -- deEnchant always shows and greys out instead (uitextfix_test.lua).
    local cases = { { "fishCook", FISHING, COOKING } }
    for _, c in ipairs(cases) do
        local key, coupled, line = c[1], c[2], c[3]
        alone(line, 1)
        local row = optionRow(key)
        T.ok(row ~= nil and type(row.hidden) == "function", key .. " has a hidden function")
        T.eq(row.hidden(), true, key .. " hidden without " .. coupled)
        MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
        CraftWorld.begin({ professions = { [coupled] = { rank = 1, max = 75 }, [line] = { rank = 1, max = 75 } } })
        T.eq(optionRow(key).hidden(), false, key .. " shown with " .. coupled)
    end
    alone(TAILOR, 1)
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, it in ipairs(g.items) do
            local s = it.key and CP.Settings.Find(it.key)
            -- (A row with `when`, such as the Glowey's Recipes switches, hides by its own rule.)
            if s and (not s.couples or s.showAlways) and not s.when then T.eq(it.hidden, nil, it.key .. " is never hidden") end
        end
    end
end)

T.test("the setting: Guides group, on by default, greyed without Enchanting", function()
    local s = CP.Settings.Find("deEnchant")
    T.ok(s ~= nil, "a deEnchant setting")
    if not s then return end
    T.eq(s.group, "Guides")
    T.eq(s.kind, "toggle")
    T.eq(CP.DEFAULTS.deEnchant, true, "on by default")
    T.ok(type(s.desc) == "string" and #s.desc > 0 and #s.desc <= 220, "a short description")
    alone(TAILOR, 1)
    T.eq(s.disabled(function(k) return CP.db[k] end), true, "greyed without Enchanting")
    withEnchanting(TAILOR, 1)
    T.eq(s.disabled(function(k) return CP.db[k] end), false, "live with Enchanting")
end)

for _, line in ipairs({ TAILOR, LW, BS, ENG }) do
    T.test(CP.Guides[line].name .. ": with the setting off, Enchanting changes no plan", function()
        alone(line, 1)
        local want = shutPlan(line, 1)
        withEnchanting(line, 1, nil, false)
        T.eq(shutPlan(line, 1), want, "off: as without Enchanting")
        CP.Plan.Invalidate()
    end)
end

-- True when `plan` has a step on `spell`.
local function uses(plan, spell)
    for _, st in ipairs(plan or {}) do
        if st.spell == spell then return true end
    end
    return false
end

T.test("turning the setting off re-plans the open window without the gloves", function()
    withEnchanting(TAILOR, 1, { [LINEN] = 42 })
    CraftWorld.Open(TAILOR)
    T.advance(1)
    T.ok(uses(CP.Plan.Current().plan, GLOVES), "on: Heavy Linen Gloves for its dust")
    CP.Settings.Set("deEnchant", false)
    T.advance(1)
    T.ok(not uses(CP.Plan.Current().plan, GLOVES), "off: no gloves")
end)

T.test("a step the coupling shaped says so on its row and card, and its feeder says why", function()
    withEnchanting(TAILOR, 1, { [LINEN] = 42 })
    CraftWorld.Open(TAILOR)
    T.advance(1)
    local live = CP.Plan.Current()
    local rows = CP.GuideTab.RowsOf(live)
    local bolt, gloves
    for _, row in ipairs(rows) do
        if not row.side and row.spell == BOLT and not bolt then bolt = row end
        if not row.side and row.spell == GLOVES and not gloves then gloves = row end
    end
    T.ok(bolt and gloves, "bolts, then Heavy Linen Gloves")
    if not (bolt and gloves) then return end
    T.ok(gloves.forEnchanting == true, "the gloves step was chosen for Enchanting")
    T.ok(not bolt.forEnchanting, "bolts don't disenchant")
    local _, _, info = CP.GuideTab.RowTexts(gloves)
    T.ok(info:find(CP.GuideTab.DE_MARK, 1, true) ~= nil, "the gloves row's info: " .. info)
    local _, _, boltInfo = CP.GuideTab.RowTexts(bolt)
    T.ok(not boltInfo:find(CP.GuideTab.DE_MARK, 1, true), "the bolt row's info: " .. boltInfo)
    for _, row in ipairs(rows) do
        if row.spell and not row.forEnchanting and not (row.rank or row.train) then
            local _, _, i = CP.GuideTab.RowTexts(row)
            T.ok(not i:find(CP.GuideTab.DE_MARK, 1, true), row.recipe.name .. " is not marked: " .. i)
        end
    end

    CP.GuideTab.Pick(gloves)
    T.advance(0.5)
    local sale = CP.GuideTab.ui.details.sale:GetText() or ""
    T.ok(sale:find("^For Enchanting: disenchant these for Strange Dust x%d+$") ~= nil, "the gloves card: " .. sale)

    CP.GuideTab.Pick(bolt)
    T.advance(0.5)
    sale = CP.GuideTab.ui.details.sale:GetText() or ""
    T.ok(sale:find("^Keep %d+ for Heavy Linen Gloves.-, made to disenchant for Enchanting$") ~= nil, "the bolt card: " .. sale)
end)

T.test("with the setting off nothing is marked for Enchanting", function()
    withEnchanting(TAILOR, 1, { [LINEN] = 42 }, false)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    for _, row in ipairs(CP.GuideTab.RowsOf(CP.Plan.Current())) do
        T.ok(not row.forEnchanting and not row.keepForEnchanting, tostring(row.recipe and row.recipe.name))
    end
end)
