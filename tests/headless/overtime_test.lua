-- The Working Overtime legacy perk: its rank read from C_Traits, and the skill-up chance it multiplies.

local CP = ProfLost
local Prof = CP.Professions
local G = CP.Guide

local TREE, CONFIG, NODE, ENTRY, DEF = 1187, 77, 900, 901, 135547
local ROBE = 7623   -- Brown Linen Robe: yellow 50, green 67, grey 85

-- A legacy professions tree holding one other perk and Working Overtime at `rank` of 5.
-- `tree = false` leaves the tree out; `node = false` leaves the perk's node out.
local function traits(rank, opts)
    opts = opts or {}
    World.set(CP.Guide, "boost", 1)
    World.set(Prof, "overtime", nil)
    World.set(_G, "Constants", { LegacyConsts = { LEGACY_TREE_PROFESSIONS_ID = TREE } })
    World.set(_G, "C_Traits", {
        GetConfigIDByTreeID = function(tree)
            if opts.tree == false or tree ~= TREE then return nil end
            return CONFIG
        end,
        GetTreeNodes = function(tree)
            if tree ~= TREE then return {} end
            return opts.node == false and { 800 } or { 800, NODE }
        end,
        GetNodeInfo = function(config, node)
            if config ~= CONFIG then return nil end
            if node == 800 then return { ID = 800, entryIDs = { 801 }, activeRank = 2, maxRanks = 3 } end
            if node == NODE then return { ID = NODE, entryIDs = { ENTRY }, activeRank = rank, maxRanks = 5 } end
        end,
        GetEntryInfo = function(config, entry)
            if entry == 801 then return { definitionID = 555 } end
            if entry == ENTRY then return { definitionID = DEF } end
        end,
        GetDefinitionInfo = function(def)
            if def == 555 then return { spellID = 12345 } end
            if def == DEF then return { spellID = 1225451 } end
        end,
    })
end

local function crafts(r, from, to, boost)
    local total = 0
    for s = from, to - 1 do
        local p = s < r.yellow and 1 or (r.grey - s) / (r.grey - r.yellow)
        total = total + 1 / math.min(1, p * boost)
    end
    return math.ceil(total)
end

T.test("the rank reader returns the perk node's active rank", function()
    traits(3)
    local o = Prof.ReadOvertime()
    T.eq(o.tree, true)
    T.eq(o.node, true)
    T.eq(o.rank, 3)
    T.eq(o.max, 5)
end)

T.test("the rank reader gives 0 when the tree or the node is missing", function()
    traits(5, { tree = false })
    local o = Prof.ReadOvertime()
    T.eq(o.tree, false)
    T.eq(o.rank, 0)
    traits(5, { node = false })
    o = Prof.ReadOvertime()
    T.eq(o.tree, true)
    T.eq(o.node, false)
    T.eq(o.rank, 0)
    World.set(_G, "C_Traits", nil)
    T.eq(Prof.ReadOvertime().rank, 0, "no C_Traits at all")
end)

T.test("rank 0 changes nothing", function()
    local r = CP.Guides[197].recipes[ROBE]
    local before = G.Crafts(r, 50, 85)
    local fishing, green = CP.Fishing.SkillUpChance(200), CP.GatherGuide.Chance(160, 100)
    traits(0)
    T.eq(Prof.OvertimeRank(), 0)
    T.eq(G.boost, 1)
    T.eq(G.Crafts(r, 50, 85), before)
    T.eq(G.Crafts(r, 50, 85), crafts(r, 50, 85, 1))
    T.eq(CP.Fishing.SkillUpChance(200), fishing)
    T.eq(CP.GatherGuide.Chance(160, 100), green)
end)

T.test("rank 5 multiplies the chance by 1.2 on yellow and green steps", function()
    local r = CP.Guides[197].recipes[ROBE]
    local yellow, green = G.Crafts(r, 50, 67), G.Crafts(r, 67, 85)
    local whole = G.Crafts(r, 50, 85)
    traits(5)
    T.eq(Prof.OvertimeRank(), 5)
    T.ok(math.abs(G.boost - 1.2) < 1e-9, "boost " .. G.boost)
    T.eq(G.Crafts(r, 50, 67), crafts(r, 50, 67, 1.2))
    T.eq(G.Crafts(r, 67, 85), crafts(r, 67, 85, 1.2))
    T.ok(G.Crafts(r, 50, 67) < yellow, "yellow step crafts fall")
    T.ok(G.Crafts(r, 67, 85) < green, "green step crafts fall")
    T.ok(G.Crafts(r, 50, 85) < whole, ("Brown Linen Robe 50 to 85: %d to %d"):format(whole, G.Crafts(r, 50, 85)))
    T.eq(G.Chance(r, 49), 1, "orange stays 1")
    T.eq(G.Chance(r, 50), 1, "capped at 1")
end)

T.test("rank 5 lifts gathering and fishing chances but keeps the gathering bands", function()
    traits(5)
    Prof.OvertimeRank()
    local GG = CP.GatherGuide
    T.ok(math.abs(GG.Chance(160, 100) - 0.3) < 1e-9, "green 0.25 x 1.2")
    T.ok(math.abs(GG.Chance(130, 100) - 0.9) < 1e-9, "yellow 0.75 x 1.2")
    T.eq(GG.Band(160, 100), 0.25)
    T.eq(GG.Chance(110, 100), 1)
    T.ok(math.abs(CP.Fishing.SkillUpChance(100) - 0.6) < 1e-9, "fishing 0.5 x 1.2")
    T.eq(CP.Fishing.SkillUpChance(50), 1)
    -- A yellow target is still named first, and a green one still marked green.
    local names = GG.TargetNames({ { name = "Yellow", req = 100 }, { name = "Green", req = 60 } }, 130, 3)
    T.eq(names[1], "Yellow")
    T.eq(#names, 1)
    names = GG.TargetNames({ { name = "Green", req = 60 } }, 130, 3)
    T.eq(names[1], "Green (green)")
end)

T.test("rank 5 solves Tailoring in fewer crafts", function()
    local guide = CP.Guides[197]
    local function total()
        local n = 0
        for _, st in ipairs(CP.Solver.Plan(guide, 1, {}, CP.Pricing.GetCollect)) do n = n + (st.crafts or 0) end
        return n
    end
    traits(0)
    Prof.OvertimeRank()
    local plain = total()
    traits(5)
    Prof.OvertimeRank()
    local boosted = total()
    T.ok(boosted < plain, ("%d crafts at rank 5 vs %d at rank 0"):format(boosted, plain))
end)

T.test("a rank change on TRAIT_CONFIG_UPDATED re-reads the perk and tells the windows to re-plan", function()
    traits(0)
    T.eq(Prof.OvertimeRank(), 0)
    traits(4)
    World.set(Prof, "overtime", { rank = 0, tree = true, node = true, max = 5 })
    local moved = false
    local function onSkills() moved = true end
    CP:On("ProfLost_SKILLS", onSkills)
    World.onEnd(function() CP:Off("ProfLost_SKILLS", onSkills) end)
    T.fire("TRAIT_CONFIG_UPDATED", CONFIG)
    T.eq(Prof.OvertimeRank(), 4)
    T.ok(moved, "windows are told to re-plan")
    T.ok(math.abs(G.boost - 1.16) < 1e-9)
end)

T.test("/proflost check overtime prints the tree, node, rank and multiplier", function()
    traits(3)
    local lines = {}
    World.set(CP, "Print", function(_, msg) lines[#lines + 1] = msg end)
    SlashCmdList.PROFLOST("check overtime")
    local text = table.concat(lines, "\n")
    T.ok(text:find("tree found: yes", 1, true), text)
    T.ok(text:find("node found: yes", 1, true), text)
    T.ok(text:find("rank 3 of 5", 1, true), text)
    T.ok(text:find("multiplier 1.12", 1, true), text)
    lines = {}
    traits(3, { tree = false })
    SlashCmdList.PROFLOST("check overtime")
    text = table.concat(lines, "\n")
    T.ok(text:find("tree found: no", 1, true), text)
    T.ok(text:find("node found: no", 1, true), text)
    T.ok(text:find("rank 0 of 0", 1, true), text)
    T.ok(text:find("multiplier 1.00", 1, true), text)
end)
