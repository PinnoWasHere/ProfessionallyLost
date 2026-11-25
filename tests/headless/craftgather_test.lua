-- A crafting profession picked on the gathering panel lists what its guide still needs that this
-- zone gives, under "Gather it yourself", whether or not the player has the gathering profession
-- (player report on 1.4.0: Alchemy picked showed "Nothing for Alchemy here." in herb country).

local CP = ProfLost
local G, GL = CP.Gather, CP.GatherList
local HERB, MINE, ALCHEMY = 182, 186, 171
local DUROTAR = 1411
local PEACEBLOOM, EARTHROOT, COPPER = 2447, 2449, 2770

-- Durotar at level 20, Alchemy at 40 picked on the panel, its guide needing 20 Peacebloom.
-- `skills` are the gathering ranks; `needs` replaces Alchemy's needs.
local function scene(skills, needs)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    for _, key in ipairs({ "routeMode", "routeSkip", "skinSkip", "gatherClosed", "farmClosed" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "gatherNeeds", { [ALCHEMY] = needs or { [PEACEBLOOM] = 20 } })
    World.set(CP.charDB, "gatherSoon", nil)
    local ranks = { [ALCHEMY] = 40 }
    for id, rank in pairs(skills) do ranks[id] = rank end
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = ranks[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.set(CP.Window, "Professions", function() return { { id = ALCHEMY, name = "Alchemy" } } end)
    World.patch("C_Item.GetItemCount", function(id) return id == PEACEBLOOM and 3 or 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.charDB, "panelProf", ALCHEMY)
    G.ResetClusters()
    World.onEnd(function() G.ResetClusters() end)
end

-- The drawn lines: the Alchemy section header, its item rows by item, and the empty line's state.
local function drawn()
    local any = GL.Refresh()
    local head, items = nil, {}
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "section" and l.key == ALCHEMY then head = l end
        if l.kind == "item" then items[l.row.itemID] = l end
    end
    return head, items, any
end

T.test("Alchemy picked with Herbalism lists the Peacebloom its guide needs here, with have / need and a pin", function()
    scene({ [HERB] = 50 })
    T.eq(GL.PanelProf(), ALCHEMY, "Alchemy is the pick")
    local head, items, any = drawn()
    T.ok(any, "the list has rows")
    T.ok(head, "an Alchemy section")
    T.eq(head.text, "Alchemy 40")
    T.eq(head.info, "have / need")
    local row = items[PEACEBLOOM]
    T.ok(row, "a Peacebloom row")
    T.eq(row.info, "3 / 20")
    T.ok(row.pin ~= nil, "the row's pin leads to where it grows")
    T.eq(row.row.lacks, nil, "the player can pick it")
    local placed
    World.set(CP.Waypoint, "PlaceOnMap", function(zone, x, y, label) placed = { zone = zone, label = label } end)
    row.pin()
    T.ok(placed, "the pin places a waypoint")
    T.eq(placed.zone, DUROTAR)
    T.eq(placed.label, row.row.name, "labelled by the item")
end)

T.test("Alchemy picked without Herbalism still lists the herb and says Herbalism is missing", function()
    scene({})
    local head, items = drawn()
    T.ok(head, "an Alchemy section")
    local row = items[PEACEBLOOM]
    T.ok(row, "a Peacebloom row")
    T.eq(row.info, "3 / 20 · no Herbalism")
    T.ok(row.pin ~= nil, "still pinned: it shows where it grows")
    local said = false
    for _, text in ipairs(row.tip or {}) do said = said or text == GL.LacksText("Herbalism") end
    T.ok(said, "the tooltip says why it can't be picked")
end)

T.test("a herb above the player's Herbalism lists with the rank it needs", function()
    scene({ [HERB] = 5 }, { [EARTHROOT] = 10 })
    local _, items = drawn()
    local row = items[EARTHROOT]
    T.ok(row, "an Earthroot row")
    T.eq(row.info, ("0 / 10 · Herbalism %d"):format(row.row.short or -1))
    T.ok((row.row.short or 0) > 5, "the rank it needs is above the player's")
end)

T.test("a need this zone doesn't give leaves the section out and the empty line says so", function()
    scene({ [HERB] = 50, [MINE] = 50 }, { [COPPER] = 0, [3821] = 10 })   -- Goldthorn grows nowhere in Durotar
    GatherWorld.AnswerClasses({ [3821] = { 7, 9 }, [COPPER] = { 7, 7 } })   -- Herb, Metal & Stone
    local head, items, any = drawn()
    T.eq(head, nil, "no Alchemy section")
    T.eq(next(items), nil, "no rows")
    T.ok(not any, "the list is empty")
    T.eq(GL.EmptyText(), "No herbs Alchemy needs grow here.")
end)

T.test("with Gather it yourself off, the section stays out and the empty line says why", function()
    scene({ [HERB] = 50 })
    World.set(CP.db, "collect", false)
    local head = drawn()
    T.eq(head, nil, "no Alchemy section")
    T.eq(GL.EmptyText(), "Gather it yourself is off, so Alchemy buys what it needs.")
end)

T.test("the Herbalism pick keeps its own section, with no Alchemy section", function()
    scene({ [HERB] = 50 })
    World.set(CP.charDB, "panelProf", HERB)
    GL.Refresh()
    local herb, alch = false, false
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "section" then
            herb = herb or l.key == HERB
            alch = alch or l.key == ALCHEMY
        end
    end
    T.ok(herb, "Herbalism shows")
    T.ok(not alch, "Alchemy does not")
end)
