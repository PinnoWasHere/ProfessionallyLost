-- craftworld: the character's professions, bags and crafting, as Forever plays them.
--
-- Modelled on what the game shows:
--   * [docs] Every profession, gathering ones too, opens a profession window. Opening one:
--     TRADE_SKILL_SHOW, the ProfessionsFrame shows, then TRADE_SKILL_DATA_SOURCE_CHANGED
--     and TRADE_SKILL_LIST_UPDATE. Closing: the frame hides, then TRADE_SKILL_CLOSE.
--   * [guess] OpenTradeSkill(line) answers true for a profession the character has; the window
--     opens a moment later (the test plays it with Open).
--   * [docs] OpenTradeSkill needs a hardware event (ADDON_ACTION_BLOCKED without one). Press(b)
--     runs b's OnClick inside one, as a real click does; Opens() notes every call with
--     whether a press was under way, whether the pressed button still showed, and how
--     many Panel refreshes the press made before the call. Calls stay recorded either way.
--   * [docs] C_TradeSkillUI answers for the open profession only. GetAllRecipeIDs lists every
--     recipe, learned or not; GetRecipeInfo gives the colour at the current skill
--     (orange below yellow, yellow to the yellow/grey midpoint, green to grey, then grey).
--   * [docs] C_SkillInfo.GetSkillLineInfoByID answers for every profession the character has.
--   * [seen in game 2026-11-11] GetProfessions leaves out Skinning and Fishing.
--   * [docs] C_Item.GetItemCount counts bags, plus the bank when asked.
--   * [docs] CraftRecipe(id, n) queues n casts. A test plays each with Cast(): START, the
--     materials leave the bags, STOP, SUCCEEDED, BAG_UPDATE, BAG_UPDATE_DELAYED, on a
--     skill-up CHAT_MSG_SKILL and SKILL_LINES_CHANGED, then TRADE_SKILL_LIST_UPDATE.
--     Cast(false) fails: FAILED, STOP, and the rest of the batch is dropped.
--     TRADE_SKILL_DATA_SOURCE_CHANGED never fires on a craft: Blizzard's crafting page
--     resets its recipe selection on it (Blizzard_ProfessionsCrafting.lua:304).
-- Guesses:
--   * [db2] Recipes, colours and materials come from ProfLost's guide data (generated from
--     Forever's DB2), so a profession without a guide has no recipes here.
--   * [guess] A new character knows the trainer and starting recipes up to its skill.
--   * [guess] Orange and yellow crafts always give their skill-ups; green and grey never do.
--     The game rolls for yellow and green.
--   * [guess] GetRecipeSchematic answers only for learned recipes; GetBaseProfessionInfo
--     answers { professionID = 0 } with no window open; child professions don't exist.
--   * [guess] Each cast sends STOP before SUCCEEDED, as the modern client does.
--   * [docs] TRADE_SKILL_LIST_UPDATE follows every craft, since each changes craftable counts.
--     Blizzard's ProfessionsFrame reads those counts only when it rebuilds its list on
--     that event (Blizzard_ProfessionsFrame.lua:148, ProfessionsRecipeList.lua:337).
--   * [guess] The skill events come after the bag events.
--   * [guess] TRADE_SKILL_DATA_SOURCE_CHANGED comes after the frame shows, with the data.
--   * [guess] Open(line, "list"): the profession answers at once but its recipe list is empty
--     and IsDataSourceChanging is true until DataArrives(). Which of the two late
--     openings Forever plays is unconfirmed; /proflost trace open shows it in game.
--   * [guess] A cast without the materials fails.
--   * [guess] begin({ late = "colours" | "skill" }): on a skill-up the skill list (C_SkillInfo)
--     moves with the skill events, but the trade skill data lags a frame: recipe colours
--     ("colours"), or colours and GetBaseProfessionInfo's skill ("skill"), move only
--     with the TRADE_SKILL_LIST_UPDATE that follows. Off by default; which order Forever
--     plays is unconfirmed.
--   * [guess] Open(line, late, "foreign"): the trade skill data is live but the game's
--     ProfessionsFrame exists and stays hidden, as when another addon's window stands
--     in for it. No replacement window is offered the craft window either.
-- Seams for a simulator, each with today's behaviour when absent:
--   * begin({ roll = function(recipe, prof) return points end }): the skill-up of a
--     cast, in place of "orange and yellow always, green and grey never".
--   * begin({ refuse = function(id, why) end }): told when CraftRecipe is asked for a
--     recipe the character can't craft ("unlearned", "unknown", "tool <item>").
--   * [guess] A recipe from `recipes` with `tools = { item, ... }`: CraftRecipe starts no cast while
--     one of them is not in the bags (the client's "Requires <tool>"; the bank does not count).
--     `toolsAlso = { [tool] = { item, ... } }` names items that serve for a tool.
--   * begin({ recipes = function(line) return { [id] = recipe } end }): the profession's
--     recipe list, in place of ProfLost's guide data. A recipe has the guide's fields (name,
--     yellow, grey, ups, reagents, makes; src and learn for the default known set), so
--     the window's list, colours, reagents and products follow it.
--   * Snapshot() / begin({ from = snapshot }): the character's professions (rank, cap,
--     known recipes, in learning order), bags and bank as a plain table, and a scene
--     started from one. A reload carries it to a new process (the simulator).
--   * [guess] AddProfession(line, spec) / DropProfession(line): a profession learned or unlearned
--     mid-scene; each fires SKILL_LINES_CHANGED (guess: the skill list changes as it does
--     for a skill-up).
--   * [docs] A recipe with `cooldown` (ms): a cast that succeeds starts it, and CraftRecipe or the
--     next cast of a batch fails while it runs ("cooldown"). C_Spell.GetSpellCooldown answers
--     for the recipe's spell (client-docs; Forever documents no C_TradeSkillUI cooldown call).
--   * [docs] A recipe with `focus` (a spell focus id): CraftRecipe starts no cast unless
--     CraftWorld.FocusRule(focus) is true ("focus <id>"), and GetRecipeRequirements lists it
--     with `met` (client-docs). FocusRule is the simulator's game world's; none
--     means the character stands at every focus.
--   * [guess] Bags as the container API shows them (begin({ items = { [item] = { quality, ilvl,
--     class, subclass, sell, stack, bonding } } })): backpack 0 and bags 1-4, BAG_SLOTS each
--     (guess: four 16-slot bags). An item fills its partial stacks, then the first empty slot;
--     a smaller count leaves the last stacks first. Items past the last slot do not show.
--     C_Item.GetItemInfo answers for the items given. DrawBags() plays the game's open bags:
--     each slot's item button goes through SetItemButtonQuality, which ProfLost hooks.
-- Item names come from tests/fixtures/items.lua.
--
--   CraftWorld.begin({ professions = { [165] = 100, [186] = { rank = 100, max = 150 } },
--                      bags = { [2318] = 20 }, bank = {} })
--   CraftWorld.Open(165[, late or "list"]) / DataArrives() / Asked() / Selected() / Close() / SetBag(item, n) / Learn(line, spell) / SetSkill(line, rank, max)
--   CraftWorld.Cast() / Cast(false) / Miss(); CraftWorld.state.casts lists what was asked for.
--   CraftWorld.Press(button[, mouse]) / Opens()

CraftWorld = {}

local CP = ProfLost

local NAMES = {
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring",
    [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning",
}
CraftWorld.NAMES = NAMES

-- Left out of GetProfessions (the skill list has them).
local NOT_LISTED = { [393] = true, [356] = true }

local S

local function D() return Enum.TradeskillRelativeDifficulty end

-- The cap a skill sits under on a new character: 75, 150, 225 or 300.
function CraftWorld.Cap(rank)
    return math.min(300, (math.floor(rank / 75) + 1) * 75)
end

-- The game's colour rule, the one place the harness holds it (owner-facts rule "green-threshold"):
-- green starts at the yellow-grey midpoint rounded down. ProfLost's own functions are never read here.
function CraftWorld.GreenFrom(r) return math.floor((r.yellow + r.grey) / 2) end

function CraftWorld.Colour(r, rank)
    if rank < r.yellow then return D().Optimal end
    if rank < CraftWorld.GreenFrom(r) then return D().Medium end
    if rank < r.grey then return D().Easy end
    return D().Trivial
end
local colour = CraftWorld.Colour

local function guide(line) return CP.Guides and CP.Guides[line] end

local function recipes(line)
    if S and S.recipes then return S.recipes(line) or {} end
    local g = guide(line)
    return g and g.recipes or {}
end

-- Nothing answers while the window's data is still on its way (CraftWorld.Open(line, true)).
local function openProf() return S.open and not S.loading and S.profs[S.open] end

-- The open profession while its recipe list has arrived.
local function listed() return not S.listLoading and openProf() end

-- The open profession's recipe `id`, or nil.
local function recipe(id)
    local p = openProf()
    return p and recipes(p.line)[id], p
end

local function addProf(line, spec)
    if type(spec) == "number" then spec = { rank = spec } end
    local rank = spec.rank or 1
    local p = { line = line, name = NAMES[line] or (guide(line) and guide(line).name) or ("skill " .. line),
                rank = rank, max = spec.max or CraftWorld.Cap(rank), known = {} }
    if spec.known then
        for _, id in ipairs(spec.known) do p.known[id] = true end
    else
        for id, r in pairs(recipes(line)) do
            if (r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= rank then p.known[id] = true end
        end
    end
    S.profs[line] = p
    S.order[#S.order + 1] = line
end

local function bagUpdate() T.fire("BAG_UPDATE_DELAYED") end

local function craftable(r)
    local n
    for _, pair in ipairs(r.reagents or {}) do
        local can = math.floor((S.bags[pair[1]] or 0) / pair[2])
        n = n and math.min(n, can) or can
    end
    return n or 0
end

local function install()
    local TS = "C_TradeSkillUI."

    -- [docs] The profession info calls answer for the open profession only; no child, linked, guild or NPC crafting.
    World.patch(TS .. "GetBaseProfessionInfo", function()
        local p = openProf()
        if not p then return { professionID = 0 } end
        return { professionID = p.line, professionName = p.name, skillLevel = p.shown or p.rank,
                 skillModifier = CraftWorld.Modifier(p.line), maxSkillLevel = p.max, parentProfessionID = 0 }
    end)
    World.patch(TS .. "GetChildProfessionInfo", function() return { professionID = 0 } end)
    World.patch(TS .. "IsTradeSkillLinked", function() return false end)
    World.patch(TS .. "IsTradeSkillGuild", function() return false end)
    World.patch(TS .. "IsNPCCrafting", function() return false end)
    World.patch(TS .. "IsDataSourceChanging", function() return S.loading or S.listLoading or false end)

    -- [guess] IsTradeSkillReady answers true while a profession is open with its data, and
    -- still true after a /reload with the window open (the reload's state query reads it).
    World.patch(TS .. "IsTradeSkillReady", function() return S.open ~= nil and not S.loading end)

    -- [docs] GetAllRecipeIDs lists every recipe of the open profession, learned or not.
    World.patch(TS .. "GetAllRecipeIDs", function()
        local p = listed()
        local ids = {}
        if not p then return ids end
        for id in pairs(recipes(p.line)) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end)

    -- [classic-db] The colour thresholds are the classic yellow, green and grey points.
    World.patch(TS .. "GetRecipeInfo", function(id)
        local r, p = recipe(id)
        if not r then return nil end
        local d = colour(r, p.tinted or p.rank)
        return { recipeID = id, name = r.name, icon = 136243, learned = p.known[id] == true,
                 relativeDifficulty = d, numSkillUps = r.ups or 1, canSkillUp = d ~= D().Trivial,
                 isDummyRecipe = false }
    end)

    -- [docs] GetCraftableCount counts what the bags hold.
    World.patch(TS .. "GetCraftableCount", function(id)
        local r = recipe(id)
        return r and craftable(r) or 0
    end)

    -- [guess] The schematic answers only for learned recipes.
    World.patch(TS .. "GetRecipeSchematic", function(id)
        local r, p = recipe(id)
        if not (r and p.known[id]) then return nil end
        local slots = {}
        for _, pair in ipairs(r.reagents or {}) do
            slots[#slots + 1] = { reagentType = Enum.CraftingReagentType.Basic, quantityRequired = pair[2],
                                  reagents = { { itemID = pair[1] } } }
        end
        return { recipeID = id, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = slots }
    end)

    -- [docs] GetRecipeOutputItemData, OpenRecipe and OpenTradeSkill as C_TradeSkillUI documents them.
    World.patch(TS .. "GetRecipeOutputItemData", function(id)
        local r = recipe(id)
        return r and r.makes and { itemID = r.makes } or nil
    end)
    World.patch(TS .. "OpenRecipe", function(id) S.selected = id end)
    World.patch(TS .. "OpenTradeSkill", function(line)
        S.asked[#S.asked + 1] = line
        local press = S.press
        S.opens[#S.opens + 1] = { line = line, hw = press ~= nil, shown = press and press.button:IsVisible() or false,
                                  refreshes = press and press.refreshes or 0 }
        return S.profs[line] ~= nil
    end)

    -- [docs] CraftRecipe queues count casts; a refused recipe starts no cast.
    World.patch(TS .. "CraftRecipe", function(id, count)
        count = count or 1
        S.casts[#S.casts + 1] = { id = id, count = count }
        local r, p = recipe(id)
        if not (r and p.known[id]) then
            if S.refuse then S.refuse(id, r and "unlearned" or "unknown") end
            return
        end
        for _, tool in ipairs(r.tools or {}) do
            if not CraftWorld.HasTool(r, tool) then
                if S.refuse then S.refuse(id, "tool " .. tool) end
                return
            end
        end
        if r.focus and not CraftWorld.AtFocus(r.focus) then
            if S.refuse then S.refuse(id, "focus " .. r.focus) end
            return
        end
        if CraftWorld.CooldownLeft(id) > 0 then
            if S.refuse then S.refuse(id, ("cooldown, %d s left"):format(math.ceil(CraftWorld.CooldownLeft(id)))) end
            return
        end
        S.queue = { id = id, left = count, count = count, done = 0 }
    end)

    -- [docs] GetRecipeRequirements lists a spell focus with `met`.
    World.patch(TS .. "GetRecipeRequirements", function(id)
        local r = recipe(id)
        if not (r and r.focus) then return {} end
        return { { name = CraftWorld.FocusName and CraftWorld.FocusName(r.focus) or ("focus " .. r.focus),
                   met = CraftWorld.AtFocus(r.focus) } }
    end)

    -- [docs] C_Spell.GetSpellCooldown answers for the recipe's spell while its cooldown runs.
    World.patch("C_Spell.GetSpellCooldown", function(id)
        local ready, cd = S.ready[id], S.cooldowns[id]
        if ready and cd and ready > GetTime() then
            return { startTime = ready - cd, duration = cd, isEnabled = true, modRate = 1 }
        end
        return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
    end)

    -- [guess] Stopping lets the batch finish its current cast; a cast takes 3 seconds.
    World.patch("StopTradeSkillRepeat", function()
        if S.queue then S.queue.left = math.min(S.queue.left, 1) end
    end)
    World.patch("UnitCastingInfo", function(unit)
        local q = S.queue
        if unit ~= "player" or not q or q.left <= 0 then return nil end
        local r = recipes(S.open or 0)[q.id]
        local now = GetTime() * 1000
        return r and r.name or "", "", 136243, now, now + 3000, true, "cast", false, q.id
    end)

    -- [docs] C_SkillInfo.GetSkillLineInfoByID answers for every profession the character has.
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id)
        local p = S.profs[id]
        if not p then return nil end
        return { skillLineID = id, name = p.name, rank = p.rank, modifier = CraftWorld.Modifier(id), maxRank = p.max,
                 isHeader = false }
    end)

    -- [seen in game 2026-11-11] GetProfessions leaves out Skinning and Fishing.
    World.patch("GetProfessions", function()
        local out = {}
        for i, line in ipairs(S.order) do
            if not NOT_LISTED[line] then out[#out + 1] = i end
        end
        return unpack(out)
    end)
    World.patch("GetProfessionInfo", function(index)
        local p = S.profs[S.order[index] or 0]
        if not p then return nil end
        return p.name, 136243, p.rank, p.max, 0, 0, p.line, CraftWorld.Modifier(p.line)
    end)

    -- [docs] C_Item.GetItemCount counts bags, plus the bank when asked.
    World.patch("C_Item.GetItemCount", function(id, bank)
        return (S.bags[id] or 0) + (bank and (S.bank[id] or 0) or 0)
    end)

    -- [db2] Item names are Forever's ItemSparse names (tests/fixtures/items.lua).
    World.patch("C_Item.GetItemNameByID", function(id)
        return WorldData.items[id] or World.PASS
    end)
end

-- Starts the scene: the character's professions, bags and bank. The character's saved
-- data (CP.charDB) starts empty, as a new character's would.
function CraftWorld.begin(spec)
    spec = spec or {}
    S = { profs = {}, order = {}, bags = {}, bank = {}, casts = {}, asked = {}, opens = {}, open = nil, queue = nil,
          late = spec.late, roll = spec.roll, refuse = spec.refuse, recipes = spec.recipes,
          ready = {}, cooldowns = {}, items = spec.items or rawget(_G, "SimItems"), slots = {} }
    CraftWorld.state = S
    local from = spec.from
    for id, left in pairs(from and from.cooling or {}) do
        S.ready[id], S.cooldowns[id] = GetTime() + left[1], left[2]
    end
    if from then
        for _, line in ipairs(from.order) do addProf(line, from.profs[line]) end
    else
        local lines = {}
        for line in pairs(spec.professions or {}) do lines[#lines + 1] = line end
        table.sort(lines)
        for _, line in ipairs(lines) do addProf(line, spec.professions[line]) end
    end
    for id, n in pairs(from and from.bags or spec.bags or {}) do S.bags[id] = n end
    for id, n in pairs(from and from.bank or spec.bank or {}) do S.bank[id] = n end
    install()

    -- No trade skill is open yet, whatever an earlier scene fired.
    World.set(CP.Professions, "tradeSkillOpen", false)
    if S.items then CraftWorld.InstallBags() end
    World.set(CP, "charDB", spec.charDB or {})

    -- The scene may change the guide window's height and show the guide and gathering
    -- windows. The height goes back, and the windows are redrawn on the restored settings
    -- once the scene ends.
    World.set(CP.db, "windowHeight", CP.db.windowHeight)
    World.redraw = true
    if CP.Plan then CP.Plan.Invalidate() end
    if CP.GuideTab then CP.GuideTab.Forget() end
    if CP.Window then CP.Window.ForgetFollow() end
    World.onEnd(function()
        if S.open then
            CraftWorld.Close()
            -- The debounces the close queued (CP:Later, at most 3 s) run out here, not into the next test.
            T.advance(4)
        end
        if CP.Plan then CP.Plan.Invalidate() end
        if CP.GuideTab then CP.GuideTab.Forget() end
        if CP.Window then CP.Window.ForgetFollow() end

        -- A batch a test started must not leave the craft strip up for the next scene.
        if CP.Crafting then CP.Crafting.count, CP.Crafting.total = 0, 0 end
    end)
end

-- The character as a plain table: professions in learning order with rank, cap and known
-- recipes (sorted), bags and bank. begin({ from = it }) starts the same character.
function CraftWorld.Snapshot()
    local profs = {}
    for _, line in ipairs(S.order) do
        local p = S.profs[line]
        local known = {}
        for id in pairs(p.known) do known[#known + 1] = id end
        table.sort(known)
        profs[line] = { rank = p.rank, max = p.max, known = known }
    end
    local order, bags, bank = {}, {}, {}
    for i, line in ipairs(S.order) do order[i] = line end
    for id, n in pairs(S.bags) do bags[id] = n end
    for id, n in pairs(S.bank) do bank[id] = n end
    local cooling = {}
    for id in pairs(S.ready) do
        local left = CraftWorld.CooldownLeft(id)
        if left > 0 then cooling[id] = { left, S.cooldowns[id] } end
    end
    return { profs = profs, order = order, bags = bags, bank = bank, cooling = cooling }
end

-- Seconds before recipe `id` can be cast again; 0 when it is ready.
function CraftWorld.CooldownLeft(id)
    local ready = S.ready[id]
    return ready and math.max(0, ready - GetTime()) or 0
end

-- Whether the character stands at spell focus `focus`: the game world's rule, else always.
function CraftWorld.AtFocus(focus)
    local rule = CraftWorld.FocusRule
    return rule == nil or rule(focus) == true
end

-- Bags ---------------------------------------------------------------------------------

CraftWorld.BAG_SLOTS = 16
CraftWorld.BAGS = 4

-- An item's facts: { quality, ilvl, class, subclass, sell, stack, bonding }, or nil.
function CraftWorld.ItemFacts(id) return S.items and S.items[id] end

local function stackOf(id)
    local f = CraftWorld.ItemFacts(id)
    return f and f[6] or 20
end

-- The slots brought in line with the counts: a smaller count leaves the last stacks first,
-- a larger one fills the item's partial stacks, then the first empty slots.
local function syncSlots()
    local slots, held = S.slots, {}
    local total = (CraftWorld.BAGS + 1) * CraftWorld.BAG_SLOTS
    for i = 1, total do
        local s = slots[i]
        if s then held[s.item] = (held[s.item] or 0) + s.count end
    end
    for item, n in pairs(held) do
        local want = S.bags[item] or 0
        for i = total, 1, -1 do
            if n <= want then break end
            local s = slots[i]
            if s and s.item == item then
                local take = math.min(s.count, n - want)
                s.count, n = s.count - take, n - take
                if s.count <= 0 then slots[i] = nil end
            end
        end
    end
    local ids = {}
    for item in pairs(S.bags) do ids[#ids + 1] = item end
    table.sort(ids)
    for _, item in ipairs(ids) do
        local more = S.bags[item] - (held[item] or 0)
        local max = stackOf(item)
        for i = 1, total do
            if more <= 0 then break end
            local s = slots[i]
            if s and s.item == item and s.count < max then
                local add = math.min(max - s.count, more)
                s.count, more = s.count + add, more - add
            end
        end
        for i = 1, total do
            if more <= 0 then break end
            if not slots[i] then
                local add = math.min(max, more)
                slots[i], more = { item = item, count = add }, more - add
            end
        end
    end
end

-- The stack in `bag` (0 to BAGS), `slot` (1 to BAG_SLOTS): { item, count }, or nil.
function CraftWorld.Slot(bag, slot)
    if bag < 0 or bag > CraftWorld.BAGS or slot < 1 or slot > CraftWorld.BAG_SLOTS then return nil end
    syncSlots()
    return S.slots[bag * CraftWorld.BAG_SLOTS + slot]
end

local function itemLink(id, quality)
    local colour = ({ [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee" })[quality or 1]
        or "ffffffff"
    return ("|c%s|Hitem:%d::::::::1:::::::::|h[%s]|h|r"):format(colour, id, WorldData.items[id] or ("item " .. id))
end

function CraftWorld.InstallBags()

    -- [guess] Four 16-slot bags and the backpack.
    World.patch("C_Container.GetContainerNumSlots", function(bag)
        return (bag >= 0 and bag <= CraftWorld.BAGS) and CraftWorld.BAG_SLOTS or 0
    end)
    World.patch("C_Container.GetContainerItemInfo", function(bag, slot)
        local s = CraftWorld.Slot(bag, slot)
        if not s then return nil end
        local f = CraftWorld.ItemFacts(s.item) or {}
        return { iconFileID = 136243, stackCount = s.count, isLocked = false, quality = f[1] or 1, isReadable = false,
                 hasLoot = false, hyperlink = itemLink(s.item, f[1]), isFiltered = false, hasNoValue = (f[5] or 0) == 0,
                 itemID = s.item, isBound = f[7] == 1, itemName = WorldData.items[s.item] }
    end)

    -- [docs] C_Item.GetItemInfo answers for the items the scene gave.
    World.patch("C_Item.GetItemInfo", function(id)
        if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
        local f = id and CraftWorld.ItemFacts(id)
        if not f then return World.PASS end
        return WorldData.items[id] or ("item " .. id), itemLink(id, f[1]), f[1], f[2], 0, "", "", f[6], "", 136243, f[5],
            f[3], f[4], f[7], 0, nil, false, ""
    end)
end

-- The game's open bags: one item button per slot, each updated through SetItemButtonQuality
-- (the game's ContainerFrame does so for every slot it fills), which ProfLost hooks for its marks.
-- Returns { { bag, slot, item, button } } for the slots that hold an item.
function CraftWorld.DrawBags()
    S.buttons = S.buttons or {}
    local out = {}
    for bag = 0, CraftWorld.BAGS do
        for slot = 1, CraftWorld.BAG_SLOTS do
            local i = bag * CraftWorld.BAG_SLOTS + slot
            local b = S.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, UIParent)
                b:SetID(slot)
                function b.GetBagID() return bag end
                S.buttons[i] = b
            end
            local s = CraftWorld.Slot(bag, slot)
            local f = s and CraftWorld.ItemFacts(s.item)
            SetItemButtonQuality(b, f and f[1] or nil, s and s.item or nil)
            if s then out[#out + 1] = { bag = bag, slot = slot, item = s.item, button = b } end
        end
    end
    return out
end

-- A profession learned mid-scene, `spec` as begin's professions take it.
function CraftWorld.AddProfession(line, spec)
    if S.profs[line] then error("the character already has profession " .. tostring(line), 2) end
    addProf(line, spec)
    T.fire("SKILL_LINES_CHANGED")
end

-- A profession unlearned mid-scene; its window closes first.
function CraftWorld.DropProfession(line)
    if not S.profs[line] then return end
    if S.open == line then CraftWorld.Close() end
    S.profs[line] = nil
    for i, l in ipairs(S.order) do
        if l == line then table.remove(S.order, i) break end
    end
    T.fire("SKILL_LINES_CHANGED")
end

-- Runs `b`'s OnClick and PostClick inside a hardware event, as a real `mouse` click
-- ("LeftButton") does. Panel refreshes during the press are counted for Opens().
function CraftWorld.Press(b, mouse)
    if S.press then error("a press is already under way", 2) end
    local panel = CP.Panel
    local refresh = panel.Refresh
    local press = { button = b, refreshes = 0 }
    S.press = press
    panel.Refresh = function(...)
        press.refreshes = press.refreshes + 1
        return refresh(...)
    end
    local ok, err = pcall(function()
        local click, post = b:GetScript("OnClick"), b:GetScript("PostClick")
        if click and CP.Style.IsOn(b) then click(b, mouse or "LeftButton", false) end
        if post then post(b, mouse or "LeftButton", false) end
    end)
    panel.Refresh = refresh
    S.press = nil
    if not ok then error(err, 0) end
end

-- Every OpenTradeSkill call: { line, hw, shown, refreshes } (see the header).
function CraftWorld.Opens() return S.opens end

-- The game's profession frame, made on first open.
local function frame()
    local f = rawget(_G, "ProfessionsFrame")
    if f and S.frame == f then return f end
    -- A named frame sets its global: put the old one back, so the frame leaves with the world.
    local before = rawget(_G, "ProfessionsFrame")
    f = CreateFrame("Frame", "ProfessionsFrame", UIParent)
    rawset(_G, "ProfessionsFrame", before)
    f:SetSize(940, 600)
    f:SetPoint("CENTER")
    f:Hide()
    -- The harness keeps no alpha; the game's window is fully opaque.
    function f.GetAlpha() return 1 end
    function f.GetEffectiveAlpha() return 1 end

    -- [docs] The game's ProfessionsFrame shows when a profession opens.
    World.set(_G, "ProfessionsFrame", f)
    S.frame = f
    -- Out of sight while a replacement window shows instead.
    S.hidden = CreateFrame("Frame", nil, UIParent)
    S.hidden:Hide()
    return f
end

-- Opens profession `line`'s window and lets 0.3 s pass, so the guide can redraw.
-- `late`: the window shows before its data, as on the first open after login; nothing
-- answers until CraftWorld.DataArrives(). `where` "foreign": another addon's window
-- shows it, so the game's frame stays hidden.
function CraftWorld.Open(line, late, where)
    local p = S.profs[line]
    if not p then error("the character has no profession " .. tostring(line), 2) end
    if S.open and S.open ~= line then S.queue = nil end
    S.open, S.loading, S.listLoading = line, late == true, late == "list"
    T.fire("TRADE_SKILL_SHOW")
    local f = frame()
    if where ~= "foreign" then
        local taken = World.emit("craft:show", line)
        f:SetParent(taken and S.hidden or UIParent)
        f:Show()
    end
    if not late then
        T.fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
        T.fire("TRADE_SKILL_LIST_UPDATE")
    end
    T.advance(0.3)
end

-- The late window's data arrives.
function CraftWorld.DataArrives()
    S.loading, S.listLoading = false, false
    T.fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
    T.fire("TRADE_SKILL_LIST_UPDATE")
end

-- Profession lines OpenTradeSkill was asked for, in order. The world never opens one by
-- itself: the test plays the opening with Open.
function CraftWorld.Asked() return S.asked end

function CraftWorld.Selected() return S.selected end

function CraftWorld.Close()
    if not S.open then return end
    S.open, S.queue, S.loading, S.listLoading = nil, nil, false, false
    if S.frame then S.frame:Hide() end
    T.fire("TRADE_SKILL_CLOSE")
    World.emit("craft:close")
    T.advance(0.3)
end

function CraftWorld.Opened() return S.open end

function CraftWorld.SetBag(id, n)
    S.bags[id] = n > 0 and n or nil
    bagUpdate()
end

function CraftWorld.SetBank(id, n)
    S.bank[id] = n > 0 and n or nil
end

function CraftWorld.Bag(id) return S.bags[id] or 0 end

-- A profession's skill modifier, as the skill list shows it beside the rank (a fishing pole's or a
-- lure's bonus). 0 unless a world sets it (GatherWorld).
function CraftWorld.Modifier(line) return 0 end

-- Whether the bags hold `tool` or an item that serves for it (recipe.toolsAlso[tool]).
function CraftWorld.HasTool(recipe, tool)
    if (S.bags[tool] or 0) > 0 then return true end
    for _, other in ipairs(recipe and recipe.toolsAlso and recipe.toolsAlso[tool] or {}) do
        if (S.bags[other] or 0) > 0 then return true end
    end
    return false
end

function CraftWorld.Known(line, id)
    local p = S.profs[line]
    return p ~= nil and p.known[id] == true
end

-- A recipe learned at a trainer or from a pattern.
function CraftWorld.Learn(line, id)
    S.profs[line].known[id] = true
    T.fire("NEW_RECIPE_LEARNED", id)
    if S.open == line then T.fire("TRADE_SKILL_LIST_UPDATE") end
end

-- A skill change: a skill-up, or training that lifts the cap.
function CraftWorld.SetSkill(line, rank, max)
    local p = S.profs[line]
    p.rank, p.max = rank, max or p.max
    T.fire("SKILL_LINES_CHANGED")
    if S.open == line then T.fire("TRADE_SKILL_LIST_UPDATE") end
end

-- The next cast gives no point, as a yellow craft's failed roll does.
function CraftWorld.Miss() S.miss = true end

-- Plays the next cast of the batch CraftRecipe started. `ok` false makes it fail.
-- Returns false when nothing is queued.
function CraftWorld.Cast(ok)
    local q = S.queue
    if not q or q.left <= 0 then return false end
    local r, p = recipe(q.id)
    T.fire("UNIT_SPELLCAST_START", "player", "Cast-" .. q.done, q.id)
    local cooling = CraftWorld.CooldownLeft(q.id) > 0
    if cooling and S.refuse then S.refuse(q.id, ("cooldown, %d s left"):format(math.ceil(CraftWorld.CooldownLeft(q.id)))) end
    if ok == false or craftable(r) == 0 or cooling then
        S.queue = nil
        T.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-" .. q.done, q.id)
        T.fire("UNIT_SPELLCAST_STOP", "player", "Cast-" .. q.done, q.id)
        World.emit("craft:stop", q.id, q.done, q.count)
        return true
    end
    for _, pair in ipairs(r.reagents or {}) do
        local left = (S.bags[pair[1]] or 0) - pair[2]
        S.bags[pair[1]] = left > 0 and left or nil
    end
    if r.makes then S.bags[r.makes] = (S.bags[r.makes] or 0) + 1 end
    if r.cooldown and r.cooldown > 0 then
        S.cooldowns[q.id] = r.cooldown / 1000
        S.ready[q.id] = GetTime() + r.cooldown / 1000
    end
    q.left, q.done = q.left - 1, q.done + 1
    if q.left <= 0 then S.queue = nil end
    T.fire("UNIT_SPELLCAST_STOP", "player", "Cast-" .. (q.done - 1), q.id)
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. (q.done - 1), q.id)
    T.fire("BAG_UPDATE", 0)
    bagUpdate()
    local d = colour(r, p.rank)
    local miss = S.miss
    S.miss = nil
    local gain
    if S.roll then
        gain = S.roll(r, p)
    else
        gain = (d == D().Optimal or d == D().Medium) and (r.ups or 1) or 0
    end
    if gain > 0 and p.rank < p.max and not miss then
        local was = p.rank
        p.rank = math.min(p.max, p.rank + gain)
        if S.late then
            p.tinted = was
            if S.late == "skill" then p.shown = was end
        end
        T.fire("CHAT_MSG_SKILL", ("Your skill in %s has increased to %d."):format(p.name, p.rank))
        T.fire("SKILL_LINES_CHANGED")
        if S.late then
            T.advance(0.05)
            p.tinted, p.shown = nil, nil
        end
    end
    T.fire("TRADE_SKILL_LIST_UPDATE")
    World.emit("craft:made", q.id, q.done, q.count)
    if q.left <= 0 then World.emit("craft:stop", q.id, q.done, q.count) end
    return true
end
