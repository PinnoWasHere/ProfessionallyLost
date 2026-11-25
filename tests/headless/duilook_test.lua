-- With Daylight UI loaded, ProfLost's small pieces come from Daylight UI's own builders
-- (review items 45, 46 and 47; the look rule: every piece comes from Daylight UI's own builders):
--   45  each Disenchant row's X is its icon button (Widgets.IconButton), and "Show ignored
--       items" is its text link (Widgets.Link): hover, press and click sound;
--   46  row and control hovers ease through Parts.Light at Parts.HI, rules and dividers are
--       Parts.Rule, the craft strip's bar is its pill bar (Widgets.Bar, Widgets.BarAccent);
--       the picked row's wash keeps Style.PaintAccent at its recorded 0.22;
--   47  the campfire hush asks Daylight UI's fade engine (Fade.Hush) and never writes alpha
--       on a window that engine fades.
--
-- tests/world/daylightworld.lua fakes those builders and records their calls in its state.

local CP = ProfLost
local S, W, P = CP.Style, CP.Window, CP.Panel
local DUROTAR = 1411

-- The Daylight UI world with the plugin started; its state records the builders' calls.
local function daylight()
    DaylightWorld.begin({ plugin = true, craftWindow = false })
    local st = DaylightWorld.state
    st.fadeAreas[CP.Look.FADE_KEY] = true
    return st, st
end

-- Item 45 ---------------------------------------------------------------------------------

local function deItem()
    local DE = CP.Disenchant
    return { itemID = 900011, icon = 134400, ignored = false, quality = 2, name = "Mock Green Sword", ilvl = 20,
             advice = DE.Advice({ group = 1, vendor = 500 }, function() return 1000 end,
                 function() return "Strange Dust" end),
             yield = DE.Yield(1) }
end

T.test("45: a Disenchant row's X is Daylight UI's icon button, with hover, bump and click sound", function()
    local _, st = daylight()
    World.set(CP.charDB, "deIgnore", {})
    local r = CreateFrame("Button", nil, UIParent)
    CP.DisenchantTab.InitRow(r, deItem())
    local x = r.ignore
    T.ok(x.daylight == true, "made by Widgets.IconButton (Style.IconButton)")
    T.eq(x.icon and x.icon.file, "ui-close.png", "its close glyph")
    T.ok(x:GetScript("OnEnter") ~= nil and x:GetScript("OnLeave") ~= nil, "it answers the mouse")
    x:GetScript("OnEnter")(x)
    T.ok(x.over == true, "hover ink")
    x:GetScript("OnLeave")(x)
    local sounds = st.sounds
    x:GetScript("OnClick")(x, "LeftButton")
    x:GetScript("PostClick")(x, "LeftButton")
    T.eq(st.sounds, sounds + 1, "its click sound")
    T.eq(CP.charDB.deIgnore[900011], true, "the click still ignores the item")
end)

T.test("45: 'Show ignored items' is Daylight UI's text link, with hover and click sound", function()
    local seen, st = daylight()
    T.ok(type(CP.DisenchantTab.MakeToggle) == "function", "the toggle has a maker (it was a bare Button built inline)")
    local holder = CreateFrame("Frame", nil, UIParent)
    local t = CP.DisenchantTab.MakeToggle(holder)
    T.ok(seen.links[t] ~= nil, "made by Widgets.Link")
    t.SetLabel("Show ignored items (1)")
    T.eq(t.label:GetText(), "Show ignored items (1)", "the label is the link's text")
    t:GetScript("OnEnter")(t)
    T.ok(t.lit == true, "hover")
    local sounds = st.sounds
    local shown = 0
    World.set(CP.DisenchantTab, "ShowIgnored", function() shown = shown + 1 end)
    t:GetScript("OnClick")(t, "LeftButton")
    t:GetScript("PostClick")(t, "LeftButton")
    T.eq(st.sounds, sounds + 1, "its click sound")
    T.eq(shown, 1, "the click still flips the list")
end)

-- Item 46 ---------------------------------------------------------------------------------

-- Hover texture lit by Parts.Light for `b`, or nil.
local function lit(seen, on)
    local last = seen.lights[#seen.lights]
    return last and last.on == on and last.t or nil
end

T.test("46: a row's hover eases through Parts.Light at Parts.HI, and keeps the caller's own hover", function()
    local seen = daylight()
    local b = CreateFrame("Button", nil, UIParent)
    -- The harness keeps no vertex colour, so this fresh button's textures record theirs.
    local create = b.CreateTexture
    b.CreateTexture = function(self, ...)
        local t = create(self, ...)
        local set = t.SetVertexColor
        t.SetVertexColor = function(tex, r, g, bl, a)
            tex.vertex = { r, g, bl, a }
            return set(tex, r, g, bl, a)
        end
        return t
    end
    S.Interactive(b)
    local mine = 0
    b:SetScript("OnEnter", function() mine = mine + 1 end)
    b:GetScript("OnEnter")(b)
    local t = lit(seen, true)
    T.ok(t ~= nil, "Parts.Light lit a texture on enter")
    T.eq(mine, 1, "the caller's OnEnter still runs")
    local a = t.vertex and t.vertex[4]
    T.ok(a and math.abs(a - 0.06) < 1e-6, "at Parts.HI's alpha as vertex colour, got " .. tostring(a))
    T.ok(t:GetDrawLayer() ~= "HIGHLIGHT", "not the game's instant highlight layer")
    b:GetScript("OnLeave")(b)
    T.eq(lit(seen, false), t, "and eased out on leave")
end)

T.test("46: a control's hover eases through Parts.Light", function()
    local seen = daylight()
    local b = CreateFrame("Button", nil, UIParent)
    S.Control(b)
    b:GetScript("OnEnter")(b)
    T.ok(lit(seen, true) ~= nil, "Parts.Light lit on enter")
    b:GetScript("OnLeave")(b)
    T.ok(lit(seen, false) ~= nil, "and eased out on leave")
end)

T.test("46: rules, dividers and the tab row's rule are Parts.Rule", function()
    local seen = daylight()
    local row = CreateFrame("Button", nil, UIParent)
    T.ok(seen.rules[S.Rule(row)], "Style.Rule")
    T.ok(seen.rules[S.Divider(row)], "Style.Divider")
    local f = CreateFrame("Frame", nil, UIParent)
    S.Shell(f, 60)
    T.ok(seen.rules[f.__rule], "the shell's tab row rule")
end)

T.test("46: the craft strip's bar is Daylight UI's pill bar in the accent, repainted with it", function()
    local seen = daylight()
    local bar = S.AccentBar(UIParent)
    T.ok(seen.bars[bar], "made by Widgets.Bar")
    T.ok((seen.barAccents[bar] or 0) >= 1, "painted by Widgets.BarAccent")
    local before = seen.barAccents[bar]
    S.Repaint()
    T.ok(seen.barAccents[bar] > before, "repainted when the accent changes")
end)

T.test("46: the picked row's wash stays Daylight UI's PaintAccent at 0.22", function()
    daylight()
    local b = CreateFrame("Button", nil, UIParent)
    S.PickRow(b, true)
    T.eq(DaylightWorld.state.accents[b.pickWash], S.PICK.wash)
    T.eq(S.PICK.wash, 0.22)
end)

-- Item 47 ---------------------------------------------------------------------------------

-- A free, shown guide window whose alpha Daylight UI's fade engine owns.
local function freeWindow()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [165] = 100 } })
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 800 })
    World.set(W.managed, "mover", false)
    W.PlaceAnchor()
    W.Open()
    T.advance(0.2)
end

T.test("47: sitting by a campfire hushes the window through Daylight UI's fade, never its own", function()
    local seen = daylight()
    freeWindow()
    T.ok(W.managed.fade, "Daylight UI fades the window")
    T.ok(P.frame:IsShown(), "shown")
    local writes = {}
    local setAlpha = P.frame.SetAlpha
    World.set(P.frame, "SetAlpha", function(self, a)
        writes[#writes + 1] = a
        return setAlpha(self, a)
    end)
    local aura
    World.patch("C_UnitAuras.GetPlayerAuraBySpellID", function(id) return id == 1229739 and aura or nil end)
    World.onEnd(function()
        aura = nil
        CP.GatherList.UpdateSitting()
        T.advance(0.5)
    end)

    aura = { spellId = 1229739 }
    CP.GatherList.UpdateSitting()
    T.advance(1)
    local h = seen.hushes.ProfLost
    T.ok(h ~= nil, "Fade.Hush asked for")
    T.eq(h and h[1], CP.Look.FADE_KEY, "on the guide window's fade area")
    T.eq(#writes, 0, "ProfLost wrote no alpha while sitting, got " .. table.concat(writes, ","))

    aura = nil
    CP.GatherList.UpdateSitting()
    T.advance(1)
    T.eq(seen.hushes.ProfLost, nil, "standing lifts the hush")
    T.eq(seen.unhushes, 1, "through Fade.Unhush")
    T.eq(#writes, 0, "and standing writes no alpha either, got " .. table.concat(writes, ","))
end)
