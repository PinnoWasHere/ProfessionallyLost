-- Farm's Best farm rows stay one line in any font: each row's text ends left of its price,
-- shortened in a fixed order when the full text does not fit. The detached Gathering window
-- goes from its least to its widest size under several font metrics. Fonts come from the
-- visual world's model (tests/world/visual.lua), so the fit measures as the row draws.

local CP = ProfLost
local W, P, GP, GL, S = CP.Window, CP.Panel, CP.GatherPanel, CP.GatherList, CP.Style
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR, TANARIS, WINTERSPRING = 1411, 1446, 1452
local SCALE, RUGGED = 8154, 8170   -- Scorpid Scale, Rugged Leather

-- A glyph-width multiplier on the visual world's letter, a font face and a text size.
local METRICS = {
    { name = "narrow face", font = "narrow", scale = 1, glyph = 1 },
    { name = "narrow glyphs", font = "general", scale = 1, glyph = 0.7 },
    { name = "normal", font = "general", scale = 1, glyph = 1 },
    { name = "1.5x glyphs", font = "general", scale = 1, glyph = 1.5 },
    { name = "2x glyphs", font = "general", scale = 1, glyph = 2 },
    { name = "largest text size", font = "general", scale = 1.15, glyph = 1 },
    { name = "largest text, wide face", font = "wide", scale = 1.15, glyph = 1 },
}
local WIDTH_STEP = 20
local ELLIPSIS = "…"

local function settle() T.advance(0.5) end

local function scene()
    Visual.begin()
    DaylightWorld.begin({ plugin = true })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 60, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 900 })
    World.set(CP.db, "font", "general")
    World.set(CP.db, "textScale", 1)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherPanelClosed", nil)
    World.set(CP.db, "gatherAttached", false)
    World.set(CP.db, "gatherPoint", { "TOPLEFT", "BOTTOMLEFT", 600, 900 })
    World.set(CP.db, "gatherSize", nil)
    World.set(CP.db, "routeMode", "farm")
    World.set(CP.db, "farmClosed", nil)
    World.set(CP.charDB, "panelProf", nil)
    World.set(CP.charDB, "gatherZone", nil)
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.set(CP.Pricing, "SaleValue", function(item)
        return nil, item == SCALE and 4600 or item == RUGGED and 4000 or 100
    end)
    World.set(CP.Pricing, "AuctionAge", function() return nil end)
    World.set(CP.Farm, "Items", function() return { SCALE, RUGGED } end)
    World.set(CP.Farm, "Find", function(item)
        return { zone = item == SCALE and TANARIS or WINTERSPRING, score = 1 }, true
    end)
    World.onEnd(function()
        CraftWorld.Close()
        S.ApplyScale()
        S.ApplyFont()
        CP.db.gatherAttached = true
        GP.ModeChanged()
        GP.anchor:ClearAllPoints()
        W.Update()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    GP.PlaceAnchor()
    GP.Layout()
    settle()
end

-- The player's font through the options' own rows; a glyph width change reaches the list as
-- the game's font change does (Style.ApplyFont).
local function metric(m)
    World.set(Visual, "LETTER", Visual.LETTER * m.glyph)
    CP.Settings.Set("font", m.font)
    CP.Settings.Set("textScale", m.scale)
    S.ApplyFont()
    settle()
end

-- Cuts `s` to its first `n` characters, then the ellipsis.
local function cut(s, n)
    local out, i = "", 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if i >= n then break end
        out, i = out .. ch, i + 1
    end
    return out:gsub("%s+$", "") .. ELLIPSIS
end

local function chars(s)
    local n = 0
    for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n
end

-- Every form a row's text may take, longest first: the full text, the short lead, the
-- material cut a character at a time and then dropped, then the zone cut.
local function ladder(zone, item, lead)
    local out = {}
    local head = lead and "Best: " or ""
    if lead then out[1] = ("Best farm: %s (%s)"):format(zone, item) end
    out[#out + 1] = ("%s%s (%s)"):format(head, zone, item)
    for n = chars(item) - 1, 1, -1 do out[#out + 1] = ("%s%s (%s)"):format(head, zone, cut(item, n)) end
    out[#out + 1] = head .. zone
    for n = chars(zone) - 1, 1, -1 do out[#out + 1] = head .. cut(zone, n) end
    return out
end

-- The shown rows of the Best farm group: the lead and the rows that light with it.
local function bestRows()
    local _, rows = GL.Drawn()
    local lead, out = nil, {}
    for _, r in ipairs(rows) do
        if r:IsShown() and r.line and r.line.kind == "plan" and tostring(r.line.text):find("^Best") then
            lead = r.line
            out[1] = r
        end
    end
    for _, r in ipairs(rows) do
        if lead and r:IsShown() and r.line and r.line.spotOf == lead then out[#out + 1] = r end
    end
    return out, lead
end

local function zoneOf(i) return C_Map.GetMapInfo(i == 1 and TANARIS or WINTERSPRING).name end
local function itemOf(i) return CP.ItemName(i == 1 and SCALE or RUGGED) end

for _, m in ipairs(METRICS) do
    T.test(("Best farm rows are one line, end left of their price and shorten in order: %s"):format(m.name), function()
        scene()
        metric(m)
        for w = GP.SIZE_MIN[1], GP.MAX_W, WIDTH_STEP do
            GP.Resize(w, 400)
            settle()
            local at = ("%s at %d px"):format(m.name, w)
            local rows, lead = bestRows()
            T.eq(#rows, 2, at .. ": two Best farm rows")
            for _, l in ipairs((GL.Drawn())) do
                T.ok(not (l.kind == "cont" and (l.of == lead or l.of and l.of.spotOf == lead)),
                    at .. ": no wrapped line under a Best farm row: " .. tostring(l.text))
            end
            for i, r in ipairs(rows) do
                local line, name = r.line, r.name
                local text = tostring(name:GetText())
                local tag = ("%s, row %d %q"):format(at, i, text)
                T.ok(not line.wrapped, tag .. ": the price stays on the row")
                T.eq(r.info:GetText(), CP.Pricing.Format(i == 1 and 4600 or 4000) .. " ea (AH)", tag .. ": its price")
                T.eq(name:GetNumLines(), 1, tag .. ": one line")
                T.ok(name:GetRight() <= r.info:GetLeft() + 0.5, tag .. ": the text's bound ends left of the price")
                -- The first form that fits the row's room, in the fixed order.
                local room = name:GetRight() - name:GetLeft()
                local forms, want = ladder(zoneOf(i), itemOf(i), i == 1), nil
                for _, form in ipairs(forms) do
                    if S.Measure(form, "body") <= room then want = form break end
                end
                if want then
                    T.eq(text, want, ("%s: the first form that fits %.0f px"):format(tag, room))
                    T.ok(not name:IsTruncated(), tag .. ": drawn whole")
                    local right = name:GetLeft() + name:GetUnboundedStringWidth()
                    T.ok(right <= r.info:GetLeft() + 0.5,
                        ("%s: text ends at %.1f, the price starts at %.1f"):format(tag, right, r.info:GetLeft()))
                else
                    -- Not even the shortest form fits: it stands, and the font string's bound clips it.
                    T.eq(text, forms[#forms], ("%s: nothing fits %.0f px, the shortest form"):format(tag, room))
                end
                if text ~= forms[1] then
                    T.eq(line.tip and line.tip[1], forms[1], tag .. ": the tooltip shows the full text")
                else
                    T.eq(line.tip, nil, tag .. ": whole, no tooltip")
                end
            end
        end
    end)
end

T.test("a Best farm row fits again after a font change", function()
    scene()
    GP.Resize(GP.MAX_W, 400)
    settle()
    local rows = bestRows()
    local before = rows[1] and rows[1].name:GetText()
    T.eq(before, ("Best farm: %s (%s)"):format(zoneOf(1), itemOf(1)), "whole at the widest")
    CP.Settings.Set("font", "wide")
    CP.Settings.Set("textScale", 1.15)
    settle()
    rows = bestRows()
    local r = rows[1]
    local after = r and r.name:GetText()
    T.ok(before ~= after, ("the text shortens for the wider font: %q, then %q"):format(tostring(before), tostring(after)))
    T.ok(r and r.name:GetLeft() + r.name:GetUnboundedStringWidth() <= r.info:GetLeft() + 0.5, "and ends left of the price")
end)

T.test("hovering a shortened Best farm row shows its full text and lights the whole group", function()
    scene()
    GP.Resize(GP.SIZE_MIN[1], 400)
    settle()
    local rows = bestRows()
    T.eq(#rows, 2, "two rows")
    local lit, said = {}, nil
    local _, all = GL.Drawn()
    for _, r in ipairs(all) do
        World.set(r, "LockHighlight", function(self) lit[self] = true end)
        World.set(r, "UnlockHighlight", function(self) lit[self] = nil end)
    end
    World.set(GameTooltip, "SetText", function(_, text) said = text end)
    rows[1]:GetScript("OnEnter")(rows[1])
    T.ok(rows[1].name:GetText() ~= said, "the row is shortened: " .. tostring(rows[1].name:GetText()))
    T.eq(said, ("Best farm: %s (%s)"):format(zoneOf(1), itemOf(1)), "the tooltip reads the full text")
    T.ok(lit[rows[2]], "the second row lights with the lead")
    rows[1]:GetScript("OnLeave")(rows[1])
    rows[2]:GetScript("OnEnter")(rows[2])
    T.ok(lit[rows[1]], "the lead lights with the second row")
    rows[2]:GetScript("OnLeave")(rows[2])
end)
