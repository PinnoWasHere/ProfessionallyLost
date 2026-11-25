-- known and knowledge: the guide and the world agree on what the character knows.
--
-- ctx: CP, guide, rows, live, known (the world's known set, recipe id -> true), facts (the truth,
-- for names; optional).

setfenv(1, Rules.ENV)

-- known: never told to learn or buy a recipe the world knows. A profession ProfLost has not read yet
-- (`live.unread`) shows its recipes unlearned and asks the player to open it once. That is not being
-- told to learn them; Knowledge covers it.
-- @rule[Known] independent: the world's known set against the recipes the rows offer
function Rules.Known(ctx)
    local CP, guide, live, known = ctx.CP, ctx.guide, ctx.live, ctx.known
    local out, seen = {}, {}
    if live and live.unread then return out end
    local function told(id, how)
        if id and not seen[id] and known ~= nil and known[id] == true then
            seen[id] = true
            out[#out + 1] = ("%s is known, yet the guide %s"):format(Rules.NameOf(ctx, id), how)
        end
    end
    for _, row in ipairs(ctx.rows or {}) do
        if row.train then
            for _, r in ipairs(row.train.recipes or {}) do
                for id, k in pairs(guide.recipes) do
                    if k == r then told(id, ("says to train it at %d"):format(row.train.skill)) end
                end
            end
        elseif row.spell and row.recipe and row.learned == false then
            local word = CP.Guide.SourceWord and CP.Guide.SourceWord(row.recipe) or row.recipe.src
            told(row.spell, ("shows it unlearned (%s) at %s-%s"):format(tostring(word), tostring(row.from), tostring(row.to)))
        end
    end
    return out
end

-- knowledge: ProfLost knows every recipe the world knows, or says it has not read them.
-- @rule[Knowledge] independent: the world's known set against the plan's learned set
function Rules.Knowledge(ctx)
    local live = ctx.live
    if not live then return { "no plan at all" } end
    if live.unread then return {} end
    local out = {}
    local learned = live.learned or {}
    local alias = {}
    for guideID, liveID in pairs(live.alias or {}) do alias[liveID] = guideID end
    for id in pairs(ctx.known) do
        if not learned[id] and not (alias[id] and learned[alias[id]]) then
            out[#out + 1] = ("%s is known, and ProfLost plans as if it were not"):format(Rules.NameOf(ctx, id))
        end
    end
    table.sort(out)
    return out
end
