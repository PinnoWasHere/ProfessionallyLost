-- solves: Route.Solve answers shared across the scenes of one test file.
--
-- Route.Solve is a pure function of its points, zone size, cap, walking grid and start, and
-- of the Route and Terrain tunables. A scene that asks for the same solve again gets the
-- stored answer, with its stops swapped for the new call's own point tables, so a test still
-- gets fresh tables to read and change. A scene opts in with MapWorld.begin{ shareSolves = true };
-- a test of the solver itself leaves it off and always runs the real one.
--
-- Setting SOLVES_VERIFY = true (a world file loaded before the test) makes every stored
-- answer also run the real solver and compare, and errors on a difference.
--
--   Solves.share()      the memo for this scene
--   Solves.hits / Solves.misses

Solves = { hits = 0, misses = 0 }

local CP = ProfLost

local cache = {}
local gridSigs = setmetatable({}, { __mode = "k" })
local wrapped = setmetatable({}, { __mode = "k" })

local function ordered(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
end

-- Appends a value's exact content to `out`: tables by sorted key, numbers at full precision.
local function sig(v, out, depth)
    local t = type(v)
    if t == "number" then
        out[#out + 1] = ("%.17g"):format(v)
    elseif t == "string" then
        out[#out + 1] = #v .. ":" .. v
    elseif t == "table" then
        if depth > 8 then error("solves: table too deep to key") end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, ordered)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            sig(k, out, depth + 1)
            out[#out + 1] = "="
            sig(v[k], out, depth + 1)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    elseif t == "function" or t == "userdata" or t == "thread" then
        error("solves: a " .. t .. " in a solve input")
    else
        out[#out + 1] = tostring(v)
    end
end

-- A grid's content: its size and which cells are open or charged.
local function gridSig(g)
    local known = gridSigs[g]
    if known then return known end
    local out = { g.cols, ",", g.rows, ",", g.cell, ",", g.w, ",", g.h, ";" }
    local cells, seen = g.cols * g.rows, 0
    local open, cost = {}, {}
    for i = 0, cells - 1 do
        local c = g.cost[i]
        open[#open + 1] = g.open[i] and "o" or "."
        if c then cost[#cost + 1] = i .. "=" .. ("%.17g"):format(c) end
    end
    for _ in pairs(g.open) do seen = seen + 1 end
    local sawOpen = 0
    for i = 0, cells - 1 do if g.open[i] then sawOpen = sawOpen + 1 end end
    local sawCost = 0
    for _ in pairs(g.cost) do sawCost = sawCost + 1 end
    if seen ~= sawOpen or sawCost ~= #cost then error("solves: grid cells outside the grid") end
    known = table.concat(out) .. table.concat(open) .. ";" .. table.concat(cost, ",")
    gridSigs[g] = known
    return known
end

-- The numbers, strings and booleans of a module: its tunables (Terrain.work only counts).
local function tunables(m, out)
    local keys = {}
    for k, v in pairs(m) do
        local t = type(v)
        if (t == "number" or t == "string" or t == "boolean") and k ~= "work" then keys[#keys + 1] = k end
    end
    table.sort(keys, ordered)
    for _, k in ipairs(keys) do
        sig(k, out, 0)
        out[#out + 1] = "="
        sig(m[k], out, 0)
        out[#out + 1] = ","
    end
end

local function keyFor(points, w, h, maxLength, grid, from)
    local out = {}
    sig(points, out, 0)
    out[#out + 1] = "|"
    sig({ w, h, maxLength == nil and "nil" or maxLength, from or "none" }, out, 0)
    out[#out + 1] = "|"
    out[#out + 1] = grid and gridSig(grid) or "nogrid"
    out[#out + 1] = "|"
    tunables(CP.Route, out)
    out[#out + 1] = "|"
    tunables(CP.Terrain, out)
    return table.concat(out)
end

-- A copy of `v` in which every table in `swap` is replaced by swap[table].
local function copy(v, swap, seen)
    if type(v) ~= "table" then return v end
    if swap[v] ~= nil then return swap[v] end
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, x in pairs(v) do out[copy(k, swap, seen)] = copy(x, swap, seen) end
    return out
end

local function same(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do
        if not same(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function identity(points)
    local swap = {}
    for _, p in ipairs(points) do swap[p] = p end
    return swap
end

-- Wraps Route.Solve for the scene.
function Solves.share()
    local Route = CP.Route
    local real = Route.Solve
    if wrapped[real] then return end

    local function solve(points, w, h, tick, maxLength, grid, from)
        local ok, key = pcall(keyFor, points, w, h, maxLength, grid, from)
        if not ok then return real(points, w, h, tick, maxLength, grid, from) end
        local stored = cache[key]
        if stored then
            Solves.hits = Solves.hits + 1
            local swap = {}
            for i, p in ipairs(stored.points) do swap[p] = points[i] end
            local out = copy(stored.result, swap, {})
            if SOLVES_VERIFY then
                local fresh = real(points, w, h, tick, maxLength, grid, from)
                if not same(out, fresh, {}) then error("solves: a stored answer differs from the real solve", 0) end
            end
            return out
        end
        Solves.misses = Solves.misses + 1
        local result = real(points, w, h, tick, maxLength, grid, from)
        local list = {}
        for i, p in ipairs(points) do list[i] = p end
        cache[key] = { points = list, result = copy(result, identity(points), {}) }
        return result
    end
    wrapped[solve] = true
    World.set(Route, "Solve", solve)
end
