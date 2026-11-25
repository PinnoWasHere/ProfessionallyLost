-- The drawn route follows its rows' sources. A skill-up can change which creatures or nodes
-- give an item while the item stays on the list (a new beast skinnable, a vein no longer
-- above the player), and the map then shows what a fresh solve of the same rows shows
-- (farm picks lane, 2026-11-16: at Skinning 225 a spot read "Level 41-42 49%" where a fresh
-- solve read "Level 41-45 54%"). A skill-up that changes no source solves nothing again.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local HBD = LibStub("HereBeDragons-2.0")
local SKIN, MINE, HERB = 393, 186, 182
local LW, BS, ALCHEMY = 165, 164, 171
local BARRENS = 1413
local MEDIUM, HEAVY = 2319, 4234
local SHADOWGEM, SWIFTTHISTLE = 1210, 2452

local ranks = {}

-- The player in `zone` at `level`, Follow the guide, with gathering ranks `ranks` (set again
-- by `rank`) and the guides' needs `needs`.
local function scene(zone, level, needs)
    MapWorld.begin({ zone = zone, x = 0.5, y = 0.5, level = level, side = "Horde" })
    World.set(HBD, "GetWorldCoordinatesFromZone", function(_, x, y, z) return x * 1000 + z, y * 1000, 1 end)
    for _, key in ipairs({ "routeMode", "routeSkip", "skinSkip" }) do World.set(CP.db, key, nil) end
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.charDB, "gatherNeeds", needs)
    World.set(CP.charDB, "gatherSoon", nil)
    ranks = {}
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = ranks[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    G.ResetClusters()
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
        G.ResetClusters()
    end)
end

-- The panel rebuilds and every solve it starts ends.
local function settle()
    GL.Refresh()
    local frames = 0
    repeat
        T.advance(0.05, 0.05)
        frames = frames + 1
    until not (CP.GatherGuide.Warming() or RM.Solving() or RM.Passing()) or frames > 4000
    GL.Refresh()
end

-- What the map draws for the player's zone, one string a part.
local function drawn()
    local out = {}
    for _, s in ipairs((RM.Spots())) do
        local about = {}
        for name, a in pairs(s.about or {}) do
            local drops = {}
            for item, chance in pairs(a.drops or {}) do drops[#drops + 1] = item .. "@" .. chance end
            table.sort(drops)
            about[#about + 1] = ("%s %s-%s %s"):format(name, tostring(a.minLevel), tostring(a.maxLevel),
                table.concat(drops, ","))
        end
        table.sort(about)
        out[#out + 1] = ("spot %.4f,%.4f %.3f [%s]"):format(s.x, s.y, s.value, table.concat(about, "; "))
    end
    for _, p in ipairs((RM.Stops())) do out[#out + 1] = ("stop %.4f,%.4f %s"):format(p.x, p.y, tostring(p.name)) end
    return out
end

-- The map as drawn after `rank`'s skill-up equals a fresh solve of the same rows.
local function same(what)
    settle()
    local kept = drawn()
    RM.Forget()
    settle()
    local fresh = drawn()
    for i = 1, math.max(#kept, #fresh) do
        if kept[i] ~= fresh[i] then
            T.ok(false, ("%s: line %d drawn %s, fresh %s"):format(what, i, tostring(kept[i]), tostring(fresh[i])))
            return false
        end
    end
    T.ok(#fresh > 0, what .. ": something drawn")
    return true
end

-- The sources of `item`'s route row in `zone`, by name.
local function sources(zone, item)
    for _, r in ipairs(GL.RouteRows(zone, nil, true)) do
        if r.itemID == item then
            local names = {}
            for _, s in ipairs(r.sources) do names[#names + 1] = s.name end
            table.sort(names)
            return table.concat(names, ",")
        end
    end
    return ""
end

-- Skill-ups from `from` to `to` by `step`; at each one whose sources of `item` changed, the
-- map is checked against a fresh solve. Returns how many such changes there were.
local function climb(prof, zone, item, from, to, step)
    ranks[prof] = from
    settle()
    local was, changes = sources(zone, item), 0
    for rank = from + step, to, step do
        ranks[prof] = rank
        local now = sources(zone, item)
        if now ~= was then
            changes = changes + 1
            if not same(("%s rank %d, sources of %d changed"):format(prof, rank, item)) then return changes end
        end
        was = now
    end
    return changes
end

T.test("Skinning: a newly skinnable beast for a listed leather redraws the grind spots", function()
    scene(BARRENS, 40, { [LW] = { [MEDIUM] = 200, [HEAVY] = 200 } })
    T.ok(climb(SKIN, BARRENS, MEDIUM, 100, 200, 5) > 0, "Medium Leather's creatures change on the way")
end)

T.test("Mining: a vein no longer above the player joins the loop, and its gem's row", function()
    scene(BARRENS, 30, { [BS] = { [SHADOWGEM] = 20 } })
    T.ok(climb(MINE, BARRENS, SHADOWGEM, 50, 80, 5) > 0, "Shadowgem gains Tin and Silver on the way")
end)

T.test("Herbalism: a herb reached by skill joins the loop, and its row's sources", function()
    scene(BARRENS, 30, { [ALCHEMY] = { [SWIFTTHISTLE] = 20 } })
    ranks[HERB] = 60
    settle()
    T.ok(climb(HERB, BARRENS, SWIFTTHISTLE, 60, 75, 5) > 0, "Swiftthistle gains Briarthorn at 70")
end)

T.test("a skill-up that changes no source solves nothing again", function()
    scene(BARRENS, 40, { [LW] = { [MEDIUM] = 200 } })
    ranks[SKIN] = 151
    settle()
    local solves = 0
    local update = RM.Update
    World.set(RM, "Update", function(...)
        if not RM.Solving() then
            update(...)
            if RM.Solving() then solves = solves + 1 end
        else
            update(...)
        end
    end)
    local before = sources(BARRENS, MEDIUM)
    ranks[SKIN] = 152
    T.eq(sources(BARRENS, MEDIUM), before, "152 skins no new beast here")
    settle()
    T.eq(solves, 0, "no solve for a rank that changes nothing the route reads")
end)
