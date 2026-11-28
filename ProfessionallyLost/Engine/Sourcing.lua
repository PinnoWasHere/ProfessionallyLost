local _, CP = ...
if CP.stopped then return end

-- Which guide recipes the player can actually use: learnable on their faction, and,
-- when collecting as they level, made from materials they can get themselves.

local Sourcing = {}
CP.Sourcing = Sourcing

local TRADE_GOODS = 7
-- Trade goods subclass -> gathering skill line: Leather -> Skinning,
-- Metal & Stone -> Mining, Herb -> Herbalism.
Sourcing.GATHER = { [6] = 393, [7] = 186, [9] = 182 }

local SIDE = { Alliance = "A", Horde = "H" }

function Sourcing.Side()
    return SIDE[UnitFactionGroup("player")]
end

-- Set of the player's profession skill lines.
function Sourcing.PlayerSkills()
    local set = {}
    local pv = CP.Professions.preview
    if pv then
        set[pv.line] = true
        return set
    end
    for _, index in pairs({ GetProfessions() }) do
        local skillLine = select(7, GetProfessionInfo(index))
        if skillLine then set[skillLine] = true end
    end
    -- Forever's GetProfessions seems to leave out Skinning and Fishing; the skill list has them.
    for id in pairs(CP.Gather and CP.Gather.Skills() or {}) do set[id] = true end
    return set
end

-- A recipe the player knows, gets with the profession, or can learn from an NPC of
-- their faction. One whose trainers teach only holders of a specialization (`spec`) needs it held.
-- Recipes with no NPC data are assumed learnable.
function Sourcing.CanLearn(guide, id, recipe, learned, side)
    if learned[id] then return true end
    if recipe.spec and not CP.Professions.Holds(recipe.spec) then return false end
    if recipe.src == "auto" or not recipe.npcs or #recipe.npcs == 0 then
        return true
    end
    for _, entry in ipairs(recipe.npcs) do
        local npc = guide.npcs and guide.npcs[entry]
        if npc and (npc[2] == "N" or npc[2] == side) then return true end
    end
    return false
end

-- Gathering skill line a material needs, or nil when anyone can get it (vendor
-- stock, cloth, meat, drops). Fish need Fishing whatever the client files them under
-- (Oily Blackmouth is Trade Goods > Other). A second value names Fishing as another
-- way to get a material that is also fished (Stranglekelp).
local ELEMENTAL = 10   -- Elemental Water fishes up in pools but mostly drops from elementals

-- Items herb and ore nodes give (Stranglekelp), built once.
local nodeItems
local function fromNodes(itemID)
    if not nodeItems then
        nodeItems = {}
        local D = CP.GatherData
        for _, n in pairs(D and D.nodes or {}) do
            if n[4] ~= CP.Gather.FISHING then
                for _, l in ipairs(D.loot[n[3]] or {}) do nodeItems[l[1]] = true end
            end
        end
    end
    return nodeItems[itemID] == true
end
Sourcing.FromNodes = fromNodes

function Sourcing.GatherSkill(guide, itemID)
    local item = guide.items and guide.items[itemID]
    if item and item[2] then return nil end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    local line = classID == TRADE_GOODS and Sourcing.GATHER[subclassID] or nil
    local fish = CP.Pricing and CP.Pricing.IsFish(itemID)
    if line then return line, fish and CP.Gather.FISHING or nil end
    if fish and not fromNodes(itemID) and not (classID == TRADE_GOODS and subclassID == ELEMENTAL) then
        return CP.Gather.FISHING
    end
    return nil
end

-- A gathering profession's reach as the player stands (owner, 2026-11-27): `line` gets `itemID`
-- only once a source the data holds takes their rank, and, with `level`, sits where they may farm
-- (Farm.Reaches). Mining gets a smelted bar only once it mines the ore and knows or may learn the
-- smelt at its rank (Farm.Smelts). `ranks` is skill line -> rank (Gather.Skills); a line with no
-- rank read is not judged. Returns reach(line, itemID) for CanGet.
function Sourcing.Reach(ranks, level)
    local memo = {}
    return function(line, itemID)
        local rank = ranks and ranks[line]
        if not rank or not CP.Farm or not CP.GatherData then return true end
        local key = line .. ":" .. itemID
        local ok = memo[key]
        if ok == nil then
            if CP.Farm.Reach(itemID, line) then
                ok = CP.Farm.Reaches(itemID, line, rank, level)
            else
                ok = line == CP.Gather.MINING and CP.Farm.Smelts(itemID, rank, level)
            end
            memo[key] = ok
        end
        return ok
    end
end

-- The reach of the player's gathering professions now: their ranks and level.
function Sourcing.PlayerReach()
    return Sourcing.Reach(CP.Gather.Skills(), CP.Gather.PlayerLevel())
end

-- Whether the player can get a material without the auction house: vendor stock,
-- else any one of its sources (the gathering skill for its kind while `reach(line, item)` allows
-- it, or a profession that crafts it, guide item field 3). A material with no known source is a drop.
function Sourcing.CanGet(guide, itemID, skills, reach)
    local item = guide.items and guide.items[itemID]
    if item and item[2] then return true end
    local gather, also = Sourcing.GatherSkill(guide, itemID)
    local crafted = item and item[3]
    if not gather and not crafted then return true end
    for _, line in ipairs({ gather, also }) do
        if skills[line] and (not reach or reach(line, itemID)) then return true end
    end
    for _, line in ipairs(crafted or {}) do
        if skills[line] then return true end
    end
    return false
end

-- The professions in `skills` but not in `solo` that let the player get `itemID`: the
-- gathering profession for its kind, Fishing for a fish, and the other crafting professions
-- that make it. Empty when `solo` gets it too. A gathering line counts while `reach` allows it.
function Sourcing.GotThrough(guide, itemID, skills, solo, reach)
    local out = {}
    if Sourcing.CanGet(guide, itemID, solo, reach) or not Sourcing.CanGet(guide, itemID, skills, reach) then return out end
    local gather, also = Sourcing.GatherSkill(guide, itemID)
    for _, line in ipairs({ gather, also }) do
        if skills[line] and not solo[line] and (not reach or reach(line, itemID)) then out[#out + 1] = line end
    end
    local item = guide.items and guide.items[itemID]
    for _, line in ipairs(item and item[3] or {}) do
        if skills[line] and not solo[line] then out[#out + 1] = line end
    end
    return out
end

-- True for Herbalism, Mining and Skinning.
local GATHERING = {}
for _, line in pairs(Sourcing.GATHER) do GATHERING[line] = true end
function Sourcing.IsGathering(line) return GATHERING[line] == true end

-- `skills` as the character would have them without the professions that change guide
-- `key`'s plan: no other crafting profession, no gathering profession and no Fishing.
-- Under "Gather it yourself" a gathering profession lets in the recipes its materials make.
function Sourcing.Solo(skills, key)
    local out = {}
    for line in pairs(skills or {}) do
        if line == key or not (CP.Guides and CP.Guides[line]) and line ~= CP.Gather.FISHING and not GATHERING[line] then
            out[line] = true
        end
    end
    return out
end

function Sourcing.CanGather(guide, recipe, skills)
    for _, pair in ipairs(recipe.reagents) do
        if not Sourcing.CanGet(guide, pair[1], skills) then return false end
    end
    return true
end

-- Filter for Solver.Plan. `collect` limits recipes to materials the player can gather,
-- with `skills` (default: the player's) and `reach` (Sourcing.Reach; none judges no rank).
-- Each material's answer is kept for the filter's life, one solve.
function Sourcing.Filter(guide, learned, collect, skills, reach)
    local side = Sourcing.Side()
    skills = collect and (skills or Sourcing.PlayerSkills()) or nil
    local got = {}
    return function(id, recipe)
        if not Sourcing.CanLearn(guide, id, recipe, learned, side) then return false end
        if skills then
            for _, pair in ipairs(recipe.reagents) do
                local item = pair[1]
                local can = got[item]
                if can == nil then
                    can = Sourcing.CanGet(guide, item, skills, reach)
                    got[item] = can
                end
                if not can then return false end
            end
        end
        return true
    end
end
