-- A gathering row names what the character can gather at the row's starting skill, and a
-- zone whose only skill-giving targets are green is a last resort that says so (simulator
-- findings, 2026-11-16: a Mining row from 225 named Truesilver Deposit, which needs 230; a
-- Mining row 119-125 sent a Horde miner to Desolace, where only green Tin Vein gives a point).

local CP = ProfLost
local GG = CP.GatherGuide
local MINE = 186

-- MOCK targets: three ore nodes by the skill they need.
local function node(name, req) return { kind = "nodes", entry = name, name = name, req = req } end

T.test("a row names no target it can't gather yet", function()
    local list = { node("Truesilver Deposit", 230), node("Mithril Deposit", 175), node("Gold Vein", 155) }
    local names = GG.TargetNames(list, 225, 2)
    for _, n in ipairs(names) do T.ok(not n:find("Truesilver", 1, true), "named " .. n) end
    T.eq(names[1], "Mithril Deposit (green)", "the best it can gather, marked green")
end)

T.test("orange and yellow targets are named plainly", function()
    local list = { node("Truesilver Deposit", 230), node("Mithril Deposit", 175) }
    T.eq(GG.TargetNames(list, 240, 2)[1], "Truesilver Deposit")
    T.eq(GG.TargetNames(list, 180, 2)[1], "Mithril Deposit")
end)

T.test("a Mining guide's rows from 225 name nothing above their start", function()
    MapWorld.begin({ zone = 1418, level = 35, side = "Alliance" })
    GG.Reset()
    for _, r in ipairs(GG.Rows({ line = MINE, skill = 225, max = 300, level = 35, side = "Alliance", zone = 1418 })) do
        if r.gather then
            local reqs = {}
            for _, t in ipairs(r.gather.targets) do reqs[t.name] = t.req end
            for _, n in ipairs(GG.TargetNames(r.gather.targets, r.from, 2)) do
                local name = n:gsub(" %(green%)$", "")
                T.ok(not reqs[name] or reqs[name] <= r.from, ("row %d-%d names %s (needs %s)"):format(r.from, r.to, n, tostring(reqs[name])))
            end
        end
    end
end)

T.test("a zone with only green targets loses to one with orange or yellow", function()
    MapWorld.begin({ zone = 1443, level = 20, side = "Horde" })
    GG.Reset()
    local zones = GG.Zones(MINE, 119, nil, 1, "Horde", 28)
    T.ok(#zones > 0, "zones on Kalimdor")
    local best = zones[1]
    local plain = false
    for _, t in ipairs(best.targets) do
        if GG.Chance(119, t.req) >= 0.75 then plain = true end
    end
    T.ok(plain, ("the best zone at 119, %d, has a target better than green"):format(best.zone))
    for _, z in ipairs(zones) do
        if z.greenOnly then T.ok(z.score < best.score, "green-only zone " .. z.zone .. " ranks below") end
    end
end)
