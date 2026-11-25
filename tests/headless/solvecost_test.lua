-- SOLVECOST-01: a skill-up in one profession re-solves that profession's plan and no other
-- guide's. Cooking's shut plan once re-solved (about nine Solver.Plan calls) on every First Aid
-- skill-up because its cache key read an epoch that any skill change bumps.

local CP = ProfLost
local FIRST_AID, COOKING, TAILOR = 129, 185, 197
local DUROTAR = 1411

local function counter()
    local c = { byGuide = {}, plans = 0 }
    local offline, plan = CP.Plan.Offline, CP.Solver.Plan
    World.set(CP.Plan, "Offline", function(guide, ...)
        c.byGuide[guide.name] = (c.byGuide[guide.name] or 0) + 1
        return offline(guide, ...)
    end)
    World.set(CP.Solver, "Plan", function(...)
        c.plans = c.plans + 1
        return plan(...)
    end)
    return c
end

local function character()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [FIRST_AID] = 140, [COOKING] = 1, [TAILOR] = 60 } })
    World.set(CP.VendorWatch, "current", CP.VendorWatch.current)
    World.set(CP.db, "collect", true)
    -- Every shut plan solved once, so the next solve is the skill-up's.
    for _, id in ipairs({ FIRST_AID, COOKING, TAILOR }) do CP.Plan.Shut(id) end
    T.advance(2)
end

T.test("a First Aid skill-up re-solves First Aid and leaves Cooking's and Tailoring's shut plans", function()
    character()
    local c = counter()
    local cooking, tailoring = CP.Plan.Shut(COOKING), CP.Plan.Shut(TAILOR)
    CraftWorld.SetSkill(FIRST_AID, 141)
    T.fire("CHAT_MSG_SKILL", "Your skill in First Aid has increased to 141.")
    T.advance(3)
    T.ok(CP.Plan.Shut(COOKING) == cooking, "Cooking's plan is kept")
    T.ok(CP.Plan.Shut(TAILOR) == tailoring, "Tailoring's plan is kept")
    T.eq(c.byGuide[CP.Guides[COOKING].name], nil, "Cooking not solved")
    T.eq(c.byGuide[CP.Guides[TAILOR].name], nil, "Tailoring not solved")
    T.ok(c.byGuide[CP.Guides[FIRST_AID].name] == nil or c.byGuide[CP.Guides[FIRST_AID].name] <= 1,
        "First Aid solved at most once")
end)

T.test("opening First Aid's window leaves Cooking's and Tailoring's shut plans", function()
    character()
    local cooking, tailoring = CP.Plan.Shut(COOKING), CP.Plan.Shut(TAILOR)
    CraftWorld.Open(FIRST_AID)
    T.advance(0.5)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(0.5)
    T.ok(CP.Plan.Shut(COOKING) == cooking, "Cooking's plan is kept")
    T.ok(CP.Plan.Shut(TAILOR) == tailoring, "Tailoring's plan is kept")
end)
