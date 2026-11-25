local _, CP = ...
if CP.stopped then return end

-- Creature tooltips: what skinning the corpse gives, with each item's chance, for a
-- player with Skinning. Creatures that are herbed or mined after death (Herbalism or
-- Mining loot) get the same block. The profession's name takes the game's gathering
-- colour: red when the player's skill is too low for the creature.

local UT = {}
CP.UnitTooltip = UT

local G = CP.Gather
local LINES = { { G.SKINNING, "Skinning", "skin", "skins" }, { G.HERBALISM, "Herbalism", "herb", "herbings" },
    { G.MINING, "Mining", "mine", "minings" } }

-- The game's gathering colours: red below the skill needed, then orange, yellow and
-- green for 25, 50 and 100 points over it, grey past that.
local GATHER_COLOURS = {
    { 0, { 1, 0.13, 0.13 } },        -- red: can't yet
    { 25, { 1, 0.5, 0.25 } },        -- orange: a skill-up every time
    { 50, { 1, 1, 0 } },             -- yellow
    { 100, { 0.25, 0.75, 0.25 } },   -- green
}
local GREY = { 0.5, 0.5, 0.5 }
local WHITE = { 1, 1, 1 }

function UT.GatherColour(skill, need)
    if skill < need then return GATHER_COLOURS[1][2] end
    for i = 2, #GATHER_COLOURS do
        if skill < need + GATHER_COLOURS[i][1] then return GATHER_COLOURS[i][2] end
    end
    return GREY
end

-- Creature id from a unit GUID ("Creature-0-...-<id>-..."), or nil for players and pets.
function UT.CreatureID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" then return nil end
    return tonumber(id)
end

-- Blocks for creature `id` given the player's gathering skills `skills` ({ [line] =
-- rank }) and its `level` (the data's top level when unknown): { { name, need, skill,
-- items = { { item, chance } }, note } }, likeliest first. `note` is set on a block built from the
-- player's own recordings (Finds.Loot), used only where the data has no block for that profession.
function UT.Blocks(id, skills, level)
    local mob = CP.GatherData.mobs[id]
    local top = mob and mob[4]
    local lvl = level and level > 0 and level or (mob and mob[3]) or nil
    local need = lvl and G.CorpseSkill(lvl) or 0
    local out = {}
    for _, line in ipairs(LINES) do
        local key = skills[line[1]] and top and G.Gives(id, line[1]) and top[line[1]]
        local loot = key and CP.GatherData.loot[key]
        local items, note
        if loot and #loot > 0 then
            items = {}
            for _, l in ipairs(loot) do items[#items + 1] = { item = l[1], chance = l[2] } end
        elseif line[3] == "skin" and skills[line[1]] and G.Gives(id, line[1]) then
            local list, how, skins = G.SkinLoot(id, lvl)
            if list and how ~= "data" then
                items = {}
                for _, l in ipairs(list) do items[#items + 1] = { item = l[1], chance = l[2] } end
                note = how == "recorded" and ("from %d of your %s"):format(skins, line[4]) or "estimated from level"
            end
        end
        if items and #items > 0 then
            table.sort(items, function(a, b)
                if a.chance ~= b.chance then return a.chance > b.chance end
                return a.item < b.item
            end)
            out[#out + 1] = { name = line[2], need = need, skill = skills[line[1]], items = items, note = note }
        end
    end
    return out
end

local function chanceText(c)
    return c >= 10 and ("%d%%"):format(math.floor(c + 0.5)) or ("%.1f%%"):format(c)
end

-- The client hides some values from addons ("secret values"); those can't be read or
-- passed on, so the tooltip skips them.

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end
UT.Readable = readable

-- Adds the blocks for `unit` to `tooltip`. Returns true when it added any.
-- True when the tooltip carries the game's "Skinnable" line.
function UT.ShowsSkinnable(tooltip)
    local want = _G.UNIT_SKINNABLE_LEATHER or "Skinnable"
    local name = tooltip.GetName and tooltip:GetName()
    for i = 2, tooltip.NumLines and tooltip:NumLines() or 0 do
        local fs = name and _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if readable(text) and text == want then return true end
    end
    return false
end

-- A looted corpse (dead, nothing left to loot) tells whether Forever lets it be skinned.
-- The tooltip redraws while the mouse rests on it; each corpse is read once, and a
-- creature already known skinnable is never read again.
local read, readCount = {}, 0
UT.READ_MAX = 200

-- True when the unit is tapped by someone else, or when that can't be read.
function UT.TapDenied(unit)
    if type(UnitIsTapDenied) ~= "function" then return false end
    local ok, denied = pcall(UnitIsTapDenied, unit)
    return ok and (not readable(denied) or denied == true)
end

function UT.Learn(tooltip, unit, guid, id)
    local mob = id and CP.GatherData.mobs[id]
    if not (mob and mob[4] and mob[4][G.SKINNING]) or read[guid] then return end
    local seen = CP.db and CP.db.skinSeen and CP.db.skinSeen[id]
    if seen == true then return end
    local dead = UnitIsDead(unit)
    if not readable(dead) or not dead then return end
    local ok, loot = pcall(CanLootUnit, guid)
    local shows = UT.ShowsSkinnable(tooltip)

    -- A corpse another player holds loot rights on hides its loot and its line from us.
    if not shows and UT.TapDenied(unit) then return end
    if not shows and not (ok and readable(loot) and loot == false) then return end   -- loot left: ask later
    if readCount >= UT.READ_MAX then wipe(read) readCount = 0 end
    read[guid], readCount = true, readCount + 1
    G.LearnSkin(id, shows, guid)
end

function UT.Add(tooltip, unit)
    if not (CP.db and CP.db.unitTooltip) or not readable(unit) then return false end
    local guid = UnitGUID(unit)
    if not readable(guid) then return false end
    local level = UnitLevel(unit)
    if not readable(level) then level = nil end
    local id = UT.CreatureID(guid)
    UT.Learn(tooltip, unit, guid, id)
    local blocks = id and UT.Blocks(id, G.Skills(), level) or {}
    if #blocks == 0 then return false end
    local needs = G.Needs()
    for _, b in ipairs(blocks) do
        local name = UT.GatherColour(b.skill, b.need)
        tooltip:AddLine(b.name, name[1], name[2], name[3])
        if b.note then tooltip:AddLine("  " .. b.note, GREY[1], GREY[2], GREY[3]) end
        for _, it in ipairs(b.items) do
            local name = C_Item.GetItemNameByID(it.item)
            if not name then C_Item.RequestLoadItemDataByID(it.item) end
            -- What the player's guides still need to 300, beyond bags, bank, mail and purchases on the way.
            local short = (needs[it.item] or 0) - CP.ItemTooltip.Have(it.item)
            local want = short > 0 and ("  short x%d"):format(short) or ""
            -- An item the guides are short of stands out in Daylight UI's accent.
            local c = short > 0 and CP.Style.color.accent or WHITE
            tooltip:AddDoubleLine("  " .. (name or ("item " .. it.item)) .. want, chanceText(it.chance),
                c[1], c[2], c[3], 1, 1, 1)
        end
    end
    tooltip:Show()
    return true
end

-- Unit tooltips go through TooltipDataProcessor on the modern client.
local types = _G.Enum and _G.Enum.TooltipDataType
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and types and types.Unit then
    TooltipDataProcessor.AddTooltipPostCall(types.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        -- A world-cursor tooltip can hand over a secret unit token; the mouseover token
        -- names the same unit and is readable.
        local _, unit = tooltip:GetUnit()
        if not readable(unit) then unit = UnitExists("mouseover") and "mouseover" or nil end
        UT.Add(tooltip, unit)
    end)
end
