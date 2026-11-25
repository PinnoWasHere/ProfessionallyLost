-- causes (fishing-tag lane, 2026-11-18: Storm Gauntlets' Fishing cause spread onto three other rows):
-- every profession a main or stop row's info names is among that row's own causes, the professions
-- the plan says picked its recipe (`live.causes(spell, recipe)`; "disenchant" for Enchanting's
-- credit). A stop row has no recipe of its own, so it names none.
--
-- ctx: CP, live, rows.

setfenv(1, Rules.ENV)

-- @rule[Causes] self: a row's words against the plan's own causes (live.causes, GuideTab.CauseWords)
function Rules.Causes(ctx)
    local CP, live = ctx.CP, ctx.live
    local out = {}
    if not (live and live.causes) then return out end
    for _, row in ipairs(ctx.rows or {}) do
        local words = row.cause and not row.side and CP.GuideTab.CauseWords(row.cause) or ""
        if words ~= "" then
            local own = row.spell and not (row.rank or row.train) and live.causes(row.spell, row.recipe) or {}
            local allowed = {}
            for _, line in ipairs(own) do
                allowed[CP.Shared.Name(line)] = true
                if line == CP.Shared.ENCHANTING and own.de then allowed[CP.GuideTab.DE_MARK] = true end
            end
            for word in words:gmatch("[^,]+") do
                word = word:gsub("^%s+", ""):gsub("%s+$", "")
                if not allowed[word] then
                    out[#out + 1] = ("%s (%s-%s) names %s, which did not pick that row"):format(
                        row.recipe and row.recipe.name or "a stop", tostring(row.from or row.at), tostring(row.to or ""), word)
                end
            end
        end
    end
    return out
end
