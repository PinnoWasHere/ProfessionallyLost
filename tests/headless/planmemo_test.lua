-- The plan is a function of the character's state: a solve leans on the last plan only
-- where the state moved on, so solving one state again gives the same plan, a setting
-- turned off and on restores the guide, and a plan remembered under other settings is
-- not leaned on.

local CP = ProfLost
local ENCHANTING, TAILOR = 333, 197
local LINEN = 2589
local DUROTAR, ELWYNN = 1411, 1429
local LINES = { 129, 164, 165, 171, 185, 197, 202, 333 }

local function dump(live)
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        local kind = row.rank and "rank" or row.train and "train" or row.side and "or" or "step"
        out[#out + 1] = ("%s:%s-%s:%s:%s"):format(kind, tostring(row.at or row.from), tostring(row.to),
            tostring(row.spell), tostring(row.crafts))
    end
    return table.concat(out, ";")
end

local function firstDiff(a, b)
    local pa, pb = {}, {}
    for part in a:gmatch("[^;]+") do pa[#pa + 1] = part end
    for part in b:gmatch("[^;]+") do pb[#pb + 1] = part end
    for i = 1, math.max(#pa, #pb) do
        if pa[i] ~= pb[i] then return ("row %d: %s | %s"):format(i, tostring(pa[i]), tostring(pb[i])) end
    end
    return "same"
end

-- A fresh solve of the open window, as the simulator's `fresh` check asks for one.
local function resolve()
    CP.Plan.Invalidate()
    return dump(CP.Plan.Current())
end

-- Crafts the current step `n` times, one cast each, so the saved plan has a history.
local function work(n)
    for _ = 1, n do
        local live = CP.Plan.Current()
        local st = live.plan and live.plan[1]
        if not (st and st.spell and live.learned[st.spell]) then return end
        local r = live.guide.recipes[st.spell]
        for _, pair in ipairs(r.reagents) do CraftWorld.SetBag(pair[1], CraftWorld.Bag(pair[1]) + pair[2]) end
        C_TradeSkillUI.CraftRecipe(st.spell, 1)
        CraftWorld.Cast()
        T.advance(0.2)
    end
end

for _, collect in ipairs({ true, false }) do
    T.test(("a solve of the same state draws the same plan again (%s)"):format(collect and "collect" or "buy"), function()
        local bad = {}
        for _, line in ipairs(LINES) do
            for _, skill in ipairs({ 1, 60, 130, 200 }) do
                MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
                CraftWorld.begin({ professions = { [line] = { rank = skill } } })
                World.set(CP.db, "collect", collect)
                CraftWorld.Open(line)
                T.advance(1)
                work(4)
                local first = resolve()
                for i = 2, 4 do
                    local again = resolve()
                    if again ~= first then
                        bad[#bad + 1] = ("%s %d, solve %d: %s"):format(CP.Guides[line].name, skill, i, firstDiff(first, again))
                        break
                    end
                end
                World.finish()
            end
        end
        T.eq(#bad, 0, table.concat(bad, "\n"))
    end)
end

T.test("Gather it yourself turned off and on restores the guide", function()
    local bad = {}
    for _, line in ipairs(LINES) do
        MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
        CraftWorld.begin({ professions = { [line] = { rank = 60 } } })
        World.set(CP.db, "collect", true)
        CraftWorld.Open(line)
        T.advance(1)
        work(4)
        local before = resolve()
        CP.Settings.Set("collect", false)
        T.advance(1)
        resolve()
        resolve()
        CP.Settings.Set("collect", true)
        T.advance(1)
        local back = resolve()
        if back ~= before then bad[#bad + 1] = CP.Guides[line].name .. ": " .. firstDiff(before, back) end
        World.finish()
    end
    T.eq(#bad, 0, table.concat(bad, "\n"))
end)

T.test("Plan for Enchanting turned off and on restores Tailoring's guide", function()
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 }, [TAILOR] = { rank = 1, max = 75 } },
                       bags = { [LINEN] = 42 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    local coupled = resolve()
    CP.Settings.Set("deEnchant", false)
    T.advance(1)
    local plain = resolve()
    T.ok(plain ~= coupled, "off: another plan")
    CP.Settings.Set("deEnchant", true)
    T.advance(1)
    T.eq(resolve(), coupled, "on again: the coupled plan, " .. firstDiff(coupled, resolve()))
end)

T.test("a plan remembered under other settings is not leaned on", function()
    -- Tailoring 1 with 42 Linen Cloth: alone, the plan Enchanting's credit leaves behind
    -- would hold its bolts 1-25; a plan made under the setting off starts fresh.
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 1, max = 75 } }, bags = { [LINEN] = 42 } })
    World.set(CP.db, "collect", true)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    local fresh = resolve()
    World.finish()

    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 }, [TAILOR] = { rank = 1, max = 75 } },
                       bags = { [LINEN] = 42 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    resolve()
    CP.Settings.Set("deEnchant", false)
    T.advance(1)
    local off = resolve()
    T.eq(off, fresh, "off: the plan without Enchanting, " .. firstDiff(fresh, off))
end)
