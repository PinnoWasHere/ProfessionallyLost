-- A shut solve takes the peek's plan when nothing changed since the peek. Release run on b40ff62,
-- blacksmithing-horde-collect-new-alsoenchanting-controls-s1: a Blacksmithing skill-up cost 13
-- Solver.Plan calls (at most 12). Blacksmithing's disenchant credit peeked at Enchanting's plan
-- (Plan.Shut with `peek`, 4 calls), then the guide's trip text asked for Enchanting's own shut plan
-- with the same key and solved it again (4 more).

local CP = ProfLost
local Plan = CP.Plan
local ENCHANTING, BLACKSMITHING = 333, 164
local DUROTAR = 1411

local function counter()
    local c = { plans = 0, enchanting = 0 }
    local offline, plan = Plan.Offline, CP.Solver.Plan
    World.set(Plan, "Offline", function(guide, id, ...)
        if id == ENCHANTING then c.enchanting = c.enchanting + 1 end
        return offline(guide, id, ...)
    end)
    World.set(CP.Solver, "Plan", function(...)
        c.plans = c.plans + 1
        return plan(...)
    end)
    return c
end

-- A character with Enchanting and Blacksmithing, and no shut or peeked plan cached.
local function character()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 },
                                       [BLACKSMITHING] = { rank = 211, max = 225 } } })
    World.set(CP.db, "collect", true)
    local was = Plan.Caches()
    World.onEnd(function() Plan.SetCaches(was) end)
    Plan.SetCaches({ epoch = was.epoch, sureEpoch = was.sureEpoch, shut = {}, peeks = {}, cached = nil,
                     lastKey = nil, readRev = was.readRev, booked = was.booked })
end

-- A table as text, keys sorted, functions left out.
local function dump(v, seen)
    if type(v) ~= "table" then return type(v) == "function" and "fn" or tostring(v) end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. dump(v[k], seen) end
    seen[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
end

local function saved()
    local db = CP.charDB
    return dump({ committed = db.committed and db.committed[ENCHANTING],
                  last = db.lastPlan and db.lastPlan[ENCHANTING], dropped = Plan.Dropped[ENCHANTING] })
end

local function rows(live)
    local out = {}
    for _, st in ipairs(live and live.plan or {}) do
        out[#out + 1] = ("%s:%s-%s:%s"):format(tostring(st.spell), tostring(st.from), tostring(st.to),
            tostring(st.crafts))
    end
    return table.concat(out, ";")
end

T.test("a shut solve after a peek with the same inputs solves nothing again", function()
    character()
    local c = counter()
    local before = saved()
    local peeked = Plan.Shut(ENCHANTING, true)
    T.ok(peeked ~= nil, "the peek has a plan")
    T.eq(c.enchanting, 1, "the peek solved Enchanting")
    T.eq(saved(), before, "the peek saved nothing")
    local plans = c.plans
    local live = Plan.Shut(ENCHANTING)
    print(("PEEKADOPT|peek %d Solver.Plan calls, shut %d more"):format(plans, c.plans - plans))
    T.eq(c.enchanting, 1, "the shut solve took the peek's plan")
    T.eq(c.plans, plans, "no Solver.Plan call after the peek")
    T.eq(rows(live), rows(peeked), "the shut plan is the peek's")
    T.ok(Plan.Shut(ENCHANTING, true) == live, "a later peek reads the shut plan")
end)

T.test("the shut plan taken from a peek saves what its own solve would", function()
    character()
    Plan.Shut(ENCHANTING, true)
    local live = Plan.Shut(ENCHANTING)
    local adopted, adoptedRows = saved(), rows(live)

    character()
    local c = counter()
    local own = Plan.Shut(ENCHANTING)
    T.eq(c.enchanting, 1, "control: the shut plan solved")
    T.eq(rows(own), adoptedRows, "the same plan")
    T.eq(saved(), adopted, "the same saved plan, last plan and dropped mark")
end)

T.test("a peek is not taken after a craft counted on the saved plan", function()
    character()
    Plan.Shut(ENCHANTING)
    local was = Plan.Caches()
    Plan.SetCaches({ epoch = was.epoch, sureEpoch = was.sureEpoch, shut = {}, peeks = {}, cached = nil,
                     lastKey = nil, readRev = was.readRev, booked = was.booked })
    Plan.Shut(ENCHANTING, true)
    local c = Plan.Committed(ENCHANTING)
    T.ok(c ~= nil, "Enchanting has a saved plan")
    if not c then return end
    World.set(c, "made", (c.made or 0) + 1)
    local n = counter()
    Plan.Shut(ENCHANTING)
    T.eq(n.enchanting, 1, "the shut plan solved afresh")
    T.eq(Plan.Committed(ENCHANTING), c, "the saved plan keeps its craft count")
end)

T.test("a peek whose saved plan changed since is not taken", function()
    character()
    Plan.Shut(ENCHANTING, true)
    -- Another solve saved a plan for Enchanting after the peek.
    local db = CP.charDB
    World.set(db, "committed", db.committed or {})
    World.set(db.committed, ENCHANTING, {})
    local c = counter()
    Plan.Shut(ENCHANTING)
    T.eq(c.enchanting, 1, "the shut plan solved afresh")
end)
