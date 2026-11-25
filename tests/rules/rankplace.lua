-- rankplace (tester, 2026-11-18: "put the skill upgrade step at where it's needed"): a rank row sits
-- no earlier than the first of (a) its cap and (b) the first trainer visit from its learn skill up to
-- below its cap, where the player goes anyway. A main craft row after the rank row that starts below
-- that skill means the player was sent to train before it was needed.
-- The current row is allowed through the cap (SPLITROW-01): a locked step planned while the rank rode
-- a trainer visit holds its range when the visit goes, and the rank it now needs inside it leads it.
--
-- ctx: rows.

setfenv(1, Rules.ENV)

-- @rule[RankPlace] independent: the tester's placement rule over the drawn rows
function Rules.RankPlace(ctx)
    local rows = ctx.rows
    local out = {}
    local current
    for _, row in ipairs(rows or {}) do
        if row.spell and not row.side and not (row.rank or row.train) then current = row break end
    end
    for i, row in ipairs(rows or {}) do
        local rank = row.rank
        if rank then
            local need = rank.cap
            for _, other in ipairs(rows) do
                local t = other.train
                if t and t.skill >= rank.skill and t.skill < rank.cap and t.skill < need then need = t.skill end
            end
            for j = i + 1, #rows do
                local st = rows[j]
                if st == current and st.to > rank.cap then break end
                if st.spell and not st.side and not (st.rank or st.train) and st.from < need then
                    out[#out + 1] = ("%s sits before %s %d-%d, but is needed only at %d (%s)"):format(
                        rank.name, st.recipe and st.recipe.name or tostring(st.spell), st.from, st.to, need,
                        need == rank.cap and "its cap" or "the trainer visit there")
                    break
                end
            end
        end
    end
    return out
end
