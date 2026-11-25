-- Work the addon skips when it can't change what shows: redraws after an enchant step
-- is gone, other units' events, guest scans, the route while the gathering panel is
-- shut, a hidden window's redraw, bag slot paints, item-name bursts and alpha logging.
-- Each case counts calls through wrappers set with World.set.

local CP = ProfLost
local W, P, GL, GP = CP.Window, CP.Panel, CP.GatherList, CP.GatherPanel
local LW, TAILOR, ENCHANTING, MINING, HERBALISM, SKINNING = 165, 197, 333, 186, 182, 393
local DUROTAR = 1411
local HEARTHSTONE = 6948   -- in no guide
local BRACER = 7418        -- Enchant Bracer - Inferior Stamina

-- A free guide window, the gathering panel folded unless `gather`, the route on.
local function scene(gather)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde", shareSolves = true })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [ENCHANTING] = 80,
        [MINING] = 60, [HERBALISM] = 40, [SKINNING] = 90 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "gatherOpen", gather == true)
    World.set(CP.db, "route", true)
    World.onEnd(function()
        T.fire("PLAYER_REGEN_ENABLED")
        W.opened = false
        W.Update()
    end)
    W.Update()
    GP.Layout()
    CP.Gather.UpdateAllNeeds()
    T.advance(3)
    T.ok(P.frame:IsShown(), "the window shows")
end

-- Counts calls of `tbl[name]` from now on; returns a reader.
local function count(tbl, name)
    local n, fn = 0, tbl[name]
    World.set(tbl, name, function(...)
        n = n + 1
        return fn(...)
    end)
    return function() return n end
end

-- The /proflost mem report's line for `label`, or nil.
local function memLine(label)
    local before = #T.prints()
    SlashCmdList.PROFLOST("mem")
    for i = before + 1, #T.prints() do
        local line = tostring(T.prints()[i])
        if line:find(label, 1, true) then return line end
    end
    return nil
end

T.test("an enchant step's window closed: a player spell cast redraws nothing", function()
    scene()
    local EA = CP.EnchantAgain
    EA.row = { key = "test", spell = BRACER, recipe = CP.Guides[ENCHANTING].recipes[BRACER] }
    W.Close()
    T.ok(not P.frame:IsShown(), "closed")
    local redraws = count(P, "Refresh")
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 133)
    T.fire("UNIT_SPELLCAST_FAILED", "player", "cast-2", 133)
    T.advance(1)
    T.eq(redraws(), 0, "panel redraws after the window closed")
    EA.row = nil
end)

T.test("an enchant step on screen: a combat spell redraws nothing, the enchant does", function()
    scene()
    local EA = CP.EnchantAgain
    EA.row = { key = "test", spell = BRACER, recipe = CP.Guides[ENCHANTING].recipes[BRACER] }
    local redraws = count(P, "Refresh")
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 133)
    T.advance(1)
    T.eq(redraws(), 0, "panel redraws after a fireball")
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", BRACER)
    T.advance(1)
    T.eq(redraws(), 1, "panel redraws after the enchant")
    EA.row = nil
end)

T.test("another unit's spell cast and aura change reach no handler", function()
    scene()
    SlashCmdList.PROFLOST("mem on")
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "target", "cast-1", 133)
    T.fire("UNIT_SPELLCAST_START", "nameplate3", "cast-2", 133)
    T.fire("UNIT_AURA", "party1")
    local cast, aura = memLine("UNIT_SPELLCAST"), memLine("UNIT_AURA")
    SlashCmdList.PROFLOST("mem off")
    T.eq(cast, nil, "a cast handler ran")
    T.eq(aura, nil, "an aura handler ran")
end)

T.test("a UNIT_ event registers for the player only", function()
    local hub = CP.hub
    T.ok(hub ~= nil, "CP.hub")
    local asked = {}
    World.set(hub, "RegisterEvent", function(_, event) asked[#asked + 1] = "all " .. event end)
    World.set(hub, "RegisterUnitEvent", function(_, event, unit) asked[#asked + 1] = unit .. " " .. event end)
    CP:On("UNIT_HEALTH", function() end)
    CP:On("PLAYER_FOCUS_CHANGED", function() end)
    T.eq(asked, { "player UNIT_HEALTH", "all PLAYER_FOCUS_CHANGED" })
end)

T.test("profession windows opening and closing walk no frames", function()
    scene()
    local walks = count(UIParent, "GetChildren")
    for _ = 1, 3 do
        CraftWorld.Open(LW)
        T.advance(1.5)
        CraftWorld.Close()
        T.advance(0.5)
    end
    T.fire("ADDON_LOADED", "ItemTree")
    CraftWorld.Open(LW)
    T.advance(1.5)
    CraftWorld.Close()
    T.eq(walks(), 0, "no frame walk: the guide window takes no other addon's buttons")
end)

-- Still-needed items of the gathering guides, and the route's row builds from now on.
local function needed()
    for item, n in pairs(CP.Gather.Needs()) do
        if n > 0 and CP.Purchases.Have(item) < n then return item, n end
    end
end

T.test("a bag change with the gathering panel shut rebuilds the route once, only when the needs move", function()
    scene()
    T.ok(not GP.Showing(), "the panel is shut")
    local rows = count(GL, "RouteRows")
    for i = 1, 3 do
        CraftWorld.SetBag(HEARTHSTONE, i)
        T.advance(0.2)
    end
    T.advance(2)
    local same = rows()

    local item, n = needed()
    T.ok(item ~= nil, "a still-needed item")
    for i = 1, 3 do
        CraftWorld.SetBag(item, n * i)
        T.advance(0.2)
    end
    T.advance(2)
    local moved = rows() - same

    T.fire("PLAYER_REGEN_DISABLED")
    CraftWorld.SetBag(item, 0)
    T.advance(2)
    local fight = rows() - same - moved
    T.fire("PLAYER_REGEN_ENABLED")
    T.advance(2)
    local after = rows() - same - moved - fight
    T.eq(("route builds: %d same needs, %d needs moved, %d in combat, %d after combat"):format(same, moved, fight, after),
        "route builds: 0 same needs, 1 needs moved, 0 in combat, 1 after combat")
end)

T.test("a hidden window's redraw waits for the next show", function()
    scene()
    W.Close()
    local chrome = count(W, "Chrome")
    P:Refresh()
    T.eq(chrome(), 0, "Window.Chrome while hidden")
    W.Open()
    T.advance(0.1)
    T.ok(chrome() >= 1, "the show lays the window out")
    T.ok(P.frame:IsShown(), "shown")
end)

T.test("a bag slot paint with marks off reads no needs; with tracing off it builds no trace text", function()
    scene()
    local NM = CP.NeededMarks
    local item = needed()
    T.ok(item ~= nil, "a still-needed item")
    local slot = CreateFrame("Button", nil, UIParent)
    slot.GetBagID = function() return 0 end
    slot:SetID(1)
    World.set(CP.db, "neededMarks", false)
    World.set(CP.trace, "marks", nil)
    local needs = count(NM, "Needed")
    NM.Update(slot, item)
    local off = needs()

    World.set(CP.db, "neededMarks", true)
    local strings = count(_G, "tostring")
    NM.Update(slot, item)
    T.eq(("%d Needed calls with marks off, %d tostring calls with tracing off"):format(off, strings()),
        "0 Needed calls with marks off, 0 tostring calls with tracing off")
    T.ok(slot.profLostMark and slot.profLostMark:IsShown(), "the mark shows")
end)

T.test("twenty item names over twenty frames redraw the window and the list once each", function()
    scene(true)
    T.ok(GP.Showing(), "the gathering panel shows")
    local panel, list = count(P, "Refresh"), count(GL, "Refresh")
    for i = 1, 20 do
        local id = 990000 + i
        CP.RequestItem(id)
        T.fire("GET_ITEM_INFO_RECEIVED", id, true)
        T.advance(1 / 60)
    end
    T.advance(1)
    T.eq(("%d panel redraws, %d list rebuilds"):format(panel(), list()), "1 panel redraws, 1 list rebuilds")
end)

T.test("Daylight UI's whisper card moves the window from its own show and hide, found when made", function()
    scene()
    local updates = count(W, "Update")
    -- The harness's stub takes only an index; the client takes the addon's name too.
    World.set(C_AddOns, "IsAddOnLoaded", function(name) return name == "DaylightUI_Chat" end)
    T.fire("ADDON_LOADED", "DaylightUI_Chat")
    local before = rawget(_G, "DaylightUIChatTalk")
    local card = CreateFrame("Frame", "DaylightUIChatTalk", UIParent)
    rawset(_G, "DaylightUIChatTalk", before)
    card:Hide()
    World.set(_G, "DaylightUIChatTalk", card)
    T.advance(1)
    T.eq(updates(), 0, "nothing moves while the card is shut")
    card:Show()
    T.eq(updates(), 1, "the card's show moves the window")
    card:Hide()
    T.eq(updates(), 2, "and its hide")
    T.advance(2)
    T.eq(updates(), 2, "no look between")
end)

T.test("an alpha change with the look watch off reads no stack", function()
    scene()
    World.set(CP.trace, "look", nil)
    local stacks = count(_G, "debugstack")
    P.frame:SetAlpha(0.5)
    P.frame:SetAlpha(0.6)
    P.frame:SetAlpha(1)
    T.eq(stacks(), 0, "debugstack calls")
end)
