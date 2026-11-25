local _, CP = ...
if CP.stopped then return end

-- The icon of the profession that needs it, small and round in the corner of bag and
-- bank slots holding an item the player's guides still use, so it isn't sold or
-- vendored. Daylight UI's bags are marked through Paint kind "bagslot" on the overlay
-- API.Attach gives (UseDaylight); the game's own bag and bank slots through a hook on
-- SetItemButtonQuality. Daylight UI's bags fill a slot only when its bag changes
-- (DaylightUI_Bags Window.FillDirty), so every seen slot is repainted here when the
-- guides' needs or the setting change.

local NeededMarks = {}
CP.NeededMarks = NeededMarks

local MEDIA = CP.MEDIA
local SIZE = 14
local ICONS = {
    [164] = "Interface\\Icons\\Trade_BlackSmithing", [165] = "Interface\\Icons\\Trade_LeatherWorking",
    [197] = "Interface\\Icons\\Trade_Tailoring", [202] = "Interface\\Icons\\Trade_Engineering",
    [171] = "Interface\\Icons\\Trade_Alchemy", [333] = "Interface\\Icons\\Trade_Engraving",
    [185] = "Interface\\Icons\\INV_Misc_Food_15", [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
}
NeededMarks.ICONS = ICONS

-- What reached us so far, for the trace's summary.
NeededMarks.stats = { daylight = nil, paints = 0, hooks = 0, refreshes = 0 }

-- The profession that needs the most of `item`, or nil.
function NeededMarks.Needed(item)
    local best, most
    for key, needs in pairs(CP.charDB and CP.charDB.gatherNeeds or {}) do
        local n = needs[item] or 0
        if n > 0 and (not most or n > most) then best, most = key, n end
    end
    return best
end

local function itemOf(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return (C_Item.GetItemInfoInstant(value)) end
    return nil
end

-- Every host painted so far: host -> { item, bag, slot, via }. Weak, so a released
-- frame goes.
local slots = setmetatable({}, { __mode = "k" })

-- Trace ---------------------------------------------------------------------------

-- Hidden: /proflost trace marks on|off prints each paint, at most TRACE_PER_SECOND lines a
-- second. On for this session only.
NeededMarks.TRACE_PER_SECOND = 40
local budget = { at = -1, n = 0, dropped = 0 }

function NeededMarks.Tracing()
    return CP.trace.marks == true
end

local function trace(fmt, ...)
    if not NeededMarks.Tracing() then return end
    local now = GetTime()
    if now - budget.at >= 1 then
        if budget.dropped > 0 then CP.TraceLine("marks", now, "(%d lines dropped)", budget.dropped) end
        budget.at, budget.n, budget.dropped = now, 0, 0
    end
    if budget.n >= NeededMarks.TRACE_PER_SECOND then
        budget.dropped = budget.dropped + 1
        return
    end
    budget.n = budget.n + 1
    CP.TraceLine("marks", now, fmt, ...)
end

local function profName(key)
    local guide = key and CP.Guides and CP.Guides[key]
    return guide and guide.name or tostring(key)
end

-- Paint ---------------------------------------------------------------------------

-- Shows or hides the mark on `host` (a frame) for `item`. Returns whether it shows,
-- the profession that needs the item, and why not.
local function paint(host, item)
    local why, prof
    if not (CP.db and CP.db.neededMarks) then
        why = "setting off"
    elseif not item then
        why = "empty"
    else
        prof = NeededMarks.Needed(item)
        if not prof then why = "not needed" end
    end
    local mark = host.profLostMark
    if not prof then
        if mark then mark:Hide() end
        return false, nil, why
    end
    if not mark then
        mark = host:CreateTexture(nil, "OVERLAY", nil, 7)
        mark:SetSize(SIZE, SIZE)
        mark:SetPoint("TOPLEFT", 1, -1)
        mark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local mask = host:CreateMaskTexture()
        mask:SetAllPoints(mark)
        mask:SetTexture(MEDIA .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mark:AddMaskTexture(mask)
        host.profLostMark = mark
    end
    mark:SetTexture(ICONS[prof] or MEDIA .. "Icon")
    mark.prof = prof
    mark:Show()
    return true, prof
end

-- Paints `host` for `item` and remembers it; `via` names the path for the trace.
local function markSlot(host, item, via, bag, slot)
    local s = slots[host]
    if not s then
        s = {}
        slots[host] = s
    end
    s.item, s.bag, s.slot, s.via = item, bag, slot, via
    local drawn, prof, why = paint(host, item)
    if (item or drawn) and NeededMarks.Tracing() then
        trace("%s %s:%s item %s, needed %s, drawn %s%s", via, tostring(bag), tostring(slot), tostring(item),
            prof and profName(prof) or "no", drawn and "yes" or "no", why and (" (" .. why .. ")") or "")
    end
    return drawn
end

-- Show or hide the mark on a game bag or bank slot for the item it holds.
function NeededMarks.Update(button, itemIDOrLink)
    if not (button and button.GetBagID) then return end
    NeededMarks.stats.hooks = NeededMarks.stats.hooks + 1
    local ok, bag = pcall(button.GetBagID, button)
    markSlot(button, itemOf(itemIDOrLink), "game", ok and bag or "?", button.GetID and button:GetID() or "?")
end

-- Repaints every slot seen so far, e.g. after the setting or the needs change.
function NeededMarks.Refresh()
    NeededMarks.stats.refreshes = NeededMarks.stats.refreshes + 1
    local n = 0
    for host, s in pairs(slots) do
        paint(host, s.item)
        n = n + 1
    end
    trace("repainted %d slots", n)
end

local function refreshSoon() CP:Soon("neededMarks", NeededMarks.Refresh) end

-- Marks Daylight UI's bag, bank and alt slots. Plugin.Start hands over `me` and the API.
function NeededMarks.UseDaylight(me, API)
    if not (me and type(me.Paint) == "function" and API and type(API.Attach) == "function") then
        NeededMarks.stats.daylight = "no Paint or Attach in its API"
        return false
    end
    local handle = me.Paint("bagslot", function(slot, _, info)
        NeededMarks.stats.paints = NeededMarks.stats.paints + 1
        local t = type(info) == "table" and info or {}
        local host = API.Attach(slot)
        if not host then
            trace("daylight %s:%s: API.Attach gave no overlay", tostring(t.bag), tostring(t.slot))
            return
        end
        markSlot(host, t.itemID, "daylight", t.bag, t.slot)
    end)
    NeededMarks.stats.daylight = handle and "registered" or "Paint refused bagslot"
    return handle ~= nil
end

-- Turns the trace on or off and says what has reached us so far.
function NeededMarks.SetTrace(on)
    CP.SetTracing("marks", on)
    if not on then
        CP:Print("Bag marks trace off.")
        return
    end
    local st, kinds, seen = NeededMarks.stats, 0, 0
    for _ in pairs(CP.charDB and CP.charDB.gatherNeeds or {}) do kinds = kinds + 1 end
    for _ in pairs(slots) do seen = seen + 1 end
    CP:Print(("Bag marks trace on: setting %s, needs for %d professions, Daylight UI paint %s, %d paints, %d game hooks, %d slots seen. Open your bags, move an item, and paste what follows.")
        :format(CP.db.neededMarks and "on" or "off", kinds, tostring(st.daylight or "not asked"), st.paints, st.hooks, seen))
    NeededMarks.Refresh()
    for host, s in pairs(slots) do
        local drawn = host.profLostMark ~= nil and host.profLostMark:IsShown()
        if s.item then
            trace("seen %s %s:%s item %s, drawn %s, host shown %s", s.via, tostring(s.bag), tostring(s.slot),
                tostring(s.item), drawn and "yes" or "no", tostring(host:IsVisible()))
        end
    end
end

if SetItemButtonQuality then
    hooksecurefunc("SetItemButtonQuality", function(button, _, itemIDOrLink)
        NeededMarks.Update(button, itemIDOrLink)
    end)
end

-- The guides' needs changed (Gather.SaveNeeds), or the saved ones arrived.
CP:On("ProfLost_NEEDS", refreshSoon)
CP:On("PLAYER_ENTERING_WORLD", refreshSoon)
