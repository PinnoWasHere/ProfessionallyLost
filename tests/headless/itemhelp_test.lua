-- Item tooltips (guide needs, best farm zone) and needed marks on bag slots.

local CP = ProfLost
local G = CP.Gather
local MEDIUM_LEATHER, LW = 2319, 165

local function withNeeds(needs, fn)
    local saved = CP.charDB.gatherNeeds
    CP.charDB.gatherNeeds = needs
    local savedPos = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(z) return z end   -- the harness has no zone maps

    -- A needs update left queued by an earlier file would replace `needs` while time runs.
    local savedAll, savedSave = G.UpdateAllNeeds, G.SaveNeeds
    G.UpdateAllNeeds, G.SaveNeeds = function() end, function() end

    G.ResetClusters()
    local ok, err = pcall(fn)
    G.UpdateAllNeeds, G.SaveNeeds = savedAll, savedSave
    CP.charDB.gatherNeeds, CP.Waypoint.MapPosZone = saved, savedPos
    G.ResetClusters()
    T.ok(ok, err)
end

T.test("the best zone to farm Medium Leather at level 29 suits the level", function()
    withNeeds({}, function()
        local best = CP.Farm.Best(MEDIUM_LEATHER, { level = 29, side = "Horde", skills = { [G.SKINNING] = 194 } })
        T.ok(best ~= nil, "some zone gives it")
        local z = CP.GatherData.zones[best.zone]
        T.ok(not z.inst, "never a dungeon")
        T.ok(z.lvl[1] <= 32, ("zone %d starts at level %d"):format(best.zone, z.lvl[1]))
        local kalimdor = CP.Farm.Best(MEDIUM_LEATHER, { level = 29, side = "Horde", continent = 1,
            skills = { [G.SKINNING] = 194 } })
        T.eq(CP.GatherData.zones[kalimdor.zone].map, 1, "a Horde player in Kalimdor stays in Kalimdor")
        T.ok(not CP.GatherGuide.SKIP[kalimdor.zone], "never a city")
        T.eq(CP.Farm.Best(MEDIUM_LEATHER, { level = 29, side = "Horde", skills = {} }), nil,
            "without Skinning there is nowhere to farm a skin")
    end)
end)

T.test("an item tooltip says what the guides need, what's held, and where to farm", function()
    withNeeds({ [LW] = { [MEDIUM_LEATHER] = 180 } }, function()
        local saved = { count = C_Item.GetItemCount, skills = G.Skills, level = UnitLevel }
        C_Item.GetItemCount = function() return 42 end
        G.Skills = function() return { [G.SKINNING] = 194 } end
        UnitLevel = function() return 29 end
        local ok, err = pcall(function()
            -- The farm zone is found in the background (Farm.Find); the tooltip names it once found.
            CP.ItemTooltip.Lines(MEDIUM_LEATHER)
            while CP.Farm.Warming() do T.advance(0.02, 0.02) end
            local lines = CP.ItemTooltip.Lines(MEDIUM_LEATHER)
            T.eq(lines[1][1], "Leatherworking needs x180")
            T.eq(lines[2][1], "Have 42 · short x138")
            T.ok(lines[3] and lines[3][1]:find("^Farm in ") ~= nil, "names a zone")
            T.eq(#CP.ItemTooltip.Lines(2318), 0, "an item no guide needs: nothing added")
        end)
        C_Item.GetItemCount, G.Skills, UnitLevel = saved.count, saved.skills, saved.level
        T.ok(ok, err)
    end)
end)

-- A player with Mining and Blacksmithing (Discord, owner approved 2026-11-27): "If I mouse over a bar the
-- tooltip might say I have 30 and still need 70. When I mouse over the equivalent ore it should show I
-- still need 70 bars." Smelt Iron takes 1 Iron Ore a bar, Smelt Bronze 1 Copper Bar and 1 Tin Bar for 2
-- Bronze Bars, Smelt Dark Iron 8 Dark Iron Ore a bar (client SpellReagents and SpellEffect).
T.test("an ore's tooltip says what the guides still need of the bar it smelts into", function()
    local IRON_ORE, IRON_BAR, COPPER_ORE, COPPER_BAR, BRONZE_BAR = 2772, 3575, 2770, 2840, 2841
    local DARK_ORE, DARK_BAR, BS = 11370, 11371, 164
    local held = { [IRON_BAR] = 30, [IRON_ORE] = 12, [COPPER_BAR] = 5 }
    local names = { [IRON_BAR] = "Iron Bar", [COPPER_BAR] = "Copper Bar", [BRONZE_BAR] = "Bronze Bar",
                    [DARK_BAR] = "Dark Iron Bar" }
    withNeeds({ [BS] = { [IRON_BAR] = 100, [COPPER_BAR] = 20, [BRONZE_BAR] = 40, [DARK_BAR] = 10 } }, function()
        local saved = { count = C_Item.GetItemCount, name = C_Item.GetItemNameByID, on = CP.db.itemTooltip }
        C_Item.GetItemCount = function(id) return held[id] or 0 end
        C_Item.GetItemNameByID = function(id) return names[id] end
        local ok, err = pcall(function()
            local lines = CP.ItemTooltip.Lines(IRON_ORE)
            T.eq(lines[1] and lines[1][1], "Smelts into Iron Bar")
            T.eq(lines[2] and lines[2][1], "Blacksmithing needs x100")
            T.eq(lines[3] and lines[3][1], "Have 30 · short x70 (70 ore)", "the bars held count, the ore held does not")
            lines = CP.ItemTooltip.Lines(COPPER_ORE)
            T.eq(lines[1] and lines[1][1], "Smelts into Copper Bar")
            T.eq(lines[2] and lines[2][1], "Blacksmithing needs x20")
            T.eq(lines[3] and lines[3][1], "x20 more for Bronze Bar", "40 Bronze Bars take 20 Copper Bars")
            T.eq(lines[4] and lines[4][1], "Have 5 · short x35 (35 ore)")
            lines = CP.ItemTooltip.Lines(DARK_ORE)
            T.eq(lines[3] and lines[3][1], "Have 0 · short x10 (80 ore)", "8 ore a Dark Iron Bar")
            held[IRON_BAR] = 100
            lines = CP.ItemTooltip.Lines(IRON_ORE)
            T.eq(lines[3] and lines[3][1], "Have 100 · enough")
            for _, l in ipairs(CP.ItemTooltip.Lines(COPPER_BAR)) do
                T.ok(not l[1]:find("^Smelts into"), "a bar's own tooltip names no smelt: " .. l[1])
            end
            local tip = { AddLine = function() end, AddDoubleLine = function() end, Show = function() end }
            CP.db.itemTooltip = true
            T.ok(CP.ItemTooltip.Add(tip, IRON_ORE), "the ore's lines show")
            CP.db.itemTooltip = false
            T.ok(not CP.ItemTooltip.Add(tip, IRON_ORE), "Guide line in item tooltips off: none")
        end)
        C_Item.GetItemCount, C_Item.GetItemNameByID, CP.db.itemTooltip = saved.count, saved.name, saved.on
        T.ok(ok, err)
    end)
end)

T.test("bag slots holding a needed item get a mark, others don't", function()
    withNeeds({ [LW] = { [MEDIUM_LEATHER] = 10 } }, function()
        local slot = CreateFrame("Button", nil, UIParent)
        function slot.GetBagID() return 0 end
        CP.NeededMarks.Update(slot, MEDIUM_LEATHER)
        T.ok(slot.profLostMark and slot.profLostMark:IsShown(), "needed: marked")
        T.eq(slot.profLostMark.prof, LW, "with the icon of the profession that needs it")
        CP.NeededMarks.Update(slot, 2318)
        T.ok(not slot.profLostMark:IsShown(), "not needed: no mark")
        CP.NeededMarks.Update(slot, nil)
        T.ok(not slot.profLostMark:IsShown(), "empty slot: no mark")
        local loot = CreateFrame("Button", nil, UIParent)
        CP.NeededMarks.Update(loot, MEDIUM_LEATHER)
        T.eq(loot.profLostMark, nil, "only bag and bank slots")
    end)
end)

T.test("Daylight UI's bag slots get the mark through Paint, and the setting applies at once", function()
    withNeeds({ [LW] = { [MEDIUM_LEATHER] = 10 } }, function()
        local painter
        local me = { Paint = function(kind, fn) T.eq(kind, "bagslot") painter = fn return {} end }
        local api = { Attach = function(slot) return slot end }
        T.ok(CP.NeededMarks.UseDaylight(me, api))
        local slot = CreateFrame("Button", nil, UIParent)   -- no GetBagID: not a game slot
        painter(slot, {}, { itemID = MEDIUM_LEATHER })
        T.ok(slot.profLostMark and slot.profLostMark:IsShown(), "needed: marked")
        T.eq(slot.profLostMark.prof, LW)
        local was = CP.db.neededMarks
        CP.db.neededMarks = true
        CP.Settings.Set("neededMarks", false)
        T.ok(not slot.profLostMark:IsShown(), "turned off: the mark goes without reopening the bags")
        CP.Settings.Set("neededMarks", true)
        T.ok(slot.profLostMark:IsShown(), "turned on: it comes back")
        painter(slot, {}, { itemID = 2318 })
        T.ok(not slot.profLostMark:IsShown(), "another item: no mark")
        painter(slot, {}, nil)
        T.ok(not slot.profLostMark:IsShown(), "empty slot: no mark")
        CP.db.neededMarks = was
        CP.NeededMarks.Refresh()
    end)
end)

T.test("a Cooking step's fish says how many to catch and where", function()
    local LONGJAW, TIRISFAL = 6289, 1420
    local water = CP.Fishing.WaterFor(LONGJAW, 60, 15, "Horde", function(z) return z == TIRISFAL and 300 or 3000 end)
    T.ok(water ~= nil, "some water lands Longjaw at Fishing 60")
    T.ok(water.land > 0 and water.chance > 0)
    local saved = C_SkillInfo.GetSkillLineInfoByID
    C_SkillInfo.GetSkillLineInfoByID = function(id) if id == 356 then return { rank = 60 } end return saved(id) end
    local ok, text = pcall(CP.GuideTab.FishText, { item = LONGJAW, name = "Raw Longjaw Mud Snapper", short = 52 })
    C_SkillInfo.GetSkillLineInfoByID = saved
    T.ok(ok, text)
    T.ok(text:find("^Fish 52 in ") ~= nil, text)
    T.ok(text:find("Fishing %+%d+$") ~= nil, "the Fishing points those casts give: " .. text)
    T.ok(#text <= 48, "short: " .. #text .. " characters")
end)

T.test("ProfLost's tooltip lines carry a header so they're easy to find", function()
    local saved = { needs = CP.charDB.gatherNeeds, count = C_Item.GetItemCount, on = CP.db.itemTooltip }
    CP.charDB.gatherNeeds = { [165] = { [2319] = 10 } }
    C_Item.GetItemCount = function() return 20 end
    CP.db.itemTooltip = true
    local added = {}
    local tip = { AddLine = function(_, t) added[#added + 1] = t end, AddDoubleLine = function(_, t) added[#added + 1] = t end,
                  Show = function() end }
    local ok, err = pcall(CP.ItemTooltip.Add, tip, 2319)
    CP.charDB.gatherNeeds, C_Item.GetItemCount, CP.db.itemTooltip = saved.needs, saved.count, saved.on
    T.ok(ok, err)
    T.ok(added[2] and added[2]:find("Professionally Lost$") ~= nil, "header after a gap: " .. tostring(added[2]))
end)

T.test("each profession's next step is saved, listed under Next up, and shown by the launcher", function()
    local guide = { recipes = { [1] = { name = "Brilliant Smallfish", learn = 1, yellow = 45, grey = 85, ups = 1,
                                        reagents = { { 6291, 1 } } } } }
    local saved = C_Item.GetItemCount
    C_Item.GetItemCount = function() return 4 end
    local st = CP.Gather.NextStep(guide, { skill = 5, max = 75 }, { { spell = 1, from = 1, to = 50 } }, { [1] = true })
    C_Item.GetItemCount = saved
    T.eq(st.name, "Brilliant Smallfish")
    T.eq(st.to, 50)
    T.ok(st.short > 0, "short of fish: " .. st.short)
    T.ok(st.learned)

    local savedSteps, savedLast = CP.charDB.nextStep, CP.charDB.lastProf
    CP.charDB.nextStep, CP.charDB.lastProf = { [185] = st }, 185
    local ok, err = pcall(function()
        local GL = CP.GatherList
        GL.nextOpen = false
        local lines = GL.NextLines()
        T.eq(#lines, 1, "collapsed: just the header")
        T.eq(lines[1].text, "Next up")
        GL.nextOpen = true
        lines = GL.NextLines()
        T.eq(lines[2].text, "Cooking", "just the profession")
        T.ok(lines[2].tip[1]:find("^Brilliant Smallfish, skill 5 to 50") ~= nil, "the step in the tooltip")
        T.ok(lines[3].text:find(" x" .. st.short .. "$") ~= nil, "the material and how many short: " .. lines[3].text)
        T.eq(lines[3].textColor, CP.Style.color.warn)
        T.ok(lines[3].indent > 18, "under the profession")
        GL.nextOpen = false
        T.eq(CP.Launcher.Text(), "Cooking 5", "short, for narrow data-text slots")
        T.ok(CP.Launcher.object ~= nil, "registered with LibDataBroker")
    end)
    CP.charDB.nextStep, CP.charDB.lastProf = savedSteps, savedLast
    T.ok(ok, err)
end)

T.test("the launcher tooltip lists gathering skills with where to go next, or the rank to train", function()
    local ranks = { [G.SKINNING] = { 120, 150 }, [G.FISHING] = { 75, 75 }, [G.MINING] = { 300, 300 } }
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id)
        local r = ranks[id]
        return r and { skillID = id, rank = r[1], maxRank = r[2], modifier = 0, isHeader = false } or nil
    end)
    World.patch("C_Map.GetMapInfo", function(id) return { mapID = id, name = "Zone " .. id } end)
    withNeeds({}, function()
        MapWorld.SettleGuides({ G.SKINNING })   -- under withNeeds' map answers
        local lines = {}
        local tip = {
            AddLine = function(_, a) lines[#lines + 1] = { a } end,
            AddDoubleLine = function(_, a, b) lines[#lines + 1] = { a, b } end,
        }
        CP.Launcher.object.OnTooltipShow(tip)
        local by = {}
        for _, l in ipairs(lines) do if l[2] then by[l[1]] = l[2] end end
        T.ok(by["Skinning 120"] and by["Skinning 120"]:find("^Zone %d+$") ~= nil,
            "Skinning names a zone: " .. tostring(by["Skinning 120"]))
        T.eq(by["Fishing 75"], "train Journeyman", "at its cap, the rank to train")        T.eq(by["Mining 300"], "maxed")
        T.eq(by["Herbalism 0"], nil, "a skill the player lacks isn't listed")
        T.eq(lines[#lines][1], "Right-click: settings.", "the same click lines as the minimap button")
        T.eq(lines[#lines - 2][1], "Left-click: show or hide the guide window.")
    end)
end)

T.test("a step is ready only when the bags hold every material, not just the first", function()
    -- In game: Toughened Leather Armor showed "ready" with Medium Leather 63/50 but
    -- Cured Light Hide 3/10 and Fine Thread 0/10.
    local guide = { recipes = { [1] = { name = "Toughened Leather Armor", learn = 100, yellow = 130, grey = 160,
        ups = 1, reagents = { { 2319, 10 }, { 4231, 2 }, { 2321, 2 } } } } }
    local have = { [2319] = 63, [4231] = 3, [2321] = 0 }
    World.patch("C_Item.GetItemCount", function(id) return have[id] or 0 end)
    local st = CP.Gather.NextStep(guide, { skill = 116, max = 150 }, { { spell = 1, from = 116, to = 121 } }, { [1] = true })
    T.eq(st.item, 4231, "the first material short: Cured Light Hide")
    T.eq(st.short, 2 * CP.Guide.Crafts(guide.recipes[1], 116, 121) - 3)
    have = { [2319] = 63, [4231] = 30, [2321] = 30 }
    st = CP.Gather.NextStep(guide, { skill = 116, max = 150 }, { { spell = 1, from = 116, to = 121 } }, { [1] = true })
    T.eq(st.short, 0, "everything on hand: ready")

    -- Owner: ready too when the hides can be cured from what's held, Salt aside. Vendor
    -- goods are bought on the way and never count.
    guide.recipes[2] = { name = "Cured Light Hide", learn = 35, yellow = 55, grey = 75, ups = 1,
                         reagents = { { 783, 1 }, { 4289, 1 } } }
    guide.prep = { [4231] = 2 }
    guide.items = { [4289] = { 50, true }, [2321] = { 100, true }, [783] = { 200, false } }
    local steps = { { spell = 1, from = 116, to = 121 } }
    have = { [2319] = 63, [4231] = 3, [783] = 20, [2321] = 30 }
    st = CP.Gather.NextStep(guide, { skill = 116, max = 150 }, steps, { [1] = true, [2] = true })
    T.eq(st.short, 0, "hides curable, salt from a vendor: ready")
    have = { [2319] = 63, [4231] = 3, [783] = 20, [2321] = 2 }
    st = CP.Gather.NextStep(guide, { skill = 116, max = 150 }, steps, { [1] = true, [2] = true })
    -- Owner, Mote of Magic: a vendor good counts when it is all the step lacks.
    T.eq(st.item, 2321, "thread is all the step lacks: buy it")
    T.eq(st.short, 2 * CP.Guide.Crafts(guide.recipes[1], 116, 121) - 2)
    T.eq(st.buy and st.buy.price, 100, "the vendor price")
    T.eq(st.make, nil)
    have = { [2319] = 63, [4231] = 3, [783] = 1, [2321] = 2 }
    st = CP.Gather.NextStep(guide, { skill = 116, max = 150 }, steps, { [1] = true, [2] = true })
    T.eq(st.item, 4231, "hides short too: the thread never counts")
    T.eq(st.buy, nil)
    have = { [2319] = 63, [4231] = 3, [783] = 20, [2321] = 30 }
    st = CP.Gather.NextStep(guide, { skill = 116, max = 150 }, steps, { [1] = true })
    T.eq(st.item, 4231, "curing not learned: the cured hides are short")
    have = { [2319] = 63, [4231] = 3, [783] = 1, [2321] = 30 }
    st = CP.Gather.NextStep(guide, { skill = 116, max = 150 }, steps, { [1] = true, [2] = true })
    -- Playtester on 1.0.0: Next up names the step's own material, as its card does, and
    -- what it's made from second.
    T.eq(st.item, 4231, "too few Light Hides to cure: the step's Cured Light Hide is short")
    T.eq(st.make and st.make.item, 783, "made from Light Hide, the material to get")
    T.eq(st.make and st.make.count, 2 * CP.Guide.Crafts(guide.recipes[1], 116, 121) - 3 - 1, "Light Hides short")
    -- Light Hides only in the bank: ready, but it says the bank is needed.
    local bankHave = { [783] = 20 }
    World.patch("C_Item.GetItemCount", function(id, bank)
        return (have[id] or 0) + (bank and bankHave[id] or 0)
    end)
    st = CP.Gather.NextStep(guide, { skill = 116, max = 150 }, steps, { [1] = true, [2] = true })
    T.eq(st.short, 0, "the bank covers it: ready")
    T.eq(st.bank and st.bank.item, 783, "ready only with the bank: fetch Light Hide")
    bankHave = { [783] = 2 }
    st = CP.Gather.NextStep(guide, { skill = 116, max = 150 }, steps, { [1] = true, [2] = true })
    T.eq(st.item, 4231, "bags and bank together still short")
    T.eq(st.make and st.make.item, 783, "of the Light Hides the cured ones are made from")
    T.ok(not st.bank)
end)

T.test("Next up lists gathering skills under the crafting ones", function()
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id)
        if id == G.SKINNING then return { skillID = id, rank = 209, maxRank = 300, modifier = 0 } end
        if id == G.FISHING then return { skillID = id, rank = 1, maxRank = 75, modifier = 0 } end
    end)
    World.patch("C_Map.GetMapInfo", function(id) return { mapID = id, name = "Zone " .. id } end)
    local savedSteps = CP.charDB.nextStep
    CP.charDB.nextStep = {}
    withNeeds({}, function()
        MapWorld.SettleGuides({ G.SKINNING })   -- under withNeeds' map answers
        local GL = CP.GatherList
        GL.nextOpen = true
        local lines = GL.NextLines()
        GL.nextOpen = false
        T.eq(lines[1].info, "2")
        T.eq(lines[2].text, "Skinning")
        T.ok(lines[3].text:find("^Go to Zone %d+$") ~= nil, lines[3].text)
        T.eq(lines[4].text, "Fishing")
        T.ok(lines[5].text:find("^Go to ") ~= nil, lines[5].text)
    end)
    CP.charDB.nextStep = savedSteps
end)

T.test("opening the Skinning window puts Skinning in the data text, with its rank", function()
    -- Owner: Skinning and Fishing have windows too; the slot only ever showed crafting ones.
    local savedLast = CP.charDB.lastProf
    World.patch("C_TradeSkillUI.GetBaseProfessionInfo", function()
        return { professionID = 393, professionName = "Skinning", skillLevel = 210, maxSkillLevel = 300 }
    end)
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id)
        if id == G.SKINNING then return { skillID = id, rank = 210, maxRank = 300, modifier = 0 } end
    end)
    -- The window opening marks the trade skill open; the test's end puts it back.
    World.set(CP.Professions, "tradeSkillOpen", CP.Professions.tradeSkillOpen)
    T.fire("TRADE_SKILL_SHOW")
    T.eq(CP.charDB.lastProf, G.SKINNING)
    T.eq(CP.Launcher.Text(), "Skinning 210")
    T.eq(CP.Launcher.object.text, "Skinning 210", "the slot updates at once")
    CP.charDB.lastProf = savedLast
    CP.Launcher.Update()
end)

T.test("Next up reads 'Bank: Light Hide x7' when only the bank covers the step", function()
    -- In game (owner, 2026-11-11): a plain "Ready" read as craftable now, though the
    -- Light Hides to cure were in the bank.
    local KEY = 990165
    local guide = { name = "Leatherworking", prep = { [4231] = 2 },
        items = { [4289] = { 50, true }, [2321] = { 100, true }, [783] = { 200, false } },
        recipes = {
            [1] = { name = "Toughened Leather Armor", learn = 100, yellow = 130, grey = 160, ups = 1,
                    reagents = { { 2319, 10 }, { 4231, 2 }, { 2321, 2 } }, makes = 2314 },
            [2] = { name = "Cured Light Hide", learn = 35, yellow = 55, grey = 75, ups = 1,
                    reagents = { { 783, 1 }, { 4289, 1 } } } } }
    local crafts = CP.Guide.Crafts(guide.recipes[1], 116, 121)
    local bags = { [2319] = 63, [4231] = 3, [2321] = 30 }
    local bank = { [783] = 2 * crafts - 3 }
    World.patch("C_Item.GetItemCount", function(id, withBank)
        return (bags[id] or 0) + (withBank and bank[id] or 0)
    end)
    World.patch("C_Item.GetItemNameByID", function(id) return id == 783 and "Light Hide" or nil end)
    local saved = { steps = CP.charDB.nextStep, learned = CP.charDB.learned }
    CP.Guides[KEY] = guide
    CP.charDB.learned = { [KEY] = { 1, 2 } }
    CP.charDB.nextStep = { [KEY] = { name = "Toughened Leather Armor", spell = 1, from = 116, to = 121,
                                     skill = 116, max = 150, short = 0, learned = true } }
    local ok, err = pcall(function()
        CP.GatherList.nextOpen = true
        local lines = CP.GatherList.NextLines()
        local line
        for i, l in ipairs(lines) do
            if l.text == "Leatherworking" then line = lines[i + 1] end
        end
        T.ok(line ~= nil, "Leatherworking listed")
        T.eq(line.text, ("Bank: Light Hide x%d"):format(2 * crafts - 3))
        T.eq(line.textColor, CP.Style.color.warn, "an errand, not green Ready")
        T.ok(line.info and line.info:find("Cursor\\Buy", 1, true) ~= nil, "the coin-bag icon")
        T.ok(line.tip[2]:find("from the bank") ~= nil, line.tip[2])

        bags[783] = 2 * crafts
        lines = CP.GatherList.NextLines()
        for i, l in ipairs(lines) do
            if l.text == "Leatherworking" then line = lines[i + 1] end
        end
        T.eq(line.text, "Ready to craft Toughened Leather Armor", "hides in the bags: ready")
        T.eq(line.info, nil, "no icon")
    end)
    CP.GatherList.nextOpen = false
    CP.Guides[KEY] = nil
    CP.charDB.nextStep, CP.charDB.learned = saved.steps, saved.learned
    T.ok(ok, err)
end)
