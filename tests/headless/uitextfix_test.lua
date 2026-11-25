-- Five text and visibility fixes from the 1.3.0 screenshots: the All card's skill-up line, the
-- Gather card's in-zone note, the side setting's short words, the source line's skill number
-- kept with its line, and Plan for Enchanting always on the page, greyed without its professions.

local CP = ProfLost
local GT, S, GG = CP.GuideTab, CP.Style, CP.GatherGuide
local ENCHANTING, TAILOR = 333, 197
local SKIN, BADLANDS, ELWYNN, DUROTAR = 393, 1418, 1429, 1411

local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

T.test("the All card's skill-up line uses the Available Skill Ups wording and stays short", function()
    local line = CP.Impromptu.Info({ name = "Heavy Silk Bandage", crafts = 23, points = 7.2, buy = { { count = 4, name = "Coarse Thread" } } }, true)
    T.eq(line, "Heavy Silk Bandage x23 · ~7.2 pts")
    T.ok(not line:find("Impromptu", 1, true), "no Impromptu: " .. line)
    T.ok(#line <= 48, "short enough for the card: " .. line)
    T.eq(CP.Impromptu.Info({ name = "Linen Bandage", crafts = 5, points = 3 }, true), "Linen Bandage x5 · ~3 pts")
end)

-- A level 60 Skinning 295 in the Badlands whose next stretch is the Badlands.
local function skinCard(zone)
    MapWorld.begin({ zone = zone, level = 60, side = "Alliance", shareSolves = true })
    World.set(CP.Gather, "Skills", function() return { [SKIN] = 295 } end)
    World.set(CP.Gather, "MaxRank", function() return 300 end)
    World.set(GG, "Ready", function() return true end)
    World.set(GG, "PlayerRows", function() return {} end)
    World.set(GG, "Next", function() return { zone = BADLANDS } end)
    return GT.Card({ prof = { id = SKIN, ids = { SKIN }, skill = 295, max = 300, name = "Skinning" } })
end

T.test("a Gather card says in words when you are in its zone, and nothing elsewhere", function()
    local here = skinCard(BADLANDS)
    T.ok(tostring(here.step):find("Gather in", 1, true) ~= nil, "step: " .. tostring(here.step))
    T.eq(here.need, "You're in this zone")
    T.eq(skinCard(ELWYNN).need, "", "elsewhere")
end)

T.test("the side setting is labelled and valued in words that fit", function()
    local s = CP.Settings.Find("gatherSide")
    T.eq(s.label, "Side when attached")
    T.eq(s.values, { left = "Left", right = "Right" })
    T.ok(#s.label <= 24, "label fits")
end)

-- The source line of an unlearned step, with a far trainer.
local function sourceLine()
    local W = CP.Window
    MapWorld.begin({ zone = DUROTAR, x = 0.52, y = 0.43, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 45, max = 75 } } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function()
        W.opened = false
        W.Update()
    end)
    W.Update()
    T.advance(0.1)
    CraftWorld.Open(TAILOR)
    CraftWorld.Close()
    W.Pick(TAILOR)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    local row
    for _, r in ipairs(GT.ui.rows) do
        if r.recipe and r.spell and not (r.rank or r.train or r.side) then row = r break end
    end
    if not row then return nil end
    local recipe = {}
    for k, v in pairs(row.recipe) do recipe[k] = v end
    recipe.src, recipe.learn = "trainer", 155
    World.set(CP.Guide, "WaypointFor", function() return { name = "Una" } end)
    World.set(CP.Guide, "FromText", function() return " from Una, Thunder Bluff (41.5, 42.6)  ·  9m 22s", {} end)
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    copy.learned, copy.recipe = false, recipe
    GT.FillDetails(copy)
    return GT.ui.details.status:GetText() or ""
end

T.test("the source line puts the skill number ahead of the place, in text ink", function()
    local status = sourceLine()
    T.ok(status ~= nil, "a craft row")
    if not status then return end
    T.eq(plain(status), "Train  ·  skill 155  ·  from Una, Thunder Bluff (41.5, 42.6)  ·  9m 22s")
    T.ok(status:find(S.Hex(S.color.text) .. "skill 155|r", 1, true) ~= nil, "skill in text ink: " .. status)
end)

-- A character with these skill lines and nothing else.
local function character(lines)
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    local professions = {}
    for _, l in ipairs(lines) do professions[l] = { rank = 1, max = 75 } end
    CraftWorld.begin({ professions = professions })
end

local function deRow()
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, it in ipairs(g.items) do
            if it.key == "deEnchant" then return it end
        end
    end
end

T.test("Plan for Enchanting always shows, and greys out unless Enchanting and a disenchanting profession are both there", function()
    local cases = {
        { { TAILOR }, true, "Tailoring alone" },
        { { ENCHANTING }, true, "Enchanting alone" },
        { { TAILOR, ENCHANTING }, false, "both" },
    }
    for _, c in ipairs(cases) do
        character(c[1])
        local row = deRow()
        T.ok(row ~= nil, c[3] .. ": the row is on the page")
        if row then
            T.eq(row.hidden, nil, c[3] .. ": never hidden")
            T.eq(row.disabled(function(k) return CP.db[k] end), c[2], c[3] .. ": greyed out")
            T.ok(row.desc:find("Greyed out until", 1, true) ~= nil, "the description says why")
        end
    end
end)

T.test("a greyed-out Plan for Enchanting is no switch on a guide's card", function()
    character({ TAILOR })
    T.eq(#CP.Settings.Switches(TAILOR), 0, "no switch without Enchanting")
    character({ TAILOR, ENCHANTING })
    T.eq(#CP.Settings.Switches(TAILOR), 1, "a switch with both")
end)
