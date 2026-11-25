-- RELFIX-01: a solve saves the steps its own plan locks (Plan.Commit's `invested`). The 1.3.0 release
-- run (leatherworking-alliance-buy-new-controls-s1) found a fresh plan saved with none, so the next
-- solve, with nothing moved, wrote different saved data and the preview on/off round trip failed.

local CP = ProfLost
local LW = 165
local HEAVY = 4234

local function scene()
    MapWorld.begin({ zone = 1411, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = 143, max = 225 } }, bags = { [HEAVY] = 58 } })
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel:Refresh()
end

local function invested()
    local c = CP.Plan.Committed(LW)
    local keys = {}
    for k in pairs(c and c.invested or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return table.concat(keys, ","), c
end

T.test("a fresh plan saves the steps it locks, and solving again with nothing moved saves the same", function()
    scene()
    local first, c = invested()
    T.ok(c ~= nil, "a plan is saved")
    local cur = c and c.steps[c.current or 1]
    T.ok(cur and first:find(CP.Plan.StepKey(cur), 1, true) ~= nil,
        ("the current step %s is saved as invested: %s"):format(cur and CP.Plan.StepKey(cur) or "?", first))

    CP.Plan.Invalidate()
    CP.Plan.ForgetBook()
    T.advance(1)
    CP.Panel:Refresh()
    local second = invested()
    print(("RELFIX01|invested|first %s|second %s"):format(first, second))
    T.eq(second, first, "a second solve with nothing moved saves the same invested steps")
    CraftWorld.Close()
end)
