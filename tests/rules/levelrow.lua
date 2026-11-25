-- levelrow: a level row ("<zone>: reach level N", row.levelGate) asks a level the character has not
-- reached yet. One that asks a level it already has is a row drawn for an older level.
--
-- ctx: row, level, zoneName(zone) (the world's name for the zone).

setfenv(1, Rules.ENV)

-- @rule[LevelRow] independent: the world's level against the level the row asks
function Rules.LevelRow(ctx)
    local row, level = ctx.row, ctx.level
    local gate = row and row.levelGate
    if not gate or level < gate.need then return {} end
    local band = row.gather or row.fish
    return { ("the row %d-%d still reads %s: reach level %d at level %d (drawn for level %s)"):format(row.from, row.to,
        ("%s (%d)"):format(ctx.zoneName(band.zone), band.zone), gate.need, level, tostring(gate.have)) }
end
