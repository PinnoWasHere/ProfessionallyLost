local _, CP = ...
if CP.stopped then return end

-- A gathering loop through the herb and ore clusters of what the guides still need
-- in a zone, and grind spots for the creatures: mobs wander and respawn, so the
-- densest groups to stand in beat a loop through every spawn point. Points are on the zone map (0 to 1); distances are in yards from the zone's
-- size. Spawns within CLUSTER_YD of a stop's lead share that stop. The loop is a nearest-neighbour tour
-- improved by 2-opt over each stop's nearest neighbours (and Or-opt on small loops),
-- then pruned: a stop whose detour costs far more yards per item than the loop's
-- average is dropped, so the loop stays on dense ground. When the loop would run
-- longer than MAX_YD, it is built from the stops in the densest disc whose loop fits.
-- A loop through every stop of a dense patch snakes in lanes a stop apart; when that
-- loop runs alongside itself for over LANE_MAX of its length, the capped loop is
-- built as one ring round the patch instead, which never runs back beside itself.

local Route = {}
CP.Route = Route

Route.PRUNE = 2.0       -- drop a cluster costing over this many times the average yards per item
Route.MIN_POINTS = 4    -- never prune below this
Route.MAX_YD = 6000     -- longest loop worth walking round while levelling
Route.FARM_YD = 12000   -- farming: about one respawn cycle mounted, so nodes are back by the next lap
Route.NEAR_START_YD = 1500  -- a dense patch this far from the player counts half when picking where to loop
Route.DOT_YD = 40       -- spacing of drawn dots
Route.CLUSTER_YD = 60   -- spawns within this of a stop's lead join that stop
Route.FIT_TRIES = 6     -- loops tried when sizing the disc a capped loop covers
Route.FIT_AIM = 0.92    -- each try aims at this share of the cap
Route.FIT_LOW = 0.8     -- a loop this share of the cap or more fits well enough
Route.LANE_YD = 150     -- stretches this close run alongside each other
Route.LANE_GAP_YD = 400 -- unless they are this near along the loop
Route.LANE_STEP = 10    -- yards between samples when measuring that
Route.LANE_MAX = 0.05   -- a capped loop running alongside itself for more is made a ring
Route.RING_SECTORS = 24 -- wedges round a capped loop's centre
Route.RING_BAND = 150   -- yards per band out from the centre
Route.RING_SHIFT = 2    -- bands the ring may move in or out between neighbouring wedges
Route.RING_SEARCH = 24  -- prices of a yard tried when sizing the ring
Route.RING_PRICE_MIN = 1e-4 -- items a yard at the cheapest price tried
Route.RING_PRICE_MAX = 1    -- and at the dearest
Route.NEIGHBOURS = 8    -- 2-opt tries each stop's nearest few
Route.OR_OPT_MAX = 120  -- Or-opt only runs on loops up to this many stops
Route.GRIND_YD = 150    -- a grind spot covers the mobs within this radius
Route.GRIND_SPOTS = 3   -- grind spots shown per zone
Route.NEAR_YD = 800     -- a grind spot this far from the player counts half

-- How fast a creature dies for the player, as a weight on its drops: lower mobs die
-- quicker (up to 1.4), higher ones slower, and 4+ levels up is risky enough to rank
-- last (0.15). The displayed yields stay raw; only the ranking uses this.

function Route.KillSpeed(mobLevel, playerLevel)
    if not (mobLevel and playerLevel) then return 1 end
    local diff = mobLevel - playerLevel
    if diff >= 4 then return 0.15 end
    return math.max(0.4, math.min(1.4, 1 - 0.12 * diff))
end

local sqrt = math.sqrt

-- The running solve's path costs (Terrain.Distances), else straight lines, and, with
-- terrain, its walking record { grid, tick, legs } (see Route.Length), whose lines the cap
-- and the status line count. Solve sets both and puts them back every time its own
-- tick returns, so a solve that ran during a yield cannot change them.
local metric, walking

local function dist(a, b, w, h)
    local row = metric and metric[a]
    local d = row and row[b]
    if d then return d end
    local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
    return sqrt(dx * dx + dy * dy)
end

-- Total length of a closed loop, in yards. With `walk` (Solve's terrain record), the
-- yards of the walking lines between the stops instead, which it searches once per pair
-- and keeps in `walk.legs` ({ [a] = { [b] = { { x, y } } } }).
function Route.Length(loop, w, h, walk)
    local n, total = #loop, 0
    if walk then
        for i = 1, n do
            local a, b = loop[i], loop[i % n + 1]
            local row = walk.legs[a]
            if not row then row = {}; walk.legs[a] = row end
            local line = row[b]
            if not line then
                line = CP.Terrain.Path(walk.grid, a, b, walk.tick)
                row[b] = line
            end
            local at = a
            for _, p in ipairs(line) do
                local dx, dy = (p.x - at.x) * w, (p.y - at.y) * h
                total = total + sqrt(dx * dx + dy * dy)
                at = p
            end
        end
        return n > 1 and total or 0
    end
    for i = 1, n do total = total + dist(loop[i], loop[i % n + 1], w, h) end
    return n > 1 and total or 0
end

local function nearestTour(points, w, h)
    local left, tour = {}, {}
    for i = 2, #points do left[#left + 1] = points[i] end
    tour[1] = points[1]
    while #left > 0 do
        local last, best, bestD = tour[#tour], 1, math.huge
        for i, p in ipairs(left) do
            local d = dist(last, p, w, h)
            if d < bestD then best, bestD = i, d end
        end
        tour[#tour + 1] = table.remove(left, best)
    end
    return tour
end

-- Reverse tour[i..j] in place.
local function reverse(t, i, j)
    while i < j do
        t[i], t[j] = t[j], t[i]
        i, j = i + 1, j - 1
    end
end

-- Each point's nearest few, closest first.
local function neighbours(t, w, h, k, tick)
    local out = {}
    for _, p in ipairs(t) do
        local list = {}
        for _, q in ipairs(t) do
            if q ~= p then
                local d = dist(p, q, w, h)
                if #list < k or d < list[#list][2] then
                    local at = #list + 1
                    while at > 1 and list[at - 1][2] > d do at = at - 1 end
                    table.insert(list, at, { q, d })
                    if #list > k then list[#list] = nil end
                end
            end
        end
        local nb = {}
        for i, e in ipairs(list) do nb[i] = e[1] end
        out[p] = nb
        if tick then tick() end
    end
    return out
end

-- 2-opt: swap two edges whenever that shortens the loop, trying for each stop only
-- its nearest neighbours. `tick` lets a caller yield.
local function twoOpt(t, w, h, tick)
    local n = #t
    if n < 4 then return end
    local pos = {}
    for i, p in ipairs(t) do pos[p] = i end
    local near = neighbours(t, w, h, Route.NEIGHBOURS, tick)
    local improved, passes = true, 0
    while improved and passes < 30 do
        improved, passes = false, passes + 1
        for i = 1, n do
            local a, b = t[i], t[i % n + 1]
            local dab = dist(a, b, w, h)
            for _, c in ipairs(near[a]) do
                local dac = dist(a, c, w, h)
                if dac >= dab then break end
                local j = pos[c]
                local d = t[j % n + 1]
                if c ~= b and d ~= a then
                    local delta = dac + dist(b, d, w, h) - dab - dist(c, d, w, h)
                    if delta < -1e-6 then
                        local lo, hi = i % n + 1, j
                        if lo > hi then lo, hi = j + 1, i end
                        reverse(t, lo, hi)
                        for k = lo, hi do pos[t[k]] = k end
                        improved = true
                        break
                    end
                end
            end
            if tick then tick() end
        end
    end
end

-- Or-opt: move runs of 1 to 3 points to a cheaper place in the loop.
local function orOpt(t, w, h, tick)
    local improved, moves = true, 0
    while improved and moves < 4 * #t do
        improved = false
        for len = 1, 3 do
            local n = #t
            if n < len + 3 then break end
            for i = 1, n do
                local first, last = i, i + len - 1
                if last > n then break end
                local prev, nextp = t[(first - 2) % n + 1], t[last % n + 1]
                local seg = {}
                for k = first, last do seg[#seg + 1] = t[k] end
                local removeGain = dist(prev, t[first], w, h) + dist(t[last], nextp, w, h) - dist(prev, nextp, w, h)
                local rest = {}
                for k = 1, n do
                    if k < first or k > last then rest[#rest + 1] = t[k] end
                end
                local bestCost, bestAt, flip = removeGain - 1e-6, nil, false
                for k = 1, #rest do
                    local p, q = rest[k], rest[k % #rest + 1]
                    local base = dist(p, q, w, h)
                    local fwd = dist(p, seg[1], w, h) + dist(seg[#seg], q, w, h) - base
                    local bwd = dist(p, seg[#seg], w, h) + dist(seg[1], q, w, h) - base
                    if fwd < bestCost then bestCost, bestAt, flip = fwd, k, false end
                    if bwd < bestCost then bestCost, bestAt, flip = bwd, k, true end
                end
                if bestAt then
                    if flip then reverse(seg, 1, #seg) end
                    for k = #seg, 1, -1 do table.insert(rest, bestAt + 1, seg[k]) end
                    for k = 1, n do t[k] = rest[k] end
                    improved, moves = true, moves + 1
                    break
                end
                if tick then tick() end
            end
            if improved then break end
        end
    end
end

-- Drop clusters whose detour costs too many yards per item, and then the costliest
-- ones while the loop walks more than `maxLength` yards; returns how many went.
local function prune(t, w, h, maxLength, tick)
    local dropped = 0
    while #t > Route.MIN_POINTS do
        local n, value = #t, 0
        for _, p in ipairs(t) do value = value + p.value end
        local average = Route.Length(t, w, h) / math.max(value, 1e-6)
        local worst, worstRatio
        for i = 1, n do
            local prev, p, nextp = t[(i - 2) % n + 1], t[i], t[i % n + 1]
            local detour = dist(prev, p, w, h) + dist(p, nextp, w, h) - dist(prev, nextp, w, h)
            local ratio = detour / math.max(p.value, 1e-6)
            if not worstRatio or ratio > worstRatio then worst, worstRatio = i, ratio end
        end
        local long = maxLength and Route.Length(t, w, h, walking) > maxLength
        if worstRatio <= Route.PRUNE * average and not long then break end
        table.remove(t, worst)
        dropped = dropped + 1
        if tick then tick() end
    end
    return dropped
end

-- The stops within `radius` yards of the one with the most value around it. With
-- `from` (the player, on the zone map), a patch NEAR_START_YD away counts half, so the
-- loop starts near the player unless something much richer is farther off.
local function densest(points, w, h, radius, tick, from)
    local best, bestValue = nil, -1
    for _, c in ipairs(points) do
        local v = 0
        for _, p in ipairs(points) do
            if dist(c, p, w, h) <= radius then v = v + p.value end
        end
        if from then v = v / (1 + dist(c, from, w, h) / Route.NEAR_START_YD) end
        if v > bestValue then best, bestValue = c, v end
        if tick then tick() end
    end
    local out = {}
    for _, p in ipairs(points) do
        if dist(best, p, w, h) <= radius then out[#out + 1] = p end
    end
    return out, best
end

local function tour(points, w, h, tick)
    local t = nearestTour(points, w, h)
    twoOpt(t, w, h, tick)
    if #t <= Route.OR_OPT_MAX then orOpt(t, w, h, tick) end
    return t
end

-- The loop round the densest disc of stops that fits `maxLength`, so a capped loop
-- covers one patch of ground whole. A loop's length grows about with its stop count,
-- so each try takes the radius that holds the count aiming at FIT_AIM of the cap, kept
-- between the radii already tried. Returns the longest loop that fits, else the shortest.
local function fit(points, w, h, maxLength, tick, from)
    local radius, lo, hi = maxLength / 5, nil, nil
    local best, bestLen, short, shortLen
    for _ = 1, Route.FIT_TRIES do
        local stops, centre = densest(points, w, h, radius, tick, from)
        local t = tour(stops, w, h, tick)
        local len = Route.Length(t, w, h)
        if len <= maxLength then
            if not best or len > bestLen then best, bestLen = t, len end
            if not hi or len >= Route.FIT_LOW * maxLength then break end
            lo = radius
        else
            if not short or len < shortLen then short, shortLen = t, len end
            hi = radius
        end
        local reach = {}
        for i, p in ipairs(points) do reach[i] = dist(centre, p, w, h) end
        table.sort(reach)
        local want = math.floor(#t * Route.FIT_AIM * maxLength / math.max(len, 1))
        local guess = reach[math.max(1, math.min(#reach, want))]
        if (lo and guess <= lo) or guess >= hi then guess = ((lo or 0) + hi) / 2 end
        radius = guess
    end
    return best or short
end

-- Yards from `p` ({ x, y } in yards) to the segment a-b on the zone map, and how far
-- along a-b (0 to 1) the nearest point is.
local function toSegment(p, a, b, w, h)
    local ax, ay, px, py = a.x * w, a.y * h, p[1], p[2]
    local dx, dy = b.x * w - ax, b.y * h - ay
    local l2 = dx * dx + dy * dy
    local f = l2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) or 0
    local ex, ey = ax + f * dx - px, ay + f * dy - py
    return sqrt(ex * ex + ey * ey), f
end

-- The share of a closed line's length that runs within `near` yards of an earlier
-- stretch more than `gap` yards away along the line, either way round: 0 for a clean
-- circuit, more where it doubles back alongside itself. Samples every LANE_STEP yards.
function Route.SelfOverlap(line, w, h, near, gap, tick)
    near, gap = near or Route.LANE_YD, gap or Route.LANE_GAP_YD
    local n, step = #line, Route.LANE_STEP
    if n < 3 then return 0 end
    local arc = { 0 }
    for i = 1, n do
        local a, b = line[i], line[i % n + 1]
        local dx, dy = (b.x - a.x) * w, (b.y - a.y) * h
        arc[i + 1] = arc[i] + sqrt(dx * dx + dy * dy)
    end
    local total, over = arc[n + 1], 0
    if total <= 0 then return 0 end
    for i = 1, n do
        local a, b = line[i], line[i % n + 1]
        local len = arc[i + 1] - arc[i]
        local s = step / 2
        while s < len do
            local f, at = s / len, arc[i] + s
            local p = { (a.x + (b.x - a.x) * f) * w, (a.y + (b.y - a.y) * f) * h }
            for j = 1, i - 1 do
                local d, g = toSegment(p, line[j], line[j % n + 1], w, h)
                if d < near then
                    local back = at - (arc[j] + g * (arc[j + 1] - arc[j]))
                    if math.min(back, total - back) > gap then
                        over = over + step
                        break
                    end
                end
            end
            s = s + step
            if tick then tick() end
        end
    end
    return over / total
end

-- The best bands for one wedge-by-band value table at price `lambda` (items per yard):
-- band[s] for each wedge, the cyclic path through the wedges gathering most for its length.
local function bands(value, at, S, B, lambda, tick)
    local shift = Route.RING_SHIFT
    local bestTotal, bestBand = -math.huge, nil
    local function d(s1, b1, s2, b2)
        local p, q = at[s1][b1], at[s2][b2]
        return sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2)
    end
    for b0 = 1, B do
        local score, from = { [1] = {} }, { [1] = {} }
        score[1][b0] = value[1][b0]
        for s = 2, S do
            score[s], from[s] = {}, {}
            for b = 1, B do
                local top, arg = -math.huge, nil
                for pb = math.max(1, b - shift), math.min(B, b + shift) do
                    local prev = score[s - 1][pb]
                    if prev then
                        local v = prev - lambda * d(s - 1, pb, s, b)
                        if v > top then top, arg = v, pb end
                    end
                end
                if arg then score[s][b], from[s][b] = top + value[s][b], arg end
            end
        end
        for b = math.max(1, b0 - shift), math.min(B, b0 + shift) do
            local last = score[S][b]
            if last then
                local total = last - lambda * d(S, b, 1, b0)
                if total > bestTotal then
                    bestTotal, bestBand = total, { [S] = b }
                    for s = S, 2, -1 do bestBand[s - 1] = from[s][bestBand[s]] end
                end
            end
        end
        if tick then tick() end
    end
    return bestBand
end

-- A capped loop as one ring round the densest spot: the ground round it is cut into
-- RING_SECTORS wedges and RING_BAND yd bands, and the ring takes one band per wedge,
-- moving at most RING_SHIFT bands between neighbours, through the stops there. Every
-- ray from the centre crosses such a ring once, so it never runs back alongside itself.
-- The price of a yard is searched for the ring gathering most within `maxLength`.
local function ring(points, w, h, maxLength, tick, from)
    local S, band = Route.RING_SECTORS, Route.RING_BAND
    local B = math.max(1, math.ceil(maxLength / (2 * math.pi) / band))
    local _, centre = densest(points, w, h, maxLength / (2 * math.pi), tick, from)
    local value, at, members = {}, {}, {}
    for s = 1, S do
        value[s], at[s], members[s] = {}, {}, {}
        local a = (s - 0.5) * 2 * math.pi / S
        for b = 1, B do
            local r = (b - 0.5) * band
            value[s][b], at[s][b], members[s][b] = 0, { r * math.cos(a), r * math.sin(a) }, {}
        end
    end
    for _, p in ipairs(points) do
        local dx, dy = (p.x - centre.x) * w, (p.y - centre.y) * h
        local b = math.floor(sqrt(dx * dx + dy * dy) / band) + 1
        if b <= B then
            local a = math.atan2(dy, dx) % (2 * math.pi)
            local s = math.min(S, math.floor(a / (2 * math.pi) * S) + 1)
            value[s][b] = value[s][b] + p.value
            table.insert(members[s][b], { p, a })
        end
    end
    -- Each price gives a ring, shortened and trimmed to the cap; the one gathering most wins.
    -- Free, then RING_PRICE_MIN to RING_PRICE_MAX items a yard, evenly on a log scale.
    local best, bestValue, seen = nil, -1, {}
    local lo, hi, n = Route.RING_PRICE_MIN, Route.RING_PRICE_MAX, Route.RING_SEARCH
    for k = 0, n do
        local lambda = k == 0 and 0 or lo * (hi / lo) ^ ((k - 1) / math.max(1, n - 1))
        local chosen = bands(value, at, S, B, lambda, tick)
        local key = table.concat(chosen, ",")
        if not seen[key] then
            seen[key] = true
            local t = {}
            for s = 1, S do
                local cell = members[s][chosen[s]]
                table.sort(cell, function(x, y) return x[2] < y[2] end)
                for _, m in ipairs(cell) do t[#t + 1] = m[1] end
            end
            if #t >= 3 then
                twoOpt(t, w, h, tick)
                prune(t, w, h, maxLength, tick)
                local v = 0
                for _, p in ipairs(t) do v = v + p.value end
                if v > bestValue and Route.Length(t, w, h) <= maxLength then best, bestValue = t, v end
            end
        end
    end
    if not best then return tour(densest(points, w, h, maxLength / 5, tick, from), w, h, tick) end
    twoOpt(best, w, h, tick)
    if #best <= Route.OR_OPT_MAX then orOpt(best, w, h, tick) end
    return best
end

-- The loop through `points` ({ x, y, value, ... }): { loop, length, dropped, path }.
-- `tick`, when given, is called often so a coroutine can yield between frames.
-- `maxLength` caps the loop in yards (Route.MAX_YD when nil; false for no cap).
-- `grid` (Terrain.Grid) measures stops by walking path round rough ground; `path` is
-- then the line to draw, stop to stop along those paths, else the loop itself.
-- `from` (the player's { x, y } on the zone map) centres a capped loop near them.
function Route.Solve(points, w, h, tick, maxLength, grid, from)
    if maxLength == nil then maxLength = Route.MAX_YD end
    if #points < 2 then return { loop = { points[1] }, length = 0, dropped = 0, path = { points[1] } } end
    local ownMetric, mine
    local ownTick = tick
    if tick then
        tick = function()
            ownTick()
            metric, walking = ownMetric, mine
        end
    end
    metric, walking = nil, nil
    mine = grid and { grid = grid, tick = tick, legs = {} } or nil
    local t = tour(points, w, h, tick)
    if maxLength and Route.Length(t, w, h) > maxLength then
        t = fit(points, w, h, maxLength, tick, from)
        if Route.SelfOverlap(t, w, h, nil, nil, tick) > Route.LANE_MAX then
            t = ring(points, w, h, maxLength, tick, from)
        end
    end
    if prune(t, w, h, maxLength or nil, tick) > 0 then
        twoOpt(t, w, h, tick)
        if #t <= Route.OR_OPT_MAX then orOpt(t, w, h, tick) end
    end
    local result = { loop = t, length = Route.Length(t, w, h), dropped = #points - #t }

    -- With terrain, the chosen stops are re-ordered by walking distance: only they get
    -- path searches, a few dozen however many spawns the zone has.
    if grid and #t > 2 then
        -- No pcall here: the solver yields inside, and Lua 5.1 can't yield across one.
        -- A route that errors is dropped whole, and the next Solve sets `metric` again.
        -- Improve the straight-line order rather than start over: it is already good, and
        -- a fresh nearest-neighbour start loses more than walking distance wins back.
        ownMetric = CP.Terrain.Distances(grid, t, tick)
        metric, walking = ownMetric, mine
        twoOpt(t, w, h, tick)
        if #t <= Route.OR_OPT_MAX then orOpt(t, w, h, tick) end

        -- Walking, some stops turn out to be spurs (out along a gully and back): drop the
        -- ones whose walking detour costs too much for what they give, and trim to the cap.
        if prune(t, w, h, maxLength or nil, tick) > 0 then
            twoOpt(t, w, h, tick)
            if #t <= Route.OR_OPT_MAX then orOpt(t, w, h, tick) end
        end
        result.loop, result.length, result.dropped = t, Route.Length(t, w, h, mine), #points - #t
    end
    local path = result.loop
    if grid and #result.loop > 1 then
        path = {}
        local n = #result.loop
        Route.Length(result.loop, w, h, mine)   -- fills mine.legs
        for i = 1, n do
            path[#path + 1] = result.loop[i]
            local walk = mine.legs[result.loop[i]][result.loop[i % n + 1]]
            for k = 1, #walk - 1 do path[#path + 1] = walk[k] end
        end
        path = CP.Terrain.Smooth(grid, path)
    end
    metric, walking = nil, nil
    result.path = path
    return result
end

-- Points along the loop every `step` yards, for drawing: { { x, y } }.
function Route.Dots(loop, w, h, step)
    step = step or Route.DOT_YD
    local out, n, carry = {}, #loop, 0
    if n < 2 then return out end
    for i = 1, n do
        local a, b = loop[i], loop[i % n + 1]
        local len = dist(a, b, w, h)
        local at = step - carry
        while at < len do
            local f = at / len
            out[#out + 1] = { a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f }
            at = at + step
        end
        carry = len - (at - step)
    end
    return out
end

local EMPTY = {}
local floor = math.floor

local function byValueThenPlace(a, b)
    if a.value ~= b.value then return a.value > b.value end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end

local function byValue(a, b) return a.value > b.value end

local function byPlace(a, b)
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end

-- Gather points into stops: the most valuable point not yet taken leads a stop, and
-- every untaken point within `radius` yards of it joins (Route.CLUSTER_YD by default).
-- No member sits farther than `radius` from its leader, so stops spread evenly and the
-- loop runs smoothly instead of zig-zagging between near neighbours. A stop has the
-- value-weighted position, the summed value, and the profession and name of its biggest part.
-- `tick` (optional) runs once per point and stop, for a solver that yields.
function Route.Merge(points, w, h, radius, tick)
    radius = radius or Route.CLUSTER_YD
    local order = {}
    for i, p in ipairs(points) do order[i] = p end
    table.sort(order, byValueThenPlace)

    -- Points by grid cell, `radius` wide, to find neighbours without testing every pair.
    -- A cell's key is cx * 100000 + cy.
    local cells = {}
    for _, p in ipairs(order) do
        local k = floor(p.x * w / radius) * 100000 + floor(p.y * h / radius)
        local cell = cells[k]
        if not cell then cell = {}; cells[k] = cell end
        cell[#cell + 1] = p
    end
    local taken, out = {}, {}
    local r2 = radius * radius
    for _, lead in ipairs(order) do
        if not taken[lead] then
            local c = { sx = 0, sy = 0, value = 0, score = 0, best = -1, parts = {}, items = {}, about = {} }
            local parts, items, about = c.parts, c.items, c.about
            local mixes
            local lx, ly = lead.x, lead.y
            local cx, cy = floor(lx * w / radius), floor(ly * h / radius)
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local cell = cells[(cx + dx) * 100000 + cy + dy] or EMPTY
                    for i = 1, #cell do
                        local p = cell[i]
                        local ex, ey = (p.x - lx) * w, (p.y - ly) * h
                        if not taken[p] and ex * ex + ey * ey <= r2 then
                            taken[p] = true
                            local pv = p.value
                            c.sx, c.sy = c.sx + p.x * pv, c.sy + p.y * pv
                            c.value = c.value + pv
                            c.score = c.score + (p.score or pv)
                            for k, v in pairs(p.parts or EMPTY) do parts[k] = (parts[k] or 0) + v end
                            for k, v in pairs(p.items or EMPTY) do items[k] = (items[k] or 0) + v end
                            for k, v in pairs(p.about or EMPTY) do about[k] = v end
                            for m in pairs(p.mixes or EMPTY) do
                                mixes = mixes or {}
                                mixes[m] = true
                            end
                            if pv > c.best then c.best, c.prof, c.name, c.kind = pv, p.prof, p.name, p.kind end
                        end
                    end
                end
            end
            if c.value > 0 then
                c.x, c.y = c.sx / c.value, c.sy / c.value
            else
                c.x, c.y = lx, ly
            end
            c.sx, c.sy, c.best, c.mixes = nil, nil, nil, mixes
            out[#out + 1] = c
        end
        if tick then tick() end
    end
    -- Second pass: a stop takes in its nearest neighbour closer than `radius`, the way a
    -- player picks both from one spot. One sweep, richest stops first, neighbours found
    -- through the same grid, so it stays linear on zones with thousands of spawns.
    table.sort(out, byValue)
    local grid2 = {}
    for _, c in ipairs(out) do
        local k = floor(c.x * w / radius) * 100000 + floor(c.y * h / radius)
        local cell = grid2[k]
        if not cell then cell = {}; grid2[k] = cell end
        cell[#cell + 1] = c
    end
    local gone = {}
    for _, a in ipairs(out) do
        if not gone[a] then
            local ax, ay = a.x, a.y
            local cx, cy = floor(ax * w / radius), floor(ay * h / radius)
            local best, bestD
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local cell = grid2[(cx + dx) * 100000 + cy + dy] or EMPTY
                    for i = 1, #cell do
                        local b = cell[i]
                        if b ~= a and not gone[b] then
                            local ex, ey = (ax - b.x) * w, (ay - b.y) * h
                            local d = ex * ex + ey * ey
                            if d <= r2 and (not bestD or d < bestD) then best, bestD = b, d end
                        end
                    end
                end
            end
            if best then
                local v = a.value + best.value
                a.x, a.y = (ax * a.value + best.x * best.value) / v, (ay * a.value + best.y * best.value) / v
                a.value, a.score = v, (a.score or 0) + (best.score or 0)
                for k, x in pairs(best.parts) do a.parts[k] = (a.parts[k] or 0) + x end
                for k, x in pairs(best.items) do a.items[k] = (a.items[k] or 0) + x end
                for k, x in pairs(best.about) do a.about[k] = x end
                for m in pairs(best.mixes or EMPTY) do
                    a.mixes = a.mixes or {}
                    a.mixes[m] = true
                end
                gone[best] = true
            end
        end
        if tick then tick() end
    end
    local kept = {}
    for _, c in ipairs(out) do
        if not gone[c] then kept[#kept + 1] = c end
    end
    table.sort(kept, byPlace)
    return kept
end

-- Route stops for the checklist rows of `zone`, built from every spawn cluster of
-- every creature or node source of an item the guides still need, gathered into
-- stops by Route.Merge. A cluster's value is spawns x drop chance, summed over the needed
-- items it gives. `clusters(kind, entry)` returns the in-zone clusters
-- ({ x, y, spawns }), Gather.Clusters by default. `only` ("mob" or "node") keeps one kind;
-- "later" takes only the rows above the player's skill (`row.later`), which every other
-- call leaves out: they are shown, never walked.
-- `level` (optional) is the player's level, for Route.KillSpeed. `tick` (optional) runs
-- once per cluster and stop, for a solver that yields.
function Route.Points(zone, rows, clusters, only, level, tick)
    local G = CP.Gather
    local byKey, out = { mobs = {}, nodes = {} }, {}
    local farming = G.RouteFarming()
    local later = only == "later"
    if later then only = "node" end
    for _, row in ipairs(rows) do
        if row.need and not row.done and (row.later == true) == later then
            local item = row.itemID
            for _, src in ipairs(row.sources) do
                if (src.kind == "mob" or src.kind == "node") and src.entry and (not only or src.kind == only)
                    and G.GrindSource(item, src) then
                    local mob = src.kind == "mob"
                    local kind = mob and "mobs" or "nodes"
                    local list
                    if clusters then list = clusters(kind, src.entry) else list = G.Clusters(zone, kind, src.entry, tick) end
                    -- Farm keeps one point per creature and profession, so a creature that
                    -- drops Cooking goods and skins leather feeds both sections' spots.
                    local key = farming and (src.entry .. ":" .. tostring(src.prof)) or src.entry
                    local byIndex = byKey[kind][key]
                    if not byIndex then byIndex = {}; byKey[kind][key] = byIndex end
                    local name, chance = src.name, src.chance
                    local speed = mob and Route.KillSpeed(src.minLevel and src.maxLevel
                        and (src.minLevel + src.maxLevel) / 2, level) or 1
                    for i, c in ipairs(list) do
                        local p = byIndex[i]
                        if not p then
                            p = { x = c[1], y = c[2], value = 0, score = 0, prof = src.prof, name = name,
                                kind = src.kind, parts = {}, items = {}, about = {} }
                            byIndex[i], out[#out + 1] = p, p
                        end
                        local v = c[3] * chance / 100
                        p.value = p.value + v
                        p.score = p.score + v * speed
                        p.parts[name] = (p.parts[name] or 0) + v
                        p.items[item] = (p.items[item] or 0) + v
                        if c.mix then
                            p.mixes = p.mixes or {}
                            p.mixes[c.mix] = true
                        end
                        local a = p.about[name] or { minLevel = src.minLevel, maxLevel = src.maxLevel, drops = {},
                                                     skill = src.skill, item = src.item or (item > 0 and item or nil),
                                                     how = src.how }
                        a.drops[item] = chance
                        p.about[name] = a
                        if tick then tick() end
                    end
                end
            end
        end
    end
    local w, h = G.ZoneSize(zone)
    if not w then return out end
    if not farming then return Route.KeepInside(zone, Route.Merge(out, w, h, nil, tick), out, w, h, tick) end

    -- Farm merges each profession's points on their own, so Cooking's stops never absorb the
    -- creatures a Skinning spot is made of.
    local groups, profs = {}, {}
    for _, p in ipairs(out) do
        local prof = p.prof or 0
        if not groups[prof] then groups[prof], profs[#profs + 1] = {}, prof end
        table.insert(groups[prof], p)
    end
    table.sort(profs)
    local stops = {}
    for _, prof in ipairs(profs) do
        for _, s in ipairs(Route.Merge(groups[prof], w, h, nil, tick)) do stops[#stops + 1] = s end
    end
    return Route.KeepInside(zone, stops, out, w, h, tick)
end

-- A merged stop sits at its points' weighted middle, which can cross a bent border.
-- Such a stop moves to its nearest point in `points` the game puts in `zone`.
function Route.KeepInside(zone, stops, points, w, h, tick)
    local G = CP.Gather
    for _, s in ipairs(stops) do
        if not G.Inside(zone, s.x, s.y) then
            local best, bestD
            for _, p in ipairs(points) do
                local d = dist(s, p, w, h)
                if (not bestD or d < bestD) and G.Inside(zone, p.x, p.y) then best, bestD = p, d end
            end
            if best then s.x, s.y = best.x, best.y end
        end
        if tick then tick() end
    end
    return stops
end

-- For each point of `points`, the indices of the points within `radius` yards of it,
-- lowest first (itself included). Points go into cells a little over `radius` wide, so
-- each point only tests the 3 x 3 cells round its own. The squared distance settles all
-- but the pairs within a hair of `radius`, which take the same square root as `dist`.
-- While Solve measures by terrain (`metric`), every pair goes through `dist`.
local function everyPair(points, n, w, h, radius, tick)
    local near = {}
    for i = 1, n do
        local c, list = points[i], {}
        for j = 1, n do
            if dist(c, points[j], w, h) <= radius then list[#list + 1] = j end
        end
        near[i] = list
        if tick then tick() end
    end
    return near
end

local function neighbourhoods(points, n, w, h, radius, tick)
    if metric or not (radius > 0 and w > 0 and h > 0) then return everyPair(points, n, w, h, radius, tick) end
    local near = {}
    local size = radius * 1.001
    local cells, col, row = {}, {}, {}
    for i = 1, n do
        local p = points[i]
        local cx, cy = floor(p.x * w / size), floor(p.y * h / size)
        if cx ~= cx or cy ~= cy then return everyPair(points, n, w, h, radius, tick) end
        col[i], row[i] = cx, cy
        local column = cells[cx]
        if not column then column = {}; cells[cx] = column end
        local cell = column[cy]
        if not cell then cell = {}; column[cy] = cell end
        cell[#cell + 1] = i
    end
    local r2 = radius * radius
    local inside, outside = r2 * (1 - 1e-9), r2 * (1 + 1e-9)
    for i = 1, n do
        local c = points[i]
        local x, y = c.x, c.y
        local cx, cy = col[i], row[i]
        local list = {}
        for dx = -1, 1 do
            local column = cells[cx + dx]
            if column then
                for dy = -1, 1 do
                    local cell = column[cy + dy]
                    if cell then
                        for k = 1, #cell do
                            local j = cell[k]
                            local p = points[j]
                            local ex, ey = (x - p.x) * w, (y - p.y) * h
                            local d2 = ex * ex + ey * ey
                            if d2 <= inside or (d2 <= outside and sqrt(d2) <= radius) then list[#list + 1] = j end
                        end
                    end
                end
            end
        end
        table.sort(list)
        near[i] = list
        if tick then tick() end
    end
    return near
end

-- The densest groups of creature stops: up to `count` spots, each covering the stops
-- within `radius` yards of its best centre, highest value first, none overlapping.
-- Each spot: { x, y, value, prof, name, parts, items, radius } at the covered stops'
-- weighted middle: `parts` maps every creature there to its share, `items` every
-- needed item; `about` gives each creature's levels and drop chances
-- ({ minLevel, maxLevel, drops = { [itemID] = chance } }); `name` and `itemID` are
-- the biggest of each; `radius` (yards) reaches
-- the farthest stop plus a margin, for drawing the area.
-- Spots rank by kill-speed score (Route.Points), and with `from` (the player's
-- { x, y } on the zone map) a spot NEAR_YD away counts half. With `zone`, a spot whose
-- middle the game puts in another zone moves to its best stop. `tick` (optional) runs
-- once per stop and per candidate centre, for a solver that yields.
function Route.GrindSpots(points, w, h, radius, count, from, zone, tick)
    radius, count = radius or Route.GRIND_YD, count or Route.GRIND_SPOTS
    local n, out = 0, {}
    while points[n + 1] ~= nil do n = n + 1 end
    local near = n > 0 and neighbourhoods(points, n, w, h, radius, tick) or EMPTY
    local gone, left = {}, n
    while #out < count and left > 0 do
        -- Candidates and their neighbours in `points` order, as one shrinking list would give.
        local best, bestValue
        for i = 1, n do
            if not gone[i] then
                if tick then tick() end
                local v = 0
                local list = near[i]
                for k = 1, #list do
                    local j = list[k]
                    if not gone[j] then
                        local p = points[j]
                        v = v + (p.score or p.value)
                    end
                end
                if from then v = v / (1 + dist(points[i], from, w, h) / Route.NEAR_YD) end
                if not bestValue or v > bestValue then best, bestValue = i, v end
            end
        end
        local list = near[best]
        best = points[best]
        local spot = { x = 0, y = 0, value = 0, parts = {}, items = {}, about = {} }
        local top = -1
        for k = #list, 1, -1 do
            local j = list[k]
            if not gone[j] then
                local p = points[j]
                spot.x, spot.y = spot.x + p.x * p.value, spot.y + p.y * p.value
                spot.value = spot.value + p.value
                for key, v in pairs(p.parts or EMPTY) do spot.parts[key] = (spot.parts[key] or 0) + v end
                for key, v in pairs(p.items or EMPTY) do spot.items[key] = (spot.items[key] or 0) + v end
                for key, v in pairs(p.about or EMPTY) do spot.about[key] = v end
                if p.value > top then top, spot.prof = p.value, p.prof end
                gone[j], left = true, left - 1
            end
        end
        spot.x, spot.y = spot.x / spot.value, spot.y / spot.value
        if zone and not CP.Gather.Inside(zone, spot.x, spot.y) then spot.x, spot.y = best.x, best.y end
        local reach = 0
        for k = 1, #list do reach = math.max(reach, dist(spot, points[list[k]], w, h)) end
        spot.radius = math.max(60, reach + 40)
        local bestPart, bestItem = -1, -1
        for k, v in pairs(spot.parts) do
            if v > bestPart then bestPart, spot.name = v, k end
        end
        for k, v in pairs(spot.items) do
            if v > bestItem then bestItem, spot.itemID = v, k end
        end
        spot.name = spot.name or "creatures"
        out[#out + 1] = spot
        spot.rank = #out
    end
    return out
end

-- GrindSpots for each profession's stops on their own, so a profession with many dense
-- groups never crowds out another's. Spots list by profession (lowest id first), each
-- profession's best first; `rank` counts within the profession and `of` is its total.
function Route.GrindSpotsByProf(points, w, h, radius, count, from, zone, tick)
    local groups, profs = {}, {}
    local i = 1
    while points[i] ~= nil do
        local p = points[i]
        local prof = p.prof or 0
        if not groups[prof] then groups[prof], profs[#profs + 1] = {}, prof end
        table.insert(groups[prof], p)
        i = i + 1
    end
    table.sort(profs)
    local out = {}
    for _, prof in ipairs(profs) do
        local spots = Route.GrindSpots(groups[prof], w, h, radius, count, from, zone, tick)
        for _, spot in ipairs(spots) do
            spot.of = #spots
            out[#out + 1] = spot
        end
    end
    return out
end

-- Cache key for a zone and the rows that shape its route.
function Route.Key(zone, rows)
    local ids = {}
    for _, row in ipairs(rows) do
        if row.need and not row.done then ids[#ids + 1] = row.itemID end
    end
    table.sort(ids)
    return zone .. ":" .. table.concat(ids, ",")
end
