-- A profession never opened is unread: its shut plan guesses the known recipes from the
-- spellbook, which may not answer for recipes (unverified on Forever). Entering the world
-- re-plans every profession a second later (GatherList replan -> Gather.UpdateAllNeeds ->
-- Plan.Shut). A plan saved from that guess held its current step (Plan.Locks) after the first
-- read: Tailoring 60/75 then led with "Train Journeyman" at 60 instead of crafting to 75 first
-- (ORDERLEAK-07). The guess is saved marked as one, and a read that proves it wrong starts afresh.

local CP = ProfLost
local Plan = CP.Plan
local LW, TAILOR = 165, 197
local DUROTAR = 1411

local function rows(live)
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        local kind = row.rank and "rank" or row.train and "train" or row.side and "or" or "step"
        out[#out + 1] = ("%s:%s-%s:%s:%s"):format(kind, tostring(row.from or row.at), tostring(row.to),
            tostring(row.spell), tostring(row.learned))
    end
    return table.concat(out, "\n")
end

-- A character with `profs`; the spellbook answers false for every recipe.
local function character(profs)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = profs })
    World.patch("C_SpellBook.IsSpellKnown", function() return false end)
    Plan.ForgetBook()
    World.onEnd(Plan.ForgetBook)
end

-- Profession `id`'s saved plans as guesses or not: { shown, last }, each true, false or nil (none).
local function guesses(id)
    local c, last = Plan.Committed(id), CP.charDB.lastPlan and CP.charDB.lastPlan[id]
    return { c and c.guess == true, last and last.guess ~= nil }
end

-- The unread plan was saved as a guess, and the first read solve replaced it with a plan that is not.
local function guessReplaced(before, after, where)
    T.eq(before[1], true, where .. ": the unread shown plan is saved as a guess")
    T.eq(before[2], true, where .. ": the unread last plan is saved as a guess")
    T.eq(after[1], false, where .. ": the read shown plan is no guess")
    T.eq(after[2], false, where .. ": the read last plan is no guess")
end

-- The plan for `line` at its first open, with nothing solved before.
local function firstOpen(profs, line)
    character(profs)
    CraftWorld.Open(line)
    T.advance(1)
    local want = rows(Plan.Current())
    CraftWorld.Close()
    T.advance(1)
    return want
end

-- Opens `line` for the first time and checks the plan matches `want`. Returns guesses() while open.
local function openMatches(line, want, where)
    CraftWorld.Open(line)
    T.advance(1)
    T.ok(Plan.Read(line), where .. ": read at the first open")
    T.eq(rows(Plan.Current()), want, where .. ": the plan is the first open's")
    local after = guesses(line)
    CraftWorld.Close()
    MapWorld.SettleGuides()
    return after
end

for _, case in ipairs({ { "login", true, false }, { "/reload", false, true } }) do
    local name, login, reload = case[1], case[2], case[3]
    T.test(name .. " with Tailoring never opened: the first open plans as if nothing ran before", function()
        local profs = { [TAILOR] = { rank = 60, max = 75 } }
        local want = firstOpen(profs, TAILOR)
        T.ok(want:find("^step:60%-%d+:") ~= nil, "control: crafts from 60 before training: " .. want)

        character(profs)
        T.fire("PLAYER_ENTERING_WORLD", login, reload)
        T.advance(3)
        local shut = Plan.Shut(TAILOR)
        T.ok(shut ~= nil and shut.unread, "the shut plan ran, unread")
        local before = guesses(TAILOR)
        guessReplaced(before, openMatches(TAILOR, want, name), name)
    end)
end

T.test("a profession learned this session: its unread plan gives way at the first open", function()
    local want = firstOpen({ [LW] = 100, [TAILOR] = 1 }, TAILOR)

    character({ [LW] = 100 })
    CraftWorld.Open(LW)
    T.advance(1)
    CraftWorld.Close()
    CraftWorld.AddProfession(TAILOR, 1)
    T.advance(3)
    local shut = Plan.Shut(TAILOR)
    T.ok(shut ~= nil and shut.unread, "the shut plan ran, unread")
    local before = guesses(TAILOR)
    local lw = Plan.Committed(LW)
    T.ok(lw ~= nil and not lw.guess, "the read profession's plan is saved, no guess")
    guessReplaced(before, openMatches(TAILOR, want, "learned"), "learned")
end)

T.test("a read profession's shut plan is still saved at login", function()
    character({ [TAILOR] = { rank = 60, max = 75 } })
    CraftWorld.Open(TAILOR)
    T.advance(1)
    local want = rows(Plan.Current())
    CraftWorld.Close()
    T.advance(1)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    Plan.Invalidate()
    T.fire("PLAYER_ENTERING_WORLD", true, false)
    T.advance(3)
    local saved = guesses(TAILOR)
    T.eq(saved[1], false, "the shown plan is saved, no guess")
    T.eq(saved[2], false, "the last plan is saved, no guess")
    T.eq(rows(Plan.Shut(TAILOR)), want, "the shut plan is the open one's")
    MapWorld.SettleGuides()
end)

T.test("a guess the read list confirms holds, as before", function()
    character({ [TAILOR] = { rank = 60, max = 75 } })
    World.patch("C_SpellBook.IsSpellKnown", function(id) return CraftWorld.state.profs[TAILOR].known[id] == true end)
    T.fire("PLAYER_ENTERING_WORLD", true, false)
    T.advance(3)
    local held = Plan.Committed(TAILOR)
    T.ok(held ~= nil and held.guess, "the unread plan is saved as a guess")
    CraftWorld.Open(TAILOR)
    T.advance(1)
    Plan.Current()
    T.ok(Plan.Committed(TAILOR) == held, "the read solve holds to the same saved plan")
    T.ok(not held.guess, "no longer a guess")
    CraftWorld.Close()
    MapWorld.SettleGuides()
end)
