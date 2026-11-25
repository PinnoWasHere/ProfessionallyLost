-- daylightworld: Daylight UI's plugin API (DaylightUI.API 1.3), as its API.md describes it.
-- Interface only; none of its code.
--
-- Modelled from the API notes:
--   * [docs] DaylightUI:RegisterPlugin / RegisterModule, API.For(name) -> `me` with On,
--     RegisterMover, RegisterFade, RegisterCommand, RegisterSkin, RegisterTestPart,
--     AddOptionsGroup, AddDefaults, Paint, AttachCraftPane; API.On / Off, GetSetting,
--     SelectCraftRecipe, GetCraftProfession, Attach; the look builders (Skin, Text,
--     Button, Bar, Close, Input, Colors, Accent, Font, FontFile, FontRow).
--   * Its profession window (DaylightUICraft) takes over from the game's: when
--     craftworld opens a profession the game's frame stays shown but out of sight.
--     Read from DaylightUI/Craft/Window.lua and Windows/Follow.lua (1.7):
--       - [docs] its follower polls the game's frame each frame, so the window opens one
--         frame after the game's frame shows, once GetBaseProfessionInfo names a
--         profession (Craft.Changed). It doesn't wait for the recipe list: it reads
--         whatever GetAllRecipeIDs holds then. With no profession yet it waits for
--         TRADE_SKILL_LIST_UPDATE, then one frame (Craft.Settled);
--       - [docs] with the window up, TRADE_SKILL_SHOW refills it a frame later unless the
--         data source is changing (Craft.TradeSkillShown, Craft.Refill), and
--         TRADE_SKILL_LIST_UPDATE re-reads the list a frame later (List.Soon(0)). A
--         re-read on the same profession picks nothing and tells plugins nothing
--         (Craft.Refreshed); on another profession it refills;
--       - [docs] opening fires CraftShown, CraftProfessionChanged(skillLine), then
--         CraftRecipeSelected(its pick); a refill fires the last two when they change;
--       - [docs] its pick is its own per profession for the session (Craft.picked): the one
--         picked before while its list holds it, else the list's first recipe, else
--         none. It never reads the game's selection, so OpenRecipe changes nothing in it.
--     Closing fires CraftHidden.
--   * [docs] SelectCraftRecipe (Craft.Select) is false while the window is shut, or its list
--     doesn't hold the recipe: not yet refilled for that profession, read before the
--     list arrived, or not learned.
--   * [docs] Its Create button (Create(id, n)) fires CraftStarted, crafts through the game,
--     and fires CraftMade per cast and CraftStopped at the end.
--   * [docs] Paint "craftrow" runs on a line per learned recipe of the open profession, now
--     and whenever the window opens; API.Attach hands the same overlay each time.
--   * [docs] Every view has AttachCraftPane; without the window its pane is hidden and never
--     shows (Craft.Pane). Craft/Module.lua sets DaylightUI.craftOwnWindow and craftMogul
--     at login; `mogul = true` is DaylightMogul owning professions: no window, no events.
--   * [docs] API.Button and Widgets.DressButton (W.DressButton): b.text, Hover, SetActive, SetOff,
--     OnEnter/OnLeave/OnMouseDown/OnMouseUp, PostClick's sound (state.sounds), b.lit for
--     the trace. Style.PaintAccent(tex, alpha) records the alpha (state.accents); Win.LINE 2.
--   * [docs] Widgets.Scroll and Widgets.SCROLL (W.Scroll): the thin bar its lists scroll with
--     (state.scrollBars). begin adopts ProfLost's lists onto it, as a Daylight UI loaded
--     before ProfLost does; the end drops them back to the game's bars.
--   * [docs] Widgets.Icon and Widgets.IconButton: a tinted Media icon, and the bare icon button
--     its window headers use (Win.HeaderIcon), with its click sound.
--   * [guess] `lag` (seconds): the follower looks that late, and the game's frame stays on
--     UIParent until it parks it then (Win.Follow).
-- Guesses:
--   * [guess] The game's frame, our timers and its timers run in the order they were asked for,
--     so a timer ProfLost starts on TRADE_SKILL_SHOW runs before the window's refill.
--   * [docs] Win.Parts (Windows/Parts.lua): Light(t, on, instant) shows or hides a hover texture
--     (no ease) and records the call (state.lights); HI is {1, 1, 1, 0.06}; Rule(parent, vertical)
--     makes a faint 1 px line the caller anchors (state.rules).
--   * [docs] Widgets.Link(parent, size, opts) (Options/Widgets.lua): a 20 px text button with b.text,
--     b.line, b.SetLabel(text), b.lit while hovered and its click sound on PostClick (state.links).
--   * [docs] Widgets.Bar(parent, h) is a StatusBar with b.track and b.fill (state.bars);
--     Widgets.BarAccent(bar, alpha) records one paint per call (state.barAccents).
--   * [docs] Fade (Fade.lua): State(key) answers now, goal, alpha, opacity for a key in
--     state.fadeAreas and nil for any other; Hush(name, prefixes) records the hush
--     (state.hushes); Unhush(name, snap) lifts it and counts it (state.unhushes) only if it held.
--   * [guess] The first learned recipe stands for its list's first line (List.First).
--   * [guess] The look builders make plain frames; colours are fixed.
--   * [guess] Settings live in DaylightWorld.settings[scope][path]; SetSetting fires SettingChanged.
--   * [guess] RegisterSkin stores the skin and never calls it (no Kit here).
--   * [guess] API.Menu (Widgets.OpenMenu, Options/Widgets.lua): the menu opens under its owner
--     and its owner is DaylightUI.Widgets.menuOwner until it closes. A full-screen
--     catcher above everything closes it on any click (CloseMenu), so a click never
--     reaches the owner while it is open. PickMenu(key) picks a line, which closes it.
--   * [guess] DaylightUI.Movers.Save(key, exact) records the save (Saved()). Movers.PieceScale and
--     SetPieceScale keep state.frameScales[key]; they don't rescale the frame.
--   * [guess] DaylightUI:Set(scope, path, value) is SetSetting and answers true.
--   * [guess] API.Fade(region, alpha, speed) records the call (state.alphaFades) and sets the alpha
--     at once; API.Speed holds FAST 0.12, NORMAL 0.2, SLOW 0.4.
--
--   DaylightWorld.begin({ craftWindow = true, plugin = true, api17 = true, settings = { ProfLost = { ... } } })
--   `plugin` runs ProfLost's Plugin.Start against it, and puts back what that changed.
--   DaylightWorld.Fire(event, ...) / Create(id, n) / SetSetting(scope, path, value) / Login()
--   DaylightWorld.Snapshot(): its saved settings and each profession's pick; begin({ from = it })
--   starts there. SetCraftWindow(on): its "Professions window" setting turned on or off
--   mid-scene (craftOwnWindow); off, it takes no profession window and its own hides
--   (guess: CraftHidden fires as on a close). Needs begin with the craft window.

-- Font keys to files (API.FontFile). An unknown key is the player's font, "general".
DaylightWorld = { FONT_FILES = { general = "Fonts\\FRIZQT__.TTF", wide = "Fonts\\MORPHEUS.TTF",
                                 narrow = "Fonts\\ARIALN.TTF" } }

local CP = ProfLost
local S

local function handle(event, fn)
    local h = { event = event, fn = fn }
    S.handlers[#S.handlers + 1] = h
    return h
end

-- Calls every handler of `event`, Daylight UI's events to plugins.
function DaylightWorld.Fire(event, ...)
    for _, h in ipairs(S.handlers) do
        if h.event == event and not h.off then h.fn(...) end
    end
end

-- W.DressButton (Options/Widgets.lua): its look's calls and scripts, no drawing. Hover
-- lights the trace (b.lit), a press sets b.down, PostClick plays the click sound.
local function dress(b, text)
    if not b.text then
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        b.text:SetPoint("CENTER")
    end
    b.text:SetText(text or "")
    b.dressed, b.lit = true, false
    function b.Paint() end
    function b.Light(on) b.lit = (on or b.active) and not b.off and true or false end
    function b.Hover(on)
        if not on then b.down = false end
        b.Light(on)
    end
    function b.SetActive(on)
        b.active = on
        b.Light(false)
    end
    function b.SetOff(on)
        b.off = on and true or nil
        b:SetEnabled(not on)
        b.Light(false)
    end
    b:SetScript("OnEnter", function() b.Hover(true) end)
    b:SetScript("OnLeave", function() b.Hover(false) end)
    b:SetScript("OnMouseDown", function() b.down = true end)
    b:SetScript("OnMouseUp", function() b.down = false end)
    b:SetScript("PostClick", function() S.sounds = S.sounds + 1 end)
    S.buttons[#S.buttons + 1] = b
    return b
end

-- W.Scroll (Options/Widgets.lua): a thin bar SCROLL.width wide, `x` right of `sf` and
-- as tall, made at alpha 0. Update shows it at SCROLL.rest while the list overflows and
-- hides it when everything fits; Wake lights it full. To jumps (no glide), Wheel moves
-- `step` per notch from where it stands. read/write as the opts give them, else the
-- ScrollFrame's own. No mouse, no fades, no poll: callers call Update.
local SCROLL = { width = 4, gap = 6, step = 48, rest = 0.7 }

local function scrollBar(sf, opts)
    opts = opts or {}
    local bar = CreateFrame("Frame", nil, opts.parent or sf:GetParent())
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", opts.x or SCROLL.gap, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", opts.x or SCROLL.gap, 0)
    bar:SetWidth(SCROLL.width)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.thumb = bar:CreateTexture(nil, "ARTWORK")
    bar:SetAlpha(0)
    bar.opts, bar.sf = opts, sf
    local function read()
        if opts.read then return opts.read() end
        -- The game answers numbers; the harness's stubs may not.
        local child = sf:GetScrollChild()
        local h, view = tonumber(child and child:GetHeight()) or 0, tonumber(sf:GetHeight()) or 0
        return tonumber(sf:GetVerticalScroll()) or 0, math.max(0, h - view), view
    end
    local function write(v)
        if opts.write then opts.write(v) else sf:SetVerticalScroll(v) end
    end
    function bar.Update()
        local at, max, view = read()
        bar.max = max
        bar:SetAlpha((max > 0 and view > 0) and SCROLL.rest or 0)
        return at
    end
    function bar.Wake()
        bar.Update()
        if (bar.max or 0) > 0 then bar:SetAlpha(1) end
    end
    function bar.To(v)
        local _, max = read()
        write(math.max(0, math.min(max, v)))
        bar.Wake()
    end
    function bar.Wheel(delta) bar.To((read()) - delta * (opts.step or SCROLL.step)) end
    function bar.Lock(on) bar.locked = on and true or nil end
    function bar.Stop() end
    S.scrollBars[#S.scrollBars + 1] = bar
    return bar
end

-- W.Icon and W.IconButton (Options/Widgets.lua): a Media icon tinted `color`; a bare
-- icon button ICON_BUTTON square with its 14 px icon in the middle, b.over while the
-- mouse is on it, its click sound after each click. An icon keeps its `file` and `color`.
local MEDIA = "Interface\\AddOns\\DaylightUI\\Media\\"
local ICON_BUTTON, ICON = 20, 14

local function icon(parent, file, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(MEDIA .. file)
    t.file = file
    t:SetSize(size, size)
    local c = color or { 1, 1, 1 }
    t.color = c
    t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    return t
end

local function iconButton(parent, file, tip, onClick, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or ICON_BUTTON, size or ICON_BUTTON)
    b.icon = icon(b, file, ICON)
    b.icon:SetPoint("CENTER")
    function b.SetIcon(f)
        b.icon:SetTexture(MEDIA .. f)
        b.icon.file = f
    end
    b.tipText = tip
    b:SetScript("OnEnter", function() b.over = true end)
    b:SetScript("OnLeave", function() b.over = false end)
    b:SetScript("OnClick", function(self, button) if onClick then onClick(self, button) end end)
    b:SetScript("PostClick", function() S.sounds = S.sounds + 1 end)
    return b
end

local function button(parent, text, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height or 24)
    return dress(b, text)
end

-- The line Daylight UI draws for `recipeID`, made once and reused.
local function row(id)
    S.rows[id] = S.rows[id] or CreateFrame("Frame", nil, S.window)
    return S.rows[id]
end

local function paintRows()
    if not S.craft then return end
    for _, id in ipairs(World.keys(S.list)) do
        for _, p in ipairs(S.painters) do
            if p.kind == "craftrow" and not p.off then p.fn(row(id), {}, { recipeID = id }) end
        end
    end
end

-- What its list reads now (Data.Read): the open profession and its learned recipes.
local function read()
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local line = type(base) == "table" and base.professionID ~= 0 and base.professionID or nil
    local list, first = {}, nil
    for _, id in ipairs(line and C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if type(info) == "table" and info.learned then
            list[id] = true
            first = first and math.min(first, id) or id
        end
    end
    return line, list, first
end

local function changing() return C_TradeSkillUI.IsDataSourceChanging() == true end

local function makeMe(name)
    local me = { name = name }
    function me.On(event, fn) return handle(event, fn) end
    function me.RegisterMover(frame, key, label, default)
        S.movers[key] = { frame = frame, label = label, default = default }
        return true
    end
    function me.RegisterFade(spec) S.fades[spec.key] = spec return true end
    function me.RegisterCommand(word, fn, help) S.commands[word] = { fn = fn, help = help } return true end
    function me.RegisterSkin(addon, fn) S.skins[addon] = fn return true end
    function me.RegisterTestPart(key, label) S.testParts[key] = label return true end
    function me.AddOptionsGroup(page, group) S.groups[#S.groups + 1] = { page = page, group = group } return true end
    function me.AddDefaults(module, defaults) S.defaults[module] = defaults return true end
    function me.Paint(kind, fn, opts)
        local p = { kind = kind, fn = fn, opts = opts }
        S.painters[#S.painters + 1] = p
        if kind == "craftrow" then paintRows() end
        return p
    end
    -- Every view has it (View.AttachCraftPane). Without its window the pane is a hidden
    -- frame under UIParent that never shows (Craft.Pane, Craft.DockPanes).
    function me.AttachCraftPane(width)
        S.paneWidth = width
        if not S.pane then
            S.pane = CreateFrame("Frame", nil, S.window or UIParent)
            if S.window then
                S.pane:SetPoint("TOPLEFT", S.window, "TOPRIGHT", 0, 0)
                S.pane:SetPoint("BOTTOMLEFT", S.window, "BOTTOMRIGHT", 0, 0)
            else
                S.pane:Hide()
            end
        end
        S.pane:SetWidth(width)
        return S.pane
    end
    return me
end

local function makeAPI(minor)
    local API = { major = 1, minor = minor }
    function API.For(name)
        S.me[name] = S.me[name] or makeMe(name)
        return S.me[name]
    end
    function API.On(event, fn) return handle(event, fn) end
    function API.Off(h) if type(h) == "table" then h.off = true end end
    function API.GetSetting(scope, path)
        local t = S.settings[scope]
        return t and t[path]
    end
    function API.IsModuleEnabled(name) return S.modules[name] ~= false end
    function API.Attach(frame)
        S.overlays[frame] = S.overlays[frame] or CreateFrame("Frame", nil, frame)
        return S.overlays[frame]
    end
    function API.GetCraftRow(id) return S.rows[id] end
    function API.GetCraftProfession()
        if not S.craft then return nil end
        return S.craft, CraftWorld.NAMES[S.craft]
    end
    function API.SelectCraftRecipe(id)
        if not (S.window and S.window:IsShown() and S.craft and S.list and S.list[id]) then return false end
        S.picked[S.craft] = id
        if S.selected ~= id then
            S.selected = id
            DaylightWorld.Fire("CraftRecipeSelected", id)
        end
        return true
    end
    -- The look.
    function API.Skin() return nil end
    -- In the player's font at its size role's size (API.md: tiny/small/body/head/title).
    local TEXT_PX = { tiny = 10, small = 12, body = 13, head = 15, title = 18 }
    function API.Text(parent, size)
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetFont(DaylightWorld.FONT_FILES.general, TEXT_PX[size] or TEXT_PX.body, "")
        return fs
    end
    API.Button = button
    function API.Close(parent, onClick)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(16, 16)
        b:SetScript("OnClick", onClick)
        return b
    end
    function API.Bar(parent) return CreateFrame("StatusBar", nil, parent) end
    function API.Input(parent) return CreateFrame("EditBox", nil, parent) end
    function API.Colors()
        return { TITLE = { 1, 1, 1 }, TEXT = { 0.9, 0.9, 0.9 }, LABEL = { 0.7, 0.7, 0.7 }, OFF = { 0.5, 0.5, 0.5 },
                 GOOD = { 0.4, 0.8, 0.4 }, WARN = { 0.9, 0.7, 0.3 }, BAD = { 0.9, 0.3, 0.3 } }
    end
    function API.Accent() return 0.25, 0.6, 1 end
    function API.Menu(owner, keys, values, current, onPick, width)
        S.menus = S.menus + 1
        S.menu = { owner = owner, keys = keys, values = values, current = current, onPick = onPick, width = width }
        S.addon.Widgets.menuOwner = owner
    end
    function API.Font() return "Fonts\\FRIZQT__.TTF" end
    function API.FontFile(key)
        local files = DaylightWorld.FONT_FILES
        return files[key] or files.general
    end
    function API.FontRow(key, label, desc) return { type = "font", key = key, label = label, desc = desc } end
    API.Speed = { FAST = 0.12, NORMAL = 0.2, SLOW = 0.4 }
    function API.Fade(region, alpha, speed)
        S.alphaFades[#S.alphaFades + 1] = { region = region, alpha = alpha, speed = speed }
        region:SetAlpha(alpha)
    end
    return API
end

-- Starts the scene.
-- Plugin.Start and Plugin.Sync copy Daylight UI's saved values into CP.db. Every setting and
-- carry-over flag goes back when the test ends. `plugin` calls it; a test that calls
-- Plugin.Start or Plugin.Sync itself calls it first.
function DaylightWorld.KeepSettings()
    for _, s in ipairs(CP.Settings.LIST) do
        if s.key then World.set(CP.db, s.key, CP.db[s.key]) end
    end
    for _, key in ipairs({ "hideInCombatCarried", "gatherHideCarried", "gatherSideCarried", "guideStepsCarried" }) do
        World.set(CP.db, key, CP.db[key])
    end
end

function DaylightWorld.begin(spec)
    spec = spec or {}
    S = { handlers = {}, me = {}, movers = {}, fades = {}, commands = {}, skins = {}, testParts = {},
          groups = {}, defaults = {}, painters = {}, overlays = {}, rows = {}, plugins = {}, registered = {},
          settings = spec.settings or {}, modules = spec.modules or {},
          craftWindow = spec.craftWindow ~= false and not spec.mogul, craft = nil, picked = {},
          lag = spec.lag or 0, sounds = 0, buttons = {}, accents = {}, alphaFades = {},
          lights = {}, rules = {}, links = {}, bars = {}, barAccents = {}, fadeAreas = {}, hushes = {},
          unhushes = 0 }
    if spec.from then
        for scope, t in pairs(spec.from.settings or {}) do
            S.settings[scope] = {}
            for path, v in pairs(t) do S.settings[scope][path] = v end
        end
        for line, id in pairs(spec.from.picked or {}) do S.picked[line] = id end
    end
    DaylightWorld.state = S
    local API = makeAPI(spec.minor or 3)
    -- API 1.7's small calls, with `api17 = true`: MotionOn, IsUnlocked, GetFrame and Media
    -- answer from S.api17 (motion, unlocked, frames[name]) and count their uses in S.api17.used.
    if spec.api17 then
        S.api17 = { motion = true, unlocked = false, frames = {}, used = {} }
        local function use(name) S.api17.used[name] = (S.api17.used[name] or 0) + 1 end
        function API.MotionOn() use("MotionOn") return S.api17.motion end
        function API.IsUnlocked() use("IsUnlocked") return S.api17.unlocked end
        function API.GetFrame(name) use("GetFrame") return S.api17.frames[name] end
        function API.Media(file) use("Media") return MEDIA .. file end
    end
    -- craftOwnWindow and craftMogul as Craft/Module.lua's OnEnable sets them at login.
    local addon = { API = API, Widgets = {}, Movers = {}, Win = { LINE = 2 }, Style = {},
                    craftOwnWindow = S.craftWindow, craftMogul = spec.mogul == true }
    S.addon, S.menus, S.saves = addon, 0, {}
    -- Win.Caster (Windows/Cast.lua): a secure button on UIParent laid over a row out of
    -- combat; Over(row, attrs) and Hide() only. S.casters lists each one made; c.overs
    -- counts its Over calls.
    S.casters = {}
    function addon.Win.Caster(spec)
        local c = { spec = spec, overs = 0 }
        S.casters[#S.casters + 1] = c
        function c.Over(row, attrs)
            c.overs = c.overs + 1
            if InCombatLockdown() then return nil end
            local b = c.button or CreateFrame("Button", spec.name, UIParent, "SecureActionButtonTemplate")
            if not c.button then
                -- As Windows/Cast.lua: modified clicks go to spec.post after the secure click.
                b:SetScript("PostClick", function(self, button)
                    if self.row and spec.post then spec.post(self.row, button) end
                end)
            end
            c.button = b
            for _, key in ipairs({ "type1", "spell", "macrotext1", "type2", "macrotext2" }) do b:SetAttribute(key, attrs[key]) end
            b.row = row
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", row:GetLeft(), row:GetBottom())
            b:SetSize(row:GetWidth(), row:GetHeight())
            b:Show()
            return b
        end
        function c.Hide()
            if c.button and not InCombatLockdown() then c.button:Hide() end
        end
        return c
    end
    -- Win.Parts (Windows/Parts.lua): Light shows or hides the hover texture and records the call.
    local Parts = { HI = { 1, 1, 1, 0.06 }, RULE = { 1, 1, 1, 0.06 } }
    function Parts.Light(t, on, instant)
        S.lights[#S.lights + 1] = { t = t, on = on == true, instant = instant }
        t:SetShown(on == true)
    end
    function Parts.Rule(parent, vertical)
        local t = parent:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(1, 1, 1, 0.06)
        if vertical then t:SetWidth(1) else t:SetHeight(1) end
        S.rules[t] = true
        return t
    end
    addon.Win.Parts = Parts
    -- W.Link, W.Bar and W.BarAccent (Options/Widgets.lua).
    function addon.Widgets.Link(parent, size)
        local b = CreateFrame("Button", nil, parent)
        b:SetHeight(20)
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        b.text:SetPoint("LEFT")
        b.line = b:CreateTexture(nil, "ARTWORK")
        function b.SetLabel(text) b.text:SetText(text or "") end
        b:SetScript("OnEnter", function() b.lit = true end)
        b:SetScript("OnLeave", function() b.lit = false end)
        b:SetScript("PostClick", function() S.sounds = S.sounds + 1 end)
        S.links[b] = size or "small"
        return b
    end
    function addon.Widgets.Bar(parent, h)
        local bar = CreateFrame("StatusBar", nil, parent)
        bar:SetHeight(h or 4)
        bar.track = bar:CreateTexture(nil, "BACKGROUND")
        bar.fill = bar:CreateTexture(nil, "ARTWORK")
        S.bars[bar] = true
        return bar
    end
    function addon.Widgets.BarAccent(bar)
        S.barAccents[bar] = (S.barAccents[bar] or 0) + 1
    end
    -- Fade.lua: State, Hush and Unhush.
    addon.Fade = {}
    function addon.Fade.State(key)
        if not S.fadeAreas[key] then return nil end
        return 1, 1, 1, 1
    end
    function addon.Fade.Hush(name, prefixes) S.hushes[name] = prefixes end
    function addon.Fade.Unhush(name)
        if S.hushes[name] == nil then return end
        S.hushes[name] = nil
        S.unhushes = S.unhushes + 1
    end
    function addon.Widgets.CloseMenu() addon.Widgets.menuOwner = nil end
    addon.Widgets.DressButton = dress
    addon.Widgets.SCROLL = SCROLL
    addon.Widgets.Scroll = scrollBar
    addon.Widgets.Icon = icon
    addon.Widgets.IconButton = iconButton
    -- W.TabLook (Options/Widgets.lua): label ink at rest, white on hover, the accent when
    -- picked. The caller drives s.Paint(over) and s.Pick(on).
    S.tabWhite = { 1, 1, 1 }
    function addon.Widgets.TabLook(b, s, text)
        s.text = text
        function s.Paint(over)
            if s.picked then return text:SetTextColor(API.Accent()) end
            text:SetTextColor(unpack(over and S.tabWhite or API.Colors().LABEL))
        end
        function s.Pick(on)
            s.picked = on and true or nil
            s.Paint(b:IsMouseOver() == true)
        end
        return s
    end
    S.scrollBars = {}
    function addon.Style.PaintAccent(tex, alpha)
        S.accents[tex] = alpha
        tex:SetVertexColor(0.25, 0.6, 1, alpha)
    end
    function addon.Movers.Save(key, exact) S.saves[#S.saves + 1] = { key = key, exact = exact } end
    -- Movers.PieceScale / SetPieceScale (Movers.lua): general.frameScales[key], 1 stored as nil.
    S.frameScales = {}
    function addon.Movers.PieceScale(key) return S.frameScales[key] or 1 end
    function addon.Movers.SetPieceScale(key, v)
        S.frameScales[key] = math.abs(v - 1) > 0.001 and v or nil
    end
    -- DaylightUI:Set (Core.lua): saves a module's setting and fires SettingChanged.
    function addon.Set(_, scope, path, value)
        DaylightWorld.SetSetting(scope, path, value)
        return true
    end
    function addon.RegisterPlugin(_, name, def) S.plugins[name] = def end
    function addon.RegisterModule(_, name, def) S.registered[name] = def end

    -- [docs] DaylightUI.API 1.3 as its API.md describes it.
    World.set(_G, "DaylightUI", addon)
    -- Daylight UI loads before ProfLost, so every list already scrolls with its bar.
    CP.Style.AdoptScrolls()
    World.onEnd(function() CP.Style.AdoptScrolls(false) end)

    if S.craftWindow then
        -- A named frame sets its global: put the old one back, so the frame leaves with the world.
        local before = rawget(_G, "DaylightUICraft")
        S.window = CreateFrame("Frame", "DaylightUICraft", UIParent)
        rawset(_G, "DaylightUICraft", before)
        S.window:SetSize(720, 560)
        S.window:SetPoint("CENTER")
        S.window:Hide()
        function S.window.GetAlpha() return 1 end
        function S.window.GetEffectiveAlpha() return 1 end

        -- [docs] Daylight UI's profession window takes over from the game's (Craft/Window.lua).
        World.set(_G, "DaylightUICraft", S.window)
        local window = S.window
        World.onEnd(function() window:Hide() end)
    end

    -- Fills the list for the profession the game has open (Craft.Open / Craft.Refill):
    -- the remembered pick while the list holds it, else its first recipe.
    local function fill()
        local line, list, first = read()
        local was = S.craft
        S.craft, S.list = line, list
        if not line then return end
        if not (S.picked[line] and list[S.picked[line]]) then S.picked[line] = first end
        local opening = not S.window:IsShown()
        if opening then
            S.window:Show()
            DaylightWorld.Fire("CraftShown")
        end
        if opening or line ~= was then DaylightWorld.Fire("CraftProfessionChanged", line) end
        paintRows()
        local pick = S.picked[line]
        if pick ~= S.selected or opening or line ~= was then
            S.selected = pick
            if pick then DaylightWorld.Fire("CraftRecipeSelected", pick) end
        end
    end

    -- The follower's look a frame after the game's frame shows (Craft.Changed): open
    -- once a profession answers, else wait for the list (Craft.Settled).
    -- The follower parks the game's frame under its veil (Win.Follow) as it looks, so with
    -- `lag` the game's frame shows on UIParent until then.
    local function look()
        if S.window:IsShown() or not CraftWorld.Opened() then return end
        local game, veil = CraftWorld.state.frame, CraftWorld.state.hidden
        if game and veil and game:GetParent() ~= veil then game:SetParent(veil) end
        if read() then fill() else S.waiting = true end
    end

    -- TRADE_SKILL_SHOW with the window up (Craft.TradeSkillShown -> Craft.Refill).
    local function shown()
        if S.window:IsShown() and not changing() then fill() end
    end

    -- TRADE_SKILL_LIST_UPDATE: a waiting window opens (Craft.Settled); an open one
    -- re-reads its list (List.Soon(0) -> Craft.Refreshed), refilling on a new profession.
    local function listed()
        if not S.window:IsShown() then
            if S.waiting then
                S.waiting = nil
                look()
            end
            return
        end
        if changing() then return end
        local line, list = read()
        if line ~= S.craft then return fill() end
        S.list = list
        paintRows()
    end
    DaylightWorld.Settle = function() if S.window:IsShown() then fill() else look() end end

    if S.craftWindow then
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
        ev:RegisterEvent("TRADE_SKILL_SHOW")
        ev:SetScript("OnEvent", function(_, event)
            C_Timer.After(0, event == "TRADE_SKILL_SHOW" and shown or listed)
        end)
        World.onEnd(function() ev:UnregisterAllEvents() ev:SetScript("OnEvent", nil) end)
    end

    World.listen(function(what, a, b, c)
        if not S.craftWindow then return end
        if what == "craft:show" then
            C_Timer.After(S.lag, look)
            return S.lag == 0
        elseif what == "craft:close" then
            S.craft, S.selected, S.list, S.waiting = nil, nil, nil, nil
            S.window:Hide()
            DaylightWorld.Fire("CraftHidden")
        elseif what == "craft:made" and S.creating then
            DaylightWorld.Fire("CraftMade", a, b, c)
        elseif what == "craft:stop" and S.creating then
            S.creating = nil
            DaylightWorld.Fire("CraftStopped", a, b, c)
        end
    end)

    if spec.plugin then
        DaylightWorld.KeepSettings()
        -- The plugin view and API Plugin.Start hands to Host go back to what they were.
        World.set(CP.Host.view, "me", CP.Host.view.me)
        World.set(CP.Host.view, "api", CP.Host.view.api)
        CP.Plugin.Start()
        World.onEnd(function()
            -- What Plugin.Start handed to ProfLost's other modules goes back to no Daylight UI.
            CP.Crafting.daylight = nil
            CP.Plugin.active = false
            CP.Window.managed.mover, CP.Window.managed.fade = false, false
        end)
    end
end

-- Daylight UI's Create button: `count` of the selected recipe through the game.
function DaylightWorld.Create(id, count)
    S.creating = true
    DaylightWorld.Fire("CraftStarted", id, count)
    C_TradeSkillUI.CraftRecipe(id, count)
end

function DaylightWorld.SetSetting(scope, path, value)
    S.settings[scope] = S.settings[scope] or {}
    S.settings[scope][path] = value
    DaylightWorld.Fire("SettingChanged", scope, path, value)
end

function DaylightWorld.Login() DaylightWorld.Fire("Login") end

function DaylightWorld.Snapshot()
    local settings, picked = {}, {}
    for scope, t in pairs(S.settings) do
        settings[scope] = {}
        for path, v in pairs(t) do settings[scope][path] = v end
    end
    for line, id in pairs(S.picked) do picked[line] = id end
    return { settings = settings, picked = picked, craftWindow = S.craftWindow }
end

function DaylightWorld.SetCraftWindow(on)
    if not S.window then error("DaylightWorld began without its craft window", 2) end
    on = on and true or false
    S.craftWindow = on
    S.addon.craftOwnWindow = on
    if not on and S.window:IsShown() then
        S.craft, S.selected, S.list, S.waiting = nil, nil, nil, nil
        S.window:Hide()
        DaylightWorld.Fire("CraftHidden")
    end
end

-- /dui <word> <rest>.
function DaylightWorld.Command(word, rest)
    local c = S.commands[word]
    if c then c.fn(rest or "") end
    return c ~= nil
end

-- A click anywhere while Daylight UI's menu is open: its catcher closes it.
function DaylightWorld.CloseMenu() S.addon.Widgets.CloseMenu() end

-- Picks line `key` of the open menu.
function DaylightWorld.PickMenu(key)
    local m = S.menu
    S.addon.Widgets.CloseMenu()
    if m then m.onPick(key) end
end

-- Mover saves ProfLost asked for, in order.
function DaylightWorld.Saved() return S.saves end
