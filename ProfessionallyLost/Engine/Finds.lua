local _, CP = ...
if CP.stopped then return end

-- The player's own gathering finds: each herb picked, vein mined and beast skinned,
-- where the player stood, saved per zone (ProfLostDB.finds). They fill zones the
-- vanilla spawn data lacks, Forever's new ones above all, and later bake into
-- Data/Gather.lua.
-- finds[zone] = { n = { [node name] = { packed... } }, m = { [creature id] = { packed... } },
--                v = { [creature id] = { packed... } } }
-- `v` holds where the player saw beasts the data lacks. It stays the player's own.
-- A packed spot is x * 1e4 rounded, times 1e4, plus y * 1e4 rounded.

local Finds = {}
CP.Finds = Finds

Finds.SAME = 0.004       -- map units: a find this close to a saved one is the same spot
Finds.SPELLS = { herb = 2366, mine = 2575, skin = 8613 }   -- the rank 1 spells, for their names

local pending            -- { castGUID, kind, name, creature } from UNIT_SPELLCAST_SENT
local awaiting           -- { creature, kind, at } between a finished cast and its loot window

Finds.LOOT_WAIT = 15         -- seconds a finished cast waits for its loot window
Finds.LOOT_CREATURES = 400   -- creatures whose loot is kept
Finds.LOOT_ITEMS = 24        -- items kept per creature and kind
Finds.SEEN_CREATURES = 400   -- beasts the data lacks whose name, levels and spots are kept
Finds.SEEN_SPOTS = 40        -- spots kept per such beast and zone

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function store()
    if not CP.db then return nil end
    CP.db.finds = CP.db.finds or {}
    return CP.db.finds
end

function Finds.Pack(x, y)
    return math.floor(x * 1e4 + 0.5) * 1e4 + math.floor(y * 1e4 + 0.5)
end

function Finds.Unpack(p)
    return math.floor(p / 1e4) / 1e4, p % 1e4 / 1e4
end

local function near(list, x, y)
    for _, p in ipairs(list or {}) do
        local px, py = Finds.Unpack(p)
        if math.abs(px - x) < Finds.SAME and math.abs(py - y) < Finds.SAME then return true end
    end
    return false
end

-- Adds a find unless one within SAME is already saved. True when it was new.
function Finds.Add(zone, group, key, x, y)
    local db = store()
    if not (db and zone and key and x and y) then return false end
    db[zone] = db[zone] or {}
    db[zone][group] = db[zone][group] or {}
    local list = db[zone][group][key] or {}
    db[zone][group][key] = list
    if near(list, x, y) then return false end
    list[#list + 1] = Finds.Pack(x, y)
    if CP.GatherMate then CP.GatherMate.Added(zone) end
    return true
end

local function spots(zone, group)
    local db = store()
    local out = {}
    for key, list in pairs(db and db[zone] and db[zone][group] or {}) do
        out[key] = {}
        for _, p in ipairs(list) do
            local x, y = Finds.Unpack(p)
            table.insert(out[key], { x, y, 1 })
        end
    end
    return out
end

-- { [node name] = { { x, y, 1 }, ... } } for `zone`.
function Finds.Nodes(zone) return spots(zone, "n") end

-- { [creature id] = { { x, y, 1 }, ... } } for `zone`.
function Finds.Mobs(zone) return spots(zone, "m") end

-- Where the player saw beasts the data lacks in `zone`, as Finds.Mobs.
function Finds.Seen(zone) return spots(zone, "v") end

-- The saved creature ids of `group` ("m" or "v") in `zone`: { [id] = packed spots }.
local NONE = {}
function Finds.MobIDs(zone, group)
    local db = store()
    return db and db[zone] and db[zone][group] or NONE
end

-- What the player saw of a beast the data lacks: { name, lo, hi }, or nil.
function Finds.Creature(id)
    local all = CP.db and CP.db.seenMobs
    return all and all[id]
end

-- Saves beast `id` with its name and `level`, and the spot (`zone`, `x`, `y`; optional)
-- where the player stood. Only for creatures the data lacks. A new beast or spot starts
-- the zone's gathering answers over once things settle (Engine/GatherMate.lua).
function Finds.Note(id, name, level, zone, x, y)
    if not (CP.db and id) or CP.GatherData.mobs[id] then return end
    CP.db.seenMobs = CP.db.seenMobs or {}
    local all = CP.db.seenMobs
    local c = all[id]
    if not c then
        local count = 0
        for _ in pairs(all) do count = count + 1 end
        if count >= Finds.SEEN_CREATURES then return end
        c = {}
        all[id] = c
        if CP.GatherMate then CP.GatherMate.Added(zone) end
    end
    if type(name) == "string" and name ~= "" then c.name = name end
    if type(level) == "number" and level > 0 then
        c.lo, c.hi = math.min(c.lo or level, level), math.max(c.hi or level, level)
    end
    if not (zone and x and y) then return end
    local z = store()[zone]
    if z and z.m and near(z.m[id], x, y) then return end
    local list = Finds.MobIDs(zone, "v")[id]
    if list and #list >= Finds.SEEN_SPOTS then return end
    Finds.Add(zone, "v", id, x, y)
end

-- The player's spot on `zone`'s map: x, y, or nil.
local function playerAt(zone)
    local pos = zone and C_Map.GetPlayerMapPosition(zone, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if secret(x) or secret(y) or not x or x == 0 then return nil end
    return x, y
end

-- Counts of saved finds: zones, nodes, creatures.
function Finds.Count()
    local zones, nodes, mobs = 0, 0, 0
    for _, z in pairs(store() or {}) do
        zones = zones + 1
        for _, list in pairs(z.n or {}) do nodes = nodes + #list end
        for _, list in pairs(z.m or {}) do mobs = mobs + #list end
    end
    return zones, nodes, mobs
end

local function kindOf(spellID)
    if secret(spellID) or not C_Spell or not C_Spell.GetSpellName then return nil end
    local name = C_Spell.GetSpellName(spellID)
    if not name then return nil end
    for kind, id in pairs(Finds.SPELLS) do
        if C_Spell.GetSpellName(id) == name then return kind end
    end
end

-- The creature id of `unit`, or nil for players, pets and unreadable units.
local function creatureOf(unit)
    local guid = UnitGUID(unit)
    if not guid or secret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind == "Creature" and tonumber(id) or nil
end

local function levelOf(unit)
    local level = UnitLevel and UnitLevel(unit)
    if secret(level) or type(level) ~= "number" or level <= 0 then return nil end
    return level
end

-- The creature id and level of the corpse being skinned, from the target or the mouseover.
local function creatureFor(name)
    for _, unit in ipairs({ "target", "mouseover" }) do
        local unitName = UnitName(unit)
        if not secret(unitName) and unitName == name then
            local id = creatureOf(unit)
            if id then return id, levelOf(unit) end
        end
    end
end

-- A beast the data lacks, targeted or under the mouse: its name, level and where the
-- player stands. A beast has a SKIN_TYPES creature type or a beast family.
function Finds.Saw(unit)
    local id = CP.db and creatureOf(unit)
    if not id or CP.GatherData.mobs[id] then return end
    local family = UnitCreatureFamily and UnitCreatureFamily(unit)
    local kind = UnitCreatureType and UnitCreatureType(unit)
    if secret(family) or secret(kind) then return end
    if not (family or CP.Gather.SKIN_TYPES[kind]) then return end
    local name = UnitName(unit)
    local zone = CP.Waypoint.PlayerZone()
    local x, y = playerAt(zone)
    Finds.Note(id, not secret(name) and name or nil, levelOf(unit), zone, x, y)
end

function Finds.Sent(unit, target, castGUID, spellID)
    if unit ~= "player" or secret(target) or secret(castGUID) then return end
    local kind = kindOf(spellID)
    if not kind or type(target) ~= "string" or target == "" then return end
    local creature, level = creatureFor(target)
    pending = { cast = castGUID, kind = kind, name = target, creature = creature, level = level }
end

function Finds.Succeeded(unit, castGUID)
    local p = pending
    if unit ~= "player" or not p or secret(castGUID) or castGUID ~= p.cast then return end
    pending = nil
    -- Only skinning loot is recorded; herbs and ore from creatures are not.
    local zone = CP.Waypoint.PlayerZone()
    if p.creature and p.kind == "skin" then
        awaiting = { creature = p.creature, kind = p.kind, at = GetTime(), zone = zone }
        Finds.Note(p.creature, p.name, p.level)
    end
    local x, y = playerAt(zone)
    if not x then return end
    if p.kind == "skin" then
        if p.creature then
            Finds.Add(zone, "m", p.creature, x, y)
            CP.Gather.LearnSkin(p.creature, true)
        end
    else
        Finds.Add(zone, "n", p.name, x, y)
    end
end

-- Loot the player's gathering gave, per creature id: db.gatherLoot[id][kind] =
-- { n = loots seen, items = { [item id] = loots it was in } }. An item counts once per loot.
function Finds.Loot(id, kind)
    local db = CP.db and CP.db.gatherLoot
    return db and db[id] and db[id][kind]
end

local function lootItems()
    local items = {}
    local num = GetNumLootItems and GetNumLootItems() or 0
    if secret(num) then return nil end
    local itemType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
    for slot = 1, num do
        local kind = GetLootSlotType and GetLootSlotType(slot)
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        if not secret(kind) and not secret(link) and (kind == nil or kind == itemType) and type(link) == "string" then
            local id = tonumber(link:match("item:(%d+)"))
            if id then items[id] = true end
        end
    end
    return items
end

-- Saves what the loot window holds against the creature just gathered from.
function Finds.Looted()
    local a = awaiting
    if not a then return end
    awaiting = nil
    if GetTime() - a.at > Finds.LOOT_WAIT or not CP.db then return end
    local items = lootItems()
    if not items then return end
    local all = CP.db.gatherLoot or {}
    CP.db.gatherLoot = all
    if not all[a.creature] then
        local count = 0
        for _ in pairs(all) do count = count + 1 end
        if count >= Finds.LOOT_CREATURES then return end
        all[a.creature] = {}
    end
    local rec = all[a.creature][a.kind] or { n = 0, items = {} }
    all[a.creature][a.kind] = rec
    rec.n = rec.n + 1
    local kept = 0
    for _ in pairs(rec.items) do kept = kept + 1 end
    for id in pairs(items) do
        if rec.items[id] then
            rec.items[id] = rec.items[id] + 1
        elseif kept < Finds.LOOT_ITEMS then
            rec.items[id], kept = 1, kept + 1
        end
    end

    -- Skins of a creature without the data's loot change its chances on the next settle.
    local _, how = CP.Gather.SkinLoot(a.creature)
    if how and how ~= "data" and CP.GatherMate then CP.GatherMate.Added(a.zone) end
end

CP:On("LOOT_READY", function() Finds.Looted() end)
CP:On("LOOT_OPENED", function() Finds.Looted() end)
CP:On("UNIT_SPELLCAST_SENT", function(_, ...) Finds.Sent(...) end)
CP:On("UNIT_SPELLCAST_SUCCEEDED", function(_, ...) Finds.Succeeded(...) end)
CP:On("PLAYER_TARGET_CHANGED", function() Finds.Saw("target") end)
CP:On("UPDATE_MOUSEOVER_UNIT", function() Finds.Saw("mouseover") end)
