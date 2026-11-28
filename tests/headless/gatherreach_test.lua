-- The guide counts a gathered material only once the gathering skill and the character's level
-- reach it (owner, 2026-11-27): Leatherworking's Green Whelp Bracers (165-175) said "Your Skinning
-- gathers the Green Whelp Scale this uses" at Skinning 165. Real data: Adolescent Whelp (34-35) and
-- Dreaming Whelp (35-36) skin Green Whelp Scale at 20.9% and 19.3% (cMaNGOS skinning loot 740 and
-- 741). Skinning a level 34 corpse takes 170 (Gather.CorpseSkill), and Farm takes a creature at most
-- Gather.FARM_SAFE_LEVELS (3) above the character, so the whelps need level 31.

local CP = ProfLost
local LW, SKIN = 165, 393
local SCALE, BRACERS = 7392, 9202
local SWAMP = 1435

-- Green Whelp Scale, Thick Leather and Rugged Leather answer as Leather; nothing else of the guide
-- is Skinning's.
local LEATHER = { [SCALE] = true, [4304] = true, [8170] = true }
local function classes()
    World.patch("C_Item.GetItemInfoInstant", function(id)
        if LEATHER[id] then return id, "", "", "", 0, 7, 6 end
        return id, "", "", "", 0, 15, 0
    end)
end

local function character(skin, level)
    MapWorld.begin({ zone = SWAMP, level = level, side = "Alliance" })
    CraftWorld.begin({ professions = { [LW] = { rank = 165, max = 225 }, [SKIN] = { rank = skin, max = 225 } } })
    World.set(CP.db, "collect", true)
    classes()
    CP.Plan.Invalidate()
end

local function allowed(spell)
    local guide = CP.Guides[LW]
    local allow = CP.Sourcing.Filter(guide, {}, true, CP.Sourcing.PlayerSkills(), CP.Sourcing.PlayerReach())
    return allow(spell, guide.recipes[spell])
end

-- The Leatherworking guide's rows and their card lines from a solve with the window open.
local function rows()
    CraftWorld.Open(LW)
    T.advance(0.5)
    local live = CP.Plan.Current()
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        out[#out + 1] = { row = row, cause = CP.GuideTab.CauseText(row) or "" }
    end
    CraftWorld.Close()
    return out, live
end

T.test("Skinning 165: Green Whelp Bracers is not planned on a scale the skill can't skin", function()
    character(165, 38)
    T.eq(CP.Gather.CorpseSkill(34), 170, "a level 34 corpse takes Skinning 170")
    World.set(CP.charDB, "lastPlan", nil)
    World.set(CP.charDB, "committed", nil)
    for _, r in ipairs(rows()) do
        T.ok(not r.cause:find("Green Whelp Scale", 1, true), "no card says Skinning gathers it: " .. r.cause)
        if r.row.spell == BRACERS and not r.row.side then
            T.ok(false, ("Green Whelp Bracers %d-%d leans on Skinning"):format(r.row.from, r.row.to))
        end
    end
    T.ok(not CP.Sourcing.PlayerReach()(SKIN, SCALE), "Green Whelp Scale is out of reach at 165")
    T.ok(not allowed(BRACERS), "the filter leaves Green Whelp Bracers out")
end)

T.test("Skinning 170 at level 38: the scale is in reach", function()
    character(170, 38)
    T.ok(CP.Sourcing.PlayerReach()(SKIN, SCALE), "Green Whelp Scale is in reach")
    T.ok(allowed(BRACERS), "the filter lets Green Whelp Bracers in")
end)

T.test("Skinning 170 at level 30: the whelps are too high to farm", function()
    character(170, 30)
    T.ok(not CP.Sourcing.PlayerReach()(SKIN, SCALE), "level 30 is under the whelps' 31")
    T.ok(not allowed(BRACERS), "the filter leaves Green Whelp Bracers out")
end)

T.test("a gathering skill-up that crosses a source's need moves the plan's key; one that crosses none does not", function()
    character(160, 38)
    -- A view of the guide of its own, so no key an earlier test left stands in.
    local guide = setmetatable({}, { __index = CP.Guides[LW] })
    local at160 = CP.Plan.ReachKey(guide)
    CraftWorld.SetSkill(SKIN, 165)
    T.eq(CP.Plan.ReachKey(guide), at160, "nothing of the guide's needs 161 to 165")
    CraftWorld.SetSkill(SKIN, 170)
    T.ok(CP.Plan.ReachKey(guide) ~= at160, "Green Whelp Scale comes in at 170")
end)

-- The current step holds (decision 0007 rule 1); the reach rule applies from the next step.
T.test("a saved plan from before the reach rule keeps its current step and gives up the later scale step", function()
    character(165, 38)
    local ctx = CP.Plan.Context(LW)
    World.set(CP.charDB, "committed", { [LW] = { [ctx] = { version = CP.Plan.COMMIT_VERSION, costfix = true, ctx = ctx, skill = 165,
        shown = true, steps = { { 165, 175, BRACERS, nil, 10, nil, nil, nil, 10 },
                                { 175, 185, BRACERS, nil, 10, nil, nil, nil, 10 } } } } })
    World.set(CP.charDB, "lastPlan", nil)
    local main = {}
    for _, r in ipairs(rows()) do
        if r.row.spell and not r.row.side and not (r.row.rank or r.row.train) then main[#main + 1] = r.row end
    end
    T.eq(main[1] and ("%d %d-%d"):format(main[1].spell, main[1].from, main[1].to), "9202 165-175", "the current step holds")
    for i = 2, #main do
        T.ok(main[i].spell ~= BRACERS, ("the later Green Whelp Bracers step is gone (%d-%d)"):format(main[i].from, main[i].to))
    end
    local c = CP.charDB.committed and CP.charDB.committed[LW] and CP.charDB.committed[LW][ctx]
    T.ok(c and c.reach, "the plan saved in its place carries the reach mark")
end)

-- Mining: Coarse Stone comes from Tin Veins, which take Mining 65 (Lock skill, db2); Copper Veins give
-- Rough Stone only. Fishing: Raw Slitherskin Mackerel lands in Durotar's water (base -70) at any
-- skill; Raw Rockscale Cod's waters (Tanaris, base 205) land a bite from 201.
T.test("Mining and Fishing reach by node skill and water", function()
    local F, MINING, FISHING = CP.Farm, 186, 356
    T.ok(not F.Reaches(2836, MINING, 64, 60), "Coarse Stone at Mining 64")
    T.ok(F.Reaches(2836, MINING, 65, 60), "Coarse Stone at Mining 65")
    T.ok(F.Reaches(6303, FISHING, 1, 5), "Raw Slitherskin Mackerel at Fishing 1")
    T.ok(not F.Reaches(6362, FISHING, 200, 60), "Raw Rockscale Cod at Fishing 200")
    T.ok(F.Reaches(6362, FISHING, 201, 60), "Raw Rockscale Cod at Fishing 201")
    T.eq(F.Reach(2840, MINING), nil, "no node gives a Copper Bar")
end)

T.test("a leather no creature skins never counts", function()
    World.patch("C_Item.GetItemInfoInstant", function(id)
        if id == 4461 then return id, "", "", "", 0, 7, 6 end
        return id, "", "", "", 0, 15, 0
    end)
    T.ok(not CP.Sourcing.Reach({ [393] = 300 }, 60)(393, 4461), "Raptor Hide: no creature skins it")
end)

-- A bar counts only once Mining mines its ore and smelts it. Client SkillLineAbility and cMaNGOS
-- trainer rows: Smelt Copper is learned with Mining, Smelt Tin and Smelt Bronze at 65 (Tin Vein 65),
-- Smelt Iron at 125 (Iron Deposit 125), Smelt Steel at 165 (Iron Bar and Coal, which vendors sell),
-- Smelt Mithril at 175. Gloom'rel teaches Smelt Dark Iron at 230 once quest 4083 (level 40) is done.
T.test("a smelted bar counts only once Mining mines the ore and may learn the smelt", function()
    local MINING = 186
    local function at(rank, level, bar) return CP.Sourcing.Reach({ [MINING] = rank }, level)(MINING, bar) end
    T.ok(at(1, 60, 2840), "Copper Bar at Mining 1")
    T.ok(not at(64, 60, 3576) and at(65, 60, 3576), "Tin Bar from Mining 65")
    T.ok(not at(64, 60, 2841) and at(65, 60, 2841), "Bronze Bar from Mining 65, Copper and Tin Bars both in reach")
    T.ok(not at(124, 60, 3575) and at(125, 60, 3575), "Iron Bar from Mining 125")
    T.ok(not at(164, 60, 3859) and at(165, 60, 3859), "Steel Bar from Mining 165: Iron Bar smelted, Coal bought")
    T.ok(not at(174, 60, 3860) and at(175, 60, 3860), "Mithril Bar from Mining 175")
    T.ok(not at(229, 60, 11371), "Dark Iron Bar: Smelt Dark Iron is taught at 230")
    T.ok(not at(230, 39, 11371), "Dark Iron Bar: Smelt Dark Iron's quest asks level 40")
    T.ok(at(300, 60, 11371), "Dark Iron Bar at Mining 300, level 60")
    T.ok(not at(300, 60, 17771), "Elementium Bar: no source teaches Smelt Elementium")
end)

T.test("Blacksmithing with Mining 100 plans no Iron Bar step on Mining", function()
    local BS, MINING, IRON = 164, 186, 3575
    World.patch("C_Item.GetItemInfoInstant", function(id)
        if CP.Farm.SmeltsOf(id) or CP.Farm.Reach(id, MINING) then return id, "", "", "", 0, 7, 7 end
        return id, "", "", "", 0, 15, 0
    end)
    local guide = CP.Guides[BS]
    local skills = { [BS] = true, [MINING] = true }
    local function lets(rank)
        local allow = CP.Sourcing.Filter(guide, {}, true, skills, CP.Sourcing.Reach({ [MINING] = rank }, 60))
        local n = 0
        for id, r in pairs(guide.recipes) do
            local iron = false
            for _, pair in ipairs(r.reagents) do if pair[1] == IRON then iron = true end end
            if iron and not guide.items[IRON][2] and allow(id, r) then n = n + 1 end
        end
        return n
    end
    T.eq(lets(100), 0, "no recipe that asks Iron Bar at Mining 100")
    T.ok(lets(125) > 0, "Iron Bar recipes come in at Mining 125")
end)

T.test("the reach key reads every gathered material of the guide", function()
    character(300, 60)
    local guide = setmetatable({}, { __index = CP.Guides[LW] })
    local all = CP.Plan.ReachKey(guide)
    T.ok(all:find("^3/"), "Green Whelp Scale, Thick and Rugged Leather in reach at Skinning 300: " .. all)
end)
