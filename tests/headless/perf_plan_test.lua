-- Plan work per event and per solve: with a profession window open, a bag change the
-- plan doesn't read costs no solve and no recipe read, and one solve prices, credits and
-- reads the player's skills once per item. The harness stubs collectgarbage to 0, so these
-- count calls instead of memory.

local CP = ProfLost
local LW, TAILOR, ENCHANTING, COOKING = 165, 197, 333, 185
local DUROTAR = 1411
local HEARTHSTONE = 6948      -- in no guide
local LINEN_BOLT = 2996       -- Tailoring's prep: a held count its plan reads
local LIGHT_LEATHER = 2318    -- Light Armor Kit's only material, in no prep or craft-only set

-- Counts Plan.Solve, Solver.Plan and recipe reads from now on.
local function counter()
    local c = { solves = 0, plans = 0, lists = 0, infos = 0, held = {} }
    local solve, plan = CP.Plan.Solve, CP.Solver.Plan
    World.set(CP.Plan, "Solve", function(...)
        c.solves = c.solves + 1
        return solve(...)
    end)
    World.set(CP.Solver, "Plan", function(guide, skill, learned, priceFn, allow, prefer, held, ...)
        c.plans = c.plans + 1
        c.held[#c.held + 1] = held
        return plan(guide, skill, learned, priceFn, allow, prefer, held, ...)
    end)
    local TS = C_TradeSkillUI
    local all, info = TS.GetAllRecipeIDs, TS.GetRecipeInfo
    World.set(TS, "GetAllRecipeIDs", function(...)
        c.lists = c.lists + 1
        return all(...)
    end)
    World.set(TS, "GetRecipeInfo", function(...)
        c.infos = c.infos + 1
        return info(...)
    end)
    return c
end

local function shown(c)
    return ("%d plan solves, %d Solver.Plan, %d lists, %d recipe reads"):format(c.solves, c.plans, c.lists, c.infos)
end

-- A character with `profs`, profession `line`'s window open and settled.
local function scene(line, profs, collect)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = profs })
    World.set(CP.db, "collect", collect ~= false)
    CraftWorld.Open(line)
    T.advance(2)
    T.ok(CP.Plan.Current() ~= nil, "the open profession's plan")
end

-- Steps and their "or" rows, every number exact.
local function dump(live)
    local out = {}
    for i, st in ipairs(live.plan or {}) do
        local side = live.sides and live.sides[i]
        local more = {}
        for _, m in ipairs(side and side.more or {}) do more[#more + 1] = tostring(m.spell) end
        out[#out + 1] = ("%d-%d:%s:%.17g:%.17g%s"):format(st.from, st.to, tostring(st.spell), st.crafts or 0,
            st.cost or 0, side and ("|" .. tostring(side.spell) .. ":" .. tostring(side.crafts) .. ":"
            .. table.concat(more, "+")) or "")
    end
    return table.concat(out, ";")
end

-- Bag events -------------------------------------------------------------------------

T.test("a bag change no plan reads costs no solve and no recipe read", function()
    scene(TAILOR, { [TAILOR] = 60 })
    local c = counter()
    CraftWorld.SetBag(HEARTHSTONE, 1)
    T.advance(2)
    for _ = 1, 3 do CP.Plan.Current() end
    T.eq(c.plans .. " solves, " .. c.infos .. " recipe reads, " .. c.lists .. " lists",
        "0 solves, 0 recipe reads, 0 lists", shown(c))
end)

T.test("a bag change of a prep item the plan reads solves once, with the new count", function()
    scene(TAILOR, { [TAILOR] = 60 })
    local c = counter()
    CraftWorld.SetBag(LINEN_BOLT, 5)
    T.advance(2)
    for _ = 1, 3 do CP.Plan.Current() end
    T.eq(c.solves, 1, "one plan solve (" .. shown(c) .. ")")
    T.eq(c.held[1] and c.held[1][LINEN_BOLT], 5, "the main solve holds the 5 bolts")
    local after = dump(CP.Plan.Current())
    CP.Plan.Invalidate()
    T.eq(dump(CP.Plan.Current()), after, "the plan is what a fresh solve gives")
end)

T.test("a bag change of a rare byproduct the plan reads solves once", function()
    scene(LW, { [LW] = 120 })
    local guide = CP.Guides[LW]
    local rare
    for item, info in pairs(guide.items) do
        if info[5] and not (rare and rare < item) then rare = item end
    end
    T.ok(rare ~= nil, "Leatherworking has a rare byproduct")
    local c = counter()
    CraftWorld.SetBag(rare, 4)
    T.advance(2)
    CP.Plan.Current()
    T.eq(c.solves, 1, "one plan solve (" .. shown(c) .. ")")
end)

T.test("the current step's craftable count follows the bags without a solve", function()
    scene(LW, { [LW] = 1 })
    local function current()
        for _, row in ipairs(CP.GuideTab.RowsOf(CP.Plan.Current())) do
            if row.current then return row end
        end
    end
    T.eq(current().spell, 2152, "Light Armor Kit leads")
    T.eq(current().craftable, 0, "nothing to make it from")
    local c = counter()
    CraftWorld.SetBag(LIGHT_LEATHER, 7)
    T.advance(2)
    T.eq(current().craftable, 7, "7 Light Leather make 7")
    local status = CP.GuideTab.ui.details.status:GetText() or ""
    T.ok(status:find("materials for 7", 1, true), "the drawn step card says so: " .. status)
    CraftWorld.SetBag(LIGHT_LEATHER, 3)
    T.advance(2)
    T.eq(current().craftable, 3, "3 left make 3")
    T.eq(c.plans .. " solves, " .. c.infos .. " recipe reads", "0 solves, 0 recipe reads", shown(c))
end)

-- What still solves -------------------------------------------------------------------

T.test("each change the solve reads gives a fresh plan", function()
    local cases = {
        { "a recipe learned", function()
            local g, known = CP.Guides[TAILOR], CraftWorld.state.profs[TAILOR].known
            local pick
            for id, r in pairs(g.recipes) do
                if not known[id] and r.src == "trainer" and r.learn <= 75 and not (pick and pick < id) then pick = id end
            end
            CraftWorld.Learn(TAILOR, pick)
        end },
        { "one recipe swapped for another, count unchanged", function()
            local g, known = CP.Guides[TAILOR], CraftWorld.state.profs[TAILOR].known
            local drop, add
            for id in pairs(known) do if not (drop and drop < id) then drop = id end end
            for id, r in pairs(g.recipes) do
                if not known[id] and r.src == "trainer" and r.learn <= 75 and not (add and add < id) then add = id end
            end
            -- A list update with the same ids keeps the list (it follows every craft), so
            -- the list is dropped by hand: the plan key alone must tell the two sets apart.
            known[drop], known[add] = nil, true
            CP.Professions.DropRecipes()
            T.fire("TRADE_SKILL_LIST_UPDATE")
        end },
        { "a skill-up", function()
            CraftWorld.SetSkill(TAILOR, 61)
            T.fire("CHAT_MSG_SKILL", "Your skill in Tailoring has increased to 61.")
        end },
        { "Gather it yourself turned off", function() World.set(CP.db, "collect", false) end },
        { "Fish for Cooking through its setting", function()
            World.set(CP.db, "fishCook", not CP.db.fishCook)
            CP.Settings.Find("fishCook").apply()
        end },
        { "Mogul's PricesChanged", function()
            MogulWorld.begin({ prices = { [2589] = 20 } })
            -- The login also places the window anchors; they go back where they were.
            for _, anchor in ipairs({ CP.Window.anchor, CP.GatherPanel.anchor }) do
                local points = {}
                for i = 1, anchor:GetNumPoints() do points[i] = { anchor:GetPoint(i) } end
                World.onEnd(function()
                    anchor:ClearAllPoints()
                    for _, pt in ipairs(points) do anchor:SetPoint(unpack(pt)) end
                end)
            end
            T.fire("PLAYER_LOGIN")
            MogulWorld.SetPrice(2589, 40)
            MogulWorld.PricesChanged()
        end },
        { "Plan.Invalidate", function() CP.Plan.Invalidate() end },
    }
    local got, want = {}, {}
    for _, case in ipairs(cases) do
        scene(TAILOR, { [TAILOR] = 60 })
        local c = counter()
        case[2]()
        T.advance(2)
        CP.Plan.Current()
        got[#got + 1] = case[1] .. ": " .. c.solves
        want[#want + 1] = case[1] .. ": 1"
        World.finish()
    end
    T.eq(table.concat(got, "; "), table.concat(want, "; "), "plan solves per change")
end)

T.test("a faction standing change re-solves a guide with reputation patterns", function()
    local reaction = 4
    World.patch("C_Reputation.GetFactionDataByID", function(id)
        return { factionID = id, name = "Faction " .. id, reaction = reaction }
    end)
    scene(LW, { [LW] = 250 }, false)
    local c = counter()
    CP.Plan.Current()
    T.eq(c.solves, 0, "nothing changed (" .. shown(c) .. ")")
    reaction = 5
    CP.Plan.Current()
    T.eq(c.solves, 1, "Honored everywhere (" .. shown(c) .. ")")
end)

-- Work inside one solve ---------------------------------------------------------------

-- Counts calls inside each Solver.Plan call: Disenchant.Yield by group, Shared.DECredit
-- by recipe, Sourcing.PlayerSkills, Scan.RealmKey, and the items each price function asked.
local function inside()
    local n = { solves = {} }
    local cur
    local plan = CP.Solver.Plan
    World.set(CP.Solver, "Plan", function(...)
        cur = { yields = {}, maxYield = 0, credits = {}, maxCredit = 0, skills = 0, realm = 0, items = {} }
        n.solves[#n.solves + 1] = cur
        local a, b = plan(...)
        cur = nil
        return a, b
    end)
    local yield = CP.Disenchant.Yield
    World.set(CP.Disenchant, "Yield", function(group)
        if cur then
            cur.yields[group] = (cur.yields[group] or 0) + 1
            cur.maxYield = math.max(cur.maxYield, cur.yields[group])
        end
        return yield(group)
    end)
    local credit = CP.Shared.DECredit
    World.set(CP.Shared, "DECredit", function(recipe, ...)
        if cur then
            cur.credits[recipe] = (cur.credits[recipe] or 0) + 1
            cur.maxCredit = math.max(cur.maxCredit, cur.credits[recipe])
        end
        return credit(recipe, ...)
    end)
    local skills = CP.Sourcing.PlayerSkills
    World.set(CP.Sourcing, "PlayerSkills", function()
        if cur then cur.skills = cur.skills + 1 end
        return skills()
    end)
    local realm = CP.Scan.RealmKey
    World.set(CP.Scan, "RealmKey", function()
        if cur then cur.realm = cur.realm + 1 end
        return realm()
    end)
    for _, name in ipairs({ "Get", "GetCollect", "Auction" }) do
        local fn = CP.Pricing[name]
        World.set(CP.Pricing, name, function(item, ...)
            if cur then cur.items[name .. item] = true end
            return fn(item, ...)
        end)
    end
    return n
end

local function worst(n)
    local w = { yield = 0, credit = 0, credits = 0, skills = 0, realmOver = -math.huge }
    for _, s in ipairs(n.solves) do
        local items = 0
        for _ in pairs(s.items) do items = items + 1 end
        w.yield = math.max(w.yield, s.maxYield)
        w.credit = math.max(w.credit, s.maxCredit)
        w.skills = math.max(w.skills, s.skills)
        w.realmOver = math.max(w.realmOver, s.realm - items)
        for _, k in pairs(s.credits) do w.credits = w.credits + k end
    end
    return w
end

for _, collect in ipairs({ true, false }) do
    for _, line in ipairs({ ENCHANTING, TAILOR }) do
        local label = ("%s with Enchanting known (%s)"):format(CP.Guides[line].name, collect and "collect" or "buy")
        T.test(label .. ": one solve yields, reads skills and files prices once each", function()
            MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
            CraftWorld.begin({ professions = { [ENCHANTING] = 60, [TAILOR] = 100 } })
            World.set(CP.db, "collect", collect)
            CraftWorld.Open(ENCHANTING)
            T.advance(2)
            CP.Plan.Current()
            CraftWorld.Close()
            T.advance(1)
            T.ok(CP.charDB.gatherNeeds and CP.charDB.gatherNeeds[ENCHANTING], "Enchanting's needs are saved")
            CraftWorld.Open(line)
            T.advance(2)
            local n = inside()
            CP.Plan.Invalidate()
            CP.Plan.Current()
            local w = worst(n)
            T.ok(#n.solves > 0, "solves ran")
            if line == TAILOR then T.ok(w.credits > 0, "Tailoring's greens are credited") end
            local seen = ("%d solves; per solve at most %d Disenchant.Yield of one group, %d DECredit of one "
                .. "recipe, %d PlayerSkills, %d RealmKey over the items priced"):format(#n.solves, w.yield, w.credit,
                w.skills, w.realmOver)
            T.ok(w.yield <= 1 and w.credit <= 1 and w.skills <= 1 and w.realmOver <= 0, seen)
        end)
    end
end

T.test("RealmKey follows the faction", function()
    World.patch("UnitGUID", function() return "Player-4440-0A1B2C3D" end)
    World.patch("UnitFactionGroup", function() return "Horde", "Horde" end)
    T.eq(CP.Scan.RealmKey(), "Server-4440-Horde")
    T.eq(CP.Scan.RealmKey(), "Server-4440-Horde")
    World.patch("UnitFactionGroup", function() return "Alliance", "Alliance" end)
    T.eq(CP.Scan.RealmKey(), "Server-4440-Alliance")
    World.patch("UnitGUID", function() return "Player-512-0A1B2C3D" end)
    T.eq(CP.Scan.RealmKey(), "Server-512-Alliance")
    World.patch("UnitGUID", function() return "Player-0-0A1B2C3D" end)
    T.eq(CP.Scan.RealmKey(), "Forever-Alliance", "no server id: the faction's Forever key")
end)

-- Plans unchanged ---------------------------------------------------------------------

-- Each scene's plan as the code before the per-solve memos gave it, each step past a rank's
-- cap cut at the cap (CLARITY-01). A pattern step's "or" rows come from known and trainer
-- recipes alone; a green one stands only where no such recipe is orange or yellow.
local SCENES = {
    { name = "Leatherworking 1", line = LW, profs = { [LW] = 1 }, collect = true,
      -- No Feathered Breastplate (10647) "or" row: its Cured Thick Hide is planned from stock only.
      want = "1-45:2152:50:40;45-51:2149:9:15.300000000000001;51-80:3756:31:80.600000000000023;80-93:2165:14:46.200000000000003;93-112:2167:23:80.500000000000014;112-121:2168:13:85.799999999999997;121-125:3764:4:46.400000000000006;125-130:23190:7:14.700000000000001|20649:7:3780;130-155:3780:29:147.89999999999998;155-160:3772:8:76.799999999999997|9198:5:;160-165:9201:5:81.5;165-175:9202:10:142|9201:10:;175-196:10487:21:107.09999999999999;196-210:10507:18:93.600000000000009;210-225:10548:15:216;225-235:19058:14:56;235-263:19049:30:198|10558:67:19058;263-280:19066:21:195.29999999999998;280-295:19082:19:518.70000000000005;295-300:16661:8:2042.4000000000001" },
    -- Tailoring: Bolt of Runecloth runs 205-215 and the silk and mageweave bolts to where their counts
    -- take the skill, since makers earn their points (decision 0008).
    { name = "Tailoring 150", line = TAILOR, profs = { [TAILOR] = 150 }, collect = true,
      -- Crimson Silk Vest (8791), not Long Silken Cloak (3861): its Mana Potion (3827) is limited stock (FDBSTOCK-01).
      want = "150-168:8786:20:1088|8489:30:8791;168-173:8791:6:434.40000000000003;173-180:8799:7:506.80000000000007;180-190:12061:12:170.39999999999998;190-205:12053:17:479.39999999999998;205-215:18401:17:136;215-240:18402:31:96.100000000000009;240-255:18409:21:245.69999999999999|18402:100:;255-260:18419:9:776.69999999999993;260-265:18423:9:202.5;265-300:18450:62:6231" },
    { name = "Tailoring 150, buy", line = TAILOR, profs = { [TAILOR] = 150 }, collect = false,
      want = "150-168:8786:20:150000|8489:30:8764+8791;168-175:8791:8:79200;175-180:8799:5:53500;180-190:12061:12:96000;190-194:12048:6:69000;194-205:12053:13:182000;205-215:18401:17:136000;215-218:12072:5:95000;218-238:18402:24:696000;238-260:18417:28:1260000|18402:104:;260-295:18450:47:3431188;295-300:18457:5:861000" },
    { name = "Enchanting 60", line = ENCHANTING, profs = { [ENCHANTING] = 60, [TAILOR] = 100 }, collect = true,
      want = "60-75:7420:16:25.600000000000001;75-90:7420:22:35.200000000000003;90-101:7457:11:35.200000000000003;101-130:7771:37:118.40000000000001;130-170:7863:48:307.20000000000005;170-192:13637:25:302.5;192-205:13661:14:204.40000000000001;205-226:13746:21:306.59999999999997;226-250:13815:32:467.19999999999999;250-270:25127:24:453.60000000000002|17180:30:;270-300:20017:34:1815.6000000000001|13937:160:13943" },
    { name = "Enchanting 60, buy", line = ENCHANTING, profs = { [ENCHANTING] = 60, [TAILOR] = 100 }, collect = false,
      want = "60-75:7420:16:12800;75-76:7420:2:1600;76-100:7426:26:20800;100-110:7745:10:8010;110-140:13419:31:31|7745:32:7861+13501;140-150:13536:10:10|13501:10:;150-185:13536:43:43|13501:59:13642+13644;185-210:13646:33:66|13659:27:13693+13695;210-215:13815:5:5;215-220:13836:5:10;220-225:13858:5:15;225-230:13887:5:15;230-235:13917:5:5;235-275:13931:48:144|13935:48:13937+13943;275-296:20017:23:138|13943:47:13948;296-300:20026:5:35|13948:13:" },
    { name = "Cooking 150", line = COOKING, profs = { [COOKING] = 150 }, collect = true,
      want = "150-175:3376:26:49.400000000000006|6500:27:;175-225:13028:52:31.199999999999999;225-235:13028:16:9.5999999999999996;235-275:20626:42:92.400000000000006|21175:85:;275-300:18245:25:27.500000000000004|21175:92:" },
    { name = "Tailoring 100 with Enchanting", line = TAILOR, profs = { [ENCHANTING] = 60, [TAILOR] = 100 }, collect = true, first = ENCHANTING,
      -- Double-stitched Woolen Shoulders (3848) and the silk shirts since a crafted green the client makes
      -- of a classic white disenchants for Enchanting's credit (STABLE-01). The "or" row is Crimson Silk Vest
      -- (8791) because Long Silken Cloak's Mana Potion is limited stock (FDBSTOCK-01).
      want = "100-127:3848:33:447.15000000000003;127-134:8760:8:118.50000000000003;134-140:8762:8:108.40000000000001;140-175:8786:41:557.60000000000002|8764:47:8791+8799;175-187:8799:14:712.77500000000009;187-205:12053:20:141;205-215:18401:17:136;215-240:18402:31:24.025000000000002;240-255:18409:21:61.424999999999997|18402:100:;255-260:18419:9:349.08749999999998;260-265:18423:9:202.5;265-300:18450:62:6231" },
    { name = "Tailoring 100 with Enchanting, buy", line = TAILOR, profs = { [ENCHANTING] = 60, [TAILOR] = 100 }, collect = false, first = ENCHANTING,
      want = "100-127:3848:33:46200;127-140:3852:19:43700;140-150:3865:17:85000;150-172:8786:25:187500|8489:30:8764+8791;172-180:8799:8:85600;180-190:12061:12:96000;190-194:12048:6:69000;194-205:12053:13:182000;205-215:18401:17:136000;215-218:12072:5:95000;218-238:18402:24:696000;238-260:18417:28:1260000|18402:104:;260-295:18450:47:3431188;295-300:18457:5:861000" },
    { name = "Tailoring 100 with Enchanting, buy at Mogul prices", line = TAILOR, profs = { [ENCHANTING] = 60, [TAILOR] = 100 }, collect = false, first = ENCHANTING,
      prices = { [10940] = 300, [10938] = 900, [10939] = 2500, [10998] = 1800, [11082] = 3000, [11083] = 600, [2589] = 20, [2996] = 150 },
      -- Double-stitched Woolen Shoulders (3848) as above (STABLE-01).
      want = "100-127:3848:33:11550;127-140:3852:19:30875;140-150:3865:17:85000;150-175:8786:31:183675|8764:37:8791+8799;175-180:8799:5:53500;180-190:12061:12:96000;190-194:12048:6:69000;194-205:12053:13:182000;205-215:18401:17:136000;215-218:12072:5:95000;218-238:18402:24:696000;238-260:18417:28:1260000|18402:104:;260-295:18450:47:3431188;295-300:18457:5:861000" },
}

for _, sc in ipairs(SCENES) do
    T.test("the plan for " .. sc.name .. " is unchanged", function()
        MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
        CraftWorld.begin({ professions = sc.profs })
        World.set(CP.db, "collect", sc.collect)
        if sc.prices then MogulWorld.begin({ prices = sc.prices }) end
        if sc.first then
            CraftWorld.Open(sc.first)
            T.advance(2)
            CP.Plan.Current()
            CraftWorld.Close()
            T.advance(1)
        end
        CraftWorld.Open(sc.line)
        T.advance(2)
        T.eq(dump(CP.Plan.Current()), sc.want)
    end)
end
