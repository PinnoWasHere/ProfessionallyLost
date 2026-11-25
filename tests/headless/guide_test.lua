-- Guide engine against the generated Leatherworking guide.

local CP = ProfLost
local G = CP.Guide

local function lw() return CP.Guides[165] end

T.test("every generated guide loads with steps and recipes", function()
    local n = 0
    for _, g in pairs(CP.Guides) do
        n = n + 1
        T.ok(#g.steps > 0, g.name .. " has steps")
        for _, st in ipairs(g.steps) do
            if st.spell then T.ok(g.recipes[st.spell] ~= nil, g.name .. " step recipe " .. st.spell) end
        end
    end
    T.eq(n, 8)
end)

T.test("no trainer recipe is learned after it turns yellow", function()
    for _, g in pairs(CP.Guides) do
        for spell, r in pairs(g.recipes) do
            if r.src == "trainer" then
                T.ok(r.learn <= r.yellow, ("%s %d (%s): learn %d, yellow %d"):format(g.name, spell, r.name, r.learn, r.yellow))
            end
        end
    end
end)

-- Pending rank books only; trainer and quest ranks (Artisan First Aid) have their own tests.
local function books(pending)
    local out = {}
    for _, p in ipairs(pending) do
        if p.rank.item then out[#out + 1] = p end
    end
    return out
end

T.test("First Aid asks for the Expert book before the step that passes 150", function()
    local fa = CP.Guides[129]
    local pending = books(G.PendingRanks(fa, 150, fa.steps))
    T.eq(#pending, 1)
    T.eq(pending[1].rank.item, 16084)
    local before = fa.steps[pending[1].before]
    T.ok(before.to > 150, "book sits before the step that crosses the cap")
    T.ok(pending[1].before == 1 or fa.steps[pending[1].before - 1].to <= 150, "and not later")
end)

T.test("the Expert book disappears once the cap is raised", function()
    local fa = CP.Guides[129]
    T.eq(#books(G.PendingRanks(fa, 225, fa.steps)), 0)
    T.eq(#G.PendingRanks(fa, 300, fa.steps), 0, "Artisan done too")
    T.eq(#books(G.PendingRanks(CP.Guides[165], 150, CP.Guides[165].steps)), 0, "Leatherworking trains Expert: no book")
end)

T.test("steps cover the guide without overlaps or holes", function()
    for _, g in pairs(CP.Guides) do
        for i = 2, #g.steps do
            T.eq(g.steps[i].from, g.steps[i - 1].to, g.name .. " step " .. i)
        end
    end
end)

T.test("chance follows yellow and grey", function()
    local kit = lw().recipes[2152]  -- Light Armor Kit, yellow 30, grey 60
    T.eq(G.Chance(kit, 10), 1)
    T.eq(G.Chance(kit, 45), 0.5)
    T.eq(G.Chance(kit, 60), 0)
end)

T.test("skill 1 starts on Light Armor Kit, learned with the profession", function()
    local cur = G.Current(lw(), 1, { [2152] = true })
    T.eq(cur.step.spell, 2152)
    T.ok(cur.learned)
    T.eq(G.LearnText(cur.recipe), "Learned with the profession")
end)

T.test("mid-step skill shortens the remaining crafts", function()
    local full = G.Current(lw(), 1, {})
    local late = G.Current(lw(), 40, {})
    T.eq(late.step.spell, full.step.spell)
    T.ok(late.crafts < full.crafts)
    T.eq(late.from, 40)
end)

T.test("an unlearned trainer recipe says where to learn it", function()
    local cur = G.Current(lw(), 60, {})
    T.ok(not cur.learned)
    T.ok(cur.recipe.src == "trainer" or cur.recipe.src == "vendor")
    T.ok(G.LearnText(cur.recipe):find("skill " .. cur.recipe.learn) ~= nil)
end)

T.test("past the last step there is no current step", function()
    local last = lw().steps[#lw().steps]
    T.eq(G.Current(lw(), last.to, {}), nil)
end)

T.test("For finds a guide by child id, base id or name", function()
    T.eq(G.For({ ids = { 2999, 165 } }).name, "Leatherworking")
    T.eq(G.For({ ids = { 1 }, name = "First Aid" }).name, "First Aid")
    T.eq(G.For({ ids = { 1 }, name = "Nope" }), nil)
end)

T.test("Guide tab shows the current step for a stubbed Leatherworking", function()
    World.patch("C_TradeSkillUI.GetBaseProfessionInfo", function()
        return { professionID = 165, professionName = "Leatherworking", skillLevel = 75, skillModifier = 0, maxSkillLevel = 150 }
    end)
    World.patch("C_TradeSkillUI.GetChildProfessionInfo", function() return { professionID = 0 } end)
    World.patch("C_TradeSkillUI.GetAllRecipeIDs", function() return { 2152, 3756 } end)
    World.patch("C_TradeSkillUI.GetRecipeInfo", function(id)
        return { recipeID = id, name = id == 2152 and "Light Armor Kit" or "Embossed Leather Gloves",
                 relativeDifficulty = id == 2152 and 3 or 1, learned = true, canSkillUp = true, numSkillUps = 1 }
    end)
    World.patch("C_TradeSkillUI.GetCraftableCount", function() return 0 end)
    World.patch("C_TradeSkillUI.IsTradeSkillLinked", function() return false end)
    World.patch("C_TradeSkillUI.IsTradeSkillGuild", function() return false end)
    World.patch("C_TradeSkillUI.IsNPCCrafting", function() return false end)
    CP.Panel.frame:Show()
    CP.Panel:Refresh()
    local cur = G.Current(lw(), 75, { [2152] = true, [3756] = true })
    T.eq(cur.step.spell, 3756)
    T.ok(cur.learned)
end)

T.test("Guide tab shows the Expert book first for First Aid at 140 / 150", function()
    World.patch("C_TradeSkillUI.GetBaseProfessionInfo", function()
        return { professionID = 129, professionName = "First Aid", skillLevel = 140, skillModifier = 0, maxSkillLevel = 150 }
    end)
    World.patch("C_TradeSkillUI.GetChildProfessionInfo", function() return { professionID = 0 } end)
    World.patch("C_TradeSkillUI.GetAllRecipeIDs", function() return { 3278 } end)
    World.patch("C_TradeSkillUI.GetRecipeInfo", function(id)
        return { recipeID = id, name = "Heavy Wool Bandage", relativeDifficulty = 1, learned = true, canSkillUp = true, numSkillUps = 1 }
    end)
    World.patch("C_TradeSkillUI.GetCraftableCount", function() return 0 end)
    World.patch("C_TradeSkillUI.IsTradeSkillLinked", function() return false end)
    World.patch("C_TradeSkillUI.IsTradeSkillGuild", function() return false end)
    World.patch("C_TradeSkillUI.IsNPCCrafting", function() return false end)
    CP.Panel.frame:Show()
    T.ok(pcall(CP.Panel.Refresh, CP.Panel), "refresh with a pending book row")
end)

T.test("no guide or live plan goes past 300, the top skill in Forever", function()
    local price = function(_, g) return g and g[1] > 0 and g[1] or 1 end
    for _, g in pairs(CP.Guides) do
        T.eq(g.steps[#g.steps].to, 300, g.name .. " ends at 300")
        local plan = CP.Solver.Plan(g, 1, {}, price)
        T.ok(plan[#plan].to <= 300, g.name .. " live plan stops by 300")
    end
end)

T.test("only rows with somewhere to go get a waypoint pin", function()
    local g = lw()
    local trainerRecipe = g.recipes[2160]  -- Embossed Leather Vest, from a trainer
    T.eq(select(2, G.WaypointFor({ recipe = trainerRecipe, learned = false })), "trainer")
    T.eq(G.WaypointFor({ recipe = trainerRecipe, learned = true }), nil, "a learned recipe has no pin")
    T.eq(select(2, G.WaypointFor({ train = { recipes = { trainerRecipe } } })), "trainer")
    T.eq(select(2, G.WaypointFor({ rank = CP.Guides[129].ranks[2] })), "book vendor", "the Expert book")
    T.eq(G.WaypointFor({ recipe = { name = "No NPC", npcs = {} }, learned = false }), nil, "no known NPC, no pin")
end)

T.test("a waypoint pin replaces the current waypoint without asking", function()
    local placed
    World.patch("UnitFactionGroup", function() return "Horde", "Horde" end)
    World.patch("C_Map.GetBestMapForUnit", function() return nil end)
    World.patch("C_Map.HasUserWaypoint", function() return true end)
    World.patch("StaticPopup_Show", function() error("no prompt expected") end)
    World.patch("C_Map.GetMapPosFromWorldPos", function() return 1413, { GetXY = function() return 0.5, 0.5 end } end)
    World.patch("C_Map.GetMapInfoAtPosition", function() return nil end)
    World.patch("C_Map.GetMapInfo", function() return { mapType = 3, mapID = 1413, name = "The Barrens" } end)
    World.patch("C_Map.CanSetUserWaypointOnMap", function() return true end)
    World.patch("C_Map.SetUserWaypoint", function(p) placed = p end)
    World.patch("C_SuperTrack.SetSuperTrackedUserWaypoint", function() end)
    CP.Waypoint.ToRecipe(lw(), lw().recipes[2160])
    T.ok(placed ~= nil, "placed straight away")
end)

T.test("gathered materials set the reach; the info says what vendor goods to buy", function()
    -- In-game: Gray Leather Boots (4 Medium Leather, 2 Fine Thread, 1 Gray Dye) with
    -- 15 Medium Leather and no thread or dye.
    local g = lw()
    local reagents = {
        { itemID = 2319, name = "Medium Leather", need = 4, have = 15 },
        { itemID = 2321, name = "Fine Thread", need = 2, have = 0 },
        { itemID = 4340, name = "Gray Dye", need = 1, have = 0 },
    }
    T.ok(g.items[2321][2] and g.items[4340][2], "thread and dye are vendor goods")
    local reach, buy = G.VendorTopUp(g, reagents, 11)
    T.eq(reach, 3, "15 Medium Leather cover 3 crafts")
    T.eq(#buy, 2)
    -- The buy covers the whole step (owner, 2026-11-18), not only the 3 crafts in reach.
    T.eq(buy[1].name .. " " .. buy[1].count, "Fine Thread 22")
    T.eq(buy[2].name .. " " .. buy[2].count, "Gray Dye 11")

    reagents[1].have = 100
    reagents[2].have = 30
    local reach2, buy2 = G.VendorTopUp(g, reagents, 11)
    T.eq(reach2, 11, "capped at the step's crafts")
    T.eq(#buy2, 1, "only the dye is short")
    T.eq(buy2[1].count, 11)
end)

T.test("Lean Wolf Steak's roaming vendor gets a waypoint and says where it roams", function()
    local guide = ProfLost.Guides[185]
    local r = guide.recipes[15853]
    T.eq(r.npcs and r.npcs[1], 12246, "Super-Seller 680 sells the pattern")
    T.eq(guide.npcs[12246][4], "Desolace")
    local target = ProfLost.Waypoint.Nearest(r.npcs, guide.npcs, "H", 1, -1000, 2000)
    T.eq(target.name, "Super-Seller 680")
    T.eq(target.roams, "Desolace")
    T.eq(ProfLost.Waypoint.Describe(target), "roams Desolace")
    T.ok(ProfLost.Guide.WaypointFor({ recipe = r, learned = false }) ~= nil, "the step has a waypoint")
end)

T.test("seasonal recipes (Winter Veil) never become guide steps", function()
    local cooking = ProfLost.Guides[185]
    T.eq(cooking.recipes[21143], nil, "Gingerbread Cookie")
    T.eq(cooking.recipes[21144], nil, "Egg Nog")
    for _, guide in pairs(ProfLost.Guides) do
        for _, st in ipairs(guide.steps) do
            local r = st.spell and guide.recipes[st.spell]
            T.ok(not r or r.src ~= "seasonal", guide.name .. ": " .. tostring(r and r.name))
            for _, alt in ipairs(st.alt or {}) do
                T.ok(guide.recipes[alt] == nil or guide.recipes[alt].src ~= "seasonal")
            end
        end
    end
end)

T.test("Brown Linen Robe is green at 67 in every colour reader, as the game's window shows it", function()
    local r = ProfLost.Guides[197].recipes[7623]
    T.eq(r.yellow + r.grey, 135, "yellow 50, grey 85")
    local P = ProfLost.Professions
    T.eq(P.DifficultyAt(r, 66), P.YELLOW, "yellow at 66")
    T.eq(P.DifficultyAt(r, 67), P.GREEN, "green at 67")
    T.eq(ProfLost.Solver.GreenFrom(r), 67, "the skill it turns green")
    T.ok(ProfLost.Solver.IsGreen(r, 67), "the planner sees it green at 67")
    T.ok(not ProfLost.Solver.IsGreen(r, 66), "and yellow at 66")
end)
