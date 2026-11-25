local _, CP = ...
if CP.stopped then return end

-- While you're there. A step that sends the player to a far trainer or vendor lists what else
-- that NPC's town offers that later steps of the player's guides need, and the gold to bring,
-- so one trip covers several steps. The step card shows it (GuideTab). The plan never moves.

local Trip = {}
CP.Trip = Trip

-- An NPC on another continent or more than FAR_YARDS away is far.
Trip.FAR_YARDS = 1000

-- NPCs within TOWN_YARDS of the trip's NPC stand in its town.
Trip.TOWN_YARDS = 400

-- Training lists only what the player can learn on this visit, at the trip's skill and the
-- player's level. Patterns, rank books and vendor goods count steps that start within
-- STOCK_AHEAD points.
Trip.STOCK_AHEAD = 50

-- Names a line shows before "+N more", and lines above the gold line.
Trip.NAMES = 3
Trip.LINES = 3

Trip.LEAD = "While you're there, "
Trip.GOLD = "Bring %s for this trip"
Trip.UNPRICED = ", plus the patterns"

local SIDE = { Alliance = "A", Horde = "H" }

-- True when `npc` ({ continent, x, y }) is far from the player. Unknown spots are near.
function Trip.Far(npc)
    if not (npc and npc.continent and npc.x and npc.y) then return false end
    local continent, px, py = CP.Waypoint.PlayerWorld()
    if not (continent and px and py) then return false end
    if continent ~= npc.continent then return true end
    return (npc.x - px) ^ 2 + (npc.y - py) ^ 2 > Trip.FAR_YARDS ^ 2
end

-- The first of `entries` (creature ids in `npcs`) friendly to the player with a spawn in the
-- town of `at`, or nil. A roaming vendor stands in no town.
function Trip.InTown(at, entries, npcs)
    if not (at and npcs) then return nil end
    local side = SIDE[UnitFactionGroup("player")]
    local reach = Trip.TOWN_YARDS ^ 2
    for _, entry in ipairs(entries or {}) do
        local npc = npcs[entry]
        if npc and (npc[2] == "N" or npc[2] == side) and not npc[4] then
            for _, s in ipairs(npc[3] or {}) do
                if s[1] == at.continent and (s[2] - at.x) ^ 2 + (s[3] - at.y) ^ 2 <= reach then return entry end
            end
        end
    end
    return nil
end

-- True when the player, at skill `base` and level `have`, can learn it now.
local function ready(learn, base, level, have)
    return (learn or 0) <= base and (not (level and have) or have >= level)
end

-- One thing to train or buy.
local function add(list, name, cost)
    list[#list + 1] = { name = name, cost = cost }
end

-- Ranks and trainer recipes of `rows` that a trainer in the town teaches.
local function training(g, rows, out)
    for _, row in ipairs(rows) do
        local rank = row.rank
        if rank and rank.kind == "trainer" and not g.seen[rank] and ready(rank.skill, g.base, rank.level, g.level)
            and Trip.InTown(g.at, rank.npcs, g.guide.npcs) then
            g.seen[rank] = true
            add(out, rank.name, rank.fee or 0)
        elseif row.train and not row.train.pattern then
            for _, r in ipairs(row.train.recipes) do
                local entry = not g.seen[r] and ready(r.learn, g.base, r.level, g.level) and Trip.InTown(g.at, r.npcs, g.guide.npcs)
                if entry then
                    g.seen[r] = true
                    add(out, r.name, CP.Guide.Fee(r, entry))
                end
            end
        end
    end
end

-- A vendor pattern the town sells that the player can buy: the bags don't hold it and the
-- standing it needs isn't known to be short.
local function pattern(g, r, out)
    if g.seen[r] or not r.pattern or CP.Purchases.Have(r.pattern) > 0 or CP.Guide.HasStanding(r) == false then return end
    if not Trip.InTown(g.at, r.npcs, g.guide.npcs) then return end
    g.seen[r] = true
    local it = g.guide.items and g.guide.items[r.pattern]
    out[#out + 1] = { name = r.name .. " pattern", cost = it and it[1] or nil, unpriced = not (it and it[1]) }
end

-- Patterns and rank books of `rows` the town sells, and the vendor goods their crafts use
-- (`goods`, item -> { need, price }). A good whose data names its sellers counts when one
-- stands in the town. One without named sellers counts for the trip's own profession only,
-- since its supplies vendor stands near its trainer.
local function buying(g, rows, out, goods)
    local reach = g.base + Trip.STOCK_AHEAD
    for _, row in ipairs(rows) do
        local from = row.from or (row.train and row.train.skill) or row.at or 0
        if from <= reach then
            local rank, r = row.rank, row.recipe
            if rank and not rank.kind and rank.item and not g.seen[rank]
                and Trip.InTown(g.at, rank.npcs, g.guide.npcs) then
                g.seen[rank] = true
                out[#out + 1] = { name = rank.name, cost = rank.price or 0 }
            elseif row.train and row.train.pattern then
                pattern(g, row.train.recipes[1], out)
            elseif r and row.learned == false and (r.src == "vendor" or r.src == "reputation") then
                pattern(g, r, out)
            end
            if r and not (row.rank or row.train or row.side) and not CP.Deskill.Is(r) and (row.crafts or 0) > 0 then
                for _, pair in ipairs(r.reagents or {}) do
                    local it = g.guide.items and g.guide.items[pair[1]]
                    local sold = it and it[2] and (it.vendors and Trip.InTown(g.at, it.vendors, g.guide.npcs)
                        or not it.vendors and g.own)
                    if sold then
                        local e = goods[pair[1]] or { need = 0, price = it[1] or 0 }
                        goods[pair[1]] = e
                        e.need = e.need + pair[2] * row.crafts
                    end
                end
            end
        end
    end
end

-- What else the trip's town offers. `trip` = { npc, guide, skill, rows, own, uses, skip }: the
-- NPC the card names, the step's guide, the skill the player goes at, that guide's rows after
-- the trip's row, the trip's own cost in copper, the vendor goods the trip's own step buys
-- (item -> count), and the recipes and ranks the trip itself learns (a set). `others` =
-- { { guide, name, skill, rows } }, the player's other guided professions. Returns
-- { train, others = { { name, items } }, buy, gold, unpriced }.
function Trip.Offer(trip, others)
    local level = CP.Guide.PlayerLevel()
    local at = trip.npc
    local function scope(guide, base)
        local seen = {}
        for k in pairs(trip.skip or {}) do seen[k] = true end
        return { guide = guide, base = base, level = level, at = at, seen = seen, own = guide == trip.guide }
    end
    local offer = { train = {}, others = {}, buy = {}, gold = trip.own or 0 }
    local goods = {}
    local mine = scope(trip.guide, trip.skill)
    training(mine, trip.rows or {}, offer.train)
    buying(mine, trip.rows or {}, offer.buy, goods)
    for _, o in ipairs(others or {}) do
        local g = scope(o.guide, o.skill)
        local items = {}
        training(g, o.rows or {}, items)
        if #items > 0 then offer.others[#offer.others + 1] = { name = o.name, items = items } end
        buying(g, o.rows or {}, offer.buy, goods)
    end
    local ids = {}
    for item in pairs(goods) do ids[#ids + 1] = item end
    table.sort(ids)
    for _, item in ipairs(ids) do
        local e = goods[item]
        local short = math.ceil(e.need - (C_Item.GetItemCount(item, true) or 0) - (trip.uses and trip.uses[item] or 0))
        if short > 0 then
            local name = CP.ItemName(item)
            if not name or name == "" then name = "item " .. item end
            offer.buy[#offer.buy + 1] = { name = ("%s x%d"):format(name, short), cost = e.price * short }
        end
    end
    for _, list in ipairs({ offer.train, offer.buy }) do
        for _, it in ipairs(list) do
            offer.gold = offer.gold + (it.cost or 0)
            if it.unpriced then offer.unpriced = true end
        end
    end
    for _, o in ipairs(offer.others) do
        for _, it in ipairs(o.items) do offer.gold = offer.gold + (it.cost or 0) end
    end
    return offer
end

-- "A, B, C +2 more".
local function names(list)
    local out = {}
    for i, it in ipairs(list) do
        if i > Trip.NAMES then
            out[#out] = out[#out] .. (" +%d more"):format(#list - Trip.NAMES)
            break
        end
        out[#out + 1] = it.name
    end
    return table.concat(out, ", ")
end

-- The card's lines for `offer`, the gold line last, or nil when the town offers nothing more.
function Trip.Lines(offer)
    local lines = {}
    if #offer.train > 0 then lines[#lines + 1] = "Train " .. names(offer.train) end
    if #offer.others > 0 then
        local parts = {}
        for _, o in ipairs(offer.others) do parts[#parts + 1] = ("%s: %s"):format(o.name, names(o.items)) end
        lines[#lines + 1] = "Other trainers here: " .. table.concat(parts, "; ")
    end
    if #offer.buy > 0 then lines[#lines + 1] = "Buy " .. names(offer.buy) end
    if #lines == 0 then return nil end
    while #lines > Trip.LINES do table.remove(lines) end
    lines[1] = Trip.LEAD .. lines[1]:sub(1, 1):lower() .. lines[1]:sub(2)
    local fmt = CP.Pricing and CP.Pricing.Format or tostring
    lines[#lines + 1] = Trip.GOLD:format(fmt(offer.gold)) .. (offer.unpriced and Trip.UNPRICED or "")
    return lines
end

-- The card's block for a trip, or nil for a near NPC or a town with nothing more to do.
function Trip.Text(trip, others)
    if not Trip.Far(trip.npc) then return nil end
    local lines = Trip.Lines(Trip.Offer(trip, others))
    return lines and table.concat(lines, "\n") or nil
end
