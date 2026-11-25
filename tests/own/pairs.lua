-- PROFLOST_PAIRS support for the own runner. prefix(mode, seed) is the one line that run.lua puts in
-- front of each addon file under Engine, UI, Core and Pricing, so `pairs` there walks its keys in order
-- (asc, desc or seed:<n>).

local PRELUDE = [==[local pairs = (function(mode, seed)
local rp, nx, ty, ts, sort, rg = pairs, next, type, tostring, table.sort, rawget
local ids, n, hs = setmetatable({}, { __mode = "k" }), 0, {}
local rk = { number = 1, string = 2, boolean = 3, table = 4, ["function"] = 5, userdata = 6, thread = 7 }
local function id(k) local i = ids[k] if not i then n = n + 1 i = n ids[k] = i end return i end
local function lt(a, b)
local ta, tb = ty(a), ty(b)
if ta ~= tb then return rk[ta] < rk[tb] end
if ta == "number" or ta == "string" then return a < b end
if ta == "boolean" then return b and not a end
return id(a) < id(b)
end
local function hash(k)
local h = hs[k]
if h then return h end
h = seed % 1000003
local s = ts(ty(k)) .. ts(k)
if ty(k) ~= "number" and ty(k) ~= "string" and ty(k) ~= "boolean" then s = ty(k) .. id(k) end
for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483629 end
hs[k] = h
return h
end
local function shuffled(a, b)
local x, y = hash(a), hash(b)
if x ~= y then return x < y end
return lt(a, b)
end
local cmp = mode == "seed" and shuffled or lt
local step = mode == "desc" and -1 or 1
return function(t)
if ty(t) ~= "table" then return rp(t) end
local ks, c = {}, 0
for k in nx, t do c = c + 1 ks[c] = k end
if c > 1 then sort(ks, cmp) end
local i = step == 1 and 0 or c + 1
return function()
while true do
i = i + step
local k = ks[i]
if k == nil then return nil end
local v = rg(t, k)
if v ~= nil then return k, v end
end
end, t, nil
end
end)(@MODE@, @SEED@) ]==]

local M = {}

M.FOLDERS = { Engine = true, UI = true, Core = true, Pricing = true }

-- Returns mode, seed for a PROFLOST_PAIRS value, nil when unset, and errors on a bad value.
function M.parse(value)
    value = (value or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if value == "" then return nil end
    if value == "asc" or value == "desc" then return value, 0 end
    local n = value:match("^seed:(%d+)$")
    if n then return "seed", tonumber(n) end
    error("PROFLOST_PAIRS=" .. value .. ": use one of asc, desc, seed:<n>")
end

function M.prefix(mode, seed)
    local line = PRELUDE:gsub("%s*\n", " ")
    return (line:gsub("@MODE@", '"' .. mode .. '"'):gsub("@SEED@", tostring(seed)))
end

-- True for an addon file whose pairs is ordered. rel is relative to the addon folder.
function M.covers(rel)
    local top = rel:match("^([^/]+)/")
    return top ~= nil and M.FOLDERS[top] == true and rel:lower():match("%.lua$") ~= nil
end

return M
