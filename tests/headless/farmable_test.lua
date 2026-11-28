-- Farm and its pins offer only creatures worth farming (owner, 2026-11-27, a Horde skinner in Tanaris
-- in Farm mode: Profit listed Sungrass, its pin read "Needs level 52. Apothecary Quinard is too high
-- for you yet."; "I don't want to see farmable NPCs like this. Enemy mobs are fine. But Undercity?
-- Stormwind?"). Quinard is an Undercity NPC (faction template 68) whose loot gives Sungrass at 31.5%.
-- The data leaves out faction NPCs, quest and event NPCs, bosses and rares
-- (the data build's farm rule), and a why text names the item and the zone, never a creature.
-- Real generated data.

local CP = ProfLost
local G, GL, RM, Farm, GT = CP.Gather, CP.GatherList, CP.RouteMap, CP.Farm, CP.GuideTab
local SKIN, COOK = 393, 185
local TANARIS, SWAMP = 1446, 1435
local SUNGRASS, SCALE = 8838, 7392
local QUINARD, KIRIKA, BLUEWALL, TORTA, ONYXIA = 17070, 17079, 17080, 6015, 10184

-- A Horde skinner with Cooking, level 48, standing in Tanaris in Farm mode.
local function scene()
    MapWorld.begin({ zone = TANARIS, x = 0.5, y = 0.5, level = 48, side = "Horde", shareSolves = true })
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.db, "routeMode", "farm")
    World.set(CP.db, "skinSkip", nil)
    World.set(CP.db, "gatherClosed", nil)
    World.set(CP.db, "farmClosed", nil)
    World.set(CP.charDB, "gatherNeeds", nil)
    World.set(CP.charDB, "gatherSoon", nil)
    World.set(CP.charDB, "gatherZone", nil)
    World.set(CP.charDB, "vendorWatch", nil)
    local ranks = { [SKIN] = 250, [COOK] = 225 }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = ranks[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.GatherPanel, "Showing", function() return true end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Pricing, "SaleValue", function(item) return item % 40 + 1, item == SUNGRASS and 5000 or nil end)
    World.set(CP.Pricing, "AuctionAge", function() return 3600 end)
    GL.SetPanelProf(nil)
    G.ResetClusters()
    Farm.Reset()
    RM.Forget()
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
        G.ResetClusters()
        Farm.Reset()
    end)
end

-- The drawn Profit section of `zone`: its rows up to the next section.
local function profit(zone)
    GL.SetZone(zone)
    for _ = 1, 40 do T.advance(0.05, 0.05) end
    GL.Refresh()
    local out, inside = {}, false
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "section" then
            if inside then break end
            inside = l.key == GL.PROFIT_KEY
        elseif inside then
            out[#out + 1] = l
        end
    end
    return out
end

-- The first creature name `text` holds, or nil.
local function names(text)
    for _, m in pairs(CP.GatherData.mobs) do
        local name = type(m) == "table" and m[1]
        if name and #name > 3 and text:find(name, 1, true) then return name end
    end
end

T.test("the data holds no faction NPC, boss or rare as a farm", function()
    local mobs = CP.GatherData.mobs
    for _, e in ipairs({ KIRIKA, BLUEWALL, TORTA, ONYXIA }) do
        T.eq(mobs[e], nil, "creature " .. e .. " is no farm")
    end
end)

T.test("Quinard, a Forsaken NPC out in Silithus, is the Alliance's farm alone", function()
    T.eq(CP.GatherData.sides[QUINARD], "A", "hostile to the Alliance only (owner, 2026-11-27: enemy faction camps)")
    MapWorld.begin({ zone = TANARIS, side = "Horde", level = 60 })
    T.eq(G.Gives(QUINARD, COOK), false, "the Horde never farms him")
    MapWorld.begin({ zone = TANARIS, side = "Alliance", level = 60 })
    T.eq(G.Gives(QUINARD, COOK), true)
end)

T.test("Tanaris, Horde skinner with Cooking at 48: Profit lists no Sungrass", function()
    scene()
    local lines = profit(TANARIS)
    local listed = {}
    for _, l in ipairs(lines) do
        if l.itemID then listed[#listed + 1] = tostring(l.text) end
        T.ok(l.itemID ~= SUNGRASS, "Sungrass is listed: " .. tostring(l.text))
    end
    T.ok(#listed > 0, "Profit lists Tanaris's goods")
end)

T.test("Tanaris: no Profit row's pin text names a creature for a spot it can't find", function()
    scene()
    World.set(CP, "Print", function() end)
    for _, l in ipairs(profit(TANARIS)) do
        if l.itemID then
            local place, why = Farm.Nearest(l.itemID, { zone = TANARIS })
            if not place then
                local text = GL.FarmNavWhy(why, TANARIS, l.itemID)
                T.eq(names(text), nil, "the why names a creature: " .. text)
            end
        end
    end
end)

T.test("a level why says the item, the zone and the level, never the creature", function()
    MapWorld.begin({ zone = SWAMP, x = 0.5, y = 0.5, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [SKIN] = { rank = 175, max = 225 } } })
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    G.ResetClusters()
    local place, why = Farm.Nearest(SCALE, { skills = { [SKIN] = 175 } })
    T.eq(place, nil, "the whelps are level 34")
    T.eq(GT.NavWhy(why, SCALE), "No spot for Green Whelp Scale at your level yet (needs level 31).")
    local _, here = Farm.Nearest(SCALE, { skills = { [SKIN] = 175 }, zone = SWAMP })
    T.eq(GL.FarmNavWhy(here, SWAMP, SCALE),
        "No spot in Swamp of Sorrows for Green Whelp Scale at your level yet (needs level 31).")
    local _, skill = Farm.Nearest(SCALE, { skills = { [SKIN] = 165 }, level = 38 })
    T.eq(GT.NavWhy(skill, SCALE), "Needs Skinning 170 for Green Whelp Scale. You have 165.")
end)

T.test("a zone's why reads that zone's sources, not another zone's creatures", function()
    scene()
    local place, why = Farm.Nearest(SCALE, { skills = { [SKIN] = 250 }, level = 30, zone = TANARIS })
    T.eq(place, nil, "no whelps in Tanaris")
    T.eq(why and why.kind, "none", "the Swamp's level 34 whelps do not speak for Tanaris")
    T.eq(GL.FarmNavWhy(why, TANARIS, SCALE), "No spot in Tanaris has enough of it for you.")
    local sungrass, none = Farm.Nearest(SUNGRASS, { skills = { [SKIN] = 250, [COOK] = 225 }, zone = TANARIS })
    T.eq(sungrass, nil, "no creature worth farming drops Sungrass")
    T.eq(none, nil)
end)
