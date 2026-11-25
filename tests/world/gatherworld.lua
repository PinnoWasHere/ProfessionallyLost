-- gatherworld: herbs, ore, skinnable corpses and fishing water, as a gatherer meets them.
--
-- The facts are the gathering truth (SimGather, from the simulator's fixtures) or a table a
-- test hands to begin(). The character's skill, cap and bags are CraftWorld's; where it stands,
-- its level and faction are MapWorld's. Each rule names its source:
--   classic-db   the cMaNGOS classic database, and the server code it runs on (cited from its
--                source: Player::UpdateGatherSkill, SkillGainChance, UpdateFishingSkill,
--                Spell::EffectSkinning, GameObject::Use for a fishing bobber; mangosd.conf.dist
--                defaults). Cited, not read from a local copy
--   db2          the Forever client's own tables
--   client-docs  the Forever client's API documentation
--   wiki         warcraft.wiki.gg
--   guess        no source settles it
-- Rules:
--   * [classic-db] What a gatherer finds in a zone: one of the profession's sources the truth places there,
--     picked by spawn weight (classic-db spawns; every spawn point as likely as another and
--     pools not modelled: guess). Herbalism and Mining find nodes, Skinning creatures with
--     skinning loot. Only the zone the character stands in counts.
--   * [db2] A node needs skill at or above its Lock skill (db2). A corpse needs the classic skill for
--     its level: 1 to level 10, (level - 10) x 10 to 19, level x 5 from 20 (classic-db). The
--     creature's level is rolled in its range (classic-db, Creature::SelectLevel).
--   * [guess] Below the need the game refuses: UI_ERROR_MESSAGE with "Skill not high enough"
--     (client-docs payload; the text and errorType are a guess), no loot, no skill.
--   * [guess] A creature DANGER levels or more above the character is too dangerous to kill: the
--     gatherer leaves it, and the world counts it (wiki: a mob 5 or more levels above is red).
--   * [classic-db] A harvest rolls the truth's loot (classic-db LootTemplate: a row at its chance, one item
--     per group, references `times` times) into the bags with the seeded generator.
--   * [classic-db] Its skill-up (classic-db): chance 100 / 75 / 25 / 0 % while the skill is below need + 25
--     / + 50 / + 100 / above (SkillChance.Orange, Yellow, Green, Grey = 100, 75, 25, 0;
--     MiningSteps and SkinningSteps 0), doubled for an elite corpse, one point each
--     (SkillGain.Gathering = 1). Never past the cap.
--   * [classic-db] A cast in the zone's water (classic-db): a bite lands when skill - base + 5 >= a roll of
--     1 to 100; a landed fish rolls the water's loot and gives a point with chance 100 % below
--     75, else 2500 / (skill - 50) % (integer division). A miss: UI_ERROR_MESSAGE "Your fish got
--     away!" (guess). A zone with no water in the truth refuses the cast.
--   * [guess] The water is the zone's own (skill_fishing_base_level and fishing_loot_template under its
--     AreaID), else its easiest sub-area's (guess: where the character casts is not modelled).
--   * [guess] A skill-up fires CHAT_MSG_SKILL, then CraftWorld.SetSkill's SKILL_LINES_CHANGED, as a craft
--     does in CraftWorld.
--   * [docs] C_Map.SetUserWaypoint keeps the waypoint ProfLost sets (client-docs names and returns);
--     CanSetUserWaypointOnMap answers true for every map the maps fixture knows.
--   * Gear, when begin() has it (SimGatherTools and SimGear from the simulator; inert without them):
--     - [db2] A node or corpse of a profession whose gathering spell asks a tool (db2 SpellTotems) needs the
--       tool, or an item that serves for it, in the bags. Without it: UI_ERROR_MESSAGE "Requires
--       <tool>" (the text is a guess), no loot, no skill.
--     - [classic-db] A cast needs the item class its spell asks equipped (classic-db: a fishing pole). Without it:
--       UI_ERROR_MESSAGE "Must have a Fishing Pole equipped" (guess). Equip(item) puts a pole from the
--       bags in the main hand; the one there goes back to the bags.
--     - [classic-db] The skill a bite is landed with is the rank plus the pole's bonus plus a lure's while it lasts
--       (classic-db: GetSkillValue counts both). The skill-up chance reads the rank alone. The skill list
--       shows the bonus as the modifier (CraftWorld.Modifier).
--     - [db2] Lure(item) puts a lure from the bags on the equipped pole for its minutes (SimGear.lures; wiki)
--       at its RequiredSkillRank (db2). Time passes CAST_SECONDS a cast (guess).
--     - [classic-db] A cast within POOL_REACH yards of a pool the truth places in the zone (a fishing node) fishes
--       the pool: its loot, the zone's land check (classic-db: a fishing hole is used from the bobber,
--       the land check is the zone's, 0 where it has none). A pool never runs dry (guess).
-- Nothing happens until begin(); a test that loads the world but not this scene sees the
-- harness stubs, and every patch comes off when the test ends.
--
--   GatherWorld.begin({ facts = SimGather, random = fn, seed = 1 })   after MapWorld and CraftWorld
--   GatherWorld.Sources(line, zone) / Find(line) / Harvest(line, src) / Gather(line) / Cast()
--   GatherWorld.Chance(skill, need, elite) / FishChance(skill) / Land(skill, base) / Water(zone)
--   GatherWorld.CorpseSkill(level) / Waypoint() / Zone(zone) / Facts()
--   GatherWorld.Lacks(line) / Equip(item) / Lure(item) / Bonus(line) / Equipped() / PoolAt()
--   GatherWorld.AnswerClasses(classes) -> count(): item classes for C_Item.GetItemInfoInstant,
--     needs no begin(); count() says how many answers it gave
--   GatherWorld.state: { finds, harvests, refusals = { { entry, why } }, dangerous, casts, landed,
--                        escaped, ups, loot = { [item] = n } }
--   GatherWorld.Snapshot(): the counts, the loot and the waypoint; begin({ from = it }) starts
--   there. The facts and the generator are begin's own (the simulator's generator state is
--   GameWorld's).

GatherWorld = { state = {} }

local S

GatherWorld.DANGER = 5
GatherWorld.SKINNING, GatherWorld.FISHING = 393, 356
GatherWorld.CHANCE = { orange = 100, yellow = 75, green = 25, grey = 0 }
GatherWorld.TOO_LOW = "Skill not high enough"
GatherWorld.ESCAPED = "Your fish got away!"
GatherWorld.NO_POLE = "Must have a Fishing Pole equipped"
GatherWorld.CAST_SECONDS = 15
GatherWorld.POOL_REACH = 20
local ERR_TYPE = 1

local SKIN, FISH = 393, 356

local function rnd() return S.random() end

-- Park-Miller, as GameWorld rolls, for a scene without the simulator.
local function own(seed)
    local s = (seed or 1) % 2147483646 + 1
    for _ = 1, 8 do s = (s * 16807) % 2147483647 end
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

function GatherWorld.Facts() return S.facts end

function GatherWorld.Zone(zone) return S.facts.zones[zone] end

function GatherWorld.CorpseSkill(level)
    if level <= 10 then return 1 end
    if level < 20 then return (level - 10) * 10 end
    return level * 5
end

-- Percent chance of a point gathering something that needs `need` at `skill`.
function GatherWorld.Chance(skill, need, elite)
    local C = GatherWorld.CHANCE
    local c
    if skill >= need + 100 then c = C.grey
    elseif skill >= need + 50 then c = C.green
    elseif skill >= need + 25 then c = C.yellow
    else c = C.orange end
    return math.min(100, c * (elite and 2 or 1))
end

function GatherWorld.FishChance(skill)
    if skill < 75 then return 100 end
    return math.floor(2500 / (skill - 50))
end

-- Percent of bites that land at `skill` in water of base `base`.
function GatherWorld.Land(skill, base)
    return math.max(0, math.min(100, skill - base + 5))
end

-- The zone's water: { base, loot, name }, or nil.
function GatherWorld.Water(zone)
    local z = S.facts.zones[zone]
    local fish = z and z.fish
    if not fish then return nil end
    if fish.base and fish.loot and #fish.loot > 0 then return { base = fish.base, loot = fish.loot, name = z.name } end
    local best
    for _, sub in pairs(fish.sub or {}) do
        if sub.base and sub.loot and #sub.loot > 0 and (not best or sub.base < best.base) then
            best = { base = sub.base, loot = sub.loot, name = sub.name }
        end
    end
    return best
end

-- The profession's sources in `zone`: { { kind, entry, name, n, need, min, max, elite, loot } },
-- `need` for a node only (a corpse's comes from the level it spawns at).
function GatherWorld.Sources(line, zone)
    local z = S.facts.zones[zone]
    local out = {}
    if not z then return out end
    local kind = line == SKIN and "mobs" or "nodes"
    local facts = S.facts[kind]
    for entry, at in pairs(z[kind] or {}) do
        local f = facts[entry]
        if f and f.line == line then
            out[#out + 1] = { kind = kind, entry = entry, name = f.name, n = at.n, need = f.skill, min = f.min,
                              max = f.max, elite = f.elite, loot = f.loot }
        end
    end
    table.sort(out, function(a, b) return a.entry < b.entry end)
    return out
end

-- One source the gatherer comes upon in the zone it stands in, by spawn weight. Nil and why.
function GatherWorld.Find(line)
    local zone = MapWorld.state.zone
    local list = GatherWorld.Sources(line, zone)
    local total = 0
    for _, s in ipairs(list) do total = total + s.n end
    if total <= 0 then return nil, ("the truth places nothing of skill %d in %s"):format(line, MapWorld.ZoneName(zone)) end
    local x = rnd() * total
    S.finds = S.finds + 1
    for _, s in ipairs(list) do
        x = x - s.n
        if x < 0 then return s end
    end
    return list[#list]
end

local function give(item, low, high, got)
    local n = low + math.floor(rnd() * (high - low + 1))
    got[item] = (got[item] or 0) + n
end

local function roll(rolls, got)
    for _, r in ipairs(rolls or {}) do
        if r.group then
            local x, acc = rnd() * 100, 0
            for _, m in ipairs(r.group) do
                acc = acc + m[2]
                if x < acc then give(m[1], m[3], m[4], got) break end
            end
        elseif r.ref then
            for _ = 1, r.times or 1 do
                if rnd() * 100 < r.chance then roll(r.ref, got) end
            end
        elseif rnd() * 100 < r[2] then
            give(r[1], r[3], r[4], got)
        end
    end
    return got
end
GatherWorld.Roll = function(rolls) return roll(rolls, {}) end

local function bag(got)
    local items = {}
    for item in pairs(got) do items[#items + 1] = item end
    table.sort(items)
    for _, item in ipairs(items) do
        S.loot[item] = (S.loot[item] or 0) + got[item]
        CraftWorld.SetBag(item, CraftWorld.Bag(item) + got[item])
    end
end

local function prof(line)
    local p = CraftWorld.state.profs[line]
    if not p then error("the character has no profession " .. tostring(line), 3) end
    return p
end

-- A point at `chance` percent: CHAT_MSG_SKILL, then the skill list moves.
local function skillUp(p, chance)
    if p.rank >= p.max or rnd() * 100 >= chance then return false end
    T.fire("CHAT_MSG_SKILL", ("Your skill in %s has increased to %d."):format(p.name, p.rank + 1))
    CraftWorld.SetSkill(p.line, p.rank + 1, p.max)
    S.ups = S.ups + 1
    return true
end

local function refuse(entry, why)
    S.refusals[#S.refusals + 1] = { entry = entry, why = why }
    T.fire("UI_ERROR_MESSAGE", ERR_TYPE, GatherWorld.TOO_LOW)
end

-- Gear --------------------------------------------------------------------------------

local function toolName(item) return (rawget(_G, "SimToolNames") or {})[item] or ("item " .. tostring(item)) end
GatherWorld.ToolName = toolName

-- Whether the bags hold `tool` or an item that serves for it.
local function holds(tool)
    if CraftWorld.Bag(tool) > 0 then return true end
    for _, other in ipairs(S.alts[tool] or {}) do
        if CraftWorld.Bag(other) > 0 then return true end
    end
    return false
end

-- What profession `line` lacks to gather: "tool" and the item, "equip" and the class it asks, or nil.
function GatherWorld.Lacks(line)
    for _, tool in ipairs((S.tools[line] or {}).tools or {}) do
        if not holds(tool) then return "tool", tool end
    end
    local want = S.gear and S.gear.equip[line]
    if want and not (S.equipped and S.gear.poles[S.equipped]) then return "equip", want end
end

function GatherWorld.Equipped() return S.equipped end

-- Puts pole `item` from the bags in the main hand. True, or false and why.
function GatherWorld.Equip(item)
    if CraftWorld.Bag(item) <= 0 then return false, "not in the bags" end
    if not (S.gear and S.gear.poles[item]) then return false, "no fishing pole" end
    CraftWorld.SetBag(item, CraftWorld.Bag(item) - 1)
    if S.equipped then CraftWorld.SetBag(S.equipped, CraftWorld.Bag(S.equipped) + 1) end
    S.equipped = item
    T.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    T.fire("SKILL_LINES_CHANGED")
    return true
end

-- The lure on the pole while it lasts: { item, bonus, ends } or nil.
local function lure()
    if S.lure and S.clock < S.lure.ends and S.equipped then return S.lure end
    S.lure = nil
end

-- Puts lure `item` from the bags on the equipped pole. True, or false and why.
function GatherWorld.Lure(item)
    local l = S.gear and S.gear.lures[item]
    if not l then return false, "no lure" end
    if CraftWorld.Bag(item) <= 0 then return false, "not in the bags" end
    if not (S.equipped and S.gear.poles[S.equipped]) then return false, "no fishing pole equipped" end
    if prof(FISH).rank < l[3] then return false, ("needs Fishing %d"):format(l[3]) end
    CraftWorld.SetBag(item, CraftWorld.Bag(item) - 1)
    S.lure = { item = item, bonus = l[1], ends = S.clock + l[2] * 60 }
    T.fire("SKILL_LINES_CHANGED")
    return true
end

-- The lure on the pole now, or nil.
function GatherWorld.LureOn() return lure() end

-- The bonus the gear adds to profession `line`'s skill now.
function GatherWorld.Bonus(line)
    if line ~= FISH or not S.gear then return 0 end
    local pole = S.equipped and S.gear.poles[S.equipped] or 0
    local l = lure()
    return pole + (l and l.bonus or 0)
end

-- The pool the character stands within POOL_REACH yards of in its zone: the truth's node entry, or nil.
function GatherWorld.PoolAt()
    local z = S.facts.zones[MapWorld.state.zone]
    if not (z and z.nodes and z.w) then return nil end
    local px, py = MapWorld.state.x or 0, MapWorld.state.y or 0
    local ids = {}
    for entry in pairs(z.nodes) do ids[#ids + 1] = entry end
    table.sort(ids)
    for _, entry in ipairs(ids) do
        local f, at = S.facts.nodes[entry], z.nodes[entry].at
        if f and f.line == FISH and type(at) == "string" then
            for i = 1, #at - 5, 6 do
                local x, y = tonumber(at:sub(i, i + 2)) / 1000, tonumber(at:sub(i + 3, i + 5)) / 1000
                if math.sqrt(((x - px) * z.w) ^ 2 + ((y - py) * z.h) ^ 2) <= GatherWorld.POOL_REACH then return entry end
            end
        end
    end
end

-- Gathers `src` (from Find or Sources). True and { items, up, need, level }; or false, why and
-- its code ("skill", "danger", "tool").
function GatherWorld.Harvest(line, src)
    local p = prof(line)
    local need, level = src.need, nil
    if src.kind == "mobs" then
        level = src.min + math.floor(rnd() * ((src.max or src.min) - src.min + 1))
        if level >= MapWorld.state.level + GatherWorld.DANGER then
            S.dangerous = S.dangerous + 1
            return false, ("%s (level %d) is too dangerous for a level %d character"):format(src.name, level,
                MapWorld.state.level), "danger", level
        end
        need = GatherWorld.CorpseSkill(level)
    end
    local lacks, tool = GatherWorld.Lacks(line)
    if lacks == "tool" then
        S.refusals[#S.refusals + 1] = { entry = src.entry, why = "requires " .. toolName(tool) }
        T.fire("UI_ERROR_MESSAGE", ERR_TYPE, "Requires " .. toolName(tool))
        return false, ("%s needs a %s in the bags"):format(src.name, toolName(tool)), "tool", tool
    end
    if p.rank < (need or 0) then
        refuse(src.entry, ("%s needs %d"):format(src.name, need))
        return false, ("%s needs skill %d"):format(src.name, need), "skill", need
    end
    S.harvests = S.harvests + 1
    local got = roll(src.loot, {})
    bag(got)
    local up = skillUp(p, Rules.Boost(GatherWorld.Chance(p.rank, need or 0, src.elite) / 100) * 100)
    return true, { items = got, up = up, need = need, level = level }
end

-- Finds a source and gathers it: Find, then Harvest.
function GatherWorld.Gather(line)
    local src, why = GatherWorld.Find(line)
    if not src then return false, why, "empty" end
    local ok, info, code, need = GatherWorld.Harvest(line, src)
    return ok, info, code, need, src
end

-- One cast in the zone's water, or in the pool the character stands at. True and { items, up, pool },
-- false and "escaped", or false, why and "water" or "equip".
function GatherWorld.Cast()
    local p = prof(FISH)
    local zone = MapWorld.state.zone
    local water = GatherWorld.Water(zone)
    local pool = S.gear and GatherWorld.PoolAt()
    if GatherWorld.Lacks(FISH) == "equip" then
        T.fire("UI_ERROR_MESSAGE", ERR_TYPE, GatherWorld.NO_POLE)
        return false, "no fishing pole equipped", "equip"
    end
    S.casts = S.casts + 1
    S.clock = S.clock + GatherWorld.CAST_SECONDS
    if not water and not pool then return false, ("the truth has no water in %s"):format(MapWorld.ZoneName(zone)), "water" end
    local base = water and water.base or 0
    local chance = GatherWorld.Land(p.rank + GatherWorld.Bonus(FISH), base)
    if chance < 1 + math.floor(rnd() * 100) then
        S.escaped = S.escaped + 1
        T.fire("UI_ERROR_MESSAGE", ERR_TYPE, GatherWorld.ESCAPED)
        return false, "escaped", "escaped"
    end
    S.landed = S.landed + 1
    if pool then S.pools = S.pools + 1 end
    local got = roll(pool and S.facts.nodes[pool].loot or water.loot, {})
    bag(got)
    local up = skillUp(p, Rules.Boost(GatherWorld.FishChance(p.rank) / 100) * 100)
    return true, { items = got, up = up, base = base, pool = pool }
end

function GatherWorld.Waypoint() return S.waypoint end

local function install()

    -- [docs] The user waypoint calls keep the waypoint ProfLost sets; every map in the maps fixture accepts one.
    World.patch("C_Map.CanSetUserWaypointOnMap", function(id) return WorldData.maps[id] ~= nil end)
    World.patch("C_Map.SetUserWaypoint", function(point)
        local x, y = point.position:GetXY()
        S.waypoint = { zone = point.uiMapID, x = x, y = y }
        S.waypoints = S.waypoints + 1
    end)
    World.patch("C_Map.GetUserWaypoint", function()
        local w = S.waypoint
        return w and { uiMapID = w.zone, position = CreateVector2D(w.x, w.y) } or nil
    end)
    World.patch("C_Map.HasUserWaypoint", function() return S.waypoint ~= nil end)
    World.patch("C_Map.ClearUserWaypoint", function() S.waypoint = nil end)
    World.patch("C_SuperTrack.SetSuperTrackedUserWaypoint", function() end)
end

-- Item classes: C_Item.GetItemInfoInstant answers class and subclass for the items in `classes`
-- ({ [item] = { classID, subclassID } }, SimItemClasses from the simulator), by id,
-- id string or item link; every other item gets the harness stub's answer. The returns are the
-- client's (client-docs: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID);
-- the type names are the classes' English names (guess). Until the test ends, and without begin().
local CLASS_NAMES = { [7] = "Trade Goods" }
local SUBCLASS_NAMES = { [7] = { [6] = "Leather", [7] = "Metal & Stone", [9] = "Herb" } }
GatherWorld.ICON = 134400

function GatherWorld.AnswerClasses(classes)
    local answered = 0

    -- [docs] GetItemInfoInstant returns itemID, type, subtype, equip slot, icon, classID, subclassID. [guess] The type names are the classes' English names.
    World.patch("C_Item.GetItemInfoInstant", function(item)
        local id = tonumber(item) or type(item) == "string" and tonumber(item:match("item:(%d+)"))
        local c = id and classes[id]
        if not c then return World.PASS end
        answered = answered + 1
        return id, CLASS_NAMES[c[1]] or "", (SUBCLASS_NAMES[c[1]] or {})[c[2]] or "", "", GatherWorld.ICON, c[1], c[2]
    end)
    return function() return answered end
end

local COUNTS = { "finds", "harvests", "dangerous", "casts", "landed", "escaped", "ups", "waypoints", "pools", "clock" }

function GatherWorld.Snapshot()
    local out = { loot = {} }
    for _, k in ipairs(COUNTS) do out[k] = S[k] end
    for item, n in pairs(S.loot) do out.loot[item] = n end
    local w = S.waypoint
    if w then out.waypoint = { zone = w.zone, x = w.x, y = w.y } end
    out.equipped = S.equipped
    if S.lure then out.lure = { item = S.lure.item, bonus = S.lure.bonus, ends = S.lure.ends } end
    return out
end

function GatherWorld.begin(spec)
    spec = spec or {}
    local facts = spec.facts or rawget(_G, "SimGather")
    if not facts then error("no gathering facts: pass begin({ facts }) or load the gathering truth (SimGather)", 2) end
    -- Gear: SimGatherTools and SimGear (the simulator's) unless the spec names its own; none in a scene
    -- that loads neither.
    local gear = spec.gear
    if gear == nil then gear = rawget(_G, "SimGear") or false end
    S = { facts = facts, random = spec.random or own(spec.seed), finds = 0, harvests = 0, refusals = {},
          dangerous = 0, casts = 0, landed = 0, escaped = 0, ups = 0, loot = {}, waypoints = 0, pools = 0, clock = 0,
          gear = gear or nil, tools = gear and (spec.tools or rawget(_G, "SimGatherTools")) or {},
          alts = rawget(_G, "SimToolAlts") or {} }
    local from = spec.from
    if from then
        for _, k in ipairs(COUNTS) do S[k] = from[k] or 0 end
        for item, n in pairs(from.loot or {}) do S.loot[item] = n end
        if from.waypoint then S.waypoint = { zone = from.waypoint.zone, x = from.waypoint.x, y = from.waypoint.y } end
        S.equipped = from.equipped
        if from.lure then S.lure = { item = from.lure.item, bonus = from.lure.bonus, ends = from.lure.ends } end
    end
    GatherWorld.state = S
    install()
    if S.gear then World.set(CraftWorld, "Modifier", function(line) return GatherWorld.Bonus(line) end) end
    World.onEnd(function() GatherWorld.state = {} end)
end
