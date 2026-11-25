local _, CP = ...
if CP.stopped then return end

-- Crafts in flight from the player's last Craft click. While a batch runs, tabs swap
-- their craft buttons for a strip: "Making 3 of 15", a progress bar and Stop, as
-- Daylight UI's own profession window does.

local Prof = CP.Professions
local S = CP.Style
local Crafting = { count = 0, total = 0 }
CP.Crafting = Crafting

local function set(n)
    if Crafting.count == n then return end
    if n == 0 then Crafting.stepEnd, Crafting.stepCount, Crafting.stepKeeps, Crafting.recipe = nil, nil, nil, nil end
    Crafting.count = n
    CP:Soon("refresh", function() CP.Panel:Refresh() end)
end

function Crafting.Busy()
    return Crafting.count > 0
end

-- The step a batch started on, set by the step card while the batch runs: its end skill, its
-- count and whether later steps keep its crafts. Once the step is done, further crafts of it give
-- no skill, so the card says to stop (decision 0008, rule 6).
Crafting.OVERSHOOT = "This step is done (skill %d). Stop the batch."

-- Whether the running batch makes the step's recipe `spell` (or its `alias`). A batch whose
-- recipe is unknown counts as the step's own.
function Crafting.IsBatchOf(spell, alias)
    local id = Crafting.recipe
    if id == nil or spell == nil then return true end
    return id == spell or (alias ~= nil and alias[spell] == id)
end

function Crafting.Track(stepEnd, count, keeps, spell, alias)
    if not Crafting.Busy() then
        Crafting.stepEnd, Crafting.stepCount, Crafting.stepKeeps = nil, nil, nil
    elseif Crafting.stepEnd == nil and type(stepEnd) == "number" and Crafting.IsBatchOf(spell, alias) then
        Crafting.stepEnd = stepEnd
        Crafting.stepCount = type(count) == "number" and count or nil
        Crafting.stepKeeps = keeps and true or nil
    end
end

-- True while a batch runs and its step is done: `skill` has reached the step's end and the step
-- keeps nothing, or this batch's crafts have reached the step's count. A step whose crafts later
-- steps keep is not done at its end while its count is unmet.
function Crafting.Overshoot(skill)
    if not (Crafting.Busy() and Crafting.stepEnd ~= nil and type(skill) == "number") then return false end
    if skill >= Crafting.stepEnd and not Crafting.stepKeeps then return true end
    return Crafting.stepCount ~= nil and Crafting.Progress() >= Crafting.stepCount
end

-- The card's warning line for `skill`, or nil.
function Crafting.OvershootText(skill)
    if Crafting.Overshoot(skill) then return Crafting.OVERSHOOT:format(skill) end
end

-- The skill the guide window shows for the open profession, or nil.
local function skillNow()
    local live = CP.GuideTab and CP.GuideTab.ui and CP.GuideTab.ui.live
    return live and live.prof and live.prof.skill
end

-- Our strip shows only for our own batches; Daylight UI's window shows its own.
function Crafting.ShowStrip()
    return Crafting.count > 0 and not Crafting.daylight
end

-- Craft `count` of a learned recipe. Only called from a player's button click.
function Crafting.Start(recipeID, count)
    if not recipeID or not count or count <= 0 then return end
    if CP.Preview and CP.Preview.Refuse("craft") then return end
    Prof.Open(recipeID)
    Prof.Craft(recipeID, count)
    Crafting.daylight = nil
    Crafting.stepEnd, Crafting.stepCount, Crafting.stepKeeps = nil, nil, nil
    Crafting.count, Crafting.total = count, count
    Crafting.recipe = recipeID
    CP.Panel:Refresh()
end

-- How far the batch is: made, total.
function Crafting.Progress()
    return Crafting.total - Crafting.count, Crafting.total
end

-- How much of the craft being cast is done, 0 to 1.
function Crafting.CastShare()
    local _, _, _, from, to = UnitCastingInfo("player")
    if issecretvalue and (issecretvalue(from) or issecretvalue(to)) then return 0 end
    if type(from) ~= "number" or type(to) ~= "number" or to <= from then return 0 end
    return math.max(0, math.min(1, (GetTime() * 1000 - from) / (to - from)))
end

-- Only the game's own code can stop a cast, so Stop is a secure "/stopcasting" button
-- laid over the visible one. With Daylight UI loaded it is the kit's Win.Caster; else a
-- SecureActionButtonTemplate on UIParent (never a child of our panel, which would make
-- the panel protected). Both change only out of combat.
local STOP_MACRO = "/stopcasting"
local NAME = "ProfLost_StopCast"

-- Ends the game's repeat if it has one. The visible button's own click does only this
-- (it cannot stop the cast in hand); the secure overlay's click does the rest.
function Crafting.StopRepeat()
    if StopTradeSkillRepeat then StopTradeSkillRepeat() end
end

-- The batch is over: clear it.
function Crafting.Stop()
    Crafting.StopRepeat()
    set(0)
end

local function daylightCaster()
    local addon = rawget(_G, "DaylightUI")
    local Win = type(addon) == "table" and addon.Win
    return type(Win) == "table" and type(Win.Caster) == "function" and Win.Caster or nil
end

-- A secure overlay, `spec`: name (the button's global name), macro (the macro text a
-- click runs), post(row) after a click, and hover (true: it leaves with the mouse, out of
-- combat). o.Over(row, macro) lays it over `row`, with another macro when given;
-- o.Hide() takes it away. Both change only out of combat.

-- Daylight UI's caster, wrapped to our one-call shape.
local function kitOverlay(make, spec)
    local c = make({ name = spec.name,
        above = function() return CP.Panel and CP.Panel.frame end,
        enter = function(row) if row.Hover then row.Hover(true) end end,
        leave = function(row) if row.Hover then row.Hover(false) end end,
        post = function(row) spec.post(row) end })
    local o = {}
    function o.Over(row, macro)
        local b = c.Over(row, { type1 = "macro", macrotext1 = macro or spec.macro })
        o.button = c.button
        return b
    end
    function o.Hide() c.Hide() end
    return o
end

-- Our own button. A change asked for in combat waits for PLAYER_REGEN_ENABLED.
local function plainOverlay(spec)
    local o, b, want, macro = {}, nil, nil, nil

    local function apply()
        if InCombatLockdown() then return end
        if not want then
            if b then b:Hide() end
            return
        end
        if not b then
            b = CreateFrame("Button", spec.name, UIParent, "SecureActionButtonTemplate")
            b:Hide()
            b:RegisterForClicks("LeftButtonUp")
            b:SetAttribute("useOnKeyDown", false)
            b:SetAttribute("type", "macro")
            b:SetScript("OnEnter", function() if want and want.Hover then want.Hover(true) end end)
            b:SetScript("OnLeave", function()
                if want and want.Hover then want.Hover(false) end
                if spec.hover and not InCombatLockdown() then o.Hide() end
            end)
            b:SetScript("PostClick", function() spec.post(want) end)
            o.button = b
        end
        b:SetAttribute("macrotext", macro or spec.macro)
        local left, bottom, w, h = want:GetLeft(), want:GetBottom(), want:GetWidth(), want:GetHeight()
        if not (left and bottom and w and h) then
            b:Hide()
            return
        end
        local k = want:GetEffectiveScale() / UIParent:GetEffectiveScale()
        b:SetFrameStrata(want:GetFrameStrata())
        b:SetFrameLevel(want:GetFrameLevel() + 20)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * k, bottom * k)
        b:SetSize(w * k, h * k)
        b:Show()
    end

    function o.Over(row, m)
        want, macro = row, m
        apply()
    end
    function o.Hide()
        want = nil
        apply()
    end
    CP:On("PLAYER_REGEN_ENABLED", apply)
    -- Still allowed here; a shown secure button would act on any click in a fight.
    CP:On("PLAYER_REGEN_DISABLED", function() if b then b:Hide() end end)
    return o
end

-- The overlay for `spec` for this session's Daylight UI (or ours without it), one per name.
Crafting.overlays = {}

function Crafting.SecureOverlay(spec)
    local make = daylightCaster()
    local have = Crafting.overlays[spec.name]
    if not have or have.make ~= (make or false) then
        have = { make = make or false, overlay = make and kitOverlay(make, spec) or plainOverlay(spec) }
        Crafting.overlays[spec.name] = have
    end
    return have.overlay
end

local STOP = { name = NAME, macro = STOP_MACRO, post = function() Crafting.Stop() end }

local function overlay()
    Crafting.overlay = Crafting.SecureOverlay(STOP)
    return Crafting.overlay
end
Crafting.Overlay = overlay

-- Where the Stop overlay was last laid.
local laid = {}

-- Lays the Stop overlay over `stop` when it isn't there: on a batch's first frame, after
-- Stop moves, resizes or changes strata or level, and after the overlay hid (combat, the
-- mouse leaving it, the strip hiding). Out of combat only, as the overlay changes.
-- With two strips up, the overlay stays on the Stop it covers while that one shows.
function Crafting.Follow(stop)
    if InCombatLockdown() then return end
    local o = overlay()
    local b = o.button
    local shown = b and b:IsShown() and laid.o == o
    if shown and laid.stop ~= stop and laid.stop:IsVisible() then return end
    local left, bottom, w, h = stop:GetLeft(), stop:GetBottom(), stop:GetWidth(), stop:GetHeight()
    local k, strata, level = stop:GetEffectiveScale(), stop:GetFrameStrata(), stop:GetFrameLevel()
    if shown and laid.stop == stop and laid.left == left and laid.bottom == bottom
        and laid.w == w and laid.h == h and laid.k == k and laid.strata == strata and laid.level == level then
        return
    end
    o.Over(stop)
    laid.o, laid.stop, laid.left, laid.bottom, laid.w, laid.h = o, stop, left, bottom, w, h
    laid.k, laid.strata, laid.level = k, strata, level
end

-- The progress strip, sized by its parent's anchors. `strip:Update()` refreshes it.
-- `opts` (optional): height, stop (Stop's width), text (its text size); the step
-- card's sizes without it.
Crafting.STRIP = { height = 22, stop = 72, text = "body" }

function Crafting.Strip(parent, opts)
    local o = opts or Crafting.STRIP
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(o.height)
    strip.stop = S.Button(strip, o.stop, o.height)
    strip.stop:SetPoint("RIGHT")
    strip.stop.label:SetText("Stop")
    strip.stop:SetScript("OnClick", Crafting.StopRepeat)
    strip.text = S.Text(strip, o.text)
    strip.text:SetPoint("LEFT", 2, 0)
    strip.bar = S.AccentBar(strip)
    strip.bar:SetPoint("LEFT", strip.text, "RIGHT", 12, 0)
    strip.bar:SetPoint("RIGHT", strip.stop, "LEFT", -12, 0)
    strip.bar:SetMinMaxValues(0, 1)

    -- The text changes only with the count or the accent; the bar moves every frame.
    function strip:Update()
        local made, total = Crafting.Progress()
        local accent = S.color.accent
        local r, g, b = accent[1], accent[2], accent[3]

        -- The one in progress, counting from 1.
        local now = math.min(made + 1, total)
        if now ~= self.now or total ~= self.total or r ~= self.r or g ~= self.g or b ~= self.b then
            self.now, self.total, self.r, self.g, self.b = now, total, r, g, b
            local hex = ("%02x%02x%02x"):format(r * 255, g * 255, b * 255)
            self.text:SetText(("Making |cff%s%d|r of |cff%s%d|r"):format(hex, now, hex, total))
        end
        self.bar:SetValue(total > 0 and (made + Crafting.CastShare()) / total or 0)

        -- Past the step's end, Stop is the main action.
        S.Urge(self.stop, Crafting.Overshoot(skillNow()))
    end

    -- Fills across each cast, as Daylight UI's own bar does.
    strip:SetScript("OnUpdate", function(self)
        if Crafting.Busy() then
            self:Update()
            Crafting.Follow(self.stop)
        end
    end)
    strip:SetScript("OnHide", function(self)
        if Crafting.overlay and (laid.stop == self.stop or not laid.stop) then Crafting.overlay.Hide() end
    end)
    strip:Hide()
    return strip
end

-- A batch from Daylight UI's own Create button: its events drive the strip, and the
-- game's cast events below stand aside until it stops.
function Crafting.UseDaylight(me)
    if not (me and type(me.On) == "function") then return false end
    me.On("CraftStarted", function(recipeID, count)
        if type(count) ~= "number" or count <= 0 then return end
        Crafting.recipe = recipeID
        Crafting.daylight = true
        Crafting.total = count
        set(count)
    end)
    me.On("CraftMade", function(_, done, count)
        if not Crafting.daylight or type(done) ~= "number" or type(count) ~= "number" then return end
        Crafting.total = count
        set(math.max(count - done, 0))
    end)
    me.On("CraftStopped", function()
        if not Crafting.daylight then return end
        Crafting.daylight = nil
        set(0)
    end)
    return true
end

-- Each finished craft counts down.
CP:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
    if Crafting.daylight then return end
    if unit == "player" and Crafting.count > 0 then set(Crafting.count - 1) end
end)

-- A cast ended: if nothing follows it shortly, the batch is over.
CP:On("UNIT_SPELLCAST_STOP", function(_, unit)
    if Crafting.daylight or unit ~= "player" or Crafting.count == 0 then return end
    C_Timer.After(0.5, function()
        if not UnitCastingInfo("player") then set(0) end
    end)
end)

local function done(_, unit)
    if Crafting.daylight or (unit and unit ~= "player") then return end
    set(0)
end
CP:On("UPDATE_TRADESKILL_CAST_STOPPED", done)
CP:On("UNIT_SPELLCAST_INTERRUPTED", done)
CP:On("UNIT_SPELLCAST_FAILED", done)
-- The window closing ends any batch, Daylight UI's too.
CP:On("TRADE_SKILL_CLOSE", function()
    Crafting.daylight = nil
    set(0)
end)
