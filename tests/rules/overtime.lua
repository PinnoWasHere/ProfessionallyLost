-- The Working Overtime legacy perk as the truth applies it. The addon's own copy (Guide.Boost) is never read.

setfenv(1, Rules.ENV)

-- Assumption (owner, unconfirmed): the server multiplies a skill-up chance by 1 + PER_RANK x rank.
-- If it turns out to add instead, Rules.Boost is the one line to change.
-- `rank` is the character's perk rank, set by a run's `overtime` spec (GameWorld.begin).
Rules.Overtime = { PER_RANK = 0.04, rank = 0 }

-- A chance `p` (0 to 1) with the perk applied, capped at 1.
-- @rule[Boost] independent: the perk's effect on a skill-up chance, from the truth's own rank and constant
function Rules.Boost(p)
    local o = Rules.Overtime
    if o.rank <= 0 then return p end
    return math.min(1, p * (1 + o.PER_RANK * o.rank))
end
