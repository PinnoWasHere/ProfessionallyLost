local _, CP = ...
if CP.stopped then return end

-- ProfLost's launchers: the data text (any LibDataBroker display), the minimap button and
-- the addon compartment. All take the same clicks (Launcher.Click). The data text reads
-- the last profession and its next step; each tooltip lists every profession's next step.

local Launcher = {}
CP.Launcher = Launcher

local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
local ICON = CP.MEDIA .. "Icon"
local NAME = "Professionally Lost"

-- "Cooking 5", or the addon's name before any profession was opened. Short, so it fits a
-- narrow data-text slot; the tooltip has the next steps.
-- Gathering skills shown by name: they have a window but no crafting guide.
local GATHER_NAMES = { [393] = "Skinning", [186] = "Mining", [182] = "Herbalism", [356] = "Fishing" }
Launcher.GATHER_NAMES = GATHER_NAMES

function Launcher.Text()
    local key = CP.charDB and CP.charDB.lastProf
    if key and GATHER_NAMES[key] then
        local rank = CP.Gather.Skills()[key]
        return rank and ("%s %d"):format(GATHER_NAMES[key], rank) or NAME
    end
    local st = key and CP.charDB.nextStep and CP.charDB.nextStep[key]
    local guide = key and CP.Guides and CP.Guides[key]
    if not (st and guide) then return NAME end
    return ("%s %d"):format(guide.name, st.skill)
end

-- The open window's profession becomes the last one, gathering windows included.
function Launcher.Opened()
    local p = CP.Professions.IsOwn() and CP.Professions.Current()
    for _, id in ipairs(p and p.ids or {}) do
        if GATHER_NAMES[id] or (CP.Guides and CP.Guides[id]) then
            CP.charDB.lastProf = id
            Launcher.Update()
            return
        end
    end
end

-- Gathering skills have no craft window, so they come from the skill list: the rank,
-- then where the gathering guide sends the player next, or the rank to train.
-- { { name, skill, left = "Skinning 120", right = "Thousand Needles", warn } }.
local GATHER = { { 393, "Skinning" }, { 186, "Mining" }, { 182, "Herbalism" }, { 356, "Fishing" } }
local MAX_SKILL = 300

function Launcher.GatherLines()
    local G, GG = CP.Gather, CP.GatherGuide
    local skills = G.Skills()
    local out = {}
    for _, e in ipairs(GATHER) do
        local id, name = e[1], e[2]
        local skill = skills[id]
        if skill then
            local right, warn = "maxed", false
            if skill < MAX_SKILL and not GG.Ready(id) then
                -- The guide's zones build in the background; its signal redraws this.
                right = GG.WARM.waiting
                GG.Warm(id)
            elseif skill < MAX_SKILL then
                local max = G.MaxRank(id) or MAX_SKILL
                local nextUp = GG.Next(GG.PlayerRows(id, skill, max), skill, max)
                local zone = nextUp and nextUp.zone and C_Map.GetMapInfo(nextUp.zone)
                if nextUp and nextUp.train then
                    right, warn = "train " .. nextUp.train, true
                elseif zone and nextUp.level and nextUp.level > (G.PlayerLevel() or 0) then
                    right, warn = ("Level %d for %s"):format(nextUp.level, zone.name), true
                elseif zone and nextUp.zone == G.PlayerZone() then
                    right = "gather"
                elseif zone then
                    right = zone.name
                else
                    right = "gather"
                end
            end
            out[#out + 1] = { name = name, skill = skill, left = ("%s %d"):format(name, skill),
                              right = right, warn = warn }
        end
    end
    return out
end

local function itemName(id) return CP.ItemName(id) or ("item " .. id) end

-- Every profession's next step, then the gathering skills, on `tooltip`.
function Launcher.Steps(tooltip)
    local steps = CP.charDB and CP.charDB.nextStep or {}
    local any = false
    for key, saved in pairs(steps) do
        local st = CP.Gather.LiveStep(key, saved)
        local guide = CP.Guides and CP.Guides[key]
        if guide and st then
            any = true
            local need = CP.Gather.NeedText(st, itemName)
            local info = need or (st.learned and (st.bank and "ready with bank" or CP.Gather.ReadyText(st, guide)) or "learn it")
            local what = ("%s to %d"):format(st.name, st.to)
            -- At the cap: the rank to learn, not a craft.
            if st.rank then what, info = (CP.Guide.StopText({ rank = st.rank })), ("capped at %d"):format(st.max) end
            local warn = CP.Style.color.warn
            tooltip:AddDoubleLine(("%s %d: %s"):format(guide.name, st.skill, what), info,
                1, 1, 1, warn[1], warn[2], warn[3])
            -- A rank the skill has opened but the level can't train yet.
            if st.levelShort then tooltip:AddLine("  " .. st.levelShort.text, warn[1], warn[2], warn[3], true) end
        end
    end

    for _, g in ipairs(Launcher.GatherLines()) do
        any = true
        local c = g.warn and CP.Style.color.warn or CP.Style.color.muted
        tooltip:AddDoubleLine(g.left, g.right, 1, 1, 1, c[1], c[2], c[3])
    end
    if not any then
        local c = CP.Style.color.label
        tooltip:AddLine("Open a profession window once to see its next step.", c[1], c[2], c[3])
    end
end

-- The same clicks on every launcher: left shows or hides the guide window, Shift-left
-- the Gathering window, right opens the settings.
Launcher.CLICK_LINES = {
    "Left-click: show or hide the guide window.",
    "Shift-click: show or hide the Gathering window.",
    "Right-click: settings.",
}

function Launcher.Click(button)
    if button == "RightButton" then return CP.Panel:OpenSettings() end
    if IsShiftKeyDown() then
        if CP.GatherPanel then CP.GatherPanel.ToggleShown() end
        return
    end
    if CP.Window then CP.Window.Toggle() end
end

-- The click lines at the foot of a launcher's tooltip.
function Launcher.ClickHelp(tooltip)
    local c = CP.Style.color.muted
    for _, line in ipairs(Launcher.CLICK_LINES) do tooltip:AddLine(line, c[1], c[2], c[3]) end
end

local object
if ldb then
    object = ldb:NewDataObject("ProfLost", {
        type = "data source",
        label = "Professionally Lost",
        text = NAME,
        icon = ICON,
        OnClick = function(_, button) Launcher.Click(button) end,
        OnTooltipShow = function(tooltip)
            Launcher.Steps(tooltip)
            Launcher.ClickHelp(tooltip)
        end,
    })
end
Launcher.object = object

-- The minimap button, through LibDBIcon-1.0. Its place and hide flag are CP.db.minimap;
-- the "Minimap button" setting (CP.db.minimapButton) sets the flag. Daylight UI's
-- minimap drawer collects LibDBIcon buttons into its strip.
Launcher.ICON_NAME = "ProfLost"

local minimapObject = ldb and ldb:NewDataObject("ProfLost Guide window", {
    type = "launcher",
    label = "Professionally Lost guide window",
    icon = ICON,
    OnClick = function(_, button) Launcher.Click(button) end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine(CP.Gradient("Professionally Lost"))
        Launcher.ClickHelp(tooltip)
    end,
})
Launcher.minimapObject = minimapObject

local function dbicon() return LibStub and LibStub("LibDBIcon-1.0", true) end

-- Shows or hides the registered minimap button by its saved hide flag.
local function showByFlag()
    local lib = dbicon()
    if not (lib and lib:IsRegistered(Launcher.ICON_NAME)) then return end
    if CP.db.minimap.hide then lib:Hide(Launcher.ICON_NAME) else lib:Show(Launcher.ICON_NAME) end
end

-- Registers the minimap button, shown or hidden as its saved hide flag says, so a hide
-- holds across reloads. True once registered.
function Launcher.ShowMinimap()
    local lib = dbicon()
    if not (lib and minimapObject and CP.db) then return false end
    CP.db.minimap = CP.db.minimap or {}
    if CP.db.minimapButton == false then CP.db.minimap.hide = true end
    if not lib:IsRegistered(Launcher.ICON_NAME) then
        -- A failure here says so once in chat rather than breaking the login.
        local ok, err = pcall(lib.Register, lib, Launcher.ICON_NAME, minimapObject, CP.db.minimap)
        if not ok then
            if CP.BugReport and CP.BugReport.Record then CP.BugReport.Record("minimap button: " .. tostring(err)) end
            CP:Print("The minimap button isn't available. /proflost still opens the window.")
            return false
        end
    end
    showByFlag()
    return true
end

-- The "Minimap button" setting changed or arrived from Daylight UI: the hide flag follows it.
function Launcher.ApplyMinimap()
    if not CP.db then return end
    CP.db.minimap = CP.db.minimap or {}
    CP.db.minimap.hide = CP.db.minimapButton == false or nil
    showByFlag()
end

-- The addon compartment's entry (the .toc's AddonCompartmentFunc*). The game passes
-- the addon's name, then the mouse button or the menu button frame.

function ProfLost_Open(_, button)
    Launcher.Click(type(button) == "string" and button or "LeftButton")
end

function ProfLost_OnEnter(_, owner)
    GameTooltip:SetOwner(owner or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("Professionally Lost", 1, 1, 1)
    Launcher.Steps(GameTooltip)
    Launcher.ClickHelp(GameTooltip)
    GameTooltip:Show()
end

function ProfLost_OnLeave()
    GameTooltip_Hide()
end

function Launcher.Update()
    if object then object.text = Launcher.Text() end
end

CP:On("PLAYER_LOGIN", Launcher.Update)
CP:On("PLAYER_LOGIN", function() Launcher.ShowMinimap() end)
CP:On("ProfLost_SKILLS", Launcher.Update)
CP:On(CP.GatherGuide.WARM.signal, Launcher.Update)
CP:On("TRADE_SKILL_SHOW", Launcher.Opened)
CP:On("TRADE_SKILL_LIST_UPDATE", Launcher.Opened)
