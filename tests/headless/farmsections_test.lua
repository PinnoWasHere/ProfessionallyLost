-- Farm shows every gathering and cooking profession the character has: Cooking's meat and
-- eggs as grind spots, Fishing's catches as rows, none of it weighed by a guide need.
-- Shown grind spots are numbered 1..n within their profession's section. Scene: the owner's
-- Stranglethorn Vale character, level 38, Skinning 248, Cooking 5, Fishing 5.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local SKIN, COOK, FISH = 393, 185, 356
local STV = 1434
local RAPTOR_EGG = 3685

local function scene(mode, act)
    MapWorld.begin({ zone = STV, x = 0.33, y = 0.5, level = 38, side = "Horde", shareSolves = true })
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.db, "routeMode", mode)
    World.set(CP.db, "gatherClosed", nil)
    World.set(CP.db, "farmClosed", nil)
    World.set(CP.charDB, "gatherNeeds", nil)
    World.set(CP.charDB, "gatherSoon", nil)
    local ranks = { [SKIN] = 248, [COOK] = 5, [FISH] = 5 }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = ranks[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.GatherPanel, "Showing", function() return true end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    GL.SetPanelProf(nil)
    G.ResetClusters()
    RM.Forget()
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
        G.ResetClusters()
    end)
    act()
end

local function settled()
    GL.Refresh()
    local frames = 0
    repeat
        T.advance(0.05, 0.05)
        frames = frames + 1
    until not (CP.GatherGuide.Warming() or RM.Solving() or RM.Passing()) or frames > 8000
    GL.Refresh()
    return (GL.Drawn())
end

-- { [prof] = { spots = { line }, items = { line }, plans = n } } for the section lines drawn.
local function sections(lines)
    local out, cur = {}, nil
    for _, l in ipairs(lines) do
        if l.kind == "section" then
            cur = { spots = {}, items = {}, plans = 0 }
            out[l.key] = cur
        elseif cur and l.kind == "source" and l.spot then
            cur.spots[#cur.spots + 1] = l
        elseif cur and l.kind == "item" then
            cur.items[#cur.items + 1] = l
        elseif cur and l.kind == "plan" and not l.spotOf then
            cur.plans = cur.plans + 1
        end
    end
    return out
end

T.test("Farm draws Cooking and Fishing for a character who has them", function()
    scene("farm", function()
        local s = sections(settled())
        T.ok(s[COOK] ~= nil, "a Cooking section")
        T.ok(s[COOK] and #s[COOK].spots > 0, "Cooking lists meat and egg grind spots")
        T.ok(s[FISH] ~= nil, "a Fishing section")
        T.ok(s[FISH] and #s[FISH].items > 0, "Fishing lists what is caught here")
        T.eq(s[FISH] and s[FISH].plans, 0, "no fishing plan in Farm")
        for _, l in ipairs(s[FISH] and s[FISH].items or {}) do
            T.ok(not l.row.need, "a catch carries no guide need")
            T.eq(l.row.prof, FISH, "a catch from the water: " .. tostring(l.row.itemID))
        end
    end)
end)

T.test("Farm: raptors drop Raptor Egg for Cooking", function()
    scene("farm", function()
        local s = sections(settled())
        local found
        for _, l in ipairs(s[COOK] and s[COOK].spots or {}) do
            for name, a in pairs(l.spot.about) do
                if a.drops[RAPTOR_EGG] and name:find("Raptor") then found = name end
            end
        end
        T.ok(found ~= nil, "a Cooking grind spot names a raptor that drops Raptor Egg")
    end)
end)

T.test("Farm: the picked profession alone, Cooking and Fishing included", function()
    scene("farm", function()
        GL.SetPanelProf(COOK)
        local s = sections(settled())
        T.ok(s[COOK] ~= nil and s[FISH] == nil and s[SKIN] == nil, "Cooking alone")
        GL.SetPanelProf(FISH)
        s = sections(settled())
        T.ok(s[FISH] ~= nil and s[COOK] == nil and s[SKIN] == nil, "Fishing alone")
    end)
end)

T.test("a Farm Cooking spot reads the same with and without a guide need", function()
    local function cooking()
        local out = {}
        for _, l in ipairs(sections(settled())[COOK] and sections(settled())[COOK].spots or {}) do
            out[#out + 1] = l.text .. "|" .. tostring(l.info)
        end
        return out
    end
    local plain, needy
    scene("farm", function() plain = cooking() end)
    scene("farm", function()
        World.set(CP.charDB, "gatherNeeds", { [COOK] = { [RAPTOR_EGG] = 40 } })
        needy = cooking()
    end)
    T.ok(#plain > 0, "Cooking spots exist")
    T.eq(needy, plain)
end)

T.test("shown grind spots are numbered 1 to n in their section, best first", function()
    for _, mode in ipairs({ "farm", false }) do
        scene(mode or nil, function()
            World.set(CP.charDB, "gatherNeeds", { [COOK] = { [RAPTOR_EGG] = 40 } })
            World.set(CP.charDB, "gatherSoon", { [COOK] = { [RAPTOR_EGG] = 40 } })
            local s = sections(settled())
            local shown = 0
            for prof, sec in pairs(s) do
                for i, l in ipairs(sec.spots) do
                    shown = shown + 1
                    T.eq(l.rank, ("#%d"):format(i), ("profession %s, spot %d"):format(tostring(prof), i))
                end
            end
            T.ok(shown > 0, "spots shown in " .. tostring(mode))
        end)
    end
end)

T.test("a lone Skinning spot reads #1 when Cooking's spots rank above it on the map", function()
    scene("farm", function()
        local function spot(prof, rank, x)
            return { x = x, y = 0.5, value = 10, prof = prof, rank = rank, name = "Raptor", parts = { Raptor = 1 },
                items = {}, about = { Raptor = { minLevel = 37, maxLevel = 40, drops = { [RAPTOR_EGG] = 60 } } } }
        end
        local planted = { spot(COOK, 1, 0.3), spot(COOK, 2, 0.4), spot(SKIN, 3, 0.5) }
        World.set(RM, "Spots", function() return planted, STV end)
        local s = sections(GL.Drawn() and (function() GL.Refresh() return (GL.Drawn()) end)())
        T.eq(#s[SKIN].spots, 1)
        T.eq(s[SKIN].spots[1].rank, "#1", "the only Skinning spot shown")
        T.eq(s[COOK].spots[1].rank, "#1")
        T.eq(s[COOK].spots[2].rank, "#2")
    end)
end)

T.test("Follow the guide: a Cooking guide that needs eggs lists Raptor Egg with raptor spots", function()
    scene(nil, function()
        World.set(CP.charDB, "gatherNeeds", { [COOK] = { [RAPTOR_EGG] = 16 } })
        World.set(CP.charDB, "gatherSoon", { [COOK] = { [RAPTOR_EGG] = 16 } })
        local s = sections(settled())
        local row
        for _, l in ipairs(s[COOK] and s[COOK].items or {}) do
            if l.row.itemID == RAPTOR_EGG then row = l.row end
        end
        T.ok(row ~= nil, "Raptor Egg is a Cooking row")
        T.eq(row and row.need, 16)
        local raptor
        for _, l in ipairs(s[COOK] and s[COOK].spots or {}) do
            for name, a in pairs(l.spot.about) do
                if a.drops[RAPTOR_EGG] and name:find("Raptor") then raptor = name end
            end
        end
        T.ok(raptor ~= nil, "a raptor grind spot")
    end)
end)

T.test("Farm: every profession keeps its own grind spots on the map, numbered like the panel", function()
    for _, mode in ipairs({ "farm", false }) do
        scene(mode or nil, function()
            local s = sections(settled())
            local spots = (RM.Spots())
            local per = {}
            for _, spot in ipairs(spots) do
                per[spot.prof] = (per[spot.prof] or 0) + 1
                T.eq(spot.rank, per[spot.prof], "the pin badge counts within its profession")
                T.ok(per[spot.prof] <= CP.Route.GRIND_SPOTS, "at most the cap per profession")
            end
            if mode then
                T.ok((per[SKIN] or 0) >= 1, "Skinning keeps a spot")
                T.ok((per[COOK] or 0) >= 1, "Cooking keeps a spot")
            end
            for prof, sec in pairs(s) do
                T.eq(#sec.spots, per[prof] or 0, "the panel lists the map's spots for " .. tostring(prof))
                for i, l in ipairs(sec.spots) do
                    T.eq(l.rank, "#" .. l.spot.rank, "panel number equals pin badge")
                    T.eq(l.spot.of, per[prof], "the tooltip total counts its profession")
                end
            end
        end)
    end
end)

T.test("Farm's Fishing lists real catches, not crates", function()
    scene("farm", function()
        local s = sections(settled())
        T.ok(s[FISH] and #s[FISH].items > 0, "Fishing lists catches")
        for _, l in ipairs(s[FISH] and s[FISH].items or {}) do
            T.ok(CP.Pricing.IsFish(l.row.itemID), "a real catch: " .. tostring(l.row.itemID))
            T.ok(l.row.itemID ~= 20708, "no Crate of Fishing Supplies")
        end
    end)
end)
