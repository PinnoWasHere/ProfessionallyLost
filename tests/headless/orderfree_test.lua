-- A guide's plan does not depend on which profession was solved first (ORDERFREE-01, the plan
-- order review of 2026-11-20). A gear guide's disenchant credit reads
-- Enchanting's needs; two identical characters must see the same guide whichever window they
-- opened first, with no window open at all, and after a reload.

local CP = ProfLost
local ENCHANTING, TAILOR, LW = 333, 197, 165
local DUROTAR = 1411

-- A new Horde character with `line` and Enchanting, both at 1/75, "Gather it yourself" on.
-- `charDB` is the saved data to start from (a reload), else none.
local function character(line, charDB)
    MapWorld.begin({ zone = DUROTAR, level = 5, side = "Horde" })
    CraftWorld.begin({ professions = { [line] = { rank = 1, max = 75 }, [ENCHANTING] = { rank = 1, max = 75 } },
                       charDB = charDB })
    -- The vendor scan the clock runs sets this; later files must not see it.
    World.set(CP.VendorWatch, "current", CP.VendorWatch.current)
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
end

-- Profession `line`'s window opened and its plan solved, then closed.
local function open(line)
    CraftWorld.Open(line)
    T.advance(0.5)
    local live = CP.Plan.Current()
    CraftWorld.Close()
    T.advance(0.5)
    return live
end

-- The plan `line`'s window shows, as text: each main step's recipe and range.
local function shown(line)
    local live = open(line)
    local out = {}
    for _, st in ipairs(live and live.plan or {}) do
        if st.spell then out[#out + 1] = ("%d %d-%d"):format(st.spell, st.from, st.to) end
    end
    return table.concat(out, ", ")
end

-- A deep copy of plain saved data.
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Gather.UpdateAllNeeds' own loop, solving the guides in `order`.
local function solveIn(order)
    for _, id in ipairs(order) do
        local live = CP.Plan.Shut(id)
        if live and live.plan then
            CP.Gather.SaveNeeds({ guide = live.guide, prof = live.prof, plan = live.plan, learned = live.learned,
                                  shapedBy = live.shapedBy })
        end
    end
end

-- The partner's plan after each way into the guide, by name.
local function variants(line)
    local out = {}
    character(line)
    open(ENCHANTING)
    out["Enchanting's window first"] = shown(line)

    character(line)
    open(line)
    open(ENCHANTING)
    out[CraftWorld.NAMES[line] .. "'s window first"] = shown(line)
    local saved = copy(CP.charDB)

    character(line)
    CP.Gather.UpdateAllNeeds()
    out["no window, Gather.UpdateAllNeeds"] = shown(line)

    character(line)
    solveIn({ line, ENCHANTING })
    out["no window, " .. CraftWorld.NAMES[line] .. " solved first"] = shown(line)

    character(line)
    solveIn({ ENCHANTING, line })
    out["no window, Enchanting solved first"] = shown(line)

    -- A reload with the saved data of the partner-first character.
    character(line, saved)
    T.fire("PLAYER_ENTERING_WORLD", false, true)
    T.advance(2)
    out["after a reload of the " .. CraftWorld.NAMES[line] .. "-first character"] = shown(line)
    return out
end

for _, line in ipairs({ TAILOR, LW }) do
    T.test(("%s + Enchanting: one plan whichever profession is solved first"):format(CraftWorld.NAMES[line]), function()
        local out = variants(line)
        local want = out["Enchanting's window first"]
        T.ok(want ~= "", "the guide has steps")
        for _, name in ipairs(World.keys(out)) do
            print(("ORDERFREE|%s|%s|%s"):format(CraftWorld.NAMES[line], name, out[name]:sub(1, 160)))
            T.eq(out[name], want, name)
        end
    end)
end

-- The credit reads Enchanting's current plan: its signature joins every key a gear guide's plan
-- is cached under, so new Enchanting needs re-solve it.
T.test("Enchanting's needs are part of a gear guide's shut-plan key", function()
    character(TAILOR)
    local key = CP.Plan.CreditKey(TAILOR)
    local _, sig = CP.Shared.EnchantingNeeds()
    T.ok(sig ~= nil and sig ~= "", "Enchanting needs something at 1")
    T.eq(key, sig)
    T.eq(CP.Plan.CreditKey(ENCHANTING), "", "Enchanting reads no credit")
    World.set(CP.db, "deEnchant", false)
    T.eq(CP.Plan.CreditKey(TAILOR), "", "Plan for Enchanting off: no credit")
end)

-- Version 5: a version 4 plan that took the credit may have been made without it, so it is solved
-- afresh once; a version 4 plan without Enchanting is kept as it stands.
local function savedAs4(line)
    open(line)
    local ctx = CP.Plan.Context(line)
    local c = CP.charDB.committed[line][ctx]
    T.eq(c.version, 5, "a fresh plan is version 5")
    c.version = 4
    CP.Plan.Invalidate()
    local dropped = CP.Plan.Dropped[line] or 0
    open(line)
    return CP.charDB.committed[line][ctx], (CP.Plan.Dropped[line] or 0) - dropped
end

T.test("a version 4 Tailoring plan is solved afresh with Enchanting, kept without it", function()
    character(TAILOR)
    local c, dropped = savedAs4(TAILOR)
    T.eq(dropped, 1, "with Enchanting: dropped once")
    T.eq(c and c.version, 5, "solved again at version 5")

    MapWorld.begin({ zone = DUROTAR, level = 5, side = "Horde" })
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 1, max = 75 } } })
    World.set(CP.db, "collect", true)
    c, dropped = savedAs4(TAILOR)
    T.eq(dropped, 0, "without Enchanting: kept")
    T.eq(c and c.version, 5, "re-marked version 5")

    character(TAILOR)
    World.set(CP.db, "deEnchant", false)
    c, dropped = savedAs4(TAILOR)
    T.eq(dropped, 0, "Plan for Enchanting off: kept")
end)

-- The credit's source stays cheap: another profession's skill-up re-solves no shut plan. A shut plan
-- reads the skills only as the set of professions held, and a gear guide's credit through its key.
T.test("a skill-up re-solves neither the gear guide's shut plan nor Enchanting's", function()
    character(TAILOR)
    local ench, tail = CP.Plan.Shut(ENCHANTING), CP.Plan.Shut(TAILOR)
    CP:Emit("ProfLost_SKILLS")
    T.ok(CP.Plan.Shut(ENCHANTING) == ench, "Enchanting's plan is kept")
    T.ok(CP.Plan.Shut(TAILOR) == tail, "Tailoring's plan is kept")
    CP.Plan.Invalidate()
    T.ok(CP.Plan.Shut(ENCHANTING) ~= ench, "Plan.Invalidate re-solves Enchanting too")
end)

-- Reading Enchanting's needs for the credit saves nothing of Enchanting's: its own guide is the
-- same whether another guide was solved first or not.
T.test("a gear guide's solve leaves Enchanting's saved plan alone", function()
    character(TAILOR)
    local needs = CP.Shared.EnchantingNeeds()
    T.ok(needs ~= nil, "Enchanting needs something")
    local tailoring = CP.Plan.Shut(TAILOR)
    T.ok(tailoring and tailoring.credit ~= nil, "Tailoring took the credit")
    local committed = CP.charDB.committed and CP.charDB.committed[ENCHANTING]
    T.ok(committed == nil or next(committed) == nil, "no Enchanting plan saved")
    T.eq(CP.charDB.lastPlan and CP.charDB.lastPlan[ENCHANTING], nil, "no Enchanting last plan filed")
end)

T.test("Gather.UpdateAllNeeds solves Enchanting first, then the rest by id", function()
    local order = CP.Gather.SolveOrder()
    T.eq(order[1], ENCHANTING)
    for i = 3, #order do T.ok(order[i - 1] < order[i], "sorted after Enchanting") end
end)

-- Plain data as one sorted string, for deep comparisons.
local function encode(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for i, k in ipairs(keys) do out[i] = tostring(k) .. "=" .. encode(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end

-- Enchanting's saved plan and last plan, once its window has solved, with the last plan's memo
-- marked stale so the next solve files a new one.
local function enchantingSaved()
    character(TAILOR)
    open(ENCHANTING)
    local memo = CP.charDB.lastPlan[ENCHANTING].memo
    for _, m in pairs(memo) do m.state = -1 end
    CP.Plan.Invalidate()
    return encode(CP.charDB.committed[ENCHANTING]), encode(CP.charDB.lastPlan[ENCHANTING]),
        CP.charDB.committed[ENCHANTING]
end

T.test("reading Enchanting's needs leaves its saved plan, last plan and memo as they were", function()
    local committed, last, same = enchantingSaved()
    T.ok(CP.Shared.EnchantingNeeds() ~= nil, "the credit read Enchanting's plan")
    T.eq(encode(CP.charDB.lastPlan[ENCHANTING]), last, "the last plan and its memo")
    T.eq(encode(CP.charDB.committed[ENCHANTING]), committed, "the saved plan")
    T.ok(CP.charDB.committed[ENCHANTING] == same, "the same saved table")
end)

T.test("a solve that raises while reading Enchanting's needs leaves its saved data as it was", function()
    local committed, last, same = enchantingSaved()
    local dropped = encode(CP.Plan.Dropped)
    World.set(CP.Solver, "Plan", function() error("planted") end)
    T.ok(not pcall(CP.Shared.EnchantingNeeds), "the error reaches the caller")
    T.eq(encode(CP.charDB.lastPlan[ENCHANTING]), last, "the last plan and its memo")
    T.eq(encode(CP.charDB.committed[ENCHANTING]), committed, "the saved plan")
    T.ok(CP.charDB.committed[ENCHANTING] == same, "the same saved table")
    T.eq(encode(CP.Plan.Dropped), dropped, "Plan.Dropped")
end)

T.test("reading Enchanting's needs on a character with nothing saved saves nothing", function()
    character(TAILOR)
    T.eq(CP.charDB.committed, nil, "nothing saved yet")
    T.ok(CP.Shared.EnchantingNeeds() ~= nil, "the credit read Enchanting's plan")
    T.eq(CP.charDB.committed, nil, "still nothing saved")
    T.eq(CP.charDB.lastPlan == nil or CP.charDB.lastPlan[ENCHANTING] == nil, true, "no last plan filed")
end)

-- The version 5 check needs the skill list: a solve before it lists the profession holds a version 4
-- plan as it stands and decides later; once it is read, the plan that took the credit is dropped once.
local function hold(live)
    return CP.Plan.Hold(live.prof, live.guide, live.learned, live.dead)
end

T.test("a version 4 plan waits for the skill list before the version 5 check", function()
    character(TAILOR)
    local live = open(TAILOR)
    local ctx = CP.Plan.Context(TAILOR)
    local saved = CP.charDB.committed[TAILOR][ctx]
    saved.version = 4
    local dropped = CP.Plan.Dropped[TAILOR] or 0
    local skills = CP.Sourcing.PlayerSkills
    World.set(CP.Sourcing, "PlayerSkills", function() return {} end)
    local c = hold(live)
    T.ok(c == saved, "no skills read: the version 4 plan is held")
    T.eq(saved.version, 4, "and keeps its version")
    T.eq((CP.Plan.Dropped[TAILOR] or 0) - dropped, 0, "not dropped yet")
    World.set(CP.Sourcing, "PlayerSkills", skills)
    T.eq(hold(live), nil, "skills read: nothing held")
    T.eq((CP.Plan.Dropped[TAILOR] or 0) - dropped, 1, "dropped once")
    T.eq(CP.charDB.committed[TAILOR][ctx], nil, "gone from the saved plans")
end)

T.test("a version 4 plan checked with the skill list read is dropped at once, and only once", function()
    character(TAILOR)
    local live = open(TAILOR)
    local ctx = CP.Plan.Context(TAILOR)
    CP.charDB.committed[TAILOR][ctx].version = 4
    local dropped = CP.Plan.Dropped[TAILOR] or 0
    T.eq(hold(live), nil, "dropped")
    T.eq(hold(live), nil, "nothing to hold")
    T.eq((CP.Plan.Dropped[TAILOR] or 0) - dropped, 1, "dropped once")
end)
