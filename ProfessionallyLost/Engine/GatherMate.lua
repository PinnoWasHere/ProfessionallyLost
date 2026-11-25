local _, CP = ...
if CP.stopped then return end

-- Herb, ore and fishing nodes recorded by GatherMate2, when it's installed: the
-- player's own finds plus any GatherMate2_Data pack, imported or not. These are real
-- Forever positions, so they back up the vanilla spawn data and cover zones it lacks.
-- Read at runtime only; nothing of GatherMate2 is copied into ProfLost.

local GM = {}
CP.GatherMate = GM

local TYPES = { "Herb Gathering", "Mining", "Fishing" }
local PACK = {   -- GatherMate2_Data's tables, there until the player imports them
    ["Herb Gathering"] = "GatherMateData2HerbDB",
    ["Mining"] = "GatherMateData2MineDB",
    ["Fishing"] = "GatherMateData2FishDB",
}

local cache = {}
-- GatherMate2's own methods, called by name (they're the addon's API, not the game's).
local NAME_FOR, NODES_FOR = "GetNameForNode", "GetNodesForZone"

function GM.Addon()
    local ace = LibStub("AceAddon-3.0", true)
    return ace and ace:GetAddon("GatherMate2", true) or nil
end

-- GatherMate2's packed coordinate to zone-map x, y (its own scheme: x and y to four
-- places, packed as x * 10^10 + y * 10^6).
function GM.Decode(coord)
    return math.floor(coord / 1000000) / 10000, math.floor(coord % 1000000 / 100) / 10000
end

-- { [node name] = { { x, y, 1 }, ... } } for `zone`, cached until a find or import.
-- Spots the game's map puts in another zone are left out: GatherMate2's packs file some
-- nodes under the map they show on, not the zone they stand in.
local cacheEpoch
local resets = 0   -- counts resets, so a build that yielded across one isn't kept

function GM.Nodes(zone)
    local epoch = CP.Gather.MapEpoch()
    if epoch ~= cacheEpoch then wipe(cache); cacheEpoch = epoch end
    if cache[zone] then return cache[zone] end
    local began = resets
    local out, seen, found = {}, {}, {}
    local inside = CP.Gather.Inside
    local addon = GM.Addon()
    if addon then
        local function add(nodeType, coord, id)
            local name = addon[NAME_FOR](addon, nodeType, id)
            if name and not seen[coord .. name] then
                seen[coord .. name] = true
                found[#found + 1] = coord
                found[#found + 1] = name
            end
        end
        for _, nodeType in ipairs(TYPES) do
            for coord, id in addon[NODES_FOR](addon, zone, nodeType, true) do add(nodeType, coord, id) end
            local pack = _G[PACK[nodeType]]
            for coord, id in pairs(pack and pack[zone] or {}) do add(nodeType, coord, id) end
        end
    end
    -- The map is asked about each node once GatherMate2's tables are walked, so a running
    -- job can yield between nodes without GatherMate2 adding to a table mid-walk.
    local tick = CP.Gather.RunningTick()
    for i = 1, #found, 2 do
        local name = found[i + 1]
        local x, y = GM.Decode(found[i])
        if inside(zone, x, y) then
            out[name] = out[name] or {}
            table.insert(out[name], { x, y, 1 })
        end
        if tick then tick() end
    end
    -- ProfLost's own finds (Engine/Finds.lua) join them, GatherMate2 or not.
    local function join(name, list)
        for _, c in ipairs(list) do
            if inside(zone, c[1], c[2]) then
                out[name] = out[name] or {}
                table.insert(out[name], c)
            end
        end
    end
    for name, list in pairs(CP.Finds and CP.Finds.Nodes(zone) or {}) do join(name, list) end
    -- Peers' spots that two players agree on (Engine/Peers.lua).
    for name, list in pairs(CP.Peers and CP.Peers.Nodes(zone) or {}) do join(name, list) end
    if resets == began and cacheEpoch == epoch then cache[zone] = out end
    return out
end

-- Forget cached zones, after GatherMate2 imports or deletes nodes.
function GM.Reset()
    resets = resets + 1
    wipe(cache)
    if CP.Peers then CP.Peers.Reset() end
    if CP.Gather.ResetClusters then CP.Gather.ResetClusters() end
    if CP.Terrain then CP.Terrain.Reset() end
end

-- A single new find barely changes a zone, and while farming new ground nearly every
-- node is one. Rebuilding clusters, guides and the route each time would cost a full
-- rebuild every few seconds, so new finds wait SETTLE seconds (or a zone change) and
-- go in together. Only the zones they landed in start over; a find with no zone starts
-- every zone over. The terrain grid keeps its cache: one node moves no walls.
GM.SETTLE = 120
local pending = false
local zones, everyZone = {}, false

local function settle()
    if not pending then return end
    local changed, all = zones, everyZone
    pending, zones, everyZone = false, {}, false
    resets = resets + 1
    if CP.Peers then CP.Peers.Reset() end
    if all then
        wipe(cache)
        CP.Gather.ResetClusters()
    else
        for zone in pairs(changed) do cache[zone] = nil end
        CP.Gather.ResetZones(changed)
    end
end

-- A find, node or peer's spots came in for `zone` (a uiMapID; nil when unknown).
function GM.Added(zone)
    if type(zone) == "number" then zones[zone] = true else everyZone = true end
    if pending then return end
    pending = true
    C_Timer.After(GM.SETTLE, settle)
end

function GM.Pending() return pending end

CP:On("ZONE_CHANGED_NEW_AREA", settle)

CP:On("PLAYER_ENTERING_WORLD", function()
    local addon = GM.Addon()
    if addon and addon.RegisterMessage and not GM.listening then
        GM.listening = true
        local function changed() GM.Reset() end
        -- GatherMate2 sends the message name, then the node's zone.
        addon.RegisterMessage(GM, "GatherMate2NodeAdded", function(_, zone) GM.Added(zone) end)
        for _, msg in ipairs({ "GatherMate2NodeDeleted", "GatherMateData2Import", "GatherMate2Cleanup" }) do
            addon.RegisterMessage(GM, msg, changed)
        end
    end
end)
