-- Runs the headless tests on the own fake game, under plain luajit or Lua 5.1. From the repo root:
--
--   luajit tests/own/run.lua --only tests/headless/clamp_test.lua   one test file, one process
--   luajit tests/own/run.lua --all                                   every tests/headless/*_test.lua,
--                                                                    one process each, in turn
--   luajit tests/own/run.lua --all --no-world                        only files that use no world
--
-- One process loads the fake game, the addon by its toc, every file of tests/world/order.txt and
-- tests/rules, then the test file, and ends with a line "OWN <passed> passed <failed> failed <n> errors".

local ADDON = "ProfessionallyLost"
local runner = (arg and arg[0] or ""):gsub("\\", "/")
local here = runner:match("^(.*)/[^/]*$") or "."

local function read(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local text = fh:read("*a")
    fh:close()
    return (text:gsub("^\239\187\191", ""))
end

-- The stub never reads the private harness. Its own files must not name one, and any host file
-- access to such a path fails.
local FORBIDDEN = { "data/" .. "harness", "wow" .. "-api", "/harn" .. "ess/" }
local function harness_path(p)
    p = tostring(p):lower():gsub("\\", "/")
    for _, bad in ipairs(FORBIDDEN) do
        if p:find(bad, 1, true) then return true end
    end
    return false
end
do
    local function guard(name, fn)
        return function(path, ...)
            if harness_path(path) then error("own stub: refuses harness path " .. tostring(path), 2) end
            return fn(path, ...)
        end
    end
    io.open, io.lines, io.popen = guard("open", io.open), guard("lines", io.lines), guard("popen", io.popen)
    dofile, loadfile = guard("dofile", dofile), guard("loadfile", loadfile)
    for _, own in ipairs({ "stub.lua", "t.lua", "pairs.lua", "catalog.lua", "extra.lua" }) do
        local fh = io.open(here .. "/" .. own, "rb")
        if fh then
            local text = fh:read("*a")
            fh:close()
            for _, bad in ipairs(FORBIDDEN) do
                assert(not text:lower():find(bad, 1, true), "own stub: " .. own .. " names a harness path (" .. bad .. ")")
            end
        end
    end
end

local function lines(text)
    local out = {}
    for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do out[#out + 1] = line end
    return out
end

local WINDOWS = package.config:sub(1, 1) == "\\"

-- Every file under `dir` by a directory walk, as paths from the working directory.
local function walk(dir)
    local out = {}
    if WINDOWS then
        local cwd = io.popen("cd"):read("*l"):gsub("\\", "/") .. "/"
        local p = io.popen('dir /b /s /a-d "' .. dir:gsub("/", "\\") .. '"')
        for line in p:lines() do
            local path = line:gsub("\\", "/")
            if path:sub(1, #cwd):lower() == cwd:lower() then path = path:sub(#cwd + 1) end
            out[#out + 1] = path
        end
        p:close()
    else
        local p = io.popen('find "' .. dir .. '" -type f')
        for line in p:lines() do out[#out + 1] = (line:gsub("^%./", "")) end
        p:close()
    end
    return out
end

-- The files under `dir` that match `pattern`, sorted: git's list in a checkout, else a directory walk,
-- so a copy of the tree without .git runs too.
local function listing(dir, pattern)
    local out, found = {}, {}
    local p = io.popen('git ls-files -- "' .. dir .. '"')
    for path in p:lines() do found[#found + 1] = path end
    p:close()
    if #found == 0 then found = walk(dir) end
    for _, path in ipairs(found) do
        if path:match(pattern) then out[#out + 1] = path end
    end
    table.sort(out)
    return out
end

local only, all, noworld
do
    local i = 1
    while arg and arg[i] do
        if arg[i] == "--only" then only = arg[i + 1]; i = i + 1
        elseif arg[i] == "--all" then all = true
        elseif arg[i] == "--no-world" then noworld = true end
        i = i + 1
    end
end

local WORLD_GLOBALS = { "World", "DaylightWorld", "Visual", "CraftWorld", "MapWorld", "AHWorld", "MogulWorld",
                        "PeerWorld", "GatherWorld", "VendorWorld", "Solves", "Rules" }

if all then
    local luabin = arg and arg[-1] or "luajit"
    local files = listing("tests/headless", "_test%.lua$")
    local tp, tf, te, tfiles, bad = 0, 0, 0, 0, {}
    local start = os.time()
    for _, f in ipairs(files) do
        local skip = false
        if noworld then
            local text = read(f) or ""
            for _, g in ipairs(WORLD_GLOBALS) do
                if text:find("%f[%w_]" .. g .. "%f[^%w_]") then skip = true; break end
            end
        end
        if not skip then
            local h = io.popen(luabin .. " " .. runner .. ' --only "' .. f .. '" 2>&1')
            local out = h:read("*a")
            h:close()
            local p, fl, er = out:match("OWN (%d+) passed (%d+) failed (%d+) errors")
            tfiles = tfiles + 1
            if p then
                tp, tf, te = tp + tonumber(p), tf + tonumber(fl), te + tonumber(er)
                if tonumber(fl) > 0 or tonumber(er) > 0 then bad[#bad + 1] = out end
            else
                te = te + 1
                bad[#bad + 1] = f .. ": no summary\n" .. out:sub(-800)
            end
        end
    end
    for _, b in ipairs(bad) do io.write("---\n", b, "\n") end
    io.write(string.format("TOTAL files %d, %d passed, %d failed, %d errors, %ds\n", tfiles, tp, tf, te, os.time() - start))
    os.exit((tf + te) == 0 and 0 or 1)
end

assert(only, "usage: run.lua --only <test file> | --all")

collectgarbage("setpause", 400)

local t0 = os.clock()
local function stage(label)
    if os.getenv("OWN_TIMING") then io.stderr:write(string.format("%-8s %.2fs\n", label, os.clock() - t0)) end
end
local G = dofile(here .. "/stub.lua")
local T = dofile(here .. "/t.lua")(G)
G.setup()
G.strict_events = (os.getenv("OWN_STRICT_EVENTS") or os.getenv("PROFLOST_STRICT_EVENTS") or "") ~= ""
stage("setup")

-- The addon, by its toc.
local toc = listing(ADDON, "%.toc$")[1]
local names = {}
for _, line in ipairs(lines(read(toc))) do
    line = line:match("^%s*(.-)%s*$")
    if line:sub(1, 2) == "##" then
        local key, value = line:match("^##%s*([^:]+):%s*(.*)$")
        if key == "SavedVariables" or key == "SavedVariablesPerCharacter" then
            for n in value:gmatch("[^,%s]+") do G.declared[n] = true end
        end
    elseif line ~= "" and line:sub(1, 1) ~= "#" then
        names[#names + 1] = (line:gsub("\\", "/"))
    end
end
local ns = {}
-- PROFLOST_PAIRS: addon files under Engine, UI, Core and Pricing walk their keys in a set order.
local Pairs = dofile(here .. "/pairs.lua")
local pairs_mode, pairs_seed = Pairs.parse(os.getenv("PROFLOST_PAIRS"))
for _, rel in ipairs(names) do
    if rel:match("%.lua$") then
        local src = read(ADDON .. "/" .. rel)
        if src and pairs_mode and Pairs.covers(rel) then src = Pairs.prefix(pairs_mode, pairs_seed) .. src end
        if src then G.load(src, rel, ADDON, ns) else G.record_error("missing", rel, "") end
    end
end

stage("addon")
G.fire("ADDON_LOADED", ADDON)
G.fire("PLAYER_LOGIN")
G.fire("PLAYER_ENTERING_WORLD", true, false)

local function run_file(path)
    local src = read(path)
    if not src then G.record_error("missing test file", path, ""); return end
    G.load_test(src, path)
end

local order = {}
for _, line in ipairs(lines(read("tests/world/order.txt"))) do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then order[#order + 1] = line end
end
order[#order + 1] = "tests/rules/env.lua"
for _, p in ipairs(listing("tests/rules", "%.lua$")) do
    if p ~= "tests/rules/env.lua" then order[#order + 1] = p end
end
stage("boot")
for _, p in ipairs(order) do run_file(p) end
stage("worlds")
run_file(only)
stage("test")

local passed, failed = 0, 0
for _, t in ipairs(G.tests) do
    if t.ok then passed = passed + 1 else
        failed = failed + 1
        io.write("FAIL ", only, " / ", t.name, "\n  ", tostring(t.message), "\n")
    end
end
for _, e in ipairs(G.errors) do
    io.write("ERROR ", only, " / ", e.context, "\n  ", tostring(e.message), "\n")
end
io.write(string.format("OWN %d passed %d failed %d errors\n", passed, failed, #G.errors))
os.exit((failed + #G.errors) == 0 and 0 or 1)
