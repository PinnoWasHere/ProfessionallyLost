local _, CP = ...
if CP.stopped then return end

-- Gathering zones by skill band, after wow-professions.com's Classic guides
-- (the wow-professions.com gathering guide). Hand-written. The gathering guide boosts these
-- zones; its scorer still drops enemy, empty or over-level ones.
-- { from skill, to skill, { uiMapID, ... } }; Skinning splits by faction.

local DUROTAR, MULGORE, TIRISFAL = 1411, 1412, 1420
local ELWYNN, TELDRASSIL, DUN_MOROGH, DARKSHORE = 1429, 1438, 1426, 1439
local BARRENS, SILVERPINE, LOCH_MODAN, REDRIDGE, ASHENVALE = 1413, 1421, 1432, 1433, 1440
local HILLSBRAD, WETLANDS, STONETALON = 1424, 1437, 1442
local ARATHI, STRANGLETHORN, DESOLACE, NEEDLES = 1417, 1434, 1443, 1441
local TANARIS, SEARING_GORGE, HINTERLANDS, FERALAS = 1446, 1427, 1425, 1444
local FELWOOD, UNGORO, BLASTED_LANDS = 1448, 1449, 1419
local EPL, WINTERSPRING, BURNING_STEPPES = 1423, 1452, 1428

-- The site lists both factions' home zones in one row; each faction keeps its own.
local function both(horde, alliance, shared)
    local h, a = {}, {}
    for _, band in ipairs(shared) do
        h[#h + 1], a[#a + 1] = band, band
    end
    for i, band in ipairs(horde) do table.insert(h, i, band) end
    for i, band in ipairs(alliance) do table.insert(a, i, band) end
    return { Horde = h, Alliance = a }
end

local HERB = both({
    { 1, 70, { DUROTAR, MULGORE, TIRISFAL } },
    { 70, 115, { BARRENS, SILVERPINE } },
}, {
    { 1, 70, { ELWYNN, TELDRASSIL, DUN_MOROGH } },
    { 70, 115, { LOCH_MODAN, DARKSHORE } },
}, {
    { 115, 170, { HILLSBRAD, WETLANDS, STONETALON } },
    { 170, 205, { STRANGLETHORN, ARATHI } },
    { 205, 230, { TANARIS, SEARING_GORGE } },
    { 230, 270, { HINTERLANDS } },
    { 270, 300, { FELWOOD } },
})

local MINE = both({
    { 1, 65, { DUROTAR, MULGORE, TIRISFAL } },
    { 65, 125, { HILLSBRAD, ASHENVALE, BARRENS } },
}, {
    { 1, 65, { ELWYNN, DARKSHORE, DUN_MOROGH } },
    { 65, 125, { HILLSBRAD, REDRIDGE, ASHENVALE } },
}, {
    { 125, 175, { ARATHI, DESOLACE, NEEDLES } },
    { 175, 245, { HINTERLANDS, TANARIS } },
    { 245, 275, { UNGORO, BLASTED_LANDS, FELWOOD } },
    { 275, 300, { UNGORO, EPL, WINTERSPRING, BURNING_STEPPES } },
})

CP.SiteZones = {
    [182] = HERB,
    [186] = MINE,
    [393] = {
        Horde = {
            { 1, 75, { DUROTAR } },
            { 75, 125, { BARRENS } },
            { 125, 205, { NEEDLES } },
            { 205, 300, { FERALAS } },
            { 280, 300, { UNGORO } },
        },
        Alliance = {
            { 1, 75, { DUN_MOROGH } },
            { 75, 115, { LOCH_MODAN } },
            { 115, 155, { WETLANDS } },
            { 155, 205, { ARATHI } },
            { 205, 300, { FERALAS } },
            { 280, 300, { UNGORO } },
        },
    },
}
