local _, CP = ...
if CP.stopped then return end

-- Enchant again: one button (and key binding) that casts the current Enchanting step's
-- enchant on the matching equipped item, and on the next press confirms the "Replace
-- enchant?" dialog. Leveling Enchanting then takes two presses per craft and no
-- clicking through the profession window, item and dialog.

local EA = {}
CP.EnchantAgain = EA

EA.BUTTON = "ProfLost_EnchantAgain"

-- Equipment slot for the word after "Enchant" in a recipe name.
local SLOTS = {
    Bracer = 9, Chest = 5, Cloak = 15, Boots = 8, Gloves = 10, Shield = 17,
    Weapon = 16, ["2H Weapon"] = 16,
}
local SLOT_NAME = { [9] = "wrist", [5] = "chest", [15] = "back", [8] = "feet", [10] = "hands",
                    [17] = "off hand", [16] = "main hand" }

-- Set when the game blocks confirming the dialog from the button: the player clicks
-- the dialog's Yes instead for the rest of the session.
local confirmBlocked = false

-- The equipment slot an enchant recipe targets, or nil for anything else (rods, oils).
function EA.SlotFor(recipe)
    if not recipe or recipe.makes then return nil end
    local what = recipe.name and recipe.name:match("^Enchant (.-) %- ")
    return what and SLOTS[what] or nil
end

function EA.SlotName(slot)
    return SLOT_NAME[slot] or "?"
end

-- The equipped item for `recipe`: itemID and its ItemLocation, or nil.
function EA.Target(recipe)
    local slot = EA.SlotFor(recipe)
    local itemID = slot and GetInventoryItemID("player", slot)
    if not itemID then return nil end
    local loc = CreateFromMixins(ItemLocationMixin)
    loc:SetEquipmentSlot(slot)
    if not C_Item.DoesItemExist(loc) then return nil end
    return itemID, loc, slot
end

-- True while the game asks whether to replace the item's enchant.
local function replacePending()
    return StaticPopup_FindVisible("REPLACE_ENCHANT") ~= nil
end

-- What a press does now: "confirm", "busy", "bind" (a Bind on Equip item: the player
-- confirms that once), "noitem" or "cast".
function EA.Action(recipe)
    if replacePending() then return confirmBlocked and "busy" or "confirm" end
    if StaticPopup_FindVisible("BIND_ENCHANT") then return "bind" end
    if UnitCastingInfo("player") then return "busy" end
    if not EA.Target(recipe) then return "noitem" end
    return "cast"
end

-- The spell to cast for `row`: the player's own, which the guide's id may not be.
function EA.Spell(row)
    local G = CP.GuideTab
    return G and G.PlayerSpell and G.PlayerSpell(row) or row.spell
end

-- A press of the key binding. It uses the card button's gate, so where the button is
-- greyed the key does nothing.
function EA.Key()
    local row = EA.row
    if row and CP.GuideTab.EnchantGate(row) then EA.Press(row) end
end

-- A press: cast the enchant, or confirm the replace dialog it raised.
function EA.Press(row)
    if not row or not row.recipe then return end
    if CP.Preview and CP.Preview.Refuse("enchant") then return end
    local action = EA.Action(row.recipe)
    if action == "confirm" then
        EA.confirming = true
        C_Item.ReplaceEnchant()
        EA.confirming = false
        StaticPopup_Hide("REPLACE_ENCHANT")
    elseif action == "cast" then
        local _, loc = EA.Target(row.recipe)
        C_TradeSkillUI.CraftEnchant(EA.Spell(row), 1, nil, loc)
    elseif action == "noitem" then
        CP:Print(("Equip an item in your %s slot to enchant it."):format(EA.SlotName(EA.SlotFor(row.recipe))))
    end
    CP:Soon("refresh", function() CP.Panel:Refresh() end)
end

-- Button label for the current state.
function EA.Label(recipe)
    local action = EA.Action(recipe)
    if action == "confirm" then return "Confirm replace" end
    if action == "bind" then return "Confirm binding" end
    return "Enchant again"
end

-- The step the key binding acts on; the Guide tab sets it.
EA.row = nil

-- Hidden named button for the key binding (Bindings.xml).
local key = CreateFrame("Button", EA.BUTTON, UIParent)
key:SetScript("OnClick", function() EA.Key() end)

_G.BINDING_HEADER_PROFLOST = "Professionally Lost"
_G["BINDING_NAME_CLICK " .. EA.BUTTON .. ":LeftButton"] = "Enchant again"

-- The game said no to confirming from the button: leave the dialog to the player.
CP:On("ADDON_ACTION_BLOCKED", function(_, addon)
    if addon == CP.name and EA.confirming then confirmBlocked = true end
end)
CP:On("ADDON_ACTION_FORBIDDEN", function(_, addon)
    if addon == CP.name and EA.confirming then
        confirmBlocked = true
        CP:Print("Click Yes on the replace dialog; the game doesn't let Professionally Lost confirm it.")
    end
end)

-- The button's label follows the dialogs and the step's own cast. The step goes when
-- the guide window hides or the profession window closes; the next draw sets it again.
local function relabel() CP:Soon("refresh", function() CP.Panel:Refresh() end) end

for _, event in ipairs({ "REPLACE_ENCHANT", "BIND_ENCHANT" }) do
    CP:On(event, function() if EA.row then relabel() end end)
end
for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }) do
    CP:On(event, function(_, _, _, spellID)
        if EA.row and spellID == EA.Spell(EA.row) then relabel() end
    end)
end

local function forget() EA.row = nil end
CP.Panel.frame:HookScript("OnHide", forget)
CP:On("TRADE_SKILL_CLOSE", forget)
