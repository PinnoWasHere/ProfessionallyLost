-- Event churn: what each game event costs in solves and redraws. The harness stubs
-- collectgarbage to 0, so these count calls (plan solves, Panel:Refresh,
-- GatherList.Refresh) instead of memory. A plan solve is Plan.Solve (an open window) or
-- Plan.Offline (a shut one); each runs one main Solver.Plan and one more per "or" row
-- and fallback it looks for, counted apart.

local CP = ProfLost
local W, P, GP = CP.Window, CP.Panel, CP.GatherPanel
local LW, TAILOR, ALCHEMY, ENCHANTING, COOKING, FIRST_AID = 165, 197, 171, 333, 185, 129
local MINING, HERBALISM, SKINNING = 186, 182, 393
local DUROTAR = 1411
local HEARTHSTONE = 6948      -- in no guide
local LINEN_BOLT = 2996       -- Tailoring's prep: a held count its plan reads

-- Counts solves (by guide), panel redraws and checklist rebuilds from now on.
local function counter()
    local c = {}
    function c.reset()
        c.solves, c.plans, c.byGuide, c.panel, c.list = 0, 0, {}, 0, 0
    end
    c.reset()
    local function solved(guide)
        if not guide then return end
        c.solves = c.solves + 1
        c.byGuide[guide.name] = (c.byGuide[guide.name] or 0) + 1
    end
    local offline, solve, plan = CP.Plan.Offline, CP.Plan.Solve, CP.Solver.Plan
    World.set(CP.Plan, "Offline", function(guide, ...)
        solved(guide)
        return offline(guide, ...)
    end)
    World.set(CP.Plan, "Solve", function(p, ...)
        solved(CP.Guide.For(p))
        return solve(p, ...)
    end)
    World.set(CP.Solver, "Plan", function(...)
        c.plans = c.plans + 1
        return plan(...)
    end)
    local refresh = P.Refresh
    World.set(P, "Refresh", function(self, ...)
        c.panel = c.panel + 1
        return refresh(self, ...)
    end)
    local list = CP.GatherList.Refresh
    World.set(CP.GatherList, "Refresh", function(...)
        c.list = c.list + 1
        return list(...)
    end)
    return c
end

-- The owner's scene: six guided crafts and three gathering skills, all shut, the
-- window free in All mode with the gathering panel open. Settles before counting.
local function scene(show)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [ALCHEMY] = 50, [ENCHANTING] = 80,
        [COOKING] = 70, [FIRST_AID] = 90, [MINING] = 60, [HERBALISM] = 40, [SKINNING] = 90 } })
    World.set(CP.db, "hideInCombat", show == "nocombat")
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "gatherOpen", true)
    World.onEnd(function()
        T.fire("PLAYER_REGEN_ENABLED")
        W.opened = false
        W.Update()
    end)
    CP.Settings.Find("hideInCombat").apply()
    W.SetMode("all")
    GP.Layout()
    T.fire("SKILL_LINES_CHANGED")
    T.advance(2)
    T.ok(P.frame:IsShown(), "the window shows")
    return counter()
end

local function shown(c)
    return ("%d solves (%d Solver.Plan), %d panel redraws, %d checklist rebuilds"):format(c.solves, c.plans, c.panel,
        c.list)
end

T.test("a bag update that changes no held count does no solve in All mode", function()
    local c = scene()
    CraftWorld.SetBag(HEARTHSTONE, 1)
    T.advance(2)
    T.eq(c.solves, 0, "solves after an unrelated bag update (" .. shown(c) .. ")")
    T.eq(c.plans, 0, "no Solver.Plan either (" .. shown(c) .. ")")
    T.ok(c.panel <= 1, "one panel redraw at most (" .. shown(c) .. ")")
end)

T.test("a bag update that moves a held count re-solves only that profession", function()
    local c = scene()
    CraftWorld.SetBag(LINEN_BOLT, 5)
    T.advance(2)
    T.eq(c.byGuide[CP.Guides[TAILOR].name], 1, "Tailoring re-solves once (" .. shown(c) .. ")")
    T.eq(c.solves, 1, "nothing else re-solves (" .. shown(c) .. ")")
end)

T.test("a skill event that moves no profession's rank does nothing", function()
    local c = scene()
    T.fire("SKILL_LINES_CHANGED")
    T.fire("CHAT_MSG_SKILL", "Your skill in Swords has increased to 41.")
    T.advance(2)
    T.eq(c.solves, 0, "solves (" .. shown(c) .. ")")
    T.eq(c.plans, 0, "Solver.Plan (" .. shown(c) .. ")")
    T.eq(c.panel, 0, "panel redraws (" .. shown(c) .. ")")
    T.eq(c.list, 0, "checklist rebuilds (" .. shown(c) .. ")")
end)

T.test("a guided skill-up solves each shut profession at most once", function()
    local c = scene()
    CraftWorld.SetSkill(TAILOR, 61)
    T.fire("CHAT_MSG_SKILL", "Your skill in Tailoring has increased to 61.")
    T.advance(3)
    for name, n in pairs(c.byGuide) do T.ok(n <= 1, ("%s solved %d times"):format(name, n)) end
    T.eq(c.byGuide[CP.Guides[TAILOR].name], 1, "Tailoring re-solves (" .. shown(c) .. ")")
    T.ok(c.panel <= 2, "two panel redraws at most (" .. shown(c) .. ")")
    T.ok(c.list <= 2, "two checklist rebuilds at most (" .. shown(c) .. ")")
end)

T.test("an item load ProfLost never asked for redraws nothing", function()
    local c = scene()
    T.fire("GET_ITEM_INFO_RECEIVED", 999999, true)
    T.advance(1)
    T.eq(c.panel, 0, "panel redraws (" .. shown(c) .. ")")
    T.eq(c.list, 0, "checklist rebuilds (" .. shown(c) .. ")")
    T.ok(CP.RequestItem ~= nil, "CP.RequestItem")
    CP.RequestItem(999998)
    T.fire("GET_ITEM_INFO_RECEIVED", 999998, true)
    T.advance(1)
    T.eq(c.panel, 1, "an asked-for item redraws the panel once (" .. shown(c) .. ")")
    T.fire("GET_ITEM_INFO_RECEIVED", 999998, true)
    T.advance(1)
    T.eq(c.panel, 1, "only the first load of it counts (" .. shown(c) .. ")")
end)

-- Counts recipe list reads and recipe lookups from now on.
local function reads()
    local n = { lists = 0, infos = 0 }
    local TS = C_TradeSkillUI
    local all, info = TS.GetAllRecipeIDs, TS.GetRecipeInfo
    World.set(TS, "GetAllRecipeIDs", function(...)
        n.lists = n.lists + 1
        return all(...)
    end)
    World.set(TS, "GetRecipeInfo", function(...)
        n.infos = n.infos + 1
        return info(...)
    end)
    return n
end

T.test("an open window's plan, asked for again with nothing changed, reads no recipe", function()
    scene()
    CraftWorld.Open(TAILOR)
    T.advance(2)
    T.ok(CP.Plan.Current() ~= nil, "Tailoring's plan")
    local n = reads()
    for _ = 1, 5 do CP.Plan.Current() end
    P:Refresh()
    W.SetMode("one")
    W.SetMode("all")
    T.advance(2)
    T.eq(n.lists .. " lists, " .. n.infos .. " recipes", "0 lists, 0 recipes", "reads")
end)

T.test("an event that can change the recipe list re-reads it once", function()
    scene()
    CraftWorld.Open(TAILOR)
    T.advance(2)
    local size = #C_TradeSkillUI.GetAllRecipeIDs()

    -- TRADE_SKILL_LIST_UPDATE also follows every craft: with the same ids it reads only them.
    local cases = { { "TRADE_SKILL_LIST_UPDATE", "1 lists, 0 recipes" },
                    { "NEW_RECIPE_LEARNED", "1 lists, " .. size .. " recipes" } }
    for _, case in ipairs(cases) do
        local event = case[1]
        local n = reads()
        T.fire(event)
        T.advance(2)
        for _ = 1, 3 do CP.Plan.Current() end
        T.eq(n.lists .. " lists, " .. n.infos .. " recipes", case[2], event)
        World.finish()
        scene()
        CraftWorld.Open(TAILOR)
        T.advance(2)
    end
end)

T.test("a combat transition redraws the panel once", function()
    for _, show in ipairs({ "nocombat", "always" }) do
        local c = scene(show)
        T.fire("PLAYER_REGEN_DISABLED")
        T.advance(0.5)
        T.fire("PLAYER_REGEN_ENABLED")
        T.advance(1)
        T.ok(P.frame:IsShown(), show .. ": shown after combat")
        T.ok(c.panel <= 1, show .. ": one panel redraw at most (" .. shown(c) .. ")")
        T.ok(c.list <= 1, show .. ": one checklist rebuild at most (" .. shown(c) .. ")")
        if show == "nocombat" then T.eq(c.panel, 1, "the window shows again redrawn (" .. shown(c) .. ")") end
        World.finish()
    end
end)

T.test("a folded gathering panel defers its rebuild until it opens", function()
    local c = scene()
    GP.Toggle()
    T.ok(not GP.IsOpen(), "folded")
    c.reset()
    T.fire("ZONE_CHANGED_NEW_AREA")
    CraftWorld.SetBag(HEARTHSTONE, 2)
    T.advance(2)
    T.eq(c.list, 0, "no rebuild while folded (" .. shown(c) .. ")")
    GP.Toggle()
    T.eq(c.list, 0, "the click's own frame only starts the slide (" .. shown(c) .. ")")
    T.advance(0.05)
    T.eq(c.list, 1, "one rebuild the frame after it opens (" .. shown(c) .. ")")
    T.advance(1)
    T.eq(c.list, 1, "no second rebuild (" .. shown(c) .. ")")
end)

-- Counts the zone's row builds (Gather.BuildZone) from now on.
local function builds()
    local n = 0
    local build = CP.Gather.BuildZone
    World.set(CP.Gather, "BuildZone", function(...)
        n = n + 1
        return build(...)
    end)
    return function() return n end
end

T.test("bag updates and reopening the gathering panel reuse the zone's rows; a skill-up or a new zone rebuilds them", function()
    local c = scene()
    World.set(CP.db, "route", true)
    GP.Toggle()
    T.ok(not GP.IsOpen(), "folded")
    T.advance(1)
    local n = builds()
    for i = 1, 5 do
        CraftWorld.SetBag(HEARTHSTONE, 2 + i)
        T.advance(0.5)
    end
    T.eq(n(), 0, "a route on the map follows bag updates without rebuilding the zone's rows")
    GP.Toggle()
    T.advance(0.5)
    T.eq(c.list, 1, "the checklist rebuilt once")
    T.eq(n(), 0, "from the zone's kept rows")
    CraftWorld.SetSkill(SKINNING, 95)
    T.fire("CHAT_MSG_SKILL", "Your skill in Skinning has increased to 95.")
    T.advance(2)
    T.eq(n(), 1, "a gathering skill-up builds them once")
    MapWorld.begin({ zone = 1413, level = 30, side = "Horde" })
    T.fire("ZONE_CHANGED_NEW_AREA")
    T.advance(1)
    T.eq(n(), 2, "a new zone builds its own")
end)

T.test("/proflost mem counts events and jobs while on, and nothing while off", function()
    scene()
    SlashCmdList.PROFLOST("mem on")
    T.fire("BAG_UPDATE_DELAYED")
    T.fire("BAG_UPDATE_DELAYED")
    T.advance(1)
    local before = #T.prints()
    SlashCmdList.PROFLOST("mem")
    local out = {}
    for i = before + 1, #T.prints() do out[#out + 1] = tostring(T.prints()[i]) end
    local text = table.concat(out, "\n")
    T.ok(text:find("BAG_UPDATE_DELAYED") and text:find("2 calls"), text)
    T.ok(text:find("soon:refresh"), text)
    SlashCmdList.PROFLOST("mem off")
    T.fire("BAG_UPDATE_DELAYED")
    before = #T.prints()
    SlashCmdList.PROFLOST("mem")
    local last = tostring(T.prints()[#T.prints()])
    T.ok(#T.prints() == before + 1 and last:find("off"), last)
end)
