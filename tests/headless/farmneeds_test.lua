-- Farm weighs no guide need (owner, 2026-11-15: Farm is for gathering to sell; Follow the
-- guide is the mode for guide needs). A character whose guides need meat, herbs, ore and
-- leather sees the same Farm panel, menu, route, grind spots, other zones and Nearby zones as
-- the same character with no guide needs. Follow the guide still routes the needs.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local HBD = LibStub("HereBeDragons-2.0")
local SKIN, HERB, MINE, COOK = 393, 182, 186, 185
local LW, ALCHEMY, BS = 165, 171, 164
local DUROTAR = 1411
local MEAT, PEACEBLOOM, COPPER, LIGHT = 769, 2447, 2770, 2318

local NEEDS = { [COOK] = { [MEAT] = 40 }, [ALCHEMY] = { [PEACEBLOOM] = 30 }, [BS] = { [COPPER] = 50 },
                [LW] = { [LIGHT] = 60 } }

-- The player in Durotar at level 12 with Skinning, Herbalism, Mining and Cooking, the guides'
-- needs `needs`, in `mode`, other zones off.
local function scene(needs, mode)
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = 12, side = "Horde" })
    World.set(HBD, "GetWorldCoordinatesFromZone", function(_, x, y, z) return x * 1000 + z, y * 1000, 1 end)
    for _, key in ipairs({ "routeSkip", "skinSkip", "gatherClosed", "farmClosed" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "routeMode", mode)
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.charDB, "gatherNeeds", needs)
    World.set(CP.charDB, "gatherSoon", needs)
    local ranks = { [SKIN] = 60, [HERB] = 60, [MINE] = 60, [COOK] = 60 }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = ranks[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 150 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    G.ResetClusters()
    RM.Forget()
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
        G.ResetClusters()
    end)
end

-- The route menu's lines as the player reads them.
local function menuLines()
    local out = {}
    local root = {}
    local function entry(rec)
        function rec:SetResponse() end
        function rec:SetEnabled() end
        return rec
    end
    function root.CreateTitle(_, text) out[#out + 1] = "title " .. tostring(text); return entry({}) end
    function root.CreateRadio(_, text) out[#out + 1] = "radio " .. tostring(text); return entry({}) end
    function root.CreateCheckbox(_, text) out[#out + 1] = "check " .. tostring(text); return entry({}) end
    function root.CreateButton(_, text) out[#out + 1] = "button " .. tostring(text); return entry({}) end
    World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen)
        wipe(out)
        gen(owner, root)
    end)
    GL.RouteMenu(UIParent)
    return out
end

-- The tooltip a stop pin shows, line by line.
local function stopTip(stop)
    local f = RM.TestStop()
    f.stop = stop
    local lines = {}
    World.patch("GameTooltip.AddLine", function(_, text) lines[#lines + 1] = tostring(text) end)
    World.patch("GameTooltip.AddDoubleLine", function(_, a, b) lines[#lines + 1] = tostring(a) .. "|" .. tostring(b) end)
    f:GetScript("OnEnter")(f)
    return table.concat(lines, " / ")
end

-- Everything Farm shows and the map follows, after every solve ends.
local function view()
    GL.Refresh()
    local frames = 0
    repeat
        T.advance(0.05, 0.05)
        frames = frames + 1
    until not (CP.GatherGuide.Warming() or RM.Solving() or RM.Passing()) or frames > 8000
    GL.Refresh()
    local v = { panel = {}, route = {}, spots = {}, others = {}, menu = menuLines(), tips = {} }
    for _, l in ipairs((GL.Drawn())) do
        v.panel[#v.panel + 1] = table.concat({ l.kind, tostring(l.text), tostring(l.info) }, "|")
    end
    for _, r in ipairs(GL.RouteRows(DUROTAR, nil, true)) do
        local names = {}
        for _, s in ipairs(r.sources) do names[#names + 1] = s.name end
        table.sort(names)
        v.route[#v.route + 1] = r.itemID .. ":" .. table.concat(names, ",")
    end
    table.sort(v.route)
    for _, s in ipairs((RM.Spots())) do
        v.spots[#v.spots + 1] = ("%.4f,%.4f %s"):format(s.x, s.y, RM.SpotFor(s))
    end
    for _, z in ipairs(RM.Others()) do v.others[#v.others + 1] = tostring(z) end
    for _, p in ipairs((RM.Stops())) do v.tips[#v.tips + 1] = stopTip(p) end
    return v
end

local function same(a, b, what)
    for _, part in ipairs({ "panel", "route", "spots", "others", "menu", "tips" }) do
        local x, y = a[part], b[part]
        for i = 1, math.max(#x, #y) do
            if x[i] ~= y[i] then
                T.ok(false, ("%s: %s #%d with needs %s, without %s"):format(what, part, i, tostring(x[i]),
                    tostring(y[i])))
                break
            end
        end
    end
end

local function routes(v, item)
    for _, r in ipairs(v.route) do
        if r:sub(1, #tostring(item) + 1) == item .. ":" then return true end
    end
    return false
end

T.test("Farm with guide needs equals Farm without them", function()
    scene(nil, "farm")
    local plain = view()
    T.ok(#plain.route > 0 and #plain.panel > 0, "Farm has something to show in Durotar")
    scene(NEEDS, "farm")
    local needy = view()
    T.ok(routes(needy, MEAT), "Farm's Cooking spots hold Chunk of Boar Meat as a sellable, need or none")
    T.ok(routes(plain, MEAT), "and without any need")
    same(needy, plain, "Farm")
end)

T.test("Farm's menu and stops name no guide need", function()
    scene(NEEDS, "farm")
    local v = view()
    for _, line in ipairs(v.menu) do T.ok(not line:find("need %d"), "menu: " .. line) end
    for _, tip in ipairs(v.tips) do T.ok(not tip:find("Your guides need", 1, true), "stop: " .. tip) end
end)

T.test("Follow the guide still routes the guides' needs", function()
    scene(NEEDS, nil)
    local v = view()
    T.ok(routes(v, MEAT), "the meat need has grind spots in the guide")
    T.ok(routes(v, PEACEBLOOM) and routes(v, COPPER), "herb and ore needs on the loop")
end)
