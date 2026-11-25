-- Faction and material filters against the generated Leatherworking guide.

local CP = ProfLost
local lw = CP.Guides[165]
local HERBALIST_GLOVES = 9146   -- pattern sold only by an Alliance vendor; needs Kingsblood

local function itemClasses(map)
    World.patch("C_Item.GetItemInfoInstant", function(id)
        local c = map[id]
        if c then return id, "", "", "", 0, c[1], c[2] end
        return id, "", "", "", 0, 15, 0
    end)
end

T.test("an Alliance-only vendor pattern is not learnable for Horde", function()
    local r = lw.recipes[HERBALIST_GLOVES]
    T.ok(not CP.Sourcing.CanLearn(lw, HERBALIST_GLOVES, r, {}, "H"))
    T.ok(CP.Sourcing.CanLearn(lw, HERBALIST_GLOVES, r, {}, "A"))
    T.ok(CP.Sourcing.CanLearn(lw, HERBALIST_GLOVES, r, { [HERBALIST_GLOVES] = true }, "H"), "known recipes stay usable")
end)

T.test("herbs need Herbalism; vendor stock and cloth need nothing", function()
    itemClasses({ [3356] = { 7, 9 }, [2318] = { 7, 6 }, [2589] = { 7, 5 } })
    T.eq(CP.Sourcing.GatherSkill(lw, 3356), 182)        -- Kingsblood
    T.eq(CP.Sourcing.GatherSkill(lw, 2318), 393)        -- Light Leather
    T.eq(CP.Sourcing.GatherSkill(lw, 2589), nil)        -- Linen Cloth
    T.eq(CP.Sourcing.GatherSkill({ items = { [2320] = { 10, true } } }, 2320), nil)  -- vendor thread
end)

T.test("fish need Fishing whatever the client files them under", function()
    local alc = CP.Guides[171]
    -- Forever files Oily Blackmouth as Trade Goods > Other (7, 11).
    itemClasses({ [6358] = { 7, 11 }, [6359] = { 7, 11 }, [13422] = { 7, 11 }, [2447] = { 7, 9 },
                  [3820] = { 7, 9 }, [7070] = { 7, 10 } })
    T.eq(CP.Sourcing.GatherSkill(alc, 6358), 356)       -- Oily Blackmouth
    T.eq(CP.Sourcing.GatherSkill(alc, 6359), 356)       -- Firefin Snapper
    T.eq(CP.Sourcing.GatherSkill(alc, 13422), 356)      -- Stonescale Eel
    T.eq(CP.Sourcing.GatherSkill(alc, 2447), 182)       -- Peacebloom stays a herb
    T.eq(CP.Sourcing.GatherSkill(alc, 7070), nil)       -- Elemental Water drops from elementals too
    T.ok(CP.Sourcing.CanGet(alc, 3820, { [182] = true }), "Stranglekelp is picked")
    T.ok(CP.Sourcing.CanGet(alc, 3820, { [356] = true }), "or fished")
    local oil = alc.recipes[7836]
    T.ok(not CP.Sourcing.CanGather(alc, oil, { [171] = true, [182] = true }))
    T.ok(CP.Sourcing.CanGather(alc, oil, { [171] = true, [356] = true }))
end)

T.test("collecting, fish recipes leave the main path and show as or-rows", function()
    local alc = CP.Guides[171]
    itemClasses({ [6358] = { 7, 11 }, [6359] = { 7, 11 }, [13422] = { 7, 11 } })
    World.patch("UnitFactionGroup", function() return "Horde", "Horde" end)
    World.patch("GetProfessions", function() return 1, 2 end)
    World.patch("GetProfessionInfo", function(i)
        if i == 1 then return "Alchemy", 0, 1, 300, 0, 0, 171 end
        return "Fishing", 0, 100, 150, 0, 0, 356
    end)
    local collect, fc, info = CP.db.collect, CP.db.fishCook, C_SkillInfo.GetSkillLineInfoByID
    CP.db.collect, CP.db.fishCook = true, true

    -- Fishing at 100 with the pairing on: fish come nearly free, so the fish plan wants them.
    C_SkillInfo.GetSkillLineInfoByID = function(id)
        if id == 356 then return { rank = 100, maxRank = 150, skillLineID = 356 } end
        return info(id)
    end
    local ok, err = pcall(function()
        local live = CP.Plan.Offline(alc, "fishaside", 1, 300, {})
        for _, st in ipairs(live.plan) do
            local r = st.spell and alc.recipes[st.spell]
            T.ok(not (r and CP.Plan.UsesFish(alc, r)), "main path without fish: " .. (r and r.name or ""))
        end
        live.sides, live.dead = {}, {}
        CP.Plan.AddFallbacks(live)
        local fishSides = {}
        for i, side in pairs(live.sides) do
            if side.withFish then
                T.ok(CP.Plan.UsesFish(alc, side.recipe), side.recipe.name .. " is a fish recipe")
                T.ok(side.spell ~= live.plan[i].spell, "an or-row is never the step itself")
                fishSides[#fishSides + 1] = side.recipe.name
            end
        end
        T.ok(#fishSides > 0, "some fish or-rows")
        for i, side in pairs(live.sides) do
            T.ok(side.spell ~= live.plan[i].spell, "no or-row repeats its step: " .. side.recipe.name)
        end
    end)
    CP.db.collect, CP.db.fishCook, C_SkillInfo.GetSkillLineInfoByID = collect, fc, info
    T.ok(ok, err)
end)

T.test("a Horde leatherworker-skinner plan skips Herbalist's Gloves", function()
    itemClasses({ [3356] = { 7, 9 }, [2318] = { 7, 6 }, [2319] = { 7, 6 }, [4234] = { 7, 6 } })
    World.patch("UnitFactionGroup", function() return "Horde", "Horde" end)
    World.patch("GetProfessions", function() return 1, 2 end)
    World.patch("GetProfessionInfo", function(i)
        if i == 1 then return "Leatherworking", 0, 100, 150, 0, 0, 165 end
        return "Skinning", 0, 100, 150, 0, 0, 393
    end)
    local price = function(_, g) return g and g[1] > 0 and g[1] or 1 end
    local allow = CP.Sourcing.Filter(lw, {}, true)
    T.ok(not allow(HERBALIST_GLOVES, lw.recipes[HERBALIST_GLOVES]))
    for _, st in ipairs(CP.Solver.Plan(lw, 100, {}, price, allow)) do
        T.ok(st.spell ~= HERBALIST_GLOVES, "step at " .. st.from)
    end
end)

T.test("a crafted material needs one of the professions that make it", function()
    -- Nimble Leather Gloves need an Elixir of Minor Agility (Alchemy).
    itemClasses({ [2319] = { 7, 6 } })
    local lwSkin = { [165] = true, [393] = true }
    T.ok(not CP.Sourcing.CanGet(lw, 2457, lwSkin), "no Alchemy, no elixir")
    T.ok(CP.Sourcing.CanGet(lw, 2457, { [171] = true }), "an alchemist can make it")
    T.ok(CP.Sourcing.CanGet(lw, 2319, { [393] = true }), "Medium Leather: skinned")
    T.ok(CP.Sourcing.CanGet(lw, 2319, { [165] = true }), "Medium Leather: or made from Light Leather")
    T.ok(not CP.Sourcing.CanGather(lw, lw.recipes[9074], lwSkin), "Nimble Leather Gloves are out")
end)

T.test("Level-as-you-go leaves Nimble Leather Gloves out for a leatherworker-skinner", function()
    itemClasses({ [2318] = { 7, 6 }, [2319] = { 7, 6 }, [4234] = { 7, 6 } })
    World.patch("UnitFactionGroup", function() return "Horde", "Horde" end)
    World.patch("GetProfessions", function() return 1, 2 end)
    World.patch("GetProfessionInfo", function(i)
        if i == 1 then return "Leatherworking", 0, 100, 150, 0, 0, 165 end
        return "Skinning", 0, 100, 150, 0, 0, 393
    end)
    local allow = CP.Sourcing.Filter(lw, {}, true)
    for _, st in ipairs(CP.Solver.Plan(lw, 94, { [2165] = true }, CP.Pricing.GetCollect, allow)) do
        T.ok(st.spell ~= 9074, "no Nimble Leather Gloves at " .. st.from)
    end
end)
