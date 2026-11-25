local _, CP = ...
if CP.stopped then return end

-- Levelling lanes: where each faction quests at each level, as a common levelling
-- guide runs it. Hand-written, not generated. Gathering guides lean toward the lane's
-- zones for the level a character gathering at that skill would be, so gathering
-- happens where the player is questing anyway. A zone's revisits are one span.
-- { from level, to level, { uiMapID, ... } }

CP.Lanes = {
    Horde = {
        { 1, 13, { 1411, 1412, 1420 } },    -- Durotar, Mulgore, Tirisfal Glades
        { 13, 15, { 1421 } },               -- Silverpine Forest
        { 15, 26, { 1413, 1442 } },         -- The Barrens, Stonetalon Mountains
        { 21, 28, { 1440 } },               -- Ashenvale
        { 22, 32, { 1424 } },               -- Hillsbrad Foothills
        { 28, 34, { 1441 } },               -- Thousand Needles
        { 32, 39, { 1417 } },               -- Arathi Highlands
        { 34, 41, { 1443 } },               -- Desolace
        { 36, 51, { 1434 } },               -- Stranglethorn Vale
        { 37, 48, { 1445 } },               -- Dustwallow Marsh
        { 38, 39, { 1416 } },               -- Alterac Mountains
        { 39, 40, { 1418 } },               -- Badlands
        { 40, 51, { 1435 } },               -- Swamp of Sorrows
        { 41, 48, { 1446 } },               -- Tanaris
        { 43, 50, { 1444 } },               -- Feralas
        { 48, 49, { 1425 } },               -- The Hinterlands
        { 49, 54, { 1449 } },               -- Un'Goro Crater
        { 50, 51, { 1419 } },               -- Blasted Lands
        { 51, 52, { 1427, 1428 } },         -- Searing Gorge, Burning Steppes
        { 51, 54, { 1447 } },               -- Azshara
        { 52, 59, { 1448, 1452 } },         -- Felwood, Winterspring
        { 56, 58, { 1422, 1423 } },         -- Western and Eastern Plaguelands
        { 59, 60, { 1451 } },               -- Silithus
    },
    Alliance = {
        { 1, 13, { 1429, 1426, 1438 } },    -- Elwynn Forest, Dun Morogh, Teldrassil
        { 13, 20, { 1436 } },               -- Westfall
        { 15, 21, { 1439 } },               -- Darkshore
        { 18, 19, { 1432 } },               -- Loch Modan
        { 19, 27, { 1433 } },               -- Redridge Mountains
        { 21, 30, { 1440 } },               -- Ashenvale
        { 21, 24, { 1442 } },               -- Stonetalon Mountains
        { 24, 29, { 1437 } },               -- Wetlands
        { 25, 32, { 1431 } },               -- Duskwood
        { 30, 50, { 1434 } },               -- Stranglethorn Vale
        { 32, 33, { 1424 } },               -- Hillsbrad Foothills
        { 32, 40, { 1417 } },               -- Arathi Highlands
        { 33, 41, { 1445 } },               -- Dustwallow Marsh
        { 33, 34, { 1441 } },               -- Thousand Needles
        { 35, 37, { 1443 } },               -- Desolace
        { 38, 40, { 2548 } },               -- Riverglades (Forever)
        { 40, 40, { 1416 } },               -- Alterac Mountains
        { 41, 42, { 1418 } },               -- Badlands
        { 43, 43, { 1435 } },               -- Swamp of Sorrows
        { 43, 49, { 1446 } },               -- Tanaris
        { 44, 53, { 1444 } },               -- Feralas
        { 48, 49, { 1425 } },               -- The Hinterlands
        { 49, 54, { 1449 } },               -- Un'Goro Crater
        { 50, 51, { 1427 } },               -- Searing Gorge
        { 51, 51, { 1419 } },               -- Blasted Lands
        { 51, 57, { 1428 } },               -- Burning Steppes
        { 51, 58, { 1422 } },               -- Western Plaguelands
        { 52, 53, { 1447 } },               -- Azshara
        { 52, 56, { 1448 } },               -- Felwood
        { 54, 59, { 1452 } },               -- Winterspring
        { 57, 58, { 1423 } },               -- Eastern Plaguelands
        { 59, 60, { 1451 } },               -- Silithus
    },
}
