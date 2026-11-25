local _, CP = ...
if CP.stopped then return end

-- The queue: every craft from the player's skill to a target skill, cut from the
-- live plan, with rank books in place and materials summed. Pure logic, so it runs
-- headless.

local Queue = {}
CP.Queue = Queue

local CAPS = { 75, 150, 225, 300 }

-- Highest skill the guide reaches.
function Queue.End(guide)
    local last = guide.steps[#guide.steps]
    return last and last.to or 0
end

-- The cap the player can level to now: `maxSkill` while above `skill`, else the next
-- rank cap (they are at their cap and must train first). Never past the guide's end.
local function reachable(guide, skill, maxSkill)
    local stop = Queue.End(guide)
    if maxSkill and maxSkill > skill then return math.min(maxSkill, stop) end
    for _, cap in ipairs(CAPS) do
        if cap > skill and cap <= stop then return cap end
    end
    return stop
end

-- Default target: the player's current cap (see reachable).
function Queue.DefaultTarget(guide, skill, maxSkill)
    return reachable(guide, skill, maxSkill)
end

-- Clamp a typed target into (skill, guide end]; nil when nothing is left to do.
function Queue.Clamp(guide, skill, target)
    local stop = Queue.End(guide)
    target = math.min(math.floor(tonumber(target) or 0), stop)
    if target <= skill then return nil end
    return target
end

-- The target in effect: the saved one when it is still ahead, else the default.
function Queue.Target(guide, skill, saved, maxSkill)
    return (saved and Queue.Clamp(guide, skill, saved))
        or Queue.Clamp(guide, skill, Queue.DefaultTarget(guide, skill, maxSkill))
end

-- Entries from `skill` to `target`, in order:
--   { kind = "craft", spell, recipe, from, to, crafts }
--   { kind = "rank", rank }    a rank to learn (book, trainer or quest) where PendingRanks puts it
--   { kind = "train", train }  a trainer visit before the crafts it unlocks
-- `plan` is a live plan from Solver.Plan; `maxSkill` the player's current cap.
-- `learned` (a set of recipe ids), when given, places trainer visits.
function Queue.Build(guide, skill, maxSkill, target, plan, learned)
    local crafts = {}
    for _, st in ipairs(plan) do
        if st.spell and st.from < target and st.to > skill then
            local recipe = guide.recipes[st.spell]
            local from, to = math.max(skill, st.from), math.min(st.to, target)
            local n = recipe and CP.Guide.Crafts(recipe, from, to)
            if n and n < math.huge and n > 0 then
                crafts[#crafts + 1] = { kind = "craft", spell = st.spell, recipe = recipe, from = from, to = to, crafts = n,
                                        gives = recipe.deskill and CP.Deskill.Gives(n) or nil }
            end
        end
    end
    local out = {}
    -- Without `learned`, every recipe counts as known, so no trainer visits.
    local known = learned or setmetatable({}, { __index = function() return true end })
    for _, e in ipairs(CP.Guide.WithStops(guide, crafts, known, skill, maxSkill)) do
        if e.rank then
            if e.rank.cap < target then out[#out + 1] = { kind = "rank", rank = e.rank } end
        elseif e.train then
            out[#out + 1] = { kind = "train", train = e.train }
        else
            out[#out + 1] = e
        end
    end
    return out
end

-- Materials for the whole queue: { { itemID, need, first } }, in queue order.
-- `first` is the index of the first entry that uses the material. What a disenchant step gives
-- (`gives`, rounded as Shared.DERound) covers the later entries' use first.
function Queue.Materials(entries)
    local out, byID, pool = {}, {}, {}
    for i, e in ipairs(entries) do
        if e.kind == "craft" then
            for _, pair in ipairs(e.recipe.reagents) do
                local use = pair[2] * e.crafts
                local take = math.min(pool[pair[1]] or 0, use)
                pool[pair[1]] = (pool[pair[1]] or 0) - take
                local m = byID[pair[1]]
                if not m and use - take > 0 then
                    m = { itemID = pair[1], need = 0, first = i }
                    byID[pair[1]] = m
                    out[#out + 1] = m
                end
                if m then m.need = m.need + use - take end
            end
            for item, n in pairs(e.gives or {}) do pool[item] = (pool[item] or 0) + CP.Shared.DERound(n) end
        end
    end
    return out
end

-- Order materials with `have` set: short ones first, soonest needed first, the
-- biggest shortfall breaking ties; complete ones last, in queue order.
function Queue.SortMaterials(mats)
    table.sort(mats, function(a, b)
        local sa, sb = a.have < a.need, b.have < b.need
        if sa ~= sb then return sa end
        if a.first ~= b.first then return a.first < b.first end
        local ga, gb = a.need - a.have, b.need - b.have
        if ga ~= gb then return ga > gb end
        return a.itemID < b.itemID
    end)
    return mats
end


-- Gold the queue still costs: materials short of `mats[i].have` at `priceFn`, and
-- the fees of its trainer visits and trainer ranks. Returns total, materials, training, and
-- whether any material had no price.
function Queue.Cost(guide, entries, mats, priceFn)
    local materials, training, missing = 0, 0, false
    for _, m in ipairs(mats) do
        local short = m.need - (m.have or 0)
        if short > 0 then
            local price = priceFn(m.itemID, guide.items and guide.items[m.itemID])
            if price then materials = materials + price * short else missing = true end
        end
    end
    for _, e in ipairs(entries) do
        if e.kind == "train" then training = training + (e.train.fee or 0) end
        if e.kind == "rank" then
            -- A trainer rank costs its fee, a book rank its price; a quest rank is free.
            local rank = e.rank
            if rank.kind == "trainer" then
                training = training + (rank.fee or 0)
            elseif rank.kind == nil and rank.item then
                training = training + (rank.price or 0)
            end
        end
    end
    return materials + training, materials, training, missing
end
