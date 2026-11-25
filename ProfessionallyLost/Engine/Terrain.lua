local _, CP = ...
if CP.stopped then return end

-- Where a zone can be walked, guessed from where things spawn: creatures, herbs, ore
-- and GatherMate2's finds all sit on ground players reach, so cells near them count as
-- open and the rest (ridges, cliffs) cost UNKNOWN times as much to cross. Water round
-- fishing pools and the other faction's towns (their trainers and vendors) cost more
-- again, so a route crosses them only when nothing else connects. Ground near creatures
-- well above the player is walkable ground with a small toll: a path leans round it when
-- that costs little, and never swings wide. Routes measure stops by shortest path over
-- this grid and draw that path. It is a guess: a valley nothing spawns in reads as rough.

local Terrain = {}
CP.Terrain = Terrain

Terrain.CELL_YD = 50       -- grid cell size
Terrain.REACH = 1          -- cells around a spawn that count as open (wider pulls shore water open)
Terrain.UNKNOWN = 8        -- cost of crossing a cell nothing spawns near
Terrain.WATER = 8          -- cells round a fishing pool

-- Cells round creatures DANGER_LEVELS or more above the player. A path walks at most
-- DANGER - 1 extra yards (10%) to keep a yard off them.
Terrain.DANGER = 1.1
Terrain.DANGER_LEVELS = 4
Terrain.TOWN = 40          -- the other faction's towns
Terrain.TOWN_REACH = 4     -- cells round each of their trainers and vendors (200 yd)
Terrain.MIN_OPEN = 0.06    -- below this share of open cells the data is too thin to judge
Terrain.LEARN_EVERY = 2    -- seconds between footprints
Terrain.LEARN_BATCH = 25   -- new cells learned before routes are re-solved with them

local cache = {}
Terrain.work = 0   -- cells settled by path searches, for measuring


local SIDE = { Alliance = "A", Horde = "H" }

-- The other faction's NPC spawns by zone, { [zone] = { { x, y } } }: trainers and
-- vendors from every guide plus the gathering trainers. Built once per faction.
local towns = {}

local resets = 0   -- counts resets, so a grid built across one by a yielding job isn't kept

function Terrain.Reset()
    resets = resets + 1
    wipe(cache)
    wipe(towns)
end
local function enemyTowns(side)
    local mine = SIDE[side]
    if not mine then return {} end
    if towns[side] then return towns[side] end
    local out, seen = {}, {}
    local function add(npc)
        if npc[2] ~= "N" and npc[2] ~= mine then
            for _, at in ipairs(npc[3] or {}) do
                local key = at[1] .. ":" .. math.floor(at[2]) .. ":" .. math.floor(at[3])
                if not seen[key] then
                    seen[key] = true
                    local zone, x, y = CP.Waypoint.SpawnPos(at)
                    if zone then
                        out[zone] = out[zone] or {}
                        table.insert(out[zone], { x, y })
                    end
                end
            end
        end
    end
    for _, g in pairs(CP.Guides or {}) do
        for _, npc in pairs(g.npcs or {}) do add(npc) end
    end
    local D = CP.GatherData
    for _, npc in pairs(D.rankNpcs or {}) do add(npc) end
    for _, npc in pairs(D.fishing and D.fishing.npcs or {}) do add(npc) end
    towns[side] = out
    return out
end
Terrain.EnemyTowns = enemyTowns

-- Fishing pools GatherMate2 records, by name.
local POOL_WORDS = { "School", "Pool", "Wreckage", "Floating" }
local function isPool(name)
    for _, w in ipairs(POOL_WORDS) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

-- The zone's grid: { cols, rows, cell, w, h, open = { [index] = true }, cost = { [index]
-- = n }, danger = { [index] = true } }, or false when the zone has too little spawn data.
-- `danger` holds the charged cells that are walkable ground near stronger creatures, not
-- water or a town. `ctx` = { side, level }.
-- `tick` (optional) runs once per spawn cluster and node, for a solver that yields.
function Terrain.Grid(zone, w, h, ctx, tick)
    ctx = ctx or {}
    local key = table.concat({ zone, ctx.side or "", ctx.level or 0 }, ":")
    if cache[key] ~= nil then return cache[key] end
    local began = resets
    local cell = Terrain.CELL_YD
    local cols, rows = math.max(1, math.ceil(w / cell)), math.max(1, math.ceil(h / cell))
    local open, cost, count = {}, {}, 0
    local danger, water, town = {}, {}, {}   -- why each charged cell costs
    local function each(x, y, reach, fn)
        local cx, cy = math.floor(x * w / cell), math.floor(y * h / cell)
        for dy = -reach, reach do
            for dx = -reach, reach do
                local c, r = cx + dx, cy + dy
                if c >= 0 and r >= 0 and c < cols and r < rows and dx * dx + dy * dy <= reach * reach then
                    fn(r * cols + c)
                end
            end
        end
    end
    local function mark(x, y)
        each(x, y, Terrain.REACH, function(i)
            if not open[i] then open[i], count = true, count + 1 end
        end)
    end
    local function charge(x, y, reach, n, why)
        each(x, y, reach, function(i)
            cost[i] = math.max(cost[i] or 1, n)
            why[i] = true
        end)
    end
    local D = CP.GatherData
    local z = D.zones[zone]
    for entry in pairs(z and z.mobs or {}) do
        local m = D.mobs[entry]
        local strong = ctx.level and m and m[2] >= ctx.level + Terrain.DANGER_LEVELS
        for _, c in ipairs(CP.Gather.Clusters(zone, "mobs", entry, tick)) do
            mark(c[1], c[2])
            if strong then charge(c[1], c[2], 1, Terrain.DANGER, danger) end
            if tick then tick() end
        end
    end
    for entry in pairs(z and z.nodes or {}) do
        local n = D.nodes[entry]
        local pool = n and n[4] == CP.Gather.FISHING
        for _, c in ipairs(CP.Gather.Clusters(zone, "nodes", entry, tick)) do
            if pool then charge(c[1], c[2], 1, Terrain.WATER, water) else mark(c[1], c[2]) end
            if tick then tick() end
        end
    end
    for name, spots in pairs(CP.GatherMate and CP.GatherMate.Nodes(zone) or {}) do
        local pool = isPool(name)
        for _, sp in ipairs(spots) do
            if pool then charge(sp[1], sp[2], 1, Terrain.WATER, water) else mark(sp[1], sp[2]) end
            if tick then tick() end
        end
    end
    for _, t in ipairs(ctx.side and enemyTowns(ctx.side)[zone] or {}) do
        charge(t[1], t[2], Terrain.TOWN_REACH, Terrain.TOWN, town)
    end

    -- Where the player has been: walked cells are ground whatever the spawns say,
    -- swum cells are water. Walking clears a water mark, never a town or creatures.
    -- Footprints come in CELL_YD cells like the grid's own.
    for i, kind in pairs(CP.db and CP.db.footprints and CP.db.footprints[zone] or {}) do
        if i < cols * rows then
            if kind == 2 then
                cost[i], water[i] = math.max(cost[i] or 1, Terrain.WATER), true
            elseif not cost[i] or (water[i] and not town[i]) then
                water[i] = nil
                cost[i] = danger[i] and Terrain.DANGER or nil
                if not cost[i] and not open[i] then open[i], count = true, count + 1 end
            end
        end
    end
    -- A charged cell isn't open ground: smoothing and straight lines keep off it.
    for i in pairs(cost) do
        if open[i] then open[i], count = nil, count - 1 end
    end
    -- Creatures' ground under water or a town is that, not walkable ground.
    for i in pairs(danger) do
        if water[i] or town[i] then danger[i] = nil end
    end
    local grid = count >= Terrain.MIN_OPEN * cols * rows
        and { cols = cols, rows = rows, cell = cell, w = w, h = h, open = open, cost = cost, danger = danger } or false
    if resets == began then cache[key] = grid end
    return grid
end

-- Footprints -------------------------------------------------------------------
-- Every LEARN_EVERY seconds on foot or mounted, the player's cell is saved per zone in
-- CP.db.footprints[zone][cell] = 1 (walked) or 2 (swum). Never in an instance, on a taxi
-- or flying. Walking wins over an old water mark: shallows are wadeable.

function Terrain.Learn(zone, x, y, swimming, w, h)
    if not (CP.db and zone and x and y and w and h) then return false end
    local cols = math.ceil(w / Terrain.CELL_YD)
    local i = math.floor(y * h / Terrain.CELL_YD) * cols + math.floor(x * w / Terrain.CELL_YD)
    CP.db.footprints = CP.db.footprints or {}
    local cells = CP.db.footprints[zone] or {}
    CP.db.footprints[zone] = cells
    local kind = swimming and 2 or 1
    if cells[i] == kind or (cells[i] == 1 and swimming) then return false end
    cells[i] = kind
    return true
end

local learned = 0

-- Full batches of new cells learned this session, by zone. A drawn route keys on the count.
local batches = {}
Terrain.batches = batches

local function step()
    if UnitOnTaxi("player") or IsFlying() then return end
    local zone = CP.Waypoint and CP.Waypoint.PlayerZone()
    if not zone or CP.Gather.IsInstance(zone) then return end
    local pos = C_Map.GetPlayerMapPosition(zone, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    local w, h = CP.Gather.ZoneSize(zone)
    if Terrain.Learn(zone, x, y, IsSwimming(), w, h) then
        learned = learned + 1
        if learned >= Terrain.LEARN_BATCH then
            learned = 0
            batches[zone] = (batches[zone] or 0) + 1
            Terrain.Reset()
        end
    end
end
Terrain.Step = step

-- Footprints shape the loops through herbs and ore, so they are only taken with the
-- route on, Herbalism or Mining learned, and out of combat.
local function wanted()
    if not (CP.db and CP.db.route ~= false) or InCombatLockdown() then return false end
    local skills = CP.Gather.Skills()
    return skills[CP.Gather.HERBALISM] ~= nil or skills[CP.Gather.MINING] ~= nil
end
Terrain.Wanted = wanted

CP:On("PLAYER_ENTERING_WORLD", function()
    if not Terrain.ticker then
        Terrain.ticker = C_Timer.NewTicker(Terrain.LEARN_EVERY, function()
            if wanted() then pcall(step) end
        end)
    end
end)

local function cellOf(g, p)
    local c = math.min(g.cols - 1, math.max(0, math.floor(p.x * g.w / g.cell)))
    local r = math.min(g.rows - 1, math.max(0, math.floor(p.y * g.h / g.cell)))
    return r * g.cols + c
end

-- Binary heap of { cost, index }.
local function push(heap, cost, i)
    local n = #heap + 1
    heap[n] = { cost, i }
    while n > 1 do
        local up = math.floor(n / 2)
        if heap[up][1] <= heap[n][1] then break end
        heap[up], heap[n] = heap[n], heap[up]
        n = up
    end
end

local function pop(heap)
    local top, n = heap[1], #heap
    local last = heap[n]
    heap[n] = nil
    n = n - 1
    if n == 0 then return top end
    heap[1] = last
    local i = 1
    while true do
        local l, r, m = 2 * i, 2 * i + 1, i
        if l <= n and heap[l][1] < heap[m][1] then m = l end
        if r <= n and heap[r][1] < heap[m][1] then m = r end
        if m == i then break end
        heap[i], heap[m] = heap[m], heap[i]
        i = m
    end
    return top
end

local STEPS = { { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
                { 1, 1, 1.4142 }, { 1, -1, 1.4142 }, { -1, 1, 1.4142 }, { -1, -1, 1.4142 } }

-- Shortest-path costs in yards from `from` (a cell index), until `target` (a cell index)
-- or every cell of `targets` ({ [index] = true }) is settled, else over the whole grid.
-- Returns cost and previous-cell tables.
local function search(g, from, target, tick, targets)
    local left = 0
    for _ in pairs(targets or {}) do left = left + 1 end
    local cost, prev, heap = { [from] = 0 }, {}, {}
    push(heap, 0, from)
    local cols, rows, open, cell, unknown = g.cols, g.rows, g.open, g.cell, Terrain.UNKNOWN
    local pops = 0
    while #heap > 0 do
        local top = pop(heap)
        local d, i = top[1], top[2]
        if d <= cost[i] then
            if i == target then break end
            if targets and targets[i] then
                targets[i] = nil
                left = left - 1
                if left == 0 then break end
            end
            local c, r = i % cols, math.floor(i / cols)
            local here = g.cost and g.cost[i] or (open[i] and 1 or unknown)
            for _, s in ipairs(STEPS) do
                local nc, nr = c + s[1], r + s[2]
                if nc >= 0 and nr >= 0 and nc < cols and nr < rows then
                    local j = nr * cols + nc
                    local there = g.cost and g.cost[j] or (open[j] and 1 or unknown)
                    local step = s[3] * cell * (here + there) / 2
                    local nd = d + step
                    if not cost[j] or nd < cost[j] then
                        cost[j], prev[j] = nd, i
                        push(heap, nd, j)
                    end
                end
            end
            pops = pops + 1
            Terrain.work = Terrain.work + 1
            if tick and pops % 200 == 0 then tick() end
        end
    end
    return cost, prev
end

-- Path costs between every pair of `points`: { [a] = { [b] = yards } }.
function Terrain.Distances(g, points, tick)
    local cells, out = {}, {}
    for _, p in ipairs(points) do cells[p] = cellOf(g, p) end
    for _, a in ipairs(points) do
        local targets = {}
        for _, b in ipairs(points) do targets[cells[b]] = true end
        local cost = search(g, cells[a], nil, tick, targets)
        local row = {}
        for _, b in ipairs(points) do row[b] = cost[cells[b]] or math.huge end
        out[a] = row
    end
    return out
end

-- What crossing cell `i` costs a yard.
local function cellCost(g, i)
    return g.cost and g.cost[i] or (g.open[i] and 1 or Terrain.UNKNOWN)
end

-- True when the straight line between two cells costs no more than `spent`, what the
-- searched path between them costs: the line crosses nothing the path went round.
local function clear(g, i, j, spent)
    local c1, r1 = i % g.cols, math.floor(i / g.cols)
    local c2, r2 = j % g.cols, math.floor(j / g.cols)
    local steps = math.max(math.abs(c2 - c1), math.abs(r2 - r1)) * 2
    local len = math.sqrt((c2 - c1) ^ 2 + (r2 - r1) ^ 2) * g.cell
    local total = (cellCost(g, i) + cellCost(g, j)) / 2
    for k = 1, steps - 1 do
        local t = k / steps
        local c = math.floor(c1 + (c2 - c1) * t + 0.5)
        local r = math.floor(r1 + (r2 - r1) * t + 0.5)
        total = total + cellCost(g, r * g.cols + c)
    end
    -- The search's diagonal step is 1.4142, a hair under the root of two.
    return total * len / steps <= spent * 1.001
end

-- True on walkable ground: open, or near stronger creatures.
local function groundAt(g, x, y)
    local c = math.min(g.cols - 1, math.max(0, math.floor(x * g.w / g.cell)))
    local r = math.min(g.rows - 1, math.max(0, math.floor(y * g.h / g.cell)))
    local i = r * g.cols + c
    return g.open[i] == true or (g.danger ~= nil and g.danger[i] == true)
end

-- Rounds the corners of a closed walking line (Chaikin's corner cutting, twice). Stops
-- (points with a `value`) stay put; a corner is cut only where both new points are on
-- walkable ground and the corner itself was, so smoothing never drifts onto rough ground.
function Terrain.Smooth(g, path, passes)
    for _ = 1, passes or 2 do
        local n = #path
        if n < 3 then return path end
        local out = {}
        for i = 1, n do
            local prev, p, nextp = path[(i - 2) % n + 1], path[i], path[i % n + 1]
            if p.value or not groundAt(g, p.x, p.y) then
                out[#out + 1] = p
            else
                local a = { x = p.x + (prev.x - p.x) * 0.25, y = p.y + (prev.y - p.y) * 0.25 }
                local b = { x = p.x + (nextp.x - p.x) * 0.25, y = p.y + (nextp.y - p.y) * 0.25 }
                if groundAt(g, a.x, a.y) and groundAt(g, b.x, b.y) then
                    out[#out + 1] = a
                    out[#out + 1] = b
                else
                    out[#out + 1] = p
                end
            end
        end
        path = out
    end
    return path
end

-- The walking line from `a` to `b` (zone-map points): { { x, y } }, without `a`, ending
-- at `b`. Corners are kept only where a straight line would cost more than the path.
function Terrain.Path(g, a, b, tick)
    local from, to = cellOf(g, a), cellOf(g, b)
    if from == to then return { { x = b.x, y = b.y } } end
    local cost, prev = search(g, from, to, tick)
    local cells = { to }
    while cells[#cells] ~= from and prev[cells[#cells]] do cells[#cells + 1] = prev[cells[#cells]] end
    local path = {}
    for k = #cells, 1, -1 do path[#path + 1] = cells[k] end
    local out, anchor = {}, 1
    while anchor < #path do
        local far = anchor + 1
        for k = #path, anchor + 2, -1 do
            if clear(g, path[anchor], path[k], cost[path[k]] - cost[path[anchor]]) then far = k break end
        end
        if far < #path then
            local i = path[far]
            out[#out + 1] = { x = (i % g.cols + 0.5) * g.cell / g.w, y = (math.floor(i / g.cols) + 0.5) * g.cell / g.h }
        end
        anchor = far
    end
    out[#out + 1] = { x = b.x, y = b.y }
    return out
end
