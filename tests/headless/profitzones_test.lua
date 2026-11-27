-- Farm's Profit section shows in every outdoor zone: the zone's dearest goods, or one plain line
-- when the character can gather nothing there to sell, then the Best farm rows. The owner's
-- skinner (Alliance, Skinning 289, Cooking 5) picked Duskwood, Swamp of Sorrows and Westfall in
-- the Gathering panel and saw no Profit (2026-11-27). Real generated data throughout.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local SKIN, COOK, LW, FA = 393, 185, 165, 129
local STORMWIND, HINTERLANDS = 1453, 1425
local ZONES = { Duskwood = 1431, ["Swamp of Sorrows"] = 1435, Westfall = 1436 }
local ORDER = { "Duskwood", "Swamp of Sorrows", "Westfall" }

-- A test price: every item sells, dearer by item id, from the vendor or the AH.
local function price(item) return item % 50 + 1, item % 3 == 0 and item % 97 * 10 or nil end

-- The player in Stormwind in Farm mode, picking zones in the Gathering panel.
local function scene(level, ranks)
    MapWorld.begin({ zone = STORMWIND, x = 0.5, y = 0.5, level = level, side = "Alliance", shareSolves = true })
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
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = ranks[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.GatherPanel, "Showing", function() return true end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Pricing, "SaleValue", price)
    World.set(CP.Pricing, "AuctionAge", function() return 3600 end)
    World.set(CP.Farm, "Find", function() return { zone = HINTERLANDS, score = 1 }, true end)
    GL.SetPanelProf(nil)
    G.ResetClusters()
    RM.Forget()
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
        G.ResetClusters()
    end)
end

local function owner() scene(46, { [SKIN] = 289, [COOK] = 5, [LW] = 165, [FA] = 225 }) end

-- The drawn lines of the Profit section in `zone`: its heading, then its rows up to the next section.
local function profit(zone)
    GL.SetZone(zone)
    for _ = 1, 40 do T.advance(0.05, 0.05) end
    GL.Refresh()
    local out, inside = {}, false
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "section" then
            if inside then break end
            inside = l.key == GL.PROFIT_KEY
        end
        if inside then out[#out + 1] = l end
    end
    return out
end

local function texts(lines)
    local out = {}
    for _, l in ipairs(lines) do out[#out + 1] = tostring(l.text) end
    return table.concat(out, " | ")
end

-- 1. The owner's skinner ------------------------------------------------------------------

for _, name in ipairs(ORDER) do
    T.test("the owner's skinner sees Profit in " .. name .. ", the zone's dearest goods first", function()
        owner()
        local zone = ZONES[name]
        local lines = profit(zone)
        T.eq(lines[1] and lines[1].text, GL.FARM_HEAD_PROFIT, "Profit heads the zone: " .. texts(lines))
        local goods = GL.FarmGoods(zone, {}, G.Skills())
        T.ok(#goods >= GL.FARM_SHOW, "goods to sell here: " .. #goods)
        for i = 1, GL.FARM_SHOW do
            T.eq(lines[i + 1] and lines[i + 1].itemID, goods[i].item, "row " .. i .. " is the zone's good")
            T.ok(i == 1 or goods[i - 1].value >= goods[i].value, "dearest first")
        end
    end)
end

-- 2. Nothing to sell ------------------------------------------------------------------------

for _, name in ipairs(ORDER) do
    T.test("with nothing to sell in " .. name .. ", Profit still shows one plain line and the Best farm rows", function()
        scene(3, {})
        local zone = ZONES[name]
        local g = GL.FarmGoods(zone, {}, G.Skills())
        T.eq(#g, 0, "a level 3 character with no gathering skill has nothing to sell here: " .. tostring(g[1] and g[1].item))
        local lines = profit(zone)
        T.eq(lines[1] and lines[1].text, GL.FARM_HEAD_PROFIT, "Profit heads the zone: " .. texts(lines))
        T.eq(lines[2] and lines[2].text, GL.FARM_NONE, "one plain line says so")
        T.eq(lines[2] and lines[2].muted, true)
        T.ok(lines[3] and tostring(lines[3].text):find("^Best farm: "), "then the Best farm rows: " .. texts(lines))
    end)
end

-- 3. No price yet ---------------------------------------------------------------------------

T.test("with no price for any good here, the heading still says Profit and Best farm still looks", function()
    owner()
    local zone = ZONES.Duskwood
    local here = {}
    for _, g in ipairs(GL.FarmGoods(zone, {}, G.Skills())) do here[g.item] = true end
    World.set(CP.Pricing, "SaleValue", function(item)
        if here[item] then return nil, nil end
        return price(item)
    end)
    local lines = profit(zone)
    T.eq(lines[1] and lines[1].text, GL.FARM_HEAD_PROFIT, texts(lines))
    T.eq(lines[2] and lines[2].info, GL.FARM_NO_PRICE, "the goods say no price yet")
    local better
    for _, l in ipairs(lines) do
        if tostring(l.text):find("^Best farm: ") then better = l end
    end
    T.ok(better ~= nil, "a priced zone elsewhere is named: " .. texts(lines))
end)
