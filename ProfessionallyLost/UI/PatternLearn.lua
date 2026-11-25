local _, CP = ...
if CP.stopped then return end

-- A recipe's pattern in the bags: the step card's button reads "Learn pattern" and a
-- click uses the pattern. Using an item is protected, so the click lands on a secure
-- "/use item:N" button laid over the visible one (Crafting.SecureOverlay: Daylight UI's
-- Win.Caster, else our own), out of combat only. Learning is caught without the
-- profession window: the game's learn events, its "You have learned" line, or the used
-- pattern leaving the bags. The recipe joins the saved learned list (charDB.learned),
-- which the plans of shut professions read, so the card flips to Open or Craft at once.

local PL = {}
CP.PatternLearn = PL

PL.LABEL = "Learn pattern"
PL.COMBAT_TIP = "Patterns can't be learned in combat."
PL.WAIT = 10   -- seconds a click waits for its pattern to leave the bags or the game to say so

-- How many of `item` are in the bags (not the bank or the mail).
function PL.InBags(item)
    return item and (C_Item.GetItemCount(item) or 0) or 0
end

-- Why a pattern in the bags can't be learned yet: { label, tip }, or nil when it can.
function PL.Gate(recipe, prof)
    if not (recipe and prof and prof.skill) then return nil end
    local req = recipe.learn or 0
    local name = prof.name and (" " .. prof.name) or ""
    if req > prof.skill then
        return { label = "At " .. req, tip = ("Learnable at%s %d"):format(name, req) }
    end
    local level = UnitLevel and UnitLevel("player") or nil
    if recipe.level and level and level < recipe.level then
        return { label = "Level " .. recipe.level, tip = ("Needs character level %d"):format(recipe.level) }
    end
    return nil
end

-- The macro a click runs.
function PL.Macro(item)
    return "/use item:" .. item
end

-- The guide key (profession id) whose recipes hold `spell`.
function PL.Owner(spell)
    for key, guide in pairs(CP.Guides or {}) do
        if guide.recipes and guide.recipes[spell] then return key end
    end
end

-- Marks `spell` learned in the saved list and redraws. True when it was new.
function PL.Learned(spell)
    local key = spell and PL.Owner(spell)
    if not (key and CP.charDB) then return false end
    if PL.pending and PL.pending.spell == spell then PL.pending = nil end
    CP.charDB.learned = CP.charDB.learned or {}
    local list = CP.charDB.learned[key] or {}
    CP.charDB.learned[key] = list
    for _, id in ipairs(list) do
        if id == spell then return false end
    end
    list[#list + 1] = spell
    CP.Professions.DropRecipes()
    if CP.Plan and CP.Plan.Invalidate then CP.Plan.Invalidate() end
    CP.Panel.Changed()
    return true
end

-- The secure overlay.
local SPEC = { name = "ProfLost_LearnPattern", hover = true }
function SPEC.post(row)
    local use = row and row.usePattern
    if use then PL.pending = { spell = use.spell, item = use.item, count = PL.InBags(use.item), at = GetTime() } end
end

function PL.Overlay()
    return CP.Crafting.SecureOverlay(SPEC)
end

-- The mouse is on `button` (the step card's Learn pattern): lay the secure /use over it.
function PL.Enter(button)
    local use = button.usePattern
    if not use or not CP.Style.IsOn(button) or InCombatLockdown() or CP.Professions.preview then return end
    PL.Overlay().Over(button, PL.Macro(use.item))
    PL.over = button
end

-- The card no longer offers a pattern: take the overlay away.
function PL.Release()
    if not PL.over then return end
    PL.over = nil
    PL.Overlay().Hide()
end

-- Learning, seen without the profession window ---------------------------------------------

local function byID(_, id)
    if type(id) == "number" then PL.Learned(id) end
end
for _, event in ipairs({ "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE" }) do
    CP:On(event, byID)
end

-- "You have learned how to create a new item: %s." while a click waits.
local function learnLine()
    local fmt = rawget(_G, "ERR_LEARN_RECIPE_S")
    if type(fmt) ~= "string" then fmt = "You have learned how to create a new item: %s." end
    local escaped = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. escaped:gsub("%%s", ".+") .. "$"
end
PL.LEARN_LINE = learnLine()

local function waiting()
    local p = PL.pending
    if p and GetTime() - p.at > PL.WAIT then PL.pending, p = nil, nil end
    return p
end

CP:On("CHAT_MSG_SYSTEM", function(_, msg)
    local p = waiting()
    if p and type(msg) == "string" and msg:find(PL.LEARN_LINE) then PL.Learned(p.spell) end
end)

CP:On("BAG_UPDATE_DELAYED", function()
    local p = waiting()
    if p and PL.InBags(p.item) < p.count then PL.Learned(p.spell) end
end)

-- In combat the button greys with its reason; after, it is Learn pattern again. Only a
-- card that offers a pattern redraws.
local function offered()
    local d = CP.GuideTab and CP.GuideTab.ui.details
    return d ~= nil and d:IsShown() and d.craftAll.usePattern ~= nil
end

CP:On("PLAYER_REGEN_DISABLED", function()
    PL.over = nil
    if offered() then CP.Panel.Changed() end
end)
CP:On("PLAYER_REGEN_ENABLED", function()
    if offered() then CP.Panel.Changed() end
end)
