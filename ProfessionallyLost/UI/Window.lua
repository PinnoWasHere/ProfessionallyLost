local _, CP = ...
if CP.stopped then return end

-- The guide window, always free-standing: where it stands, when it shows (closed or not,
-- hideInCombat), folding and closing, and which profession it guides (the View switch
-- and the profession dropdown on the tab row).

local S, Prof = CP.Style, CP.Professions
local Panel, Host = CP.Panel, CP.Host
local panel = Panel.frame

local Window = { managed = { mover = false, fade = false } }
CP.Window = Window

local ICON = 16
local BAR_H = CP.Style.BUTTON_H   -- the tab row's buttons
local SWITCH_W, PICK_W = 56, 60   -- the least widths; labels widen them

-- Room around a tab-row button's label. Narrower than Daylight UI's own buttons (32),
-- so the View switch, the dropdown and the tabs share the 310 px row. A row too full for
-- the longest profession name takes ROW_PAD_LEAST instead.
Window.ROW_PAD, Window.ROW_PAD_LEAST = 20, 10

-- The gathering skills: a window and a gathering guide, no crafting guide.
local GATHER = CP.Launcher.GATHER_NAMES

-- Professions --------------------------------------------------------------------

-- Every guided profession the player has, by name: { { id, name, skill, modifier } }.
-- `skill` is the rank alone, as the launcher and the guide read it.
function Window.Professions()
    local out = {}
    if not (Prof.preview or (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID)) then return out end
    local function add(id, name)
        local info = Prof.SkillLine(id)
        local rank = info and not info.isHeader and (info.rank or 0) or 0
        if rank > 0 then out[#out + 1] = { id = id, name = name, skill = rank, modifier = info.modifier or 0 } end
    end
    for id, guide in pairs(CP.Guides or {}) do add(id, guide.name) end
    for id, name in pairs(GATHER) do
        if not (CP.Guides and CP.Guides[id]) then add(id, name) end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- True while the player's own profession window is open, whichever addon draws it. Its
-- data alone could outlast the window, so the game's trade skill must be open
-- (Prof.tradeSkillOpen) or Daylight UI's craft API must list a profession.
function Window.ProfessionOpen()
    if not Prof.IsOwn() then return false end
    return Prof.tradeSkillOpen or Host.DaylightWindow()
end

-- The open window's guided profession id, or nil.
-- A profession preview has no window of its own, so the player's open one never counts.
function Window.OpenID()
    if Prof.preview or not Window.ProfessionOpen() then return nil end
    local p = Prof.Current()
    for _, id in ipairs(p and p.ids or {}) do
        if (CP.Guides and CP.Guides[id]) or GATHER[id] then return id end
    end
    return p and p.id
end

function Window.Mode()
    return CP.charDB and CP.charDB.guideMode == "all" and "all" or "one"
end

-- A dropdown pick made while another profession's window is open: it holds until that
-- window closes or changes profession.
local override

-- The profession One mode shows: the open window's, else the saved pick, else the last
-- profession opened, else the first the player has.
function Window.ChosenID()
    local open = Window.OpenID()
    if open then
        if override and override.at == open then return override.id end
        return open
    end
    override = nil
    local list = Window.Professions()
    local has = {}
    for _, e in ipairs(list) do has[e.id] = true end
    local db = CP.charDB or {}
    return (db.guideProf and has[db.guideProf] and db.guideProf) or (db.lastProf and has[db.lastProf] and db.lastProf)
        or (list[1] and list[1].id)
end

-- The live plan for profession `id`: Plan.Current while its window is open, else Plan.Shut.
function Window.LiveFor(id)
    if not id then return nil end
    if id == Window.OpenID() then return CP.Plan.Current() end
    return CP.Plan.Shut(id)
end

-- One mode's plan, or nil when there is no profession to guide.
function Window.Live()
    return Window.LiveFor(Window.ChosenID())
end

-- All mode's plans, one per guided profession, by name.
function Window.AllLives()
    local out, seen = {}, {}
    for _, e in ipairs(Window.Professions()) do
        local live = Window.LiveFor(e.id)
        if live then
            out[#out + 1] = live
            seen[e.id] = true
        end
    end
    local open = Window.OpenID()
    if open and not seen[open] then
        local live = CP.Plan.Current()
        if live then table.insert(out, 1, live) end
    end
    return out
end

-- The profession a plan belongs to, as the switch and dropdown know it.
function Window.KeyOf(live)
    local p = live and live.prof
    for _, id in ipairs(p and p.ids or {}) do
        if (CP.Guides and CP.Guides[id]) or GATHER[id] then return id end
    end
    return p and p.id
end

-- Picks profession `id` for One mode and saves it.
function Window.Pick(id)
    if not (CP.charDB and id) then return end
    CP.charDB.guideMode = "one"
    CP.charDB.guideProf = id
    local open = Window.OpenID()
    override = (open and open ~= id) and { id = id, at = open } or nil
    Panel:Refresh()
end

function Window.SetMode(mode)
    if not CP.charDB then return end
    CP.charDB.guideMode = mode == "all" and "all" or "one"
    Panel:Refresh()
end

-- Visibility ---------------------------------------------------------------------

local inCombat = false
Window.opened = false   -- opened in a fight while hideInCombat hides it; stays for that fight
Window.byHand = false   -- opened by the player this session; shows while the guide is left to Glowey's Recipes

-- True when the player closed the free window. Saved: it stays shut through combat,
-- loading screens, profession windows closing and reloads, until the minimap button,
-- the launcher or /proflost opens it.
function Window.Closed()
    return CP.db ~= nil and CP.db.windowClosed == true
end

-- True while the hideInCombat setting hides the free window.
local function combatHidden()
    return inCombat and not (CP.db and CP.db.hideInCombat == false)
end
Window.CombatHidden = combatHidden

-- True while the gatherHideInCombat setting hides the detached gathering panel.
function Window.GatherCombatHidden()
    return inCombat and not (CP.db and CP.db.gatherHideInCombat == false)
end

-- True when the window should show now.
function Window.Wanted()
    if Window.Closed() then return false end
    if not Window.byHand and CP.Glowey and CP.Glowey.Handed("guide") then return false end
    return Window.opened or not combatHidden()
end

-- Placement ----------------------------------------------------------------------

-- The window hangs from this anchor's top-left, so folding keeps its top edge put. The
-- anchor has the window's unfolded size, so Daylight UI's mover shows the whole window
-- even while it is folded. The mover moves the anchor; without it the title bar drags it.
local anchor = CreateFrame("Frame", "ProfLost_WindowAnchor", UIParent)
Window.LEVEL = 5   -- the free window's least frame level: its shell and fold tab sit below it
anchor:SetSize(Panel.WIDTH, CP.DEFAULTS.windowHeight)
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)
Window.anchor = anchor

-- Beside the chat box, where the gathering checklist used to start.
function Window.DefaultPoint()
    return CP.GatherList.DefaultPoint()
end

function Window.PlaceAnchor()
    if Window.managed.mover then return end
    anchor:SetScale(Window.PieceScale())
    anchor:ClearAllPoints()
    local pt = CP.db and CP.db.windowPoint
    if pt then
        anchor:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        anchor:SetPoint(unpack(Window.DefaultPoint()))
    end
end

-- The most height of a view that sizes itself (the All view, the Shop and Disenchant tabs),
-- past which its lists scroll.
local function baseHeight()
    return CP.db and CP.db.windowHeight or CP.DEFAULTS.windowHeight
end

-- The screen's width and height in the anchor's units, or nil before the screen has a size.
local function screen()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
    local k = (UIParent:GetEffectiveScale() or 1) / (anchor:GetEffectiveScale() or 1)
    return w * k, h * k
end

-- The grip's least width: the gathering panel's, so the guide can match it edge to edge.
function Window.LeastWidth()
    return CP.GatherPanel and CP.GatherPanel.WIDTH or Panel.BASE_WIDTH
end

-- The player's width from the corner grip (CP.db.windowWidth), at least LeastWidth and at
-- most the screen's, or nil.
function Window.Width()
    local w = CP.db and CP.db.windowWidth
    if type(w) ~= "number" then return nil end
    local sw = screen()
    if sw then w = math.min(w, sw) end
    return math.floor(math.max(w, Window.LeastWidth()) + 0.5)
end

Panel.PlayerWidth = function() return Window.Width() end

-- True on the One view of the Guide tab, whose height is its step list's: "Steps shown" rows.
function Window.Listed()
    return Panel.current == "guide" and Window.Mode() ~= "all"
end

-- The window's unfolded height. The One view is as tall as its rows and the parts below
-- them, at most the screen's height; any other view at most baseHeight.
function Window.ExpandedHeight()
    local need = Window.Listed() and Panel.OpenHeight()
    if not need then return baseHeight() end
    local _, sh = screen()
    return math.floor((sh and math.min(need, sh) or need) + 0.5)
end

-- Sizes the free window to what its view needs, at most its unfolded height, past which
-- its lists scroll. A tab that can't say fills that height. The anchor keeps the unfolded
-- height, so Daylight UI's mover shows the window at its largest, but only the window's
-- own height keeps to the screen (Style.ClampTop), so it reaches the bottom edge.
function Window.Fit()
    local full = Window.ExpandedHeight()
    local left, top = anchor:GetLeft(), anchor:GetTop()
    local w0, h0 = anchor:GetSize()
    anchor:SetSize(Panel.WIDTH, full)
    Window.HoldTopLeft(left, top, w0 ~= Panel.WIDTH or h0 ~= full)
    if CP.db and Window.managed.mover then CP.db.windowAnchorSize = { Panel.WIDTH, full } end
    local need = Panel.folded and Panel.FoldedHeight() or Panel.OpenHeight()
    local h = need and math.min(need, full) or full
    panel:SetSize(Panel.WIDTH, h)
    Window.Clamp()
end

-- Puts the anchor's top-left back at `left`, `top` after a resize moved it, and saves the
-- spot. Daylight UI's mover holds the anchor by its centre, so a new size would move the
-- window's top and the panel beside it. A `resized` anchor saves even where it stands, since
-- the mover keeps its centre. The mover's save snaps that centre to a whole screen pixel and
-- places the anchor there, so the anchor takes the exact top-left again afterwards;
-- otherwise each change would add up to half a pixel.
Window.HOLD_SLACK = 0.001   -- px of top-left movement taken as none

function Window.HoldTopLeft(left, top, resized)
    if not (left and top) or Window.dragging then return end
    local l, t = anchor:GetLeft(), anchor:GetTop()
    if not (l and t) then return end
    local slack = Window.HOLD_SLACK
    local moved = math.abs(l - left) >= slack or math.abs(t - top) >= slack
    if not moved and not (resized and Window.managed.mover) then return end
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    if Window.SavePlace() then
        anchor:ClearAllPoints()
        anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
end

-- The anchor at its last fitted size (CP.db.windowAnchorSize). Daylight UI's mover places
-- it by the centre it saved at that size, so it takes the size before the mover places it.
function Window.SizeAnchor()
    local size = CP.db and CP.db.windowAnchorSize
    if type(size) ~= "table" or type(size[1]) ~= "number" or type(size[2]) ~= "number" then return end
    anchor:SetSize(size[1], size[2])
end

-- The free window's clamp: its shown height, widened on one side by the attached
-- gathering panel while it is out, so the pair stays on screen as one. A panel that
-- slides out past the screen's edge moves the window in.
function Window.Clamp()
    local left, right = 0, 0
    local reach, side = 0, nil
    if CP.GatherPanel then reach, side = CP.GatherPanel.Reach() end
    if side == "left" then left = reach elseif side == "right" then right = reach end
    S.ClampTop(anchor, panel:GetHeight(), left, right)
    Window.KeepOnScreen()
end

-- Moves the anchor sideways until its clamp rect (Style.ClampTop) is on screen. Daylight
-- UI's mover keeps its own place, and a drag clamps by itself. True when it moved.
function Window.KeepOnScreen()
    if Window.managed.mover or Window.dragging then return false end
    local l, r, top = anchor:GetLeft(), anchor:GetRight(), anchor:GetTop()
    if not (l and r and top) then return false end
    local screen = UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1) / (anchor:GetEffectiveScale() or 1)
    local cl, cr = l - (anchor.profLostClampLeft or 0), r + (anchor.profLostClampRight or 0)
    local dx = 0
    if cr > screen then dx = screen - cr end
    if cl + dx < 0 then dx = -cl end
    if math.abs(dx) < 0.5 then return false end
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l + dx, top)
    Window.SavePlace()
    return true
end

-- The corner grip ----------------------------------------------------------------------

-- The grip's least size: the gathering panel's width (Window.LeastWidth), and the One
-- view's height at one step. Daylight UI's grip reads this table at each press.
Window.GRIP_LIFT = 20   -- the grip's frame levels above the window
local gripMin = { Panel.BASE_WIDTH, CP.DEFAULTS.windowHeight }

-- The grip works while the window is unlocked, or while /dui unlock is on, as dragging does.
function Window.Resizable()
    if InCombatLockdown() then return false end
    return not Window.Locked() or CP.GatherPanel.Unlocked()
end

-- The panel hangs from the anchor's top-left again after Daylight UI's grip held it.
local function hang()
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", anchor, "TOPLEFT", CP.GatherList.TalkOffset(anchor), 0)
end

-- True while the grip's vertical drag sets "Steps shown": the unfolded One view.
local function stepping()
    return Window.Listed() and not Panel.folded
end

-- The One view's height without its step list.
local function listless()
    return (Panel.OpenHeight() or 0) - CP.GuideTab.ListHeight()
end

-- The Steps shown whose list height (GuideTab.GripHeight) lies nearest `list` px. A tie
-- takes the larger count, as a half row rounds up.
function Window.StepsFor(list)
    local s = CP.Settings.Find("guideSteps")
    local best, gap
    for n = s.min, s.max, s.step do
        local d = math.abs(CP.GuideTab.GripHeight(n) - list)
        if not gap or d <= gap then best, gap = n, d end
    end
    return best
end

-- The window at the player's new size `w` x `h`. The width stays within the grip's bounds
-- and the screen's edge past its top-left, saved in CP.db.windowWidth. An attached gathering
-- panel out on the right keeps its room, so the pair stays put. On the unfolded One view the
-- height sets "Steps shown" to the steps whose rows come nearest it, a step with its "or"
-- rows; elsewhere it changes nothing.
-- `live` while the corner is dragged; at the drop the window hangs from its anchor again
-- and redraws.
function Window.Resize(w, h, live)
    if not CP.db or not Window.Resizable() then return end
    local sw = screen()
    local left = anchor:GetLeft()
    local reach, side = CP.GatherPanel.Reach()
    if side == "right" then sw = sw and sw - reach end
    local least = Window.LeastWidth()
    w = math.max(least, w)
    if sw and type(left) == "number" then w = math.max(least, math.min(w, sw - left)) end
    CP.db.windowWidth = math.floor(w + 0.5)
    if stepping() then
        local g = Window.grab
        local list = g and CP.GuideTab.GripHeight(g.n) + h - g.h or h - listless()
        CP.db.guideSteps = Window.StepsFor(list)
    end
    if live then return Window.Chrome() end
    Window.Dropped()
end

-- The grip's press: the steps and the height it starts from, so a drag past k steps' rows
-- changes "Steps shown" by k even while the guide has fewer steps than that.
function Window.GripStart()
    Window.grab = { n = CP.GuideTab.Steps(), h = panel:GetHeight() or 0 }
end

-- The grip's drop. "Steps shown" is saved where its slider saves it; the window hangs from
-- its anchor again and redraws.
function Window.Dropped()
    Window.grab = nil
    if stepping() then CP.Settings.Save("guideSteps", CP.GuideTab.Steps()) end
    hang()
    Panel:Refresh()
end

-- The grip's right-click: back to the width the window takes by itself and the default steps.
function Window.ResetSize()
    if not CP.db or not Window.Resizable() then return end
    CP.db.windowWidth = nil
    CP.Settings.Save("guideSteps", CP.DEFAULTS.guideSteps)
    hang()
    Panel:Refresh()
end

-- Daylight UI's window grip (Style.Grip), as the detached gathering panel's.
local grip = S.Grip(panel, {
    min = gripMin,
    start = function() Window.GripStart() end,
    resized = function(w, h) Window.Resize(w, h, true) end,
    done = function() Window.Dropped() end,
    reset = function() Window.ResetSize() end,
})
Window.grip = grip

-- Shows the grip while it works, over /dui unlock's handles while that is on, and sets
-- its least size.
function Window.SyncGrip()
    gripMin[1] = Window.LeastWidth()
    gripMin[2] = stepping() and listless() + CP.GuideTab.GripHeight(1) or (panel:GetHeight() or 0)
    grip:SetShown(Window.Resizable())
    local up = CP.GatherPanel.Unlocked()
    grip:SetFrameStrata(up and "FULLSCREEN" or (panel:GetFrameStrata() or S.WINDOW_STRATA))
    grip:SetFrameLevel((panel:GetFrameLevel() or 0) + Window.GRIP_LIFT)
end

-- Daylight UI's mover sizes the anchor (its master scale times the mouse wheel over the
-- handle in /dui unlock); the free window and its gathering panel take the same scale.
function Window.Scale()
    local s = anchor:GetScale()
    return (type(s) == "number" and s > 0) and s or 1
end

-- Text measures differently at each scale, since glyphs round to whole screen pixels, so a
-- new scale lays the window out again on the next frame, as a fold and unfold does. The
-- next frame also lets Daylight UI's mover place the anchor at its new scale first.
local drawnScale = Window.Scale()

function Window.Rescaled()
    local s = Window.Scale()
    if math.abs(s - drawnScale) < 0.0001 then return end
    drawnScale = s
    CP:Soon("guideScale", function() Panel:Refresh() end)
end

hooksecurefunc(anchor, "SetScale", function()
    panel:SetScale(Window.Scale())
    Window.Rescaled()
end)

-- The options' "Guide window scale" and "Gathering panel scale": each window's own size.
-- With Daylight UI's mover it is the mover's piece scale, the value its mouse wheel sets in
-- /dui unlock (Movers.PieceScale and Movers.SetPieceScale, general.frameScales). Without it,
-- CP.db.guideScale or CP.db.gatherScale on the window's anchor.
Window.SCALE_MIN, Window.SCALE_MAX, Window.SCALE_STEP = 0.5, 2, 0.05

function Window.Movers()
    local addon = rawget(_G, "DaylightUI")
    local M = type(addon) == "table" and addon.Movers
    if type(M) == "table" and type(M.PieceScale) == "function" and type(M.SetPieceScale) == "function" then return M end
end

-- The piece scale kept for `moverKey` (when `managed`) or in CP.db[dbKey].
function Window.ReadScale(managed, moverKey, dbKey)
    local M = managed and Window.Movers()
    if M then return M.PieceScale(moverKey) end
    local v = CP.db and CP.db[dbKey]
    return type(v) == "number" and v or 1
end

-- Snaps `v` to the slider's steps and keeps it where ReadScale reads it. Returns the value
-- kept, or nil when it went to the mover (which scales the anchor itself) or nowhere.
function Window.WriteScale(managed, moverKey, dbKey, v)
    v = math.floor(math.max(Window.SCALE_MIN, math.min(Window.SCALE_MAX, v)) / Window.SCALE_STEP + 0.5)
        * Window.SCALE_STEP
    local M = managed and Window.Movers()
    if M then M.SetPieceScale(moverKey, v) return nil end
    if not CP.db then return nil end
    CP.db[dbKey] = math.abs(v - 1) > 0.001 and v or nil
    return v
end

function Window.PieceScale()
    return Window.ReadScale(Window.managed.mover, Window.MOVER_KEY, "guideScale")
end

function Window.SetPieceScale(v)
    v = Window.WriteScale(Window.managed.mover, Window.MOVER_KEY, "guideScale", v)
    if v then anchor:SetScale(v) end
end

-- Stands the panel at the anchor, in its strata. Its frame level is the client's: a click
-- raises it, and Window.Release raises it as it comes out of hiding.
function Window.Place()
    if panel:GetFrameStrata() ~= CP.Style.WINDOW_STRATA then panel:SetFrameStrata(CP.Style.WINDOW_STRATA) end
    panel:SetToplevel(true)
    panel:SetScale(Window.Scale())
    panel:SetAlpha(1)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", anchor, "TOPLEFT", CP.GatherList.TalkOffset(anchor), 0)
    Window.Chrome()
end

-- True while combat holds the panel still. Nothing in it is secure (the disenchant button
-- lives under UIParent), but should something make it protected, it neither moves nor
-- hides until the fight ends.
function Window.Held()
    return InCombatLockdown() and panel:IsProtected()
end

-- Shows or hides the window by Window.Wanted.
function Window.Release()
    if not (CP.db and panel) or Window.Held() then return end
    if Window.Wanted() then
        -- A window already standing keeps its drawing; one coming out of hiding redraws.
        local standing = panel:IsShown()
        Window.Place()
        panel:Show()
        if not standing then
            CP.Style.Front(panel, Window.LEVEL)
            Panel:Refresh()
        end
    else
        panel:Hide()
    end
end

-- Re-applies the visibility setting. A detached gathering panel follows the same setting
-- on its own.
function Window.Update()
    Window.Release()
    if CP.GatherPanel then CP.GatherPanel.Update() end
end

function Window.Open()
    if CP.db then CP.db.windowClosed = nil end
    Window.opened = combatHidden()
    Window.byHand = true
    Window.Update()
end

function Window.Close()
    if CP.db then CP.db.windowClosed = true end
    Window.opened = false
    Window.byHand = false
    Window.Update()
end

-- The minimap button, the launcher's left-click and /proflost: open or close the window.
function Window.Toggle()
    if panel:IsShown() then
        Window.Close()
    else
        Window.Open()
    end
end

-- Open -------------------------------------------------------------------------

-- A Craft button for a profession whose window is shut, or shows another profession,
-- reads Open. It opens that window, then selects the step's recipe once the window shows.
-- Open never crafts.

-- Seconds a pick waits for its window before it lapses.
Window.PICK_SECONDS = 5

-- While a pick waits in Daylight UI's window, Land retries this often: that window can
-- open before its recipe list, and its later re-read tells plugins nothing.
Window.PICK_POLL = 0.1

-- Seconds after a pick lands in Daylight UI's window during which a selection change
-- that window makes on its own is put back, at most GUARD_TRIES times.
Window.GUARD_SECONDS, Window.GUARD_TRIES = 1, 2

-- OpenTradeSkill needs a hardware event but carries no combat flag, so Open works in combat.
-- False greys Open in combat with OPEN_COMBAT_TIP.
Window.OPEN_IN_COMBAT = true
Window.OPEN_COMBAT_TIP = "Can't open a profession window in combat"
Window.OPEN_BUSY_TIP = "Wait for the batch to finish"

local pick    -- { id, recipe, at } while a pick waits for its window
local guard   -- { id, prof, ends, tries } after a pick landed in Daylight UI's window
local poller

-- Trace ----------------------------------------------------------------------------

-- Hidden: /proflost trace open on|off prints each step of an Open to chat, timed from the
-- click, until TRACE_AFTER seconds after the pick lands or lapses. On for this session only.
Window.TRACE_AFTER = 3
local traceFrom, traceUntil = 0, 0

local function tracing()
    return CP.trace.open == true and GetTime() <= traceUntil
end

function Window.Trace(fmt, ...)
    if not tracing() then return end
    CP.TraceLine("open", GetTime() - traceFrom, fmt, ...)
end
local trace = Window.Trace

-- What the game, the guide window and Daylight UI's window say now, which window the
-- player sees, and why Daylight UI's reports nothing.
local function report()
    local cur = Prof.Current()
    local why = Host.DaylightWhy()
    return ("game %s, guide %s, Daylight %s%s, window %s, list changing %s"):format(tostring(cur and cur.id),
        tostring(Window.OpenID()), tostring(Host.CraftProfession()), why and (" (" .. why .. ")") or "",
        tostring(Host.Holder()), tostring(Prof.Changing()))
end

-- A trace line followed by what everyone reports; reads nothing while the trace is off.
local function traceState(fmt, ...)
    if not tracing() then return end
    trace(fmt .. "; " .. report(), ...)
end

-- The first `count` calls outside this file that led here, one per line, for the open
-- trace. The leading frames in Window.lua and the client's own are skipped.
Window.TRACE_STACK = 3
Window.STACK_DEPTH = 24
local function callers(count)
    local stack
    if type(debugstack) == "function" then
        stack = debugstack(1, Window.STACK_DEPTH, 0)
    elseif debug and debug.traceback then
        stack = debug.traceback("", 1)
    end
    local out, leading = {}, true
    for line in tostring(stack or ""):gmatch("[^\n]+") do
        line = line:gsub("^%s+", ""):gsub("Interface[\\/]AddOns[\\/]", "")
        local own = line:find("Window.lua", 1, true) or line:find("^%[C%]") or line:find("^stack traceback")
        if not (own and leading) and line ~= "" and #out < count then
            leading = false
            out[#out + 1] = line
        end
    end
    return out
end

-- The game blocked a call of ours (ADDON_ACTION_BLOCKED or _FORBIDDEN, raised inside
-- the call): with the open trace on, chat names it and the calls that led there.
Window.BLOCK_STACK = 10
local function blocked(event, addon, fn)
    if addon ~= CP.name or not CP.trace.open then return end
    CP.TraceLine("open", GetTime() - traceFrom, "%s: %s", event, tostring(fn))
    for _, line in ipairs(callers(Window.BLOCK_STACK)) do print("    " .. line) end
end
CP:On("ADDON_ACTION_BLOCKED", blocked)
CP:On("ADDON_ACTION_FORBIDDEN", blocked)

function Window.SetTrace(on)
    CP.SetTracing("open", on)
    CP:Print("Open trace " .. (on and "on: click Open and paste what follows." or "off."))
end

-- Picks ----------------------------------------------------------------------------

-- True when crafting profession `id` needs its window opened first.
function Window.NeedsOpen(id)
    return id ~= nil and Window.OpenID() ~= id
end

-- Why Open can't run now, or nil.
function Window.OpenBlocked()
    if not Window.OPEN_IN_COMBAT and InCombatLockdown() then return Window.OPEN_COMBAT_TIP end
    if CP.Crafting.Busy() then return Window.OPEN_BUSY_TIP end
    return nil
end

local function stopPoll()
    if poller then poller:Cancel() end
    poller = nil
end

-- The pick waiting for its window, or nil once it landed or lapsed.
function Window.PendingPick()
    if pick and GetTime() - pick.at > Window.PICK_SECONDS then
        traceState("the pick lapsed after %d s", Window.PICK_SECONDS)
        traceUntil = GetTime() + Window.TRACE_AFTER
        pick = nil
    end
    if not pick then stopPoll() end
    return pick
end

function Window.CancelPick()
    pick, guard = nil, nil
    stopPoll()
end

-- True when Daylight UI's window lists another profession than the game has open: its
-- list hasn't refilled yet, so a selection now would miss.
local function daylightBehind()
    if not Host.DaylightWindow() then return false end
    local cur = Prof.Current()
    return not (cur and Host.CraftProfession() == cur.id)
end

local function spend(p)
    pick = nil
    stopPoll()
    traceUntil = GetTime() + Window.TRACE_AFTER
    -- An Open pick moves the guide to its step; a row's pick already stands there.
    if p.recipe and not p.row then
        Panel:Refresh()
        if CP.GuideTab.Follow then CP.GuideTab.Follow(p.recipe) end
    end
    return true
end

-- Selects the waiting pick's recipe once its profession's window shows. True when the
-- pick is spent. `why` names what called (an event, "poll"), for the trace.
-- Daylight UI's window takes the pick through SelectCraftRecipe. That window can open
-- before its recipe list arrives, so a refusal waits for the list, unless the game says
-- the recipe isn't learned. While Daylight UI's window is on, the pick waits for it and
-- never goes to the game's hidden window. DaylightMogul's window takes it only through
-- a select call of its own; without one the pick ends with the window open. The game's
-- window takes OpenRecipe, on an event only: its own first selection comes before ours.
-- The recipe is the guide's id; the live plan's alias gives the player's own spell.
function Window.Land(why)
    why = why or "land"
    local p = Window.PendingPick()
    if not p then return false end
    if Window.OpenID() ~= p.id then
        traceState("%s: waiting for profession %s", why, tostring(p.id))
        return false
    end
    if not p.recipe then return spend(p) end
    local live = CP.Plan.Current()
    local id = live and live.alias and live.alias[p.recipe] or p.recipe
    if Host.DaylightWindow() then
        if daylightBehind() then
            traceState("%s: Daylight UI's list is behind", why)
            return false
        end
        local ok = Host.SelectRecipe(id)
        traceState("%s: SelectCraftRecipe(%d) -> %s", why, id, tostring(ok))
        if ok then
            guard = { id = id, prof = p.id, ends = GetTime() + Window.GUARD_SECONDS, tries = 0 }
        elseif Prof.RecipeLearned(id) == false then
            trace("recipe %d isn't learned: nothing to select", id)
        else
            return false
        end
        return spend(p)
    end
    if Host.DaylightOwns() then
        traceState("%s: waiting for Daylight UI's window", why)
        return false
    end
    if Host.MogulOwns() then
        if not Host.MogulCanSelect() then
            trace("%s: DaylightMogul's window has no call to select recipe %d; it keeps its own pick", why, id)
            return spend(p)
        end
        local ok = Host.SelectRecipe(id)
        trace("%s: DaylightMogul select(%d) -> %s", why, id, tostring(ok))
        if ok or Prof.RecipeLearned(id) == false then return spend(p) end
        return false
    end
    if why == "poll" then return false end
    Prof.Open(id)
    trace("%s: OpenRecipe(%d) in the game's window", why, id)
    return spend(p)
end

-- Daylight UI's window picked `recipeID` (CraftRecipeSelected). Shortly after a pick
-- landed there, a change that window made on its own goes back to the pick.
function Window.DaylightSelected(recipeID)
    trace("Daylight selected %s", tostring(recipeID))
    local g = guard
    if not g or recipeID == g.id then return end
    if GetTime() > g.ends or g.tries >= Window.GUARD_TRIES or Host.CraftProfession() ~= g.prof then
        guard = nil
        return
    end
    g.tries = g.tries + 1
    C_Timer.After(0, function()
        if guard ~= g then return end
        trace("selecting %d again: %s", g.id, tostring(Host.SelectRecipe(g.id)))
    end)
end

-- Opens profession `id`'s window, then selects guide recipe `recipe` when it shows.
-- `row`: a step row's click, whose row the guide keeps. False when Open is blocked or
-- the game refused.
-- OpenTradeSkill needs the click's hardware event. Callers run this first in their
-- OnClick, before any refresh hides or rebuilds the clicked button.
function Window.OpenTo(id, recipe, row)
    if not id or Window.OpenBlocked() then return false end
    if CP.Preview and CP.Preview.Refuse("open") then return false end
    if not (C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill) then return false end
    pick, guard = { id = id, recipe = recipe, at = GetTime(), row = row and true or nil }, nil
    traceFrom, traceUntil = GetTime(), GetTime() + Window.PICK_SECONDS + Window.TRACE_AFTER
    traceState("Open profession %s, recipe %s", tostring(id), tostring(recipe))
    local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, id)
    if tracing() then
        trace("OpenTradeSkill -> %s %s", tostring(ok), tostring(opened))
        for _, line in ipairs(callers(Window.TRACE_STACK)) do print("    from " .. line) end
    end
    if not ok or opened == false then
        pick = nil
        return false
    end
    stopPoll()
    poller = C_Timer.NewTicker(Window.PICK_POLL, function()
        if Window.PendingPick() and (Host.DaylightOwns() or Host.MogulOwns()) then Window.Land("poll") end
    end)
    Window.LandSoon("click")
    return true
end

-- Selects guide recipe `recipe` in profession `id`'s window, already open on it: a step
-- row's click. It lands as Open's pick does, waiting for Daylight UI's list when that
-- lags. The row keeps its own pick in the guide. True when it landed at once.
function Window.SelectIn(id, recipe)
    if not (id and recipe) or Window.OpenID() ~= id then return false end
    pick, guard = { id = id, recipe = recipe, at = GetTime(), row = true }, nil
    traceFrom, traceUntil = GetTime(), GetTime() + Window.PICK_SECONDS + Window.TRACE_AFTER
    traceState("Row pick %s in profession %s", tostring(recipe), tostring(id))
    stopPoll()
    if Window.Land("row") and not pick then return true end
    poller = C_Timer.NewTicker(Window.PICK_POLL, function()
        if Window.PendingPick() then Window.Land("poll") end
    end)
    return false
end

-- Lands a frame after the window's event, so the window's own first selection comes
-- before ours. The event can come before the window shows: one more try 0.2 s later, while
-- a pick still waits.
function Window.LandSoon(why)
    if not Window.PendingPick() then return end
    C_Timer.After(0, function()
        if not Window.Land(why) and Window.PendingPick() then
            C_Timer.After(0.2, function() Window.Land(why) end)
        end
    end)
end

for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_CLOSE" }) do
    CP:On(event, function()
        traceState(event)
        if event ~= "TRADE_SKILL_CLOSE" then Window.LandSoon(event) end
    end)
end

-- Following the guide ----------------------------------------------------------------

-- One mode follows the open profession window, whichever profession it shows and however
-- it opened (keybind, spellbook, a menu, a tab inside the window): the guide's chosen
-- profession becomes the window's. Only the guide changes. The window is never switched,
-- because OpenTradeSkill outside a click is blocked. A dropdown pick made while the window
-- is open holds until the window closes or shows another profession.

local follow = { seen = nil }
Window.follow = follow

-- Drops what the follow remembers, as a fresh login starts. The test worlds call it
-- between scenes.
function Window.ForgetFollow()
    follow.seen, override = nil, nil
end

-- The guide takes the open window's profession, once each time that window's profession
-- changes. True when the guide's choice changed.
function Window.Follow(why)
    local open = Window.OpenID()
    if open == follow.seen then return false end
    follow.seen = open
    if not open or Window.Mode() ~= "one" or not CP.charDB then return false end
    if override and override.at ~= open then override = nil end
    if CP.charDB.guideProf == open then return false end
    CP.charDB.guideProf = open
    trace("%s: the guide follows the open window to %s", tostring(why), tostring(open))
    Panel.Changed()
    return true
end

for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_LIST_UPDATE" }) do
    CP:On(event, function()
        Window.Follow(event)
        -- The window can show a frame after its event.
        C_Timer.After(0, function() Window.Follow("next frame") end)
    end)
end
CP:On("TRADE_SKILL_CLOSE", function()
    follow.seen, override = nil, nil
end)

-- Combat greys or frees Open when OPEN_IN_COMBAT is off.
local function combatChanged()
    if not Window.OPEN_IN_COMBAT then Panel.Changed() end
end
CP:On("PLAYER_REGEN_DISABLED", combatChanged)
CP:On("PLAYER_REGEN_ENABLED", combatChanged)

-- Title bar ----------------------------------------------------------------------

-- Close: hides the window until the player opens it again, saved (Window.Close).
-- Daylight UI's own close X (API.Close) in a 16 px box; a plain "x" without it.
local closeBtn = S.Close(panel, function() Window.Close() end, ICON)
Window.closeButton = closeBtn

-- Folded or not, per mode: One mode keeps CP.db.windowCollapsed (default open), All
-- mode CP.db.windowCollapsedAll (default folded: the title bar and the cards).
function Window.Folded()
    if not CP.db then return false end
    if Window.Mode() == "all" then return CP.db.windowCollapsedAll ~= false end
    return CP.db.windowCollapsed == true
end

function Window.SetFolded(on)
    if Window.Mode() == "all" then
        CP.db.windowCollapsedAll = on and true or false
    else
        CP.db.windowCollapsed = on and true or nil
    end
    Window.Chrome()
    Panel:Refresh()
end

-- Fold: the window drops its tab row and step list, keeps the Guide header and the
-- current step (All mode: the cards), and keeps its top edge.
local foldBtn = S.FoldButton(panel, ICON, function() Window.SetFolded(not Window.Folded()) end)
Window.foldButton = foldBtn

-- Lock: unlocked, the title bar drags the free window. Saved in CP.db.windowLocked. It
-- locks the guide window only; the detached gathering panel has its own.
function Window.Locked()
    return CP.db ~= nil and CP.db.windowLocked == true
end

local lockBtn

-- Escape: the game's CloseSpecialWindows hides every shown frame named in UISpecialFrames.
-- A hidden proxy frame named there is shown while `want()` is true. The game also runs
-- CloseSpecialWindows on its own: entering the world (login, /reload, a loading screen),
-- losing control and full-screen panels all call CloseAllWindows. So a hide of the proxy
-- only marks it, and the player's Escape (the ToggleGameMenu post-hook) runs `onEscape`,
-- the close button's own handler, so the close is saved. A mark the hook doesn't take is
-- dropped on the next frame, and the proxy shows again. Our own show and hide of the proxy
-- raise `syncing` and mark nothing. Returns the function that re-reads `want`.
local escapes = {}

function Window.EscapeProxy(name, want, onEscape)
    local esc = CreateFrame("Frame", name, UIParent)
    esc:Hide()
    tinsert(UISpecialFrames, name)
    local syncing, marked = false, false
    local sync
    local function drop()
        marked = false
        sync()
    end

    -- A parent's hide (Alt+Z hides UIParent) leaves the proxy shown and marks nothing.
    esc:SetScript("OnHide", function(self)
        if syncing or self:IsShown() or marked then return end
        marked = true
        C_Timer.After(0, drop)
    end)
    sync = function()
        local on = want() and true or false
        if on == esc:IsShown() then return end
        syncing = true
        if on then esc:Show() else esc:Hide() end
        syncing = false
    end
    escapes[#escapes + 1] = function()
        if not marked then return end
        marked = false
        onEscape()
    end
    return sync, esc
end

-- The player's Escape runs ToggleGameMenu; entering the world never does.
if type(ToggleGameMenu) == "function" then
    hooksecurefunc("ToggleGameMenu", function()
        for _, take in ipairs(escapes) do take() end
    end)
end

Window.EscSync, Window.escFrame = Window.EscapeProxy("ProfLost_GuideEscape",
    function() return panel:IsShown() and not Window.Locked() end,
    function() Window.Close() end)
panel:HookScript("OnShow", Window.EscSync)
panel:HookScript("OnHide", Window.EscSync)

-- The detached gathering panel's proxy (GatherPanel loads first, so it is built here). The
-- panel calls Window.GatherEscSync when its mode or padlock changes.
local GP = CP.GatherPanel
Window.GatherEscSync, Window.gatherEscFrame = Window.EscapeProxy("ProfLost_GatherEscape",
    function() return not GP.Attached() and GP.sheet:IsShown() and not GP.Locked() end,
    function() GP.Close() end)
GP.sheet:HookScript("OnShow", Window.GatherEscSync)
GP.sheet:HookScript("OnHide", Window.GatherEscSync)

lockBtn = S.LockButton(panel, ICON, Window.Locked, function()
    CP.db.windowLocked = not Window.Locked() or nil
    Window.EscSync()
    Window.SyncGrip()
end)
Window.lockButton = lockBtn

-- The profession dropdown, in One mode, and the View switch sit on the right of the tab
-- row. Both are Daylight UI's Talents window's Builds button: its plain button
-- (API.Button) opening its menu (API.Menu), the game's context menu without it. A click
-- while the menu is open only closes it, whichever menu closes on the mouse going down first.
local pickBtn = S.Button(panel, PICK_W, BAR_H)
S.OneLine(pickBtn.label)
pickBtn:SetScript("OnClick", function(self) Window.MenuClick(self) end)
local pressed = pickBtn:GetScript("OnMouseDown")   -- the button's own pressed look
pickBtn:SetScript("OnMouseDown", function(self, ...)
    if pressed then pressed(self, ...) end
    Window.MenuDown()
end)
Window.pickButton = pickBtn

-- Single / All: one click flips the view. Both words show, the current one lit and the
-- other greyed beside it.
Window.VIEW_WORDS = { one = "Single", all = "All" }

local function ink(c, text)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5), text)
end

-- The switch's label for `mode`: "Single  All" with `mode`'s word lit.
function Window.ViewLabel(mode)
    local one = mode == "one" and S.color.title or S.color.muted
    local all = mode == "all" and S.color.title or S.color.muted
    return ink(one, Window.VIEW_WORDS.one) .. "  " .. ink(all, Window.VIEW_WORDS.all)
end

local switchBtn = S.Button(panel, SWITCH_W, BAR_H)
switchBtn:SetScript("OnClick", function()
    Window.SetMode(Window.Mode() == "all" and "one" or "all")
end)
Window.switchButton = switchBtn

-- The gathering panel's two buttons, left of the fold. The first shows and hides the panel
-- (/proflost gather). The second attaches the panel to the guide or detaches it, as the
-- "Attach to guide window" setting does, and shows only while the panel shows.
-- Daylight UI's header icon buttons (Style.IconButton), ours without it.
Window.GATHER_ICONS = { daylight = "ui-data-location.png", own = CP.GatherList.ROUTE_ICON }
Window.ATTACH_ICONS = { daylight = "ui-swap.png", own = CP.MEDIA .. "SideArrow" }
Window.GATHER_LABEL = "Gathering window"
Window.ATTACH_LABELS = { attach = "Attach to the guide", detach = "Detach from the guide" }

function Window.AttachLabel()
    return GP.Attached() and Window.ATTACH_LABELS.detach or Window.ATTACH_LABELS.attach
end

local function tip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local gatherBtn, attachBtn
gatherBtn = S.IconButton(panel, { icon = Window.GATHER_ICONS.daylight, own = Window.GATHER_ICONS.own,
    art = CP.GatherList.ROUTE_ICON, size = ICON, box = ICON,
    onClick = function() GP.ToggleShown() end,
    tip = function(self) tip(self, Window.GATHER_LABEL) end })
Window.gatherButton = gatherBtn

-- Flips the attach setting, saved and applied the way the options page does (Settings.Save).
function Window.ToggleAttached()
    CP.Settings.Save("gatherAttached", not GP.Attached())
    if attachBtn and GameTooltip:GetOwner() == attachBtn then tip(attachBtn, Window.AttachLabel()) end
end

attachBtn = S.IconButton(panel, { icon = Window.ATTACH_ICONS.daylight, own = Window.ATTACH_ICONS.own,
    size = ICON, box = ICON, onClick = function() Window.ToggleAttached() end,
    tip = function(self) tip(self, Window.AttachLabel()) end })
Window.attachButton = attachBtn

-- Title bar, right to left: close, bug, lock, fold, gathering, attach. Tab row, right to left: View, dropdown.
table.insert(Panel.titleButtons, 1, { button = closeBtn })
Panel:AddTitleButton(lockBtn)
Panel:AddTitleButton(foldBtn)
Panel:AddTitleButton(gatherBtn)
Panel:AddTitleButton(attachBtn, function() return GP.Showing() end, true)
Panel:AddRowButton(switchBtn)
Panel:AddRowButton(pickBtn, function() return Window.Mode() == "one" end)

-- The menu ------------------------------------------------------------------------

-- Blizzard_Menu's element-description and menu methods, called by name like GatherList's
-- route menu: Blizzard UI code the API database doesn't index.
local MENU = { title = "CreateTitle", radio = "CreateRadio", close = "Close" }
local DAYLIGHT = "DaylightUI"   -- the addon's global; its open menu's owner is Widgets.menuOwner

local menu = { frame = nil, hooked = {}, closedAt = -1, downAt = -1, downOpen = false }
Window.menu = menu

-- True while the profession menu is open. Daylight UI's menu says through its owner;
-- the game's through its frame.
function Window.MenuOpen()
    if menu.daylight then
        local addon = rawget(_G, DAYLIGHT)
        local W = type(addon) == "table" and addon.Widgets
        return type(W) == "table" and W.menuOwner == pickBtn
    end
    local m = menu.frame
    return m ~= nil and type(m.IsShown) == "function" and m:IsShown() == true
end

-- The menu went. `own`: we closed it, so no click of the player's closed it.
local function closed(own)
    if not own then menu.closedAt = GetTime() end
    pickBtn.SetOn(false)
end

-- While the menu is open, the button stays lit; it rests when the menu goes.
local watch = CreateFrame("Frame")
watch:Hide()
watch:SetScript("OnUpdate", function(self)
    if Window.MenuOpen() then return end
    self:Hide()
    closed()
end)

function Window.CloseMenu()
    if menu.daylight then
        local addon = rawget(_G, DAYLIGHT)
        local W = type(addon) == "table" and addon.Widgets
        if type(W) == "table" and type(W.CloseMenu) == "function" then W.CloseMenu() end
    elseif menu.frame then
        local close = menu.frame[MENU.close]
        if type(close) == "function" then close(menu.frame) else menu.frame:Hide() end
    end
    watch:Hide()
    closed(true)
end

-- The mouse went down on the dropdown: remember whether its menu was open then.
function Window.MenuDown()
    menu.downAt, menu.downOpen = GetTime(), Window.MenuOpen()
end

-- A click on the dropdown. It opens the menu only when the menu was shut as the click
-- began: a menu that closed on this click's mouse-down (the same frame) stays closed.
function Window.MenuClick(owner)
    local wasOpen = Window.MenuOpen() or menu.downOpen or menu.closedAt == menu.downAt
    menu.downOpen, menu.downAt = false, -1
    if wasOpen then
        if Window.MenuOpen() then Window.CloseMenu() end
        return
    end
    Window.Menu(owner)
end

-- A dropdown line's number: the rank, with a skill modifier apart in brackets, "75 (+10)".
local function skillText(e)
    return e.modifier ~= 0 and ("%d (%+d)"):format(e.skill, e.modifier) or tostring(e.skill)
end

-- Opens the profession menu under `owner`.
function Window.Menu(owner)
    local chosen = Window.ChosenID()
    local list = Window.Professions()
    local API = S.Daylight()
    menu.daylight = API ~= nil and type(API.Menu) == "function"
    if menu.daylight then
        local keys, values = {}, {}
        for _, e in ipairs(list) do
            keys[#keys + 1] = e.id
            values[e.id] = ("%s  %s"):format(e.name, skillText(e))
        end
        API.Menu(owner, keys, values, chosen, function(id) Window.Pick(id) end, owner:GetWidth())
    else
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        menu.frame = MenuUtil.CreateContextMenu(owner, function(_, root)
            if type(root[MENU.radio]) ~= "function" then return end
            root[MENU.title](root, "Profession")
            for _, e in ipairs(list) do
                root[MENU.radio](root, ("%s  %s"):format(e.name, skillText(e)),
                    function(id) return id == chosen end, function(id) Window.Pick(id) end, e.id)
            end
        end)
        local m = menu.frame
        if type(m) == "table" and type(m.HookScript) == "function" and not menu.hooked[m] then
            menu.hooked[m] = true
            m:HookScript("OnHide", function(self) if self == menu.frame then closed() end end)
        end
    end
    if Window.MenuOpen() then
        pickBtn.SetOn(true)
        watch:Show()
    end
end

-- Layout ---------------------------------------------------------------------------

-- Every name the dropdown can show: each guide's and each gathering skill's.
local function pickNames()
    local out = {}
    for _, guide in pairs(CP.Guides or {}) do out[#out + 1] = guide.name end
    for _, name in pairs(GATHER) do out[#out + 1] = name end
    return out
end

-- A button wide enough for the widest of `labels` in its own font plus `pad`, at least
-- `least`. Its label never truncates.
local function widthFor(button, labels, pad, least)
    local label, keep = button.label, button.label:GetText()
    local w = least
    for _, text in ipairs(labels) do
        w = math.max(w, Panel.TextWidth(label, text) + pad)
    end
    label:SetText(keep or "")
    label:SetWidth(w - pad)
    button:SetWidth(w)
end

-- The widest of `labels` in `button`'s font.
local function widest(button, labels)
    local label, keep, w = button.label, button.label:GetText(), 0
    for _, text in ipairs(labels) do w = math.max(w, Panel.TextWidth(label, text)) end
    label:SetText(keep or "")
    return w
end

-- Sizes the switch and the dropdown for their longest labels in the current font, and
-- the window for its title bar and tab row (Panel.ApplyWidth). The row gives way in this
-- order: the tabs drop to their least padding, then both buttons to ROW_PAD_LEAST. In a
-- window the player made narrower than that, the dropdown takes the room the tabs and
-- the switch leave and its name ends in "...". The row's need counts the tabs even while
-- folded, so folding keeps the width and the dropdown's.
function Window.SizeTitle()
    local views, names = { Window.ViewLabel("one"), Window.ViewLabel("all") }, pickNames()
    local sw, pw = widest(switchBtn, views), widest(pickBtn, names)
    local function need(pad) return math.max(SWITCH_W, sw + pad) + math.max(PICK_W, pw + pad) end
    local edges = Panel.ROW_EDGE + 2 * Panel.ROW_GAP
    Panel.SetNeed("row", Panel.TabsLeast(true) + edges + need(Window.ROW_PAD_LEAST))
    Panel.SetNeed("title", Panel.TitleNeed())
    Panel.ApplyWidth()
    local room = Panel.WIDTH - Panel.TabsLeast() - edges
    local pad = need(Window.ROW_PAD) <= room and Window.ROW_PAD or Window.ROW_PAD_LEAST
    widthFor(switchBtn, views, pad, SWITCH_W)
    widthFor(pickBtn, names, pad, PICK_W)
    local left = math.floor(Panel.WIDTH - Panel.TabsLeast(true) - edges - switchBtn:GetWidth())
    if pickBtn:GetWidth() > left then
        local w = math.max(PICK_W, left)
        pickBtn.label:SetWidth(w - pad)
        pickBtn:SetWidth(w)
    end
end

-- What the title bar and the frame show for folded or open, All or One.
function Window.Chrome()
    if not CP.db then return end
    Panel.SetFolded(Window.Folded())
    Window.SizeTitle()
    Window.Fit()
    foldBtn.mark:SetOpen(not Panel.folded)
    lockBtn.Sync()
    Window.SyncGrip()
    local all = Window.Mode() == "all"
    switchBtn.label:SetText(Window.ViewLabel(all and "all" or "one"))
    if not all then
        local id = Window.ChosenID()
        local name
        for _, e in ipairs(Window.Professions()) do
            if e.id == id then name = e.name end
        end
        pickBtn.label:SetText(name or (CP.Guides and id and CP.Guides[id] and CP.Guides[id].name) or GATHER[id] or "None")
    elseif Window.MenuOpen() then
        Window.CloseMenu()
    end
    Panel.Layout()
    Panel.LayoutTitle()
    if CP.GatherPanel then CP.GatherPanel.Layout() end
end

-- Dragging ---------------------------------------------------------------------------

-- Daylight UI's mover key for the window's anchor (API.lua prefixes a plugin's keys).
Window.MOVER_KEY = "plugin.ProfLost.checklist"

-- Saves where the anchor stands: into Daylight UI's mover when it places the window
-- (Movers.Save, the same call its own drag makes), else CP.db.windowPoint.
function Window.SavePlace()
    if Window.managed.mover then
        local addon = rawget(_G, DAYLIGHT)
        local Movers = type(addon) == "table" and addon.Movers
        if type(Movers) == "table" and type(Movers.Save) == "function" then
            local ok = pcall(Movers.Save, Window.MOVER_KEY, true)
            if ok then return true end
        end
    end
    local point, _, relPoint, x, y = anchor:GetPoint(1)
    if point then CP.db.windowPoint = { point, relPoint, x, y } end
    return false
end

-- The title bar, and the gathering panel's own surface (Window.Draggable), drag the
-- window and its panel as one while it is unlocked, out of combat.
local moving = false

function Window.DragStart()
    if Window.Locked() or InCombatLockdown() then return end
    moving, Window.dragging = true, true
    anchor:StartMoving()
end

function Window.DragStop()
    if not moving then return end
    moving, Window.dragging = false, false
    anchor:StopMovingOrSizing()
    Window.SavePlace()
    if CP.GatherPanel then CP.GatherPanel.Layout() end
end

-- Lets `frame` start a drag of the window, or run `start` and `stop` instead. Its child
-- buttons keep their own clicks.
function Window.Draggable(frame, start, stop)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", start or Window.DragStart)
    frame:SetScript("OnDragStop", stop or Window.DragStop)
end

local drag = CreateFrame("Frame", nil, panel)
drag:SetPoint("TOPLEFT")
drag:SetPoint("TOPRIGHT")
drag:SetHeight(Panel.TITLE_H)
drag:SetFrameLevel(panel:GetFrameLevel() + 1)
Window.Draggable(drag)
Window.drag = drag

-- Over the logo and title, the drag handle also opens the settings on a right-click, and
-- its tooltip says so. The left button still drags.
Window.TITLE_TIP = "Right click to open settings"

function Window.OverTitle()
    if Panel.logo:IsMouseOver() then return true end
    return Panel.title:IsShown() and Panel.title:IsMouseOver() or false
end

function Window.TitleTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(CP.Gradient(Panel.TITLE_FULL), 1, 1, 1)
    local c = S.color.muted
    GameTooltip:AddLine(Window.TITLE_TIP, c[1], c[2], c[3])
    GameTooltip:Show()
end

drag:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and Window.OverTitle() then Panel:OpenSettings() end
end)
drag:SetScript("OnEnter", Window.TitleTip)
drag:SetScript("OnLeave", GameTooltip_Hide)

-- The gathering panel drags the window while attached, itself while detached.
if CP.GatherPanel then Window.Draggable(CP.GatherPanel.sheet, CP.GatherPanel.DragStart, CP.GatherPanel.DragStop) end

-- The title bar's controls sit above the drag handle.
for _, t in ipairs(Panel.titleButtons) do t.button:SetFrameLevel(panel:GetFrameLevel() + 5) end

-- Events -------------------------------------------------------------------------

CP:On("PLAYER_LOGIN", function()
    inCombat = InCombatLockdown()
    Window.PlaceAnchor()
end)
CP:On("PLAYER_ENTERING_WORLD", function() Window.Update() end)
CP:On("PLAYER_REGEN_DISABLED", function()
    inCombat = true
    Window.Update()
end)
-- Out of combat it shows anyway, so an opening in combat has done its job.
CP:On("PLAYER_REGEN_ENABLED", function()
    inCombat = false
    Window.opened = false
    if CP.GatherPanel then CP.GatherPanel.opened = false end
    Window.Update()
end)
