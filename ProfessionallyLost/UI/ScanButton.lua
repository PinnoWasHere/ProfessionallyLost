local _, CP = ...
if CP.stopped then return end

-- The Scan prices button on the auction house window. It hangs under the window's bottom
-- right corner as the window's child, so it moves, fades and raises with it and clicks
-- land. It fades in when the auction house opens and pulses until clicked, or while a
-- full scan within the cooldown already exists. While a scan runs it shows the progress
-- and a click stops it; during the cooldown it shows the minutes left.
--
-- The window: DaylightMogul's own (DaylightMogulMain) while it stands in for the auction
-- house, else the game's AuctionHouseFrame, dressed by Daylight UI's skins or not. Mogul
-- parks the game's frame at alpha 0, so a parked frame doesn't count. Read only.

local S, Scan = CP.Style, CP.Scan

local ScanButton = {
    LABEL = "Scan prices",
    MOGUL_WINDOW = "DaylightMogulMain",
    GAME_WINDOW = "AuctionHouseFrame",
    H = 26,
    GAP = 4,              -- below the window's edge
    CHECK_EVERY = 0.2,    -- seconds between looks for the window while the auction house is open
    SEEN_ALPHA = 0.05,    -- a window drawn fainter than this is parked out of sight
}
CP.ScanButton = ScanButton

local button, host, ticker
local clicked = false   -- clicked this visit: the pulse stops

local function seen(f)
    if type(f) ~= "table" or not (f.IsVisible and f:IsVisible()) then return false end
    local a = f.GetEffectiveAlpha and f:GetEffectiveAlpha() or f:GetAlpha()
    return type(a) ~= "number" or a > ScanButton.SEEN_ALPHA
end

-- Where the button goes: { kind, window }, or nil while no auction house window shows.
function ScanButton.Host()
    local mogul = rawget(_G, ScanButton.MOGUL_WINDOW)
    if seen(mogul) then return { kind = "Mogul window", window = mogul } end
    local game = rawget(_G, ScanButton.GAME_WINDOW)
    if seen(game) then return { kind = "game AuctionHouseFrame", window = game } end
    return nil
end

local function hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- The label: progress while a scan runs, the gradient name otherwise, minutes left
-- during the cooldown.
function ScanButton.Label()
    local progress = Scan.ProgressText()
    if progress then return progress end
    local left = Scan.CooldownLeft()
    local name = CP.Gradient(ScanButton.LABEL)
    if left > 0 then
        return ("%s  %s%d min|r"):format(name, hex(S.color.muted), math.max(1, math.ceil(left / 60)))
    end
    return name
end

-- True while the button should pulse: nothing runs, a full scan is allowed, and the
-- player hasn't clicked it this visit.
function ScanButton.Wants()
    return not clicked and not Scan.Running() and Scan.CooldownLeft() == 0
end

local function tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Scan auction prices", 1, 1, 1)
    if Scan.Running() then
        GameTooltip:AddLine(Scan.ProgressText() .. ". Click to stop.", 0.8, 0.8, 0.8, true)
    elseif Scan.FullAvailable() then
        GameTooltip:AddLine(("Reads the whole auction house at once and prices every item on it, not only the guides' materials (%s).")
            :format(Scan.Thousands(Scan.InterestCount())), 0.8, 0.8, 0.8, true)
        local left = Scan.CooldownLeft()
        if left > 0 then
            GameTooltip:AddLine(("Again in %d min: the game allows one full scan every %d min."):format(
                math.max(1, math.ceil(left / 60)), math.floor(Scan.config.cooldown / 60)), 1, 0.5, 0.4, true)
        end
    else
        GameTooltip:AddLine(Scan.config.noFullLine, 1, 0.5, 0.4, true)
    end
    if CP.Pricing.HasMogul() then
        GameTooltip:AddLine("DaylightMogul's prices come first; these fill the rest.", 0.6, 0.6, 0.6, true)
    end
    local last = Scan.LastTime()
    if last then
        local now = GetServerTime and GetServerTime() or time()
        GameTooltip:AddLine(("Last scan %s ago."):format(CP.Pricing.FormatAge(math.max(0, now - last))), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function ScanButton.Click()
    clicked = true
    S.Pulse(button, false)
    if Scan.Running() then return Scan.Stop() end
    local ok, why = Scan.Start()
    if not ok and why then CP:Print(why) end
end

local function make()
    local b = S.Button(UIParent, 80, ScanButton.H)
    b:Hide()
    b:SetScript("OnClick", ScanButton.Click)
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    button = b
    ScanButton.button = b
    return b
end

-- A child of the window, hanging under its bottom right corner, above its parts.
local function place(b, h)
    local w = h.window
    b:SetParent(w)
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", w, "BOTTOMRIGHT", 0, -ScanButton.GAP)
    b:SetFrameStrata(w:GetFrameStrata())
    b:SetFrameLevel(w:GetFrameLevel() + 30)
end

-- Shows the button on the auction house window, or hides it.
function ScanButton.Update()
    local h = Scan.open and ScanButton.Host() or nil
    if not h then
        host = nil
        if button then
            S.Pulse(button, false)
            button:Hide()
        end
        return
    end
    local b = button or make()
    local label = ScanButton.Label()
    if label ~= b.profLostLabel then
        b.profLostLabel = label
        b.label:SetText(label)
        b:SetWidth(CP.Panel.TextWidth(b.label) + S.BUTTON_PAD)
    end
    S.SetEnabled(b, Scan.Running() or Scan.CooldownLeft() == 0)
    local fresh = not (host and host.window == h.window) or not b:IsShown()
    if fresh then
        host = h
        place(b, h)
        S.FadeIn(b)
    end
    S.Pulse(b, ScanButton.Wants())
    if GameTooltip:GetOwner() == b then tooltip(b) end
end

-- The auction house window shows a frame or more after AUCTION_HOUSE_SHOW, and Mogul's
-- window can take its place: a look every CHECK_EVERY while it is open.
local function watch(on)
    if ticker then ticker:Cancel() end
    ticker = on and C_Timer.NewTicker(ScanButton.CHECK_EVERY, ScanButton.Update) or nil
end

CP:On("AUCTION_HOUSE_SHOW", function()
    clicked = false
    watch(true)
    ScanButton.Update()
end)

CP:On("AUCTION_HOUSE_CLOSED", function()
    watch(false)
    ScanButton.Update()
end)

Scan.OnChange(function() ScanButton.Update() end)
