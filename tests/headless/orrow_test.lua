-- A cheaper "or" row under the locked current step (owner, 2026-11-27: "offer the cheaper option as
-- an or row under current step"). The owner's Leatherworking at 165 holds Green Whelp Bracers 165-175
-- x10, saved under the old effort model; with 10 Heavy Hide in the bags Barbaric Shoulders costs
-- about 16 skins a craft against the bracers' 30. The step holds (decision 0007); the shoulders show
-- as an "or" row that says why, and picking it makes them the current step.

local CP = ProfLost
local GT = CP.GuideTab
local LW, SKINNING = 165, 393
local BRACERS, SHOULDERS, GLOVES, HIDE, SALT = 9202, 7151, 7156, 4235, 4289

-- Every trainer recipe up to `rank`, and the bracers' pattern.
local function known(rank)
    local out = { BRACERS }
    for id, r in pairs(CP.Guides[LW].recipes) do
        if (r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= rank then out[#out + 1] = id end
    end
    return out
end

-- Leatherworking 165 with Skinning 290 at level 40, the bracers saved as the current step.
-- `unknown` leaves one trainer recipe unlearned.
local function scene(bags, collect, unknown)
    local list = {}
    for _, id in ipairs(known(165)) do
        if id ~= unknown then list[#list + 1] = id end
    end
    MapWorld.begin({ zone = 1417, level = 40, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = 165, max = 225, known = list },
                                       [SKINNING] = { rank = 290, max = 300 } }, bags = bags })
    World.set(CP.db, "collect", collect ~= false)
    World.set(CP.charDB, "lastPlan", nil)
    local ctx = CP.Plan.Context(LW)
    World.set(CP.charDB, "committed", { [LW] = { [ctx] = {
        version = CP.Plan.COMMIT_VERSION, ctx = ctx, reach = true, shown = true, skill = 165, made = 0,
        steps = { { 165, 175, BRACERS, nil, 10, nil, nil, 142, 10 } } } } })
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel:Refresh()
end

local function current()
    for _, row in ipairs(GT.ui.rows) do
        if row.spell and not row.side and not (row.rank or row.train) then return row end
    end
end

-- The "or" rows right under the current step.
local function orsUnder()
    local out, seen = {}, false
    for _, row in ipairs(GT.ui.rows) do
        if row.spell and not row.side and not (row.rank or row.train) then
            if seen then break end
            seen = true
        elseif seen and row.side then
            out[#out + 1] = row
        end
    end
    return out
end

-- The cheaper "or" row of recipe `spell` under the current step, else the first one.
local function cheaperRow(spell)
    for _, row in ipairs(orsUnder()) do
        if row.cheaper and (not spell or row.spell == spell) then return row end
    end
end

local function cheaperText()
    local out = {}
    for _, row in ipairs(orsUnder()) do
        if row.cheaper then out[#out + 1] = row.spell .. " " .. row.cheaper end
    end
    return table.concat(out, "; ")
end

local function stepText(row) return row and ("%d %d-%d x%d"):format(row.spell, row.from, row.to, row.crafts) or "none" end

T.test("the owner's case: Barbaric Shoulders shows as an \"or\" row under the locked bracers, saying why", function()
    scene({ [HIDE] = 10 })
    T.eq(stepText(current()), ("%d 165-175 x10"):format(BRACERS), "the bracers step holds as saved")
    -- Guardian Gloves (4 Heavy Leather and a Cured Heavy Hide) are cheaper still, so they lead.
    local why = "Cheaper now: uses your 10 Heavy Hide"
    T.eq(cheaperText(), ("%d %s; %d %s"):format(GLOVES, why, SHOULDERS, why), "two cheaper rows, the cheapest first")
    T.eq(#orsUnder(), CP.Plan.CHEAPER_MAX, "at most CHEAPER_MAX rows")
    local _, list = CP.Plan.Cheaper(CP.Plan.Current())
    for _, f in ipairs(list or {}) do
        T.ok(f.cost <= f.was * (1 - CP.Plan.BETTER_BY), ("%d at least BETTER_BY cheaper: %.1f against %.1f"):format(f.spell, f.cost, f.was))
    end
    local alt = cheaperRow(SHOULDERS)

    GT.Pick(alt)
    T.advance(0.3)
    local status = GT.ui.details.status:GetText() or ""
    T.eq(stepText(current()), ("%d 165-175 x%d"):format(SHOULDERS, CP.Guide.Crafts(CP.Guides[LW].recipes[SHOULDERS], 165, 175)),
        "picking it makes Barbaric Shoulders the current step")
    T.eq(cheaperRow(BRACERS), nil, "the bracers are no cheaper \"or\" row")
    T.ok(status ~= "", "the card shows the new step: " .. status)
    CraftWorld.Close()
end)

T.test("the reason stands on the card of the \"or\" row", function()
    scene({ [HIDE] = 10 })
    local alt = cheaperRow(SHOULDERS)
    -- Following the recipe in the profession window picks the row without switching the step.
    T.ok(GT.Follow(SHOULDERS), "the row is picked")
    local status = GT.ui.details.status:GetText() or ""
    T.ok(status:find("Cheaper now: uses your 10 Heavy Hide", 1, true) ~= nil, "card: " .. status)
    T.eq(alt and stepText(current()), ("%d 165-175 x10"):format(BRACERS), "the bracers still lead")
    CraftWorld.Close()
end)

T.test("without the hides the bracers are the cheaper craft: no \"or\" row", function()
    scene({})
    T.eq(stepText(current()), ("%d 165-175 x10"):format(BRACERS), "the bracers step holds")
    T.eq(cheaperRow(), nil, "no cheaper row")
    CraftWorld.Close()
end)

T.test("buy mode: the same comparison by gold; hides a later step uses are not free", function()
    -- At list prices the bracers (6 Green Whelp Scale, 8 Heavy Leather) cost 10600 a craft and
    -- Guardian Gloves (4 Heavy Leather, a Cured Heavy Hide) 3850.
    scene({}, false)
    T.eq(stepText(current()), ("%d 165-175 x10"):format(BRACERS), "the bracers step holds")
    local alt = cheaperRow()
    T.eq(alt and alt.spell, GLOVES, "Guardian Gloves lead")
    T.eq(alt and alt.cheaper, "Cheaper now at today's prices", "the row says why")
    T.eq(#orsUnder(), CP.Plan.CHEAPER_MAX, "at most CHEAPER_MAX rows")
    CraftWorld.Close()

    -- The buy plan's Guardian Gloves step after the bracers takes the 10 hides, so they stay with it.
    scene({ [HIDE] = 10 }, false)
    local later = false
    for _, st in ipairs(CP.Plan.Current().plan) do
        if st.spell == GLOVES and st.from >= 175 then later = true end
    end
    T.ok(later, "a later Guardian Gloves step")
    alt = cheaperRow()
    T.eq(alt and alt.cheaper, "Cheaper now at today's prices", "the hides are kept for it")
    CraftWorld.Close()
end)

T.test("the reason never names a vendor good", function()
    -- The hides' curing takes the held Salt too, but Salt is bought on the way.
    scene({ [HIDE] = 10, [SALT] = 30 })
    local alt = cheaperRow(GLOVES)
    T.eq(alt and alt.cheaper, "Cheaper now: uses your 10 Heavy Hide", "the hides alone")
    CraftWorld.Close()
end)

T.test("buy mode: an unlearned trainer recipe pays its fee and reads trainer", function()
    -- Guardian Gloves' 2160 fee is spread over the points left to grey 205 at each skill, as the
    -- solve spreads it; the gloves still beat the bracers by far.
    scene({}, false, GLOVES)
    local alt = cheaperRow(GLOVES)
    T.ok(alt ~= nil and not alt.learned, "the unlearned gloves still show")
    local _, list = CP.Plan.Cheaper(CP.Plan.Current())
    local f = list and list[1]
    T.eq(f and f.spell, GLOVES, "the gloves lead")
    local fee = 0
    for s = 165, 174 do fee = fee + 2160 / (205 - s) end
    T.ok(f and math.abs(f.cost - (38500 + fee)) < 1, ("the fee is in the cost: %s, want %.1f"):format(tostring(f and f.cost), 38500 + fee))
    local _, _, info = GT.RowTexts(alt)
    T.eq(info, "trainer", "the row says where to learn it")
    CraftWorld.Close()
end)

T.test("check locked: the \"or\" row changes no locked step; picking it is the player asking", function()
    scene({})
    local st = {}
    local function look()
        return Rules.Locked({ CP = CP, line = LW, guide = CP.Guides[LW], live = CP.Plan.Current(), st = st, casts = {},
                              held = function(item) return CP.Purchases.Have(item) end })
    end
    T.eq(look(), {}, "first look")
    CraftWorld.SetBag(HIDE, 10)
    CP.Plan.Invalidate()
    CP.Panel:Refresh()
    T.ok(cheaperRow() ~= nil, "the row shows")
    T.eq(look(), {}, "the hides in the bags change no locked step")
    GT.Pick(cheaperRow(SHOULDERS))
    T.eq(current().spell, SHOULDERS, "switched")
    T.eq(look(), {}, "a pick of the row is the player asking")
    CraftWorld.Close()
end)
