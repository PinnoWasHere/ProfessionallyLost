-- Cloth on the gathering panel (decision 0006): one row per cloth the
-- guides need that the zone gives at the player's level, its tooltip naming the best spots, the
-- level and side filter, the one-or-all pick and Farm.

local CP = ProfLost
local G, GL = CP.Gather, CP.GatherList
local FIRST_AID, TAILORING, HERB = 129, 197, 182
local DUROTAR, STV = 1411, 1434
local LINEN, WOOL, SILK, MAGEWEAVE = 2589, 2592, 4306, 4338

-- The player in `spec.zone` at `spec.level` on `spec.side`, the guides' needs `spec.needs`
-- ({ [guide] = { [item] = n } }), `spec.have` in the bags, gathering ranks `spec.skills`.
local function scene(spec)
    MapWorld.begin({ zone = spec.zone, level = spec.level, side = spec.side or "Horde" })
    for _, key in ipairs({ "routeMode", "routeSkip", "skinSkip", "gatherClosed", "farmClosed" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.charDB, "panelProf", nil)
    World.set(CP.charDB, "gatherNeeds", spec.needs or {})
    World.set(CP.charDB, "gatherSoon", nil)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = (spec.skills or {})[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.set(CP.Window, "Professions", function()
        return { { id = FIRST_AID, name = "First Aid" }, { id = TAILORING, name = "Tailoring" } }
    end)
    World.patch("C_Item.GetItemCount", function(id) return (spec.have or {})[id] or 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    G.ResetClusters()
end

-- The Cloth section's lines as drawn: the header (or nil) and the rows by item.
local function drawn()
    GL.Refresh()
    local head, rows = nil, {}
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "section" and l.key == GL.CLOTH_KEY then head = l end
        if l.kind == "item" and l.cloth then rows[l.row.itemID] = l end
    end
    return head, rows
end

T.test("Stranglethorn at level 41 shows one Mageweave row with have / need and who drops it", function()
    scene({ zone = STV, level = 41, needs = { [FIRST_AID] = { [MAGEWEAVE] = 60, [LINEN] = 20 } }, have = { [MAGEWEAVE] = 12 } })
    local head, rows = drawn()
    T.ok(head, "a Cloth section")
    T.eq(head.text, "Cloth")
    local row = rows[MAGEWEAVE]
    T.ok(row, "a Mageweave row")
    T.eq(rows[LINEN], nil, "no Linen: nothing in Stranglethorn drops it")
    local c = row.cloth
    T.ok(c.lo <= c.hi and c.hi <= 50, "the droppers' levels: " .. c.lo .. "-" .. c.hi)
    T.eq(row.info, ("12 / 60 · humanoids %d-%d"):format(c.lo, c.hi))
    T.ok(#c.spots >= 1 and #c.spots <= G.CLOTH_SPOTS, "one to three spots: " .. #c.spots)
    T.ok(row.pin ~= nil, "the row's pin leads to the best spot")
    T.ok(row.tip[1]:find("^Humanoids %d+%-%d+ drop it here: about 1 in %d+ kills$"), row.tip[1])
    T.eq(row.tip[2], "Best spots:")
    T.eq(#row.tip, 2 + #c.spots, "one line per spot, no mob list")
    T.ok(row.tip[3]:find("^#1 .+, level %d+"), row.tip[3])
    T.eq(CP.GatherList.ClothTip(c), row.tip, "the row's tip is ClothTip's")
end)

T.test("a band more than three levels above the player does not count", function()
    scene({ zone = STV, level = 30, needs = { [FIRST_AID] = { [MAGEWEAVE] = 60 } } })
    local head, rows = drawn()
    T.eq(rows[MAGEWEAVE], nil, "no Mageweave at level 30")
    T.eq(head, nil, "no Cloth section")
    for _, b in ipairs(CP.GatherData.zones[STV].cloth[MAGEWEAVE]) do
        T.ok(not G.ClothSafe(b[1], 30), "every Mageweave band needs more than level 33")
    end
    local c = G.Cloth(STV, MAGEWEAVE, 45, "Horde")
    T.ok(c, "at 45 it counts")
    for _, s in ipairs(c.spots) do T.ok(s.lo <= 48, "each spot's creatures start at most 3 above") end
end)

-- Owner, 2026-11-27: "Enemy faction camps: yes" (scripts/guidegen/farmable.py), so Durotar's Kul Tiras
-- camp bands for the Horde alone.
T.test("an enemy camp's cloth band is the side's it is hostile to", function()
    scene({ zone = DUROTAR, level = 5 })
    local bands = CP.GatherData.zones[DUROTAR].cloth[LINEN]
    for _, b in ipairs(bands) do
        T.ok(b[9] == nil or b[9] == "H", "a Durotar band the Alliance alone may kill: " .. tostring(b[9]))
        T.eq(#b[7], #G.Decode(b[6]), "one lead creature and level span per spot")
        for _, lead in ipairs(b[7]) do
            if tostring(lead[1]):find("Kul Tiras", 1, true) then T.eq(b[9], "H", tostring(lead[1])) end
        end
    end
    for _, level in ipairs({ 5, 12 }) do
        local h, a = G.Cloth(DUROTAR, LINEN, level, "Horde"), G.Cloth(DUROTAR, LINEN, level, "Alliance")
        T.ok(h ~= nil, "the Horde has Durotar's Linen at level " .. level)
        T.ok((h and h.kills or 0) > (a and a.kills or 0), "the camp's spawns count for the Horde alone at " .. level)
    end
end)

T.test("a cloth the bags cover drops off; no cloth need, no section", function()
    scene({ zone = STV, level = 45, needs = { [FIRST_AID] = { [MAGEWEAVE] = 60 } }, have = { [MAGEWEAVE] = 60 } })
    local head = drawn()
    T.eq(head, nil, "covered")
    scene({ zone = STV, level = 45, needs = {} })
    T.eq((drawn()), nil, "nothing needed")
end)

T.test("one picked profession shows only its own guide's cloth; a gathering pick shows none", function()
    scene({ zone = STV, level = 45, skills = { [HERB] = 200 },
            needs = { [FIRST_AID] = { [MAGEWEAVE] = 60 }, [TAILORING] = { [SILK] = 40, [MAGEWEAVE] = 30 } } })
    local _, rows = drawn()
    T.ok(rows[SILK] and rows[MAGEWEAVE], "All: Silk and Mageweave")
    T.ok(rows[MAGEWEAVE].info:find("^0 / 90"), "All sums the guides: " .. rows[MAGEWEAVE].info)
    GL.SetPanelProf(FIRST_AID)
    _, rows = drawn()
    T.ok(rows[MAGEWEAVE] and not rows[SILK], "First Aid: Mageweave only")
    T.ok(rows[MAGEWEAVE].info:find("^0 / 60"), "its own need: " .. rows[MAGEWEAVE].info)
    GL.SetPanelProf(HERB)
    local head = drawn()
    T.eq(head, nil, "Herbalism: no cloth")
    GL.SetPanelProf(nil)
end)

T.test("Farm lists every cloth the zone gives, with no need", function()
    scene({ zone = STV, level = 45, needs = {}, skills = { [HERB] = 200 } })
    World.set(CP.db, "routeMode", "farm")
    local head, rows = drawn()
    T.ok(head, "a Cloth section in Farm")
    T.ok(rows[SILK] and rows[MAGEWEAVE], "Silk and Mageweave sell")
    T.ok(rows[MAGEWEAVE].info:find("^humanoids %d+%-%d+$"), "no have / need: " .. rows[MAGEWEAVE].info)
    T.eq(rows[MAGEWEAVE].row.need, nil)
    GL.SetPanelProf(HERB)
    T.eq((drawn()), nil, "a gathering pick shows none")
    GL.SetPanelProf(nil)
end)

T.test("a click opens the row's spots, each with a pin; folded it is one row", function()
    scene({ zone = STV, level = 45, needs = { [FIRST_AID] = { [MAGEWEAVE] = 60 } } })
    local _, rows = drawn()
    local row = rows[MAGEWEAVE]
    local n = #row.cloth.spots
    local function spotLines()
        local out = {}
        for _, l in ipairs((GL.Drawn())) do
            if l.kind == "source" and l.tip and l.tip[1]:find("^#%d") then out[#out + 1] = l end
        end
        return out
    end
    T.eq(#spotLines(), 0, "closed by default")
    for _, r in ipairs(select(2, GL.Drawn())) do
        if r:IsShown() and r.line == row then r:GetScript("OnClick")(r) end
    end
    local open = spotLines()
    T.eq(#open, n, "one line per spot")
    for _, l in ipairs(open) do T.ok(l.pin ~= nil, "a pin each") end
    for _, r in ipairs(select(2, GL.Drawn())) do
        if r:IsShown() and r.line and r.line.cloth then r:GetScript("OnClick")(r) end
    end
    T.eq(#spotLines(), 0, "closed again")
end)

T.test("the row's tooltip is the item, then the pool and spots", function()
    scene({ zone = STV, level = 45, needs = { [FIRST_AID] = { [MAGEWEAVE] = 60 } } })
    drawn()
    local added = {}
    World.patch("GameTooltip.AddLine", function(_, text) added[#added + 1] = text end)
    local shown
    for _, r in ipairs(select(2, GL.Drawn())) do
        if r:IsShown() and r.line and r.line.cloth then
            r:GetScript("OnEnter")(r)
            shown = r.line
        end
    end
    T.ok(shown, "the row was drawn")
    T.eq(added[1], shown.tip[1])
    T.eq(#added, #shown.tip)
end)

T.test("the Cloth section sits above Cooking and Fishing and below the gathering sections", function()
    scene({ zone = STV, level = 41, needs = { [FIRST_AID] = { [MAGEWEAVE] = 60 } } })
    local fish = { { kind = "plan", text = "fish here" } }
    local out = GL.Lines({}, {}, fish)
    local keys = {}
    for _, l in ipairs(out) do
        if l.kind == "section" then keys[#keys + 1] = l.key end
    end
    T.eq(keys, { GL.CLOTH_KEY, G.FISHING }, "Cloth, then Fishing")
    T.eq(out[1].info, "have / need", "Cloth leads and carries the column note")
end)

T.test("a band names its creature type in the client's plural, whatever the type", function()
    local want = { [1] = "beasts", [2] = "dragonkin", [3] = "demons", [4] = "elementals", [5] = "giants",
                   [6] = "undead", [7] = "humanoids", [9] = "mechanicals" }
    for kind, word in pairs(want) do
        T.eq(CP.GatherList.ClothWho({ kind = kind, lo = 40, hi = 45 }), word .. " 40-45")
    end
    T.eq(CP.GatherList.ClothWho({ kind = 99, lo = 40, hi = 40 }), "creatures 40", "an unnamed type reads plainly")
end)
