-- The gathering panel shows one profession or all (its menu's radios, saved per character),
-- has no Next up section, and opens or closes the guide window from its header when it stands alone.

local CP = ProfLost
local G, GL, GP, W = CP.Gather, CP.GatherList, CP.GatherPanel, CP.Window
local HERB, MINE, SKIN = 182, 186, 393
local ALCHEMY, BS, LW = 171, 164, 165
local DUROTAR = 1411
local PEACEBLOOM, COPPER = 2447, 2770

-- Durotar at level 20 with Herbalism and Mining, the guides' needs on both.
local function scene(skills)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    for _, key in ipairs({ "routeMode", "routeSkip", "skinSkip", "gatherClosed", "farmClosed" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.charDB, "panelProf", nil)
    World.set(CP.charDB, "gatherNeeds", { [ALCHEMY] = { [PEACEBLOOM] = 20 }, [BS] = { [COPPER] = 30 } })
    World.set(CP.charDB, "gatherSoon", nil)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = skills[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    G.ResetClusters()
    World.onEnd(function() G.ResetClusters() end)
end

-- The profession sections drawn now, by skill line id.
local function sections()
    GL.Refresh()
    local out = {}
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "section" then out[l.key] = true end
    end
    return out
end

-- The panel's menu as the player opens it: the profession radios, the buttons, the titles.
local function menu()
    local m = { profs = {}, buttons = {}, titles = {} }
    local root = {}
    local function entry(rec)
        function rec:SetResponse(r) self.response = r end
        function rec:SetEnabled() end
        return rec
    end
    function root.CreateTitle(_, text) m.titles[#m.titles + 1] = text; return entry({ text = text }) end
    function root.CreateRadio(_, text, get, set, data)
        if type(data) == "string" then return entry({}) end
        m.profs[#m.profs + 1] = entry({ text = text, get = get, set = set, data = data })
        return m.profs[#m.profs]
    end
    function root.CreateCheckbox() return entry({}) end
    function root.CreateButton(_, text, fn)
        m.buttons[#m.buttons + 1] = entry({ text = text, fn = fn })
        return m.buttons[#m.buttons]
    end
    World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    GL.RouteMenu(UIParent)
    return m
end

T.test("the panel draws no Next up section", function()
    scene({ [HERB] = 50, [MINE] = 50 })
    World.set(GL, "nextOpen", true)
    World.set(CP.charDB, "nextStep", { [ALCHEMY] = { name = "Alchemy", skill = 50, to = 60 } })
    local s = sections()
    T.ok(s[HERB] and s[MINE], "the gathering sections still draw")
    T.eq(s.next, nil, "no Next up")
    for _, l in ipairs((GL.Drawn())) do T.ok(l.text ~= "Next up", "no Next up line") end
end)

T.test("one picked profession draws only its own section; All draws every one", function()
    scene({ [HERB] = 50, [MINE] = 50 })
    local all = sections()
    T.ok(all[HERB] and all[MINE], "All shows both")
    GL.SetPanelProf(MINE)
    local s = sections()
    T.ok(s[MINE], "Mining shows")
    T.eq(s[HERB], nil, "and Herbalism does not")
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "item" then T.ok(l.row.prof == MINE, "only ore rows: " .. tostring(l.row.prof)) end
    end
    GL.SetPanelProf(nil)
    T.ok(sections()[HERB], "back to All")
end)

T.test("the menu's radios are All plus each profession, and picking one at a time saves it", function()
    scene({ [HERB] = 50, [MINE] = 50 })
    local m = menu()
    T.eq(#m.profs, 3, "All, Herbalism, Mining")
    T.eq(m.profs[1].text, GL.ALL_LABEL)
    T.ok(m.profs[1].get(m.profs[1].data), "All is picked to start")
    for _, r in ipairs(m.profs) do T.eq(r.response, MenuResponse.Refresh, r.text .. " keeps the menu open") end
    local mining
    for _, r in ipairs(m.profs) do if r.data == MINE then mining = r end end
    T.eq(mining.set(mining.data), MenuResponse.Refresh)
    T.eq(CP.charDB.panelProf, MINE, "saved on the character")
    m = menu()
    local on = 0
    for _, r in ipairs(m.profs) do if r.get(r.data) then on = on + 1 end end
    T.eq(on, 1, "exactly one radio is on")
    T.ok(not m.profs[1].get(m.profs[1].data), "All is off")
    m.profs[1].set(m.profs[1].data)
    T.eq(CP.charDB.panelProf, nil, "All clears it")
end)

T.test("a pick the character no longer has falls back to All", function()
    scene({ [HERB] = 50, [MINE] = 50 })
    GL.SetPanelProf(MINE)
    T.eq(GL.PanelProf(), MINE)
    World.set(G, "Skills", function() return { [HERB] = 50 } end)
    T.eq(GL.PanelProf(), nil, "Mining is gone")
    local s = sections()
    T.ok(s[HERB], "everything the character has shows again")
end)

T.test("a pattern row belongs to its profession: one pick shows only that profession's", function()
    scene({ [HERB] = 50, [MINE] = 50, [ALCHEMY] = 30, [LW] = 30 })
    local alch = { item = 1, name = "A", skill = 10, npcs = {} }
    local lw = { item = 2, name = "L", skill = 20, npcs = {} }
    World.set(CP.charDB, "vendorWatch", { [ALCHEMY] = { alch }, [LW] = { lw } })
    local current = { zone = DUROTAR, found = {
        { buy = alch, target = { name = "V", x = 1, y = 1 } },
        { buy = lw, target = { name = "V", x = 1, y = 1 } },
    } }
    local function count()
        local head = GL.PatternLines(current)[1]
        return head and tonumber(head.info) or 0
    end
    T.eq(count(), 2, "All: both")
    T.eq(#GL.PanelProfs(), 4, "two gathering and two crafting choices")
    GL.SetPanelProf(ALCHEMY)
    T.eq(count(), 1, "Alchemy: its own")
    GL.SetPanelProf(MINE)
    T.eq(count(), 0, "Mining: none")
    GL.SetPanelProf(nil)
end)
