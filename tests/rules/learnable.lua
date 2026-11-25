-- learnable: every recipe a row offers to learn (a main step, an "or" row, a train stop) has a source
-- in the truth this character can use: learned with the profession, a trainer that serves its faction
-- (or any trainer, for a source that names none), a merchant or quest giver that serves it, or a
-- drop. A source that asks a spell the character lacks (a specialization: the truth's `requires`)
-- serves it not. A recipe the guide marks as a specialization's needs a specialization of the
-- profession the character holds.
--
-- ctx: guide, rows, cache (each recipe's answer while the character's specializations stay the
-- same), known (the world's known set), facts() (the truth), specs (the specializations the
-- character holds, by name), specKey, side, and the world's answers lacks(source),
-- specName(spell), teachers(id), sellers(item), serves(npc).

setfenv(1, Rules.ENV)

-- @rule[Learnable] independent: the truth's sources and the world's NPCs and specializations
function Rules.Learnable(ctx)
    local out = {}
    local guide, cache, known = ctx.guide, ctx.cache, ctx.known
    local f = ctx.facts()
    local held = ctx.specs

    -- Sellers the truth names but cannot place: Forever's favor vendors (Fritz Fizzle and
    -- Fizzlefuse for EZ-Thro Fireproof Fuse) carry no side and no spawn in classic-db.
    local function unplaced(npcs)
        if not (npcs and #npcs > 0) then return false end
        for _, e in ipairs(npcs) do
            local n = f.npcs and f.npcs[e]
            if not (n and n.side == "X" and n.spawned == false) then return false end
        end
        return true
    end

    local function why(id, r)
        local key = id .. "|" .. ctx.specKey
        if cache[key] ~= nil then return cache[key] end
        local answer = false
        if r.src == "specialization" and #held == 0 then
            answer = "the guide marks it a specialization's recipe, and the character has no specialization"
        else
            local t = f.recipes[id]
            local usable, seen, asks = false, {}, {}
            for _, s in ipairs(t and t.sources or {}) do
                seen[#seen + 1] = s.kind
                local lack = ctx.lacks(s)
                if lack then
                    asks[ctx.specName(lack)] = true
                elseif s.kind == "auto" or s.kind == "drop" then usable = true
                elseif s.kind == "trainer" then usable = usable or #ctx.teachers(id) > 0
                elseif (s.kind == "vendor" or s.kind == "reputation") and s.item then
                    usable = usable or #ctx.sellers(s.item) > 0 or unplaced(s.npcs)
                elseif s.kind == "quest" then
                    for _, e in ipairs(s.npcs or {}) do usable = usable or ctx.serves(e) == true end
                end
            end
            local names = {}
            for name in pairs(asks) do names[#names + 1] = name end
            table.sort(names)
            if not t then
                answer = "the truth has no such recipe"
            elseif not usable and #names > 0 then
                answer = ("every source asks %s, which the character lacks (it holds %s)"):format(
                    table.concat(names, " or "), #held > 0 and table.concat(held, ", ") or "no specialization")
            elseif not usable then
                answer = ("no source in the truth serves a %s character (sources: %s)"):format(ctx.side,
                    #seen > 0 and table.concat(seen, ", ") or "none")
            end
        end
        cache[key] = answer
        return answer
    end
    local idOf = {}
    for id, r in pairs(guide.recipes) do idOf[r] = id end
    for _, row in ipairs(ctx.rows or {}) do
        local list = {}
        if row.train then
            for _, r in ipairs(row.train.recipes or {}) do list[#list + 1] = { id = idOf[r], r = r, where = ("train at %d"):format(row.train.skill) } end
        elseif row.spell and row.recipe and row.learned == false and not (known ~= nil and known[row.spell] == true) then
            list[1] = { id = row.spell, r = row.recipe, where = ("%s%d-%d"):format(row.side and "or row " or "", row.from, row.to) }
        end
        for _, e in ipairs(list) do
            local bad = e.id and why(e.id, e.r)
            if bad then out[#out + 1] = ("%s (%s) is offered to learn: %s"):format(e.r.name, e.where, bad) end
        end
    end
    return out
end
