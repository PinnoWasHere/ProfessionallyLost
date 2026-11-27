local _, CP = ...
if CP.stopped then return end

-- What the player can gather in a zone with the professions they have, and from
-- what: creatures to skin or loot, herb and ore nodes, fishing waters and pools.
-- The data is CP.GatherData (Data/Gather.lua).

local Gather = {}
CP.Gather = Gather

Gather.SKINNING, Gather.MINING, Gather.HERBALISM = 393, 186, 182
Gather.COOKING, Gather.FISHING = 185, 356
Gather.PROFS = { 393, 186, 182, 185, 356 }

local ORDER = { [393] = 1, [186] = 2, [182] = 3, [185] = 4, [356] = 5 }

-- Each faction's home zones and capitals. Guides never send a player into the other
-- faction's (Stormwind's canals are a fine 75-130 spot, for the Alliance only).
local HOME_ZONES = {
    Alliance = { [1429] = true, [1426] = true, [1438] = true, [1436] = true, [1432] = true, [1439] = true,
                 [1453] = true, [1455] = true, [1457] = true },
    Horde = { [1411] = true, [1412] = true, [1420] = true, [1421] = true,
              [1454] = true, [1456] = true, [1458] = true },
}
local ENEMY = { Alliance = "Horde", Horde = "Alliance" }

-- Each faction's own levelling ground beyond its home zones: towns, flight paths and
-- quests there are theirs (Redridge and Duskwood for the Alliance, the Barrens for the Horde).
local TERRITORY = {
    Alliance = { [1433] = true, [1431] = true, [1437] = true },
    Horde = { [1413] = true },
}

-- "own", "enemy" or "contested": whose ground `zone` is for `side`.
function Gather.Territory(zone, side)
    local enemy = ENEMY[side]
    if not enemy then return "contested" end
    if HOME_ZONES[side][zone] or TERRITORY[side][zone] then return "own" end
    if HOME_ZONES[enemy][zone] or TERRITORY[enemy][zone] then return "enemy" end
    return "contested"
end

-- The player's level.
function Gather.PlayerLevel()
    return UnitLevel("player") or 1
end

-- True when `zone` is a home zone of the faction opposing `side` ("Alliance" or "Horde").
function Gather.EnemyHome(zone, side)
    local enemy = side and HOME_ZONES[ENEMY[side]]
    return enemy ~= nil and enemy[zone] == true
end

-- Skill needed to skin, herb or mine a corpse of `level`.
-- Which creatures Forever lets the player skin. The data's skinning loot comes from a
-- server dump, and Forever's server leaves some out (Giant Plains Creeper). The game
-- shows which: a skinnable corpse's tooltip carries a "Skinnable" line once it's looted.
-- CP.db.skinSeen[id] = true after one shows it (or a skin succeeds); a number counts
-- looted corpses seen without it, and NO_SKIN of those with none showing it means no.
Gather.NO_SKIN = 2
Gather.NOT_SKINNABLE = { [2565] = true }   -- Giant Plains Creeper, seen in game 2026-11-12

local function skinSeen()
    if not CP.db then return {} end
    CP.db.skinSeen = CP.db.skinSeen or {}
    return CP.db.skinSeen
end

-- False when Forever doesn't let creature `id` be skinned; true otherwise. The
-- player's own skin wins, then the known list, then any peer's skin (Engine/Peers.lua),
-- then the player's looted corpses, then CONSENSUS peers saying no.
function Gather.Skinnable(id)
    local seen = skinSeen()[id]
    if seen == true then return true end
    if Gather.NOT_SKINNABLE[id] then return false end
    local peer = CP.Peers and CP.Peers.Skin(id)
    if peer == true then return true end
    if type(seen) == "number" and seen >= Gather.NO_SKIN then return false end
    return peer ~= false
end

-- Caches that hold creatures by skinnable answer, declared here for SkinChanged.
local continentSkins = {}   -- Gather.ContinentSkins' answers by their key
local resets = 0    -- counts cache resets, so a build that yielded across one isn't kept
-- The last ForZone list asked for with opts.cache, and what it was built for.
local zoneRows = { key = nil, list = nil, zone = nil }
local zoneTargets = {}   -- Gather.ZoneTargets' answers by zone, line and reset

-- Guides, farm spots and the checklist after a creature's skinnable answer changes.
function Gather.SkinChanged()
    resets = resets + 1
    zoneRows.key, zoneRows.list, zoneRows.zone = nil, nil, nil
    wipe(continentSkins)
    wipe(zoneTargets)
    if CP.GatherGuide then CP.GatherGuide.Reset() end
    if CP.Farm and CP.Farm.Reset then CP.Farm.Reset() end
    if CP.GatherList then CP.GatherList.Changed() end
end

-- True when creature `entry` gives `prof` loot in this game.
function Gather.Gives(entry, prof)
    return prof ~= Gather.SKINNING or Gather.Skinnable(entry)
end

-- What a looted corpse showed: `skinnable` true when its tooltip had the line.
-- `guid` keeps one corpse from counting twice.
local counted = {}
Gather.COUNTED_MAX = 200   -- corpses remembered this session; plenty to tell two apart
function Gather.CountedSize()
    local n = 0
    for _ in pairs(counted) do n = n + 1 end
    return n
end
function Gather.LearnSkin(id, skinnable, guid)
    local seen = skinSeen()
    if seen[id] == true then return end
    local was = Gather.Skinnable(id)
    if skinnable then
        seen[id] = true
    elseif guid and not counted[guid] then
        if Gather.CountedSize() >= Gather.COUNTED_MAX then wipe(counted) end
        counted[guid] = true
        seen[id] = (type(seen[id]) == "number" and seen[id] or 0) + 1
    end
    if Gather.Skinnable(id) ~= was then Gather.SkinChanged() end
end

function Gather.CorpseSkill(level)
    if level <= 10 then return 1 end
    if level < 20 then return (level - 10) * 10 end
    return level * 5
end

-- Percent of bites that land in water with base level `base`, 0 to 100.
function Gather.LandChance(skill, base)
    return math.max(0, math.min(100, skill - base + 5))
end

-- The rank alone: a modifier (a fishing pole, a lure) lifts no skill-up or step.
local function rankOf(info)
    if type(info) ~= "table" or info.isHeader then return nil end
    local r = info.rank or 0
    return r > 0 and r or nil
end

-- { [skillLine] = rank } for the gathering-side professions the player has.
function Gather.Skills()
    local out = {}
    if not C_SkillInfo then return out end
    local wanted = {}
    for _, id in ipairs(Gather.PROFS) do wanted[id] = true end
    if C_SkillInfo.GetSkillLineInfoByID or CP.Professions.preview then
        for id in pairs(wanted) do out[id] = rankOf(CP.Professions.SkillLine(id)) end
        return out
    end
    local ok, n = pcall(C_SkillInfo.GetNumSkillLines)
    for i = 1, ok and n or 0 do
        local got, info = pcall(C_SkillInfo.GetSkillLineInfo, i)
        if got and type(info) == "table" and wanted[info.skillID] then out[info.skillID] = rankOf(info) end
    end
    return out
end

-- The skill's current cap (75, 150, 225 or 300), or nil when the player lacks it.
function Gather.MaxRank(id)
    local info = CP.Professions.SkillLine(id)
    return info and info.maxRank or nil
end

local function bySource(a, b)
    if a.chance ~= b.chance then return a.chance > b.chance end
    return a.name < b.name
end

-- Highest creature level that is grey to a player of `level` (gives no XP).
function Gather.GreyLevel(level)
    if level <= 5 then return 0 end
    if level <= 39 then return level - math.floor(level / 10) - 5 end
    if level <= 59 then return level - math.floor(level / 5) - 1 end
    return level - 9
end

-- Clusters are packed 5 characters each (see Data/Gather.lua): x and y as two
-- base-92 digits, then the spawn count.
local DIGITS, VALUE = {}, {}
for c = 33, 126 do
    if c ~= 34 and c ~= 92 then
        DIGITS[#DIGITS + 1] = c
        VALUE[c] = #DIGITS - 1
    end
end
local BASE = #DIGITS
local SCALE = BASE * BASE - 1

-- { { x, y, spawns } } with x, y on the zone map (0 to 1).
function Gather.Decode(packed)
    local out = {}
    for i = 1, #packed - 4, 5 do
        local a, b, c, d, e = packed:byte(i, i + 4)
        out[#out + 1] = {
            (VALUE[a] * BASE + VALUE[b]) / SCALE,
            (VALUE[c] * BASE + VALUE[d]) / SCALE,
            VALUE[e],
        }
    end
    return out
end

-- Zone membership. The data's zone rectangles overlap at every border (most of
-- Dustwallow sits inside the Barrens' rectangle), so each per-zone point asks the
-- game's map whose ground it is: data spawns, GatherMate2 nodes, finds, peers' spots,
-- route stops and grind spot centres. Answers stay until a map call is swapped (only
-- tests do that), so rebuilding the clusters after a find makes no map calls.
local owners = {}   -- zone -> { [point key] = owning zone, or false where the map can't say }
local dataIn = {}   -- Clusters key -> the data's clusters the game puts in the zone
local asked = {}    -- the map calls the answers came from

local function sameMap()
    local W, M = CP.Waypoint, C_Map
    return asked[1] == W.MapPosZone and asked[2] == M.GetWorldPosFromMapPos
        and asked[3] == M.GetMapPosFromWorldPos and asked[4] == M.GetMapInfoAtPosition
        and asked[5] == M.GetMapInfo and asked[6] == CreateVector2D
end

local epoch = 0

-- A number that changes whenever the answers start over, for caches built on them.
function Gather.MapEpoch()
    if not sameMap() then
        local W, M = CP.Waypoint, C_Map
        owners, dataIn = {}, {}
        asked = { W.MapPosZone, M.GetWorldPosFromMapPos, M.GetMapPosFromWorldPos,
                  M.GetMapInfoAtPosition, M.GetMapInfo, CreateVector2D }
        epoch = epoch + 1
    end
    return epoch
end

-- The zone the game puts a point of `zone`'s map in, or nil where the map can't say.
function Gather.ZoneAt(zone, x, y)
    Gather.MapEpoch()
    local byZone = owners[zone]
    if not byZone then byZone = {}; owners[zone] = byZone end
    local key = math.floor(x * 1e6 + 0.5) * 1e7 + math.floor(y * 1e6 + 0.5)
    local at = byZone[key]
    if at == nil then
        at = CP.Waypoint.MapPosZone(zone, x, y) or false
        byZone[key] = at
    end
    return at or nil
end

-- True when the game puts the point in `zone`, or can't say (instances have no map;
-- Forever's new zones may not answer).
function Gather.Inside(zone, x, y)
    if zone >= Gather.INSTANCE then return true end
    local at = Gather.ZoneAt(zone, x, y)
    return at == nil or at == zone
end

-- Spawn points that hold one of several kinds (the data's `mix`), by zone, entry and
-- position: { odds = { [entry] = percent }, how, n }. One table per cluster, shared by
-- every kind there, so a route stop can tell two kinds stood on the same spots.
local mixes, mixData = {}, nil

local function spotKey(x, y)
    return math.floor(x * SCALE + 0.5) * 100000 + math.floor(y * SCALE + 0.5)
end

function Gather.Mixes(zone)
    if mixData ~= CP.GatherData then mixes, mixData = {}, CP.GatherData end
    local byEntry = mixes[zone]
    if byEntry then return byEntry end
    byEntry = {}
    local z = CP.GatherData.zones[zone]
    for _, m in ipairs(z and z.mix or {}) do
        for _, c in ipairs(Gather.Decode(m[1])) do
            local spot = { odds = m[2], how = m[3], n = c[3] }
            local key = spotKey(c[1], c[2])
            for entry in pairs(m[2]) do
                byEntry[entry] = byEntry[entry] or {}
                byEntry[entry][key] = spot
            end
        end
    end
    mixes[zone] = byEntry
    return byEntry
end

-- "Tin Vein 80% · Silver Vein 20%": a shared spot's kinds, likeliest first. An even split
-- the data had to guess says so.
function Gather.MixText(spot)
    local list = {}
    for entry, pct in pairs(spot.odds) do
        local n = CP.GatherData.nodes[entry]
        list[#list + 1] = { name = n and n[1] or ("node " .. entry), pct = pct }
    end
    table.sort(list, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        return a.name < b.name
    end)
    local parts = {}
    for i, e in ipairs(list) do parts[i] = ("%s %d%%"):format(e.name, math.floor(e.pct + 0.5)) end
    local text = table.concat(parts, " · ")
    if spot.how == "even" then text = text .. " (odds unknown, split evenly)" end
    return text
end

-- The kinds `entry` shares spawn points with in `zone`: { { text, n } }, most spots first.
function Gather.MixLines(zone, entry)
    local byText = {}
    for _, spot in pairs(Gather.Mixes(zone)[entry] or {}) do
        local text = Gather.MixText(spot)
        byText[text] = (byText[text] or 0) + spot.n
    end
    local out = {}
    for text, n in pairs(byText) do out[#out + 1] = { text = text, n = n } end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.text < b.text
    end)
    return out
end

-- The data's spawns of an entry the game puts in `zone`. The data never changes, so
-- these outlast Gather.ResetClusters and skip the point cache. `tick` (optional) runs
-- after each map lookup, so a background job can yield between them. A spot shared with
-- other kinds counts its spawns by this kind's share, and carries `mix`.
local function dataInside(key, zone, kind, entry, tick)
    local began = Gather.MapEpoch()
    if not dataIn[key] then
        local z = CP.GatherData.zones[zone]
        local packed = z and z[kind] and z[kind][entry]
        local trust = z and z.inst or kind == "nodes" and Gather.OWN_NODES[zone]
        local shared = kind == "nodes" and Gather.Mixes(zone)[entry]
        local kept = {}
        for _, c in ipairs(packed and Gather.Decode(packed) or {}) do
            local spot = shared and shared[spotKey(c[1], c[2])]
            if spot then c[3], c.mix = c[3] * spot.odds[entry] / 100, spot end
            local at = not trust and CP.Waypoint.MapPosZone(zone, c[1], c[2])
            if not at or at == zone then kept[#kept + 1] = c end
            if tick and not trust then tick() end
        end
        -- Answers from swapped map calls (tests only) never land in the new cache.
        if epoch ~= began then return kept end
        dataIn[key] = kept
    end
    return dataIn[key]
end

-- Chat lines for `/proflost border`: where both map lookups put the player's spot and
-- `zone`'s data spawns. Asks the map for every spawn, so it runs on command only.
function Gather.BorderReport(zone, px, py)
    local W = CP.Waypoint
    local function name(id)
        local info = id and C_Map.GetMapInfo(id)
        return info and info.name or (id and tostring(id) or "can't say")
    end
    local lines = {}
    if px and py then
        local a, b = W.MapPosLookups(zone, px, py)
        lines[1] = ("your spot: continent map says %s, best map says %s"):format(name(a), name(b))
    end
    local z = CP.GatherData.zones[zone]
    local total, away = 0, { {}, {} }
    for _, kind in ipairs({ "mobs", "nodes" }) do
        for _, packed in pairs(z and z[kind] or {}) do
            for _, c in ipairs(Gather.Decode(packed)) do
                total = total + c[3]
                local a, b = W.MapPosLookups(zone, c[1], c[2])
                for i, at in ipairs({ a or false, b or false }) do
                    if at ~= zone then away[i][at] = (away[i][at] or 0) + c[3] end
                end
            end
        end
    end
    for i, label in ipairs({ "continent map", "best map" }) do
        local parts, out = {}, 0
        for at, n in pairs(away[i]) do
            out = out + n
            parts[#parts + 1] = ("%s %d"):format(at and name(at) or "can't say", n)
        end
        table.sort(parts)
        lines[#lines + 1] = ("%s: %d of %d spawns elsewhere%s"):format(label, out, total,
            #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
    end
    return lines
end

-- The clusters of a creature ("mobs") or node ("nodes") that the game places inside
-- `zone`. Nodes also get GatherMate2's recorded finds of the same name (already
-- checked by GatherMate.Nodes), which are real Forever spots: where they match a spawn
-- they add to its weight, elsewhere they're new stops. Cached; GatherMate2 changes
-- clear it.
local inZone = {}   -- zone -> kind -> entry -> clusters
local byName = {}   -- zone -> name -> spawns of that herb or ore in the zone
local covered = {}  -- zone -> line -> GatherMate2's node counts there (Gather.NodeFits)

-- Each background job's tick, by its coroutine. A cluster build deep inside another
-- call (the checklist's rows, a farm search) yields through it; outside a job there is none.
local jobTicks = setmetatable({}, { __mode = "k" })

function Gather.JobTick(tick)
    local co = coroutine.running()
    if co then jobTicks[co] = tick end
end

function Gather.RunningTick()
    local co = coroutine.running()
    return co and jobTicks[co] or nil
end

-- The lowest data entry of each node name: GatherMate2's finds of a name join that
-- entry only, so names with several entries (Copper Vein) don't count them twice.
local firstOfName
local function firstEntry(name)
    if not firstOfName then
        firstOfName = {}
        for entry, n in pairs(CP.GatherData.nodes) do
            if not firstOfName[n[1]] or entry < firstOfName[n[1]] then firstOfName[n[1]] = entry end
        end
    end
    return firstOfName[name]
end

-- Zones whose node spawns are GatherLite's own positions on that zone's map, so they are
-- never checked against a neighbour's rectangle (Mount Hyjal's overlap Darkshore's).
Gather.OWN_NODES = { [2482] = true }

-- `tick` (optional, else the running job's) runs after each map lookup the first build makes.
function Gather.Clusters(zone, kind, entry, tick)
    local byKind = inZone[zone]
    local byEntry = byKind and byKind[kind]
    local kept = byEntry and byEntry[entry]
    if kept then return kept end
    tick = tick or Gather.RunningTick()
    local began = resets
    kept = {}
    for i, c in ipairs(dataInside(kind .. entry .. ":" .. zone, zone, kind, entry, tick)) do kept[i] = c end
    local name = kind == "nodes" and CP.GatherData.nodes[entry] and CP.GatherData.nodes[entry][1]
    if name and CP.GatherMate and firstEntry(name) == entry then
        for _, c in ipairs(CP.GatherMate.Nodes(zone)[name] or {}) do kept[#kept + 1] = c end
    end
    -- Beasts the player skinned or saw here (Engine/Finds.lua), and peers' agreed spots.
    local function keepInside(list)
        for _, c in ipairs(list or {}) do
            if Gather.Inside(zone, c[1], c[2]) then kept[#kept + 1] = c end
        end
    end
    if kind == "mobs" and CP.Finds then
        keepInside(CP.Finds.Mobs(zone)[entry])
        keepInside(CP.Finds.Seen(zone)[entry])
    end
    if kind == "mobs" and CP.Peers then keepInside(CP.Peers.Mobs(zone)[entry]) end
    if resets ~= began then return kept end
    byKind = inZone[zone]
    if not byKind then byKind = {}; inZone[zone] = byKind end
    byEntry = byKind[kind]
    if not byEntry then byEntry = {}; byKind[kind] = byEntry end
    byEntry[entry] = kept
    return kept
end

-- Instances (dungeons) are keyed INSTANCE + their map id, since Forever has no game
-- map for them.

Gather.INSTANCE = 100000

function Gather.IsInstance(zone)
    local z = zone and CP.GatherData.zones[zone]
    return z and z.inst ~= nil or false
end

-- The outdoor zone each instance's entrance stands in, by instance map id. An instance
-- with no data of its own lists this zone.
Gather.INSTANCE_ZONES = {
    [30] = 1416, [33] = 1421, [34] = 1453, [36] = 1436, [43] = 1413, [47] = 1413, [48] = 1440,
    [70] = 1418, [90] = 1426, [109] = 1435, [129] = 1413, [189] = 1420, [209] = 1446,
    [229] = 1428, [230] = 1427, [249] = 1445, [289] = 1422, [309] = 1434, [329] = 1423,
    [349] = 1443, [369] = 1453, [389] = 1454, [409] = 1428, [429] = 1444, [469] = 1428,
    [509] = 1451, [531] = 1451, [533] = 1423,
}

-- The last outdoor zone the player stood in this session, for an instance the table
-- doesn't name.
Gather.lastOutdoor = nil

local function hasData(zone) return CP.GatherData.zones[zone] ~= nil end

-- True when the data places creature or node `entry` ("mobs" or "nodes") in `zone`.
-- Reads the zone's `has` list, so a zone not yet decoded stays packed.
local holds = setmetatable({}, { __mode = "k" })   -- zone table -> { mobs = set, nodes = set }
function Gather.Holds(zone, kind, entry)
    local z = CP.GatherData.zones[zone]
    if not z then return false end
    local has = rawget(z, "has")
    if not has then return z[kind] ~= nil and z[kind][entry] ~= nil end
    local sets = holds[z]
    if not sets then
        sets = { mobs = {}, nodes = {} }
        for code, id in has:gmatch("(%a)(%d+)") do
            sets[code == "m" and "mobs" or "nodes"][tonumber(id)] = true
        end
        holds[z] = sets
    end
    return sets[kind] ~= nil and sets[kind][entry] == true
end

-- The first of the game's place names that isn't `zone`'s own name, or nil.
local function otherPlace(zone, ...)
    local info = zone and C_Map.GetMapInfo(zone)
    local own = info and info.name
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if type(name) == "string" and name ~= "" and name ~= own then return name end
    end
    return nil
end

-- The zone the checklist lists and where the player really is: zone, place. Inside an
-- instance with data, its own key. Inside one without, the zone its entrance stands in,
-- and the instance's name. Outdoors, the best map climbed to the first zone with data,
-- else the zone with data under the player's spot, else any zone; the place is the
-- subzone or the real zone's name when it isn't the zone's (Gnomeregan in Dun Morogh).
-- The third value is true only when the game's best map for the player named the zone:
-- outdoors, not read from the spot under overlapping zone rectangles.
function Gather.PlayerSpot()
    local inside, kind = IsInInstance()
    if inside and kind ~= "none" then
        local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
        local key = mapID and Gather.INSTANCE + mapID
        if key and hasData(key) then return key, nil end
        local zone = mapID and Gather.INSTANCE_ZONES[mapID] or Gather.lastOutdoor
        if not (zone and hasData(zone)) then return nil, name end
        return zone, otherPlace(zone, name)
    end
    local zone, bySpot = CP.Waypoint.PlayerZone(hasData)
    if not zone then zone, bySpot = CP.Waypoint.PlayerZone() end
    if not zone then return nil, otherPlace(nil, GetRealZoneText(), GetSubZoneText()) end
    if hasData(zone) then Gather.lastOutdoor = zone end
    if bySpot then return zone, otherPlace(zone, GetRealZoneText(), GetSubZoneText()), false end
    return zone, otherPlace(zone, GetSubZoneText(), GetRealZoneText()), true
end

function Gather.PlayerZone()
    return (Gather.PlayerSpot())
end

function Gather.ResetClusters()
    CP.Waypoint.ForgetMaps()
    resets = resets + 1
    wipe(inZone)
    wipe(byName)
    wipe(covered)
    zoneRows.key, zoneRows.list, zoneRows.zone = nil, nil, nil
    wipe(continentSkins)
    wipe(zoneTargets)
    if CP.GatherGuide then CP.GatherGuide.Reset() end
    if CP.Farm then CP.Farm.Reset() end
end

-- New finds or nodes in `zones` ({ [zone] = true }): those zones' clusters, spawn counts
-- and rows start over, and so do the answers summed over every zone (continent skins, the
-- gathering guides, farm zones). Other zones keep theirs, and the map answers stay.
function Gather.ResetZones(zones)
    resets = resets + 1
    for zone in pairs(zones) do
        inZone[zone], byName[zone], covered[zone] = nil, nil, nil
    end
    if zoneRows.zone and zones[zoneRows.zone] then zoneRows.key, zoneRows.list, zoneRows.zone = nil, nil, nil end
    wipe(continentSkins)
    wipe(zoneTargets)
    if CP.GatherGuide then CP.GatherGuide.Reset() end
    if CP.Farm then CP.Farm.Reset() end
end

-- A zone's size in yards: from the data, else from HereBeDragons (zones the vanilla
-- data lacks, like Forever's new ones). Nil when neither knows it.
function Gather.ZoneSize(zone)
    local z = CP.GatherData.zones[zone]
    if z and z.w then return z.w, z.h end
    local hbd = LibStub("HereBeDragons-2.0", true)
    local w, h = hbd and hbd:GetZoneSize(zone)
    if w and w > 0 then return w, h end
end

-- Node entry by name: the first data entry for each herb, vein or pool name.
local nodeByName
local function nodeEntry(name)
    if not nodeByName then
        nodeByName = {}
        for entry, n in pairs(CP.GatherData.nodes) do
            if not nodeByName[n[1]] or entry < nodeByName[n[1]] then nodeByName[n[1]] = entry end
        end
    end
    return nodeByName[name]
end
Gather.NodeEntry = nodeEntry

-- True when any of the entry's clusters is really in the zone.
function Gather.InZone(kind, entry, zone)
    return #Gather.Clusters(zone, kind, entry) > 0
end

-- Creatures with fewer spawns than this in a zone (rares, named mobs) aren't worth
-- listing: they're rarely up.
Gather.MIN_MOB_SPAWNS = 3

function Gather.Spawns(zone, kind, entry)
    local n = 0
    for _, c in ipairs(Gather.Clusters(zone, kind, entry)) do n = n + c[3] end
    return n
end

-- Herbs or ore with fewer spawns than this in a zone are strays, not worth routing.
-- Counted per name: one herb is often several data entries (Peacebloom's variants).
Gather.MIN_NODE_SPAWNS = 6

function Gather.NameSpawns(zone, name)
    local names = byName[zone]
    local n = names and names[name]
    if n == nil then
        local began = resets
        n = 0
        local z = CP.GatherData.zones[zone]
        for entry in pairs(z and z.nodes or {}) do
            local node = CP.GatherData.nodes[entry]
            if node and node[1] == name then n = n + Gather.Spawns(zone, "nodes", entry) end
        end
        local first = firstEntry(name)
        if first and not (z and z.nodes and z.nodes[first]) then n = n + Gather.Spawns(zone, "nodes", first) end
        if resets == began then
            names = byName[zone]
            if not names then names = {}; byName[zone] = names end
            names[name] = n
        end
    end
    return n
end

-- Zone maps overlap at their borders and the vanilla spawn data can't tell which side
-- a spawn is on, so a neighbour's herbs leak in (Arathi's Khadgar's Whisker along
-- Hillsbrad's east edge, where the game's map counts the ground as Hillsbrad).
-- GatherMate2's finds are real Forever positions: where it has GM_COVERAGE or more
-- nodes of a profession in a zone and none of a name, that name doesn't grow there.
-- Without GatherMate2, or with thin coverage, everything stays.
Gather.GM_COVERAGE = 30

local function gmCount(zone, line)
    local lines = covered[zone]
    local counts = lines and lines[line]
    if counts == nil then
        local began = resets
        local names, total = {}, 0
        local GM = CP.GatherMate
        for name, spots in pairs(GM and GM.Nodes(zone) or {}) do
            local entry = firstEntry(name)
            local n = entry and CP.GatherData.nodes[entry]
            if n and n[4] == line then
                names[name] = #spots
                total = total + #spots
            end
        end
        counts = { total = total, names = names }
        if resets == began then
            lines = covered[zone]
            if not lines then lines = {}; covered[zone] = lines end
            lines[line] = counts
        end
    end
    return counts
end

function Gather.NodeFits(zone, n)
    if not (n and n[4] ~= Gather.FISHING) then return true end
    local gm = gmCount(zone, n[4])
    return gm.total < Gather.GM_COVERAGE or (gm.names[n[1]] or 0) > 0
end

-- In the zone and common enough to farm there.
function Gather.Farmable(kind, entry, zone)
    if kind == "mobs" then return Gather.Spawns(zone, kind, entry) >= Gather.MIN_MOB_SPAWNS end
    local n = CP.GatherData.nodes[entry]
    if not n or n[4] == Gather.FISHING then return Gather.InZone(kind, entry, zone) end
    return Gather.InZone(kind, entry, zone) and Gather.NodeFits(zone, n)
        and Gather.NameSpawns(zone, n[1]) >= Gather.MIN_NODE_SPAWNS
end

-- Items gatherable in `zone` (a uiMapID) at `skills`:
-- { { itemID, prof, best, sources = { { kind, name, skill, chance, avg,
--   minLevel, maxLevel, land, prof } } } }. kind is "mob", "node", "pool" or "water".
-- `prof` is the skill line of the item's best source, so a fish caught here files
-- under Fishing even when a mob also drops it.
-- opts.greyLevel hides creatures at or below it; opts.here(kind, entry, zone) confirms
-- a creature ("mobs") or node ("nodes") is really in the zone (all pass without it).
-- Mob, node and pool sources carry `entry` for Gather.Clusters.
-- opts.cache keeps the list for the same zone, skill ranks and greyLevel until the spawn
-- data changes (Gather.ResetClusters); only callers whose opts.here is Gather.Farmable
-- may share it. Callers may set fields on its rows and re-sort it.
local function skillKey(skills)
    local parts = {}
    for _, id in ipairs(Gather.PROFS) do parts[#parts + 1] = skills[id] or 0 end
    return table.concat(parts, ",")
end

function Gather.ForZone(zone, skills, opts)
    opts = opts or {}
    local D = CP.GatherData
    if not D then return {} end
    local cacheKey = opts.cache and (zone .. ":" .. skillKey(skills) .. ":" .. (opts.greyLevel or 0)) or nil
    if cacheKey and zoneRows.key == cacheKey then return zoneRows.list end
    local began = resets
    local list = Gather.BuildZone(zone, skills, opts)
    if cacheKey and resets == began then zoneRows.key, zoneRows.list, zoneRows.zone = cacheKey, list, zone end
    return list
end

-- ForZone's work, uncached.
function Gather.BuildZone(zone, skills, opts)
    local D = CP.GatherData
    local z = D.zones[zone] or {}
    local byItem, list = {}, {}

    local function add(item, prof, src)
        local row = byItem[item]
        if not row then
            row = { itemID = item, prof = prof, best = -1, sources = {} }
            byItem[item], list[#list + 1] = row, row
        end
        src.prof = prof
        row.sources[#row.sources + 1] = src
        local score = src.chance * (src.land or 100) / 100
        if score > row.best then row.best, row.prof = score, prof end
    end

    local function each(key, fn)
        for _, l in ipairs(D.loot[key] or {}) do fn(l[1], l[2], l[3]) end
    end

    local function here(kind, entry)
        return not opts.here or opts.here(kind, entry, zone)
    end
    local grey = opts.greyLevel or 0

    for entry in pairs(z.mobs or {}) do
        local m = D.mobs[entry]
        local usable = m and m[3] > grey and here("mobs", entry)
        for prof, key in pairs(usable and m[4] or {}) do
            local rank = Gather.Gives(entry, prof) and skills[prof]
            local need = prof == Gather.COOKING and 0 or Gather.CorpseSkill(m[2])
            if rank and rank >= need and prof ~= Gather.SKINNING then
                each(key, function(item, chance, avg)
                    add(item, prof, { kind = "mob", entry = entry, name = m[1], minLevel = m[2], maxLevel = m[3],
                        skill = need, skillMax = prof == Gather.COOKING and 0 or Gather.CorpseSkill(m[3]),
                        chance = chance, avg = avg })
                end)
            end
        end
    end

    -- Skinning: the data's loot, else the player's skins or the level's estimate (SkinLoot).
    local skinning = skills[Gather.SKINNING]
    for entry in pairs(skinning and Gather.SkinMobs(zone) or {}) do
        local loot, how, skins = Gather.SkinLoot(entry)
        local name, lo, hi = Gather.MobInfo(entry)
        local need = lo and Gather.CorpseSkill(lo)
        if loot and need and hi > grey and skinning >= need and Gather.Gives(entry, Gather.SKINNING)
            and here("mobs", entry) then
            for _, l in ipairs(loot) do
                add(l[1], Gather.SKINNING, { kind = "mob", entry = entry, name = name, minLevel = lo, maxLevel = hi,
                    skill = need, skillMax = Gather.CorpseSkill(hi), chance = l[2], avg = l[3],
                    how = how ~= "data" and how or nil, skins = skins })
            end
        end
    end

    local fishing = skills[Gather.FISHING]
    local land = fishing and z.fish and Gather.LandChance(fishing, z.fish.base)

    -- The data's nodes, plus any GatherMate2 has recorded here that the data lacks.
    local nodes = {}
    for entry in pairs(z.nodes or {}) do nodes[entry] = true end
    for name in pairs(CP.GatherMate and CP.GatherMate.Nodes(zone) or {}) do
        local entry = nodeEntry(name)
        if entry then nodes[entry] = true end
    end

    for entry in pairs(nodes) do
        local n = D.nodes[entry]
        local prof, rank = n and n[4], n and skills[n[4]]
        local need = n and math.max(1, n[2] or 1)
        local ok = rank and (prof == Gather.FISHING and (not z.fish or land > 0) or rank >= need)
        if ok and here("nodes", entry) then
            local pool = prof == Gather.FISHING
            each(n[3], function(item, chance, avg)
                add(item, prof, { kind = pool and "pool" or "node", entry = entry, name = n[1],
                    skill = not pool and need or nil, chance = chance, avg = avg,
                    land = pool and land or nil })
            end)
        end
    end

    if land and land > 0 then
        each(z.fish.loot, function(item, chance, avg)
            add(item, Gather.FISHING, { kind = "water", name = "Fishing in open water",
                chance = chance, avg = avg, land = land })
        end)
    end

    for _, row in ipairs(list) do table.sort(row.sources, bySource) end
    return list
end

-- What the player's guides need, summed over professions: two { [itemID] = n } maps,
-- all the way to 300 and up to each profession's current cap.
function Gather.Needs()
    local function sum(saved)
        local out = {}
        for _, needs in pairs(saved or {}) do
            for item, n in pairs(needs) do out[item] = (out[item] or 0) + n end
        end
        return out
    end
    local db = CP.charDB or {}
    return sum(db.gatherNeeds), sum(db.gatherSoon)
end

local function guideKey(guide)
    for key, g in pairs(CP.Guides or {}) do
        if g == guide then return key end
    end
end

-- What the plan from `p.skill` to `target` uses of recipe `r`'s materials and of what
-- they are made from: { [itemID] = count }. A material the player makes (Bolt of Linen
-- Cloth) beyond what the plan's own crafts make and the bags and bank hold counts toward
-- what it's made from, so the cloth for the cloaks' bolts counts as cloth.
function Gather.PlanNeeds(guide, p, target, plan, learned, r)
    local Q, prep = CP.Queue, guide.prep or {}
    local entries = Q.Build(guide, p.skill, p.max, target, plan, learned)
    local use, made = {}, {}
    for _, m in ipairs(Q.Materials(entries)) do use[m.itemID] = m.need end
    for _, e in ipairs(entries) do
        if e.kind == "craft" and e.recipe.makes then
            made[e.recipe.makes] = (made[e.recipe.makes] or 0) + e.crafts * (e.recipe.yield or 1)
        end
    end
    local total = {}
    for id, n in pairs(use) do total[id] = n end
    for id, n in pairs(use) do
        local maker = prep[id] and guide.recipes[prep[id]]
        local extra = maker and n - (made[id] or 0) - (C_Item.GetItemCount(id, true) or 0)
        if extra and extra > 0 then
            local runs = math.ceil(extra / (maker.yield or 1))
            for _, raw in ipairs(maker.reagents) do
                total[raw[1]] = (total[raw[1]] or 0) + raw[2] * runs
            end
        end
    end
    -- Only the step's materials and what they're made from, to keep the saved step small.
    local out = {}
    for _, pair in ipairs(r.reagents) do
        out[pair[1]] = total[pair[1]]
        local maker = prep[pair[1]] and guide.recipes[prep[pair[1]]]
        for _, raw in ipairs(maker and maker.reagents or {}) do out[raw[1]] = total[raw[1]] end
    end
    return out
end

-- The step at `p.skill`: { name, to, skill, max, item, short, learned, crafts, keep }, or nil.
-- `crafts` counts as the step's card does: the crafts to the step's end, or what later
-- steps keep of its product when that is more (`keep`, Guide.Keeps).
-- `item` and `short` name the first of the step's own materials, as its card lists them,
-- that the bags and bank fall short of for the step's crafts, and how many. Vendor goods
-- (Fine Thread, Salt) are bought on the way and count only when the step lacks nothing
-- else; `buy` then holds the good's { price, seller, vendors }. A material the player makes
-- first (Mote of Magic, Cured Light Hide) counts only when what it's made from is short
-- too, or its recipe isn't known; `make` then names that first missing material and how
-- many ({ item, count }). The bags decide; when only the bank makes up the difference,
-- the step is ready and `bank` names the first material to fetch. `needs` holds each of
-- the step's materials needed from `p.skill` to `target`, the current cap, along the
-- whole plan (Queue.Materials).
-- At the cap with a rank to learn, the rank instead: { rank, name, skill, max, short = 0 }.
-- `levelShort` (Guide.LevelShort) when the skill has opened a rank the level can't train.
function Gather.NextStep(guide, p, plan, learned)
    local held = CP.Guide.CapRank(guide, p.skill, p.max)
    if held and plan and #plan > 0 then
        return { rank = held, name = held.name, skill = p.skill, max = p.max, to = held.cap, short = 0, learned = false,
                 levelShort = CP.Guide.LevelShort(held, p.skill, CP.Guide.PlayerLevel()) }
    end
    for i, st in ipairs(plan or {}) do
        if st.spell and st.to > p.skill then
            local r = guide.recipes[st.spell]
            local from = math.max(st.from, p.skill)
            local crafts = CP.Guide.Crafts(r, from, st.to)

            -- A maker step makes at least what later steps keep from it, as its row and card
            -- count. A saved step carries its keep, since LiveStep sees no later steps.
            local keep = st.keep or st.keepCount
            if not keep and plan[i + 1] then
                local k = CP.Guide.Keeps(guide, plan, CP.Plan and CP.Plan.Held(guide) or {})[i]
                keep = k and k.count or 0
            end
            local keepCrafts = CP.Guide.KeepCrafts(r, keep)
            if crafts < math.huge and keepCrafts > crafts then crafts = keepCrafts end
            -- A committed plan's count, as the step's row and card show it (Plan.Commit).
            if st.committed and st.first then crafts = CP.Plan.StepCrafts(st) end
            if st.crafts and st.saved then crafts = st.crafts end
            local items, prep = guide.items or {}, guide.prep or {}
            local function vendor(id) return items[id] ~= nil and items[id][2] == true end

            -- The step's first short material and its shortfall, then the material at the
            -- bottom of its making that is missing (itself when it isn't made) and how many.
            local function firstShort(count)
                local function lacking(id, lack)
                    if vendor(id) then return nil end
                    local maker = prep[id] and guide.recipes[prep[id]]
                    if not maker or (learned and not learned[prep[id]]) then return id, lack end
                    local runs = math.ceil(lack / (maker.yield or 1))
                    for _, pair in ipairs(maker.reagents) do
                        local more = pair[2] * runs - count(pair[1])
                        if more > 0 then
                            local got, n = lacking(pair[1], more)
                            if got then return got, n end
                        end
                    end
                    return nil
                end
                for _, pair in ipairs(r.reagents) do
                    local lack = pair[2] * crafts - count(pair[1])
                    if lack > 0 then
                        local got, n = lacking(pair[1], lack)
                        if got then return pair[1], lack, got, n end
                    end
                end
            end

            -- The step's first vendor good it lacks, and how many.
            local function vendorShort(count)
                for _, pair in ipairs(r.reagents) do
                    local lack = pair[2] * crafts - count(pair[1])
                    if vendor(pair[1]) and lack > 0 then return pair[1], lack end
                end
            end

            local function bags(id) return C_Item.GetItemCount(id) or 0 end
            local function owned(id) return C_Item.GetItemCount(id, true) or 0 end
            local item, short, bank, make, buy = r.reagents[1] and r.reagents[1][1], 0, nil, nil, nil
            if crafts < math.huge then
                local _, _, got, need = firstShort(bags)
                if got then
                    local id, n, raw, rawCount = firstShort(owned)
                    if id then
                        item, short = id, n
                        if raw ~= id then make = { item = raw, count = rawCount } end
                    else
                        bank = { item = got, count = need }
                    end
                else
                    -- Everything else is in the bags: a vendor good it lacks is the one thing to get.
                    local id, n = vendorShort(bags)
                    if id then
                        local still, left = vendorShort(owned)
                        if still then
                            local it = items[still]
                            item, short = still, left
                            buy = { price = it[1], seller = it.seller, vendors = it.vendors }
                        else
                            bank = { item = id, count = n }
                        end
                    end
                end
            end

            local target = guide.steps and CP.Queue.DefaultTarget(guide, p.skill, p.max)
            local needs = {}
            if target and target > p.skill and crafts < math.huge then
                needs = Gather.PlanNeeds(guide, p, target, plan, learned, r)
            end
            return { name = r.name, to = st.to, skill = p.skill, max = p.max, item = item,
                     short = short, bank = bank, make = make, buy = buy, needs = needs, target = target,
                     learned = r.deskill or (learned and learned[st.spell] == true),
                     deskill = r.deskill or nil,
                     spell = st.spell, from = st.from, crafts = crafts, keep = keep or 0,
                     levelShort = CP.Guide.LevelShortFor(guide, p.skill, p.max, CP.Guide.PlayerLevel()) }
        end
    end
    return nil
end

-- What the plan still needs of the step's short material to its target: the plan's
-- need less the bags and bank, never under the step's own shortfall.
local function stillToGet(st)
    local need = st.needs and st.needs[st.item]
    if not (need and st.target) then return nil end
    return math.max(st.short, need - (C_Item.GetItemCount(st.item, true) or 0))
end

-- A step's need as one line: the step's shortfall ("Linen Cloth x6"). A material the
-- player makes first reads "Make <item> xN", a vendor good "Buy <item> xN". Nil when
-- nothing is short. What the plan still needs to the cap is in NeedTip. `nameOf(id)`
-- gives an item's name.
function Gather.NeedText(st, nameOf)
    if not (st and st.item and (st.short or 0) > 0) then return nil end
    local verb = st.buy and "Buy " or st.make and "Make " or ""
    return ("%s%s x%d"):format(verb, nameOf(st.item), st.short)
end

-- What a step short of nothing says: "Ready to craft <recipe>", or "Ready to cast
-- <enchant>" for a recipe with no product. Plain "Ready" when the recipe is unknown.
-- With a tool the bags lack, its text instead ("Needs Blacksmith Hammer") and true.
function Gather.ReadyText(st, guide)
    local r = st and st.spell and guide and guide.recipes and guide.recipes[st.spell]
    if not (r and r.name) then return "Ready" end
    local tool = CP.Guide.MissingTool(guide, r)
    if tool then return tool.text, true end
    return (r.makes and "Ready to craft %s" or "Ready to cast %s"):format(r.name)
end

-- Where to buy a vendor good the step lacks: "Enchanting Supplies vendors, 10c each", and
-- the nearest such vendor on the player's continent when `guide` knows one.
function Gather.BuyTip(buy, guide)
    local out = {}
    local each = CP.Pricing.Format(buy.price or 0) .. " each"
    out[1] = buy.seller and ("Sold by %s vendors, %s"):format(buy.seller, each) or ("Sold by vendors, %s"):format(each)
    local near = CP.Guide.NearestSeller(guide, buy.vendors)
    if near then out[2] = ("Nearest: %s, %s"):format(near.name, CP.Waypoint.Describe(near)) end
    return out
end

-- The tooltip lines that spell out a step's need line. `guide` names the nearest vendor
-- of a vendor good.
function Gather.NeedTip(st, nameOf, guide)
    if not (st and st.item and (st.short or 0) > 0) then return {} end
    local out = { ("%d %s short for this step"):format(st.short, nameOf(st.item)) }
    local left = stillToGet(st)
    if left then out[#out + 1] = ("%d more by skill %d"):format(left, st.target) end
    if st.make then
        out[#out + 1] = ("Made from %s: %d short"):format(nameOf(st.make.item), st.make.count)
    end
    if st.buy then
        for _, line in ipairs(Gather.BuyTip(st.buy, guide)) do out[#out + 1] = line end
    end
    return out
end

-- A saved step checked against the bags now: what was short may be in hand, or spent.
function Gather.LiveStep(key, st)
    local guide = CP.Guides and CP.Guides[key]
    if guide and st and st.rank then
        -- A saved rank: its level warning follows the character's level now.
        local live = {}
        for k, v in pairs(st) do live[k] = v end
        live.levelShort = CP.Guide.LevelShort(st.rank, st.skill, CP.Guide.PlayerLevel())
        return live
    end
    if not (guide and st and st.spell and guide.recipes[st.spell]) then return st end
    local learned = {}
    for _, id in ipairs(CP.charDB.learned and CP.charDB.learned[key] or {}) do learned[id] = true end
    -- The committed count, less the crafts made since it was saved (Plan.Commit).
    local crafts = st.crafts
    local c = CP.Plan and CP.Plan.Committed(key)
    local f = c and c.steps and c.steps[c.current or 1]
    if f and f[3] == st.spell and f[2] == st.to then crafts = math.max(1, (f[9] or f[5]) - (c.made or 0)) end
    local live = Gather.NextStep(guide, { skill = st.skill, max = st.max },
        { { spell = st.spell, from = st.from or st.skill, to = st.to, keep = st.keep, crafts = crafts, saved = true } },
        learned)
    if not live then return st end
    -- The plan's needs to the cap were read from the whole plan when it was saved.
    if st.needs then live.needs = st.needs end
    return live
end

-- The materials `live`'s plan needs from its skill to `target`: { [item] = count }, or nil
-- for none. `live` is from Plan.Current or Plan.Shut.
function Gather.NeedsTo(live, target)
    local guide, p, Q = live.guide, live.prof, CP.Queue
    local out = {}
    if target and target > p.skill then
        local entries = Q.Build(guide, p.skill, p.max, target, live.plan, live.learned)
        for _, m in ipairs(Q.Materials(entries)) do out[m.itemID] = m.need end
    end
    return next(out) and out or nil
end

-- Save the materials the profession's guide needs to 300 and to its current cap, so the
-- checklist has them with the profession window closed. `live` is from Plan.Current.
-- The gathering reach (Plan.ReachKey) each guide's saved needs were made under.
local needsReach = {}

function Gather.SaveNeeds(live)
    local guide, p = live and live.guide, live and live.prof
    local key = guide and guideKey(guide)
    if not key or not live.plan then return end
    needsReach[key] = CP.Plan.ReachKey(guide)
    local Q = CP.Queue
    local function needsTo(target) return Gather.NeedsTo(live, target) end
    CP.charDB.gatherNeeds = CP.charDB.gatherNeeds or {}
    CP.charDB.gatherSoon = CP.charDB.gatherSoon or {}
    CP.charDB.gatherNeeds[key] = needsTo(Q.End(guide))
    -- The professions whose couplings shaped these needs (Plan's `shapedBy`): a guide that
    -- leans on them (Enchanting's disenchant credit) names them too.
    CP.charDB.needsShapedBy = CP.charDB.needsShapedBy or {}
    CP.charDB.needsShapedBy[key] = live.shapedBy
    CP.charDB.nextStep = CP.charDB.nextStep or {}
    CP.charDB.nextStep[key] = Gather.NextStep(guide, p, live.plan, live.learned)
    if live.recipes then CP.charDB.lastProf = key end
    if CP.Launcher then CP.Launcher.Update() end
    CP.charDB.gatherSoon[key] = needsTo(Q.DefaultTarget(guide, p.skill, p.max))
    -- A list read before its data arrived would save nothing known.
    if live.recipes and CP.Professions.Settled(p) then CP.Plan.SaveKnown(key, live.learned or {}, live.dead) end
    CP:Emit("ProfLost_NEEDS")
end

-- The guide ids in the order they are solved: Enchanting first, since the others' disenchant
-- credit reads its plan, then the rest by id.
function Gather.SolveOrder()
    local ENCHANTING = CP.Shared.ENCHANTING
    local ids = {}
    for key in pairs(CP.Guides or {}) do
        if key ~= ENCHANTING then ids[#ids + 1] = key end
    end
    table.sort(ids)
    if CP.Guides and CP.Guides[ENCHANTING] then table.insert(ids, 1, ENCHANTING) end
    return ids
end

-- Drops what a profession the player no longer has left behind: its saved plan (Enchanting's
-- disenchant credit reads it), next step and last-opened mark.
function Gather.Forget(key)
    local db = CP.charDB
    local had = (db.lastPlan and db.lastPlan[key]) or (db.nextStep and db.nextStep[key]) or db.lastProf == key
    if not had then return end
    if db.lastPlan then db.lastPlan[key] = nil end
    if db.nextStep then db.nextStep[key] = nil end
    if db.lastProf == key then db.lastProf = nil end
    if CP.Launcher then CP.Launcher.Update() end
    CP:Emit("ProfLost_NEEDS")
end

-- Needs for every guided profession the player has, from the skill list, so the
-- checklist knows them without each profession window being opened. While a profession
-- window is open, Plan.Current keeps that one exact, and only the guides whose gathering
-- reach moved since their needs were saved (a gathering skill-up, a level) are solved again.
-- The plans are Plan.Shut's, so a profession the window already solved costs no second solve.
function Gather.UpdateAllNeeds()
    if not (CP.Professions.preview or (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID)) then return end
    local open = CP.Window and CP.Window.OpenID()
    for _, key in ipairs(Gather.SolveOrder()) do
        local skip = open and (key == open or needsReach[key] == CP.Plan.ReachKey(CP.Guides[key]))
        local live = not skip and rankOf(CP.Professions.SkillLine(key)) and CP.Plan.Shut(key)
        if live then
            -- Without its recipe list, so SaveNeeds neither marks it the last profession
            -- opened nor rewrites its known recipes.
            Gather.SaveNeeds({ guide = live.guide, prof = live.prof, plan = live.plan, learned = live.learned,
                               shapedBy = live.shapedBy })
        elseif not skip then
            if CP.charDB.gatherNeeds and CP.charDB.gatherNeeds[key] then
                CP.charDB.gatherNeeds[key] = nil   -- profession dropped
                if CP.charDB.needsShapedBy then CP.charDB.needsShapedBy[key] = nil end
                CP:Emit("ProfLost_NEEDS")
            end
            if CP.charDB.gatherSoon then CP.charDB.gatherSoon[key] = nil end
            if not rankOf(CP.Professions.SkillLine(key)) then Gather.Forget(key) end
        end
    end
end

-- What routes gather, chosen from the route button's menu: CP.db.routeMode is "farm"
-- (every ticked node or skinning material the player can gather, grey ones too) or nil
-- for levelling (what gives skill or the guides need).
function Gather.RouteFarming() return CP.db ~= nil and CP.db.routeMode == "farm" end

-- The Farm menu's ticks, saved account-wide and kept across mode switches: CP.db.routeSkip
-- = { [node name] = true } and CP.db.skinSkip = { [itemID] = true } are what the player
-- unticked. The Farm menu reads them in any mode.
function Gather.NodeUnticked(name)
    return name ~= nil and CP.db ~= nil and CP.db.routeSkip ~= nil and CP.db.routeSkip[name] == true
end

function Gather.SkinUnticked(item)
    return item ~= nil and CP.db ~= nil and CP.db.skinSkip ~= nil and CP.db.skinSkip[item] == true
end

-- What the route, the panel and every other reader skip: an unticked node or leather, in
-- Farm mode only. Follow the guide always shows what the guides need, so it skips nothing.
function Gather.RouteSkipped(name)
    return Gather.RouteFarming() and Gather.NodeUnticked(name)
end

function Gather.SkinSkipped(item)
    return Gather.RouteFarming() and Gather.SkinUnticked(item)
end

-- Ticks every herb, ore and skinning material again. The leveling or farming choice stays.
function Gather.RouteReset()
    if CP.db then CP.db.routeSkip, CP.db.skinSkip = nil, nil end
end

-- Which reset label fits the gathering professions the player has: "herb", "ore",
-- "leather", "both" (herb and ore), "herb_leather", "ore_leather" or "all"; nil for none.
-- `skills` is Gather.Skills() when the caller has it.
function Gather.ResetKind(skills)
    skills = skills or Gather.Skills()
    local herb, ore = skills[Gather.HERBALISM] ~= nil, skills[Gather.MINING] ~= nil
    local leather = skills[Gather.SKINNING] ~= nil
    if herb and ore then return leather and "all" or "both" end
    if leather then return (herb and "herb_leather") or (ore and "ore_leather") or "leather" end
    return (herb and "herb") or (ore and "ore") or nil
end

-- The filter as a string, for route cache keys. Follow the guide reads no ticks, so its
-- signature holds none.
function Gather.RouteSignature()
    local names, items = {}, {}
    local farming = Gather.RouteFarming()
    for name in pairs(farming and CP.db.routeSkip or {}) do names[#names + 1] = name end
    for item in pairs(farming and CP.db.skinSkip or {}) do items[#items + 1] = item end
    table.sort(names)
    table.sort(items)
    return (CP.db and CP.db.routeMode or "level") .. "|" .. table.concat(names, ",")
        .. "|" .. table.concat(items, ",")
end

-- Skinning materials ---------------------------------------------------------------

-- A creature counts for a skinning material only at this chance per skin or better, so
-- beasts that mostly yield another leather don't fill a spot.
Gather.SKIN_MIN_CHANCE = 0.35

-- A minor skinning material (hides, scales) is one whose typical chance, the median over
-- every creature in the data that yields it, is under SKIN_MIN_CHANCE. A creature counts
-- for it at this share of that typical chance or better.
Gather.SKIN_MIN_SHARE = 0.5

-- Each skinning material's typical chance per skin, from the data's farm index. Built once
-- per data table.
local skinTypical, skinTypicalData

local function typicalSkin(item)
    local D = CP.GatherData
    if skinTypicalData ~= D then
        skinTypical, skinTypicalData = {}, D
        local farm, lists = D.Index("farm") or {}, {}
        for i = 1, #farm, 5 do
            if farm[i + 2] == Gather.SKINNING then
                local list = lists[farm[i]] or {}
                lists[farm[i]] = list
                list[#list + 1] = farm[i + 3]
            end
        end
        for id, list in pairs(lists) do
            table.sort(list)
            local n = #list
            skinTypical[id] = n % 2 == 1 and list[(n + 1) / 2] or (list[n / 2] + list[n / 2 + 1]) / 2
        end
    end
    return skinTypical[item]
end

-- The lowest chance, in percent, at which a creature counts as a skinning source of `item`:
-- SKIN_MIN_CHANCE for a leather, less for a minor material. A material the data lacks
-- takes SKIN_MIN_CHANCE.
function Gather.SkinFloor(item)
    local min = Gather.SKIN_MIN_CHANCE * 100
    local typical = typicalSkin(item)
    if not typical or typical >= min then return min end
    return typical * Gather.SKIN_MIN_SHARE
end

-- Other creature loot (meat, cloth, ...) forms a grind spot only at this chance per kill
-- or better. Fish never do; they come from Fishing.
Gather.LOOT_MIN_CHANCE = 0.25

-- Whether creature source `src` of item `itemID` may form a grind spot. Skinning has its
-- own threshold (SKIN_MIN_CHANCE, applied in skinSources). Other sources pass.
function Gather.GrindSource(itemID, src)
    if src.kind ~= "mob" or src.prof == Gather.SKINNING then return true end
    if CP.Pricing and CP.Pricing.IsFish(itemID) then return false end
    return (src.chance or 0) >= Gather.LOOT_MIN_CHANCE * 100
end

-- Skinning materials that only come from critters and starter beasts, never listed or
-- farmed. The data carries no creature type, so the list names them.
Gather.SKIN_EXCLUDE = {
    [2934] = true,   -- Ruined Leather Scraps
}

-- Farming spots leave out creatures more than this many levels above the player.
Gather.FARM_SAFE_LEVELS = 3

-- Skinning for creatures the data has no skinning loot for --------------------------

-- The loot key of a skinnable creature only ForeverDB knows (Data/Gather.lua).
Gather.UNKNOWN_SKIN = "x393"

-- A creature's own skins replace its estimate once the player has looted this many.
Gather.RECORDED_MIN_SKINS = 10

-- Classic creatures this many levels either side of a level share its estimate.
Gather.ESTIMATE_LEVELS = 1

-- The game's creature types classic skins, for beasts the data lacks (enUS names; a beast
-- with a family counts in any language).
Gather.SKIN_TYPES = { Beast = true, Dragonkin = true }

local estimates, estimateData = {}, nil
local bandKeys              -- { [level] = { skinning loot key, ... } }, one per skinnable creature
local bandMobs = {}         -- { [level] = { { [item] = chance } } }, filled per level on first use

local function median(list)
    table.sort(list)
    local n = #list
    if n % 2 == 1 then return list[(n + 1) / 2] end
    return (list[n / 2] + list[n / 2 + 1]) / 2
end

-- The skinning table a classic creature of `level` typically has: { { item, chance, 1 } },
-- each item's median chance over the classic creatures within ESTIMATE_LEVELS of it,
-- likeliest first. The nearest levels with data stand in for a level with none.
function Gather.EstimatedSkin(level)
    local D = CP.GatherData
    if estimateData ~= D then estimates, estimateData, bandKeys, bandMobs = {}, D, nil, {} end
    level = math.floor(level)
    if estimates[level] then return estimates[level] end

    -- The data's skins index names each creature's levels and key, so only the
    -- loot of the levels looked at decodes.
    if not bandKeys then
        bandKeys = {}
        local skins = D.Index("skins")
        for i = 1, #skins, 5 do
            local mid = math.floor((skins[i + 2] + skins[i + 3]) / 2)
            bandKeys[mid] = bandKeys[mid] or {}
            table.insert(bandKeys[mid], skins[i + 4])
        end
    end
    local group = {}
    for reach = Gather.ESTIMATE_LEVELS, 60 do
        for l = level - reach, level + reach do
            if not bandMobs[l] then
                local list = {}
                for _, key in ipairs(bandKeys[l] or {}) do
                    local loot = D.loot[key]
                    if loot and #loot > 0 then
                        local chances = {}
                        for _, row in ipairs(loot) do chances[row[1]] = row[2] end
                        list[#list + 1] = chances
                    end
                end
                bandMobs[l] = list
            end
            for _, c in ipairs(bandMobs[l]) do group[#group + 1] = c end
        end
        if #group > 0 then break end
    end
    local items = {}
    for _, c in ipairs(group) do
        for item in pairs(c) do items[item] = true end
    end
    local out = {}
    for item in pairs(items) do
        local list = {}
        for i, c in ipairs(group) do list[i] = c[item] or 0 end
        local chance = median(list)
        if chance > 0 then out[#out + 1] = { item, math.floor(chance * 10 + 0.5) / 10, 1 } end
    end
    table.sort(out, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    estimates[level] = out
    return out
end

-- Name and levels of creature `entry`: the data's, else what the player saw of it
-- (Engine/Finds.lua). Nil when neither knows it.
function Gather.MobInfo(entry)
    local m = CP.GatherData.mobs[entry]
    if m then return m[1], m[2], m[3] end
    local seen = CP.Finds and CP.Finds.Creature(entry)
    if seen and seen.lo then return seen.name or ("creature " .. entry), seen.lo, seen.hi end
end

local function recordedLoot(rec)
    local out = {}
    for item, seen in pairs(rec.items) do out[#out + 1] = { item, math.min(100, seen / rec.n * 100), 1 } end
    table.sort(out, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    return out
end

-- Creature `entry`'s skinning loot: { { item, chance, avg } }, how ("data", "recorded" or
-- "estimated") and, when recorded, the skins behind it. The data's loot wins. A creature
-- the data knows only as skinnable, or a beast only the player has seen, gets its level's
-- estimate (`level`, else its middle level) until the player has skinned it
-- RECORDED_MIN_SKINS times. A creature classic never skins takes the player's skins as
-- they are. Nil for anything else.
function Gather.SkinLoot(entry, level)
    local D = CP.GatherData
    local m = D.mobs[entry]
    local key = m and m[4] and m[4][Gather.SKINNING]
    local loot = key and D.loot[key]
    if loot and #loot > 0 then return loot, "data" end
    local estimate = key == Gather.UNKNOWN_SKIN or (not m and CP.Finds ~= nil and CP.Finds.Creature(entry) ~= nil)
    local rec = CP.Finds and CP.Finds.Loot(entry, "skin")
    if rec and rec.n >= (estimate and Gather.RECORDED_MIN_SKINS or 1) then
        return recordedLoot(rec), "recorded", rec.n
    end
    if not estimate then return nil end
    if not level then
        local _, lo, hi = Gather.MobInfo(entry)
        if not lo then return nil end
        level = (lo + hi) / 2
    end
    return Gather.EstimatedSkin(level), "estimated"
end

-- Every creature that may be skinned in `zone`: the data's, and those the data has no
-- skinning loot for that the player skinned or saw there. { [entry] = true }.
local function skinMobs(zone)
    local z = CP.GatherData.zones[zone]
    local out = {}
    for entry in pairs(z and z.mobs or {}) do out[entry] = true end
    if CP.Finds then
        for _, ids in ipairs({ CP.Finds.MobIDs(zone, "m"), CP.Finds.MobIDs(zone, "v") }) do
            for entry in pairs(ids) do
                if not out[entry] then
                    local _, how = Gather.SkinLoot(entry)
                    if how and how ~= "data" then out[entry] = true end
                end
            end
        end
    end
    return out
end
Gather.SkinMobs = skinMobs

-- Skinning sources in `zone` for a skinning `rank`: { [itemID] = { source } }, each source
-- a creature common enough to farm that yields the item at its SkinFloor or better.
-- SKIN_EXCLUDE items have none. A source not from the data carries `how` and `skins`.
local function skinSources(zone, rank)
    local out = {}
    for entry in pairs(skinMobs(zone)) do
        local loot, how, skins = Gather.SkinLoot(entry)
        local name, lo, hi = Gather.MobInfo(entry)
        local need = lo and Gather.CorpseSkill(lo)
        if loot and need and rank >= need and Gather.Gives(entry, Gather.SKINNING) and Gather.Farmable("mobs", entry, zone) then
            for _, l in ipairs(loot) do
                if l[2] > 0 and l[2] >= Gather.SkinFloor(l[1]) and not Gather.SKIN_EXCLUDE[l[1]] then
                    out[l[1]] = out[l[1]] or {}
                    table.insert(out[l[1]], { kind = "mob", entry = entry, name = name, minLevel = lo,
                        maxLevel = hi, skill = need, skillMax = Gather.CorpseSkill(hi), chance = l[2], avg = l[3],
                        prof = Gather.SKINNING, how = how ~= "data" and how or nil, skins = skins })
                end
            end
        end
    end
    for _, list in pairs(out) do table.sort(list, bySource) end
    return out
end

-- The skinning materials creatures in `zone` yield to the player's Skinning, for the
-- route menu: { { item, skill, need } }, `skill` the lowest skill that skins one and `need`
-- how many the guides still want. Lowest skill first. Empty without Skinning.
function Gather.SkinMaterials(zone, skills)
    local rank = (skills or Gather.Skills())[Gather.SKINNING]
    if not (rank and zone) then return {} end
    local needs = Gather.Needs()
    local out = {}
    for item, list in pairs(skinSources(zone, rank)) do
        local skill = math.huge
        for _, src in ipairs(list) do skill = math.min(skill, src.skill) end
        out[#out + 1] = { item = item, skill = skill, need = needs[item] }
    end
    table.sort(out, function(a, b)
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.item < b.item
    end)
    return out
end

-- A zone's farm score for a material falls off with how far its creatures sit below the
-- player: a zone whose top level is this many levels under the player scores half.
Gather.ZONE_LEVEL_FALLOFF = 10

-- Every skinning material the player's Skinning gets from creatures in `zones` (one
-- continent's), for the Farm filter: { { item, skill, need, zones = { zone... } } }, lowest
-- skill first. `zones` holds the best places for it near `level`, best first: creatures
-- at most FARM_SAFE_LEVELS above `level`, scored by chance x spawns and ZONE_LEVEL_FALLOFF;
-- the other faction's home zones never. Kept until the spawn data changes.
function Gather.ContinentSkins(zones, skills, level, side)
    local rank = (skills or Gather.Skills())[Gather.SKINNING]
    if not rank then return {} end
    local key = table.concat(zones, ",") .. "|" .. rank .. "|" .. level .. "|" .. tostring(side)
        .. "|" .. Gather.MapEpoch()
    local list = continentSkins[key]
    if not list then
        local byItem = {}
        for _, zone in ipairs(zones) do
            for item, sources in pairs(skinSources(zone, rank)) do
                local e = byItem[item]
                if not e then
                    e = { item = item, skill = math.huge, scores = {} }
                    byItem[item] = e
                end
                local score, top = 0, 0
                for _, src in ipairs(sources) do
                    e.skill = math.min(e.skill, src.skill)
                    if src.minLevel <= level + Gather.FARM_SAFE_LEVELS then
                        score = score + src.chance / 100 * Gather.Spawns(zone, "mobs", src.entry)
                        top = math.max(top, src.maxLevel)
                    end
                end
                if score > 0 and not Gather.EnemyHome(zone, side) then
                    local below = math.max(0, level - top)
                    e.scores[#e.scores + 1] = { zone = zone, score = score / (1 + below / Gather.ZONE_LEVEL_FALLOFF) }
                end
            end
        end
        list = {}
        for _, e in pairs(byItem) do
            table.sort(e.scores, function(a, b)
                if a.score ~= b.score then return a.score > b.score end
                return a.zone < b.zone
            end)
            local best = {}
            for i, s in ipairs(e.scores) do best[i] = s.zone end
            list[#list + 1] = { item = e.item, skill = e.skill, zones = best }
        end
        table.sort(list, function(a, b)
            if a.skill ~= b.skill then return a.skill < b.skill end
            return a.item < b.item
        end)
        continentSkins[key] = list
    end
    local needs = Gather.Needs()
    local out = {}
    for i, e in ipairs(list) do
        out[i] = { item = e.item, skill = e.skill, zones = e.zones, need = needs[e.item] }
    end
    return out
end

-- Route rows for grind spots: one per ticked skinning material, its sources the creatures
-- that yield it at its SkinFloor or better. Levelling takes the materials the
-- checklist `items` still need; farming every ticked material, without creatures more
-- than FARM_SAFE_LEVELS above the player, and reads no guide need.
function Gather.SkinRows(zone, skills, items)
    local rank = skills[Gather.SKINNING]
    if not rank then return {} end
    local farming = Gather.RouteFarming()
    local level = Gather.PlayerLevel()
    local wanted = {}
    for _, r in ipairs(not farming and items or {}) do
        if r.need and not r.done then wanted[r.itemID] = r end
    end
    local out = {}
    for item, list in pairs(skinSources(zone, rank)) do
        local row = wanted[item]
        if not Gather.SkinSkipped(item) and (farming or row) then
            local kept = {}
            for _, src in ipairs(list) do
                if not farming or src.minLevel <= level + Gather.FARM_SAFE_LEVELS then kept[#kept + 1] = src end
            end
            if #kept > 0 then
                out[#out + 1] = { itemID = item, prof = Gather.SKINNING, need = row and row.need or 1,
                    soon = row and row.soon, have = row and row.have or 0, name = row and row.name, sources = kept }
            end
        end
    end
    table.sort(out, function(a, b) return a.itemID < b.itemID end)
    return out
end

-- Route rows for Farm's Cooking grind spots: every Cooking item `zone`'s creatures drop,
-- weighed as a sellable and not as a guide need, from creatures no more than
-- FARM_SAFE_LEVELS above the player. Copies, so the zone's cached rows stay whole.
function Gather.CookRows(zone, skills, opts)
    local out = {}
    if not (zone and skills[Gather.COOKING]) then return out end
    local level = Gather.PlayerLevel()
    for _, r in ipairs(Gather.ForZone(zone, skills, opts)) do
        if r.prof == Gather.COOKING then
            local kept = {}
            for _, src in ipairs(r.sources) do
                if src.kind == "mob" and (src.minLevel or 0) <= level + Gather.FARM_SAFE_LEVELS then
                    kept[#kept + 1] = src
                end
            end
            if #kept > 0 then
                out[#out + 1] = setmetatable({ sources = kept, need = 1, soon = false, done = false, later = false },
                    { __index = r })
            end
        end
    end
    return out
end

local function itemName(id)
    local name = CP.ItemName and CP.ItemName(id)
    return name and name ~= "" and name or ("item " .. id)
end

-- Why SkinRows builds no grind spot in `zone`, as one line for /proflost zones. It walks
-- SkinRows' filters in order (border, skill, chance and ticks, level or guide needs) and
-- names the first that leaves nothing. Nil when SkinRows has rows.
function Gather.SkinReason(zone, skills, items)
    local rank = skills[Gather.SKINNING]
    if not rank then return "no Skinning" end
    if #Gather.SkinRows(zone, skills, items) > 0 then return nil end
    local data, inside, skinnable, lowest = 0, 0, 0, nil
    for entry in pairs(skinMobs(zone)) do
        local loot = Gather.SkinLoot(entry)
        local _, lo = Gather.MobInfo(entry)
        if loot and lo and Gather.Gives(entry, Gather.SKINNING) then
            data = data + 1
            if Gather.Farmable("mobs", entry, zone) then
                inside = inside + 1
                local need = Gather.CorpseSkill(lo)
                if rank >= need then
                    skinnable = skinnable + 1
                else
                    lowest = math.min(lowest or need, need)
                end
            end
        end
    end
    if data == 0 then return "no skinnable beasts in the data" end
    if inside == 0 then return ("%d skinnable beasts in the data, none inside the zone's border"):format(data) end
    if skinnable == 0 then
        return ("%d skinnable beasts, all need Skinning %d or more (yours %d)"):format(inside, lowest, rank)
    end
    local ticked, unticked = {}, {}
    for item, list in pairs(skinSources(zone, rank)) do
        if Gather.SkinSkipped(item) then unticked[#unticked + 1] = item else ticked[item] = list end
    end
    if not next(ticked) then
        if #unticked > 0 then
            table.sort(unticked)
            local names = {}
            for i, item in ipairs(unticked) do names[i] = itemName(item) end
            return ("%d skinnable beasts; every material here is unticked (%s)"):format(skinnable,
                table.concat(names, ", "))
        end
        return ("%d skinnable beasts; none yields a material worth a grind spot"):format(skinnable)
    end
    if Gather.RouteFarming() then
        local level, low, n = Gather.PlayerLevel(), math.huge, 0
        for _, list in pairs(ticked) do
            for _, src in ipairs(list) do
                n = n + 1
                low = math.min(low, src.minLevel)
            end
        end
        return ("%d sources of ticked leathers, all above level %d (lowest %d)"):format(n,
            level + Gather.FARM_SAFE_LEVELS, low)
    end
    local here = {}
    for item in pairs(ticked) do here[#here + 1] = item end
    table.sort(here)
    for i, item in ipairs(here) do here[i] = itemName(item) end
    return "follow the guide: the guides need none of " .. table.concat(here, ", ")
end

-- The herbs or ore of a profession that spawn in `zone` (the data's spawns and
-- GatherMate2's finds), once each, by the skill they need: { { name, skill, item, need } },
-- `item` what they mostly yield and `need` how many of it the player's guides still want.
function Gather.RouteNodes(line, zone)
    local D = CP.GatherData
    local z = D.zones[zone]
    -- Spawns per name inside the zone's border, the data's and GatherMate2's together.
    local here = {}
    for _, n in pairs(D.nodes) do
        if n[4] == line and here[n[1]] == nil then
            here[n[1]] = Gather.NodeFits(zone, n) and Gather.NameSpawns(zone, n[1]) >= Gather.MIN_NODE_SPAWNS
        end
    end
    local byName = {}
    for _, n in pairs(D.nodes) do
        if n[4] == line and n[2] and here[n[1]] == true and (not byName[n[1]] or n[2] < byName[n[1]].skill) then
            local loot = D.loot[n[3]]
            byName[n[1]] = { skill = n[2], item = loot and loot[1] and loot[1][1] }
        end
    end
    local needs = Gather.Needs()
    local out = {}
    for name, info in pairs(byName) do
        out[#out + 1] = { name = name, skill = info.skill, item = info.item, need = info.item and needs[info.item] or nil }
    end
    table.sort(out, function(a, b)
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.name < b.name
    end)
    return out
end

-- What `zone` holds for gathering profession `line` (Herbalism, Mining or Skinning), at any
-- rank: { { name, req, reqHi, spawns, entry?, kind, minLevel?, maxLevel? } }, lowest `req`
-- first. Herbs and ore are RouteNodes' names; Skinning's are the creatures common enough to
-- farm, `req` the skill the lowest of them needs and `reqHi` the highest. Kept until the
-- spawn data changes.
function Gather.ZoneTargets(zone, line)
    local key = zone .. ":" .. line .. ":" .. resets
    if zoneTargets[key] then return zoneTargets[key] end
    local out = {}
    if line == Gather.SKINNING then
        local byName = {}
        for entry in pairs(zone and skinMobs(zone) or {}) do
            local loot = Gather.SkinLoot(entry)
            local name, lo, hi = Gather.MobInfo(entry)
            if loot and lo and Gather.Gives(entry, Gather.SKINNING) and Gather.Farmable("mobs", entry, zone) then
                local t = byName[name]
                if not t then
                    t = { kind = "mob", name = name, entry = entry, minLevel = lo, maxLevel = hi, spawns = 0 }
                    byName[name], out[#out + 1] = t, t
                end
                t.minLevel, t.maxLevel = math.min(t.minLevel, lo), math.max(t.maxLevel, hi)
                t.req, t.reqHi = Gather.CorpseSkill(t.minLevel), Gather.CorpseSkill(t.maxLevel)
                t.spawns = t.spawns + Gather.Spawns(zone, "mobs", entry)
            end
        end
    elseif line == Gather.HERBALISM or line == Gather.MINING then
        for _, n in ipairs(zone and Gather.RouteNodes(line, zone) or {}) do
            out[#out + 1] = { kind = "node", name = n.name, req = n.skill, reqHi = n.skill, item = n.item,
                              entry = nodeEntry(n.name), spawns = Gather.NameSpawns(zone, n.name) }
        end
    end
    table.sort(out, function(a, b)
        if a.req ~= b.req then return a.req < b.req end
        return a.name < b.name
    end)
    zoneTargets[key] = out
    return out
end

-- The skill range `zone`'s targets for `line` span, lowest need to highest (at most 300):
-- lo, hi. Nil when the zone holds none.
function Gather.ZoneRange(zone, line)
    local lo, hi
    for _, t in ipairs(Gather.ZoneTargets(zone, line)) do
        lo = math.min(lo or t.req, t.req)
        hi = math.max(hi or t.reqHi, t.reqHi)
    end
    if not lo then return nil end
    return math.min(lo, 300), math.min(hi, 300)
end

-- The skill a target gives skill-ups from at `rank`: its highest need the rank reaches, or
-- nil when the rank reaches none of it.
function Gather.TargetReq(t, rank)
    if rank < t.req then return nil end
    return math.min(t.reqHi, math.max(t.req, rank))
end

-- Route rows for the herbs and ore in `zone`, for the player's Herbalism and Mining:
-- { itemID = -node entry, need = 1, sources = { node } }, each source with `skill` (what
-- it needs) and `item` (what it mostly yields). By default the orange and yellow nodes
-- below 300, which steer a levelling loop; farming, every node the player can gather.
-- `wide` adds the green ones when levelling. A node above the player's skill never comes
-- in, nor does a skipped name.
function Gather.SkillRows(zone, skills, wide)
    local out, D = {}, CP.GatherData
    local zd = D.zones[zone]

    -- The data's nodes, plus those GatherMate2, finds and peers hold here that it lacks.
    local entries = {}
    for entry in pairs(zd and zd.nodes or {}) do entries[entry] = true end
    for name in pairs(CP.GatherMate and CP.GatherMate.Nodes(zone) or {}) do
        local entry = nodeEntry(name)
        if entry then entries[entry] = true end
    end
    for entry in pairs(entries) do
        local n = D.nodes[entry]
        local rank = n and n[2] and skills[n[4]]
        local useful
        if rank and rank >= n[2] then
            useful = Gather.RouteFarming() or wide and rank < n[2] + 100 or rank < 300 and rank < n[2] + 50
        end
        if useful and not Gather.RouteSkipped(n[1]) and (n[4] == Gather.HERBALISM or n[4] == Gather.MINING) and Gather.Farmable("nodes", entry, zone) then
            local loot = D.loot[n[3]]
            out[#out + 1] = { itemID = -entry, need = 1,
                sources = { { kind = "node", entry = entry, name = n[1], chance = 100, prof = n[4],
                              skill = n[2], item = loot and loot[1] and loot[1][1] } } }
        end
    end
    table.sort(out, function(a, b) return a.itemID < b.itemID end)
    return out
end

-- Cloth ----------------------------------------------------------------------------

-- Where to farm cloth: each zone's droppers pooled into level bands with their best spots
-- (Data/Gather.lua `cloth`).

Gather.CLOTH = { 2589, 2592, 4306, 4338, 14047, 14256 }   -- Linen to Felcloth, lowest first
Gather.CLOTH_MIN_KILLS = 8   -- dropper spawns a zone needs at the player's level to list a cloth
Gather.CLOTH_SPOTS = 3       -- best spots named for a cloth
Gather.CLOTH_KINDS = { [1] = "beasts", [2] = "dragonkin", [3] = "demons", [4] = "elementals", [5] = "giants",
    [6] = "undead", [7] = "humanoids", [9] = "mechanicals" }   -- the client's plural creature types

local isCloth = {}
for _, id in ipairs(Gather.CLOTH) do isCloth[id] = true end

function Gather.IsCloth(item) return isCloth[item] == true end

-- True when a band whose highest minimum level is `need` is safe at `level`: the rule
-- Farm's skinning spots use (FARM_SAFE_LEVELS).
function Gather.ClothSafe(need, level)
    return need <= level + Gather.FARM_SAFE_LEVELS
end

-- Yards between two points of `zone`'s map.
local function yards(zone, a, b)
    local w, h = Gather.ZoneSize(zone)
    if not w then return math.huge end
    local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
    return math.sqrt(dx * dx + dy * dy)
end

-- What `zone` gives of cloth `item` to a player of `level` and `side`, or nil:
-- { item, kills, perKill, lo, hi, kind, spots = { { x, y, kills, cloth, lo, hi, name } } }.
-- The pool is every safe band of creatures the side may kill with a spot the game puts in
-- the zone; `spots` the CLOTH_SPOTS best of them, ranked by cloth a clear and kill speed,
-- with spots of two bands within Route.GRIND_YD merged.
function Gather.Cloth(zone, item, level, side)
    local z = CP.GatherData.zones[zone]
    local bands = z and z.cloth and z.cloth[item]
    if not bands then return nil end
    local mine = side == "Alliance" and "A" or side == "Horde" and "H" or nil
    local kills, cloth, lo, hi, byKind = 0, 0, nil, nil, {}
    local found = {}
    for _, b in ipairs(bands) do
        local need, blo, bhi, n, per, packed, about, kind, who = unpack(b)
        if Gather.ClothSafe(need, level) and (who == nil or who == mine) then
            local inside = {}
            for i, c in ipairs(Gather.Decode(packed)) do
                local a = about[i] or {}
                if Gather.Inside(zone, c[1], c[2]) then
                    inside[#inside + 1] = { x = c[1], y = c[2], kills = c[3], cloth = c[3] * per,
                        lo = a[2] or blo, hi = a[3] or bhi, name = a[1] or "creatures" }
                end
            end
            if #inside > 0 then
                kills, cloth = kills + n, cloth + n * per
                lo, hi = math.min(lo or blo, blo), math.max(hi or bhi, bhi)
                byKind[kind] = (byKind[kind] or 0) + n
                for _, s in ipairs(inside) do
                    s.score = s.cloth * CP.Route.KillSpeed((s.lo + s.hi) / 2, level)
                    found[#found + 1] = s
                end
            end
        end
    end
    if kills < Gather.CLOTH_MIN_KILLS then return nil end
    table.sort(found, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local spots = {}
    for _, s in ipairs(found) do
        local near
        for _, t in ipairs(spots) do
            if yards(zone, s, t) <= CP.Route.GRIND_YD then near = t break end
        end
        if near then
            near.kills, near.cloth = near.kills + s.kills, near.cloth + s.cloth
            near.lo, near.hi = math.min(near.lo, s.lo), math.max(near.hi, s.hi)
        elseif #spots < Gather.CLOTH_SPOTS then
            spots[#spots + 1] = s
        end
    end
    local kind, most = nil, -1
    for k, n in pairs(byKind) do
        if n > most or (n == most and k > kind) then kind, most = k, n end
    end
    return { item = item, kills = kills, perKill = cloth / kills, lo = lo, hi = hi, kind = kind, spots = spots }
end

-- The cloth of `items` ({ [itemID] = anything }, or every cloth when nil) that `zone`
-- gives at `level` to `side`: Gather.Cloth's answers, lowest cloth first.
function Gather.ClothRows(zone, items, level, side)
    local out = {}
    if not zone then return out end
    for _, item in ipairs(Gather.CLOTH) do
        if items == nil or items[item] ~= nil then
            local c = Gather.Cloth(zone, item, level, side)
            if c then out[#out + 1] = c end
        end
    end
    return out
end

-- Checklist rows for `zone`: ForZone's items with `need` (to 300), `soon` (to the
-- current cap), `have`, `done` and `soonDone` set. Items short for the current cap
-- come first, then items short for later, each biggest shortfall first; then the rest
-- by profession and name. `have(itemID)` and `nameOf(itemID)` come from the caller.
function Gather.Rows(zone, skills, needs, have, nameOf, opts, soon)
    soon = soon or {}
    local rows = Gather.ForZone(zone, skills, opts)
    for _, r in ipairs(rows) do
        r.need = needs[r.itemID]
        r.soon = soon[r.itemID]
        r.have = have(r.itemID) or 0
        r.done = r.need ~= nil and r.have >= r.need
        r.soonDone = r.soon == nil or r.have >= r.soon
        r.name = nameOf and nameOf(r.itemID) or tostring(r.itemID)
    end
    local function tier(r)
        if not r.soonDone then return 1 end
        if r.need and not r.done then return 2 end
        if r.need then return 3 end
        return 4
    end
    local function short(r)
        local t = tier(r)
        return t == 1 and r.soon - r.have or t == 2 and r.need - r.have or 0
    end
    table.sort(rows, function(a, b)
        local ta, tb = tier(a), tier(b)
        if ta ~= tb then return ta < tb end
        local sa, sb = short(a), short(b)
        if sa ~= sb then return sa > sb end
        if a.prof ~= b.prof then return ORDER[a.prof] < ORDER[b.prof] end
        if a.name ~= b.name then return a.name < b.name end
        return a.itemID < b.itemID
    end)
    return rows
end
