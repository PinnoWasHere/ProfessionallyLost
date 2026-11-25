-- Fixes from the second in-game round: same-name recipes, rank row order, fallback
-- crafts, the checklist beside chat and its campfire hush, Daylight UI buttons.

local CP = ProfLost

T.test("a guide recipe known under another spell of the same name counts as learned", function()
    local guide = { recipes = { [818] = { name = "Basic Campfire" }, [2540] = { name = "Roasted Boar Meat" } } }
    local recipes = { { id = 1229737, name = "Basic Campfire", learned = true },
                      { id = 2540, name = "Roasted Boar Meat", learned = true } }
    local learned = CP.Professions.Learned(recipes)
    local alias = CP.Plan.Alias(guide, recipes, learned)
    T.ok(learned[818], "Basic Campfire counts as known")
    T.eq(alias[818], 1229737, "crafted through the player's own spell")
    T.eq(alias[2540], nil, "known by its own id: no alias")
end)

T.test("an auto recipe the player lacks reads as trainer, never pattern", function()
    T.eq(CP.Guide.SourceWord({ src = "auto" }), "trainer")
    T.eq(CP.Guide.SourceWord({ src = "vendor" }), "pattern")
end)

T.test("a rank book row shows the skill where it sits, so the column climbs", function()
    local guide = CP.Guides[185]
    local steps = {
        { from = 72, to = 80 }, { from = 80, to = 137 }, { from = 137, to = 141 }, { from = 141, to = 175 },
    }
    local ranks = CP.Guide.PendingRanks(guide, 75, steps)
    T.eq(#ranks, 2, "Journeyman, then the Expert Cookbook")
    T.eq(ranks[1].rank.kind, "trainer")
    T.eq(ranks[1].before, 1, "Journeyman before the step that crosses 75")
    T.eq(ranks[2].rank.item, 16072)
    T.eq(ranks[2].before, 4, "before the step that crosses 150")
    T.eq(ranks[2].at, 141, "labelled 141, not 125")
end)

T.test("a fallback that greys out inside the step counts finite crafts", function()
    local fa = CP.Guides[129]
    local silk, heavy
    for id, r in pairs(fa.recipes) do
        if r.name == "Silk Bandage" then silk = id end
        if r.name == "Heavy Silk Bandage" then heavy = id end
    end
    T.ok(silk and heavy)
    local live = { guide = fa, learned = { [silk] = true }, recipes = {}, sides = {},
                   plan = { { spell = heavy, from = 180, to = 240, crafts = 60 } } }
    CP.Plan.AddFallbacks(live)
    local side = live.sides[1]
    if side then
        T.ok(side.crafts < math.huge and side.crafts > 0, "crafts " .. tostring(side.crafts))
    end
end)

T.test("the checklist starts beside the chat box", function()
    World.set(_G, "ChatFrame1", rawget(_G, "ChatFrame1"))
    local chat = CreateFrame("Frame", "ChatFrame1", UIParent)
    chat:SetPoint("BOTTOMLEFT", 20, 20)
    chat:SetSize(400, 200)
    chat.GetRight = function() return 420 end
    local p = CP.GatherList.DefaultPoint()
    T.eq(p[1], "TOPLEFT")
    T.eq(p[2], chat)
    T.eq(p[3], "TOPRIGHT")
end)

T.test("sitting by a campfire eases the checklist out without hiding it", function()
    local aura
    World.patch("C_UnitAuras.GetPlayerAuraBySpellID", function(id) return id == 1229739 and aura or nil end)
    aura = { spellId = 1229739 }
    CP.GatherList.UpdateSitting()
    T.fire("UNIT_AURA", "player")
    T.advance(1)
    T.ok(true, "no errors while hushed")
    aura = nil
    CP.GatherList.UpdateSitting()
    T.advance(1)
end)

T.test("with Daylight UI's look, buttons are Daylight UI's own", function()
    local made
    _G.DaylightUI = { API = { major = 1, minor = 1,
        Button = function(parent, text, h)
            made = CreateFrame("Button", nil, parent)
            made:SetHeight(h)
            made.text = made:CreateFontString()
            return made
        end, Skin = function() end, Font = function() return "x" end } }
    local b = CP.Style.Button(UIParent, 80)
    T.eq(b, made, "API.Button made it")
    T.eq(b.label, made.text, "its label is Daylight UI's text")
    _G.DaylightUI = nil
    local plain = CP.Style.Button(UIParent, 80)
    T.ok(plain ~= made and plain.label ~= nil, "without Daylight UI (tests): a plain button")
end)

T.test("the free guide window hangs from a fixed anchor, so folding keeps its top", function()
    local W, panel = ProfLost.Window, ProfLost.Panel.frame
    W.Place()
    local point, rel, relPoint = panel:GetPoint(1)
    T.eq(point, "TOPLEFT")
    T.eq(rel, W.anchor, "anchored to the mover's frame, not moved itself")
    T.eq(relPoint, "TOPLEFT")
    T.eq(W.DefaultPoint()[1], ProfLost.GatherList.DefaultPoint()[1], "it starts where the checklist did")
end)

T.test("text size: a slider in Daylight UI's options, content scales, tabs and title don't", function()
    local CP = ProfLost
    local s = CP.Settings.Find("textScale")
    T.eq(s.kind, "slider")
    T.eq(s.min, CP.Style.SCALE_MIN)
    T.eq(s.max, CP.Style.SCALE_MAX)
    T.ok(s.max <= 1.15, "the top keeps the 310px panel's columns from overflowing")
    local row
    for _, page in ipairs(CP.Plugin.Pages()) do
        for _, g in ipairs(page.groups) do
            for _, item in ipairs(g.items) do if item.key == "textScale" then row = item end end
        end
    end
    T.ok(row and row.type == "slider" and row.min == 0.85 and row.max == 1.15, "slider row")

    -- Font strings that remember their font, from a stand-in API.Text.
    local function fontString()
        local fs = UIParent:CreateFontString()
        fs.font = { "Fonts\\FRIZQT__.TTF", 13, "" }
        fs.GetFont = function(self) return unpack(self.font) end
        fs.SetFont = function(self, p, px, fl) self.font = { p, px, fl } end
        return fs
    end
    _G.DaylightUI = { API = { major = 1, minor = 1, Text = function() return fontString() end,
                             Skin = function() end, Font = function() return "x" end } }
    local content = CP.Style.Text(UIParent, "body")
    local tab = CP.Style.Text(UIParent, "body", nil, true)
    CP.db.textScale = 1.15
    CP.Style.ApplyScale()
    T.ok(math.abs(select(2, content:GetFont()) - 13 * 1.15) < 0.01, "content at 1.15x")
    T.eq(select(2, tab:GetFont()), 13, "tab label stays")
    CP.db.textScale = 9
    CP.Style.ApplyScale()
    T.ok(math.abs(select(2, content:GetFont()) - 13 * 1.15) < 0.01, "clamped to the top of the range")
    CP.db.textScale = 1
    CP.Style.ApplyScale()
    _G.DaylightUI = nil
end)
