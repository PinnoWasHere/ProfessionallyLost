-- Trainers in the guide: a visit quotes the fee the named trainer charges (guide `fees`), the
-- lowest on the player's side with its trainer named while none is chosen, and a trainer
-- the data only guessed (`npcsUnconfirmed`) says so where it is named.

local CP = ProfLost
local LW, FA = 165, 129
local BREASTPLATE, HELM = 10647, 10621
local SEJIB, HAHRANA = 7871, 11098       -- Horde: 9,000 and 5,500 for Feathered Breastplate
local STRANGLETHORN, ORGRIMMAR, STORMWIND = 1434, 1454, 1453

local function visit(spell, from, to)
    return CP.Guide.TrainStops(CP.Guides[LW], { { spell = spell, from = from, to = to } }, {}, from)[1]
end

T.test("a visit with no trainer chosen quotes the side's lowest fee and names its trainer", function()
    MapWorld.begin({ zone = ORGRIMMAR, level = 40, side = "Horde" })
    local stop = visit(BREASTPLATE, 225, 245)
    T.eq(stop.fee, 5500, "the Horde's lowest")
    local _, status = CP.Guide.StopText({ train = stop })
    T.ok(status:find("55s at Hahrana Ironhide", 1, true) ~= nil, status)
end)

T.test("the nearest trainer's own fee, and where it is cheaper", function()
    MapWorld.begin({ zone = STRANGLETHORN, level = 40, side = "Horde" })
    local stop = visit(BREASTPLATE, 225, 245)
    local _, status = CP.Guide.StopText({ train = stop }, SEJIB)
    T.ok(status:find("90s", 1, true) ~= nil, "Se'Jib charges 9,000: " .. status)
    T.ok(status:find("55s at Hahrana Ironhide", 1, true) ~= nil, "and says where it costs less: " .. status)
    _, status = CP.Guide.StopText({ train = stop }, HAHRANA)
    T.ok(status:find("55s", 1, true) ~= nil and not status:find("90s", 1, true), status)
    -- The step card's trainer is the nearest one, with its own fee.
    local npc = CP.Guide.Nearest(CP.Guides[LW], stop.recipes[1])
    T.eq(npc and npc.entry, SEJIB, "Se'Jib is the nearest in Stranglethorn")
end)

T.test("one fee everywhere: no trainer named with it", function()
    MapWorld.begin({ zone = STORMWIND, level = 40, side = "Alliance" })
    local stop = visit(BREASTPLATE, 225, 245)
    T.eq(stop.fee, 5500)
    local _, status = CP.Guide.StopText({ train = stop })
    T.ok(status:find("55s", 1, true) ~= nil and not status:find("55s at", 1, true), status)
    stop = visit(HELM, 200, 220)
    T.eq(stop.fee, 4000, "Caryssia Moonhunter, the Alliance's one Wolfshead Helm trainer")
end)

T.test("a guessed trainer says so where it is named; a confirmed one does not", function()
    MapWorld.begin({ zone = ORGRIMMAR, level = 20, side = "Horde" })
    local fa = CP.Guides[FA]
    local guessed, sure
    for _, r in pairs(fa.recipes) do
        if r.src == "trainer" and r.npcsUnconfirmed then guessed = r end
        if r.src == "trainer" and not r.npcsUnconfirmed and r.npcs and #r.npcs > 0 then sure = r end
    end
    T.ok(guessed and sure, "both kinds in First Aid")
    local text = CP.Guide.FromText(fa, guessed)
    T.ok(text:find(CP.Guide.UNCONFIRMED, 1, true) ~= nil, text)
    text = CP.Guide.FromText(fa, sure)
    T.ok(text ~= "" and not text:find(CP.Guide.UNCONFIRMED, 1, true), text)
end)

-- Simulator finding, 2026-11-16 (buy mode, seed 2): a visit at 60 with Embossed Leather Boots
-- and Fine Leather Belt sent a Horde character in Orgrimmar to Kamari, who teaches only the first.
-- The data has no trainer teaching both (apprentice trainers teach the boots, journeyman ones
-- the belt and tunic), so the visit splits in two, each with its own trainer.
T.test("a visit's waypoint goes to a trainer who teaches every recipe of the visit", function()
    MapWorld.begin({ zone = ORGRIMMAR, level = 20, side = "Horde" })
    local guide = CP.Guides[LW]
    local BOOTS, BELT, TUNIC, KAMARI = 2161, 3763, 3761, 5811
    local steps = { { spell = BOOTS, from = 60, to = 65 }, { spell = BELT, from = 60, to = 70 }, { spell = TUNIC, from = 60, to = 75 } }
    local stops = CP.Guide.TrainStops(guide, steps, {}, 60)
    local seen, belt = 0, nil
    for _, stop in ipairs(stops) do
        local target = CP.Guide.WaypointFor({ train = stop })
        T.ok(#target.npcs > 0, "some trainer")
        for _, r in ipairs(stop.recipes) do
            seen = seen + 1
            local set = {}
            for _, e in ipairs(r.npcs) do set[e] = true end
            for _, e in ipairs(target.npcs) do T.ok(set[e], ("npc %d teaches %s"):format(e, r.name)) end
            if r == guide.recipes[BELT] then belt = target end
        end
    end
    T.eq(seen, 3, "every recipe trained once")
    local named = belt and CP.Waypoint.NearestFor(guide, belt)
    T.ok(named ~= nil and named.entry ~= KAMARI, "the belt's trainer is not Kamari: " .. tostring(named and named.entry))
    local keys = {}
    for _, row in ipairs(CP.Guide.WithStops(guide, steps, {}, 60, 75, 20)) do
        if row.key then
            T.ok(not keys[row.key], "one row per key: " .. tostring(row.key))
            keys[row.key] = true
        end
    end
end)
