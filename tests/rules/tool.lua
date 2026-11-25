-- tools, the row half: the craft of `row` needs tool `item` and the bags hold none, so the row or its
-- card must name the tool and the player knows to get it before the craft.
--
-- ctx: guide, row, item, toolNames (the truth's tool names, or nil), words(row) (the row and its card
-- as the player reads them).

setfenv(1, Rules.ENV)

-- @rule[Tool] independent: the truth's tool names against the row and card text
function Rules.Tool(ctx)
    local guide, row, item = ctx.guide, ctx.row, ctx.item
    local name = ctx.toolNames and ctx.toolNames[item] or ("item " .. item)
    if ctx.words(row):lower():find(name:lower(), 1, true) then return {} end
    local maker
    for spell, r in pairs(guide.recipes) do
        if r.makes == item and (not maker or spell < maker) then maker = spell end
    end
    maker = maker and ("%s (spell %d)"):format(guide.recipes[maker].name, maker)
    return { ("%s (%s-%s) needs %s in the bags; the bags hold none, and neither the row nor its card names it%s"):format(
        row.recipe and row.recipe.name or "?", tostring(row.from), tostring(row.to), name,
        maker and ("; the guide's recipe " .. maker .. " makes it") or "; no guide recipe makes it") }
end
