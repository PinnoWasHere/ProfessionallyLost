local _, CP = ...
if CP.stopped then return end

-- Fallback list when no guide step applies. Pure logic over Professions.Recipes() output, so it runs headless.

local Fallback = {}
CP.Fallback = Fallback

-- Learned recipes that still give skill-ups. Orange first, then recipes you can
-- craft now, then by name.
function Fallback.Rank(recipes)
    local out = {}
    for _, r in ipairs(recipes) do
        if r.learned and r.canSkillUp and r.difficulty ~= CP.Professions.GREY then
            out[#out + 1] = r
        end
    end

    table.sort(out, function(a, b)
        if a.difficulty ~= b.difficulty then return a.difficulty < b.difficulty end
        local ac, bc = a.craftable > 0, b.craftable > 0
        if ac ~= bc then return ac end
        return a.name < b.name
    end)
    return out
end
