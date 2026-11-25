-- splitrow (owner, SPLITROW-01: `/proflost preview tailoring 50` drew "Woolen Cape 73-75" then
-- "Woolen Cape 75-97"): two main craft rows of one recipe whose ranges touch never stand next to each
-- other in the drawn list. A locked row (Rules.LockSet, the world's own reading) keeps its range, so a
-- pair with a locked part is allowed. Any row between the two parts (a stop, an "or" row) is
-- something to do between them, so they are no pair.
--
-- ctx: CP, guide, rows, skill, dead, held(item) (bags and bank, for LockSet).

setfenv(1, Rules.ENV)

-- @rule[SplitRows] self: a pair is excused through Rules.LockSet
function Rules.SplitRows(ctx)
    local out = {}
    local main, at = {}, {}
    for i, row in ipairs(ctx.rows or {}) do
        if row.spell and row.recipe and not row.side and not (row.rank or row.train) then
            main[#main + 1] = row
            at[row] = i
        end
    end
    local locks = Rules.LockSet(ctx, main, ctx.skill, ctx.dead)
    for k = 2, #main do
        local a, b = main[k - 1], main[k]
        if at[b] == at[a] + 1 and a.spell == b.spell and a.to == b.from and not (locks[k - 1] or locks[k]) then
            out[#out + 1] = ("%s is two rows in a row, %d-%d and %d-%d, with nothing between them"):format(
                a.recipe.name, a.from, a.to, b.from, b.to)
        end
    end
    return out
end
