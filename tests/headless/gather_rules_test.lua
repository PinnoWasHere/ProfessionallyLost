-- Logic tests with no frame and no on-screen text (so no scene): gathering guides start where a character can go, name their own zone's creatures and
-- put train rows before the stretch they gate; offline-whisper and recipe matching
-- follow the client's language.

local CP = ProfLost
local GG, G = CP.GatherGuide, CP.Gather
local HERB, MINE, SKIN, FISH = 182, 186, 393, 356
local DUROTAR, ELWYNN, SILVERPINE = 1411, 1429, 1421
local ZEPHRAS, ZEPHRAS_B = 2521, 2665

local function none() return 0 end

-- No zone map in the harness: every cluster stays in the zone the data puts it in.
local function flatMap()
    local orig = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end
    G.ResetClusters()
    return function()
        CP.Waypoint.MapPosZone = orig
        G.ResetClusters()
    end
end

local function rows(line, skill, max, level, side, zone)
    return GG.Rows({ line = line, skill = skill, max = max, level = level, side = side, zone = zone,
                     needs = {}, have = none })
end

-- Zephras Isle ---------------------------------------------------------------------

T.test("Zephras Isle is not offered to a character standing elsewhere", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        for _, side in ipairs({ "Alliance", "Horde" }) do
            local home = side == "Horde" and DUROTAR or ELWYNN
            for _, line in ipairs({ HERB, MINE }) do
                for _, c in ipairs({ { 1, 75, 1 }, { 1, 75, 5 }, { 60, 75, 12 }, { 100, 150, 30 } }) do
                    for _, r in ipairs(rows(line, c[1], c[2], c[3], side, home)) do
                        local zone = r.gather and r.gather.zone
                        T.ok(zone ~= ZEPHRAS and zone ~= ZEPHRAS_B,
                            ("%s %d from %d at level %d: a row in Zephras Isle"):format(side, line, c[1], c[3]))
                    end
                end
            end
        end
    end)
    restore()
    T.ok(ok, err)
end)

T.test("a character standing in Zephras Isle starts there, on either map", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        for _, side in ipairs({ "Alliance", "Horde" }) do
            for _, line in ipairs({ HERB, MINE }) do
                for _, here in ipairs({ ZEPHRAS, ZEPHRAS_B }) do
                    local first
                    for _, r in ipairs(rows(line, 1, 75, 1, side, here)) do
                        if r.gather then first = r break end
                    end
                    T.eq(first and first.gather.zone, ZEPHRAS, ("%s %d standing on map %d"):format(side, line, here))
                end
            end
        end
    end)
    restore()
    T.ok(ok, err)
end)

-- First stretches ------------------------------------------------------------------------

local STARTS = {
    { "Alliance", 1429 }, { "Alliance", 1438 }, { "Alliance", 1426 },
    { "Horde", 1411 }, { "Horde", 1412 }, { "Horde", 1420 },
}
local MOONGLADE = 1450
local REACH = 12   -- a zone's low creature level the first 50 skill points may reach at level 1

-- Rows on the harness's real zone maps (clusters clipped to their zone), as the game builds them.
local function sceneRows(line, level, side, here)
    MapWorld.begin({ zone = here, level = level, side = side, shareSolves = true })
    return rows(line, 1, 75, level, side, here)
end

local function lowLevel(zone)
    local lvl = GG.ZONE_LEVELS[zone] or CP.GatherData.zones[zone].lvl
    return lvl and lvl[1] or 1
end

-- A level 1 character's first 50 skill points stay on their continent, in zones whose
-- creatures start at level REACH or below.
T.test("a new character's first 50 skill points stay on their continent and level", function()
    GG.Reset()
    local ok, err = pcall(function()
        for _, start in ipairs(STARTS) do
            local side, here = start[1], start[2]
            local continent = CP.GatherData.zones[here].map
            for _, line in ipairs({ HERB, MINE, SKIN }) do
                local label = ("%s %d from zone %d"):format(side, line, here)
                local first
                for _, r in ipairs(sceneRows(line, 1, side, here)) do
                    if r.gather and r.from < 50 then
                        first = first or r
                        local z = r.gather.zone
                        T.eq(CP.GatherData.zones[z].map, continent, ("%s: %d-%d is in zone %d"):format(label, r.from, r.to, z))
                        T.ok(lowLevel(z) <= REACH, ("%s: zone %d starts at level %d"):format(label, z, lowLevel(z)))
                        T.ok(z ~= MOONGLADE, label .. ": Moonglade")
                    end
                end
                -- Teldrassil has no ore of its own: a miner there goes to the nearest ground.
                if not (line == MINE and here == 1438) then
                    T.eq(first and first.gather.zone, here, label .. ": starts in the zone they stand in")
                end
            end
        end
    end)
    GG.Reset()
    T.ok(ok, err)
end)

T.test("Moonglade is not offered below the level its data says", function()
    GG.Reset()
    local ok, err = pcall(function()
        local floor = lowLevel(MOONGLADE)
        T.ok(floor >= 50, "the zone's own range starts at 50 or above")
        for _, side in ipairs({ "Alliance", "Horde" }) do
            for _, level in ipairs({ 1, 10, 20, 30, 40 }) do
                local here = side == "Horde" and DUROTAR or ELWYNN
                for _, r in ipairs(sceneRows(SKIN, level, side, here)) do
                    T.ok(not (r.gather and r.gather.zone == MOONGLADE), ("%s level %d: Moonglade at %d"):format(side, level, r.from))
                end
            end
        end
    end)
    GG.Reset()
    T.ok(ok, err)
end)

T.test("a skinning row names only creatures the data gives skin loot", function()
    GG.Reset()
    local ok, err = pcall(function()
        for _, start in ipairs(STARTS) do
            for _, r in ipairs(sceneRows(SKIN, 1, start[1], start[2])) do
                if r.gather then
                    for _, t in ipairs(r.gather.targets) do
                        local m = CP.GatherData.mobs[t.entry]
                        T.ok(m and m[4] and m[4][SKIN] and G.Skinnable(t.entry), t.name .. " is skinnable in the data")
                    end
                end
            end
        end
    end)
    GG.Reset()
    T.ok(ok, err)
end)

T.test("a level 1 night elf without ore at home is pointed at Darkshore, Alliance ground", function()
    GG.Reset()
    local first
    for _, r in ipairs(sceneRows(MINE, 1, "Alliance", 1438)) do
        if r.gather then first = r break end
    end
    GG.Reset()
    T.eq(first and first.gather.zone, 1439, "Darkshore, not the contested Barrens")
end)

-- Fishing: a row covers skill 1, the first 50 points stay on the start continent, and the
-- current-step marker sits on the row that covers the player's skill.
T.test("a new character's fishing guide starts at once, on their continent", function()
    for _, start in ipairs(STARTS) do
        local side, here = start[1], start[2]
        MapWorld.begin({ zone = here, level = 1, side = side, shareSolves = true })
        local continent = CP.GatherData.zones[here].map
        local covering, marked
        for _, r in ipairs(rows(FISH, 1, 75, 1, side, here)) do
            if r.fish then
                if r.from <= 1 and 1 < r.to then covering = r end
                if r.from < 50 then
                    T.eq(CP.GatherData.zones[r.fish.zone].map, continent,
                        ("%s zone %d: %d-%d is in zone %d"):format(side, here, r.from, r.to, r.fish.zone))
                end
            end
            if r.current then marked = r end
        end
        T.ok(covering ~= nil, ("%s zone %d: a row covers skill 1"):format(side, here))
        T.ok(marked and marked.from <= 1 and 1 < marked.to, ("%s zone %d: the marker is on the row that covers skill 1"):format(side, here))
        T.eq(covering and covering.fish.zone, here, ("%s zone %d: fishes where they stand"):format(side, here))
    end
end)

T.test("a level 1 character's water for a fish is the zone they stand in", function()
    MapWorld.begin({ zone = DUROTAR, level = 1, side = "Horde", shareSolves = true })
    local found = 0
    local z = CP.GatherData.zones[DUROTAR]
    for _, l in ipairs(CP.GatherData.loot[z.fish.loot] or {}) do
        local water = CP.Fishing.WaterFor(l[1], 1, 1, "Horde")
        if water then
            found = found + 1
            T.eq(water.zone, DUROTAR, "named water")
        end
    end
    T.ok(found > 0, "Durotar's fish have water at level 1")
end)

-- Skinning names ---------------------------------------------------------------------

-- The names GG.TargetNames gives for a row are creatures or nodes the row's own zone holds.
T.test("a gathering row names only targets its own zone has", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        local cases = {
            { SKIN, 1, 75, 3, "Alliance", ELWYNN }, { SKIN, 1, 75, 5, "Horde", DUROTAR },
            { SKIN, 100, 150, 30, "Horde", SILVERPINE }, { SKIN, 130, 150, 25, "Alliance", ELWYNN },
            { SKIN, 200, 225, 45, "Horde", DUROTAR }, { HERB, 40, 75, 20, "Alliance", ELWYNN },
            { MINE, 100, 150, 30, "Horde", SILVERPINE }, { MINE, 1, 75, 5, "Alliance", ELWYNN },
        }
        for _, c in ipairs(cases) do
            for _, r in ipairs(rows(unpack(c))) do
                if r.gather then
                    local zone = CP.GatherData.zones[r.gather.zone]
                    local mine = {}
                    for _, t in ipairs(r.gather.targets) do
                        T.ok(zone[t.kind] and zone[t.kind][t.entry],
                            ("%d from %d (%s): %s is not in zone %d"):format(c[1], c[2], c[5], t.name, r.gather.zone))
                        mine[t.name] = true
                    end
                    for _, name in ipairs(GG.TargetNames(r.gather.targets, r.from, 3)) do
                        -- A green-only row marks its name "(green)"; a level row leads with "reach level N".
                        if not name:find("^reach level") then
                            name = name:gsub(" %(green%)$", "")
                            T.ok(mine[name], name .. " named for zone " .. r.gather.zone)
                        end
                    end
                end
            end
        end
    end)
    restore()
    T.ok(ok, err)
end)

-- Train rows ---------------------------------------------------------------------------

-- Reading top to bottom, a rank row sits where the rank becomes learnable: every stretch
-- above it ends at or before that skill, every stretch below starts at or after it.
T.test("a train row comes before the stretch from its learn skill and splits any stretch that spans it", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        local cases = {
            { HERB, 40, 75, 20, "Alliance", ELWYNN }, { HERB, 1, 75, 5, "Horde", DUROTAR },
            { MINE, 100, 150, 30, "Horde", SILVERPINE }, { MINE, 1, 75, 5, "Alliance", ELWYNN },
            { SKIN, 1, 75, 3, "Alliance", ELWYNN }, { SKIN, 130, 150, 30, "Horde", DUROTAR },
            { MINE, 160, 225, 40, "Alliance", ELWYNN }, { HERB, 60, 75, 12, "Horde", DUROTAR },
            { HERB, 1, 75, 60, "Horde", DUROTAR },
        }
        for _, c in ipairs(cases) do
            local list = rows(unpack(c))
            local label = ("%d from %d (%s)"):format(c[1], c[2], c[5])
            local ranks = 0
            for i, r in ipairs(list) do
                if r.gatherRank then
                    ranks = ranks + 1
                    local at = r.from
                    T.eq(at, math.max(r.gatherRank.at, c[2]), label .. ": the row shows its learn skill")
                    for j, other in ipairs(list) do
                        if other.gather then
                            if j < i then
                                T.ok(other.to <= at, ("%s: %d-%d sits above the %d train row"):format(label, other.from, other.to, at))
                            else
                                T.ok(other.from >= at, ("%s: %d-%d sits below the %d train row"):format(label, other.from, other.to, at))
                            end
                        end
                    end
                end
            end
            T.ok(ranks > 0 or c[3] >= 300, label .. " has rank rows")
        end
    end)
    restore()
    T.ok(ok, err)
end)

T.test("the first train row of Herbalism 40 splits Elwynn at 50", function()
    local restore = flatMap()
    local list = rows(HERB, 40, 75, 20, "Alliance", ELWYNN)
    restore()
    T.eq({ list[1].gather ~= nil, list[1].from, list[1].to }, { true, 40, 50 })
    T.eq({ list[2].gatherRank ~= nil, list[2].from }, { true, 50 })
    T.eq(list[3].from, 50)
end)

-- Offline whisper filter ----------------------------------------------------------------

local P = CP.Peers

-- Whispers `name` through the peers' own path, so P.HideSystem has it on record.
local function whispered(name)
    PeerWorld.begin({ version = "0.2.0", zone = 2548 })
    World.set(CP.db, "newsSeen", CP.db.newsSeen)
    local peer = PeerWorld.Peer(name, { version = "0.1.0" })
    peer:Hello("YELL")
    T.advance(2)
end

T.test("the offline-whisper line follows the client's own text, in any word order", function()
    -- A German-style line with the name first and punctuation the English one lacks.
    World.set(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S", "%s ist gerade nicht online (100%%).")
    whispered("Ann")
    T.ok(P.HideSystem(nil, "CHAT_MSG_SYSTEM", "Ann ist gerade nicht online (100%)."))
    T.ok(P.HideSystem(nil, "CHAT_MSG_SYSTEM", "Ann-Testrealm ist gerade nicht online (100%)."), "with the realm")
    T.ok(not P.HideSystem(nil, "CHAT_MSG_SYSTEM", "Bob ist gerade nicht online (100%)."), "another name")
    T.ok(not P.HideSystem(nil, "CHAT_MSG_SYSTEM", "No player named 'Ann' is currently playing."), "the English line")
    T.ok(not P.HideSystem(nil, "CHAT_MSG_SYSTEM", ""), "an empty line")
end)

T.test("without the client string the offline-whisper filter hides nothing and does not fail", function()
    World.set(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S", nil)
    whispered("Ann")
    T.eq(P.NotFoundLine("Ann"), nil)
    for _, msg in ipairs({ "", "Ann", "No player named 'Ann' is currently playing.", "%s", ".*" }) do
        T.ok(not P.HideSystem(nil, "CHAT_MSG_SYSTEM", msg), "kept: " .. msg)
    end
    World.set(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S", "%d")
    T.eq(P.NotFoundLine("Ann"), nil, "a string that cannot take a name is ignored")
    T.ok(not P.HideSystem(nil, "CHAT_MSG_SYSTEM", "%d"))
end)

T.test("a name with pattern characters matches as written", function()
    World.set(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S", "No player named '%s' is currently playing.")
    whispered("A.n%")
    T.ok(P.HideSystem(nil, "CHAT_MSG_SYSTEM", "No player named 'A.n%' is currently playing."))
    T.ok(not P.HideSystem(nil, "CHAT_MSG_SYSTEM", "No player named 'Axn%' is currently playing."))
end)

-- Recipe aliases -------------------------------------------------------------------------

T.test("a guide recipe matches the player's recipe by spell, then item, then name", function()
    local guide = { recipes = {
        [818] = { name = "Basic Campfire", makes = nil },
        [2540] = { name = "Roasted Boar Meat", makes = 2681 },
        [2538] = { name = "Charred Wolf Meat", makes = 2679 },
        [3000] = { name = "Plain Bread", makes = 5555 },
        [3001] = { name = "Fancy Bread", makes = 5555 },
        [3100] = { name = "Soup", makes = 6000 },
    } }
    -- A German client: names differ, ids differ for the duplicates, items are the same.
    local live = {
        { id = 2540, name = "Gebratenes Wildschweinfleisch", learned = true },
        { id = 9002538, name = "Verkohltes Wolfsfleisch", learned = true },
        { id = 9003000, name = "Brot", learned = true },
        { id = 1229737, name = "Basic Campfire", learned = true },
        { id = 9003100, name = "Suppe", learned = true },
    }
    local items = { [9002538] = 2679, [9003000] = 5555, [2540] = 2681 }
    World.patch("C_TradeSkillUI.GetRecipeOutputItemData", function(id)
        return items[id] and { itemID = items[id] } or nil
    end)
    local learned = CP.Professions.Learned(live)
    local alias = CP.Plan.Alias(guide, live, learned)
    T.eq(alias[2540], nil, "known by its own id: no alias, whatever the name")
    T.ok(learned[2540])
    T.eq(alias[2538], 9002538, "by the item it makes, with another name")
    T.ok(learned[2538])
    T.eq(alias[3000], nil, "an item two guide recipes make says nothing")
    T.eq(alias[3001], nil)
    T.eq(alias[818], 1229737, "by name when it makes no item")
    T.eq(alias[3100], nil, "no item, no matching name: not learned")
    T.ok(not learned[3100])
end)
