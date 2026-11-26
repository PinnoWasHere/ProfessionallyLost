local _, CP = ...
if CP.stopped then return end

-- Which price addon to use, asked once while none is saved (a first install, or the first
-- login after the update that added the pick). Daylight UI's question box (Options/Widgets.lua
-- W.Ask) lists the price addons loaded now plus ProfLost's own scan as Daylight UI chips
-- (W.Chip), the best by Pricing.config.order lit. The box's button, Escape or its X saves the
-- lit one. Never in a fight: it waits for the fight's end. With only ProfLost's scan to pick,
-- or without Daylight UI's box, nothing is asked or saved and Pricing.config.order decides; the
-- question comes at a later login once there is a choice.

local PriceAsk = {}
CP.PriceAsk = PriceAsk

PriceAsk.KEY = "proflost:prices"
PriceAsk.TITLE = "Auction prices"
PriceAsk.TEXT = "The game lets one addon scan the auction house at a time. Pick the one Professionally Lost "
    .. "takes its prices from. The others fill gaps. You can change it in its settings, under Prices."
PriceAsk.YES = "Use this one"
PriceAsk.DELAY = 6      -- seconds after login, after What's New's note
PriceAsk.WIDTH = 420    -- the box's width (W.Ask `width`)
PriceAsk.EDGE = 16      -- the box's side margin when Daylight UI's Win.EDGE is missing
PriceAsk.GAP = 6        -- between chips
PriceAsk.CHIP_H = 24    -- a chip's height when it reports none

local waiting = false
local made = {}           -- Daylight UI's chips, made once each and reused

-- Daylight UI's widgets when the box and its chips are there, else nil.
local function widgets()
    local dui = rawget(_G, "DaylightUI")
    local W = type(dui) == "table" and dui.Widgets
    if type(W) == "table" and type(W.Ask) == "function" and type(W.Chip) == "function" then return W, dui end
    return nil
end

-- True while no pick is saved.
function PriceAsk.Due()
    return CP.db ~= nil and CP.Pricing.Choice() == nil
end

-- The picks to offer, in the options' order: each loaded now, and ProfLost's scan.
function PriceAsk.List()
    local out = {}
    for _, c in ipairs(CP.Pricing.Choices()) do
        if c.key == "scan" or CP.Pricing.Present(c.key) then out[#out + 1] = c end
    end
    return out
end

local function settle(key)
    if PriceAsk.Due() then CP.Pricing.Choose(key) end
end

-- The chips for `list`, sized and placed in rows `width` wide (each chip's offset in
-- priceX, priceY), the lit one `pick`. Returns the rows' height and a function giving the
-- pick now. They wait hidden until the box shows them.
local function chips(W, list, pick, width)
    for i, c in ipairs(list) do
        local b = made[i] or W.Chip(UIParent, c.label)
        made[i] = b
        b:Hide()
        b.text:SetText(c.label)
        b.priceKey = c.key
        if b.FitWidth then b.FitWidth() end
        b:SetScript("OnClick", function(self)
            pick = self.priceKey
            for k = 1, #list do
                if made[k].SetOn then made[k].SetOn(made[k].priceKey == pick) end
            end
        end)
    end
    for i = #list + 1, #made do made[i]:Hide() end
    local x, y, h = 0, 0, PriceAsk.CHIP_H
    for i = 1, #list do
        local b = made[i]
        local bh = b:GetHeight()
        if type(bh) == "number" and bh > 0 then h = bh end
        local w = b:GetWidth()
        if x > 0 and x + w > width then x, y = 0, y + h + PriceAsk.GAP end
        b.priceX, b.priceY = x, y
        if b.SetOn then b.SetOn(b.priceKey == pick) end
        x = x + w + PriceAsk.GAP
    end
    return y + h, function() return pick end
end

-- Opens the question, or saves the best when there is nothing to pick or no box.
function PriceAsk.Run()
    if not PriceAsk.Due() then return false end
    if InCombatLockdown() then
        waiting = true
        return false
    end
    local list = PriceAsk.List()
    local W, dui = widgets()
    if #list < 2 or not W then return false end
    local best = CP.Pricing.Best()
    local edge = type(dui.Win) == "table" and type(dui.Win.EDGE) == "number" and dui.Win.EDGE or PriceAsk.EDGE
    local height, picked = chips(W, list, best, PriceAsk.WIDTH - 2 * edge)
    local count = #list
    local function done() settle(picked()) end
    local ok = pcall(W.Ask, {
        key = PriceAsk.KEY, title = PriceAsk.TITLE, text = PriceAsk.TEXT, width = PriceAsk.WIDTH,
        yes = PriceAsk.YES, no = false, onYes = done, onClose = done,
        preview = {
            height = height,
            show = function(holder)
                for i = 1, count do
                    local b = made[i]
                    b:SetParent(holder)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", holder, "TOPLEFT", b.priceX, -b.priceY)
                    b:Show()
                end
            end,
            hide = function()
                for _, b in ipairs(made) do
                    b:Hide()
                    b:SetParent(UIParent)
                end
            end,
        },
    })
    if not ok then settle(best) end
    return ok
end

-- The chips made so far, shown or not.
function PriceAsk.Chips() return made end

-- Forgets a question held for a fight's end.
function PriceAsk.Reset() waiting = false end

CP:On("PLAYER_REGEN_ENABLED", function()
    if not waiting then return end
    waiting = false
    PriceAsk.Run()
end)

CP:On("PLAYER_LOGIN", function()
    C_Timer.After(PriceAsk.DELAY, PriceAsk.Run)
end)
