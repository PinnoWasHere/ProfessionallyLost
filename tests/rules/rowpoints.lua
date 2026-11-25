-- rowpoints (decision 0008): a main row's count, played from its start
-- with the game's chance, ends at the row's end. Each row is checked once, the first time it shows in
-- the saved plan (a new Plan.StepKey); later bag changes and dice are `forecast`'s concern.
--   * First the row's made materials that still give points: what the row needs of each, less the
--     bags and less the output of earlier main rows not used in between, made with the maker's chance.
--   * Then the row's drawn count (the current row's full count, from its saved start), point by point
--     with fractions, chance x ups, stopping at grey.
--   * It fails when the played end is more than `row.parts or 1` points off the row's end, either way.
--     A row ending at its recipe's grey passes at grey.
--
-- ctx: CP, line, guide, rows, seen (step keys already checked), live (the plan the guide tab draws),
-- recipes (the truth's recipes), chance(id, skill) (the game's chance and points a craft),
-- held(item) (bags and bank).
-- Returns the violations and notes for the trace.

setfenv(1, Rules.ENV)

Rules.ROWPOINTS_SLACK = 1   -- points a row's played end may sit off its end, per joined part

-- The game's chance of a skill-up and points a craft for recipe `r` (yellow, grey, ups) at skill `s`.
-- @rule[CraftChance] independent: the game's skill-up formula on a recipe's yellow and grey
function Rules.CraftChance(r, s)
    local ups = math.max(1, r.ups or 1)
    if s >= r.grey then return 0, ups end
    if s < r.yellow then return 1, ups end
    return Rules.Boost((r.grey - s) / (r.grey - r.yellow)), ups
end

-- A chance(id, skill) answer over the truth's recipes `recipes`, falling back to the guide's.
-- @rule[TruthChance] independent: the truth's recipes; the guide's only where the truth has none
function Rules.TruthChance(recipes, guide)
    return function(id, s)
        local r = recipes[id] or guide.recipes[id]
        if not r then return 0, 1 end
        return Rules.CraftChance(r, s)
    end
end

-- The skill `crafts` of recipe `id` take the character to from `from`, with fractions.
-- @rule[Play] independent: plays crafts through a given chance
function Rules.Play(chance, id, from, crafts)
    local x, left = from, crafts
    while left > 1e-9 do
        local s = math.floor(x)
        local p, ups = chance(id, s)
        if p <= 0 then break end
        local rate = p * ups
        local step = (s + 1 - x) / rate
        if left >= step then
            left, x = left - step, s + 1
        else
            x, left = x + left * rate, 0
        end
    end
    return x
end

-- @rule[RowPoints] self: plays each row with the truth's chance, but the rule-8 bound asks Plan.Locks
function Rules.RowPoints(ctx)
    local CP, guide, chance, seen = ctx.CP, ctx.guide, ctx.chance, ctx.seen
    local out = {}
    local live = ctx.live
    local c = CP.Plan.Committed(ctx.line)
    local notes = {}
    if not (live and live.guide == guide and c and c.steps) then return out, notes end
    local main = {}
    for _, row in ipairs(ctx.rows or {}) do
        if row.spell and row.recipe and not row.side and not (row.rank or row.train) then main[#main + 1] = row end
    end
    local locks
    for k, row in ipairs(main) do
        local f, at
        for i, step in ipairs(c.steps) do
            if step[3] == row.spell and step[2] == row.to then f, at = step, i end
        end
        local key = f and CP.Plan.StepKey(f) .. "/" .. tostring(row.parts or 1)
        if key and not seen[key] then
            seen[key] = true
            -- The plan's own claim. The current row plays from its saved start (a craft of something
            -- else may have moved the skill since) its saved count, never 0007's recount, which carries
            -- the dice.
            local count = k == 1 and math.max(f[5] or 0, CP.Guide.KeepCrafts(row.recipe, f[6])) or row.crafts
            local x = k == 1 and f[1] or row.from
            local said = {}
            for _, pair in ipairs(row.recipe.reagents or {}) do
                local item = pair[1]
                local maker = guide.prep and guide.prep[item]
                local mr = maker and guide.recipes[maker]
                if mr then
                    local supply = ctx.held(item)
                    for j = 1, k - 1 do
                        local o = main[j]
                        if o.recipe.makes == item then supply = supply + o.crafts * (o.recipe.yield or 1) end
                        for _, q in ipairs(o.recipe.reagents or {}) do
                            if q[1] == item then supply = math.max(0, supply - q[2] * o.crafts) end
                        end
                    end
                    local short = pair[2] * count - supply
                    if short > 0 and chance(maker, math.floor(x)) > 0 then
                        local runs = math.ceil(short / (mr.yield or 1))
                        x = Rules.Play(chance, maker, x, runs)
                        said[#said + 1] = ("%d %s first"):format(runs, mr.name)
                    end
                end
            end
            local ended = Rules.Play(chance, row.spell, x, count)
            local slack = (row.parts or 1) * Rules.ROWPOINTS_SLACK
            -- A maker a locked step blocks (rule 8): the next saved step starts at the row's end and is
            -- locked, and the maker still gives points there. Its high side is the lower of the maker's
            -- grey and the locked step's end.
            local high = row.to + slack
            local nextStep = at and c.steps[at + 1]
            local r = row.recipe
            local maker = r.makes and ((guide.prep or {})[r.makes] or (guide.craftOnly or {})[r.makes])
            if maker and nextStep and nextStep[1] == row.to and chance(row.spell, row.to) > 0 then
                locks = locks or CP.Plan.Locks(c, guide, live.prof.skill, live.learned, live.dead)
                if locks[at + 1] then
                    local t = ctx.recipes[row.spell] or r
                    high = math.max(high, math.min(t.grey, nextStep[2]))
                    if ended > row.to + slack and ended <= high then
                        notes[#notes + 1] = ("rowpoints: %s %d-%d ~%d plays to %.1f, past its end into locked %s %d-%d (rule 8, bound %d)"):format(
                            r.name, row.from, row.to, count, ended, guide.recipes[nextStep[3]] and guide.recipes[nextStep[3]].name or "?",
                            nextStep[1], nextStep[2], high)
                    end
                end
            end
            if ended < row.to - slack or ended > high then
                out[#out + 1] = ("%s %d-%d ~%d crafts%s plays to %.1f, not %d (slack %d)"):format(r.name,
                    row.from, row.to, count, #said > 0 and (", with " .. table.concat(said, ", ")) or "", ended, row.to, slack)
            end
        end
    end
    return out, notes
end
