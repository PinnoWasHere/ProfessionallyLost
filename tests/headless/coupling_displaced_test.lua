-- A recipe another profession lets in that wins points and then loses all of them to the settle
-- pass shows no row, so nothing can name that profession. The plan must then be the plan without
-- that recipe (RELFIX-04: Tailoring's Bolt of Linen Cloth let Sandpaper into Engineering's plan, the
-- settle pass gave its points to Heavy Blasting Powder, and Flying Tiger Goggles lost nine crafts).

local CP = ProfLost

local MAKER, USER, GEAR, COUPLED = 1, 2, 3, 4
local RAW, PREP, GEAR_RAW, COUPLED_RAW, GOGGLES = 101, 102, 103, 104, 105
local TAILORING = 197

-- A maker whose powder a later step uses, a step that makes craft-only gear (the settle pass
-- never overwrites it), and a cheaper step that only the coupling lets in.
local guide = {
    name = "Coupling displaced",
    recipes = {
        [MAKER] = { name = "Powder", src = "trainer", learn = 1, yellow = 10, grey = 40, ups = 1,
                    reagents = { { RAW, 1 } }, makes = PREP, step = true },
        [USER] = { name = "Bomb", src = "trainer", learn = 30, yellow = 60, grey = 70, ups = 1,
                   reagents = { { PREP, 2 } }, step = true },
        [GEAR] = { name = "Goggles", src = "trainer", learn = 10, yellow = 20, grey = 30, ups = 1,
                   reagents = { { GEAR_RAW, 1 } }, makes = GOGGLES, step = true },
        [COUPLED] = { name = "Sandpaper", src = "trainer", learn = 10, yellow = 20, grey = 30, ups = 1,
                      reagents = { { COUPLED_RAW, 1 } }, step = true },
    },
    items = {},
    prep = { [PREP] = MAKER },
    craftOnly = { [GOGGLES] = true },
}

local PRICES = { [RAW] = 3, [GEAR_RAW] = 2, [COUPLED_RAW] = 1 }
local function price(item) return PRICES[item] end

local function solo(id) return id ~= COUPLED end
local plain = {
    allow = solo,
    price = price,
    causes = function(id) return id == COUPLED and { TAILORING } or {} end,
    touched = function(id) return id == COUPLED end,
}

local function shape(steps)
    local out = {}
    for _, st in ipairs(steps) do
        out[#out + 1] = ("%s %d-%d"):format(st.spell and guide.recipes[st.spell].name or "-", st.from, st.to)
    end
    return table.concat(out, "; ")
end

T.test("a coupled recipe the settle pass displaces leaves the plan as without it", function()
    local alone = CP.Solver.Plan(guide, 1, {}, price, solo, nil, {}, {})
    local with = CP.Solver.Plan(guide, 1, {}, price, nil, nil, {}, { plain = plain })
    for _, st in ipairs(with) do
        T.ok(st.spell ~= COUPLED, "Sandpaper keeps no step: " .. shape(with))
    end
    T.eq(shape(with), shape(alone), "the plan is the plan without the coupled recipe")
end)

T.test("a coupled recipe that keeps a step stays in the plan", function()
    -- Without the powder's later use nothing displaces Sandpaper, so it keeps its points.
    local user = guide.recipes[USER]
    World.set(user, "reagents", { { RAW, 1 } })
    local with = CP.Solver.Plan(guide, 1, {}, price, nil, nil, {}, { plain = plain })
    local kept = false
    for _, st in ipairs(with) do
        if st.spell == COUPLED then kept = true end
    end
    T.ok(kept, "Sandpaper keeps its step: " .. shape(with))
    T.ok(with.plain ~= nil, "the plan without the coupling is solved beside it")
end)
