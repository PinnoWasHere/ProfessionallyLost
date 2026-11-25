-- Skinning in the route filter: the menu's Skinning section picks which materials grind
-- spots are for. Leveling builds spots for ticked materials the guides need; Farming for
-- every ticked material, leaving out only creatures too high for the player. A creature
-- counts for a material at Gather.SKIN_MIN_CHANCE or better. Also: every solved zone's
-- pins stay registered together after an other-zones pass, and /proflost zones.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local HBD = LibStub("HereBeDragons-2.0")
local SKIN = 393
local DUROTAR, BARRENS = 1411, 1413
local LIGHT, MEDIUM, HEAVY, THICK, RUINED = 2318, 2319, 4234, 4304, 2934

-- Scene: the player in `spec.zone` (Durotar) at `spec.level`, with Skinning at
-- `spec.skin` (300), guide needs `spec.needs`, mode `spec.mode` and every skinning material
-- unticked but `spec.ticked` (all when nil). Spawns stay in their data zone.
local function scene(spec, act)
    MapWorld.begin({ zone = spec.zone or DUROTAR, x = 0.5, y = 0.5, level = spec.level or 40, side = "Horde" })
    World.set(HBD, "GetWorldCoordinatesFromZone", function(_, x, y, z) return x * 1000 + z, y * 1000, 1 end)
    local was = { CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.db.skinSkip }
    CP.db.route = true
    CP.db.otherZones = spec.others or false
    CP.db.routeMode = spec.mode
    CP.charDB.gatherNeeds = spec.needs and { [165] = spec.needs } or nil
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN then return { skillID = id, rank = spec.skin or 300, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local mapPos, replan = CP.Waypoint.MapPosZone, G.UpdateAllNeeds
    G.UpdateAllNeeds = function() end
    CP.Waypoint.MapPosZone = function(z) return z end
    G.ResetClusters()
    local ok, err = pcall(function()
        if spec.ticked then
            CP.db.skinSkip = {}
            for _, zone in ipairs({ DUROTAR, BARRENS }) do
                for _, m in ipairs(G.SkinMaterials(zone, G.Skills())) do
                    if not spec.ticked[m.item] then CP.db.skinSkip[m.item] = true end
                end
            end
        end
        act()
    end)
    CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.db.skinSkip, CP.charDB.gatherNeeds = false, nil, nil, nil, nil
    RM.Update(false, {})
    T.advance(1)
    CP.Waypoint.MapPosZone, G.UpdateAllNeeds = mapPos, replan
    G.ResetClusters()
    -- Set back last: a redraw with the route on under this scene's map answers would cache them.
    CP.db.otherZones, CP.db.route, CP.db.routeMode, CP.db.skinSkip = was[1], was[2], was[3], was[4]
    T.ok(ok, err)
end

-- The skinning route rows of `zone`: { [itemID] = { [creature name] = chance } }.
local function skinRows(zone)
    local out = {}
    for _, r in ipairs(GL.RouteRows(zone, nil, true)) do
        for _, src in ipairs(r.sources) do
            if src.kind == "mob" and src.prof == SKIN then
                out[r.itemID] = out[r.itemID] or {}
                out[r.itemID][src.name] = src.chance
            end
        end
    end
    return out
end

local function keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function drawHere()
    GL.RouteOnly()
    T.advance(5)
end

T.test("the threshold is 35% a skin", function()
    T.eq(G.SKIN_MIN_CHANCE, 0.35)
end)

T.test("the menu's skinning materials are this zone's, each with the skill it needs", function()
    scene({}, function()
        local mats = G.SkinMaterials(BARRENS, { [SKIN] = 300 })
        local has = {}
        for _, m in ipairs(mats) do has[m.item] = m.skill end
        T.ok(has[LIGHT] and has[MEDIUM] and has[HEAVY] and has[THICK], table.concat(keys(has), ","))
        T.ok(mats[1].skill <= mats[#mats].skill, "lowest skill first")
        T.eq(#G.SkinMaterials(BARRENS, {}), 0, "nothing without Skinning")
        local low = {}
        for _, m in ipairs(G.SkinMaterials(BARRENS, { [SKIN] = 1 })) do
            low[m.item] = true
            T.ok(m.skill <= 1, ("item %d needs %d"):format(m.item, m.skill))
        end
        T.ok(not low[THICK], "only what the player's Skinning can skin")
        T.ok(not low[RUINED] and not has[RUINED], "Ruined Leather Scraps is never listed")
    end)
end)

T.test("farming with only Light Leather ticked at level 40: spots for Light Leather in a low zone", function()
    scene({ mode = "farm", ticked = { [LIGHT] = true } }, function()
        local rows = skinRows(DUROTAR)
        T.eq(keys(rows), { LIGHT }, "only the ticked material")
        T.ok(rows[LIGHT]["Barrens Kodo"] and rows[LIGHT]["Zhevra Runner"], "decent Light Leather creatures")
        T.eq(rows[LIGHT]["Corrupted Scorpid"], nil, "33% Light is below the threshold")
        T.ok(rows[LIGHT]["Dreadmaw Crocolisk"], "37% Light counts at 35%")
        T.ok(rows[LIGHT]["Armored Scorpid"], "42% Light counts")
        T.eq(rows[LIGHT]["Mottled Boar"], nil, "Ruined-only creatures add nothing")
        drawHere()
        local spots = RM.Spots()
        T.ok(#spots > 0, "grind spots drawn")
        for _, s in ipairs(spots) do T.eq(keys(s.items), { LIGHT }, "spot " .. s.rank .. " is for Light Leather") end
        T.ok(RM.SpotFor(spots[1]):find(CP.ItemName(LIGHT) or ("item " .. LIGHT), 1, true), RM.SpotFor(spots[1]))
    end)
end)

T.test("a creature counts for the ticked leather at 35% or better", function()
    scene({ mode = "farm", ticked = { [LIGHT] = true } }, function()
        -- Barrens: Stormhide skins 42% Light and 50% Medium, Silithid Creeper 38% Light and 56% Medium.
        local rows = skinRows(BARRENS)
        T.ok(rows[LIGHT]["Stormhide"], "42% Light counts")
        T.ok(rows[LIGHT]["Silithid Creeper"], "38% Light counts at 35%")
        for name, chance in pairs(rows[LIGHT]) do T.ok(chance >= 35, name .. " " .. chance) end
        T.eq(rows[MEDIUM], nil, "Medium unticked")
    end)
end)

T.test("Light and Thick ticked, Heavy not: Heavy-only creatures add nothing", function()
    scene({ mode = "farm", level = 45, ticked = { [LIGHT] = true, [THICK] = true } }, function()
        local rows = skinRows(BARRENS)
        T.eq(keys(rows), { LIGHT, THICK })
        T.ok(rows[THICK]["Murk Thresher"], "50% Thick")
        T.eq(rows[THICK]["Rabid Bonepaw"], nil, "17% Thick, 78% Heavy: left out")
        T.eq(rows[THICK]["Hulking Gritjaw Basilisk"], nil, "21% Thick")
        drawHere()
        for _, s in ipairs(RM.Spots()) do
            T.eq(s.items[HEAVY], nil, "no spot counts Heavy Leather")
        end
    end)
end)

T.test("a creature yielding two ticked materials counts both", function()
    scene({ mode = "farm", ticked = { [LIGHT] = true, [MEDIUM] = true } }, function()
        local rows = GL.RouteRows(BARRENS, nil, true)
        local points = CP.Route.Points(BARRENS, rows, nil, "mob", 40)
        local both
        for _, p in ipairs(points) do
            if p.parts["Stormhide"] and p.items[LIGHT] and p.items[MEDIUM] then both = p end
        end
        T.ok(both ~= nil, "a Stormhide stop counts Light and Medium")
        T.ok(both.value >= both.items[LIGHT] + both.items[MEDIUM] - 1e-6, "its value is the sum of both")
    end)
end)

T.test("farming leaves out only creatures too high for the player", function()
    scene({ mode = "farm", level = 30, ticked = { [HEAVY] = true, [THICK] = true, [LIGHT] = true } }, function()
        local rows = skinRows(BARRENS)
        local limit = 30 + G.FARM_SAFE_LEVELS
        for item, list in pairs(rows) do
            for name in pairs(list) do
                for entry, m in pairs(CP.GatherData.mobs) do
                    if m[1] == name and CP.GatherData.zones[BARRENS].mobs[entry] then
                        T.ok(m[2] <= limit, ("%s (%d) for %d"):format(name, m[2], item))
                    end
                end
            end
        end
        T.ok(rows[LIGHT]["Prairie Wolf"], "a level 5 wolf is fine to farm at 30")
        T.ok(rows[HEAVY]["Raging Thunder Lizard"], "33 is within reach")
        T.eq(rows[THICK], nil, "Thick comes only from creatures 37 and up")
    end)
end)

T.test("leveling builds spots for the materials the guides need, Farm's ticks or not", function()
    scene({ needs = { [MEDIUM] = 40 } }, function()
        T.eq(keys(skinRows(BARRENS)), { MEDIUM }, "the needed leather only")
        CP.db.skinSkip = { [MEDIUM] = true }
        T.eq(keys(skinRows(BARRENS)), { MEDIUM }, "unticked in Farm: still built for the guide")
        CP.charDB.gatherNeeds = nil
        CP.db.skinSkip = nil
        T.eq(keys(skinRows(BARRENS)), {}, "nothing needed: no skinning spots")
    end)
end)

T.test("the reset ticks every skinning material again and keeps the mode", function()
    scene({ mode = "farm", ticked = { [LIGHT] = true } }, function()
        T.ok(G.SkinSkipped(MEDIUM))
        local sig = G.RouteSignature()
        GL.RouteReset()
        T.ok(not G.SkinSkipped(MEDIUM), "every material ticked")
        T.ok(G.RouteFarming(), "the mode stays")
        T.ok(sig ~= G.RouteSignature(), "the route is solved again")
    end)
end)

T.test("the route menu's skinning checkboxes untick and stay open", function()
    scene({ mode = "farm" }, function()
        local m = { titles = {}, checks = {}, buttons = {} }
        local root = {}
        local function entry(rec)
            function rec:SetResponse(r) self.response = r end
            return rec
        end
        function root.CreateTitle(_, text) m.titles[#m.titles + 1] = text end
        function root.CreateRadio() return entry({}) end
        function root.CreateCheckbox(_, text, get, set, data)
            m.checks[#m.checks + 1] = entry({ text = text, get = get, set = set, data = data })
            return m.checks[#m.checks]
        end
        function root.CreateButton(_, text, fn)
            m.buttons[#m.buttons + 1] = entry({ text = text, fn = fn })
            return m.buttons[#m.buttons]
        end
        World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
        World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
        GL.RouteMenu(UIParent)
        local light
        for _, c in ipairs(m.checks) do if c.data == LIGHT then light = c end end
        T.ok(light ~= nil, "Light Leather listed")
        T.eq(light.response, MenuResponse.Refresh, "stays open")
        T.ok(light.get(LIGHT), "ticked to start")
        T.eq(light.set(LIGHT), MenuResponse.Refresh)
        T.ok(G.SkinSkipped(LIGHT), "unticked")
        T.eq(m.buttons[1].text, "Show every leather")
    end)
end)

T.test("after a full pass every solved zone's spots are registered at once", function()
    scene({ mode = nil, others = true, needs = { [LIGHT] = 200, [MEDIUM] = 200 } }, function()
        drawHere()
        local pins = RM.PinsByZone()
        local spots, here = RM.Spots()
        T.eq(pins[here], #spots, "the player's zone")
        local n = 0
        for _, z in ipairs(RM.Others()) do
            n = n + 1
            T.ok((pins[z] or 0) > 0, "zone " .. z .. " still registered")
        end
        T.ok(n >= 3, "zones: " .. n)
        -- A redraw of the player's zone alone (a new level) keeps the rest.
        MapWorld.SetLevel(41)
        GL.RouteOnly()
        T.advance(5)
        local after = RM.PinsByZone()
        for _, z in ipairs(RM.Others()) do T.ok((after[z] or 0) > 0, "zone " .. z .. " after a redraw") end
    end)
end)

T.test("/proflost zones prints the pass, its timing and each zone", function()
    scene({ mode = nil, others = true, needs = { [LIGHT] = 200 } }, function()
        drawHere()
        local before = #T.prints()
        SlashCmdList.PROFLOST("zones")
        local out = {}
        for i = before + 1, #T.prints() do out[#out + 1] = tostring(T.prints()[i]) end
        local text = table.concat(out, "\n")
        T.ok(text:find("other zones on; pass done", 1, true), text)
        T.ok(text:find("last pass: %d+ zones looked at, %d+ solved"), text)
        T.ok(text:find("Durotar %(1411, yours%): %d+ rows, %d+ grind spots, %d+ pins drawn"), text)
        T.ok(text:find("The Barrens %(1413%): %d+ rows, %d+ grind spots, %d+ pins drawn"), text)
        T.ok(#out >= 2 + #RM.Others() + 1, "a line per zone")
    end)
end)
