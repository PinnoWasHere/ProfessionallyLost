-- Zone gathering checklist against the generated Data/Gather.lua.

local CP = ProfLost
local G = CP.Gather
local BARRENS, DEADWIND = 1413, 1430
local LIGHT_LEATHER, STRIDER_MEAT, COPPER_ORE, BRUISEWEED = 2318, 5469, 2770, 2453

local function find(rows, id)
    for _, r in ipairs(rows) do
        if r.itemID == id then return r end
    end
end

local function sourceNamed(row, name)
    for _, s in ipairs(row and row.sources or {}) do
        if s.name == name then return s end
    end
end

T.test("corpse skill follows the vanilla rule", function()
    T.eq(G.CorpseSkill(5), 1)
    T.eq(G.CorpseSkill(10), 1)
    T.eq(G.CorpseSkill(12), 20)
    T.eq(G.CorpseSkill(20), 100)
    T.eq(G.CorpseSkill(40), 200)
end)

T.test("nothing to gather without a gathering profession", function()
    T.eq(#G.ForZone(BARRENS, {}), 0)
end)

T.test("skinning sources are limited to what the skill can skin", function()
    for _, row in ipairs(G.ForZone(BARRENS, { [G.SKINNING] = 1 })) do
        for _, s in ipairs(row.sources) do
            T.ok(s.skill <= 1, s.name .. " needs " .. tostring(s.skill))
        end
    end
    local leather = find(G.ForZone(BARRENS, { [G.SKINNING] = 100 }), LIGHT_LEATHER)
    T.ok(leather ~= nil, "Light Leather at Skinning 100")
    local strider = sourceNamed(leather, "Fleeting Plainstrider")
    T.ok(strider ~= nil, "from Fleeting Plainstriders")
    T.eq(strider.skill, 20)
    T.ok(strider.chance > 50)
end)

T.test("sources are sorted by chance", function()
    local leather = find(G.ForZone(BARRENS, { [G.SKINNING] = 300 }), LIGHT_LEATHER)
    for i = 2, #leather.sources do
        T.ok(leather.sources[i - 1].chance >= leather.sources[i].chance)
    end
end)

T.test("nodes need the lock's skill", function()
    T.ok(find(G.ForZone(BARRENS, { [G.MINING] = 1 }), COPPER_ORE) ~= nil)
    T.ok(find(G.ForZone(BARRENS, { [G.HERBALISM] = 50 }), BRUISEWEED) == nil, "Bruiseweed needs 100")
    T.ok(find(G.ForZone(BARRENS, { [G.HERBALISM] = 100 }), BRUISEWEED) ~= nil)
end)

T.test("cooking drops show only with Cooking", function()
    T.ok(find(G.ForZone(BARRENS, { [G.SKINNING] = 300 }), STRIDER_MEAT) == nil)
    local meat = find(G.ForZone(BARRENS, { [G.COOKING] = 1 }), STRIDER_MEAT)
    T.ok(meat ~= nil, "Strider Meat with Cooking")
    T.eq(meat.prof, G.COOKING)
    T.eq(meat.sources[1].kind, "mob")
end)

T.test("fishing shows open water with its land chance", function()
    local rows = G.ForZone(BARRENS, { [G.FISHING] = 1 })
    T.ok(#rows > 0)
    local water
    for _, r in ipairs(rows) do
        for _, s in ipairs(r.sources) do
            if s.kind == "water" then water = s end
        end
    end
    T.ok(water ~= nil)
    T.eq(water.land, 26, "base -20 at skill 1")
    T.eq(G.LandChance(200, -20), 100)
    T.eq(G.LandChance(1, 330), 0)
    for _, r in ipairs(G.ForZone(DEADWIND, { [G.FISHING] = 1 })) do
        for _, s in ipairs(r.sources) do T.ok(s.kind ~= "water", "Deadwind water at skill 1") end
    end
end)

T.test("short for the current cap first, then short for later, then finished", function()
    local count = { [LIGHT_LEATHER] = 5, [COPPER_ORE] = 0 }
    local have = function(id) return count[id] or 0 end
    local skills = { [G.SKINNING] = 300, [G.MINING] = 300 }
    local rows = G.Rows(BARRENS, skills, { [LIGHT_LEATHER] = 200, [COPPER_ORE] = 30 }, have, nil, nil,
        { [COPPER_ORE] = 10 })
    T.eq(rows[1].itemID, COPPER_ORE, "needed now beats a bigger later shortfall")
    T.eq(rows[2].itemID, LIGHT_LEATHER)
    T.ok(rows[2].soonDone and not rows[2].done)
end)

T.test("needed items come first, unfinished before finished", function()
    local count = { [LIGHT_LEATHER] = 5, [COPPER_ORE] = 40 }
    local have = function(id) return count[id] or 0 end
    local skills = { [G.SKINNING] = 300, [G.MINING] = 300 }
    local rows = G.Rows(BARRENS, skills, { [LIGHT_LEATHER] = 20, [COPPER_ORE] = 30 }, have)
    T.eq(rows[1].itemID, LIGHT_LEATHER)
    T.ok(not rows[1].done)
    T.eq(rows[2].itemID, COPPER_ORE)
    T.ok(rows[2].done, "40 of 30 is done")
    T.eq(rows[3].need, nil)
end)

T.test("needs are saved from the queue for the profession", function()
    CP.charDB.gatherNeeds = nil
    local lw = CP.Guides[165]
    G.SaveNeeds({ guide = lw, prof = { skill = 80, max = 150 }, plan = lw.steps, learned = {} })
    local needs = CP.charDB.gatherNeeds[165]
    T.ok(needs ~= nil)
    T.ok((needs[LIGHT_LEATHER] or 0) > 0, "Light Leather to reach 150")
    T.eq(G.Needs()[LIGHT_LEATHER], needs[LIGHT_LEATHER])
    local soon = CP.charDB.gatherSoon[165]
    T.ok(soon and soon[LIGHT_LEATHER] and soon[LIGHT_LEATHER] <= needs[LIGHT_LEATHER], "to 150 is part of to 300")
    local total = 0
    for _ in pairs(needs) do total = total + 1 end
    local near = 0
    for _ in pairs(soon) do near = near + 1 end
    T.ok(total > near, "later ranks add materials the current cap doesn't need")
end)

T.test("lines hold only items a guide uses, by profession", function()
    CP.db.gatherClosed = nil
    -- No listed zone: its skill-ups and grind spots would join the lines.
    World.set(CP.GatherList, "zone", nil)
    local skills = { [G.SKINNING] = 300, [G.MINING] = 300 }
    local rows = G.Rows(BARRENS, skills, { [LIGHT_LEATHER] = 20, [COPPER_ORE] = 5 }, function() return 0 end)
    local lines = CP.GatherList.Lines(rows, skills)
    T.eq(#lines, 6, "two sections, a guide-needs heading and one item each")
    T.eq(lines[1].text, "Skinning 300")
    T.eq(lines[2].text, CP.GatherList.GUIDE_HEAD)
    T.eq(lines[2].info, "have / need", "the column note sits on the guide-needs heading")
    T.eq(lines[3].row.itemID, LIGHT_LEATHER)
    T.eq(lines[3].info, "0 / 20")
    T.eq(lines[4].text, "Mining 300")
    T.eq(lines[5].text, CP.GatherList.GUIDE_HEAD)
    T.eq(lines[6].row.itemID, COPPER_ORE)
    T.eq(#CP.GatherList.Lines(G.Rows(BARRENS, skills, {}, function() return 0 end), skills), 0,
        "nothing when no guide uses anything here")
    local text = CP.GatherList.SourceText({ kind = "mob", name = "x", minLevel = 12, maxLevel = 13,
        skill = 20, chance = 61.2 })
    T.eq(text, "lvl 12-13 · 61%")
    T.eq((CP.GatherList.SourceText({ kind = "water", name = "x", chance = 50, land = 26 })), "50% · lands 26%")
end)

T.test("grey creatures are left out", function()
    T.eq(G.GreyLevel(5), 0)
    T.eq(G.GreyLevel(30), 22)
    T.eq(G.GreyLevel(60), 51)
    local scraps = find(G.ForZone(BARRENS, { [G.SKINNING] = 300 }, { greyLevel = 20 }), 2934)
    T.ok(sourceNamed(scraps, "Plainstrider") == nil, "level 1-2 Plainstriders hidden at player level 30")
end)

T.test("creatures and nodes the game places outside the zone are left out", function()
    local here = function(kind, entry) return not (kind == "mobs" and CP.GatherData.mobs[entry][1]:find("Bloodfen")) end
    local all = G.ForZone(BARRENS, { [G.COOKING] = 1 })
    local kept = G.ForZone(BARRENS, { [G.COOKING] = 1 }, { here = here })
    local function bloodfen(rows)
        for _, r in ipairs(rows) do
            for _, s in ipairs(r.sources) do if s.name:find("Bloodfen") then return true end end
        end
    end
    T.ok(bloodfen(all), "the rectangle data lists Dustwallow raptors")
    T.ok(not bloodfen(kept))
end)

T.test("a fish files under Fishing when it's caught here", function()
    local rows = G.ForZone(BARRENS, { [G.COOKING] = 1, [G.FISHING] = 300 })
    for _, r in ipairs(rows) do
        local caught
        for _, s in ipairs(r.sources) do caught = caught or s.kind == "water" end
        if caught and r.best >= 20 then T.eq(r.prof, G.FISHING, tostring(r.itemID)) end
    end
end)

T.test("the gathering checklist lists the zone's rows and keeps them through combat", function()
    -- Needs come from the stub below only: no background re-plan (the stubbed skill
    -- list has no Leatherworking) and no open panel left by an earlier file re-saving them.
    local updateAll = G.UpdateAllNeeds
    G.UpdateAllNeeds = function() end
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id)
        return id == 393 and { skillID = 393, rank = 120, modifier = 0 } or nil
    end)
    World.patch("C_Map.GetMapInfo", function() return { mapType = 3, mapID = BARRENS, name = "The Barrens" } end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(_G, "UnitLevel", function() return 20 end)
    CP.charDB.gatherNeeds = { [165] = { [LIGHT_LEATHER] = 20 } }
    local zone, inZone = CP.Waypoint.PlayerZone, G.InZone
    CP.Waypoint.PlayerZone = function() return BARRENS end
    G.InZone = function() return true end
    local f = CP.GatherList.frame
    T.eq(f:GetParent(), CP.GatherPanel.body, "drawn in the gathering panel")
    T.ok(CP.GatherList.Refresh())
    T.advance(1)
    T.ok(f:IsShown(), "shown out of combat")
    T.ok(CP.GatherList.shown > 0, "rows drawn")
    T.fire("PLAYER_REGEN_DISABLED")
    T.advance(1)
    T.ok(f:IsShown() and CP.GatherList.shown > 0, "the tab keeps its rows in combat; the window decides what shows")
    T.fire("PLAYER_REGEN_ENABLED")
    T.advance(1)
    G.UpdateAllNeeds = updateAll
    CP.Waypoint.PlayerZone, G.InZone = zone, inZone
end)

T.test("needs are planned at login from the skill list, without a profession window", function()
    CP.charDB.gatherNeeds, CP.charDB.learned, CP.charDB.lastPlan = nil, nil, nil
    -- No profession window: an earlier file's stubbed profession must not count as open.
    World.set(C_TradeSkillUI, "GetBaseProfessionInfo", function() return { professionID = 0 } end)
    local collect = CP.db.collect
    CP.db.collect = false  -- the harness has no professions, so Level-as-you-go would filter out leather
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id)
        if id == 165 then return { skillID = 165, rank = 80, modifier = 0, maxRank = 150 } end
        return nil
    end)
    G.UpdateAllNeeds()
    local needs = CP.charDB.gatherNeeds and CP.charDB.gatherNeeds[165]
    T.ok(needs ~= nil, "Leatherworking needs saved")
    T.ok((needs[LIGHT_LEATHER] or 0) > 0)
    T.eq(CP.charDB.gatherNeeds[185], nil, "no Cooking without the skill")
    CP.db.collect = collect
end)

T.test("an opened item lists its sources best first, without rare ones or grind spots of its own", function()
    local mapPos = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(z) return z end
    G.ResetClusters()
    local row = G.Rows(1442, { [G.SKINNING] = 186 }, { [2319] = 196 }, function() return 0 end)
    local medium
    for _, r in ipairs(row) do if r.itemID == 2319 then medium = r end end
    T.ok(medium ~= nil, "Medium Leather in Stonetalon")
    local lines = CP.GatherList.SourceLines(medium, 1442)
    local common = 0
    for _, src in ipairs(medium.sources) do
        if src.chance >= G.SKIN_MIN_CHANCE * 100 then common = common + 1 end
    end
    T.ok(common < #medium.sources, "Stonetalon has rare Medium Leather sources")
    T.eq(#lines, common, "one line a source at the grind-spot chance or better")
    local last = math.huge
    for _, l in ipairs(lines) do
        T.eq(l.rank, nil, "the numbers belong to the map's grind spots")
        T.eq(l.tip[1], l.src.name, "the hover text names the creature")
        T.ok(l.yield <= last + 1e-9, "ranked by yield per clear")
        last = l.yield
    end
    T.ok(lines[1].pin ~= nil, "the best source has a waypoint")
    CP.Waypoint.MapPosZone = mapPos
    G.ResetClusters()
end)
