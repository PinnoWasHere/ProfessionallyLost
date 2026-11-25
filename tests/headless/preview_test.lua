-- /proflost preview (UI/Preview.lua, decision 0004): another
-- profession's windows for a developer, which never touch the saved variables. The forms,
-- the preview character, the marker, the refused actions, the Disenchant tab's samples, a
-- gathering preview's panel, and a whole session that leaves every saved table as it was.

local CP = ProfLost
local W, P, PV, Prof = CP.Window, CP.Panel, CP.Preview, CP.Professions
local LW, SKIN, ENCH, HERB = 165, 393, 333, 182
local DUROTAR = 1411
local FINE_THREAD = 2321

local function click(b) b:GetScript("OnClick")(b) end

-- `t` as text, keys sorted, so two tables compare by content.
local function dump(t, seen)
    if type(t) ~= "table" then return type(t) .. ":" .. tostring(t) end
    seen = seen or {}
    if seen[t] then return "<cycle>" end
    seen[t] = true
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = dump(k, seen) .. "=" .. dump(t[k], seen) end
    seen[t] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

-- The saved variables as the game would write them, and the tables ProfLost uses for them.
local function saved()
    return { db = dump(CP.db), char = dump(CP.charDB), ProfLostDB = dump(rawget(_G, "ProfLostDB")),
             ProfLostCharDB = dump(rawget(_G, "ProfLostCharDB")), dbRef = CP.db, charRef = CP.charDB }
end

-- The first line where `a` and `b` differ, with some context.
local function firstDiff(a, b)
    for i = 1, math.max(#a, #b) do
        if a:sub(i, i) ~= b:sub(i, i) then
            return ("at %d: before ...%s... after ...%s..."):format(i, a:sub(math.max(1, i - 120), i + 80),
                b:sub(math.max(1, i - 120), i + 80))
        end
    end
    return "same"
end

local function sameSaved(before, after)
    for _, k in ipairs({ "db", "char", "ProfLostDB", "ProfLostCharDB" }) do
        T.ok(before[k] == after[k], k .. " unchanged: " .. firstDiff(before[k], after[k]))
    end
    T.ok(after.dbRef == before.dbRef, "CP.db is the real table again")
    T.ok(after.charRef == before.charRef, "CP.charDB is the real table again")
end

-- Chat lines printed since `from`.
local function printed(from)
    local out = {}
    for i = from + 1, #T.prints() do out[#out + 1] = tostring(T.prints()[i]) end
    return table.concat(out, "\n")
end

-- Facts for the Disenchant samples an Enchanting preview at `skill` tries: greens of item
-- level 21 (Disenchant skill 25), as CraftWorld's bags API answers C_Item.GetItemInfo.
local function sampleFacts(skill)
    local items = {}
    for _, id in ipairs(PV.Candidates(skill)) do items[id] = { 2, 21, 4, 2, 150, 1, 0 } end
    return items
end

-- The owner: Leatherworking 100 and Skinning 100 in Durotar, the guide window closed, the
-- Leatherworking window opened once so its recipes and plan are saved.
local function owner(spec)
    spec = spec or {}
    if spec.daylight then
        Visual.begin()
        DaylightWorld.begin({ plugin = true })
        Visual.Skin()
    end
    MapWorld.begin({ zone = spec.zone or DUROTAR, level = 20, side = "Horde", shareSolves = true })
    CraftWorld.begin({ professions = { [LW] = 100, [SKIN] = 100 }, bags = { [FINE_THREAD] = 5 },
                       items = sampleFacts(spec.skill or 150) })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", spec.closed ~= false or nil)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 900 })
    World.set(W.managed, "mover", false)
    World.set(CP.GatherPanel.managed, "mover", false)
    World.onEnd(function()
        PV.Stop(true)
        W.CancelPick()
        W.opened = false
        W.Update()
    end)
    CraftWorld.Open(LW)
    CraftWorld.Close()
    W.Update()
    T.advance(3)
end

-- The forms ------------------------------------------------------------------------------

T.test("names: whole, cut short, any case, spaces dropped; an unknown or shared start names nothing", function()
    T.eq(PV.Find("Enchanting"), ENCH)
    T.eq(PV.Find("ench"), ENCH)
    T.eq(PV.Find("HERB"), HERB)
    T.eq(PV.Find("first aid"), 129)
    T.eq(PV.Find("firstaid"), 129)
    T.eq(PV.Find("leatherworking"), LW)
    local line, hits = PV.Find("zzz")
    T.eq(line, nil)
    T.eq(#hits, 0)
    -- Every crafting guide and gathering skill is reachable by its name.
    for id, name in pairs(PV.Names()) do T.eq(PV.Find(name), id, name) end
end)

T.test("caps follow the trained ranks; known recipes are the trainer and starting ones up to the skill", function()
    T.eq(PV.Cap(1), 75)
    T.eq(PV.Cap(74), 75)
    T.eq(PV.Cap(75), 150)
    T.eq(PV.Cap(150), 225)
    T.eq(PV.Cap(299), 300)
    T.eq(PV.Cap(300), 300)
    local set, list = PV.Known(ENCH, 150)
    T.ok(#list > 0, "Enchanting 150 knows recipes")
    for id in pairs(set) do
        local r = CP.Guides[ENCH].recipes[id]
        T.ok((r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= 150, r.name)
    end
    for id, r in pairs(CP.Guides[ENCH].recipes) do
        if (r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= 150 then T.ok(set[id], "knows " .. r.name) end
    end
    local _, none = PV.Known(HERB, 100)
    T.eq(#none, 0, "a gathering profession knows no recipes")
end)

T.test("/proflost preview alone, an unknown name and preview off with none on change nothing", function()
    owner()
    local before = saved()
    local from = #T.prints()
    SlashCmdList.PROFLOST("preview")
    SlashCmdList.PROFLOST("preview nosuchthing 50")
    SlashCmdList.PROFLOST("preview off")
    local said = printed(from)
    T.ok(said:find("/proflost preview <profession> [skill]", 1, true) ~= nil, said)
    T.ok(said:find("Now: off.", 1, true) ~= nil, said)
    T.ok(said:find("nosuchthing names no profession", 1, true) ~= nil, said)
    T.ok(said:find("no preview is on", 1, true) ~= nil, said)
    T.eq(Prof.preview, nil)
    T.eq(CP.Preview.Command("  "), false, "blank words are the forms again")
    T.eq(CP.Preview.Refuse("craft"), false, "no preview: nothing refused, nothing said")
    T.ok(printed(from):find("Crafting isn't possible", 1, true) == nil)
    sameSaved(before, saved())
end)

-- The preview character ------------------------------------------------------------------

T.test("an Enchanting preview: the character has Enchanting 150 alone, its trainer recipes, and the window shows", function()
    owner()
    T.ok(not P.frame:IsShown(), "the owner's guide window starts closed")
    SlashCmdList.PROFLOST("preview enchanting 150")
    T.advance(3)
    local pv = Prof.preview
    T.ok(pv ~= nil, "on")
    T.eq({ pv.line, pv.skill, pv.max }, { ENCH, 150, 225 })
    T.eq(CP.Sourcing.PlayerSkills(), { [ENCH] = true })
    T.eq(CP.Gather.Skills(), {}, "no gathering skill")
    local profs = W.Professions()
    T.eq(#profs, 1)
    T.eq(profs[1].id, ENCH)
    T.eq(W.ChosenID(), ENCH)
    T.ok(P.frame:IsShown(), "the guide window shows")
    local live = W.Live()
    T.ok(live and live.guide == CP.Guides[ENCH], "the guide is Enchanting's")
    T.ok(live.plan and #live.plan > 0, "with a plan")
    T.ok(not live.unread, "its recipes count as read")
    local _, list = PV.Known(ENCH, 150)
    for _, id in ipairs(list) do T.ok(live.learned[id], "knows " .. id) end
    T.ok(P.tabs.disenchant.button:IsShown(), "the Disenchant tab offers itself")

    -- Start and Stop by name: the chat lines say what happened.
    local from = #T.prints()
    T.eq(CP.Preview.Start(ENCH, 999), true)
    T.eq(Prof.preview.skill, PV.SKILL_MAX, "a skill past 300 is held to it")
    T.eq(CP.Preview.Start(99999, 10), false, "an unknown profession starts nothing")
    T.eq(CP.Preview.Stop(), true)
    local said = printed(from)
    T.ok(said:find("previewing Enchanting 300 (cap 300). Nothing is saved", 1, true) ~= nil, said)
    T.ok(said:find("preview of Enchanting 300 ended; your own professions are back.", 1, true) ~= nil, said)
end)

T.test("the marker: the guide window's second header line, in the warning ink; the version is back after", function()
    owner()
    SlashCmdList.PROFLOST("preview enchanting 150")
    T.advance(1)
    local text = P.version:GetText() or ""
    T.ok(text:find("Preview: Enchanting 150", 1, true) ~= nil, text)
    T.ok(text:find(CP.Style.Hex(CP.Style.color.warn), 1, true) == 1, "in the warning ink: " .. text)
    T.ok(PV.Marker() == "Preview: Enchanting 150")
    for _, t in ipairs(CP.GatherList.NoteTexts()) do
        T.ok(t:find("Preview: Enchanting 150", 1, true) ~= nil, "the gathering note leads with it: " .. t)
    end
    SlashCmdList.PROFLOST("preview off")
    T.advance(1)
    T.eq(PV.Marker(), nil)
    P:Refresh()
    T.eq(P.version:GetText(), P.VersionText() or "")
end)

-- The gathering panel's lines and the route's items once every solve has ended.
local function gatherView()
    local GL, RM = CP.GatherList, CP.RouteMap
    CP.VendorWatch.Check()
    GL.Refresh()
    local frames = 0
    repeat
        T.advance(0.05, 0.05)
        frames = frames + 1
    until not (CP.GatherGuide.Warming() or RM.Solving() or RM.Passing()) or frames > 8000
    GL.Refresh()
    local out = {}
    for _, l in ipairs((GL.Drawn())) do
        out[#out + 1] = table.concat({ tostring(l.kind), tostring(l.text), tostring(l.info) }, "|")
    end
    for _, r in ipairs(GL.RouteRows(DUROTAR, nil, true)) do out[#out + 1] = "route|" .. r.itemID end
    return out
end

T.test("a gathering preview: Herbalism 30 shows the gathering panel and route a real herbalist sees here", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde", shareSolves = true })
    CraftWorld.begin({ professions = { [HERB] = 30 } })
    MapWorld.SettleGuides({ HERB })
    T.advance(3)
    local herbalist = gatherView()

    owner()
    SlashCmdList.PROFLOST("preview herb 30")
    MapWorld.SettleGuides({ HERB })
    T.advance(3)
    T.eq(CP.Gather.Skills(), { [HERB] = 30 })
    T.eq(CP.Gather.MaxRank(HERB), 75)
    T.eq(CP.Sourcing.PlayerSkills(), { [HERB] = true })
    T.eq(W.ChosenID(), HERB)
    local preview = gatherView()
    T.ok(#herbalist > 0, "the herbalist sees something here")
    T.eq(table.concat(preview, "\n"), table.concat(herbalist, "\n"), "the preview sees what the herbalist sees")
    local text = "\n" .. table.concat(preview, "\n") .. "\n"
    for _, herb in ipairs({ 765, 2447, 2449 }) do
        T.ok(text:find("\nroute|" .. herb .. "\n", 1, true) ~= nil, "the route gathers " .. herb .. ":" .. text)
    end
    T.ok(text:find("Skinning", 1, true) == nil, "the owner's Skinning doesn't show: " .. text)
    T.ok((CP.GatherList.head.status:GetText() or ""):find("Preview: Herbalism 30", 1, true) ~= nil,
        tostring(CP.GatherList.head.status:GetText()))
end)

-- Refused actions ------------------------------------------------------------------------

T.test("Open, Craft, Enchant again and Learn pattern refuse with one line and call no game action", function()
    owner()
    SlashCmdList.PROFLOST("preview enchanting 150")
    T.advance(1)
    click(P.tabs.guide.button)
    local ui = CP.GuideTab.ui
    -- Enchant Bracer - Lesser Stamina, known, stands as an "or" row under the limited pattern.
    local row
    for _, r in ipairs(ui.rows) do
        if r.spell and r.learned and not (r.rank or r.train) then row = r break end
    end
    T.ok(row ~= nil, "a known recipe's row")
    CP.GuideTab.Pick(row)
    local from = #T.prints()
    CraftWorld.Press(ui.details.craftAll)
    T.ok(printed(from):find("isn't possible in a preview of Enchanting 150", 1, true) ~= nil, printed(from))

    -- The other ways in, each straight at its function.
    from = #T.prints()
    T.eq(W.OpenTo(ENCH, row.spell), false)
    CP.Crafting.Start(row.spell, 3)
    CP.EnchantAgain.Press({ recipe = CP.Guides[ENCH].recipes[row.spell], spell = row.spell })
    local d = ui.details
    local was = d.craftAll.usePattern
    d.craftAll.usePattern = { spell = row.spell, item = 1 }
    click(d.craftAll)
    d.craftAll.usePattern = was
    local said = printed(from)
    for _, what in ipairs({ "Opening a profession window", "Crafting", "Enchanting", "Learning a pattern" }) do
        T.ok(said:find(what .. " isn't possible", 1, true) ~= nil, what .. ": " .. said)
    end
    T.eq(#CraftWorld.Opens(), 0, "no OpenTradeSkill")
    T.eq(#CraftWorld.state.casts, 0, "no CraftRecipe")
    T.eq(#T.calls("C_TradeSkillUI.CraftEnchant"), 0, "no CraftEnchant")
    T.eq(CP.Crafting.Busy(), false, "no batch")
end)

T.test("the Disenchant tab: sample greens after the bags; its button aims at nothing and says why", function()
    owner()
    SlashCmdList.PROFLOST("preview enchanting 150")
    T.advance(1)
    click(P.tabs.disenchant.button)
    T.advance(1)
    local queue, head, b, summary = CP.DisenchantTab.State()
    T.ok(#queue > 0 and #queue <= PV.DE_SAMPLES, ("%d samples: %s"):format(#queue, tostring(summary)))
    for _, it in ipairs(queue) do
        T.ok(it.sample and it.bag == PV.SAMPLE_BAG, "a sample in no bag")
        T.ok(it.need <= 150, "within Enchanting 150")
    end
    T.ok(head ~= nil, "a head")
    T.eq(b:GetAttribute("type"), nil, "no spell")
    T.eq(b:GetAttribute("target-bag"), nil, "no target")
    local from = #T.prints()
    b:GetScript("PostClick")(b, "LeftButton")
    T.ok(printed(from):find("Disenchanting isn't possible in a preview of Enchanting 150", 1, true) ~= nil, printed(from))

    -- Off again: no samples, and the tab is gone with Enchanting.
    SlashCmdList.PROFLOST("preview off")
    T.advance(1)
    T.eq(#PV.DisenchantSamples(), 0)
    T.ok(not P.tabs.disenchant.button:IsShown(), "no Disenchant tab without Enchanting")
    from = #T.prints()
    b:GetScript("PostClick")(b, "LeftButton")
    T.eq(printed(from), "", "the real button's click says nothing")
end)

T.test("a vendor's Buy refuses during a preview and buys nothing", function()
    owner()
    SlashCmdList.PROFLOST("preview tailoring 60")
    T.advance(1)
    World.patch("GetMoney", function() return 1000000 end)
    local slots = { { 2320, 10 }, { FINE_THREAD, 100 } }
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i][1] or nil end)
    World.patch("GetMerchantItemLink", function(i)
        return slots[i] and ("|cffffffff|Hitem:%d::::::::20:::::|h[x]|h|r"):format(slots[i][1])
    end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        local s = slots[i]
        return s and { price = s[2], stackCount = 1, numAvailable = -1, isPurchasable = true }
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    local bought = {}
    World.patch("BuyMerchantItem", function(i, n) bought[#bought + 1] = { i, n } end)
    World.set(_G, "MerchantFrame", CreateFrame("Frame", nil, UIParent))
    World.onEnd(function()
        if CP.Buying.open then T.fire("MERCHANT_CLOSED") end
    end)
    T.fire("MERCHANT_SHOW")
    T.advance(CP.Buying.CHECK_EVERY * 2)
    local b = CP.Buying.Button()
    local from = #T.prints()
    if b and b:IsShown() then click(b) end
    CP.Buying.Buy({ { index = 1, quantity = 5 } })
    T.ok(printed(from):find("Buying isn't possible in a preview of Tailoring 60", 1, true) ~= nil, printed(from))
    T.eq(#bought, 0, "BuyMerchantItem never called")
end)

-- Isolation ------------------------------------------------------------------------------

T.test("a whole preview session leaves the saved variables exactly as they were", function()
    owner()
    local before = saved()
    local beforeShown = P.frame:IsShown()

    -- Enchanting: every tab, a pick, a fold, a setting, the window closed and opened, the refusals.
    SlashCmdList.PROFLOST("preview enchanting 150")
    T.advance(2)
    for _, key in ipairs({ "guide", "shop", "disenchant", "guide" }) do
        if P.tabs[key].button:IsShown() then click(P.tabs[key].button) end
        T.advance(0.5)
    end
    local ui = CP.GuideTab.ui
    for _, r in ipairs(ui.rows) do
        if r.spell and not (r.rank or r.train) then CP.GuideTab.Pick(r) break end
    end
    CraftWorld.Press(ui.details.craftAll)
    CP.Settings.Set("neededMarks", false)
    CP.Settings.Set("collect", not CP.db.collect)
    W.Pick(ENCH)
    SlashCmdList.PROFLOST("")
    SlashCmdList.PROFLOST("")
    local queue = CP.DisenchantTab.State()
    if queue and queue[1] then CP.DisenchantTab.ToggleIgnore(queue[1].itemID) end
    T.advance(2)

    -- Switch to Herbalism and to a skill-less name, then the last again with `on`.
    SlashCmdList.PROFLOST("preview herbalism 120")
    MapWorld.SettleGuides({ HERB })
    T.advance(2)
    CP.GatherPanel.ToggleShown()
    T.advance(0.5)
    CP.GatherPanel.ToggleShown()
    SlashCmdList.PROFLOST("preview cooking")
    T.advance(2)
    T.eq(Prof.preview.skill, PV.DEFAULT_SKILL)
    SlashCmdList.PROFLOST("preview off")
    SlashCmdList.PROFLOST("preview on")
    T.eq(Prof.preview.line, 185, "on resumes the last preview")
    T.advance(2)

    -- Item names arrive, skills move, bags change: the addon writes as it plays.
    T.fire("SKILL_LINES_CHANGED")
    T.fire("BAG_UPDATE_DELAYED")
    T.advance(3)

    SlashCmdList.PROFLOST("preview off")
    T.advance(5)
    sameSaved(before, saved())
    T.eq(P.frame:IsShown(), beforeShown, "the guide window is as the owner left it")
    T.eq(Prof.preview, nil)
    T.eq(CP.Sourcing.PlayerSkills(), { [LW] = true, [SKIN] = true }, "the owner's professions are back")
end)

T.test("a reload during a preview starts without it and with the real saved tables", function()
    owner()
    local char = CP.charDB
    SlashCmdList.PROFLOST("preview enchanting 150")
    T.advance(1)
    T.ok(CP.db ~= ProfLostDB, "the preview works on a copy")
    T.eq(ProfLostDB.shareOff, nil, "the copy's sharing switch stays in the copy")

    -- The reload reads the saved variables again; the scene keeps its character.
    CP.LoadSaved()
    CP.charDB = char
    T.eq(Prof.preview, nil, "off after the reload")
    T.eq(CP.db, ProfLostDB)
    T.eq(PV.Marker(), nil)
    T.eq(PV.Stop(true), false, "nothing left to stop")
    SlashCmdList.PROFLOST("preview on")
    T.eq(Prof.preview.line, PV.DEFAULT_LINE, "on after a reload starts the default")
    T.eq(Prof.preview.skill, PV.DEFAULT_SKILL)
end)

T.test("no preview starts in combat, where the Disenchant button would keep its aim", function()
    owner()
    local before = saved()
    World.patch("InCombatLockdown", function() return true end)
    local from = #T.prints()
    T.eq(CP.Preview.Start(ENCH, 150), false)
    SlashCmdList.PROFLOST("preview on")
    T.eq(Prof.preview, nil)
    T.ok(printed(from):find("preview: not in combat.", 1, true) ~= nil, printed(from))
    sameSaved(before, saved())
end)

-- Orgrimmar: six Enchanting patterns are sold here at skill 1.
local ORGRIMMAR = 1454

T.test("the zone's pattern count and its flagged patterns come back as they were after a preview", function()
    owner({ zone = ORGRIMMAR })
    local VW, GL = CP.VendorWatch, CP.GatherList
    local zone = CP.Waypoint.PlayerZone()

    -- The owner's own count: patterns flagged in this zone, a count waiting on the panel.
    VW.Check()
    local mine = VW.current and #VW.current.found or 0
    World.set(GL, "unseen", 5)
    World.set(VW, "counted", zone)
    local before = { GL.unseen, VW.counted, mine }

    SlashCmdList.PROFLOST("preview enchanting 1")
    T.advance(1)
    local during = { GL.unseen, VW.counted, VW.current and #VW.current.found or 0 }
    T.ok(during[1] ~= before[1] or during[3] ~= before[3],
        ("the preview counts its own patterns here (before %s, during %s)"):format(table.concat(before, "/"), table.concat(during, "/")))
    SlashCmdList.PROFLOST("preview off")
    T.advance(1)
    T.eq({ GL.unseen, VW.counted, VW.current and #VW.current.found or 0 }, before, "unseen, counted zone, the zone's patterns")
end)

T.test("Next up opened during a preview is folded again after it, as the owner left it", function()
    owner()
    local GL = CP.GatherList
    World.set(GL, "nextOpen", false)
    SlashCmdList.PROFLOST("preview tailoring 60")
    T.advance(1)
    GL.nextOpen = true
    SlashCmdList.PROFLOST("preview off")
    T.advance(1)
    T.eq(GL.nextOpen, false)
end)

-- Look -------------------------------------------------------------------------------------

T.test("Look.Check passes on an Enchanting and a Herbalism preview with Daylight UI", function()
    owner({ daylight = true, closed = false })
    SlashCmdList.PROFLOST("preview enchanting 150")
    T.advance(2)
    for _, key in ipairs({ "guide", "disenchant" }) do
        click(P.tabs[key].button)
        T.advance(0.5)
        Visual.Check("preview enchanting " .. key)
    end
    SlashCmdList.PROFLOST("preview herbalism 120")
    MapWorld.SettleGuides({ HERB })
    T.advance(10)
    Visual.Check("preview herbalism")
    SlashCmdList.PROFLOST("preview off")
    T.advance(10)
    Visual.Check("preview off")
end)
