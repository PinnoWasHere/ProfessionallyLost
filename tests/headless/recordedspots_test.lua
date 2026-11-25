-- Zones the data has no skinning for (Forever's Riverglades): beasts the player targets
-- or mouses over there are saved with their level and the player's spot (Engine/Finds.lua),
-- and their skins are estimated from classic beasts of the same level (Gather.SkinLoot).
-- That gives the zone a Skinning section, grind spots and Farm leathers. The player's own
-- skins replace the estimate after Gather.RECORDED_MIN_SKINS. Zones with the data's
-- skinning are unchanged.

local CP = ProfLost
local G, GL, Finds, Route = CP.Gather, CP.GatherList, CP.Finds, CP.Route
local SKIN = 393
local RIVERGLADES, BADLANDS, DUROTAR = 2548, 1418, 1411
local MEDIUM, HEAVY, THICK = 2319, 4234, 4304
local PROWLER, STALKER, ELEMENTAL = 99101, 99102, 99103   -- not in the shipped data

-- The beasts' spots, east of every shipped spawn. Only these are Riverglades ground: the
-- data's spawns there (Badlands' and Redridge's creatures) are on the neighbours' ground.
local HERE = {
    [PROWLER] = { { 0.95, 0.10 }, { 0.96, 0.12 }, { 0.94, 0.14 }, { 0.97, 0.11 } },
    [STALKER] = { { 0.95, 0.60 }, { 0.96, 0.62 }, { 0.94, 0.64 }, { 0.97, 0.61 } },
}

local function riverglades(x, y)
    for _, list in pairs(HERE) do
        for _, p in ipairs(list) do
            if math.abs(p[1] - x) < 0.001 and math.abs(p[2] - y) < 0.001 then return true end
        end
    end
    return false
end

local unit = {}   -- what the target answers: id, name, level, type

-- Plays out the finds timer on the harness clock, not the scene's frozen GetTime.
local realTime = GetTime
local function settleFinds()
    local frozen = GetTime
    GetTime = realTime
    T.advance(CP.GatherMate.SETTLE + 1)
    GetTime = frozen
end

local function scene(mode, act)
    MapWorld.begin({ zone = RIVERGLADES, x = 0.95, y = 0.10, level = 45, side = "Alliance" })
    World.set(CP.db, "finds", {})
    World.set(CP.db, "gatherLoot", nil)
    World.set(CP.db, "seenMobs", nil)
    World.onEnd(settleFinds)
    World.set(CP.db, "skinSeen", {})
    World.set(CP.db, "route", true)
    World.set(CP.db, "routeMode", mode)
    World.set(CP.db, "skinSkip", nil)
    World.set(CP.charDB, "gatherNeeds", nil)
    World.set(CP.charDB, "gatherSoon", nil)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN then return { skillID = id, rank = 260, modifier = 0, maxRank = 300 } end
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Waypoint, "MapPosZone", function(z, x, y)
        if z == RIVERGLADES then return riverglades(x, y) and RIVERGLADES or BADLANDS end
        return z
    end)
    World.set(CP.Waypoint, "PlayerZone", function() return RIVERGLADES end)
    World.set(_G, "UnitGUID", function() return unit.id and ("Creature-0-1-2-3-" .. unit.id .. "-0000") end)
    World.set(_G, "UnitName", function() return unit.name end)
    World.set(_G, "UnitLevel", function(u) if u == "player" then return 45 end return unit.level end)
    World.set(_G, "UnitCreatureType", function() return unit.type end)
    World.set(_G, "UnitCreatureFamily", function() return nil end)
    World.set(_G, "GetTime", function() return 100 end)
    World.set(C_Spell, "GetSpellName", function(id) return id == 8613 and "Skinning" or nil end)
    World.onEnd(function() CP.GatherMate.Reset() end)
    G.ResetClusters()
    act()
end

-- Targets creature `id` at each of its spots.
local function see(id, name, level, kind)
    unit.id, unit.name, unit.level, unit.type = id, name, level, kind
    for _, p in ipairs(HERE[id] or { { 0.95, 0.10 } }) do
        World.set(C_Map, "GetPlayerMapPosition", function() return { GetXY = function() return p[1], p[2] end } end)
        T.fire("PLAYER_TARGET_CHANGED")
    end
end

local function seeBeasts()
    see(PROWLER, "Riverglade Prowler", 44, "Beast")
    see(STALKER, "Riverglade Stalker", 40, "Beast")
    see(ELEMENTAL, "Riverglade Elemental", 44, "Elemental")
    G.ResetZones({ [RIVERGLADES] = true })
end

-- Plays one skin of the targeted beast, then a loot window holding `items`.
local casts = 0
local function skin(items)
    casts = casts + 1
    World.set(_G, "GetNumLootItems", function() return #items end)
    World.set(_G, "GetLootSlotType", function() return 1 end)
    World.set(_G, "GetLootSlotLink", function(slot) return "|cff1eff00|Hitem:" .. items[slot] .. "::::::::|h[x]|h|r" end)
    Finds.Sent("player", unit.name, "s" .. casts, 8613)
    Finds.Succeeded("player", "s" .. casts)
    T.fire("LOOT_READY")
end

local function rowFor(rows, item)
    for _, r in ipairs(rows) do
        if r.itemID == item then return r end
    end
end

local function sourceOf(row, entry)
    for _, src in ipairs(row and row.sources or {}) do
        if src.entry == entry then return src end
    end
end

local function leathers(zone)
    local out = {}
    for _, m in ipairs(GL.FarmLeathers(zone, G.Skills())) do out[m.item] = true end
    return out
end

T.test("a classic level's skins are the median of its beasts' tables", function()
    local at44 = G.EstimatedSkin(44)
    T.ok(#at44 > 0)
    local items = {}
    for _, l in ipairs(at44) do items[l[1]] = l[2] end
    T.ok((items[THICK] or 0) >= 35, "level 44 beasts give Thick Leather")
    T.ok((items[HEAVY] or 0) > 0, "and Heavy Leather")
    T.ok(at44[1][2] >= at44[#at44][2], "likeliest first")
end)

T.test("Riverglades without recordings: no skinning before, beasts seen give a Skinning section", function()
    scene("level", function()
        T.eq(next(leathers(RIVERGLADES)), nil, "nothing before the beasts are seen")
        seeBeasts()
        T.eq(Finds.Creature(ELEMENTAL), nil, "an elemental is not a beast")
        T.eq(Finds.Creature(PROWLER).lo, 44)
        T.eq(CP.db.gatherLoot, nil, "no skins recorded")

        local rows = G.ForZone(RIVERGLADES, G.Skills(), GL.ZONE_OPTS)
        local thick = rowFor(rows, THICK)
        T.ok(thick, "a Thick Leather row")
        T.eq(thick.prof, SKIN)
        local src = sourceOf(thick, PROWLER)
        T.ok(src, "the Prowler is a source")
        T.eq(src.how, "estimated")
        T.eq(src.name, "Riverglade Prowler")
        T.eq(src.skill, G.CorpseSkill(44))
        T.ok(rowFor(rows, HEAVY), "a Heavy Leather row")
        T.ok(sourceOf(rowFor(rows, HEAVY), STALKER), "the Stalker gives Heavy Leather")

        local info, tip = GL.SourceText(src)
        T.ok(info:find(GL.ESTIMATED, 1, true), info)
        T.ok(table.concat(tip, "\n"):find(GL.ESTIMATED_TIP, 1, true), "the tooltip says it is an estimate")

        local farm = leathers(RIVERGLADES)
        T.ok(farm[THICK], "Farm lists Thick Leather")
    end)
end)

T.test("grind spots rank the beasts by the estimated chance of the needed leather", function()
    scene("level", function()
        seeBeasts()
        local rows = G.ForZone(RIVERGLADES, G.Skills(), GL.ZONE_OPTS)
        local thick = rowFor(rows, THICK)
        T.ok(sourceOf(thick, PROWLER).chance > (sourceOf(thick, STALKER) or { chance = 0 }).chance,
            "level 44 gives Thick Leather more often than level 40")
        local one = { itemID = THICK, need = 1, sources = thick.sources }
        local w, h = G.ZoneSize(RIVERGLADES)
        local spots = Route.GrindSpots(Route.Points(RIVERGLADES, { one }, nil, "mob", 45), w, h, nil, 2)
        T.ok(#spots > 0, "grind spots")
        T.ok(spots[1].y < 0.3, ("the best spot is the Prowler's (%.2f, %.2f)"):format(spots[1].x, spots[1].y))
        local about = spots[1].about["Riverglade Prowler"]
        T.eq(about and about.how, "estimated", "the spot carries the estimate mark")

        World.set(CP.db, "routeMode", "farm")
        local skins = G.SkinRows(RIVERGLADES, G.Skills(), {})
        local farmThick = rowFor(skins, THICK)
        T.ok(farmThick and sourceOf(farmThick, PROWLER), "Farm's grind rows hold the Prowler")
    end)
end)

T.test("the player's skins replace the estimate after RECORDED_MIN_SKINS", function()
    scene("level", function()
        seeBeasts()
        unit.id, unit.name, unit.level, unit.type = PROWLER, "Riverglade Prowler", 44, "Beast"
        World.set(C_Map, "GetPlayerMapPosition", function() return { GetXY = function() return 0.95, 0.10 end } end)
        for _ = 1, G.RECORDED_MIN_SKINS - 1 do skin({ MEDIUM }) end
        local _, how = G.SkinLoot(PROWLER)
        T.eq(how, "estimated", "below the threshold the estimate stands")
        T.fire("ZONE_CHANGED_NEW_AREA")
        T.ok(sourceOf(rowFor(G.ForZone(RIVERGLADES, G.Skills(), GL.ZONE_OPTS), THICK), PROWLER))
        skin({ MEDIUM })
        local loot, how2, n = G.SkinLoot(PROWLER)
        T.eq(how2, "recorded")
        T.eq(n, G.RECORDED_MIN_SKINS)
        T.eq(loot[1][1], MEDIUM)
        T.eq(loot[1][2], 100)

        -- The zone's answers start over once the new skins settle, not on each frame.
        local before = G.ForZone(RIVERGLADES, G.Skills(), GL.ZONE_OPTS)
        T.ok(sourceOf(rowFor(before, THICK), PROWLER), "cached until the settle")
        T.ok(CP.GatherMate.Pending(), "a settle is pending")
        T.fire("ZONE_CHANGED_NEW_AREA")
        local after = G.ForZone(RIVERGLADES, G.Skills(), GL.ZONE_OPTS)
        T.eq(sourceOf(rowFor(after, THICK), PROWLER), nil, "the Prowler now gives no Thick Leather")
        local medium = sourceOf(rowFor(after, MEDIUM), PROWLER)
        T.ok(medium and medium.how == "recorded", "it gives Medium Leather from the skins")
        local _, tip = GL.SourceText(medium)
        T.ok(table.concat(tip, "\n"):find("From 10 of your skins", 1, true), table.concat(tip, "\n"))
    end)
end)

T.test("a beast the corpses show can't be skinned drops out", function()
    scene("level", function()
        seeBeasts()
        G.LearnSkin(PROWLER, false, "g1")
        G.LearnSkin(PROWLER, false, "g2")
        local rows = G.ForZone(RIVERGLADES, G.Skills(), GL.ZONE_OPTS)
        T.eq(sourceOf(rowFor(rows, THICK), PROWLER), nil)
    end)
end)

T.test("a zone with the data's skinning is unchanged", function()
    scene("farm", function()
        local function describe()
            local out = {}
            for _, r in ipairs(G.SkinRows(DUROTAR, G.Skills(), {})) do
                for _, src in ipairs(r.sources) do
                    out[#out + 1] = ("%d:%d:%s:%s"):format(r.itemID, src.entry, tostring(src.chance), tostring(src.how))
                end
            end
            table.sort(out)
            return table.concat(out, ";")
        end
        local before = describe()
        T.ok(before ~= "", "Durotar has skinning")
        seeBeasts()
        unit.id, unit.name, unit.level, unit.type = 3099, "Dire Mottled Boar", 6, "Beast"
        T.fire("PLAYER_TARGET_CHANGED")
        T.eq(Finds.Creature(3099), nil, "a beast the data knows is not saved")
        G.ResetClusters()
        T.eq(describe(), before)
    end)
end)
