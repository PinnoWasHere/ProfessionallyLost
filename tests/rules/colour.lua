-- agree, colours: ProfLost's colour for each recipe at `skill` equals the game's, from the world's own
-- rule on the truth's yellow and grey, never ProfLost's.
--
-- ctx: CP, guide, skill, recipes (the truth's recipes), colour(recipe, skill) (the game's colour).
-- Returns the violations and how many recipes were compared.

setfenv(1, Rules.ENV)

-- @rule[Colour] independent: the world's colour rule on the truth's yellow and grey
function Rules.Colour(ctx)
    local CP, skill, truth = ctx.CP, ctx.skill, ctx.recipes
    local out, n = {}, 0
    local recipes = ctx.guide.recipes
    for _, id in ipairs(Rules.Keys(recipes)) do
        local r, t = recipes[id], truth[id]
        if t and t.yellow and t.grey then
            n = n + 1
            local want, got = ctx.colour(t, skill), CP.Professions.DifficultyAt(r, skill)
            if want ~= got and #out < 3 then
                out[#out + 1] = ("colour: %s at skill %d is %d in ProfLost, %d in the game (yellow %d, grey %d)"):format(
                    r.name or tostring(id), skill, got, want, t.yellow, t.grey)
            end
        end
    end
    return out, n
end
