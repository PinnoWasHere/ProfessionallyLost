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

T.test("a saved plan from before the reach rule that leans on the scale is dropped once", function()
    character(165, 38)
    local ctx = CP.Plan.Context(LW)
    World.set(CP.charDB, "committed", { [LW] = { [ctx] = { version = CP.Plan.COMMIT_VERSION, ctx = ctx, skill = 165,
        shown = true, steps = { { 165, 175, BRACERS, nil, 10, nil, nil, nil, 10 } } } } })
    World.set(CP.charDB, "lastPlan", nil)
    local list = rows()
    for _, r in ipairs(list) do
        T.ok(not (r.row.spell == BRACERS and not r.row.side), "the saved Green Whelp Bracers step is gone")
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

T.test("a smelted bar counts with Mining at any rank; a leather no creature skins never counts", function()
    World.patch("C_Item.GetItemInfoInstant", function(id)
        if id == 2840 then return id, "", "", "", 0, 7, 7 end
        if id == 4461 then return id, "", "", "", 0, 7, 6 end
        return id, "", "", "", 0, 15, 0
    end)
    local reach = CP.Sourcing.Reach({ [186] = 1, [393] = 300 }, 60)
    T.ok(reach(186, 2840), "Copper Bar: smelted, the data holds no smelting skill")
    T.ok(not reach(393, 4461), "Raptor Hide: no creature skins it")
end)

T.test("the reach key reads every gathered material of the guide", function()
    character(300, 60)
    local guide = setmetatable({}, { __index = CP.Guides[LW] })
    local all = CP.Plan.ReachKey(guide)
    T.ok(all:find("^3/"), "Green Whelp Scale, Thick and Rugged Leather in reach at Skinning 300: " .. all)
end)
