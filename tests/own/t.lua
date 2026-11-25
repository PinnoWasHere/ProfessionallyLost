-- The T layer test files use: T.test, T.eq, T.ok, T.fails, T.fire, T.advance, T.stub, T.calls,
-- T.reset_calls, T.get, T.errors, T.prints, T.clock, T.cpu. Built on the fake game `G` (stub.lua).

return function(G)
    local T = {}

    local function deep_equal(a, b, seen)
        if a == b then return true end
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        seen = seen or {}
        if seen[a] == b then return true end
        seen[a] = b
        for k, v in pairs(a) do if not deep_equal(v, b[k], seen) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end

    local function show(v)
        if type(v) == "string" then return ("%q"):format(v) end
        return tostring(v)
    end

    -- A test, or a test file's own top-level code, may run this many CPU seconds and this many Lua
    -- instructions (OWN_MAX_INSTRUCTIONS, 0 turns it off). Past the instruction limit the hook raises
    -- whenever addon or test code is running, never inside the stub's own files.
    local LIMIT = tonumber(os.getenv("OWN_TEST_SECONDS") or "") or 120
    local MAX_INSTRUCTIONS = tonumber(os.getenv("OWN_MAX_INSTRUCTIONS") or "") or 20000000000
    local EVERY = 1000000
    local OWN_DIR = (debug.getinfo(1, "S").source:gsub("\\", "/"):match("^@?(.*)/[^/]*$") or "")
    local deadline, spent, stuck
    local function arm()
        deadline, spent, stuck = os.clock() + LIMIT, 0, nil
        debug.sethook(function()
            if not stuck then
                spent = spent + EVERY
                if os.clock() > deadline then
                    debug.sethook()
                    error("test ran past " .. LIMIT .. " CPU seconds" .. debug.traceback("", 2), 0)
                end
                if MAX_INSTRUCTIONS <= 0 or spent < MAX_INSTRUCTIONS then return end
                stuck = debug.traceback("", 2)
                debug.sethook(debug.gethook(), "", 1)
            end
            local info = debug.getinfo(2, "S")
            local src = info and info.source:gsub("\\", "/")
            if src and src:sub(1, 1) == "@" and not src:find(OWN_DIR, 2, true) then
                error("instruction limit (" .. MAX_INSTRUCTIONS .. ") passed" .. stuck, 0)
            end
        end, "", EVERY)
    end
    local function disarm() debug.sethook() end

    -- opts.allow_errors: handler errors the test provokes on purpose move to G.expected_errors.
    function T.test(name, fn, opts)
        G.calls = {}
        local before = #G.errors
        arm()
        local ok, res = xpcall(fn, G.traceback)
        local over = stuck
        arm()
        if over and ok then ok, res = false, { msg = "instruction limit (" .. MAX_INSTRUCTIONS .. ") passed" .. over, tb = over } end
        local entry = { name = name, ok = ok }
        if opts and opts.allow_errors then
            G.expected_errors = G.expected_errors or {}
            while #G.errors > before do
                table.insert(G.expected_errors, table.remove(G.errors, before + 1))
            end
        end
        if not ok then
            if type(res) ~= "table" then res = { msg = res, tb = "" } end
            entry.message, entry.traceback = tostring(res.msg), res.tb
        elseif #G.errors > before then
            entry.ok = false
            entry.message = "handler error during test: " .. G.errors[before + 1].message
            entry.traceback = G.errors[before + 1].traceback
        end
        G.tests[#G.tests + 1] = entry
    end

    function T.eq(actual, expected, msg)
        if not deep_equal(actual, expected) then
            error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
        end
    end
    function T.ok(v, msg) if not v then error(msg or "expected a truthy value", 2) end end
    function T.fails(fn, pattern)
        local ok, err = pcall(fn)
        if ok then error("expected an error", 2) end
        if pattern and not tostring(err):find(pattern) then error("error did not match " .. pattern .. ": " .. tostring(err), 2) end
        return err
    end

    T.fire = G.fire
    T.advance = G.advance

    function T.stub(path, value)
        G.overrides[path] = value
        if not G.Catalog.functions[path] and not path:find(":", 1, true) then
            G.set_path(G.env, path, function(...)
                G.calls[path] = G.calls[path] or {}
                local rec = G.calls[path]
                rec[#rec + 1] = { n = select("#", ...), ... }
                if type(value) == "function" then return value(...) end
                return value
            end)
        end
    end
    function T.calls(path) return G.calls[path] or {} end
    function T.reset_calls() G.calls = {} end
    function T.get(path) return G.get_path(G.env, path) end
    function T.errors() return G.errors end
    function T.prints() return G.prints end
    function T.clock() return G.clock end
    function T.cpu() return os.clock() end

    -- Test files read through to the game environment and write into it.
    function G.load_test(source, chunkname)
        local chunk, err = loadstring(source, "@" .. chunkname)
        if not chunk then
            G.record_error("syntax " .. chunkname, err, "")
            return false
        end
        setfenv(chunk, setmetatable({ T = T }, { __index = G.env, __newindex = G.env }))
        arm()
        local ok = G.guarded("test file " .. chunkname, chunk)
        disarm()
        return ok
    end

    return T
end
