local _, CP = ...
if CP.stopped then return end

-- Remembers the patterns and books a profession can still buy from vendors. The
-- gathering checklist lists the ones sold in the player's zone and flags new ones on
-- entering it (GatherList.Notify). The list is saved per character, so it works with
-- the profession window closed.

local VendorWatch = {}
CP.VendorWatch = VendorWatch

local asked = {}    -- "item:zone" already flagged this session
local soldOut = {}  -- item -> true when a vendor that should sell it didn't, this session

local function guideKey(guide)
    for key, g in pairs(CP.Guides or {}) do
        if g == guide then return key end
    end
end

-- The watched items of one profession, as a string.
local function itemsOf(buys)
    local ids = {}
    for i, buy in ipairs(buys or {}) do ids[i] = tostring(buy.item) end
    return table.concat(ids, ",")
end

-- Save what the open profession can still buy from vendors. `live` is from Plan.Current.
-- A list that changed reads the zone's patterns again (VendorWatch.Recheck).
function VendorWatch.Update(live)
    local guide = live and live.guide
    local key = guide and guideKey(guide)
    if not key then return end
    CP.charDB.vendorWatch = CP.charDB.vendorWatch or {}
    local buys = CP.Guide.VendorBuys(guide, live.learned or {}, live.prof.max)
    local was = itemsOf(CP.charDB.vendorWatch[key])
    CP.charDB.vendorWatch[key] = #buys > 0 and buys or nil
    if itemsOf(buys) ~= was and VendorWatch.Recheck then VendorWatch.Recheck() end
end

-- The player's reaction with a faction (1 Hated .. 8 Exalted), 0 when unknown.
function VendorWatch.Reaction(factionID)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(factionID)
        return data and data.reaction or 0
    end
    return 0
end

-- A reputation pattern is on offer only once the player has the standing.
local function canBuy(buy)
    return not buy.faction or VendorWatch.Reaction(buy.faction) >= buy.standing
end

-- True when the recipe the pattern teaches is already known, by the saved list or the
-- spellbook, so it counts as learned even with the profession window shut.
local function learnedAlready(key, buy)
    local guide = CP.Guides and CP.Guides[key]
    for spell, r in pairs(guide and guide.recipes or {}) do
        if r.pattern == buy.item then
            for _, id in ipairs(CP.charDB.learned and CP.charDB.learned[key] or {}) do
                if id == spell then return true end
            end
            if CP.Professions.SpellKnown(spell) then return true end
        end
    end
    return false
end

-- Watched buys sold in `zone`: { { buy, target, tag, new } }, lowest skill first. `new`
-- marks those not flagged yet this session. Without `all`, only new ones.
function VendorWatch.Find(zone, all)
    local out = {}
    for key, buys in pairs(CP.charDB.vendorWatch or {}) do
        local guide = CP.Guides[key]
        for _, buy in ipairs(guide and buys or {}) do
            local tag = buy.item .. ":" .. zone
            if (all or not asked[tag]) and not soldOut[buy.item] and canBuy(buy)
                and not learnedAlready(key, buy)
                and (C_Item.GetItemCount(buy.item, true) or 0) == 0 then
                local target = CP.Waypoint.InZone(buy.npcs, guide.npcs or {}, zone)
                if target then out[#out + 1] = { buy = buy, target = target, tag = tag, new = not asked[tag] } end
            end
        end
    end
    table.sort(out, function(a, b) return a.buy.skill < b.buy.skill end)
    return out
end

local SHOWN = 8

local function hex(c)
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- The found patterns grouped by vendor, in first-seen order (lowest skill first):
-- { { target, buys = { buy, ... } } }.
function VendorWatch.ByVendor(found)
    local out, at = {}, {}
    for _, f in ipairs(found) do
        local key = ("%s:%s:%s"):format(f.target.name, f.target.x, f.target.y)
        if not at[key] then
            at[key] = { target = f.target, buys = {} }
            out[#out + 1] = at[key]
        end
        local list = at[key].buys
        list[#list + 1] = f.buy
    end
    return out
end

-- Popup text: each vendor with its spot, then the patterns it sells here. Limited-stock
-- patterns are in the player's accent.
function VendorWatch.Text(found)
    local color = CP.Style and CP.Style.color or {}
    local accent = hex(color.accent or { 0.12, 0.56, 1 })
    local muted = hex(color.muted or { 0.55, 0.51, 0.45 })
    local lines = { "Patterns you can buy in this zone, for future crafts:" }
    local vendors, listed = VendorWatch.ByVendor(found), 0
    for _, v in ipairs(vendors) do
        if listed >= SHOWN then break end
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("%s%s, %s|r"):format(muted, v.target.name, CP.Waypoint.Describe(v.target))
        for _, buy in ipairs(v.buys) do
            if listed >= SHOWN then break end
            listed = listed + 1
            local need = ("skill %d"):format(buy.skill)
            if buy.faction then
                local data = C_Reputation.GetFactionDataByID(buy.faction)
                local label = _G["FACTION_STANDING_LABEL" .. buy.standing] or ""
                need = ("%s, %s %s"):format(need, data and data.name or "faction", label)
            end
            if buy.limited then
                lines[#lines + 1] = ("%s%s (%s, limited stock)|r"):format(accent, buy.name, need)
            else
                lines[#lines + 1] = ("%s (%s)"):format(buy.name, need)
            end
        end
    end
    if listed < #found then lines[#lines + 1] = ("…and %d more"):format(#found - listed) end
    lines[#lines + 1] = ""
    if #vendors > 1 then
        lines[#lines + 1] = ("Mark all %d vendors on the map, with a waypoint to the nearest?"):format(#vendors)
    else
        lines[#lines + 1] = ("Mark %s on the map, with a waypoint?"):format(vendors[1].target.name)
    end
    return table.concat(lines, "\n")
end

-- Map pins ----------------------------------------------------------------------
-- The game holds one user waypoint, so every vendor gets a pin on the world map and
-- minimap, and the waypoint goes to the nearest. Pins clear on leaving the zone.

local Pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local REF = "ProfLost_Vendors"
local MEDIA = CP.MEDIA
local pool, usedPins = {}, 0
VendorWatch.marked = nil  -- zone the pins are in

local function pinTip(self)
    local v = self.vendor
    local color = CP.Style and CP.Style.color or {}
    local a = color.accent or { 0.12, 0.56, 1 }
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(v.target.name, 1, 1, 1)
    for _, buy in ipairs(v.buys) do
        if buy.limited then
            GameTooltip:AddDoubleLine(buy.name, "limited stock", a[1], a[2], a[3], a[1], a[2], a[3])
        else
            GameTooltip:AddDoubleLine(buy.name, ("skill %d"):format(buy.skill), 0.9, 0.9, 0.9, 0.6, 0.6, 0.6)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click: remove this pin", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Shift-right-click: remove all", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function vendorPin(v, size)
    usedPins = usedPins + 1
    local f = pool[usedPins]
    if not f then
        f = CreateFrame("Frame")
        CP.MapPins.Adopt(f)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local mask = f:CreateMaskTexture()
        mask:SetAllPoints(f.icon)
        mask:SetTexture(MEDIA .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.icon:AddMaskTexture(mask)
        f.ring = f:CreateTexture(nil, "OVERLAY")
        f.ring:SetAllPoints()
        f.ring:SetTexture(MEDIA .. "GrindRing")
        f:EnableMouse(true)
        f:SetScript("OnEnter", pinTip)
        f:SetScript("OnLeave", GameTooltip_Hide)
        f:SetScript("OnMouseUp", function(self, button)
            if button ~= "RightButton" then return end
            GameTooltip:Hide()
            if IsShiftKeyDown() then VendorWatch.RemoveAll() else VendorWatch.Remove(self.vendor) end
        end)
        pool[usedPins] = f
    end
    f:SetSize(size, size)
    local inset = math.floor(size * 0.12)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", inset, -inset)
    f.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    -- The vendor's face, as the Dungeon Journal shows bosses; a pattern icon without one.
    local first = v.buys[1]
    if v.target.display and SetPortraitTextureFromCreatureDisplayID then
        f.icon:SetTexCoord(0, 1, 0, 1)
        SetPortraitTextureFromCreatureDisplayID(f.icon, v.target.display)
    else
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon:SetTexture(first and C_Item.GetItemIconByID(first.item) or 134939)
    end
    f.vendor = v
    return f
end

-- A vendor pin outside the pool, for tests.
function VendorWatch.TestPin(v)
    local f = vendorPin(v, 22)
    usedPins = usedPins - 1
    return f
end

local marked = {}  -- vendor groups with pins: { target, buys, mapID, x, y, mini, world }

-- Pins off; the waypoint is left alone.
function VendorWatch.ClearPins()
    if Pins then
        Pins:RemoveAllMinimapIcons(REF)
        Pins:RemoveAllWorldMapIcons(REF)
    end
    usedPins = 0
    marked = {}
    VendorWatch.marked = nil
end

-- The marked vendor nearest the player in `zone`, else the first.
local function nearestOf(zone)
    local here = zone and C_Map.GetPlayerMapPosition(zone, "player")
    local px, py
    if here then px, py = here:GetXY() end
    local nearest, best
    for _, v in ipairs(marked) do
        -- In game a position once came back with x but no y: both, or no distance.
        local d = (px and py and v.x and v.y and v.mapID == zone) and ((v.x - px) ^ 2 + (v.y - py) ^ 2) or math.huge
        if not nearest or d < best then nearest, best = v, d end
    end
    return nearest
end

-- Point the waypoint at the nearest pin left, or clear it once none are.
local function retarget()
    local nearest = nearestOf(VendorWatch.marked)
    VendorWatch.target = nearest
    if nearest then
        CP.Waypoint.Place(nearest.target, true)
    elseif C_Map.ClearUserWaypoint then
        C_Map.ClearUserWaypoint()
        VendorWatch.marked = nil
    end
end

-- Remove one vendor's pins; the waypoint moves on if it pointed there.
function VendorWatch.Remove(v)
    for i, m in ipairs(marked) do
        if m == v then
            table.remove(marked, i)
            if Pins then
                if v.mini then Pins:RemoveMinimapIcon(REF, v.mini) end
                if v.world then Pins:RemoveWorldMapIcon(REF, v.world) end
            end
            if VendorWatch.target == v or #marked == 0 then retarget() end
            return true
        end
    end
    return false
end

-- Remove every pin and the waypoint they set.
function VendorWatch.RemoveAll()
    local had = #marked > 0 or VendorWatch.target ~= nil
    VendorWatch.ClearPins()
    VendorWatch.target = nil
    if had and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
end

-- Talking to a pinned vendor removes its pin.
function VendorWatch.Visited(entry)
    for _, v in ipairs(marked) do
        if entry and v.target.entry == entry then return VendorWatch.Remove(v) end
    end
    return false
end

function VendorWatch.Marked() return marked end

-- Puts one vendor's pins on the minimap and world map, unless "Icons on the map" is off.
function VendorWatch.Pin(v)
    if not Pins or CP.db.mapIcons == false then return end
    v.mini = vendorPin(v, 22)
    Pins:AddMinimapIconMap(REF, v.mini, v.mapID, v.x, v.y, false, true)
    -- The map's default pin layer, below the player arrow.
    v.world = vendorPin(v, 34)
    Pins:AddWorldMapIconMap(REF, v.world, v.mapID, v.x, v.y)
end

-- "Icons on the map" was switched: the pins go or come back; the waypoint is left alone.
function VendorWatch.IconsChanged()
    if Pins then
        Pins:RemoveAllMinimapIcons(REF)
        Pins:RemoveAllWorldMapIcons(REF)
    end
    usedPins = 0
    for _, v in ipairs(marked) do
        v.mini, v.world = nil, nil
        VendorWatch.Pin(v)
    end
end

-- Pin every vendor in `found` and set the waypoint to the nearest. Returns the vendor
-- groups and the nearest one.
function VendorWatch.MarkAll(found, zone)
    VendorWatch.ClearPins()
    local vendors = VendorWatch.ByVendor(found or {})
    for _, v in ipairs(vendors) do
        local mapID, pos = CP.Waypoint.Locate(v.target)
        local x, y
        if pos then x, y = pos:GetXY() end
        -- A vendor the map can't place (no x or y) gets no pin.
        if mapID and x and y then
            v.mapID, v.x, v.y = mapID, x, y
            VendorWatch.Pin(v)
            marked[#marked + 1] = v
        end
    end
    VendorWatch.marked = zone
    local nearest = nearestOf(zone)
    VendorWatch.target = nearest
    local placed = nearest and CP.Waypoint.Place(nearest.target, true)
    if placed or (Pins and CP.db.mapIcons ~= false and #marked > 0) then
        local line
        if #marked > 1 then
            line = ("Waypoints set for %d vendors."):format(#marked)
            if placed then line = line .. (" The arrow points to the nearest, %s."):format(nearest.target.name) end
        elseif placed then
            line = ("Waypoint set for %s, %s."):format(nearest.target.name, CP.Waypoint.Describe(nearest.target))
        else
            line = ("%s is marked on the map."):format(marked[1].target.name)
        end
        CP:Print(line .. " Right-click a pin to remove it, Shift-right-click to remove all.")
    end
    return vendors, nearest
end

-- The zone's patterns for the checklist: { zone, found }.
VendorWatch.current = nil

-- The zone the unseen count (GatherList.unseen) belongs to.
VendorWatch.counted = nil

local function check()
    local zone = CP.Waypoint.PlayerZone()
    local GL = CP.GatherList
    if VendorWatch.marked and VendorWatch.marked ~= zone then VendorWatch.RemoveAll() end
    if not CP.db.vendorAlerts or not zone then
        -- Turned off, the count waits for the setting to come back on in the same zone.
        VendorWatch.current = nil
        GL.pulseUntil = 0
        if not zone then GL.unseen, VendorWatch.counted = 0, nil end
        GL.Changed()
        return
    end
    local found = VendorWatch.Find(zone, true)
    VendorWatch.current = #found > 0 and { zone = zone, found = found } or nil
    local fresh = 0
    for _, f in ipairs(found) do
        if f.new then fresh = fresh + 1 end
        asked[f.tag] = true
    end
    if fresh > 0 and GL.Notify then
        VendorWatch.counted = zone
        GL.Notify(#found)
    else
        if VendorWatch.counted ~= zone then GL.unseen = 0 end
        GL.Changed()
    end
end
VendorWatch.Check = check

-- Creature entry of the open merchant, from its GUID ("Creature-0-...-<entry>-...").
local function merchantEntry()
    local guid = UnitGUID("npc")
    local entry = guid and select(6, strsplit("-", guid))
    return tonumber(entry)
end

-- True when a vendor visit this session showed the pattern sold out.
function VendorWatch.IsSoldOut(item)
    return soldOut[item] == true
end

-- A watched pattern this merchant should sell but doesn't list is sold out for now, and one
-- it lists is back in stock. `unsure` is true when a slot's item had not loaded, so a missing
-- pattern proves nothing and no mark is set.
function VendorWatch.CheckMerchant(entry, listed, unsure)
    for _, buys in pairs(CP.charDB.vendorWatch or {}) do
        for _, buy in ipairs(buys) do
            if listed[buy.item] then
                soldOut[buy.item] = nil
            elseif not unsure then
                for _, n in ipairs(buy.npcs or {}) do
                    if n == entry then soldOut[buy.item] = true end
                end
            end
        end
    end
end

CP:On("MERCHANT_SHOW", function()
    local entry = merchantEntry()
    if not entry then return end
    local listed, unsure = {}, false
    for i = 1, GetMerchantNumItems() do
        -- The slot's link names the item when its id has not loaded yet.
        local id = GetMerchantItemID(i)
        if not id then
            local link = GetMerchantItemLink and GetMerchantItemLink(i)
            id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
        end
        if id then listed[id] = true else unsure = true end
    end
    VendorWatch.CheckMerchant(entry, listed, unsure)
    VendorWatch.Visited(entry)
    CP.Panel:Refresh()  -- a sold-out pattern drops out of the plan
end)

-- One check per burst of events; subzone moves fire often.
local pending = false
local function soon(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay, function()
        pending = false
        check()
    end)
end

-- The watch list changed: the zone's patterns are read again on the next frame.
function VendorWatch.Recheck() soon(0) end

-- This session's notes: the patterns flagged, the zone counted, the zone's patterns and the
-- gathering panel's pattern count. A profession preview (UI/Preview.lua) takes them at its
-- start and gives them back at its end.
function VendorWatch.Notes()
    local GL = CP.GatherList
    local flagged = {}
    for tag in pairs(asked) do flagged[tag] = true end
    return { asked = flagged, counted = VendorWatch.counted, current = VendorWatch.current,
             unseen = GL.unseen, patternsOpen = GL.patternsOpen, pulseUntil = GL.pulseUntil }
end

function VendorWatch.SetNotes(n)
    local GL = CP.GatherList
    wipe(asked)
    for tag in pairs(n.asked) do asked[tag] = true end
    VendorWatch.counted, VendorWatch.current = n.counted, n.current
    GL.unseen, GL.patternsOpen, GL.pulseUntil = n.unseen, n.patternsOpen, n.pulseUntil
end

CP:On("ZONE_CHANGED_NEW_AREA", function() soon(2) end)
CP:On("ZONE_CHANGED", function() soon(2) end)            -- moving between subzones
CP:On("ZONE_CHANGED_INDOORS", function() soon(2) end)
CP:On("PLAYER_ENTERING_WORLD", function() soon(5) end)
CP:On("TRADE_SKILL_CLOSE", function() soon(1) end)      -- the list was just rebuilt
