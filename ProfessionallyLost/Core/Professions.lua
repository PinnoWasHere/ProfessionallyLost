local _, CP = ...
if CP.stopped then return end

-- Read-only view of the open profession. Every C_TradeSkillUI call is guarded
-- because Forever's flavor coverage for some of them is unconfirmed.

local Prof = {}
CP.Professions = Prof

local D = Enum.TradeskillRelativeDifficulty
Prof.ORANGE, Prof.YELLOW, Prof.GREEN, Prof.GREY = D.Optimal, D.Medium, D.Easy, D.Trivial

-- The skill where a guide recipe turns green: the yellow-grey midpoint rounded down, as the
-- game's profession window shows it (owner-facts rule "green-threshold").
function Prof.GreenFrom(recipe) return math.floor((recipe.yellow + recipe.grey) / 2) end

-- Color a guide recipe has at skill `at`: orange, yellow, green or grey.
function Prof.DifficultyAt(recipe, at)
    if at < recipe.yellow then return Prof.ORANGE end
    if at < Prof.GreenFrom(recipe) then return Prof.YELLOW end
    if at < recipe.grey then return Prof.GREEN end
    return Prof.GREY
end

local function call(name, ...)
    local fn = C_TradeSkillUI[name]
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

-- A developer's profession preview (UI/Preview.lua), or nil. It holds the line, name, skill
-- and cap, and `known`, the set of recipe spells the preview character knows. While it is
-- set, the skill list answers for that character alone. It is never saved.
Prof.preview = nil

-- The skill list's entry for profession `id`, shaped as C_SkillInfo.GetSkillLineInfoByID
-- gives it, or nil when the character lacks it or the game can't say.
function Prof.SkillLine(id)
    local pv = Prof.preview
    if pv then
        if id ~= pv.line then return nil end
        return { skillLineID = pv.line, name = pv.name, rank = pv.skill, modifier = 0, maxRank = pv.max,
                 isHeader = false }
    end
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return nil end
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
    if not ok or type(info) ~= "table" then return nil end
    return info
end

-- True when the window shows your own profession, not a link, guild list or NPC.
function Prof.IsOwn()
    if call("IsTradeSkillLinked") or call("IsTradeSkillGuild") or call("IsNPCCrafting") then
        return false
    end
    return Prof.Current() ~= nil
end

-- True from TRADE_SKILL_SHOW until TRADE_SKILL_CLOSE: the game has a profession open,
-- whichever addon's window shows it. No frame is asked by name.
Prof.tradeSkillOpen = false
CP:On("TRADE_SKILL_SHOW", function() Prof.tradeSkillOpen = true end)
CP:On("TRADE_SKILL_CLOSE", function() Prof.tradeSkillOpen = false end)

-- True when the game holds an open trade skill now: its data is ready and names a
-- profession. A game without IsTradeSkillReady goes by the profession alone.
function Prof.QueryOpen()
    if call("IsTradeSkillReady") == false then return false end
    return Prof.Current() ~= nil
end

-- A /reload with a profession window open sends no TRADE_SKILL_SHOW, so entering the world
-- after one asks the game. A login or a loading screen keeps what the events said.
CP:On("PLAYER_ENTERING_WORLD", function(_, _, reloading)
    if reloading then Prof.tradeSkillOpen = Prof.QueryOpen() end
end)

-- { id, ids, name, skill, max } for the open profession, or nil.
-- `ids` holds the child, base and parent profession ids, most specific first.
-- `skill` is the rank alone: a modifier (a fishing pole, a lure) lifts no skill-up or step.
function Prof.Current()
    local base = call("GetBaseProfessionInfo")
    if type(base) ~= "table" or not base.professionID or base.professionID == 0 then
        return nil
    end

    local skill = base.skillLevel or 0
    local max = base.maxSkillLevel or 0
    local ids = {}

    -- The child profession carries the shown skill when the profession has one.
    local child = call("GetChildProfessionInfo")
    if type(child) == "table" and child.professionID and child.professionID ~= 0 then
        skill = child.skillLevel or 0
        max = child.maxSkillLevel or max
        ids[#ids + 1] = child.professionID
    end
    ids[#ids + 1] = base.professionID
    if base.parentProfessionID and base.parentProfessionID ~= 0 then
        ids[#ids + 1] = base.parentProfessionID
    end

    return { id = base.professionID, ids = ids, name = base.professionName or "", skill = skill, max = max }
end

-- True while the open profession's data is being re-read (a switch or a first open).
function Prof.Changing()
    return call("IsDataSourceChanging") == true
end

-- True or false when the game says whether recipe `id` is learned; nil when it can't
-- tell yet (no data, or the data is still changing).
function Prof.RecipeLearned(id)
    if Prof.Changing() then return nil end
    local r = call("GetRecipeInfo", id)
    if type(r) ~= "table" or r.learned == nil then return nil end
    return r.learned == true
end

-- Every recipe in the open profession, learned or not. `p` is Prof.Current()'s answer
-- when the caller has it.
-- The list is cached per profession, skill and cap. Colours and skill-ups follow the
-- skill, which is in the key, so a skill-up re-reads it once. Learning a recipe, a
-- profession switch, the window opening or closing, or a change of recipe ids drops it.
-- TRADE_SKILL_LIST_UPDATE also fires after every craft, as craftable counts move: with
-- the same ids it and a bag change refresh only each row's craftable count, on the next
-- read. Callers read the rows and never change them.
local listed, listedKey, listedSet, listedIds, countsStale

function Prof.DropRecipes() listed, listedKey, listedSet, listedIds = nil, nil, nil, nil end

for _, event in ipairs({ "NEW_RECIPE_LEARNED", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_SHOW",
    "TRADE_SKILL_CLOSE", "ProfLost_SKILLS" }) do
    CP:On(event, Prof.DropRecipes)
end
CP:On("BAG_UPDATE_DELAYED", function() countsStale = true end)

-- True when the game lists the same recipe ids, in the same order, as the kept list.
local function sameIds()
    if not listedIds then return false end
    local ids = call("GetAllRecipeIDs")
    if type(ids) ~= "table" or #ids ~= #listedIds then return false end
    for i = 1, #ids do
        if ids[i] ~= listedIds[i] then return false end
    end
    return true
end

-- The skill can move before the recipe colours do: the skill events, and ProfLost's reads on
-- them, may come before the game's TRADE_SKILL_LIST_UPDATE for that skill. A list read
-- under a key that no list update has carried yet is read again after the next one.
local updatedKey, listedSettled

local function keyOf(p) return p and (p.id .. ":" .. p.skill .. ":" .. p.max) end

CP:On("TRADE_SKILL_LIST_UPDATE", function()
    local key = keyOf(Prof.Current())
    local unsettled = listedKey == key and not listedSettled
    if listed and not unsettled and not Prof.Changing() and sameIds() then
        countsStale = true
    else
        Prof.DropRecipes()
    end
    updatedKey = key
end)

local read

function Prof.Recipes(p)
    p = p or Prof.Current()
    local key = keyOf(p)
    if listed and key == listedKey then
        if countsStale then
            countsStale = false
            for _, r in ipairs(listed) do r.craftable = call("GetCraftableCount", r.id) or 0 end
        end
        return listed
    end
    local out, ids = read()

    -- A list read mid-switch or before the data arrives is not kept.
    if key and #out > 0 and not Prof.Changing() then
        listed, listedKey, listedSet, listedIds, countsStale = out, key, nil, ids, false
        listedSettled = key == updatedKey
    end
    return out
end

-- True when the kept list is profession `p`'s whole list: read after its data arrived,
-- with every recipe giving its info.
function Prof.Settled(p)
    return listed ~= nil and listedIds ~= nil and listedKey == keyOf(p)
end

-- True when the spellbook says the player knows spell `id`; nil when it can't answer.
function Prof.SpellKnown(id)
    if Prof.preview then return Prof.preview.known[id] == true end
    local book = C_SpellBook
    if not (book and type(book.IsSpellKnown) == "function") then return nil end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local ok, known = pcall(book.IsSpellKnown, id, bank)
    if not ok then return nil end
    return known == true
end

-- True when the player holds specialization spell `spell` (Weaponsmith 9787). A spellbook that
-- can't answer reads as not held, so the guide never sends the player to a trainer who refuses.
function Prof.Holds(spell)
    local player = rawget(_G, "IsPlayerSpell")
    if not Prof.preview and type(player) == "function" and player(spell) == true then return true end
    return Prof.SpellKnown(spell) == true
end

-- The specializations guide `guide`'s recipes ask (the recipe's `spec`), sorted, built once per guide.
local specsOf = setmetatable({}, { __mode = "k" })

-- The specializations of guide `guide` the player holds, as a string: plans cache under it.
function Prof.SpecKey(guide)
    local list = specsOf[guide]
    if not list then
        list = {}
        local seen = {}
        for _, r in pairs(guide.recipes or {}) do
            if r.spec and not seen[r.spec] then
                seen[r.spec] = true
                list[#list + 1] = r.spec
            end
        end
        table.sort(list)
        specsOf[guide] = list
    end
    if #list == 0 then return "" end
    local parts = {}
    for _, spell in ipairs(list) do
        if Prof.Holds(spell) then parts[#parts + 1] = spell end
    end
    return table.concat(parts, ",")
end

-- Working Overtime, a perk in the Legacy Professions tree: each rank raises the skill-up chance
-- by 4%. ProfLost multiplies the chance by 1 + 0.04 x rank, capped at 1 (Guide.Boost).
Prof.OVERTIME_SPELL = 1225451
Prof.OVERTIME_PER_RANK = 0.04

local function traitCall(space, name, ...)
    local t = rawget(_G, space)
    local fn = type(t) == "table" and t[name]
    if type(fn) ~= "function" then return nil end
    local ok, out = pcall(fn, ...)
    if ok then return out end
    return nil
end

-- The spell behind trait node `info`'s first entry that has one.
local function nodeSpell(configID, info)
    for _, entryID in ipairs(type(info.entryIDs) == "table" and info.entryIDs or {}) do
        local entry = traitCall("C_Traits", "GetEntryInfo", configID, entryID)
        local def = type(entry) == "table" and entry.definitionID
        local d = def and traitCall("C_Traits", "GetDefinitionInfo", def)
        if type(d) == "table" and d.spellID then return d.spellID end
    end
    return nil
end

-- What the game says of the perk: { tree, node, rank, max }. Anything missing reads as rank 0.
function Prof.ReadOvertime()
    local out = { tree = false, node = false, rank = 0, max = 0 }
    local consts = rawget(_G, "Constants")
    local legacy = type(consts) == "table" and consts.LegacyConsts
    local treeID = type(legacy) == "table" and legacy.LEGACY_TREE_PROFESSIONS_ID
    if type(treeID) ~= "number" then return out end
    local configID = traitCall("C_Traits", "GetConfigIDByTreeID", treeID)
    local nodes = type(configID) == "number" and traitCall("C_Traits", "GetTreeNodes", treeID)
    if type(nodes) ~= "table" or #nodes == 0 then return out end
    out.tree = true
    for _, nodeID in ipairs(nodes) do
        local info = traitCall("C_Traits", "GetNodeInfo", configID, nodeID)
        if type(info) == "table" and nodeSpell(configID, info) == Prof.OVERTIME_SPELL then
            out.node = true
            out.rank = tonumber(info.activeRank or info.ranksPurchased) or 0
            out.max = tonumber(info.maxRanks) or 0
            return out
        end
    end
    return out
end

-- Reads the perk again and sets the chance multiplier. True when the rank moved.
function Prof.RefreshOvertime()
    local was = Prof.overtime and Prof.overtime.rank
    Prof.overtime = Prof.ReadOvertime()
    local rank = Prof.overtime.rank
    if CP.Guide then CP.Guide.boost = 1 + Prof.OVERTIME_PER_RANK * rank end
    return was ~= nil and was ~= rank
end

-- The perk's rank, read once and kept until the trait config changes. Plans key on it.
function Prof.OvertimeRank()
    if not Prof.overtime then Prof.RefreshOvertime() end
    return Prof.overtime.rank
end

local function overtimeEvent()
    if Prof.RefreshOvertime() then CP:Emit("ProfLost_SKILLS") end
end
CP:On("PLAYER_ENTERING_WORLD", overtimeEvent)
CP:On("TRAIT_CONFIG_LIST_UPDATED", overtimeEvent)
CP:On("TRAIT_CONFIG_UPDATED", overtimeEvent)

-- What a plan reads of a recipe list, as a string: each recipe's id, whether it is
-- learned and its colour, and a learned recipe's name (Plan.Alias matches by name).
-- Two lists with the same string give the same plan. Built once per kept list.
function Prof.RecipeSetKey(recipes)
    if recipes == listed and listedSet then return listedSet end
    local parts = {}
    for i, r in ipairs(recipes) do
        parts[i] = r.id .. (r.learned and ("+" .. r.difficulty .. "+" .. r.name) or ("-" .. r.difficulty))
    end
    local set = table.concat(parts, ",")
    if recipes == listed then listedSet = set end
    return set
end

-- The rows, and the ids the game listed for them. The ids are nil when a recipe gave no
-- info yet, so the next TRADE_SKILL_LIST_UPDATE reads the list again.
function read()
    local out = {}
    local ids = call("GetAllRecipeIDs")
    if type(ids) ~= "table" then return out, nil end

    local complete = true
    for _, id in ipairs(ids) do
        local r = call("GetRecipeInfo", id)
        if type(r) ~= "table" then complete = false end
        if type(r) == "table" and not r.isDummyRecipe then
            out[#out + 1] = {
                id = id,
                name = r.name or "",
                icon = r.icon,
                learned = r.learned == true,
                difficulty = r.relativeDifficulty or Prof.GREY,
                skillUps = r.numSkillUps or 0,
                canSkillUp = r.canSkillUp == true,
                craftable = call("GetCraftableCount", id) or 0,
            }
        end
    end
    return out, complete and ids or nil
end

-- What the player owns of every material in `guide`, bags and bank.
function Prof.Stock(guide)
    local stock = {}
    for itemID in pairs(guide.items or {}) do
        local n = C_Item.GetItemCount(itemID, true)
        if n and n > 0 then stock[itemID] = n end
    end
    return stock
end

-- Set of learned recipe ids.
function Prof.Learned(recipes)
    local set = {}
    for _, r in ipairs(recipes) do
        if r.learned then set[r.id] = true end
    end
    return set
end

-- Basic reagents for a recipe: { itemID, name, icon, need, have }. `have` counts bags only.
-- Names can arrive late; ProfLost_ITEM_LOADED triggers a redraw.
local function reagent(id, need)
    local name = CP.ItemName(id)
    return {
        itemID = id,
        name = name or "…",
        icon = C_Item.GetItemIconByID(id),
        need = need,
        have = C_Item.GetItemCount(id) or 0,
    }
end

-- `fallback` is a list of { itemID, count } pairs, used when the client has no
-- schematic for the recipe (a recipe the player hasn't learned).
function Prof.Reagents(recipeID, fallback)
    local out = {}
    local schematic = call("GetRecipeSchematic", recipeID, false)
    if type(schematic) == "table" and type(schematic.reagentSlotSchematics) == "table" then
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local first = slot.reagents and slot.reagents[1]
            if slot.reagentType == Enum.CraftingReagentType.Basic and first and first.itemID then
                out[#out + 1] = reagent(first.itemID, slot.quantityRequired or 1)
            end
        end
    end
    if #out == 0 and fallback then
        for _, pair in ipairs(fallback) do out[#out + 1] = reagent(pair[1], pair[2]) end
    end
    return out
end

-- Item a recipe makes, or nil (enchants and other non-item crafts).
function Prof.Output(recipeID)
    local info = call("GetRecipeOutputItemData", recipeID)
    return type(info) == "table" and info.itemID or nil
end

-- Crafts `count` of a learned recipe. Only called from a player's button click.
function Prof.Craft(recipeID, count)
    call("CraftRecipe", recipeID, count)
end

-- Selects a recipe in the profession window: Daylight UI's own while it is up (its line
-- lights and scrolls into view), else the game's.
-- True only when Daylight UI confirms the recipe now shows; the game's call gives no answer.
function Prof.Open(recipeID)
    if CP.Host and CP.Host.SelectRecipe(recipeID) then return true end
    call("OpenRecipe", recipeID)
    return false
end

-- Skill events fire for every skill line, weapons and defense too. ProfLost_SKILLS fires
-- only when a guided or gathering profession's rank or cap changed, or one was learned
-- or dropped. Entering the world takes the snapshot quietly; its own replan covers it.
local ranks, caps = {}, {}

local function rankChanged(id)
    local info = Prof.SkillLine(id)
    local rank, cap = 0, 0
    if info and not info.isHeader then
        rank = info.rank or 0
        cap = info.maxRank or rank
    end
    if ranks[id] == rank and caps[id] == cap then return false end
    ranks[id], caps[id] = rank, cap
    return true
end

-- True when a watched profession moved since the last call.
function Prof.SkillsMoved()
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return false end
    local moved = false
    for id in pairs(CP.Guides or {}) do
        if rankChanged(id) then moved = true end
    end
    for id in pairs(CP.Launcher and CP.Launcher.GATHER_NAMES or {}) do
        if rankChanged(id) then moved = true end
    end
    return moved
end

local function skillEvent()
    if Prof.SkillsMoved() then CP:Emit("ProfLost_SKILLS") end
end
CP:On("PLAYER_ENTERING_WORLD", function() Prof.SkillsMoved() end)
CP:On("SKILL_LINES_CHANGED", skillEvent)
CP:On("CHAT_MSG_SKILL", skillEvent)
