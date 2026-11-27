local _, CP = ...
if CP.stopped then return end

-- The gathering checklist: what the player can gather in their zone for their guides,
-- one section per profession. Clicking an item opens the creatures, nodes and waters
-- that give it. The map button draws a gathering loop (UI/RouteMap.lua); the Fishing
-- section leads with where to fish next. UI/GatherPanel.lua mounts it in the panel
-- that slides out of the guide window.

local S = CP.Style
local Gather = CP.Gather

local GatherList = {
    width = CP.Panel.WIDTH - 20,   -- the list's width inside its panel; the detached grip changes it
}
CP.GatherList = GatherList

local ROW_H = 20

-- The header's insets inside the list, set by its panel so it lines up with the guide's
-- title bar: `left` and `right` px in from the list's sides, `up` px above its top.
GatherList.headInset = { left = 0, right = 0, up = 0 }

-- How far below the list's top the rows start: the end of the two-line header
-- (Style.HEADER). It never changes with what the header says, so the rows stay put.
local function headH() return S.HEADER.height - GatherList.headInset.up end
GatherList.HeadHeight = headH

local EDGE = 0          -- rows and header buttons sit this far in from the tab's edge
local INFO_EDGE = 2      -- a row's info this far in from its right edge, with no pin or check
local MAX_ROWS = 22      -- rows drawn while the tab's height is unknown; more scroll
local FADE = 0.25
local MEDIA = CP.MEDIA
local FEED_ARROW_X = 20   -- a feed line's arrow, under its "Fish in" heading's text (18 in)
local PULSE_ALPHA = 0.4  -- the pulsing header's fill at full

local PROF_NAME = {
    [Gather.SKINNING] = "Skinning", [Gather.MINING] = "Mining", [Gather.HERBALISM] = "Herbalism",
    [Gather.COOKING] = "Cooking", [Gather.FISHING] = "Fishing",
}
local PROF_ORDER = {
    [Gather.SKINNING] = 1, [Gather.MINING] = 2, [Gather.HERBALISM] = 3,
    [Gather.COOKING] = 4, [Gather.FISHING] = 5,
}

local open = {}      -- itemID -> true when its sources are shown, this session
local lines = {}     -- what the rows show, rebuilt on refresh
local offset = 0     -- first shown line when the list scrolls
local inCombat = false

-- Frame --------------------------------------------------------------------------

-- The list's frame, made here and mounted in the gathering panel (GatherList.Mount).
local f = CreateFrame("Frame", "ProfLost_GatherList", UIParent)
f:SetSize(GatherList.width, headH())
f:EnableMouseWheel(true)
f:Hide()
GatherList.frame = f

-- The panel's body once mounted; the rows fill its height.
local host

local head = CreateFrame("Frame", nil, f)
head:SetPoint("TOPLEFT")
head:SetPoint("TOPRIGHT")
head:SetHeight(S.HEADER.height)

-- The header's icons are Daylight UI's header icon buttons (Style.IconButton): ProfLost's
-- trail glyph for the route (tinted like the others, in both looks), its menu bars for the
-- route filter. The map pin stays the "set a waypoint" mark on rows and cards.
GatherList.ROUTE_ICON = MEDIA .. "Trail"
GatherList.ROUTE_OFF_ALPHA = 0.35
head.route = S.IconButton(head, { icon = "ui-data-location.png", art = GatherList.ROUTE_ICON, size = 16,
    onClick = function(_, button)
        if button and button ~= "LeftButton" then return end
        CP.db.route = not GatherList.RouteOn()
        GatherList.RouteShade()
        GatherList.Refresh()
    end })
head.route:SetPoint("RIGHT", head, "TOPRIGHT", 0, -S.HEADER.mid)
head.route:RegisterForClicks("LeftButtonUp")

-- The route filter: Follow the guide or Farm, and which herbs and ore. Its icon is Daylight
-- UI's menu bars (Style.IconButton), ours without it.
GatherList.FILTER_ICONS = { daylight = "ui-micro-menu.png", own = MEDIA .. "Menu" }
head.filter = S.IconButton(head, { icon = GatherList.FILTER_ICONS.daylight, own = GatherList.FILTER_ICONS.own, size = 14,
    onClick = function(self) GatherList.RouteMenu(self) end })
head.filter:SetPoint("RIGHT", head.route, "LEFT", head.route.daylight and 0 or -4, 0)

-- Two lines, where Style.HEADER puts them: the zone the list is for, then a smaller dim
-- note with where the player really is ("in Gnomeregan") and the route's state. The note
-- always shows. Both stop short of the icons, which centre on the two lines, as Daylight
-- UI's sub line stops short of its close.
local H = S.HEADER
GatherList.HEAD_ICONS = 40   -- the route and filter icons, and the gap before them
head.title = S.HeaderText(head, 1, S.color.title)
head.title:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -H.top)
head.title:SetPoint("TOPRIGHT", head.filter, "LEFT", -6, H.mid - H.top)
head.status = S.HeaderText(head, 2, S.color.muted)
head.status:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -H.line2Top)
head.status:SetPoint("TOPRIGHT", head.filter, "LEFT", -6, H.mid - H.line2Top)
GatherList.head = head

-- The zone's name is a control: Daylight UI's tab ink on it (Style.TextSwitch), a click opens
-- the zone menu (GatherList.ZoneMenu). It covers the name's own width (GatherList.FitTitle).
GatherList.ZONE_TIP = { "Plan another zone", "See what you can gather there before you go." }
local function zoneTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(GatherList.ZONE_TIP[1], 1, 1, 1)
    GameTooltip:AddLine(GatherList.ZONE_TIP[2], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end
GatherList.ZoneTip = zoneTip
head.zone = S.TextSwitch(head, head.title, function(self) GatherList.ZoneMenu(self) end, zoneTip)
head.zone:ClearAllPoints()
head.zone:SetPoint("TOPLEFT", head.title, "TOPLEFT")
head.zone:SetPoint("BOTTOMLEFT", head.title, "BOTTOMLEFT")
head.zone:SetWidth(1)
head.zone:Show()

-- While a picked zone is listed, the note ends in "back": a click follows the player again
-- (GatherList.SetZone). It is its own text after the note's, so only the word takes the ink.
GatherList.BACK = "back"
GatherList.BACK_TIP = { "Back to where you are", "The panel lists your own zone again." }
local function backTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(GatherList.BACK_TIP[1], 1, 1, 1)
    GameTooltip:AddLine(GatherList.BACK_TIP[2], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end
GatherList.BackTip = backTip
head.backText = S.HeaderText(head, 2, S.color.muted)
head.backText:SetPoint("TOPLEFT", head.status, "TOPLEFT")
head.back = S.TextSwitch(head, head.backText, function() GatherList.SetZone(nil) end, backTip)

-- Room kept clear at the header's right end, for the detached panel's close button.
GatherList.headRoom = 0

local function placeHead()
    local i = GatherList.headInset
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", i.left, i.up)
    head:SetPoint("TOPRIGHT", -(i.right + GatherList.headRoom), i.up)
    if GatherList.FitNote then GatherList.FitNote() end
end

function GatherList.SetHeadRoom(px)
    if GatherList.headRoom == px then return end
    GatherList.headRoom = px
    placeHead()
end

function GatherList.SetHeadInsets(left, right, up)
    local i = GatherList.headInset
    i.left, i.right, i.up = left, right, up
    placeHead()
end

-- True while the route pin is on. A player who never set it has it on (DEFAULTS.route);
-- off is saved as false.
function GatherList.RouteOn()
    return CP.db ~= nil and CP.db.route ~= false
end

-- What the header's note says about the route.
GatherList.ROUTE_NOTES = {
    off = "Route is off", inside = "No route in a dungeon", none = "No route here", solving = "Finding a route",
}

-- What the header shows past the zone's name: where the player really is, and whether
-- the list is an instance's own (no route). Refresh sets them.
GatherList.place, GatherList.inside = nil, false

-- A picked zone (CP.charDB.gatherZone) is the player's plan for a zone they are heading to.
-- The panel lists it in place of the player's zone, and the header's note names where the
-- player is, then "back". Refresh sets `away` (true while it lists a picked zone), `here`
-- (the player's own zone) and `hereName` (that zone's name, for the note).
GatherList.YOU_IN = "You're in %s"
GatherList.away, GatherList.here, GatherList.hereName = false, nil, nil

-- The picked zone, or nil while the panel follows the player. A zone the data no longer
-- holds reads as none.
function GatherList.PickedZone()
    local zone = CP.charDB and CP.charDB.gatherZone
    if zone and CP.GatherData.zones[zone] then return zone end
    return nil
end

-- What the panel lists: zone, the header's place, the player's own zone, whether the zone is
-- a picked one, and the player's own place. A pick clears itself once the player stands in it,
-- alive, with the game's own map naming the zone. A ghost, or a spot the game gives no map
-- (a graveyard, Dire Maul's courtyard), reads its zone from overlapping zone rectangles,
-- which can name the picked zone when the player is far from it.
local function arrived(picked, here, sure)
    if not (picked and picked == here and sure) then return false end
    return not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
end

function GatherList.Where()
    local here, place, sure = Gather.PlayerSpot()
    local picked = GatherList.PickedZone()
    if arrived(picked, here, sure) then
        CP.charDB.gatherZone = nil
        picked = nil
    end
    if picked then return picked, nil, here, true, place end
    return here, place, here, false, place
end

-- Picks `zone` to plan ahead; nil, or the player's own zone, follows the player again.
function GatherList.SetZone(zone)
    if not CP.charDB then return end
    local here, _, sure = Gather.PlayerSpot()
    if zone == here and sure then zone = nil end
    CP.charDB.gatherZone = zone or nil
    GatherList.Refresh()
end

-- The note's route part, longest first; the later ones are shorter fallbacks. Only a
-- running solve is "Finding a route". A finished one shows its loop, or "No route here"
-- when it drew nothing.
local function routeParts()
    local N = GatherList.ROUTE_NOTES
    if not GatherList.RouteOn() then return { N.off } end
    if GatherList.inside then return { N.inside } end
    local status = CP.RouteMap.Status()
    if status then
        local last = status:match(".*· (.+)$")
        if last then return { status, last } end
        return { status }
    end
    return { CP.RouteMap.Solving() and N.solving or N.none }
end

-- The note's texts to try, widest first: the place with the full status, the place with
-- the spot count, the place alone, then the route part alone. The place outranks the
-- route, because without it the zone name above reads wrong. A profession preview's
-- marker (UI/Preview.lua) leads each text in the warning ink and outranks them all.
-- A picked zone's note is "You're in <zone> · back", the zone's name cut shorter while it
-- doesn't fit, then "back" alone. Each of its texts ends in BACK.
GatherList.NAME_MIN = 4   -- letters a cut zone name keeps at least

function GatherList.NoteTexts()
    local parts, out = routeParts(), {}
    local place = GatherList.place
    local tail = " · " .. GatherList.BACK
    if GatherList.away then
        local name = GatherList.hereName
        if name then
            out[#out + 1] = GatherList.YOU_IN:format(name) .. tail
            for n = #name - 1, GatherList.NAME_MIN, -1 do
                out[#out + 1] = GatherList.YOU_IN:format(name:sub(1, n) .. "...") .. tail
            end
        end
        out[#out + 1] = GatherList.BACK
    else
        if place then
            for _, r in ipairs(parts) do out[#out + 1] = ("in %s · %s"):format(place, r) end
            out[#out + 1] = "in " .. place
        end
        for _, r in ipairs(parts) do out[#out + 1] = r end
    end
    local marker = CP.Preview and CP.Preview.Marker()
    if not marker then return out end
    local lead = S.Hex(S.color.warn) .. marker .. "|r"
    for i, text in ipairs(out) do out[i] = lead .. " · " .. text end
    out[#out + 1] = GatherList.away and lead .. tail or lead
    return out
end

-- Room for either header line: the list's width less the header's insets, the room kept
-- at its right end, and the icons.
local function headWidth()
    local i = GatherList.headInset
    return GatherList.width - i.left - i.right - GatherList.headRoom - GatherList.HEAD_ICONS
end

-- The note line: the widest of NoteTexts that fits on one line, never cut short. Both
-- lines keep their header sizes through Daylight UI's font repaints. A picked zone's "back"
-- is its own text and click, right after the rest of the note.
local function setNote(text)
    if not GatherList.away then
        head.status:SetText(text)
        head.back:Hide()
        return
    end
    local lead = text:sub(1, #text - #GatherList.BACK)
    head.status:SetText(lead)
    head.backText:SetText(GatherList.BACK)
    local x = lead ~= "" and GatherList.Measure(lead, "small", true) or 0
    head.backText:ClearAllPoints()
    head.backText:SetPoint("TOPLEFT", head.status, "TOPLEFT", x, 0)
    head.back:SetWidth(math.max(1, GatherList.Measure(GatherList.BACK, "small", true)))
    head.back:Show()
end

function GatherList.FitNote()
    S.Pin(head.title)
    S.Pin(head.status)
    S.Pin(head.backText)
    local texts = GatherList.NoteTexts()
    local room = headWidth()
    for _, text in ipairs(texts) do
        if GatherList.Measure(text, "small", true) <= room then return setNote(text) end
    end
    setNote(texts[#texts])
end

local function routeShade()
    local on = GatherList.RouteOn()
    head.route.icon:SetDesaturated(not on)
    head.route.icon:SetAlpha(on and 1 or GatherList.ROUTE_OFF_ALPHA)
    GatherList.FitNote()
end
GatherList.RouteShade = routeShade


-- The route filter changed: re-solve the player's zone and, with other zones on, the rest.
function GatherList.RouteChanged()
    GatherList.Refresh()
    if CP.RouteMap.Revisit then CP.RouteMap.Revisit() end
end

-- Blizzard_Menu's element-description methods, called by name: they are Blizzard UI
-- code, not game API, and the API database doesn't index them.
local MENU = { title = "CreateTitle", radio = "CreateRadio", check = "CreateCheckbox", button = "CreateButton" }

-- The element description's own method that greys an entry, called by name for the same reason.
local ENTRY = { enabled = "SetEnabled", divider = "CreateDivider" }

local function menuReady(root)
    for _, name in pairs(MENU) do
        if type(root[name]) ~= "function" then return false end
    end
    return true
end

-- Ticks every herb and ore again; the leveling or farming choice stays (also a settings button).
function GatherList.RouteReset()
    Gather.RouteReset()
    GatherList.RouteChanged()
end

-- What a menu handler returns so the filter menu stays open and redraws its marks
-- (the game's menus close after a pick otherwise).
function GatherList.MenuStays()
    return MenuResponse and MenuResponse.Refresh or nil
end

-- Marks a menu entry to keep the menu open after it's picked, as Baganator's menus do.
local function stay(entry)
    if entry and entry.SetResponse then entry:SetResponse(MenuResponse and MenuResponse.Refresh) end
    return entry
end

-- Text in Daylight UI's muted ink, for menu lines (the game's menus take colour codes).
local function dim(text)
    local c = S.color.muted
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5), text)
end
GatherList.Dim = dim

local function zoneName(zone)
    local info = C_Map.GetMapInfo(zone)
    return info and info.name or "another zone"
end

GatherList.MODE_LABEL = { level = "Follow the guide", farm = "Farm: pick what to gather" }
GatherList.FOLLOW_MAX = 2      -- names on the Follow the guide line

-- What a Follow the guide route follows in `zone`: the names of the herbs, ore, leathers and
-- other loot its rows visit, in route order, once each.
function GatherList.Following(zone)
    local names, seen = {}, {}
    local function add(name)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    for _, r in ipairs(zone and GatherList.RouteRows(zone) or {}) do
        if r.itemID < 0 then
            add(r.sources[1] and r.sources[1].name)
        else
            add(r.name or CP.ItemName(r.itemID) or ("item " .. r.itemID))
        end
    end
    return names
end

-- The Follow the guide lines stay within the longest radio label's length.
local function followWidth()
    local w = 0
    for _, label in pairs(GatherList.MODE_LABEL) do w = math.max(w, #label) end
    return w
end

GatherList.FOLLOW_HEAD = "Following the guide"
GatherList.FOLLOW_NONE = "nothing to gather here"
GatherList.FOLLOW_DROP = { "^Raw " }   -- words a name drops to stay short

local function shortName(name)
    for _, pat in ipairs(GatherList.FOLLOW_DROP) do name = name:gsub(pat, "") end
    return name
end

-- A name cut to `width` characters, ending in "...".
local function fit(text, width)
    if #text <= width then return text end
    return text:sub(1, math.max(1, width - 3)) .. "..."
end

-- The "Following the guide" lines: the heading, up to FOLLOW_MAX short names one per
-- line, then "+N more" on the last name's line, or its own when that would run long.
-- No line is longer than the longest radio label.
function GatherList.FollowLines(names)
    if #names == 0 then return { GatherList.FOLLOW_HEAD, GatherList.FOLLOW_NONE } end
    local width = followWidth()
    local out = { GatherList.FOLLOW_HEAD }
    local k = math.min(#names, GatherList.FOLLOW_MAX)
    for i = 1, k do out[#out + 1] = fit(shortName(names[i]), width) end
    local more = #names - k
    if more > 0 then
        local tail = ("+%d more"):format(more)
        local joined = out[#out] .. " " .. tail
        if #joined <= width then out[#out] = joined else out[#out + 1] = tail end
    end
    return out
end

-- The Farm menu's leathers: every one the player's Skinning gets from the beasts of `zone`
-- alone, named by the item. No other zone is listed or named.
function GatherList.FarmLeathers(zone, skills)
    if not zone then return {} end
    local list = Gather.ContinentSkins({ zone }, skills, Gather.PlayerLevel(), UnitFactionGroup("player"))
    for _, mat in ipairs(list) do
        mat.label = CP.ItemName(mat.item) or ("item " .. mat.item)
    end
    return list
end

-- The panel's profession filter: one profession or all. Saved per character in
-- CP.charDB.panelProf (a skill line id; nil is All). The choices are the gathering
-- professions the character has, then the guided crafting professions it has, whose
-- vendor patterns belong to them.
GatherList.ALL_LABEL = "All professions"
GatherList.SHOW_HEADER = "Show"

function GatherList.PanelProfs()
    local out, seen, ids = {}, {}, {}
    for id in pairs(Gather.Skills()) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return PROF_ORDER[a] < PROF_ORDER[b] end)
    for _, id in ipairs(ids) do
        out[#out + 1] = { id = id, name = PROF_NAME[id] }
        seen[id] = true
    end
    -- Crafting professions the character has: Window.Professions is sorted by name.
    for _, p in ipairs(CP.Window and CP.Window.Professions() or {}) do
        if not seen[p.id] and CP.Guides and CP.Guides[p.id] then out[#out + 1] = { id = p.id, name = p.name } end
    end
    return out
end

-- The picked profession's skill line id, or nil for All. A pick the character no longer
-- has reads as All.
function GatherList.PanelProf()
    local id = CP.charDB and CP.charDB.panelProf
    if not id then return nil end
    for _, p in ipairs(GatherList.PanelProfs()) do
        if p.id == id then return id end
    end
    return nil
end

function GatherList.SetPanelProf(id)
    if not CP.charDB then return end
    CP.charDB.panelProf = id
    GatherList.Refresh()
end

-- `current` (VendorWatch.current) cut to the picked profession's patterns.
function GatherList.PickedPatterns(current)
    local pick = GatherList.PanelProf()
    if not pick then return current end
    local own = {}
    for _, buy in ipairs(CP.charDB.vendorWatch and CP.charDB.vendorWatch[pick] or {}) do own[buy] = true end
    local found = {}
    for _, f in ipairs(current.found) do
        if own[f.buy] then found[#found + 1] = f end
    end
    return { zone = current.zone, found = found }
end

-- The list's line when it has no rows.
function GatherList.EmptyText()
    local pick = GatherList.PanelProf()
    if pick then
        for _, p in ipairs(GatherList.PanelProfs()) do
            if p.id == pick then
                local craft = GatherList.CraftPick() and GatherList.CraftEmptyText(pick, p.name)
                return craft or ("Nothing for %s here."):format(p.name)
            end
        end
    end
    local skills = Gather.Skills()
    for _, prof in ipairs(GatherList.ZONE_PROFS) do
        if skills[prof] then return GatherList.EMPTY_NONE end
    end
    return GatherList.EMPTY_LEARN
end

-- The list's line with no rows and no profession picked. An outdoor zone always gives a
-- gathering skill a line (its skill-ups, or why not), so EMPTY_NONE is for a dungeon or a
-- zone with nothing to gather at all.
GatherList.EMPTY_LEARN = "Learn Herbalism, Mining or Skinning to gather here."
GatherList.EMPTY_NONE = "No herbs, ore or beasts to skin here."

-- The panel's own entries at the top of its menu: one profession or all (radios), and the
-- guide window's button when the panel stands alone.
function GatherList.ProfessionEntries(root)
    local profs = GatherList.PanelProfs()
    local G = CP.GatherPanel
    local guide = G and G.GuideButtonShown()
    if (#profs > 0 or guide) and type(root[ENTRY.divider]) == "function" then root[ENTRY.divider](root) end
    if #profs > 0 then
        root[MENU.title](root, GatherList.SHOW_HEADER)
        -- All is data false: a nil would not key a radio in the menu's own tables.
        local function isPick(id) return GatherList.PanelProf() == (id or nil) end
        local function pick(id)
            GatherList.SetPanelProf(id or nil)
            return GatherList.MenuStays()
        end
        stay(root[MENU.radio](root, GatherList.ALL_LABEL, isPick, pick, false))
        for _, p in ipairs(profs) do
            stay(root[MENU.radio](root, p.name, isPick, pick, p.id))
        end
    end
    if guide then
        root[MENU.button](root, G.GuideLabel(), function() G.ToggleGuide() end)
    end
end

-- The filter menu: Follow the guide or Farm. Follow the guide shows one dim line naming what the
-- route follows; its ticks stay saved for Farm. Farm ticks this zone's herbs and ore and
-- every leather this zone's beasts drop, and offers the reset. Each profession's section shows
-- only when the player has it; with none, one line says to learn one.
GatherList.ROUTE_LEARN = "No Mining, Herbalism or Skinning"

-- While the route pin is off, the menu's top line says so and every other entry is greyed.
GatherList.ROUTE_OFF = "Route is off: click the pin to show it"

-- The dim header over the herb, ore and leather ticks: a tick is saved and holds in any zone
-- that gives the item, though the menu lists only this zone's.
GatherList.TICKS_HEADER = "Picks are kept for other zones"

local function routeEntries(root)
    local zone = GatherList.PickedZone() or Gather.PlayerZone()
    local info = zone and C_Map.GetMapInfo(zone)
    local on = GatherList.RouteOn()
    if on then
        root[MENU.title](root, info and info.name and ("Gathering route: " .. info.name) or "Gathering route")
    else
        root[MENU.title](root, GatherList.ROUTE_OFF)
    end

    -- Every entry below the top line, greyed while the route is off.
    local function add(kind, ...)
        local entry = root[MENU[kind]](root, ...)
        if not on and type(entry) == "table" and type(entry[ENTRY.enabled]) == "function" then
            entry[ENTRY.enabled](entry, false)
        end
        return entry
    end
    local function isMode(mode) return (CP.db.routeMode or "level") == mode end
    local function setMode(mode)
        local was = Gather.RouteFarming()
        CP.db.routeMode = mode ~= "level" and mode or nil
        GatherList.RouteChanged()
        if Gather.RouteFarming() ~= was then GatherList.RebuildSoon() end
        return GatherList.MenuStays()
    end
    stay(add("radio", GatherList.MODE_LABEL.level, isMode, setMode, "level"))
    stay(add("radio", GatherList.MODE_LABEL.farm, isMode, setMode, "farm"))
    local skills = Gather.Skills()
    local learned = skills[Gather.MINING] ~= nil or skills[Gather.HERBALISM] ~= nil or skills[Gather.SKINNING] ~= nil
    if not learned then
        add("title", GatherList.ROUTE_LEARN)
        return
    end
    if not Gather.RouteFarming() then
        for _, line in ipairs(GatherList.FollowLines(GatherList.Following(zone))) do
            add("title", dim(line))
        end
        return
    end

    -- This zone's herbs and ore, by the skill each needs. Farm names no guide need. The
    -- ticks are saved by name and item, so they hold when the player enters another zone.
    add("title", dim(GatherList.TICKS_HEADER))
    local any = false
    for _, prof in ipairs({ { Gather.MINING, "Mining" }, { Gather.HERBALISM, "Herbalism" } }) do
        local nodes = skills[prof[1]] and zone and Gather.RouteNodes(prof[1], zone) or {}
        if #nodes > 0 then
            any = true
            add("title", prof[2])
            for _, node in ipairs(nodes) do
                local label = ("%s  (%d)"):format(node.name, node.skill)
                stay(add("check", label,
                    function(name) return not Gather.NodeUnticked(name) end,
                    function(name)
                        CP.db.routeSkip = CP.db.routeSkip or {}
                        CP.db.routeSkip[name] = not CP.db.routeSkip[name] or nil
                        GatherList.RouteChanged()
                        return GatherList.MenuStays()
                    end, node.name))
            end
        end
    end

    -- Every leather this zone's beasts drop: grind spots are built only for the ticked ones.
    if skills[Gather.SKINNING] then
        local mats = GatherList.FarmLeathers(zone, skills)
        if #mats > 0 then
            any = true
            add("title", "Skinning")
            for _, mat in ipairs(mats) do
                stay(add("check", mat.label,
                    function(item) return not Gather.SkinUnticked(item) end,
                    function(item)
                        CP.db.skinSkip = CP.db.skinSkip or {}
                        CP.db.skinSkip[item] = not CP.db.skinSkip[item] or nil
                        GatherList.RouteChanged()
                        return GatherList.MenuStays()
                    end, mat.item))
            end
        end
    end
    if not any then add("title", "Nothing to gather mapped here") end
    -- Worded by the professions the player has.
    local kind = Gather.ResetKind(skills)
    if kind then
        stay(add("button", CP.Settings.RESET_LABEL[kind], function()
            GatherList.RouteReset()
            return GatherList.MenuStays()
        end))
    end
end

-- The menu: the route's entries, then the panel's own (profession filter, guide button).
local function generate(_, root)
    if not menuReady(root) then
        CP:Print("The route filter can't open on this client.")
        return
    end
    routeEntries(root)
    GatherList.ProfessionEntries(root)
end

-- The open route menu (the game's) and the region it opened from.
GatherList.menu, GatherList.menuOwner = nil, nil

-- A root that records the entries `generate` adds, with no menu behind it: { kind, text, get,
-- set, data, fn, enabled, stays }. Daylight UI's menu is built from them.
local function recorder()
    local list, root = {}, {}
    local function entry(rec)
        rec.enabled = true
        function rec:SetEnabled(on) self.enabled = on ~= false end
        function rec:SetResponse() self.stays = true end
        list[#list + 1] = rec
        return rec
    end
    function root.CreateTitle(_, text) return entry({ kind = "title", text = text }) end
    function root.CreateRadio(_, text, get, set, data)
        return entry({ kind = "radio", text = text, get = get, set = set, data = data })
    end
    function root.CreateCheckbox(_, text, get, set, data)
        return entry({ kind = "check", text = text, get = get, set = set, data = data })
    end
    function root.CreateButton(_, text, fn) return entry({ kind = "button", text = text, fn = fn }) end
    function root.CreateDivider() return { SetEnabled = function() end, SetResponse = function() end } end
    return list, root
end

-- Rows Daylight UI's menu shows before it scrolls.
GatherList.NATIVE_ROWS = 18

local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The entries of the menu last opened in Daylight UI's own menu, by its row keys:
-- { owner, entries, keys }. Nil while the game's menu is the one in use.
GatherList.nativeMenu = nil

local function signature(list)
    local out = {}
    for _, e in ipairs(list) do
        out[#out + 1] = ("%s|%s|%s"):format(e.kind, e.text, tostring(e.enabled))
    end
    return table.concat(out, "\n")
end

local function closeNative()
    local addon = rawget(_G, "DaylightUI")
    local W = type(addon) == "table" and addon.Widgets
    if type(W) == "table" and type(W.CloseMenu) == "function" then W.CloseMenu() end
end

-- Opens the route menu in Daylight UI's own menu (API.Menu), so no frame of the game's shows.
-- Titles become its headings, or its quiet lines when they carry the muted ink; a greyed entry
-- is a quiet line too, since its menu has no disabled row. A pick runs the entry's own handler.
-- An entry that stays redraws the menu in place when its lines changed; the rest close it.
-- `gen` fills the menu (the route menu's `generate` when nil).
local function openNative(API, owner, gen)
    gen = gen or generate
    local list, root = recorder()
    gen(owner, root)
    local keys, values, titles, hints, entries = {}, {}, {}, {}, {}
    for _, e in ipairs(list) do
        local key = #keys + 1
        keys[key], entries[key], values[key] = key, e, e.text
        if e.kind == "title" then
            if e.text:find("^|c") then hints[key], values[key] = true, plain(e.text) else titles[key] = true end
        elseif not e.enabled then
            hints[key], values[key] = true, plain(e.text)
        end
    end
    local shape = signature(list)
    GatherList.nativeMenu = { owner = owner, entries = entries, keys = keys }
    API.Menu(owner, keys, values, nil, function(key)
        local e = entries[key]
        if not e or e.kind == "title" or not e.enabled then return end
        local ret
        if e.kind == "button" then ret = e.fn() else ret = e.set(e.data) end
        if not (e.stays or ret ~= nil) then return closeNative() end
        local fresh, froot = recorder()
        gen(owner, froot)
        if signature(fresh) ~= shape then openNative(API, owner, gen) end
    end, nil, {
        keepOpen = true, titles = titles, hints = hints, rows = GatherList.NATIVE_ROWS,
        checked = function(key)
            local e = entries[key]
            return e ~= nil and e.enabled and e.get ~= nil and not not e.get(e.data) or false
        end,
    })
end

-- The filter button's menu: Daylight UI's own while it is loaded, else the game's context menu.
function GatherList.RouteMenu(owner)
    local API = S.Daylight()
    if API and type(API.Menu) == "function" then
        GatherList.menuOwner, GatherList.menu = owner, nil
        return openNative(API, owner)
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    GatherList.menuOwner = owner
    GatherList.nativeMenu = nil
    GatherList.menu = MenuUtil.CreateContextMenu(owner, generate)
    return GatherList.menu
end

-- The route menu's entries as `generate` adds them to `root`, whichever menu shows them.
GatherList.Generate = generate

-- The zone menu ---------------------------------------------------------------------

-- The header's zone menu: Where I am, then every outdoor zone with gathering data under its
-- continent's heading, the player's continent first, each continent's zones by name. Each
-- zone's line carries a dim hint of what it holds for the player's gathering skills: the
-- skill range its herbs, ore or beasts span ("Skinning 230-300"). A zone with nothing for
-- those skills names its biggest gathering profession instead, so every line says something.
GatherList.ZONE_HERE = "Where I am"

local ZONE_TYPE = 3   -- Enum.UIMapType.Zone

-- The gathering professions a zone hint and the panel's skill lines read, in section order.
local ZONE_PROFS = { Gather.SKINNING, Gather.MINING, Gather.HERBALISM }
GatherList.ZONE_PROFS = ZONE_PROFS

-- "Skinning 230-300", or "Mining 65" when the zone's targets all need the same skill.
function GatherList.RangeText(zone, prof)
    local lo, hi = Gather.ZoneRange(zone, prof)
    if not lo then return nil end
    return lo == hi and ("%s %d"):format(PROF_NAME[prof], lo) or ("%s %d-%d"):format(PROF_NAME[prof], lo, hi)
end

-- The hint for `zone` at `skills`: the range of each of the player's gathering skills the zone
-- has targets for, else the range of its gathering profession with the most spawns. Nil only
-- for a zone with no herbs, ore or beasts to skin.
function GatherList.ZoneHint(zone, skills)
    local parts = {}
    for _, prof in ipairs(ZONE_PROFS) do
        local text = skills[prof] and GatherList.RangeText(zone, prof)
        if text then parts[#parts + 1] = text end
    end
    if #parts > 0 then return table.concat(parts, " · ") end
    local best, most = nil, 0
    for _, prof in ipairs(ZONE_PROFS) do
        local n = 0
        for _, t in ipairs(Gather.ZoneTargets(zone, prof)) do n = n + t.spawns end
        if n > most then best, most = prof, n end
    end
    return best and GatherList.RangeText(zone, best) or nil
end

-- The menu's continents: { { name, zones = { { zone, name, hint } } } }, in menu order.
function GatherList.ZoneChoices()
    local RM = CP.RouteMap
    local skills = Gather.Skills()
    local byContinent, list = {}, {}
    for zone in pairs(CP.GatherData.zones) do
        local info = not Gather.IsInstance(zone) and C_Map.GetMapInfo(zone)
        local continent = info and info.mapType == ZONE_TYPE and RM.ContinentOf(zone)
        if continent then
            local c = byContinent[continent]
            if not c then
                local cinfo = C_Map.GetMapInfo(continent)
                c = { id = continent, name = cinfo and cinfo.name or tostring(continent), zones = {} }
                byContinent[continent], list[#list + 1] = c, c
            end
            c.zones[#c.zones + 1] = { zone = zone, name = info.name, hint = GatherList.ZoneHint(zone, skills) }
        end
    end
    local here = Gather.PlayerZone()
    local home = here and RM.ContinentOf(here)
    table.sort(list, function(a, b)
        if (a.id == home) ~= (b.id == home) then return a.id == home end
        return a.name < b.name
    end)
    for _, c in ipairs(list) do
        table.sort(c.zones, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.zone < b.zone
        end)
    end
    return list
end

-- A zone's line in the menu: its name, then its hint in the muted ink. Daylight UI's menu
-- has no right-hand column, so the hint follows the name.
function GatherList.ZoneLabel(z)
    if not z.hint then return z.name end
    return ("%s  %s"):format(z.name, dim(z.hint))
end

-- The zone menu's entries, added to `root` (a game menu description or `recorder`'s).
-- Where I am is data false: a nil would not key a radio in the menu's own tables.
local function zoneGenerate(_, root)
    if not menuReady(root) then return end
    local function isPick(zone) return (GatherList.PickedZone() or false) == zone end
    local function pick(zone) GatherList.SetZone(zone or nil) end
    root[MENU.radio](root, GatherList.ZONE_HERE, isPick, pick, false)
    for _, c in ipairs(GatherList.ZoneChoices()) do
        root[MENU.title](root, c.name)
        for _, z in ipairs(c.zones) do
            root[MENU.radio](root, GatherList.ZoneLabel(z), isPick, pick, z.zone)
        end
    end
end
GatherList.ZoneGenerate = zoneGenerate

-- The zone name's menu: Daylight UI's own while it is loaded, else the game's context menu.
function GatherList.ZoneMenu(owner)
    local API = S.Daylight()
    if API and type(API.Menu) == "function" then return openNative(API, owner, zoneGenerate) end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    GatherList.nativeMenu = nil
    return MenuUtil.CreateContextMenu(owner, zoneGenerate)
end

-- Blizzard_Menu's calls that give an open menu a fresh description, as its dropdown buttons
-- do when their menu changes while open (DropdownButtonMixin:GenerateMenu). Called by name:
-- Blizzard UI code the API database doesn't index.
local REBUILD = { root = "CreateRootMenuDescription", populate = "PopulateDescription",
    mixin = "GetDefaultContextMenuMixin", set = "SetMenuDescription" }

local function menuOpen()
    local menu = GatherList.menu
    return menu ~= nil and type(menu.IsShown) == "function" and menu:IsShown() and menu or nil
end

-- A mode pick adds or drops the ticks, and Blizzard's Refresh response only re-reads marks.
-- So the open menu gets its entries again in place, its spot unchanged. Without the
-- rebuild calls it closes and opens again at the same top-left.
function GatherList.RebuildMenu()
    local menu, owner = menuOpen(), GatherList.menuOwner
    if not (menu and owner) then return false end
    local mu, m, mv = MenuUtil, _G.Menu, _G.MenuVariants
    if type(menu[REBUILD.set]) == "function" and mu and type(mu[REBUILD.root]) == "function"
        and m and type(m[REBUILD.populate]) == "function" then
        local mixin = owner.menuMixin or (mv and type(mv[REBUILD.mixin]) == "function" and mv[REBUILD.mixin]())
        local root = mu[REBUILD.root](mixin)
        m[REBUILD.populate](generate, owner, root)
        menu[REBUILD.set](menu, root)
        return true
    end
    local left, top = menu:GetLeft(), menu:GetTop()
    local again = GatherList.RouteMenu(owner)
    if again and left and top then
        again:ClearAllPoints()
        again:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    return true
end

-- The rebuild waits a frame, so the pick finishes on the entries it was made from.
function GatherList.RebuildSoon()
    C_Timer.After(0, function() GatherList.RebuildMenu() end)
end

-- The chat box the guide window starts beside: Daylight UI's, else the game's first
-- chat frame (frame names, not game APIs).
local CHAT_FRAMES = { "DaylightUIChatBox", "ChatFrame1" }
function GatherList.ChatAnchor()
    for _, name in ipairs(CHAT_FRAMES) do
        local chat = _G[name]
        if chat and chat.GetRight and chat:GetRight() then return chat end
    end
end

-- The mover's default: top-left at the chat box's top-right.
function GatherList.DefaultPoint()
    local chat = GatherList.ChatAnchor()
    if chat then return { "TOPLEFT", chat, "TOPRIGHT", 8, 0 } end
    return { "TOPRIGHT", UIParent, "TOPRIGHT", -220, -220 }
end

-- Fading -------------------------------------------------------------------------

-- Sitting by a campfire (Welcoming Campfire's auras): out of a fight the guide window
-- eases out but stays there, so the mouse brings it back.
local SITTING = { 1229739, 1289723 }
local sitting = false
local function hushed() return sitting and not inCombat end

-- The guide window while it shows, else nil.
local function free()
    local w = CP.Panel.frame
    if CP.Window and w:IsShown() then return w end
end

-- Daylight UI's fade engine while it fades the guide window, else nil. Its Fade.Hush eases
-- the window out by the fire and brings it back on mouseover or in a fight, so ProfLost
-- never writes that window's alpha itself.
GatherList.HUSH = "ProfLost"
local function engine()
    if not (CP.Window and CP.Window.managed.fade) then return nil end
    local addon = rawget(_G, "DaylightUI")
    local F = type(addon) == "table" and addon.Fade
    if type(F) == "table" and type(F.Hush) == "function" and type(F.Unhush) == "function" then return F end
end

-- The window ProfLost's own hush fades: the free window, unless Daylight UI fades it.
local function faded()
    if CP.Window and CP.Window.managed.fade then return nil end
    return free()
end

-- Daylight UI's hush on the guide window's fade area, on or off.
local hushing = false
local function engineHush(on)
    local F = engine()
    if not F then
        hushing = false
        return
    end
    if on == hushing then return end
    hushing = on
    if on then
        pcall(F.Hush, GatherList.HUSH, { CP.Look.FADE_KEY })
    else
        pcall(F.Unhush, GatherList.HUSH)
    end
end

-- Alpha steps toward the target each frame.
local fadeTarget = 1
local fader = CreateFrame("Frame")

local function fadeStep(self, elapsed)
    local w = faded()
    if not w then return self:SetScript("OnUpdate", nil) end
    local a = w:GetAlpha()
    local step = elapsed / FADE
    a = fadeTarget > a and math.min(fadeTarget, a + step) or math.max(fadeTarget, a - step)
    w:SetAlpha(a)
    if a == fadeTarget then self:SetScript("OnUpdate", nil) end
end

local function fadeTo(to)
    if not faded() then return end
    fadeTarget = to
    fader:SetScript("OnUpdate", fadeStep)
end

-- Rows ---------------------------------------------------------------------------

local rows = {}

local function itemTip(self)
    local line = self.line
    if line and line.kind == "cont" then line = line.of end
    local itemID = line and (line.kind == "item" and line.row.itemID
        or line.kind == "pattern" and line.itemID)
    if not itemID then
        if not (line and line.tip and line.tip[1]) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(line.tip[1], 1, 1, 1, 1, true)
        for i = 2, #line.tip do GameTooltip:AddLine(line.tip[i], 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink("item:" .. itemID)
    -- A cloth row adds where to farm it under the item.
    for _, text in ipairs(line.kind == "item" and line.tip or {}) do GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
end

-- The line a row belongs to: a wrapped line's first, a grind spot's first.
local function rootOf(line)
    while line do
        local up = line.kind == "cont" and line.of or line.spotOf
        if not up then return line end
        line = up
    end
end

-- Every row of the hovered row's line lights with it.
local function rowEnter(self)
    itemTip(self)
    local root = rootOf(self.line)
    for _, r in ipairs(rows) do
        if r ~= self and r:IsShown() and rootOf(r.line) == root then r:LockHighlight() end
    end
end

local function rowLeave()
    GameTooltip_Hide()
    for _, r in ipairs(rows) do r:UnlockHighlight() end
end

-- Where the folded profession sections are saved: one set per mode, since a Farm section
-- holds grind spots and a guide section holds what the guides need. The patterns
-- section keeps its own flag.
function GatherList.FoldKey()
    return Gather.RouteFarming() and "farmClosed" or "gatherClosed"
end

local function rowClick(self)
    local line = self.line
    if line and line.kind == "cont" then line = line.of end
    if not line then return end
    if line.click then return line.click() end
    if line.kind == "section" and line.key == "patterns" then
        GatherList.patternsOpen = not GatherList.patternsOpen
        -- Opening reads the count away; folding brings the count back while a pattern is
        -- unbought, so pressing the row twice leaves the badge as it was.
        local now = CP.VendorWatch and CP.VendorWatch.current
        if GatherList.patternsOpen then
            GatherList.unseenWas, GatherList.unseen = GatherList.unseen, 0
        else
            GatherList.unseen = (now and #now.found > 0) and GatherList.unseenWas or 0
            GatherList.unseenWas = 0
        end
    elseif line.kind == "section" then
        local key = GatherList.FoldKey()
        CP.db[key] = CP.db[key] or {}
        CP.db[key][line.key] = not CP.db[key][line.key] or nil
    elseif line.kind == "item" then
        open[line.row.itemID] = not open[line.row.itemID] or nil
    else
        return
    end
    GatherList.Refresh()
end

local function makeRow(i)
    local r = CreateFrame("Button", nil, f)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", EDGE, -(headH() + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", -EDGE, -(headH() + (i - 1) * ROW_H))
    S.Interactive(r)
    r.pulse = r:CreateTexture(nil, "BACKGROUND", nil, 2)
    r.pulse:SetPoint("TOPLEFT", 2, -1)          -- inside the frame's border
    r.pulse:SetPoint("BOTTOMRIGHT", -2, 1)
    r.pulse:SetColorTexture(1, 1, 1, 1)
    r.pulse:Hide()
    r.badge = S.Column(S.Text(r, "small", S.color.bad))
    r.badge:SetPoint("LEFT", 2, 0)
    r.toggle = S.Toggle(r, 8)
    r.rank = S.Column(S.Text(r, "small", S.color.accent))
    r.rank:SetPoint("LEFT", 14, 0)
    r.arrow = r:CreateTexture(nil, "ARTWORK")
    r.arrow:SetTexture(MEDIA .. "SideArrow")
    r.arrow:SetSize(12, 12)
    r.arrow:SetVertexColor(unpack(S.color.muted))
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.check = S.Check(r, 14)
    r.check:SetPoint("RIGHT", -4, 0)
    r.pin = S.PinButton(r, function(self)
        local line = self:GetParent().line
        if line and line.pin then line.pin() end
    end)
    r.pin:SetPoint("RIGHT", -2, 0)
    r.info = S.Column(S.Text(r, "small", S.color.muted))
    r.info:SetJustifyH("RIGHT")
    r.count = S.Column(S.Text(r, "small", S.color.muted))
    r.name = S.Text(r, "body")
    r.name:SetWordWrap(false)
    r.name:SetMaxLines(1)
    r:SetScript("OnClick", rowClick)
    r:SetScript("OnEnter", rowEnter)
    r:SetScript("OnLeave", rowLeave)
    rows[i] = r
    return r
end

-- A folding header's look: the chevron `x` px right of `after` (else the row's left edge),
-- then its name in the label ink. Sections and their Skill-ups and For your guides headings
-- both draw through it.
local SUB_TOGGLE_X = 16   -- a heading's chevron, under its section's name
local COUNT_GAP = 6       -- between a folded heading's name and its count

local function foldHead(r, line, after, x)
    r.toggle:SetOpen(not line.closed)
    if after then
        r.toggle:SetPoint("LEFT", after, "RIGHT", x, 0)
    else
        r.toggle:SetPoint("LEFT", x, 0)
    end
    r.toggle:Show()
    r.name:SetPoint("LEFT", r.toggle, "RIGHT", 6, 0)
    r.name:SetTextColor(unpack(S.color.label))
    r.name:SetText(line.text)
end

local function setLine(r, line)
    r.line = line
    r:UnlockHighlight()
    r.badge:SetText("")
    -- A new patterns header breathes in the accent through Style.Pulse (API.Fade).
    if line.pulse then
        local a = S.color.accent
        r.pulse:SetVertexColor(a[1], a[2], a[3], PULSE_ALPHA)
        r.pulse:Show()
        S.Pulse(r.pulse, true)
    else
        S.Pulse(r.pulse, false)
        r.pulse:Hide()
    end
    -- A pattern the player can learn now wears the guide's green pulse (Style.OwnedRow).
    S.OwnedRow(r, false)
    r.toggle:Hide()
    r.arrow:Hide()
    r.icon:Hide()
    r.check:Hide()
    r.rank:SetText(line.rank or "")
    r.pin:SetShown(line.pin ~= nil)
    r.name:ClearAllPoints()
    r.info:ClearAllPoints()
    if line.pin then
        r.info:SetPoint("RIGHT", r.pin, "LEFT", -4, 0)
    else
        r.info:SetPoint("RIGHT", -INFO_EDGE, 0)
    end
    r.name:SetPoint("RIGHT", r.info, "LEFT", -6, 0)
    r.name:SetTextColor(unpack(S.color.text))
    r.info:SetTextColor(unpack(line.infoColor or S.color.muted))
    r.info:SetText(line.wrapped and "" or line.info or "")

    r.count:SetText("")

    if line.kind == "section" then
        if line.badge then
            r.badge:SetText(line.badge)
            foldHead(r, line, r.badge, 4)
        else
            foldHead(r, line, nil, 2)
        end
    elseif line.subhead and line.click then
        foldHead(r, line, nil, SUB_TOGGLE_X)
        if line.closed and line.showCount then
            r.count:ClearAllPoints()
            r.count:SetPoint("LEFT", r.name, "LEFT", GatherList.Measure(line.text, "body") + COUNT_GAP, 0)
            r.count:SetTextColor(unpack(S.color.muted))
            r.count:SetText(line.count)
        end
    elseif line.kind == "item" then
        r.toggle:SetOpen(line.open)
        r.toggle:SetPoint("LEFT", 14, 0)
        r.toggle:Show()
        -- The icon by id, else the instant item lookup's; a later item-info event redraws.
        local id = line.row.itemID
        r.icon:SetTexture(C_Item.GetItemIconByID(id) or select(5, C_Item.GetItemInfoInstant(id)) or 134400)
        r.icon:SetPoint("LEFT", r.toggle, "RIGHT", 4, 0)
        r.icon:Show()
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetText(line.text or line.row.name)
        if line.row.done then
            r.check:Show()
            r.info:SetPoint("RIGHT", r.check, "LEFT", -2, 0)
            r.info:SetTextColor(unpack(S.color.good))
        elseif not line.row.soonDone then
            r.info:SetTextColor(unpack(S.color.warn))
        end
    elseif line.kind == "plan" then
        if line.fold ~= nil then
            r.toggle:SetOpen(line.fold)
            r.toggle:SetPoint("LEFT", 34, 0)
            r.toggle:Show()
        end
        r.name:SetPoint("LEFT", line.indent or 18, 0)
        r.name:SetText(line.text)
        r.name:SetTextColor(unpack(line.textColor or (line.muted and S.color.muted or S.color.accent)))
    elseif line.kind == "feed" then
        -- No game or Daylight UI font draws "└" and only one draws "↳": ProfLost's own
        -- SideArrow art, the guide's "or" arrow, stands for it.
        r.arrow:SetPoint("LEFT", FEED_ARROW_X, 0)
        r.arrow:Show()
        r.name:SetPoint("LEFT", r.arrow, "RIGHT", 4, 0)
        r.name:SetText(line.text)
        r.name:SetTextColor(unpack(line.textColor or S.color.muted))
    elseif line.kind == "cont" then
        r.name:SetPoint("LEFT", line.indent, 0)
        r.name:SetText(line.text)
        r.name:SetTextColor(unpack(line.color or S.color.muted))
    elseif line.kind == "vendor" then
        r.name:SetPoint("LEFT", 18, 0)
        r.name:SetText(line.text)
        r.name:SetTextColor(unpack(S.color.label))
    elseif line.kind == "pattern" then
        r.name:SetPoint("LEFT", 30, 0)
        r.name:SetText(line.text)
        r.name:SetTextColor(unpack(line.limited and S.color.accent or S.color.text))
        S.OwnedRow(r, line.learnNow)
    elseif line.kind == "label" then
        r.toggle:SetOpen(line.open)
        r.toggle:SetPoint("LEFT", 34, 0)
        r.toggle:Show()
        r.name:SetPoint("LEFT", r.toggle, "RIGHT", 4, 0)
        r.name:SetText(line.text)
        r.name:SetTextColor(unpack(S.color.label))
    elseif line.fold ~= nil then
        r.toggle:SetOpen(line.fold)
        r.toggle:SetPoint("LEFT", 34, 0)
        r.toggle:Show()
        r.name:SetPoint("LEFT", r.toggle, "RIGHT", 6, 0)
        r.name:SetText(line.text)
        r.name:SetTextColor(unpack(S.color.title))
    else
        r.arrow:SetPoint("LEFT", 34, 0)
        r.arrow:Show()
        r.name:SetPoint("LEFT", r.arrow, "RIGHT", 4, 0)
        r.name:SetText(line.text)
        r.name:SetTextColor(unpack(line.rank and S.color.title or S.color.text))
    end
end

-- Content ------------------------------------------------------------------------

local function pct(chance)
    if chance >= 10 then return ("%d%%"):format(math.floor(chance + 0.5)) end
    return ("%.1f%%"):format(chance)
end

-- A source whose chances come from its level, not the data or the player's skins.
GatherList.ESTIMATED = "estimated"
GatherList.ESTIMATED_TIP = "Chances estimated from classic beasts of its level"

-- Sub-row text: the right-hand info and the tooltip lines for one source.
function GatherList.SourceText(src)
    local parts, tip = {}, {}
    if src.kind == "mob" then
        parts[#parts + 1] = src.minLevel == src.maxLevel and ("lvl %d"):format(src.minLevel)
            or ("lvl %d-%d"):format(src.minLevel, src.maxLevel)
        if src.skill and src.skillMax and src.skillMax > src.skill then
            tip[#tip + 1] = ("Needs skill %d to %d to loot, by the corpse's level"):format(src.skill, src.skillMax)
        elseif src.skill and src.skill > 1 then
            tip[#tip + 1] = ("Needs skill %d to loot"):format(src.skill)
        end
    elseif src.kind == "node" then
        parts[#parts + 1] = ("skill %d"):format(src.skill)
    end
    parts[#parts + 1] = pct(src.chance)
    if src.how == "estimated" then
        parts[#parts + 1] = GatherList.ESTIMATED
        tip[#tip + 1] = GatherList.ESTIMATED_TIP
    elseif src.how == "recorded" then
        tip[#tip + 1] = ("From %d of your skins"):format(src.skins or 0)
    end
    if src.avg and src.avg >= 1.5 then tip[#tip + 1] = ("About %.1f each time it drops"):format(src.avg) end
    if src.land and src.land < 100 then
        parts[#parts + 1] = ("lands %d%%"):format(src.land)
        tip[#tip + 1] = "Fish get away on some bites until your Fishing is higher."
    end
    tip[#tip + 1] = ("%s chance per %s"):format(pct(src.chance),
        src.kind == "mob" and "corpse" or src.kind == "node" and "node" or "catch")
    return table.concat(parts, " · "), tip
end

-- A node's spawn points it shares with other kinds in `zone`, as tooltip lines:
-- "Some spots spawn one of:", then "Tin Vein 80% · Silver Vein 20%" for each mix.
GatherList.MIX_LINES = 3
function GatherList.AddMixTip(tip, zone, src)
    if src.kind ~= "node" or not src.entry then return end
    local lines = Gather.MixLines(zone, src.entry)
    if #lines == 0 then return end
    tip[#tip + 1] = "Some spots here spawn one of:"
    for i = 1, math.min(#lines, GatherList.MIX_LINES) do tip[#tip + 1] = lines[i].text end
end

-- The player's level and { x, y } on `zone`'s map (nil inside an instance or elsewhere),
-- for ranking grind spots by kill speed and distance.

local function grindFrom(zone)
    local level = Gather.PlayerLevel()
    if Gather.IsInstance(zone) or GatherList.away and zone == GatherList.zone then return level, nil end
    local pos = C_Map.GetPlayerMapPosition(zone, "player")
    local x, y
    if pos then x, y = pos:GetXY() end
    return level, (x and y) and { x = x, y = y } or nil
end
GatherList.GrindFrom = grindFrom

-- True when the player can gather source `src` now: its profession known at `skills`, at its
-- skill or above. A source with no profession passes.
local function canGather(src, skills)
    if not src.prof then return true end
    local rank = skills[src.prof]
    return rank ~= nil and rank >= (src.skill or 0)
end

-- A plain map pin at a point on a zone map, for a place the player can't gather yet: no
-- Mapzeroth route and no tracked arrow. Only runs from a player's click.
function GatherList.MarkOnMap(zone, x, y, name)
    if not C_Map.CanSetUserWaypointOnMap(zone) then return end
    C_Map.SetUserWaypoint({ uiMapID = zone, position = CreateVector2D(x, y) })
    C_SuperTrack.SetSuperTrackedUserWaypoint(false)
    local info = C_Map.GetMapInfo(zone)
    CP:Print(("Marked on the map: %s, %s (%.1f, %.1f)."):format(name, info and info.name or "?", x * 100, y * 100))
end

-- A row's pin: a waypoint, or only a mark on the map when `mark` is set or the point lies in
-- a picked zone the player is not in yet (no arrow until they are there).
local function placeAt(zone, x, y, name, mark)
    local only = mark or GatherList.away and zone == GatherList.zone
    local place = only and GatherList.MarkOnMap or CP.Waypoint.PlaceOnMap
    place(zone, x, y, name)
end
GatherList.PlaceAt = placeAt

-- Waypoint to the best grind spot for a creature-sourced item, or nil. `mark` only marks the
-- spot on the map, for creatures the player can't skin yet.
local function toGrind(row, mark)
    local mob = false
    for _, src in ipairs(row.sources) do mob = mob or src.kind == "mob" end
    if not mob or row.done then return nil end
    return function()
        local zone = GatherList.zone
        if not zone then return end
        local zw, zh = CP.Gather.ZoneSize(zone)
        if not zw then return end
        local z = { w = zw, h = zh }
        local level, from = grindFrom(zone)
        local spot = CP.Route.GrindSpots(CP.Route.Points(zone, { row }, nil, "mob", level), z.w, z.h, nil, 1, from,
            zone)[1]
        if spot then
            placeAt(zone, spot.x, spot.y, "Grind spot: " .. spot.name, mark)
        else
            CP:Print("No grind spot for that here.")
        end
    end
end

-- A pin to `spot`. `mark` only marks it on the map, for a source the player can't gather now.
local function spotPin(zone, spot, label, mark)
    return function() placeAt(zone, spot.x, spot.y, label, mark) end
end

-- `row` with only the creature and node sources the player can gather now at `skills`, or
-- nil when none is left.
function GatherList.Reachable(row, skills)
    local kept = {}
    for _, src in ipairs(row.sources or {}) do
        if (src.kind == "mob" or src.kind == "node") and canGather(src, skills) then kept[#kept + 1] = src end
    end
    return #kept > 0 and setmetatable({ sources = kept }, { __index = row }) or nil
end

-- Spawn points of a creature or node in the zone, and the yield per clear.
local function perClear(zone, src)
    if src.kind ~= "mob" and src.kind ~= "node" then return nil end
    local spawns = 0
    for _, c in ipairs(Gather.Clusters(zone, src.kind == "mob" and "mobs" or "nodes", src.entry)) do
        spawns = spawns + c[3]
    end
    return spawns * src.chance / 100
end

-- A grind spot's creatures, biggest share first, and their level span.
local function spotCreatures(spot)
    local list, low, high = {}, nil, nil
    for name, v in pairs(spot.parts or {}) do list[#list + 1] = { name, v } end
    table.sort(list, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    for _, e in ipairs(list) do
        local a = spot.about and spot.about[e[1]]
        if a and a.minLevel then
            low, high = math.min(low or a.minLevel, a.minLevel), math.max(high or a.maxLevel, a.maxLevel)
        end
    end
    return list, low, high
end

local function span(low, high)
    if not low then return nil end
    return low == high and tostring(low) or ("%d-%d"):format(low, high)
end

-- "Level 21-24": the levels of every creature at a grind spot, lowest to highest.
function GatherList.SpotLevels(spot)
    local _, low, high = spotCreatures(spot)
    local lv = span(low, high)
    return lv and "Level " .. lv or "Grind spot"
end

-- An item's icon in a line of text, then `text`.
local function iconText(item, text)
    return ("|T%s:0|t %s"):format(tostring(C_Item.GetItemIconByID(item) or 134400), text)
end
GatherList.IconText = iconText

-- How often a skin at a grind spot gives each material: its icon and the chance averaged
-- over the spot's creatures (one that never gives it counts as 0), lowest item id
-- first. Nil when the spot gives no item.
function GatherList.SpotChances(spot)
    local list = spotCreatures(spot)
    local sum, items = {}, {}
    for _, e in ipairs(list) do
        local about = spot.about and spot.about[e[1]]
        for item, chance in pairs(about and about.drops or {}) do
            if item > 0 then
                if not sum[item] then items[#items + 1] = item end
                sum[item] = (sum[item] or 0) + chance
            end
        end
    end
    table.sort(items)
    for i, item in ipairs(items) do
        items[i] = iconText(item, ("%d%%"):format(math.floor(sum[item] / #list + 0.5)))
    end
    return #items > 0 and table.concat(items, "  ") or nil
end

-- Grind spots open on a click to list their creatures. Kept for the session.
local spotOpen = {}

local function spotKey(zone, spot)
    return ("%s:%.4f,%.4f"):format(tostring(zone), spot.x, spot.y)
end

function GatherList.SpotOpen(zone, spot)
    return spotOpen[spotKey(zone, spot)] == true
end

-- The lines under a grind spot's `head` while it is open: each creature with its
-- levels. With `chances`, a first line shows the spot's drop chances, always on a line of
-- its own under the head. A click on any of them opens or closes the spot, as a
-- click on `head` does.
local SPOT_INDENT = 52
local CHANCE_INDENT = 56

function GatherList.SpotDetail(zone, spot, head, chances)
    local key = spotKey(zone, spot)
    local function toggle()
        spotOpen[key] = not spotOpen[key] or nil
        GatherList.Refresh()
    end
    head.fold, head.click = spotOpen[key] == true, toggle
    local out = {}
    local gives = chances and GatherList.SpotChances(spot)
    if gives then
        out[#out + 1] = { kind = "plan", muted = true, indent = CHANCE_INDENT, text = gives, spotOf = head,
            click = toggle }
    end
    if not head.fold then return out end
    for _, e in ipairs((spotCreatures(spot))) do
        local about = spot.about and spot.about[e[1]] or {}
        local info = span(about.minLevel, about.maxLevel)
        if about.how == "estimated" then info = (info and info .. " · " or "") .. GatherList.ESTIMATED end
        out[#out + 1] = { kind = "plan", muted = true, indent = SPOT_INDENT, spotOf = head, text = e[1],
            info = info, creature = e[1], click = toggle }
    end
    return out
end

-- The map's grind spots for the player's zone, by profession: { [prof] = { line } },
-- and a string that changes when they do. Each spot's first line carries its rank among
-- its profession's spots shown here (best is "#1"), with the spot's levels and drop
-- chances; SpotDetail's lines follow it.
function GatherList.SpotLines(zone)
    local spots, at = CP.RouteMap.Spots()
    local out, sig = {}, {}
    if not zone or at ~= zone then return out, "" end
    local shown = {}
    for i, spot in ipairs(spots) do
        local rank = spot.rank or i
        local prof = spot.prof or Gather.SKINNING
        out[prof] = out[prof] or {}
        shown[prof] = (shown[prof] or 0) + 1
        local head = { kind = "source", rank = ("#%d"):format(shown[prof]), src = { name = spot.name },
            text = GatherList.SpotLevels(spot), spot = spot,
            pin = spotPin(zone, spot, ("Grind spot %d: %s"):format(shown[prof], CP.RouteMap.SpotFor(spot))) }
        table.insert(out[prof], head)
        for _, l in ipairs(GatherList.SpotDetail(zone, spot, head, true)) do table.insert(out[prof], l) end
        sig[#sig + 1] = ("%d:%.4f,%.4f"):format(rank, spot.x, spot.y)
    end
    return out, table.concat(sig, ";")
end

-- A skinning source under its material's Gather.SkinFloor forms no grind spot, so the list
-- leaves it out, and a material with no other source here is not listed at all.
local function rare(src, floor)
    return src.kind == "mob" and src.prof == Gather.SKINNING and (src.chance or 0) < floor
end

function GatherList.Listed(row)
    local floor = Gather.SkinFloor(row.itemID)
    for _, src in ipairs(row.sources or {}) do
        if not rare(src, floor) then return true end
    end
    return false
end

-- The lines under an opened item: its sources, ranked by what one clear of each yields
-- here (spawns x drop chance), without the rare skinning ones. The grind spots are the
-- map's, listed once per profession (SpotLines).
function GatherList.SourceLines(row, zone)
    local out = {}
    local zw, zh
    if zone then zw, zh = CP.Gather.ZoneSize(zone) end
    local z = zw and { w = zw, h = zh }
    local ranked, skills = {}, Gather.Skills()
    local floor = Gather.SkinFloor(row.itemID)
    for _, src in ipairs(row.sources) do
        if not rare(src, floor) then ranked[#ranked + 1] = { src = src, yield = z and perClear(zone, src) or nil } end
    end
    table.sort(ranked, function(a, b)
        local ya, yb = a.yield or -1, b.yield or -1
        if ya ~= yb then return ya > yb end
        return a.src.chance > b.src.chance
    end)
    for _, r in ipairs(ranked) do
        local src = r.src
        local info, tip = GatherList.SourceText(src)
        table.insert(tip, 1, src.name)
        if zone then GatherList.AddMixTip(tip, zone, src) end
        local line = { kind = "source", src = src, text = src.name, info = info, tip = tip, yield = r.yield }
        if z and (src.kind == "mob" or src.kind == "node") then
            local one = { itemID = row.itemID, need = 1, sources = { src } }
            local level, from = grindFrom(zone)
            local best = CP.Route.GrindSpots(CP.Route.Points(zone, { one }, nil, src.kind, level), z.w, z.h, nil, 1,
                from, zone)[1]
            if best then
                line.pin = spotPin(zone, best, src.name, not canGather(src, skills))
            end
        end
        out[#out + 1] = line
    end
    return out
end

local function itemInfo(row)
    if row.need then return ("%d / %d"):format(row.have, row.need) end
    return row.have > 0 and tostring(row.have) or ""
end

local function nameOf(id)
    return CP.ItemName(id) or ("item " .. id)
end

local function have(id) return CP.Purchases.Have(id) end

-- The checklist rows the Farm menu's ticks leave (Gather.RouteSkipped by node name,
-- Gather.SkinSkipped by item). An unticked leather's Skinning row goes, as does a
-- Herbalism or Mining row whose every node is unticked; other rows lose the unticked
-- sources, so their grind spots and pins skip them too. Both readers skip nothing in
-- Follow the guide, so there every row stays. Changed rows are copies, so
-- Gather.ForZone's cached rows stay whole.
function GatherList.Ticked(items)
    local out = {}
    for _, r in ipairs(items) do
        local kept, cut, nodes, nodesLeft = {}, false, 0, 0
        for _, src in ipairs(r.sources or {}) do
            local skin = src.kind == "mob" and src.prof == Gather.SKINNING
            local node = src.kind == "node"
            if node then nodes = nodes + 1 end
            if (node and Gather.RouteSkipped(src.name)) or (skin and Gather.SkinSkipped(r.itemID)) then
                cut = true
            else
                kept[#kept + 1] = src
                if node then nodesLeft = nodesLeft + 1 end
            end
        end
        local gone = (r.prof == Gather.SKINNING and Gather.SkinSkipped(r.itemID))
            or ((r.prof == Gather.HERBALISM or r.prof == Gather.MINING) and nodes > 0 and nodesLeft == 0)
            or #kept == 0
        if not cut then
            out[#out + 1] = r
        elseif not gone then
            out[#out + 1] = setmetatable({ sources = kept }, { __index = r })
        end
    end
    return out
end

-- "5 spawns" or "1 node": `n` rounded, with `word` pluralised.
local function countWord(n, word)
    n = math.floor(n + 0.5)
    return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

-- Farm's herbs and ore: one line for each node kind the loop visits in `zone`, lowest
-- skill first, with how many stand there.
function GatherList.NodeLines(zone, skills)
    local out = {}
    for _, r in ipairs(zone and Gather.SkillRows(zone, skills) or {}) do
        local src = r.sources[1]
        local tip = { src.name, ("Needs %s %d"):format(PROF_NAME[src.prof] or "skill", src.skill) }
        GatherList.AddMixTip(tip, zone, src)
        out[#out + 1] = { kind = "source", prof = src.prof, src = src, text = src.name, skill = src.skill,
            info = ("skill %d · %s"):format(src.skill, countWord(Gather.Spawns(zone, "nodes", src.entry), "node")),
            tip = tip }
    end
    table.sort(out, function(a, b)
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.text < b.text
    end)
    return out
end

-- Cloth ------------------------------------------------------------------------------

-- The Cloth section: one row per cloth the guides need that the player's zone gives at
-- their level (Gather.Cloth).
GatherList.CLOTH_KEY = "cloth"
GatherList.CLOTH_TITLE = "Cloth"

-- The cloth the section lists, as Gather.ClothRows' `items`, and the needs behind its counts:
-- items, needs, soon. Follow the guide lists what the guides need (one picked crafting
-- profession: its own guide's). Farm reads no need: every cloth with All, the cloth a picked
-- crafting profession's guide uses. A picked gathering profession lists none.
function GatherList.ClothWanted()
    local pick, farming = GatherList.PanelProf(), Gather.RouteFarming()
    if pick and not (CP.Guides and CP.Guides[pick]) then return {}, {}, {} end
    if farming then
        if not pick then return nil, {}, {} end
        local uses = {}
        for _, item in ipairs(Gather.CLOTH) do
            if CP.Guides[pick].items and CP.Guides[pick].items[item] then uses[item] = true end
        end
        return uses, {}, {}
    end
    local needs, soon
    if pick then
        local db = CP.charDB or {}
        needs = db.gatherNeeds and db.gatherNeeds[pick] or {}
        soon = db.gatherSoon and db.gatherSoon[pick] or {}
    else
        needs, soon = Gather.Needs()
    end
    local items = {}
    for _, item in ipairs(Gather.CLOTH) do
        if needs[item] and have(item) < needs[item] then items[item] = needs[item] end
    end
    return items, needs, soon
end

-- "humanoids 36-47": what drops a cloth here and their levels.
function GatherList.ClothWho(c)
    local who = Gather.CLOTH_KINDS[c.kind] or "creatures"
    return c.lo == c.hi and ("%s %d"):format(who, c.lo) or ("%s %d-%d"):format(who, c.lo, c.hi)
end

-- "#1 Bloodsail Warlock, level 40-45 (45, 61)": a cloth spot, its rank and where it is.
function GatherList.ClothSpotText(i, s)
    local lv = s.lo == s.hi and tostring(s.lo) or ("%d-%d"):format(s.lo, s.hi)
    return ("#%d %s, level %s (%d, %d)"):format(i, s.name, lv, math.floor(s.x * 100 + 0.5), math.floor(s.y * 100 + 0.5))
end

-- The tooltip lines under a cloth row's item: the pool, then its best spots.
function GatherList.ClothTip(c)
    local who = GatherList.ClothWho(c)
    local rate = c.perKill >= 1 and ("about %.1f a kill"):format(c.perKill)
        or ("about 1 in %d kills"):format(math.max(1, math.floor(1 / c.perKill + 0.5)))
    local tip = { ("%s%s drop it here: %s"):format(who:sub(1, 1):upper(), who:sub(2), rate), "Best spots:" }
    for i, s in ipairs(c.spots) do tip[#tip + 1] = GatherList.ClothSpotText(i, s) end
    return tip
end

-- The Cloth section's lines for `zone`: its header, then a row per cloth, each opening to
-- its best spots with a pin each. `first` gives the header the column note.
function GatherList.ClothLines(zone, first)
    local out = {}
    if not zone or Gather.IsInstance(zone) then return out end
    local items, needs, soon = GatherList.ClothWanted()
    if items and not next(items) then return out end
    local farming = Gather.RouteFarming()
    local list = Gather.ClothRows(zone, items, Gather.PlayerLevel(), UnitFactionGroup("player"))
    if #list == 0 then return out end
    local closed = (CP.db[GatherList.FoldKey()] or {})[GatherList.CLOTH_KEY]
    out[1] = { kind = "section", key = GatherList.CLOTH_KEY, closed = closed, text = GatherList.CLOTH_TITLE,
               info = first and not farming and "have / need" or nil }
    if closed then return out end
    for _, c in ipairs(list) do
        local item, name = c.item, nameOf(c.item)
        local row = { itemID = item, name = name, have = have(item), need = not farming and needs[item] or nil,
                      soon = not farming and soon[item] or nil, cloth = true }
        row.done = false
        row.soonDone = row.soon == nil or row.have >= row.soon
        local who = GatherList.ClothWho(c)
        local best = c.spots[1]
        out[#out + 1] = { kind = "item", row = row, open = open[item], cloth = c, tip = GatherList.ClothTip(c),
            info = row.need and ("%d / %d · %s"):format(row.have, row.need, who) or who,
            pin = best and spotPin(zone, best, ("%s: %s"):format(name, best.name)) }
        if open[item] then
            for i, s in ipairs(c.spots) do
                local lv = s.lo == s.hi and tostring(s.lo) or ("%d-%d"):format(s.lo, s.hi)
                out[#out + 1] = { kind = "source", rank = ("#%d"):format(i), src = { name = s.name }, text = s.name,
                    info = "lvl " .. lv, tip = { GatherList.ClothSpotText(i, s) },
                    pin = spotPin(zone, s, ("%s #%d: %s"):format(name, i, s.name)) }
            end
        end
    end
    return out
end

-- Crafting sections ----------------------------------------------------------------

-- A crafting profession picked on the panel gets a section of what its guide still needs that
-- this zone gives, while "Gather it yourself" is on and the route follows the guide. The zone
-- is read at each gathering profession's top rank, so a herb the player can't pick yet, or
-- has no Herbalism for, still lists; its row names the rank or the missing profession.
GatherList.CRAFT_GATHER = { Gather.HERBALISM, Gather.MINING, Gather.SKINNING }
GatherList.CRAFT_TOP_RANK = 300

-- The empty line for a picked crafting profession, by the gathering skill its unmet needs
-- take; CRAFT_EMPTY_MIXED when they take more than one.
GatherList.CRAFT_EMPTY = {
    [Gather.HERBALISM] = "No herbs %s needs grow here.",
    [Gather.MINING] = "No ore %s needs is mined here.",
    [Gather.SKINNING] = "No leather %s needs drops here.",
}
GatherList.CRAFT_EMPTY_MIXED = "Nothing %s needs to gather is here."
GatherList.CRAFT_COLLECT_OFF = "Gather it yourself is off, so %s buys what it needs."

function GatherList.LacksText(prof)
    return ("You don't have %s. Buy it, or gather it on another character."):format(prof)
end

function GatherList.ShortText(prof, rank)
    return ("Needs %s %d to gather here."):format(prof, rank)
end

-- The picked profession when it is a guided crafting one, else nil.
function GatherList.CraftPick()
    local pick = GatherList.PanelProf()
    if pick and not PROF_ORDER[pick] and CP.Guides and CP.Guides[pick] then return pick end
    return nil
end

-- Whether a picked crafting profession gets its section now.
local function craftShown()
    return CP.db.collect and not Gather.RouteFarming()
end

-- The zone's rows at the top gathering ranks, kept for one zone and rank set until the
-- spawn data changes.
local craftZone = {}
hooksecurefunc(Gather, "ResetClusters", function() craftZone.key = nil end)

local function topRows(zone, skills)
    local parts = { zone }
    for _, id in ipairs(Gather.PROFS) do parts[#parts + 1] = skills[id] or 0 end
    local key = table.concat(parts, ":")
    if craftZone.key ~= key then
        craftZone.key, craftZone.list = key, Gather.ForZone(zone, skills, GatherList.OTHER_OPTS)
    end
    return craftZone.list
end

-- The lowest rank of `prof` that gathers anything of `row` here.
local function lowestSkill(row, prof)
    local low
    for _, src in ipairs(row.sources) do
        if src.prof == prof and src.skill then low = math.min(low or src.skill, src.skill) end
    end
    return low or 0
end

-- The rows for crafting profession `pick` in `zone`: each item its guide needs that the zone
-- gives, as Gather.Rows' rows. `lacks` names a gathering profession the player doesn't have;
-- `short` is the rank a row needs when the player's is lower.
function GatherList.CraftRows(zone, pick)
    local db = CP.charDB or {}
    local needs = db.gatherNeeds and db.gatherNeeds[pick] or {}
    local soon = db.gatherSoon and db.gatherSoon[pick] or {}
    if not zone or Gather.IsInstance(zone) or not next(needs) then return {} end
    local own, top = Gather.Skills(), {}
    for id, rank in pairs(own) do top[id] = rank end
    for _, id in ipairs(GatherList.CRAFT_GATHER) do top[id] = GatherList.CRAFT_TOP_RANK end
    local out = {}
    for _, r in ipairs(topRows(zone, top)) do
        local need = needs[r.itemID]
        if need and need > 0 and GatherList.Listed(r) then
            local row = setmetatable({ need = need, soon = soon[r.itemID], have = have(r.itemID) or 0,
                name = nameOf(r.itemID) }, { __index = r })
            row.done = row.have >= need
            row.soonDone = row.soon == nil or row.have >= row.soon
            if not own[r.prof] then
                row.lacks = PROF_NAME[r.prof]
            else
                local low = lowestSkill(r, r.prof)
                if own[r.prof] < low then row.short = low end
            end
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        if a.soonDone ~= b.soonDone then return not a.soonDone end
        if a.done ~= b.done then return not a.done end
        local sa, sb = a.need - a.have, b.need - b.have
        if sa ~= sb then return sa > sb end
        return a.name < b.name
    end)
    return out
end

-- Waypoint to the best spot for a row's best creature or node source the player can gather
-- now, or nil. A row the player can't gather yet only marks where it grows on the map.
local function toBest(row)
    if row.done then return nil end
    local reach = GatherList.Reachable(row, Gather.Skills())
    row = reach or row
    local kind
    for _, src in ipairs(row.sources) do
        if not kind and (src.kind == "mob" or src.kind == "node") then kind = src.kind end
    end
    if kind == "mob" then return toGrind(row, not reach) end
    if kind ~= "node" then return nil end
    return function()
        local zone = GatherList.zone
        if not zone then return end
        local zw, zh = CP.Gather.ZoneSize(zone)
        if not zw then return end
        local level, from = grindFrom(zone)
        local spot = CP.Route.GrindSpots(CP.Route.Points(zone, { row }, nil, "node", level), zw, zh, nil, 1, from,
            zone)[1]
        if not spot then return end
        placeAt(zone, spot.x, spot.y, row.name, not reach)
    end
end

-- The picked crafting profession's section for `zone`: its header, then a row per item.
-- `first` gives the header the column note.
function GatherList.CraftLines(zone, pick, first)
    local out = {}
    if not craftShown() then return out end
    local list = GatherList.CraftRows(zone, pick)
    if #list == 0 then return out end
    local closed = (CP.db[GatherList.FoldKey()] or {})[pick]
    local info = CP.Professions.SkillLine(pick)
    local name = ""
    for _, p in ipairs(GatherList.PanelProfs()) do
        if p.id == pick then name = p.name end
    end
    out[1] = { kind = "section", key = pick, closed = closed,
               text = ("%s %d"):format(name, info and info.rank or 0),
               info = first and "have / need" or nil }
    if closed then return out end
    for _, row in ipairs(list) do
        local note, tip = itemInfo(row), nil
        if row.lacks then
            note, tip = note .. " · no " .. row.lacks, { GatherList.LacksText(row.lacks) }
        elseif row.short then
            note, tip = ("%s · %s %d"):format(note, PROF_NAME[row.prof], row.short),
                { GatherList.ShortText(PROF_NAME[row.prof], row.short) }
        end
        out[#out + 1] = { kind = "item", row = row, open = open[row.itemID], info = note, tip = tip,
            pin = toBest(row) }
        if open[row.itemID] then
            for _, l in ipairs(GatherList.SourceLines(row, zone)) do out[#out + 1] = l end
        end
    end
    return out
end

-- The empty line's text for a picked crafting profession, or nil to use the general one.
function GatherList.CraftEmptyText(pick, name)
    if Gather.RouteFarming() then return nil end
    if not CP.db.collect then return GatherList.CRAFT_COLLECT_OFF:format(name) end
    local db = CP.charDB or {}
    local guide = CP.Guides[pick]
    local kinds, kind, count = {}, nil, 0
    for item, n in pairs(db.gatherNeeds and db.gatherNeeds[pick] or {}) do
        local line = n > 0 and have(item) < n and CP.Sourcing.GatherSkill(guide, item)
        if line and GatherList.CRAFT_EMPTY[line] and not kinds[line] then
            kinds[line], kind, count = true, line, count + 1
        end
    end
    if count == 0 then return nil end
    return (count == 1 and GatherList.CRAFT_EMPTY[kind] or GatherList.CRAFT_EMPTY_MIXED):format(name)
end

GatherList.SKILLUPS_HEAD = "Skill-ups"
GatherList.GUIDE_HEAD = "For your guides"

local GATHER_PROFS = { [Gather.SKINNING] = true, [Gather.MINING] = true, [Gather.HERBALISM] = true }

-- A small heading line inside a section, in the label ink the section headers use.
local function subHead(text, info)
    return { kind = "plan", subhead = true, text = text, info = info, textColor = S.color.label, indent = 30 }
end

-- Skill-ups and For your guides fold like their section. Folds are saved per character in
-- CP.charDB.gatherSubClosed, keyed "<profession>:<heading>"; open saves nothing.
GatherList.SUB_SKILLUPS, GatherList.SUB_GUIDE = "skillups", "guide"

local function subKey(prof, sub) return prof .. ":" .. sub end

function GatherList.SubClosed(prof, sub)
    local db = CP.charDB and CP.charDB.gatherSubClosed
    return db ~= nil and db[subKey(prof, sub)] == true
end

-- A folding heading over `hides` rows: a click folds or opens it, and folded it carries
-- their count (shown when it fits, Wrap).
local function foldSub(text, info, prof, sub, hides)
    local line = subHead(text, info)
    local key = subKey(prof, sub)
    line.closed, line.subKey = GatherList.SubClosed(prof, sub), key
    line.count = tostring(hides)
    line.click = function()
        if not CP.charDB then return end
        CP.charDB.gatherSubClosed = CP.charDB.gatherSubClosed or {}
        CP.charDB.gatherSubClosed[key] = not CP.charDB.gatherSubClosed[key] or nil
        GatherList.Refresh()
    end
    return line
end

-- Skill-ups ------------------------------------------------------------------------

GatherList.SKILLUP_LINES = 4   -- skill-up targets listed per gathering profession

-- What gives `prof` skill at `rank` in `zone`: { target, req, color } for each of the zone's
-- targets (Gather.ZoneTargets) whose skill-up chance at `rank` is above none. `color` is the
-- profession window's index (1 orange to 3 green). Orange first, then the highest need, then
-- the most spawns.
function GatherList.SkillUps(zone, prof, rank)
    local GG, out = CP.GatherGuide, {}
    for _, t in ipairs(zone and Gather.ZoneTargets(zone, prof) or {}) do
        local req = Gather.TargetReq(t, rank)
        if req and GG.Band(rank, req) > 0 then
            out[#out + 1] = { target = t, req = req, color = GG.Difficulty(rank, req) }
        end
    end
    table.sort(out, function(a, b)
        if a.color ~= b.color then return a.color < b.color end
        if a.req ~= b.req then return a.req > b.req end
        if a.target.spawns ~= b.target.spawns then return a.target.spawns > b.target.spawns end
        return a.target.name < b.target.name
    end)
    return out
end

-- The biggest spawn cluster of target `t` in `zone`: { x, y }, or nil.
local function biggestSpot(zone, t)
    if not t.entry then return nil end
    local best
    for _, c in ipairs(Gather.Clusters(zone, t.kind == "mob" and "mobs" or "nodes", t.entry)) do
        if not best or c[3] > best[3] then best = c end
    end
    return best and { x = best[1], y = best[2] } or nil
end

-- The Skill-ups lines of `prof` in `zone`: up to SKILLUP_LINES targets, each with the skill it
-- gives points at in its colour, how many spawn here, and a pin to its biggest cluster.
function GatherList.SkillUpLines(zone, prof, rank)
    local out = {}
    for i, s in ipairs(GatherList.SkillUps(zone, prof, rank)) do
        if i > GatherList.SKILLUP_LINES then break end
        local t = s.target
        local lv = t.kind == "mob" and span(t.minLevel, t.maxLevel)
        local spot = biggestSpot(zone, t)
        out[#out + 1] = { kind = "source", prof = prof, src = { name = t.name }, text = t.name, skill = s.req,
            info = ("skill %d · %s%s"):format(s.req, lv and ("lvl " .. lv .. " · ") or "",
                countWord(t.spawns, t.kind == "mob" and "spawn" or "node")),
            infoColor = CP.RouteMap.SKILL_COLOR[s.color],
            tip = { t.name, lv and ("Level %s · %s %d to %d"):format(lv, PROF_NAME[prof], t.req, t.reqHi)
                or ("Needs %s %d"):format(PROF_NAME[prof], t.req) },
            pin = spot and spotPin(zone, spot, t.name) }
    end
    return out
end

-- Why a gathering skill gets nothing in a zone, and where the gathering guide sends it instead.
GatherList.WHY_NONE = {
    [Gather.SKINNING] = "%s: no beasts to skin here",
    [Gather.MINING] = "%s: no ore here",
    [Gather.HERBALISM] = "%s: no herbs here",
}
GatherList.WHY_GREY = "%s: grey here at %d"
GatherList.WHY_HIGH = "%s: needs %d here (you're %d)"
GatherList.BETTER = "Better for you: %s"
GatherList.BETTER_ZONES = 3   -- zones the Better for you line names at most

-- Why `zone` gives `prof` no skill-ups at `rank`, or nil when it gives some.
function GatherList.WhyText(zone, prof, rank)
    local name = PROF_NAME[prof]
    local targets = Gather.ZoneTargets(zone, prof)
    if #targets == 0 then return GatherList.WHY_NONE[prof]:format(name) end
    local reach, low = false, nil
    for _, t in ipairs(targets) do
        local req = Gather.TargetReq(t, rank)
        if req then
            if CP.GatherGuide.Band(rank, req) > 0 then return nil end
            reach = true
        end
        low = math.min(low or t.req, t.req)
    end
    if reach then return GatherList.WHY_GREY:format(name, rank) end
    return GatherList.WHY_HIGH:format(name, low, rank)
end

-- The zones the gathering guide picks for `prof` at `rank` (its current stretch's best zones,
-- GatherGuide.PlayerRows), without `zone`: a list of names, or nil. Nil and true while the
-- guide's zones are still being found; GatherGuide.WARM.signal then rebuilds the list.
function GatherList.BetterZones(prof, rank, zone)
    local GG = CP.GatherGuide
    if not GG.Ready(prof) then
        GG.Warm(prof)
        return nil, true
    end
    for _, row in ipairs(GG.PlayerRows(prof, rank, Gather.MaxRank(prof) or 300)) do
        if row.gather and not row.side then
            local list = row.gather.zones or {}
            if #list == 0 then list = { { zone = row.gather.zone } } end
            local names, seen = {}, {}
            for _, z in ipairs(list) do
                if z.zone and z.zone ~= zone and not seen[z.zone] and #names < GatherList.BETTER_ZONES then
                    seen[z.zone] = true
                    names[#names + 1] = zoneName(z.zone)
                end
            end
            if row.levelGate and #names > 0 then
                names[#names] = ("%s (level %d)"):format(names[#names], row.levelGate.need)
            end
            return #names > 0 and names or nil
        end
    end
    return nil
end

-- A gathering skill's lines in place of its section when `zone` gives it neither skill-ups nor
-- anything the guides need: why, then the guide's better zones. Nil when it gives skill-ups.
function GatherList.WhyLines(zone, prof, rank)
    local why = GatherList.WhyText(zone, prof, rank)
    if not why then return nil end
    local out = { { kind = "plan", muted = true, text = why, why = prof } }
    local names, waiting = GatherList.BetterZones(prof, rank, zone)
    local better = names and table.concat(names, ", ") or waiting and CP.GatherGuide.WARM.waiting
    if better then
        out[2] = { kind = "plan", muted = not names, indent = 30, why = prof, text = GatherList.BETTER:format(better) }
    end
    return out
end

-- Farm's worth -----------------------------------------------------------------------

-- Farm is for gold: its list leads with the profit, what the zone's materials sell for. It
-- also points to zones with a material worth FARM_BETTER_RATIO times more (Farm.Find), among the
-- zones the player's gathering skills reach.
GatherList.FARM_BETTER_RATIO = 2     -- a better zone's material sells for this many times the best here
GatherList.FARM_MIN_CHANCE = 25      -- percent: a source this likely counts for a better zone
GatherList.FARM_CANDIDATES = 6       -- the most valuable materials looked up for better zones
GatherList.FARM_SHOW = 3             -- materials and better zones named at most
GatherList.FARM_HEAD_PROFIT = "Profit"
GatherList.PROFIT_KEY = "profit"     -- the Profit section's fold key in farmClosed
GatherList.FARM_HEAD_STALE = "Profit (Prices Stale - %dd old)"   -- the oldest shown auction price's age
GatherList.FARM_STALE_AGE = 86400    -- seconds: an auction price older than this is stale
GatherList.FARM_AGE_UNIT = 86400     -- seconds in one unit of the stale heading's age
GatherList.FARM_HEAD_UNPRICED = "To farm here"
GatherList.FARM_HAS = "Here: %s"
GatherList.FARM_BETTER = "Best farm: %s"
GatherList.FARM_BETTER_SHORT = "Best: %s"   -- the Best farm lead when the full text does not fit
GatherList.FARM_EACH = "%s ea (%s)"
GatherList.TAG_AH, GatherList.TAG_VENDOR = "AH", "Vendor"
GatherList.FARM_NO_PRICE = "no price yet"

-- What one `item` sells for: the auction price when it beats the vendor's, else the vendor's.
-- Returns value, tag ("AH" or "Vendor"), stale, and the auction price's age in seconds. Both
-- prices are after the auction cut, so they compare like for like. An auction source that gives
-- no age is never stale.
function GatherList.SalePrice(item)
    local vendor, ah = CP.Pricing.SaleValue(item)
    if ah and (not vendor or ah > vendor) then
        local age = CP.Pricing.AuctionAge(item)
        return ah, GatherList.TAG_AH, age ~= nil and age > GatherList.FARM_STALE_AGE, age
    end
    if vendor then return vendor, GatherList.TAG_VENDOR, false end
    return nil, nil, false
end

-- The older of two ages; either may be nil.
local function older(a, b)
    if not a then return b end
    return b and math.max(a, b) or a
end

-- What the player can farm in `zone` with `skills`: { { item, value } }, most valuable first.
-- `value` is one item's sale (SalePrice), nil when unknown; `tag` says which ("AH" or "Vendor"),
-- `stale` that an auction price is old, `age` its age in seconds. The same goods Farm's sections
-- list: leathers, herbs and ore the skills reach, Cooking's goods, cloth and the fish in `items`.
function GatherList.FarmGoods(zone, items, skills)
    local seen, out = {}, {}
    local function add(item)
        if item and item > 0 and not seen[item] then
            seen[item] = true
            local value, tag, stale, age = GatherList.SalePrice(item)
            out[#out + 1] = { item = item, value = value, tag = tag, stale = stale, age = age }
        end
    end
    if skills[Gather.SKINNING] then
        for _, m in ipairs(GatherList.FarmLeathers(zone, skills)) do add(m.item) end
    end
    for _, prof in ipairs({ Gather.MINING, Gather.HERBALISM }) do
        local rank = skills[prof]
        for _, n in ipairs(rank and Gather.RouteNodes(prof, zone) or {}) do
            if n.skill <= rank then add(n.item) end
        end
    end
    for _, r in ipairs(Gather.CookRows(zone, skills, GatherList.ZONE_OPTS)) do add(r.itemID) end
    for _, c in ipairs(Gather.ClothRows(zone, nil, Gather.PlayerLevel(), UnitFactionGroup("player"))) do add(c.item) end
    for _, r in ipairs(items or {}) do
        if r.prof == Gather.FISHING and CP.Pricing.IsFish(r.itemID) and GatherList.Listed(r) then add(r.itemID) end
    end
    table.sort(out, function(a, b)
        local va, vb = a.value or -1, b.value or -1
        if va ~= vb then return va > vb end
        return a.item < b.item
    end)
    return out
end

-- Zones with a material worth FARM_BETTER_RATIO times `best` that the player's skills reach:
-- { { text = "Zone (Material)", zone, item, info = "45s ea (AH)" } }, at most FARM_SHOW, the most
-- valuable first. The second value is true while a search still runs (Farm.FOUND then rebuilds
-- the list). The third is the oldest auction price used, in seconds, or nil.
function GatherList.FarmBetter(zone, best)
    local skills, level = Gather.Skills(), Gather.PlayerLevel()
    local floor = (best or 0) * GatherList.FARM_BETTER_RATIO
    local cand = {}
    for _, item in ipairs(CP.Farm.Items(skills, level, GatherList.FARM_MIN_CHANCE)) do
        local value, tag, _, age = GatherList.SalePrice(item)
        if value and value > 0 and value >= floor then
            cand[#cand + 1] = { item = item, value = value, tag = tag, age = age }
        end
    end
    table.sort(cand, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.item < b.item
    end)
    local opts = { level = level, side = UnitFactionGroup("player"), skills = skills,
                   continent = (CP.Waypoint.PlayerWorld()) }
    local out, seen, old = {}, {}, nil
    for i, c in ipairs(cand) do
        if i > GatherList.FARM_CANDIDATES or #out >= GatherList.FARM_SHOW then break end
        local found, known = CP.Farm.Find(c.item, opts)
        if not known then return out, true, old end
        if found and found.zone ~= zone and not seen[found.zone] then
            seen[found.zone] = true
            local place, item = zoneName(found.zone), nameOf(c.item)
            out[#out + 1] = { text = ("%s (%s)"):format(place, item), zone = place, item = item,
                info = GatherList.FARM_EACH:format(CP.Pricing.Format(c.value), c.tag) }
            old = older(old, c.age)
        end
    end
    return out, false, old
end

-- Everything `zone` holds to gather, as each profession's range: "Skinning 1-95 · Mining 1-65".
function GatherList.ZoneHas(zone)
    local parts = {}
    for _, prof in ipairs(ZONE_PROFS) do
        local text = GatherList.RangeText(zone, prof)
        if text then parts[#parts + 1] = text end
    end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

-- The lines Farm leads with in `zone`: the profit, what the zone has and better zones to farm.
function GatherList.WorthLines(zone, items, skills)
    if not zone or Gather.IsInstance(zone) then return {} end
    local goods = GatherList.FarmGoods(zone, items, skills)
    local priced = #goods == 0 or goods[1].value ~= nil
    local best = goods[1] and goods[1].value or 0
    local better, waiting, old
    if priced then better, waiting, old = GatherList.FarmBetter(zone, best) end
    local out, folded = {}, false
    if #goods == 0 then
        local has = GatherList.ZoneHas(zone)
        if has then out[1] = { kind = "plan", muted = true, text = GatherList.FARM_HAS:format(has) } end
    else
        local oldest = old
        for i = 1, math.min(#goods, GatherList.FARM_SHOW) do oldest = older(oldest, goods[i].age) end
        local stale = oldest and oldest > GatherList.FARM_STALE_AGE
        local head = not priced and GatherList.FARM_HEAD_UNPRICED
            or stale and GatherList.FARM_HEAD_STALE:format(math.floor(oldest / GatherList.FARM_AGE_UNIT))
            or GatherList.FARM_HEAD_PROFIT
        -- Profit folds like a profession section; the goods and better zones sit under it.
        folded = (CP.db[GatherList.FoldKey()] or {})[GatherList.PROFIT_KEY]
        out[1] = { kind = "section", key = GatherList.PROFIT_KEY, closed = folded, text = head }
        for i = 1, folded and 0 or math.min(#goods, GatherList.FARM_SHOW) do
            local g = goods[i]
            out[#out + 1] = { kind = "plan", indent = 30, textColor = S.color.text, itemID = g.item,
                text = iconText(g.item, nameOf(g.item)),
                info = g.value and GatherList.FARM_EACH:format(CP.Pricing.Format(g.value), g.tag)
                    or GatherList.FARM_NO_PRICE }
        end
    end
    if folded then
        return out
    elseif better and #better > 0 then
        -- One row per zone, the lead on the first; the price sits in the info column like a material's.
        -- Later zones hang off the first (spotOf), so the whole Best farm group lights as one.
        -- Each row stays one line: the wrap fits its text to the room left of the price (FarmFit).
        local lead
        for i, b in ipairs(better) do
            out[#out + 1] = { kind = "plan", indent = 30, spotOf = lead,
                fit = { zone = b.zone, item = b.item, lead = i == 1 },
                text = i == 1 and GatherList.FARM_BETTER:format(b.text) or b.text, info = b.info }
            lead = lead or out[#out]
        end
    elseif waiting then
        out[#out + 1] = { kind = "plan", muted = true, indent = 30,
            text = GatherList.FARM_BETTER:format(CP.GatherGuide.WARM.waiting) }
    end
    return out
end

-- Lines for `items` from Gather.Rows: one section per profession. Follow the guide lists, for
-- each gathering skill, what gives it skill-ups here, then the items a guide still needs with
-- their grind spots; a gathering skill that gets neither has its why and better zones in place
-- of its section (WhyLines). Farm leads with what sells (WorthLines) and lists no guide item:
-- its sections hold the map's grind spots (Cooking's meat and eggs included), the herbs and
-- ore the loop visits and the fish the water gives. `fishLines`, the Fishing plan, opens the
-- Fishing section, which shows even with no fish needed. The Cloth section sits after
-- Skinning, Mining and Herbalism and before Cooking and Fishing (ClothLines). A picked
-- crafting profession's own section leads, above its Cloth (CraftLines).
function GatherList.Lines(items, skills, fishLines)
    local out, closed = {}, CP.db[GatherList.FoldKey()] or {}
    local sections, order = {}, {}
    local zone = GatherList.zone
    local outdoors = zone and not Gather.IsInstance(zone)
    if fishLines and #fishLines > 0 then
        sections[Gather.FISHING] = {}
        order[1] = Gather.FISHING
    end
    local farming = Gather.RouteFarming()
    for _, row in ipairs(items) do
        if farming and row.prof == Gather.FISHING and GatherList.Listed(row) and CP.Pricing.IsFish(row.itemID) then
            -- Farm lists the real catches the water gives (Pricing.IsFish), as sellables with no guide need.
            row = setmetatable({ need = false, soon = false }, { __index = row })
        elseif not (row.need and not row.done and not farming and GatherList.Listed(row)) then
            row = nil
        end
        if row then
            if not sections[row.prof] then
                sections[row.prof] = {}
                order[#order + 1] = row.prof
            end
            table.insert(sections[row.prof], row)
        end
    end
    local spots
    spots, GatherList.spotSig = GatherList.SpotLines(zone)
    for _, l in ipairs(farming and GatherList.NodeLines(zone, skills) or {}) do
        spots[l.prof] = spots[l.prof] or {}
        table.insert(spots[l.prof], l)
    end
    local ups, why = {}, {}
    for _, prof in ipairs(not farming and outdoors and ZONE_PROFS or {}) do
        if skills[prof] then
            ups[prof] = GatherList.SkillUpLines(zone, prof, skills[prof])
            if #ups[prof] > 0 and not sections[prof] then
                sections[prof] = {}
                order[#order + 1] = prof
            end
        end
    end
    for prof in pairs(spots) do
        if PROF_ORDER[prof] and not sections[prof] then
            sections[prof] = {}
            order[#order + 1] = prof
        end
    end
    for _, prof in ipairs(not farming and outdoors and ZONE_PROFS or {}) do
        if skills[prof] and not sections[prof] then
            why[prof] = GatherList.WhyLines(zone, prof, skills[prof])
            if why[prof] then order[#order + 1] = prof end
        end
    end
    table.sort(order, function(a, b) return PROF_ORDER[a] < PROF_ORDER[b] end)
    local pick = GatherList.PanelProf()
    if pick then
        local only = {}
        for _, key in ipairs(order) do
            if key == pick then only[#only + 1] = key end
        end
        order = only
    end
    if farming and not pick then
        for _, l in ipairs(GatherList.WorthLines(zone, items, skills)) do out[#out + 1] = l end
    end
    local clothDone = false
    local function addCloth()
        clothDone = true
        for _, l in ipairs(GatherList.ClothLines(zone, #out == 0)) do out[#out + 1] = l end
    end
    for i, key in ipairs(order) do
        if not clothDone and PROF_ORDER[key] >= PROF_ORDER[Gather.COOKING] then addCloth() end
        if not sections[key] then
            for _, l in ipairs(why[key]) do out[#out + 1] = l end
        else
            local rows, own, ownUps = sections[key], spots[key] or {}, ups[key] or {}
            -- A gathering profession's guide section holds its skill-ups and what the guides need
            -- (their rows, then their grind spots), each under a small heading; the column note
            -- sits on the guide-needs heading.
            local split = not farming and GATHER_PROFS[key] or false
            local needInfo = i == 1 and #rows > 0 and (farming and "have" or "have / need") or nil
            out[#out + 1] = { kind = "section", key = key, closed = closed[key],
                text = ("%s %d"):format(PROF_NAME[key], skills[key] or 0),
                info = not (split and #rows > 0) and needInfo
                    or nil }
            if not closed[key] then
                if key == Gather.FISHING then
                    for _, l in ipairs(fishLines or {}) do out[#out + 1] = l end
                end
                local upsOpen, guideOpen = true, true
                if split and #ownUps > 0 then
                    local h = foldSub(GatherList.SKILLUPS_HEAD, nil, key, GatherList.SUB_SKILLUPS, #ownUps)
                    out[#out + 1], upsOpen = h, not h.closed
                end
                if upsOpen then
                    for _, l in ipairs(ownUps) do out[#out + 1] = l end
                end
                if split and (#rows > 0 or #own > 0) then
                    local spotsHere = 0
                    for _, l in ipairs(own) do
                        if not l.spotOf then spotsHere = spotsHere + 1 end
                    end
                    local h = foldSub(GatherList.GUIDE_HEAD, needInfo, key, GatherList.SUB_GUIDE, #rows + spotsHere)
                    out[#out + 1], guideOpen = h, not h.closed
                end
                if not guideOpen then rows, own = {}, {} end
                local function addRows()
                    for _, row in ipairs(rows) do
                        out[#out + 1] = { kind = "item", row = row, open = open[row.itemID], info = itemInfo(row),
                            pin = toGrind(row) }
                        if open[row.itemID] then
                            for _, l in ipairs(GatherList.SourceLines(row, zone)) do out[#out + 1] = l end
                        end
                    end
                end
                if split then addRows() end
                for _, l in ipairs(own) do out[#out + 1] = l end
                if not split then addRows() end
            end
        end
    end
    local craft = GatherList.CraftPick()
    if craft then
        for _, l in ipairs(GatherList.CraftLines(zone, craft, #out == 0)) do out[#out + 1] = l end
    end
    if not clothDone then addCloth() end
    return out
end

-- Fishing ---------------------------------------------------------------------------

-- How far a zone's middle is from the player, in yards; far away on another continent.
local function distance(zone)
    local continent, px, py = CP.Waypoint.PlayerWorld()
    local c, x, y = CP.Waypoint.MapToWorld(zone, 0.5, 0.5)
    if not continent or not c then return nil end
    if c ~= continent then return 1e9 end
    return math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
end
GatherList.Distance = distance

local function toNearest(rank, who)
    return function()
        local data = CP.GatherData.fishing
        local continent, px, py = CP.Waypoint.PlayerWorld()
        local side = CP.Sourcing.Side()
        local target = CP.Mapz.Nearest(rank.npcs, data.npcs, side)
            or CP.Waypoint.Nearest(rank.npcs, data.npcs, side, continent, px, py)
        if target then
            CP.Waypoint.Place(target)
        else
            CP:Print(("No known %s for %s."):format(who, CP.Fishing.RankName(rank)))
        end
    end
end

local function toSpot(zone)
    local spot = CP.Fishing.Spot(zone)
    if not spot then return nil end
    return function() placeAt(zone, spot[1], spot[2], "Fishing pool") end
end

local RANK_TEXT = {
    trainer = { "Train Journeyman Fishing", "trainer", "Any Fishing trainer teaches it." },
    book = { "Buy Expert Fishing", "book vendor", "\"Expert Fishing - The Bass and You\" is sold in Booty Bay." },
    quest = { "Artisan Fishing quest", "quest giver", "Nat Pagle in Dustwallow Marsh gives the quest." },
}

-- Plan lines for the Fishing section from Fishing.Plan's result.
function GatherList.FishLines(plan, zone, maxRank)
    if plan.kind == "rank" then
        local t = RANK_TEXT[plan.rank.kind]
        return { { kind = "plan", text = t[1], info = ("at %d"):format(plan.rank.skill),
            tip = { t[3] }, pin = toNearest(plan.rank, t[2]) } }
    elseif plan.kind == "none" then
        return { { kind = "plan", muted = true, text = "No water safe at your level to fish yet" } }
    end
    local out = {}
    local where = plan.here and not GatherList.away and "Fish here" or ("Fish in %s"):format(zoneName(plan.zone))
    out[1] = { kind = "plan", text = ("%s to %d"):format(where, maxRank),
        info = plan.land < 100 and ("lands %d%%"):format(plan.land) or ("~%d catches"):format(plan.catches),
        tip = { plan.land < 100 and "The easiest water you can fish. Some fish get away until your skill rises."
            or "Every bite lands there, and skill-ups don't depend on the zone." },
        pin = toSpot(plan.zone) }
    -- What the fishing feeds, under the heading behind a down-right arrow (kind "feed").
    for i, feed in ipairs(plan.feeds or {}) do
        if i > 2 then break end
        local short = feed.need - feed.have
        out[#out + 1] = { kind = "feed",
            text = short > 0 and ("%s x%d"):format(nameOf(feed.item), short) or (nameOf(feed.item) .. ": enough"),
            textColor = short > 0 and S.color.warn or S.color.good }
    end
    return out
end

local function fishPlan(zone)
    local info = CP.Professions.SkillLine(CP.Fishing.SKILL)
    if not info or not info.rank or info.rank <= 0 then return nil end
    local skill, maxRank = info.rank, info.maxRank or 75
    if skill >= 300 then return nil end
    local needs = {}
    for item, n in pairs(CP.charDB.gatherNeeds and CP.charDB.gatherNeeds[Gather.COOKING] or {}) do needs[item] = n end
    local plan = CP.Fishing.Plan({
        skill = skill, mod = info.modifier, maxRank = maxRank, level = Gather.PlayerLevel(), zone = zone,
        side = UnitFactionGroup("player"), cook = CP.Settings.FishCook(), needs = needs, have = have, distance = distance,
    })
    return GatherList.FishLines(plan, zone, maxRank)
end

-- Daylight UI's whisper card (its frame is read, never touched). While it is shown and
-- overlaps the free guide window hanging from `anchor`, the window sits just to its right.
local TALK = "DaylightUIChatTalk"

function GatherList.TalkOffset(anchor)
    local talk = rawget(_G, TALK)
    if not (anchor and talk and talk.IsVisible and talk:IsVisible()) then return 0 end
    local tl, tr, tt, tb = talk:GetLeft(), talk:GetRight(), talk:GetTop(), talk:GetBottom()
    local al, at = anchor:GetLeft(), anchor:GetTop()
    if not (tl and tr and tt and tb and al and at) then return 0 end
    local ts, as = talk:GetEffectiveScale(), anchor:GetEffectiveScale()
    tl, tr, tt, tb = tl * ts / as, tr * ts / as, tt * ts / as, tb * ts / as
    local overlaps = tl < al + anchor:GetWidth() and tr > al and tb < at and tt > at - 400
    return overlaps and math.max(0, tr - al + 4) or 0
end

-- The card's OnShow and OnHide move the window. Daylight UI's chat makes the card at its
-- first conversation, so while DaylightUI_Chat is loaded and the card isn't made yet, a
-- look every TALK_FIND seconds waits for it.
GatherList.TALK_FIND = 0.5
local talkShown, talkHooked, talkFinder = false, nil, nil

local function talkMoved()
    local talk = rawget(_G, TALK)
    local shown = talk and talk.IsVisible and talk:IsVisible() or false
    if shown == talkShown then return end
    talkShown = shown
    if CP.Window and CP.Panel.frame:IsShown() then CP.Window.Update() end
end

-- Hooks the card once it exists. True when hooked.
local function hookTalk()
    local talk = rawget(_G, TALK)
    if not (type(talk) == "table" and talk.HookScript) then return false end
    if talkHooked ~= talk then
        talkHooked = talk
        talk:HookScript("OnShow", talkMoved)
        talk:HookScript("OnHide", talkMoved)
        talkMoved()
    end
    if talkFinder then talkFinder:Cancel() end
    talkFinder = nil
    return true
end

local function findTalk()
    if hookTalk() or talkFinder then return end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "DaylightUI_Chat")
    if ok and loaded then talkFinder = C_Timer.NewTicker(GatherList.TALK_FIND, hookTalk) end
end
CP:On("PLAYER_LOGIN", findTalk)
CP:On("ADDON_LOADED", function(_, name) if name == "DaylightUI_Chat" then findTalk() end end)

-- Rows that fit in the panel's height.
local function roomRows()
    local h = host and tonumber(host:GetHeight()) or 0
    if h <= headH() then return MAX_ROWS end
    return math.max(1, math.floor((h - headH()) / ROW_H))
end
GatherList.RoomRows = roomRows

-- A scroll bar on the right edge, shown only when some lines don't fit. The list
-- pages its own rows, so the bar counts rows. Daylight UI's bar reads and moves the
-- offset (Style.PagedScroll); the game's bar is driven by hand and reports back
-- through OnScroll.

local BAR_W = 8
local WHEEL_ROWS = 3     -- rows one wheel notch moves
local bar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
bar:SetWidth(BAR_W)
bar:SetPoint("TOPRIGHT", -EDGE, -(headH() + 2))
bar:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
bar:Hide()
GatherList.scrollBar = bar
local syncing = false
local refitting = false
local draw

local function call(method, ...)
    if bar[method] then bar[method](bar, ...) end
end

if bar.RegisterCallback then
    bar:RegisterCallback("OnScroll", function(_, pct)
        if syncing then return end
        local hidden = #lines - (GatherList.shown or 0)
        if hidden <= 0 then return end
        offset = math.floor((pct or 0) * hidden + 0.5)
        draw()
    end, f)
end

local function plainShown()
    local shown = GatherList.shown or 0
    return shown > 0 and #lines > shown
end

GatherList.scrolling = S.PagedScroll({
    name = "Gathering window", list = f, plain = bar, step = WHEEL_ROWS,
    read = function()
        local shown = GatherList.shown or 0
        return offset, math.max(0, #lines - shown), shown
    end,
    write = function(v)
        local to = math.floor(v + 0.5)
        if to == offset then return end
        offset = to
        draw()
    end,
    onWheel = function(_, delta)
        offset = offset - delta * WHEEL_ROWS
        draw()
    end,
    restore = function() bar:SetShown(plainShown()) end,
})
local scrolling = GatherList.scrolling

local function syncBar(shown)
    if scrolling.active then return scrolling.dui.Update() end
    local hidden = #lines - shown
    local on = plainShown()
    bar:SetShown(on)
    if not on then return end
    syncing = true
    call("SetVisibleExtentPercentage", shown / #lines)
    call("SetPanExtentPercentage", math.min(1, WHEEL_ROWS / hidden))
    call("SetScrollPercentage", offset / hidden)
    syncing = false
end

function draw()
    local shown = math.min(#lines, roomRows())
    offset = math.max(0, math.min(offset, #lines - shown))
    GatherList.shown = shown
    local right = shown < #lines and shown > 0 and -(S.ScrollRoom(scrolling) + EDGE) or -EDGE
    local top = headH()
    bar:SetPoint("TOPRIGHT", -EDGE, -(top + 2))
    if GatherList.empty then GatherList.empty:SetPoint("TOPLEFT", 2, -top - 4) end
    for i = 1, shown do
        local r = rows[i] or makeRow(i)
        r:SetPoint("TOPLEFT", EDGE, -(top + (i - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", right, -(top + (i - 1) * ROW_H))
        setLine(r, lines[offset + i])
        r:Show()
    end
    syncBar(shown)
    for i = shown + 1, #rows do rows[i]:Hide() end
    f:SetHeight(top + shown * ROW_H + EDGE)
    -- The panel fits its height to the rows; once it has, draw for the new room.
    if not refitting and CP.GatherPanel and CP.GatherPanel.Fit() then
        refitting = true
        draw()
        refitting = false
    end
end

-- The height the list needs to show every line: the header, then its rows (or the
-- empty line).
function GatherList.NeedHeight()
    return headH() + math.max(#lines, 1) * ROW_H + EDGE
end

-- The lines the list holds and the row frames showing them, for tests.
function GatherList.Drawn() return lines, rows, offset end


-- Patterns -----------------------------------------------------------------------
-- The patterns vendors sell in the zone, collapsed under one header. Entering a zone
-- with new ones pulses the header in the accent for PULSE_SECONDS, then a red count
-- beside it waits until the player opens it.

local PULSE_SECONDS = 20
GatherList.patternsOpen, GatherList.unseen, GatherList.pulseUntil = false, 0, 0
GatherList.unseenWas = 0   -- the count the open section read away, back when it folds

function GatherList.Notify(count)
    GatherList.patternsOpen = false
    GatherList.unseen, GatherList.unseenWas = count, 0
    local ends = GetTime() + PULSE_SECONDS
    GatherList.pulseUntil = ends
    GatherList.Refresh()

    -- Only the latest pulse redraws when it ends; a later Notify or a reset owns the header.
    C_Timer.After(PULSE_SECONDS + 0.1, function()
        if GatherList.pulseUntil == ends then GatherList.Changed() end
    end)
end

-- The saved plans' next steps, one line per profession with a guide, from the plans saved
-- when each window was last open. The panel draws none of it; the simulator and the
-- headless tests read it to check the numbers the launcher and step card also show.
-- Closed until nextOpen is set.
GatherList.nextOpen = false

-- The vendor cursor's coin bag: ready, but only with what's in the bank.
local BANK_ICON = "|TInterface\\Cursor\\Buy:14:14|t"

function GatherList.NextLines()
    local steps = CP.charDB and CP.charDB.nextStep or {}
    local list = {}
    for key, st in pairs(steps) do
        local guide = CP.Guides and CP.Guides[key]
        if guide and st then list[#list + 1] = { key = key, guide = guide, st = Gather.LiveStep(key, st) } end
    end
    local gather = CP.Launcher and CP.Launcher.GatherLines() or {}
    GatherList.waitingZones = false
    for _, g in ipairs(gather) do
        if g.right == CP.GatherGuide.WARM.waiting then GatherList.waitingZones = true end
    end
    if #list + #gather == 0 then return {} end
    table.sort(list, function(a, b) return a.guide.name < b.guide.name end)
    local out = { { kind = "section", key = "next", closed = not GatherList.nextOpen, text = "Next up",
                    info = tostring(#list + #gather) } }
    if not GatherList.nextOpen then return out end
    for _, e in ipairs(list) do
        local st = e.st
        -- The profession, then what to do about it: the step's short material and how many
        -- the step lacks (Gather.NeedText; the plan's count is in the tip), "Buy <item>
        -- xN" when a vendor good is all it lacks, "Bank:
        -- <item> xN" when only the bank covers it, "Ready to craft <recipe>", or the recipe to learn.
        local item = st.item and nameOf(st.item)
        local text, color, info
        local tip = { ("%s, skill %d to %d"):format(st.name, st.skill, st.to) }
        if st.rank then
            -- At the cap: the rank to learn, worded as the guide's rank row.
            text, color = ("%s %s"):format(CP.Guide.RankVerb(st.rank), st.name), S.color.warn
            tip = { ("%s (skill capped at %d)"):format(text, st.max) }
        elseif not st.learned and not CP.Plan.Read(e.key) then
            text, color = CP.Plan.OPEN_ONCE:format(e.guide.name), S.color.warn
        elseif not st.learned then
            text, color = "Learn " .. st.name, S.color.warn
        elseif st.short > 0 and item then
            text, color = Gather.NeedText(st, nameOf), S.color.warn
            for _, line in ipairs(Gather.NeedTip(st, nameOf, e.guide)) do tip[#tip + 1] = line end
        elseif st.bank then
            -- Ready only after a bank trip: say what to fetch, not "Ready".
            local name = nameOf(st.bank.item)
            text, color, info = ("Bank: %s x%d"):format(name, st.bank.count), S.color.warn, BANK_ICON
            tip[#tip + 1] = ("Take %d %s from the bank, then it's ready"):format(st.bank.count, name)
        else
            local tool
            text, tool = Gather.ReadyText(st, e.guide)
            color = tool and S.color.warn or S.color.good
        end
        if st.levelShort then tip[#tip + 1] = st.levelShort.text end
        out[#out + 1] = { kind = "plan", text = e.guide.name, muted = false, tip = tip }
        out[#out + 1] = { kind = "plan", text = text, textColor = color, indent = 30, tip = tip, info = info }
    end
    -- Gathering skills: where their guide goes next, or the rank to train.
    for _, g in ipairs(gather) do
        local tip = { ("%s %d"):format(g.name, g.skill) }
        local text
        if g.right == "maxed" then
            text = "Maxed"
        elseif g.right == "gather" then
            text = "Gather here"
        elseif g.warn then
            text = (g.right:gsub("^train", "Train"))
        elseif g.right == CP.GatherGuide.WARM.waiting then
            text = (g.right:gsub("^%l", string.upper)) .. "..."
        else
            text = "Go to " .. g.right
        end
        out[#out + 1] = { kind = "plan", text = g.name, muted = false, tip = tip }
        out[#out + 1] = { kind = "plan", text = text, textColor = g.warn and S.color.warn or S.color.label,
                          indent = 30, tip = tip }
    end
    return out
end

-- The guide key (profession id) whose watch list holds `buy`.
local function watchKey(buy)
    for key, list in pairs(CP.charDB.vendorWatch or {}) do
        for _, b in ipairs(list) do
            if b == buy then return key end
        end
    end
end

-- Whether the player can learn what `buy` teaches this minute: the profession's skill
-- reaches the pattern's, the recipe is not known, and the purse covers `buy.price` (copper)
-- when that is known. The same skill test as Guide.LearnGate and PatternLearn.Gate.
function GatherList.PatternLearnable(buy)
    local key = buy and watchKey(buy)
    local info = key and CP.Professions.SkillLine(key)
    if not info or info.isHeader or (info.rank or 0) < (buy.skill or 0) then return false end
    local guide = CP.Guides and CP.Guides[key]
    for spell, r in pairs(guide and guide.recipes or {}) do
        if r.pattern == buy.item then
            for _, id in ipairs(CP.charDB.learned and CP.charDB.learned[key] or {}) do
                if id == spell then return false end
            end
            if CP.Professions.SpellKnown(spell) then return false end
        end
    end
    if buy.price and GetMoney and GetMoney() < buy.price then return false end
    return true
end

-- A vendor in a picked zone the player is not in only gets a mark on the map, as a row's pin there.
local function markVendor(target)
    local mapID, pos = CP.Waypoint.Locate(target)
    local x, y
    if pos then x, y = pos:GetXY() end
    if mapID and x and y then GatherList.MarkOnMap(mapID, x, y, target.name) end
end

-- The patterns section for `current` ({ zone, found }, VendorWatch's). In a picked zone the
-- player is not in, the new-pattern pulse and count stay with the player's own zone, and the
-- pins only mark the map.
function GatherList.PatternLines(current)
    if not current then return {} end
    current = GatherList.PickedPatterns(current)
    if #current.found == 0 then return {} end
    local VW = CP.VendorWatch
    local away = GatherList.away and current.zone ~= GatherList.here
    local pulsing = not away and GetTime() < GatherList.pulseUntil
    local out = { {
        kind = "section", key = "patterns", closed = not GatherList.patternsOpen,
        text = "Patterns to buy here", info = tostring(#current.found),
        pulse = pulsing, badge = not (pulsing or away) and GatherList.unseen > 0 and tostring(GatherList.unseen) or nil,
        pin = not away and function() VW.MarkAll(current.found, current.zone) end or nil,
    } }
    if not GatherList.patternsOpen then return out end
    for _, v in ipairs(VW.ByVendor(current.found)) do
        out[#out + 1] = { kind = "vendor", text = v.target.name, info = CP.Waypoint.Describe(v.target),
            pin = function()
                if away then return markVendor(v.target) end
                CP.Waypoint.Place(v.target)
            end }
        for _, buy in ipairs(v.buys) do
            out[#out + 1] = { kind = "pattern", text = buy.name, limited = buy.limited, itemID = buy.item,
                learnNow = GatherList.PatternLearnable(buy),
                info = buy.limited and "limited" or ("skill %d"):format(buy.skill) }
        end
    end
    return out
end

-- Wrapping -------------------------------------------------------------------------
-- A row whose name and right-hand info don't both fit moves the info to a line of its
-- own below (a vendor, then where they stand). Widths come from the player's font.

local INDENT = { section = 16, item = 48, vendor = 18, pattern = 30, plan = 18, label = 46, zone = 30,
                 feed = FEED_ARROW_X + 12 + 4 }
-- Room right of a row's name: the pin, or a done item's check, then GAP before its info
-- (setLine's anchors: pin 16 px 2 px in, info 4 px left of it; check 14 px 4 px in, info
-- 2 px left of it; else info INFO_EDGE in; name 6 px left of the info).
local PIN_W, CHECK_W, GAP = 20, 18, 8
-- The header's title: `full` when it fits left of the icons, else the zone's `name`.
function GatherList.FitTitle(name, full)
    S.Pin(head.title)
    local room = headWidth()
    local shown = name or full
    for _, text in ipairs({ full, name or full }) do
        if GatherList.Measure(text, "head", true) <= room then
            shown = text
            break
        end
    end
    head.title:SetText(shown)
    head.zone:SetWidth(math.max(1, math.min(room, GatherList.Measure(shown, "head", true))))
end

-- `text`'s width in size role `size`'s current font, at the role's own size when `fixed`
-- (the header's lines). Tests stand in for it.
function GatherList.Measure(text, size, fixed)
    return S.Measure(text, size, fixed)
end

-- Room for a row's text at `barShown`: the row width less margins and scroll bar.
local function rowWidth(barShown)
    return GatherList.width - 2 * EDGE - (barShown and S.ScrollRoom(scrolling) or 0)
end

-- The colour a line's own text is drawn in, for the lines its name wraps onto.
local function nameColor(line)
    local c = S.color
    if line.kind == "plan" then return line.textColor or (line.muted and c.muted or c.accent) end
    if line.kind == "feed" then return line.textColor or c.muted end
    if line.kind == "pattern" then return line.limited and c.accent or c.text end
    if line.kind == "section" or line.kind == "vendor" or line.kind == "label" then return c.label end
    return c.text
end

-- Split `text` into pieces no wider than `room` (Style.Lines, measured by GatherList.Measure).
local function splitWords(text, room)
    return S.Lines(text, "body", room, function(t) return GatherList.Measure(t, "body") end)
end

-- Lines for `list` at the list's width. A short info (a count, yards) keeps its
-- right-aligned spot on the first line and the name breaks at spaces beside it. A long
-- info (a vendor's place) takes a line of its own below the name. Nothing else truncates,
-- in any font or size Daylight UI offers. A Best farm row stays one line and shortens its
-- text to fit beside its price instead (FarmFit); its tooltip shows the full text.
GatherList.INFO_SHARE = 0.5   -- an info this share of the row or less stays on the first line
GatherList.ELLIPSIS = "…"     -- ends a cut Best farm zone or material

local function chars(s) return s:gmatch("[%z\1-\127\194-\244][\128-\191]*") end

-- `s` cut to its first `n` characters, then the ellipsis.
local function cutTo(s, n)
    local out, i = "", 0
    for ch in chars(s) do
        if i >= n then break end
        out, i = out .. ch, i + 1
    end
    return out:gsub("%s+$", "") .. GatherList.ELLIPSIS
end

local function charCount(s)
    local n = 0
    for _ in chars(s) do n = n + 1 end
    return n
end

-- A Best farm row's text for `room` px in the live font, and its full text. `fit` is
-- { zone, item, lead }. The first form that fits wins: the full text, then the lead's short
-- "Best:", then the material cut a character at a time and at last dropped, then the zone cut.
-- The shortest form stands when none fits, and the row's bound clips it.
function GatherList.FarmFit(fit, room)
    local function fits(t) return GatherList.Measure(t, "body") <= room end
    local function form(head, zone, item)
        return head:format(item and ("%s (%s)"):format(zone, item) or zone)
    end
    local full = form(fit.lead and GatherList.FARM_BETTER or "%s", fit.zone, fit.item)
    if fits(full) then return full, full end
    local head = fit.lead and GatherList.FARM_BETTER_SHORT or "%s"
    local text = form(head, fit.zone, fit.item)
    if fits(text) then return text, full end
    for n = charCount(fit.item) - 1, 0, -1 do
        text = form(head, fit.zone, n > 0 and cutTo(fit.item, n) or nil)
        if fits(text) then return text, full end
    end
    for n = charCount(fit.zone) - 1, 1, -1 do
        text = form(head, cutTo(fit.zone, n))
        if fits(text) then return text, full end
    end
    return text, full
end

-- One wrapped `line`: its name split at spaces into `out` beside a short info, a long info
-- on lines of its own below.
local function wrapLine(out, line, room, info, indent)
    local keepInfo = info > 0 and info <= room * GatherList.INFO_SHARE
    local nameRoom = keepInfo and room - GAP - info or room
    local text = line.text or (line.row and line.row.name) or (line.src and line.src.name)
    if line.count then
        line.showCount = GatherList.Measure(text, "body") + COUNT_GAP + GatherList.Measure(line.count, "small")
            <= nameRoom
    end
    if text and line.kind ~= "cont" and GatherList.Measure(text, "body") > nameRoom then
        local pieces = splitWords(text, nameRoom)
        if #pieces > 1 then
            line.text = pieces[1]
            for i = 2, #pieces do
                out[#out + 1] = { kind = "cont", text = pieces[i], of = line, indent = indent, color = nameColor(line) }
            end
        end
    end
    if info > 0 and not keepInfo and text then
        local need = GatherList.Measure(line.text or text, "body") + GAP + info
        if need > room or #out > 1 and out[#out].of == line then
            for _, piece in ipairs(splitWords(line.info, room - 6)) do
                out[#out + 1] = { kind = "cont", text = piece, of = line, indent = indent + 6,
                    color = line.infoColor }
            end
            line.wrapped = true
        end
    end
end

local function wrapAt(list, barShown)
    local out, width = {}, rowWidth(barShown)
    for _, line in ipairs(list) do
        out[#out + 1] = line
        local indent = line.indent or INDENT[line.kind] or 50
        local done = line.kind == "item" and line.row and line.row.done
        local room = width - indent - (line.pin and PIN_W or done and CHECK_W or 0)
        local info = line.info and line.info ~= "" and GatherList.Measure(line.info, "small") or 0
        if line.fit then
            -- One line by construction: the price keeps its column and the text fits beside it.
            local full
            line.text, full = GatherList.FarmFit(line.fit, info > 0 and room - GAP - info or room)
            line.tip = line.text ~= full and { full } or nil
        else
            wrapLine(out, line, room, info, indent)
        end
    end
    return out
end

-- `barShown` nil lets the wrap decide: names split for the full width first, and when the
-- split pushes the count past the rows that fit, the scroll bar appears and the lines
-- split again for the narrower width.
function GatherList.Wrap(list, barShown)
    if barShown ~= nil then return wrapAt(list, barShown) end
    local before = {}
    for i, line in ipairs(list) do before[i] = { line, line.text, line.wrapped } end
    local out = wrapAt(list, false)
    if #out <= roomRows() then return out end
    for _, b in ipairs(before) do b[1].text, b[1].wrapped = b[2], b[3] end
    return wrapAt(list, true)
end

-- What the checklist and the route read of a zone. Grey mobs stay: quick, safe kills for
-- skins. Rares and lone spawns don't. The zone's rows are built once per zone and skill
-- ranks (Gather.ForZone's cache); bag changes only refill their counts.
GatherList.ZONE_OPTS = { here = function(...) return Gather.Farmable(...) end, cache = true }

-- Zone rows for another zone than the player's: uncached, so the player's zone keeps
-- Gather.ForZone's one cached list.
GatherList.OTHER_OPTS = { here = GatherList.ZONE_OPTS.here }

-- What a gathering loop in `zone` visits: the checklist's rows there (`items`, built
-- here with `opts`, else ZONE_OPTS, when not given), the herbs and ore that still give
-- the player skill, and the ticked skinning materials (Gather.SkinRows), which alone
-- bring skinning creatures in. Only sources the player can gather now come in. Farm
-- reads no guide need, so there the checklist's rows route nothing but Cooking's meat
-- and eggs (Gather.CookRows): the Farm picks and what the zone holds.
function GatherList.RouteRows(zone, items, wide, opts)
    local skills = Gather.Skills()
    if Gather.RouteFarming() then
        items = zone and Gather.CookRows(zone, skills, opts or GatherList.ZONE_OPTS) or {}
    elseif not items then
        local needs, soon = Gather.Needs()
        items = next(skills) and Gather.Rows(zone, skills, needs, have, nameOf, opts or GatherList.ZONE_OPTS, soon) or {}
    end
    local out = {}
    for _, r in ipairs(items) do
        local kept = {}
        for _, src in ipairs(r.sources or {}) do
            local skin = src.kind == "mob" and src.prof == Gather.SKINNING
            if not skin and Gather.GrindSource(r.itemID, src) and not Gather.RouteSkipped(src.name)
                and canGather(src, skills) then
                kept[#kept + 1] = src
            end
        end
        if #kept > 0 then
            local copy = setmetatable({ sources = kept }, { __index = r })
            out[#out + 1] = copy
        end
    end
    for _, r in ipairs(Gather.SkillRows(zone, skills, wide)) do out[#out + 1] = r end
    for _, r in ipairs(Gather.SkinRows(zone, skills, items)) do out[#out + 1] = r end
    return out
end

-- Why `zone` gets no skinning grind spot (Gather.SkinReason), from the same checklist
-- rows RouteRows builds for another zone. Nil when it gets one.
function GatherList.SkinReason(zone)
    local skills = Gather.Skills()
    local needs, soon = Gather.Needs()
    local items = next(skills) and Gather.Rows(zone, skills, needs, have, nameOf, GatherList.OTHER_OPTS, soon) or {}
    return Gather.SkinReason(zone, skills, items)
end

-- A new width for the list: its rows wrap again on the next frame.
function GatherList.SetWidth(w)
    if math.abs(GatherList.width - w) < 0.5 then return end
    GatherList.width = w
    f:SetWidth(w)
    GatherList.Changed()
end

-- Mounts the list in the gathering panel's body `c`.
function GatherList.Mount(c)
    host = c
    f:SetParent(c)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT")
    f:SetPoint("TOPRIGHT")
    f:Show()
    GatherList.empty = S.Text(c, "body", S.color.muted)
    GatherList.empty:SetPoint("TOPLEFT", 2, -headH() - 4)
    GatherList.empty:SetPoint("RIGHT")
    GatherList.empty:SetText(GatherList.EMPTY_NONE)
    c:HookScript("OnSizeChanged", function() GatherList.Changed() end)
end

-- Something the list shows changed. While the gathering panel shows, the list rebuilds
-- on the next frame. Otherwise it goes stale, and the panel rebuilds it the frame after
-- it opens (GatherPanel.Layout); a route on the map still follows the player, once a burst
-- of changes settles (ROUTE_QUIET, at most ROUTE_MOST after the first) and out of combat.
-- PLAYER_REGEN_ENABLED calls Changed again.
GatherList.stale = false
GatherList.ROUTE_QUIET, GatherList.ROUTE_MOST = 1, 3

function GatherList.Changed()
    if CP.GatherPanel and CP.GatherPanel.Showing() then return CP:Soon("gatherList", GatherList.Refresh) end
    GatherList.stale = true
    if GatherList.RouteOn() and not inCombat then
        CP:Later("gatherRoute", GatherList.ROUTE_QUIET, GatherList.ROUTE_MOST, GatherList.RouteOnly)
    end
end

-- What the folded panel's route was last built from (GatherList.RouteKey); nil builds again.
local routeKey

-- The zone's solve ended. The list rebuilds when its grind spots are not the ones drawn,
-- once per change: the new spots are noted here, so a rebuild that draws nothing new
-- can't ask for another.
GatherList.spotSig = ""

function GatherList.RouteSolved()
    routeShade()
    local _, sig = GatherList.SpotLines(GatherList.zone)
    if sig ~= GatherList.spotSig then
        GatherList.spotSig = sig
        GatherList.Changed()
    end
end

-- The watched patterns sold in the listed `zone`, as VendorWatch.current holds them ({ zone,
-- found }), or nil. Where the player stands they are its scan's; a picked zone's are looked up
-- the same way (VendorWatch.Find), while the vendor alerts are on.
function GatherList.Patterns(zone, here, away)
    local VW = CP.VendorWatch
    if not away then
        local current = VW.current
        return current and current.zone == here and current or nil
    end
    if not (zone and CP.db.vendorAlerts) then return nil end
    local found = VW.Find(zone, true)
    return #found > 0 and { zone = zone, found = found } or nil
end

-- The name of the zone or instance the player stands in, for a picked zone's note.
local function hereName(here, place)
    if here and Gather.IsInstance(here) then return (GetInstanceInfo()) end
    local info = here and C_Map.GetMapInfo(here)
    return info and info.name or place
end

-- Rebuild the list for the player's zone, or the zone they picked (GatherList.Where).
-- Returns true when it has rows to show.
function GatherList.Refresh()
    if not CP.db then return end
    GatherList.stale, routeKey = false, nil
    local zone, place, here, away, herePlace = GatherList.Where()
    local inst = Gather.IsInstance(zone)
    GatherList.place, GatherList.inside = place, inst
    GatherList.here, GatherList.away = here, away
    GatherList.hereName = away and hereName(here, herePlace) or nil
    local skills = zone and Gather.Skills() or {}
    local needs, soon = Gather.Needs()
    -- A lure or pole lifts the chance a bite lands, so the source lines read it too.
    local landSkills = skills
    local fishInfo = skills[Gather.FISHING] and CP.Professions.SkillLine(CP.Fishing.SKILL)
    if fishInfo and (fishInfo.modifier or 0) ~= 0 then
        landSkills = {}
        for id, rank in pairs(skills) do landSkills[id] = rank end
        landSkills[Gather.FISHING] = skills[Gather.FISHING] + fishInfo.modifier
    end
    local items = zone and next(skills) and Gather.Rows(zone, landSkills, needs, have, nameOf, GatherList.ZONE_OPTS, soon) or {}
    items = GatherList.Ticked(items)
    GatherList.zone = zone
    -- Farm shows what to farm here, and nothing from another zone: no fishing plan. One picked profession
    -- shows only its own sections.
    local farming = Gather.RouteFarming()
    local pick = GatherList.PanelProf()
    local fishing = not pick or pick == Gather.FISHING
    lines = GatherList.Lines(items, skills,
        zone and not inst and not farming and fishing and skills[Gather.FISHING] and fishPlan(zone))
    -- The vendor patterns are the listed zone's: VendorWatch's scan where the player stands, or
    -- the picked zone's own watched patterns.
    local current = GatherList.Patterns(zone, here, away)
    if current then
        local top = GatherList.PatternLines(current)
        for i = #top, 1, -1 do table.insert(lines, 1, top[i]) end
    end
    -- No game map inside an instance: no waypoints, no route.
    if inst then
        for _, line in ipairs(lines) do line.pin = nil end
    end
    lines = GatherList.Wrap(lines)
    local routeRows = zone and not inst and GatherList.RouteRows(zone, items, true) or {}
    CP.RouteMap.Update(#routeRows > 0 and zone, routeRows, GatherList.RouteSolved, away)
    head.route:SetShown(not inst)
    head.filter:SetShown(not inst)
    routeShade()
    if GatherList.empty then
        GatherList.empty:SetText(GatherList.EmptyText())
        GatherList.empty:SetShown(#lines == 0)
    end
    local name
    if inst then
        name = GetInstanceInfo()
    else
        local info = zone and C_Map.GetMapInfo(zone)
        name = info and info.name
    end
    GatherList.FitTitle(name or "Gathering", name or "Gathering")
    draw()
    return #lines > 0
end

-- What shapes the player's loop in `zone`, as RouteMap's own key reads it: the zone, the
-- level, the route filter, the gathering ranks and the items still needed (none in Farm).
-- Bag counts and item names that leave these as they were leave the route as it was.
function GatherList.RouteKey(zone, away)
    local parts = { zone, tostring(away or false), Gather.PlayerLevel(), Gather.RouteSignature() }
    local skills = Gather.Skills()
    for _, id in ipairs(Gather.PROFS) do parts[#parts + 1] = skills[id] or 0 end
    local ids = {}
    for item, n in pairs(not Gather.RouteFarming() and (Gather.Needs()) or {}) do
        if (have(item) or 0) < n then ids[#ids + 1] = item end
    end
    table.sort(ids)
    parts[#parts + 1] = table.concat(ids, ",")
    return table.concat(parts, ":")
end

-- The listed zone's loop alone (the player's, or the picked one), for a route on the map
-- while the panel is folded.
function GatherList.RouteOnly()
    if not CP.db or inCombat then return end
    local zone, _, _, away = GatherList.Where()
    local key = zone and GatherList.RouteKey(zone, away) or "none"
    if key == routeKey then return end
    routeKey = key
    local rows = zone and not Gather.IsInstance(zone) and GatherList.RouteRows(zone, nil, true) or {}
    CP.RouteMap.Update(#rows > 0 and zone, rows, routeShade, away)
end

-- Spawn or skinning answers starting over, or the route forgotten, build it again.
local function routeStale() routeKey = nil end
hooksecurefunc(Gather, "SkinChanged", routeStale)
hooksecurefunc(Gather, "ResetClusters", routeStale)
hooksecurefunc(CP.RouteMap, "Forget", routeStale)

-- Events -------------------------------------------------------------------------

local function soon() GatherList.Changed() end

CP:On("PLAYER_LOGIN", function() inCombat = InCombatLockdown() end)
CP:On("ProfLost_FONT", soon)   -- the font or text size: lines wrap again

-- A Better for you or Better to farm line waiting on a background search.
CP:On(CP.GatherGuide.WARM.signal, soon)
CP:On(CP.Farm.FOUND, soon)

-- Guide needs follow skill and training; re-plan a moment after they change. Changes
-- inside that moment share the one re-plan.
local replanning = false
local function replan()
    if replanning then return end
    replanning = true
    C_Timer.After(1, function()
        CP:Soon("gatherNeeds", function()
            replanning = false
            Gather.UpdateAllNeeds()
            GatherList.Changed()
        end)
    end)
end
CP:On("PLAYER_ENTERING_WORLD", replan)
CP:On("ProfLost_SKILLS", replan)

-- A new level opens zones and lifts level rows and rank warnings. The client can answer
-- UnitLevel with the old level during the event, so the level is read again a moment later.
-- Only a level that moved draws again; the crafting plan itself does not read it.
local drawnLevel
local function levelled()
    local level = CP.Gather.PlayerLevel()
    if level == drawnLevel then return end
    drawnLevel = level
    if CP.Panel then CP.Panel:Refresh() end
    if CP.Launcher then CP.Launcher.Update() end
    GatherList.Changed()
end
CP:On("PLAYER_LEVEL_UP", function()
    levelled()
    C_Timer.After(1, levelled)
    replan()
end)
-- While hushed, a watcher shows the window under the mouse and eases it out after. With
-- Daylight UI fading the window, it only keeps Daylight UI's hush on while the window
-- stands free.
local watcher = CreateFrame("Frame")
local function watch(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.2 then return end
    self.t = 0
    if not hushed() then
        self:SetScript("OnUpdate", nil)
        engineHush(false)
        fadeTo(1)
        return
    end
    if engine() then return engineHush(free() ~= nil) end
    local w = faded()
    if w then
        local want = w:IsMouseOver() and 1 or 0
        if want ~= fadeTarget then fadeTo(want) end
    end
end

local function updateSitting()
    local now = false
    for _, id in ipairs(SITTING) do
        if C_UnitAuras.GetPlayerAuraBySpellID(id) then now = true end
    end
    if now == sitting then return end
    sitting = now
    if not now then engineHush(false) end
    if hushed() then watcher:SetScript("OnUpdate", watch) end
end
GatherList.UpdateSitting = updateSitting
CP:On("UNIT_AURA", function(_, unit) if unit == "player" then updateSitting() end end)

CP:On("PLAYER_REGEN_DISABLED", function()
    inCombat = true
    if sitting then fadeTo(1) end   -- a fight lifts the hush
end)
CP:On("PLAYER_REGEN_ENABLED", function()
    inCombat = false
    if hushed() then watcher:SetScript("OnUpdate", watch) end
    soon()
end)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED", "ProfLost_SKILLS",
                       "PLAYER_MONEY", "NEW_RECIPE_LEARNED" }) do
    CP:On(event, soon)
end
-- Item names trickle in over many frames: one rebuild a burst, as the guide window's.
CP:On("ProfLost_ITEM_LOADED", function()
    CP:Later("gatherNames", CP.Panel.NAMES_QUIET, CP.Panel.NAMES_MOST, soon)
end)

-- A move within the zone: the header's place follows; a new zone rebuilds the list. While a
-- picked zone is listed, only the player entering it changes what the panel lists.
local function moved()
    if not CP.db then return end
    local zone, place = GatherList.Where()
    if zone ~= GatherList.zone then return GatherList.Changed() end
    if place ~= GatherList.place then
        GatherList.place = place
        GatherList.FitNote()
    end
end
GatherList.Moved = moved
CP:On("ZONE_CHANGED", moved)
CP:On("ZONE_CHANGED_INDOORS", moved)
