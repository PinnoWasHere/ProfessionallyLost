-- nextup, the count: what the step card says the player must still gather or buy first.
-- The card's materials, in its order: a material whose have is under its need is short by
-- need - have. A vendor material ("buy N"; guide.items marks it sold without limit) is bought on the
-- way and counts only when nothing else does. A material the player makes ("make N", a prep item
-- whose recipe is learned) counts only when what it's made from is short too, in that raw material's
-- units: ceil(short / yield) runs, each raw's per-run count times the runs, less the bags.
--
-- ctx: guide, card ({ { item, have, need } }), learned (the plan's known recipes), count(item) (how
-- many of an item count as held).
-- Returns { item, short, raw, rawShort, buy }, or nil when the card is short of nothing that counts.

setfenv(1, Rules.ENV)

-- @rule[CardNeed] self: Next up's rule copied, over the guide's own items and prep tables
function Rules.CardNeed(ctx)
    local guide, card, learned, bags = ctx.guide, ctx.card, ctx.learned, ctx.count
    local items, prep = guide.items or {}, guide.prep or {}
    local function vendor(id) return items[id] ~= nil and items[id][2] == true end
    -- The raw material at the bottom of making `lack` of `id` that is short, and how many.
    local function lacking(id, lack)
        if vendor(id) then return nil end
        local maker = prep[id] and guide.recipes[prep[id]]
        if not maker or not (learned and learned[prep[id]]) then return id, lack end
        local runs = math.ceil(lack / (maker.yield or 1))
        for _, pair in ipairs(maker.reagents) do
            local more = pair[2] * runs - bags(pair[1])
            if more > 0 then
                local got, n = lacking(pair[1], more)
                if got then return got, n end
            end
        end
        return nil
    end
    for _, m in ipairs(card) do
        local short = (m.need or 0) - (m.have or 0)
        if short > 0 then
            local raw, n = lacking(m.item, short)
            if raw then return { item = m.item, short = short, raw = raw, rawShort = n } end
        end
    end
    -- Short of nothing else: the first vendor good it lacks is the thing to buy.
    for _, m in ipairs(card) do
        local short = (m.need or 0) - (m.have or 0)
        if short > 0 and vendor(m.item) then
            return { item = m.item, short = short, raw = m.item, rawShort = short, buy = true }
        end
    end
end
