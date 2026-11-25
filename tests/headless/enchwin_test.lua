-- A returning character's Enchanting plan is the same with the profession window open or shut
-- (ENCHWIN-01). The open solve reads the live list; the shut solve reads the skill list and
-- what the last read saved. Both must plan from the same skill and the same grey recipes.

local CP = ProfLost
local ENCHANTING = 333
local DUROTAR = 1411
local RANK = 74
local MINOR_HEALTH = 7420   -- the guide's first step at 74

-- Every row the guide draws: main steps, stops and "or" rows, without craftable counts.
local function rows(live)
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        local kind = row.rank and "rank" or row.train and "train" or row.side and "or" or "step"
        local stop = row.rank or row.train
        out[#out + 1] = ("%s:%s-%s:%s:%s"):format(kind, tostring(row.at or row.from), tostring(row.to),
            tostring(row.spell or (stop and (stop.name or stop.skill))), tostring(row.crafts))
    end
    return table.concat(out, ";")
end

-- The first row two row lists differ at.
local function firstDiff(a, b)
    local pa, pb = {}, {}
    for part in a:gmatch("[^;]+") do pa[#pa + 1] = part end
    for part in b:gmatch("[^;]+") do pb[#pb + 1] = part end
    for i = 1, math.max(#pa, #pb) do
        if pa[i] ~= pb[i] then return ("row %d: %s | %s"):format(i, tostring(pa[i]), tostring(pb[i])) end
    end
    return "same"
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- The window's recipe list with `spell` grey at every skill, while the guide's data says it
-- still gives points: the game moved it, as Forever did with Basic Campfire.
local function greyed(spell)
    local list
    return function(line)
        if line ~= ENCHANTING then return nil end
        if not list then
            list = {}
            for id, r in pairs(CP.Guides[ENCHANTING].recipes) do list[id] = r end
            local moved = copy(list[spell])
            moved.yellow, moved.grey = 1, 1
            list[spell] = moved
        end
        return list
    end
end

-- A Horde character with Enchanting at RANK and its trainer recipes known. `case.bonus`: a skill
-- modifier. `case.grey`: a recipe the game shows grey ahead of the guide. `charDB`: saved data.
local function character(case, charDB)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = RANK } }, charDB = charDB,
                       recipes = case.grey and greyed(case.grey) or nil })
    World.set(CraftWorld, "Modifier", function(line) return line == ENCHANTING and case.bonus or 0 end)
    World.set(CP.VendorWatch, "current", CP.VendorWatch.current)
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
end

local function login(reload)
    T.fire("PLAYER_ENTERING_WORLD", not reload, reload == true)
    T.advance(2)
end

-- The guide with Enchanting's window open, then shut again.
local function opened()
    CraftWorld.Open(ENCHANTING)
    T.advance(0.5)
    local out = rows(CP.Plan.Current())
    CraftWorld.Close()
    T.advance(0.5)
    return out
end

-- The guide with every window shut, after something that re-solves (a vendor visit).
local function shut()
    T.fire("MERCHANT_SHOW")
    T.fire("MERCHANT_CLOSED")
    T.advance(0.5)
    return rows(CP.Plan.Shut(ENCHANTING))
end

-- Session 1 reads the list through the window; session 2 reloads its saved data and sees the
-- guide shut, then open. Every view must be the open window's plan.
local function views(case)
    local out = {}
    character(case)
    login()
    out["1 open"] = opened()
    out["1 shut after the window"] = shut()
    local saved = copy(CP.charDB)

    character(case, copy(saved))
    login(true)
    out["2 shut after a reload"] = shut()
    out["2 open after a reload"] = opened()
    out["2 shut after the window"] = shut()

    -- The plans dropped (a settings context with none saved): the first solve is a shut one.
    local fresh = copy(saved)
    fresh.committed, fresh.lastPlan = nil, nil
    character(case, fresh)
    login(true)
    out["3 shut first, nothing planned"] = shut()
    out["3 open after it"] = opened()
    return out
end

local CASES = {
    { name = "a skill modifier", bonus = 10 },
    { name = "a recipe the game shows grey", grey = MINOR_HEALTH },
}

for _, case in ipairs(CASES) do
    T.test(("returning Enchanting with %s: one plan, window open or shut"):format(case.name), function()
        local out = views(case)
        local want = out["1 open"]
        T.ok(want:find("step:" .. RANK .. "-", 1, true) ~= nil, "the open plan starts at the rank: " .. want:sub(1, 80))
        local uses = want:find(":" .. MINOR_HEALTH .. ":", 1, true) ~= nil
        T.eq(uses, not case.grey, "the open plan uses Minor Health unless the game shows it grey")
        local bad = {}
        for _, name in ipairs(World.keys(out)) do
            print(("ENCHWIN|%s|%s|%s"):format(case.name, name, out[name]:sub(1, 200)))
            if out[name] ~= want then bad[#bad + 1] = name .. ": " .. firstDiff(out[name], want) end
        end
        T.eq(#bad, 0, table.concat(bad, "\n"))
    end)
end

-- The game's grey recipes are saved with the known ones, and only from a read list.
T.test("a read list saves the recipes the game shows grey", function()
    character(CASES[2])
    login()
    CP.Plan.Shut(ENCHANTING)
    T.eq(CP.charDB.grey, nil, "nothing read, nothing saved")
    opened()
    local grey = {}
    for _, id in ipairs(CP.charDB.grey and CP.charDB.grey[ENCHANTING] or {}) do grey[id] = true end
    T.ok(grey[MINOR_HEALTH], "Minor Health is saved grey")
    local guide = CP.Guides[ENCHANTING]
    for id in pairs(grey) do
        T.ok(id == MINOR_HEALTH or guide.recipes[id].grey <= RANK, ("%d is grey at %d"):format(id, RANK))
    end
end)
