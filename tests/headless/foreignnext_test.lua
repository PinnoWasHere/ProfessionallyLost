-- Next up and the launcher follow the guide's step once another addon's window shows the
-- recipe list (simulator finding, 2026-11-16, buy mode: a returning Alchemist seen through
-- another addon's window got Next up for Elixir of Minor Defense while the guide's current
-- step was Minor Mana Potion 40-50). The step Next up reads was saved from the plan made
-- before the list was read, and nothing saved it again.

local CP = ProfLost
local ALCHEMY, MANA, SILVERLEAF = 171, 2331, 765

-- Every trainer recipe up to `skill`, as a returning character knows them.
local function returning(skill)
    local known = {}
    for id, r in pairs(CP.Guides[ALCHEMY].recipes) do
        if (r.src == "trainer" or r.src == "auto") and r.learn <= skill then known[#known + 1] = id end
    end
    table.sort(known)
    return known
end

for _, collect in ipairs({ false, true }) do
    T.test(("another addon's window: the saved next step is the guide's (%s)"):format(collect and "collect" or "buy"), function()
        World.set(CP.db, "collect", collect)
        -- Buy mode: Minor Mana Potion is the cheapest to make once known, but its fee keeps
        -- it out while ProfLost has read nothing, so the read moves the plan's first step.
        World.set(CP.Pricing, "Get", function(item) return item == SILVERLEAF and 30 or 10 end)
        World.set(CP.Guides[ALCHEMY].recipes[MANA], "fee", 50000)
        World.patch("C_SpellBook.IsSpellKnown", function() return false end)
        MapWorld.begin({ zone = 1453, level = 40, side = "Alliance" })
        CraftWorld.begin({ professions = { [ALCHEMY] = { rank = 40, max = 75, known = returning(40) } } })
        -- Login with no window: Next up has what ProfLost knew then (nothing read).
        CP.Gather.UpdateAllNeeds()
        CraftWorld.Open(ALCHEMY, nil, "foreign")
        CP.Plan.Invalidate()
        local live = CP.Window.LiveFor(ALCHEMY)
        T.ok(live and not live.unread, "the list read through the window is used")
        local st = live and CP.Gather.NextStep(live.guide, live.prof, live.plan, live.learned)
        local saved = CP.charDB.nextStep and CP.charDB.nextStep[ALCHEMY]
        T.ok(st ~= nil and saved ~= nil, "a step on both sides")
        if st and saved then
            T.eq(saved.spell, st.spell, ("Next up's step %s, the guide's %s"):format(tostring(saved.name), tostring(st.name)))
            T.eq(saved.from, st.from, "same range")
        end
        CraftWorld.Close()
    end)
end
