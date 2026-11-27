-- Farm's Profit section names the best other zones to farm with no price floor, and every
-- Profit and Best farm row sets a waypoint to its nearest spot (owner, 2026-11-27: "The price
-- minimum should be removed completely. Let the player decide if it's worth farming" and "I'd
-- also like to be able to navigate to those profit spots"). A grind spot's drop-chance row
-- wraps whole entries, never an icon apart from its chance, and fits the row's real room
-- (owner's Duskwood spot #3 read "2% 24% 54% 5% |..." with "1%" on a line of its own).
-- Real generated data unless a test says otherwise.

local CP = ProfLost
local G, GL, RM, Farm, GT, S = CP.Gather, CP.GatherList, CP.RouteMap, CP.Farm, CP.GuideTab, CP.Style
local SKIN, COOK, LW, FA = 393, 185, 165, 129
local STORMWIND = 1453
local DUSKWOOD, SWAMP, BLASTED, DEADWIND, WESTFALL, REDRIDGE = 1431, 1435, 1419, 1430, 1436, 1433
local SCALE = 7392                                    -- Green Whelp Scale: Swamp of Sorrows' whelps
local RUGGED, RUGGED_HIDE, HEAVY_HIDE = 8170, 8171, 4235

-- The owner's prices in Duskwood (screenshot, 2026-11-27); everything else sells to a vendor
-- for a few copper.
local OWNER_AH = { [RUGGED] = 2200, [RUGGED_HIDE] = 1800, [HEAVY_HIDE] = 900 }
local function ownerPrice(item) return item % 40 + 1, OWNER_AH[item] end

-- The owner's skinner (Alliance, level 46, Skinning 289) in Stormwind in Farm mode, picking
-- zones in the Gathering panel.
local function scene()
    MapWorld.begin({ zone = STORMWIND, x = 0.5, y = 0.5, level = 46, side = "Alliance", shareSolves = true })
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
    local ranks = { [SKIN] = 289, [COOK] = 5, [LW] = 165, [FA] = 225 }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = ranks[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.GatherPanel, "Showing", function() return true end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Pricing, "SaleValue", ownerPrice)
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

-- The drawn Profit section of `zone`: its heading, then its rows up to the next section.
-- `frames` lets background farm searches finish.
local function profit(zone, frames)
    GL.SetZone(zone)
    for _ = 1, frames or 40 do T.advance(0.05, 0.05) end
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

-- The Best farm rows among `lines`: the lead and the rows hung off it.
local function bestRows(lines)
    local out, lead = {}, nil
    for _, l in ipairs(lines) do
        if l.kind == "plan" and l.fit then
            lead = lead or l
            out[#out + 1] = l
        end
    end
    return out
end

local function priceOf(l)
    local g, s, c = 0, 0, 0
    local info = tostring(l.info)
    g = tonumber(info:match("(%d+)g")) or 0
    s = tonumber(info:match("(%d+)s")) or 0
    c = tonumber(info:match("(%d+)c")) or 0
    return g * 10000 + s * 100 + c
end

-- 1. Best farm has no floor ----------------------------------------------------------------

T.test("the owner's skinner in Duskwood sees Best farm rows, dearest first, none of them Duskwood", function()
    scene()
    local lines = profit(DUSKWOOD, 1)
    for _ = 1, 60 do
        if not Farm.Warming() then break end
        for _ = 1, 40 do T.advance(0.05, 0.05) end
        lines = profit(DUSKWOOD, 1)
    end
    local best = bestRows(lines)
    T.eq(#best, GL.FARM_SHOW, "Best farm rows show: " .. texts(lines))
    local duskName = C_Map.GetMapInfo(DUSKWOOD).name
    for i, l in ipairs(best) do
        T.ok(l.fit.zone ~= duskName, "not the picked zone: " .. tostring(l.text))
        T.ok(i == 1 or priceOf(best[i - 1]) >= priceOf(l), "dearest first: " .. tostring(l.info))
    end
end)

T.test("Best farm lists the dearest other zones by price even when they sell for less than here", function()
    scene()
    -- Here the best good sells for 22s. Elsewhere: 30s, 5s and 1s, one of them in Duskwood.
    local items = { 9001, 9002, 9003, 9004 }
    local value = { [9001] = 500, [9002] = 3000, [9003] = 100, [9004] = 9000 }
    local zoneOf = { [9001] = WESTFALL, [9002] = REDRIDGE, [9003] = SWAMP, [9004] = DUSKWOOD }
    World.set(CP.Pricing, "SaleValue", function(item)
        if value[item] then return nil, value[item] end
        return ownerPrice(item)
    end)
    World.set(Farm, "Items", function() return items end)
    World.set(Farm, "Find", function(item) return { zone = zoneOf[item], score = 1 }, true end)
    local best = bestRows(profit(DUSKWOOD))
    local want = { { REDRIDGE, 3000 }, { WESTFALL, 500 }, { SWAMP, 100 } }
    T.eq(#best, #want, "three other zones, the picked one left out")
    for i, w in ipairs(want) do
        local l = best[i]
        T.eq(l and l.fit.zone, C_Map.GetMapInfo(w[1]).name, "row " .. i .. "'s zone")
        T.eq(l and l.info, GL.FARM_EACH:format(CP.Pricing.Format(w[2]), GL.TAG_AH), "row " .. i .. "'s price")
    end
end)

T.test("a candidate whose price has not loaded yet asks the game for it", function()
    scene()
    local asked = {}
    World.set(CP, "RequestItem", function(id) asked[id] = true end)
    World.set(CP.Pricing, "SaleValue", function(item)
        if item == 9005 then return nil, nil end
        return ownerPrice(item)
    end)
    World.patch("C_Item.GetItemNameByID", function(id) if id ~= 9005 then return "Item " .. id end end)
    World.set(Farm, "Items", function() return { 9005 } end)
    World.set(Farm, "Find", function() return { zone = WESTFALL, score = 1 }, true end)
    profit(DUSKWOOD)
    T.ok(asked[9005], "the unloaded candidate is requested, so its vendor price arrives")
end)

-- A starting isle only a character standing in it can reach (GatherGuide.START_ONLY) is never a
-- Best farm zone for anyone else, nor a nearest spot.
T.test("a level 6 character in Durotar is never sent to Zephras Isle", function()
    local ZEPHRAS, DUROTAR, PEACEBLOOM = 2521, 1411, 2447
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = 6, side = "Horde" })
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    Farm.Reset()
    World.onEnd(Farm.Reset)
    local skills = { [182] = 1, [186] = 1, [SKIN] = 1 }
    local opts = { level = 6, side = "Horde", skills = skills }
    local best = Farm.Best(PEACEBLOOM, opts)
    T.ok(best ~= nil, "Peacebloom has a farm zone")
    T.ok(best and best.zone ~= ZEPHRAS, "not the starting isle: " .. tostring(best and best.zone))
    local near = Farm.Nearest(PEACEBLOOM, opts)
    T.ok(near and near.zone ~= ZEPHRAS, "the nearest spot is not on the isle: " .. tostring(near and near.zone))
    World.set(G, "PlayerZone", function() return ZEPHRAS end)
    Farm.Reset()
    local there = Farm.Nearest(PEACEBLOOM, opts)
    T.eq(there and there.zone, ZEPHRAS, "standing on the isle, its own spot")
end)

-- 2. Farm.Nearest in one zone ---------------------------------------------------------------

T.test("Farm.Nearest with a zone finds its spot there, else says none", function()
    scene()
    local skills = { [SKIN] = 289 }
    local place = Farm.Nearest(SCALE, { skills = skills, level = 46, zone = BLASTED })
    T.ok(place ~= nil, "a spot in the Blasted Lands")
    T.eq(place and place.zone, BLASTED, "in that zone only")
    local swamp = Farm.Nearest(SCALE, { skills = skills, level = 46, zone = SWAMP })
    T.eq(swamp and swamp.zone, SWAMP)
    local none, why = Farm.Nearest(SCALE, { skills = skills, level = 46, zone = DUSKWOOD })
    T.eq(none, nil, "no whelps in Duskwood")
    T.eq(why and why.kind, "none")
end)

-- 3. Pins on Profit and Best farm rows -------------------------------------------------------

-- Every waypoint the panel sets or marks: { zone, x, y }.
local function watchPins()
    local placed = {}
    local function keep(zone, x, y) placed[#placed + 1] = { zone = zone, x = x, y = y } end
    World.set(CP.Waypoint, "PlaceOnMap", keep)
    World.set(GL, "MarkOnMap", keep)
    return placed
end

T.test("a Profit row's pin and click set a waypoint to that good's nearest spot in the picked zone", function()
    scene()
    local lines = profit(DUSKWOOD)
    local goods = {}
    for _, l in ipairs(lines) do
        if l.kind == "plan" and l.itemID then goods[#goods + 1] = l end
    end
    T.ok(#goods > 0, "Profit lists goods: " .. texts(lines))
    local placed, found = watchPins(), nil
    World.set(CP, "Print", function() end)
    for _, l in ipairs(goods) do
        T.ok(type(l.pin) == "function", "a pin on " .. tostring(l.text))
        local want = Farm.Nearest(l.itemID, { zone = DUSKWOOD })
        local n = #placed
        if l.pin then l.pin() end
        local got = placed[#placed]
        if want then
            found = found or l
            T.ok(#placed == n + 1 and got.zone == DUSKWOOD and got.x == want.x and got.y == want.y,
                "the pin goes to its nearest spot in Duskwood: " .. tostring(l.text))
        else
            T.eq(#placed, n, "no spot, no waypoint: " .. tostring(l.text))
        end
    end
    T.ok(found ~= nil, "at least one good has a spot in Duskwood")
    if not found then return end
    local n = #placed
    found.click()
    T.eq(#placed, n + 1, "a click on the row goes there too")
end)

T.test("a Best farm row's pin goes to that material's nearest spot in that zone, and its tooltip says where", function()
    scene()
    World.set(CP.Pricing, "SaleValue", function(item)
        if item == SCALE then return nil, 50000 end
        return ownerPrice(item)
    end)
    World.set(Farm, "Items", function() return { SCALE } end)
    World.set(Farm, "Find", function() return { zone = SWAMP, score = 1 }, true end)
    local best = bestRows(profit(DUSKWOOD))
    T.eq(#best, 1, "one Best farm row")
    local row = best[1]
    if not row then return end
    T.ok(type(row.pin) == "function", "it has a pin")
    local placed = watchPins()
    row.pin()
    local want = Farm.Nearest(SCALE, { zone = SWAMP })
    T.ok(want and placed[1] and placed[1].zone == SWAMP and placed[1].x == want.x and placed[1].y == want.y,
        "the waypoint is the whelps' spot in Swamp of Sorrows")
    -- The tooltip of its drawn row names the place.
    local said = {}
    World.set(GameTooltip, "SetText", function(_, text) said[#said + 1] = text end)
    World.set(GameTooltip, "AddLine", function(_, text) said[#said + 1] = text end)
    local _, rows = GL.Drawn()
    for _, r in ipairs(rows) do
        if r:IsShown() and r.line == row then r:GetScript("OnEnter")(r) end
    end
    local all = table.concat(said, " / ")
    T.ok(all:find(GT.NavText(want, SCALE), 1, true) ~= nil, "the tooltip says where: " .. all)
end)

T.test("a pin that finds no spot says why", function()
    scene()
    World.set(CP.Pricing, "SaleValue", function(item)
        if item == SCALE then return nil, 50000 end
        return ownerPrice(item)
    end)
    World.set(Farm, "Items", function() return { SCALE } end)
    -- Find names a zone with no whelps, as a stale search might.
    World.set(Farm, "Find", function() return { zone = WESTFALL, score = 1 }, true end)
    local row = bestRows(profit(DUSKWOOD))[1]
    T.ok(row and row.pin, "a pin")
    if not row then return end
    local placed, printed = watchPins(), {}
    World.set(CP, "Print", function(_, text) printed[#printed + 1] = text end)
    row.pin()
    T.eq(#placed, 0, "no waypoint")
    T.ok(printed[1] ~= nil, "chat says why: " .. tostring(printed[1]))
end)

-- 4. Drop-chance rows wrap whole entries -------------------------------------------------------

local ICONS = { 134400, 134401, 134402, 134403, 134404 }
local CHANCES = { "2%", "24%", "54%", "5%", "1%" }

local function chanceText()
    local parts = {}
    for i, icon in ipairs(ICONS) do parts[i] = ("|T%d:0|t %s"):format(icon, CHANCES[i]) end
    return table.concat(parts, "  ")
end

-- True when every texture escape in `s` is whole and followed by its chance.
local function whole(s)
    local rest = s:gsub("|T[^|]*|t %d+%%", "")
    return not rest:find("|", 1, true) and not rest:find("%d+%%"), rest
end

T.test("Style.Lines keeps an icon with its chance and never cuts an escape", function()
    local measure = function(t) return #t * 7 end
    local text, widest = chanceText(), 0
    for entry in text:gmatch("|T[^|]*|t %d+%%") do widest = math.max(widest, measure(entry)) end
    for room = widest, 400 do
        for _, piece in ipairs(S.Lines(text, "body", room, measure)) do
            local ok, rest = whole(piece)
            T.ok(ok, ("room %d: whole entries only: %q (left %q)"):format(room, piece, rest))
            if not ok then return end
        end
    end
end)

T.test("Style.Lines breaks a long word between escapes, never inside one", function()
    local measure = function(t) return #t * 7 end
    local word = "|cff00ff00Greenleaf|r|T134400:0|tlongword"
    for room = 7, 200, 7 do
        local pieces = S.Lines(word, "body", room, measure)
        T.eq(table.concat(pieces), word, "room " .. room .. ": the pieces rejoin")
        for _, piece in ipairs(pieces) do
            local open = piece:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "")
            T.ok(not open:find("|", 1, true), ("room %d: no cut escape in %q"):format(room, piece))
        end
    end
end)

-- The detached Gathering panel at `w` px wide in the visual world's font model, listing one
-- drop-chance row as SpotDetail draws it.
local function visualScene()
    local W, GP = CP.Window, CP.GatherPanel
    Visual.begin()
    DaylightWorld.begin({ plugin = true })
    Visual.Skin()
    MapWorld.begin({ zone = 1411, level = 60, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 900 })
    World.set(CP.db, "font", "general")
    World.set(CP.db, "textScale", 1)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherPanelClosed", nil)
    World.set(CP.db, "gatherAttached", false)
    World.set(CP.db, "gatherPoint", { "TOPLEFT", "BOTTOMLEFT", 600, 900 })
    World.set(CP.db, "gatherSize", nil)
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.set(GL, "Lines", function()
        return { { kind = "plan", muted = true, indent = 56, text = chanceText() } }
    end)
    World.onEnd(function()
        CraftWorld.Close()
        CP.db.gatherAttached = true
        GP.ModeChanged()
        GP.anchor:ClearAllPoints()
        W.Update()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    GP.PlaceAnchor()
    GP.Layout()
    T.advance(0.5)
end

T.test("a drop-chance row with no info fits its real room at every width, whole entries only", function()
    visualScene()
    local GP = CP.GatherPanel
    for w = GP.SIZE_MIN[1], GP.MAX_W do
        GP.Resize(w, 400)
        GL.Refresh()
        local _, rows = GL.Drawn()
        for _, r in ipairs(rows) do
            if r:IsShown() and r.line then
                local text = tostring(r.name:GetText())
                local ok, rest = whole(text)
                T.ok(ok, ("%d px: whole entries: %q (left %q)"):format(w, text, rest))
                T.ok(not r.name:IsTruncated(), ("%d px: drawn whole: %q"):format(w, text))
                if not ok or r.name:IsTruncated() then return end
            end
        end
    end
end)
