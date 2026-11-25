-- A disenchant row never replaces a step the player has locked in (DESKILL-01c, decision 0007).
-- Greens that arrive during a locked Enchanting step wait for the points after it.

local CP = ProfLost
local ENCHANTING = 333
local DUROTAR = 1411
local SPELL = 13262
local GLOVES = 4307           -- green, item level 15, disenchant group 1

local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 } }, bags = {},
                       items = { [GLOVES] = { 2, 15, 4, 1, 5, 1, 0 } } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    World.patch("InCombatLockdown", function() return false end)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
end

local function steps()
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(CP.Plan.Current())) do
        if row.spell and not (row.rank or row.train or row.side) then out[#out + 1] = row end
    end
    return out
end

local function describe(rows)
    local parts = {}
    for i, row in ipairs(rows) do
        parts[i] = ("%s %s-%s x%s"):format(tostring(row.spell), tostring(row.from), tostring(row.to), tostring(row.crafts))
    end
    return table.concat(parts, "; ")
end

T.test("greens arriving mid-step leave the locked step whole", function()
    scene()
    local before = steps()
    local first = before[1]
    T.ok(first and first.spell ~= SPELL, "a craft step first: " .. describe(before))
    CraftWorld.SetBag(GLOVES, 12)
    CP.Plan.Invalidate()
    T.advance(1)
    CP.Panel:Refresh()
    local rows = steps()
    T.eq(rows[1].spell, first.spell, describe(rows))
    T.eq(rows[1].from, first.from, describe(rows))
    T.eq(rows[1].to, first.to, describe(rows))
    for _, row in ipairs(rows) do
        if row.spell == SPELL then
            T.ok(row.from >= first.to, "the disenchant row sits after the locked step: " .. describe(rows))
        end
    end
    CraftWorld.Close()
end)

T.test("Deskill.Fix places the step only outside the locked points", function()
    scene()
    CraftWorld.SetBag(GLOVES, 12)
    local guide = CP.Guides[ENCHANTING]
    local p = { skill = 1, max = 75 }
    local _, _, free = CP.Deskill.Fix(guide, p, nil, nil, nil)
    T.ok(free and free > 1, "unlocked, the greens place a step")
    local fixed = CP.Deskill.Fix(guide, p, nil, nil, { { 1, 30 } })
    for s = 1, 29 do T.ok(not (fixed and fixed[s]), "point " .. s .. " stays the lock's") end
    CraftWorld.Close()
end)
