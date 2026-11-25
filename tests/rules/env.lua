-- Shared rules (decision 0009, 1.4): the checks that judge one
-- state. Each is Rules.<Name>(ctx) and returns its violations. The play-throughs call them through
-- SimCheck's wrappers; layer 1 and scenes call them with their own ctx.
--
-- A rule sees Lua's standard library and `Rules`, nothing else. The addon (ctx.CP) and every answer
-- of a world or the screen come in through ctx. Each rule file starts with setfenv(1, Rules.ENV), so
-- a rule that reads or sets any other global raises.
--
-- paths.worlds() loads this file first, then the other tests/rules/*.lua sorted.

Rules = Rules or {}

local STD = { "assert", "error", "ipairs", "next", "pairs", "pcall", "rawget", "select", "tonumber",
              "tostring", "type", "unpack", "math", "string", "table" }

local env = { Rules = Rules }
for _, name in ipairs(STD) do env[name] = _G[name] end
setmetatable(env, {
    __index = function(_, k) error("a rule reads the global " .. tostring(k) .. "; pass it in ctx", 2) end,
    __newindex = function(_, k) error("a rule sets the global " .. tostring(k), 2) end,
})
Rules.ENV = env

setfenv(1, env)

-- The keys of `t` in a fixed order: numbers, then strings, each ascending, then any other keys.
-- Lua 5.1 and LuaJIT walk a table in different orders, so a loop whose order reaches a violation
-- walks these. The same order as World.keys.
local KEY_RANK = { number = 1, string = 2 }

local function keyBefore(a, b)
    local ra, rb = KEY_RANK[type(a)] or 3, KEY_RANK[type(b)] or 3
    if ra ~= rb then return ra < rb end
    if ra == 3 then return false end
    return a < b
end

-- @rule[Keys] independent: a fixed key order; judges nothing
function Rules.Keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, keyBefore)
    return out
end

-- Recipe `id`'s name: the guide's, else the truth's (ctx.facts(), when the world has one).
-- @rule[NameOf] independent: a recipe's name for a message; judges nothing
function Rules.NameOf(ctx, id)
    local r = ctx.guide and ctx.guide.recipes[id]
    if not r and ctx.facts then
        local f = ctx.facts()
        r = f and f.recipes[id]
    end
    return r and r.name or ("spell " .. tostring(id))
end
