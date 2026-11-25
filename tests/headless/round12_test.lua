-- Round 12, the polish after 0.2.57: no detach glyphs, a short Follow the guide line, the
-- route menu rebuilding in place on a mode pick, the Skinning tooltips wording, and the
-- gathering panel's side as left or right of the guide. The Nearby zones rows are in
-- farmzones_test.

local CP = ProfLost
local W, GP, GL, G = CP.Window, CP.GatherPanel, CP.GatherList, CP.Gather
local MINING, HERB = 186, 182
local DUROTAR = 1411

-- 1. The detach glyphs are gone --------------------------------------------------------------

T.test("no detach or reattach glyph: the setting alone attaches and detaches", function()
    T.eq(W.detachButton, nil, "no |-> on the guide's title bar")
    T.eq(GP.attachButton, nil, "no <-| on the detached panel")
    T.eq(CP.Style.GlyphButton, nil, "the glyph builder is gone")
    T.eq(GP.SetAttached, nil)
    T.eq(GP.HeadRoom(), GP.CLOSE_GAP + GP.GUIDE + GP.ICON_GAP + GP.LOCK + GP.ICON_GAP + GP.CLOSE,
        "header room for the guide button, padlock and close only")
    for _, t in ipairs(CP.Panel.titleButtons) do
        local label = t.button.label and t.button.label:GetText()
        T.ok(not (label and label:find("->", 1, true)), "no glyph among the title buttons")
    end
end)

-- 2. The Follow the guide line is short --------------------------------------------------------

local function widest()
    local w = 0
    for _, label in pairs(GL.MODE_LABEL) do w = math.max(w, #label) end
    return w
end

T.test("Following the guide: a heading, then at most two short names and +N more", function()
    local fish = { "Raw Brilliant Smallfish", "Raw Longjaw Mud Snapper", "Raw Bristle Whisker Catfish",
        "Raw Rainbow Fin Albacore", "Raw Rockscale Cod", "Raw Spotted Yellowtail" }
    T.eq(GL.FollowLines(fish), { "Following the guide", "Brilliant Smallfish", "Longjaw Mud Snapper",
        "+4 more" }, "Raw dropped, two names, the rest as a count")
    for _, line in ipairs(GL.FollowLines(fish)) do
        T.ok(#line <= widest(), "within the widest radio label: " .. line)
    end
    T.eq(GL.FollowLines({ "Peacebloom" }), { "Following the guide", "Peacebloom" })
    T.eq(GL.FollowLines({ "Peacebloom", "Silverleaf", "Earthroot" }),
        { "Following the guide", "Peacebloom", "Silverleaf +1 more" }, "the count joins a short name")
    local long = GL.FollowLines({ "An Extremely Long Ore Name Indeed" })
    T.ok(#long[2] <= widest() and long[2]:find("...", 1, true) ~= nil, "a name too long is cut: " .. long[2])
    T.eq(GL.FOLLOW_MAX, 2)
end)

-- A route menu wired as Blizzard_Menu's: a context menu frame that can take a fresh
-- description while open. Returns the recorder.
local function menuWorld(skills, opts)
    opts = opts or {}
    local rec = { opened = 0, rebuilt = 0 }
    local function fakeRoot()
        local m = { titles = {}, radios = {}, checks = {}, entries = {} }
        local root = { m = m }
        local function entry(kind, text, set, data)
            local e = { kind = kind, text = text, set = set, data = data }
            function e:SetResponse(v) self.response = v end
            function e:SetEnabled(on) self.enabled = on end
            m.entries[#m.entries + 1] = e
            return e
        end
        function root.CreateTitle(_, text) m.titles[#m.titles + 1] = text; return entry("title", text) end
        function root.CreateRadio(_, text, _, set, data)
            local e = entry("radio", text, set, data)
            m.radios[#m.radios + 1] = e
            return e
        end
        function root.CreateCheckbox(_, text, _, set, data)
            local e = entry("check", text, set, data)
            m.checks[#m.checks + 1] = e
            return e
        end
        function root.CreateButton(_, text) return entry("button", text) end
        return root
    end
    local function newMenu()
        local menu = { shown = true, left = 300, top = 700 }
        function menu:IsShown() return self.shown end
        function menu:GetLeft() return self.left end
        function menu:GetTop() return self.top end
        function menu:ClearAllPoints() self.point = nil end
        function menu:SetPoint(...) self.point = { ... } end
        if not opts.noRebuild then
            function menu:SetMenuDescription(root)
                rec.rebuilt = rec.rebuilt + 1
                rec.root = root
            end
        end
        return menu
    end
    World.set(_G, "MenuUtil", {
        CreateContextMenu = function(owner, gen)
            rec.opened = rec.opened + 1
            rec.root = fakeRoot()
            gen(owner, rec.root)
            rec.menu = newMenu()
            return rec.menu
        end,
        CreateRootMenuDescription = function(mixin) rec.mixin = mixin; return fakeRoot() end,
    })
    World.set(_G, "Menu", { PopulateDescription = function(gen, owner, root) gen(owner, root) end })
    World.set(_G, "MenuVariants", { GetDefaultContextMenuMixin = function() return "contextMixin" end })
    World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
    World.set(G, "Skills", function() return skills end)
    World.set(G, "PlayerZone", function() return DUROTAR end)
    -- The menu alone: a mode pick starts no route solve that could outlive the scene.
    World.set(GL, "RouteChanged", function() end)
    return rec
end

local function radio(rec, mode)
    for _, r in ipairs(rec.root.m.radios) do if r.data == mode then return r end end
end

local function hasTitle(root, text)
    for _, t in ipairs(root.m.titles) do if t:find(text, 1, true) then return true end end
    return false
end

-- 3. A mode pick rebuilds the open menu in place --------------------------------------------

T.test("Follow the guide's menu lines are never wider than its radio labels", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "route", true)
    World.set(CP.db, "routeMode", nil)
    World.set(GL, "Following", function()
        return { "Raw Brilliant Smallfish", "Raw Longjaw Mud Snapper", "Raw Rainbow Fin Albacore", "Peacebloom" }
    end)
    local rec = menuWorld({ [HERB] = 50 })
    GL.RouteMenu(UIParent)
    local m = rec.root.m
    T.ok(hasTitle(rec.root, "Following the guide"))
    for i = 2, #m.titles do
        local plain = m.titles[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        T.ok(#plain <= widest(), "short line: " .. plain)
    end
end)

T.test("picking Farm adds the ticks at once, in the same open menu", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "route", true)
    World.set(CP.db, "routeMode", nil)
    local rec = menuWorld({ [MINING] = 100, [HERB] = 100 })
    GL.RouteMenu(UIParent)
    T.eq(#rec.root.m.checks, 0, "Follow the guide: no ticks")
    local first = rec.menu
    local response = radio(rec, "farm").set("farm")
    T.eq(CP.db.routeMode, "farm")
    T.eq(response, MenuResponse.Refresh, "the menu stays open")
    T.eq(rec.rebuilt, 0, "nothing rebuilt while the pick runs")
    T.advance(0.2)
    T.eq(rec.rebuilt, 1, "rebuilt the next frame")
    T.eq(rec.opened, 1, "the same menu, not a second one")
    T.ok(rec.menu == first)
    T.eq(rec.mixin, "contextMixin", "a context menu's own look")
    T.ok(#rec.root.m.checks > 0, "the herb and ore ticks are there")
    T.ok(hasTitle(rec.root, GL.TICKS_HEADER), "under their header")

    -- Back to Follow the guide: the ticks go and the short line comes.
    radio(rec, "level").set("level")
    T.advance(0.2)
    T.eq(rec.rebuilt, 2)
    T.eq(#rec.root.m.checks, 0, "no ticks")
    T.ok(hasTitle(rec.root, "Following the guide"))

    -- The mode already picked: nothing to rebuild.
    radio(rec, "level").set("level")
    T.advance(0.2)
    T.eq(rec.rebuilt, 2, "same mode, no rebuild")
end)

T.test("a menu closed before the next frame isn't reopened", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "route", true)
    World.set(CP.db, "routeMode", nil)
    local rec = menuWorld({ [MINING] = 100 })
    GL.RouteMenu(UIParent)
    radio(rec, "farm").set("farm")
    rec.menu.shown = false
    T.advance(0.2)
    T.eq(rec.rebuilt, 0)
    T.eq(rec.opened, 1)
end)

T.test("without the rebuild calls the menu opens again at the same top-left", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "route", true)
    World.set(CP.db, "routeMode", nil)
    local rec = menuWorld({ [MINING] = 100 }, { noRebuild = true })
    GL.RouteMenu(UIParent)
    radio(rec, "farm").set("farm")
    T.advance(0.2)
    T.eq(rec.opened, 2, "opened again")
    T.eq(rec.menu.point, { "TOPLEFT", UIParent, "BOTTOMLEFT", 300, 700 }, "where the first one stood")
    T.ok(#rec.root.m.checks > 0, "with the ticks")
end)

-- 5. The creature tooltip setting's wording --------------------------------------------------

T.test("the unitTooltip setting reads Skinning tooltips", function()
    local s = CP.Settings.Find("unitTooltip")
    T.eq(s.label, "Skinning tooltips")
    T.eq(s.desc, "Skinning drop chances, the skill needed, and how many to gather.")
    T.eq(CP.DEFAULTS.unitTooltip, true, "same key, same default")
end)

-- 6. The gathering panel's side ----------------------------------------------------------------

T.test("the side setting offers Left and Right, one line of help", function()
    local s = CP.Settings.Find("gatherSide")
    T.eq(s.values, { left = "Left", right = "Right" })
    T.eq(s.desc, "Which side of the guide window the attached Gathering window opens on.")
end)

T.test("a new save gets the right side, and a docking build's save the side away from its dock, once", function()
    local fresh = CP.CarryOver({})
    T.eq(fresh.gatherSide, "right", "new install: right")
    T.ok(fresh.gatherSideCarried)
    T.eq(CP.CarryOver({ dockSide = "LEFT" }).gatherSide, "left", "the old dock stood left")
    T.eq(CP.CarryOver({ gatherSide = "auto", dockSide = "LEFT" }).gatherSide, "left", "auto migrated")
    T.eq(CP.CarryOver({ gatherSide = "auto", dockSide = "RIGHT" }).gatherSide, "right")
    local picked = CP.CarryOver({ gatherSide = "left", dockSide = "RIGHT" })
    T.eq(picked.gatherSide, "left", "a picked side stays")
    T.eq(picked.gatherSideCarried, nil)
end)

T.test("with Daylight UI the carried side is saved in its profile, so its page shows it", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "gatherSide", "left")
    World.set(CP.db, "gatherSideCarried", true)
    DaylightWorld.begin({ plugin = true })
    DaylightWorld.Login()
    T.eq(CP.db.gatherSide, "left")
    T.eq(DaylightWorld.state.settings.ProfLost.gatherSide, "left", "written to Daylight UI")
    T.eq(CP.db.gatherSideCarried, nil, "once")
end)

T.test("a side the player picked in Daylight UI wins over the carried one", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "gatherSide", "right")
    World.set(CP.db, "gatherSideCarried", true)
    DaylightWorld.begin({ plugin = true, settings = { ProfLost = { gatherSide = "left" } } })
    DaylightWorld.Login()
    T.eq(CP.db.gatherSide, "left")
    T.eq(CP.db.gatherSideCarried, nil)
end)
