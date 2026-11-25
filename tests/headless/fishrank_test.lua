-- Fishing advice reads the fishing rank alone for rank steps, catches to go and the 300 cut,
-- and rank + modifier (a lure or pole) only for the chance a bite lands. The Guide tab's
-- Fishing row weighs the Cooking guide's needs as the checklist does.
-- Covers review items 5, 6, 16, 24 and 29.

local CP = ProfLost
local F, G, GG, GL = CP.Fishing, CP.Gather, CP.GatherGuide, CP.GatherList
local FISH, COOK, ALCHEMY = 356, 185, 171
local DUROTAR, BARRENS, MULGORE = 1411, 1413, 1412
local SMALLFISH, OILY = 6291, 6358

-- The player in `zone` at `level` with Fishing `rank` of `max` and a `mod` lure bonus, Fish for
-- Cooking on, `needs` as the guides' saved needs.
local function scene(zone, level, rank, mod, max, needs)
    MapWorld.begin({ zone = zone, x = 0.5, y = 0.5, level = level, side = "Horde" })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "fishCook", true)
    World.set(CP.db, "routeSkip", nil)
    World.set(CP.charDB, "gatherNeeds", needs or {})
    World.set(CP.charDB, "gatherSoon", needs or {})
    World.set(CP.charDB, "guideMode", "one")
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        return id == FISH and { skillID = id, rank = rank, modifier = mod, maxRank = max } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
end

-- What the checklist's fishPlan hands to FishLines and the source rows Refresh builds.
local function refresh()
    local seen = { plan = nil, rows = nil }
    local lines, rows = GL.FishLines, G.Rows
    World.set(GL, "FishLines", function(plan, ...) seen.plan = plan return lines(plan, ...) end)
    World.set(G, "Rows", function(...)
        seen.rows = rows(...)
        return seen.rows
    end)
    GL.Refresh()
    return seen
end

local function sourceLands(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        for _, s in ipairs(r.sources or {}) do
            if s.land then out[#out + 1] = s.land end
        end
    end
    return out
end

T.test("a lure does not bring the next rank step early (items 6, 16)", function()
    local p = F.Plan({ skill = 60, mod = 25, maxRank = 75, level = 15, zone = DUROTAR, side = "Horde",
        have = function() return 0 end })
    T.eq(p.kind, "zone", "60/75 with +25 still fishes")
    scene(DUROTAR, 15, 60, 25, 75)
    local seen = refresh()
    T.ok(seen.plan, "the panel plans fishing")
    T.eq(seen.plan.kind, "zone", "the panel does not say Train Journeyman Fishing")
    scene(DUROTAR, 15, 140, 20, 150)
    seen = refresh()
    T.eq(seen.plan and seen.plan.kind, "zone", "140/150 with +20 does not say Buy Expert Fishing")
end)

T.test("a lure does not cut catches to go or hide the plan near 300 (items 6, 16)", function()
    local p = F.Plan({ skill = 100, mod = 25, maxRank = 150, level = 40, zone = BARRENS, side = "Horde",
        have = function() return 0 end })
    T.eq(p.catches, F.CatchesTo(100, 150), "catches count from the rank alone")
    scene(BARRENS, 50, 280, 25, 300)
    local seen = refresh()
    T.ok(seen.plan, "280/300 with +25 keeps its Fishing plan")
    T.eq(seen.plan and seen.plan.catches, F.CatchesTo(280, 300))
end)

T.test("a lure still lifts the land chance (item 6 keeps rank + modifier there)", function()
    local bare = F.Plan({ skill = 1, maxRank = 75, level = 15, zone = DUROTAR, side = "Horde",
        have = function() return 0 end })
    local lured = F.Plan({ skill = 1, mod = 15, maxRank = 75, level = 15, zone = DUROTAR, side = "Horde",
        have = function() return 0 end })
    T.eq(bare.land, 76)
    T.eq(lured.land, 91)
end)

T.test("the heading and the source rows name the same land chance (item 29)", function()
    scene(DUROTAR, 15, 1, 15, 75)
    local seen = refresh()
    T.eq(seen.plan.land, 91)
    local lands = sourceLands(seen.rows)
    T.ok(#lands > 0, "fish sources show")
    for _, l in ipairs(lands) do T.eq(l, 91, "source land equals the heading") end
    scene(DUROTAR, 15, 1, 25, 75)
    seen = refresh()
    T.eq(seen.plan.land, 100)
    for _, l in ipairs(sourceLands(seen.rows)) do T.eq(l, 100, "a lure that lands every bite shows 100") end
end)

-- Durotar is near, Mulgore a little farther, and holds the fish the Cooking guide needs.
local function yards(zone)
    if zone == DUROTAR then return 0 end
    if zone == MULGORE then return 800 end
    return 1e9
end

T.test("the Guide tab's Fishing row follows the Cooking feeds like the checklist (item 5)", function()
    scene(DUROTAR, 10, 30, 0, 75, { [COOK] = { [SMALLFISH] = 72 } })
    World.set(GL, "Distance", yards)
    local row
    for _, r in ipairs(GG.PlayerRows(FISH, 30, 75)) do
        if r.fish then row = r break end
    end
    T.ok(row, "a fishing row")
    local plan = F.Plan({ skill = 30, maxRank = 75, level = 10, zone = DUROTAR, side = "Horde", cook = true,
        needs = { [SMALLFISH] = 72 }, have = function() return 0 end, distance = yards })
    T.ok(#plan.feeds > 0, "the checklist's plan finds the feed")
    T.eq(row.fish.zone, plan.zone, "the row names the checklist's water")
    T.ok(#row.fish.feeds > 0, "the row lists the feed")
end)

T.test("the Fishing card lists only the Cooking guide's fish (item 24)", function()
    scene(BARRENS, 40, 100, 0, 150, { [ALCHEMY] = { [OILY] = 72 } })
    World.set(GL, "Distance", yards)
    local row
    for _, r in ipairs(GG.PlayerRows(FISH, 100, 150)) do
        if r.fish then row = r break end
    end
    T.ok(row, "a fishing row")
    for _, f in ipairs(row.fish.feeds or {}) do
        T.ok(f.item ~= OILY, "Alchemy's Oily Blackmouth is not tagged Cooking")
    end
    scene(BARRENS, 40, 100, 0, 150, { [COOK] = { [OILY] = 72 } })
    World.set(GL, "Distance", yards)
    row = nil
    for _, r in ipairs(GG.PlayerRows(FISH, 100, 150)) do
        if r.fish then row = r break end
    end
    local found = false
    for _, f in ipairs(row and row.fish.feeds or {}) do
        if f.item == OILY then found = true end
    end
    T.ok(found, "Cooking's own need still lists")
end)
