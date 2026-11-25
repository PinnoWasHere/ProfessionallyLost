-- cooldown, the planning half: a step whose recipe has a cooldown of at least COOLDOWN_MIN in the
-- game plans no more than one craft unless its card says so ("cooldown", "day", "hour"); a card that
-- has a material made by such a recipe made more than once says so too.
--
-- ctx: CP, guide, rows, facts() (the truth's recipes and their cooldowns), bags(item) (the bags'
-- count), words(row) (the row and its card as the player reads them).

setfenv(1, Rules.ENV)

Rules.COOLDOWN_MIN = 3600000   -- ms: an hour; a shorter cooldown does not hold a session up

-- @rule[Cooldown] independent: the truth's cooldowns against the row and card text
function Rules.Cooldown(ctx)
    local out = {}
    local CP, guide = ctx.CP, ctx.guide
    local f = ctx.facts()
    local function cd(id)
        local t = f.recipes[id]
        return t and t.cooldown and t.cooldown >= Rules.COOLDOWN_MIN and t.cooldown or nil
    end
    local function says(row)
        local text = ctx.words(row):lower()
        return text:find("cooldown") or text:find("%f[%a]days?%f[%A]") or text:find("%f[%a]hours?%f[%A]")
    end
    for _, row in ipairs(ctx.rows or {}) do
        if row.spell and row.recipe and not (row.rank or row.train) then
            local c = cd(row.spell)
            if c and (row.crafts or 0) > 1 and not says(row) then
                out[#out + 1] = ("%s (%d-%d) plans ~%d crafts; the game allows one every %.0f hours, and its card does not say so"):format(
                    row.recipe.name, row.from, row.to, math.floor(row.crafts + 0.5), c / 3600000)
            end
            for _, pair in ipairs(row.recipe.reagents or {}) do
                local maker = guide.prep and guide.prep[pair[1]]
                local mc = maker and cd(maker)
                if mc and pair[2] * (row.crafts or 0) > 1 + ctx.bags(pair[1]) and not says(row) then
                    out[#out + 1] = ("%s (%d-%d) needs %d %s, made one at a time every %.0f hours, and its card does not say so"):format(
                        row.recipe.name, row.from, row.to, pair[2] * math.floor(row.crafts + 0.5), CP.ItemName(pair[1]) or ("item " .. pair[1]),
                        mc / 3600000)
                end
            end
        end
    end
    return out
end
