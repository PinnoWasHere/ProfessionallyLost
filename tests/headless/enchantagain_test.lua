-- Enchant again: the button and key binding that repeat an enchant on worn gear.
-- The harness has no profession window or dialogs, so the game side is stubbed and
-- the tests check what the button asks the game to do.

local CP = ProfLost
local EA = CP.EnchantAgain
local guide = CP.Guides[333]
local BRACER = 7418   -- Enchant Bracer - Inferior Stamina

local function find(pattern)
    for id, r in pairs(guide.recipes) do
        if r.name:find(pattern) then return id, r end
    end
end

-- The harness's ItemLocationMixin has empty methods; this one remembers the slot.
local FAKE_LOCATION = {
    SetEquipmentSlot = function(self, s) self.slot = s end,
    GetEquipmentSlot = function(self) return self.slot end,
}
local realLocation = _G.ItemLocationMixin

-- Worn item in `slots`, popups in `popups`; returns the calls the game received.
local function game(slots, popups)
    local calls = {}
    _G.ItemLocationMixin = FAKE_LOCATION
    World.patch("GetInventoryItemID", function(_, slot) return slots[slot] end)
    World.patch("C_Item.DoesItemExist", function() return true end)
    World.patch("C_Item.IsBound", function() return true end)
    World.patch("StaticPopup_FindVisible", function(name) return popups[name] and {} or nil end)
    World.patch("StaticPopup_Hide", function(name) calls[#calls + 1] = "hide " .. name; popups[name] = nil end)
    World.patch("UnitCastingInfo", function() return nil end)
    World.patch("C_TradeSkillUI.CraftEnchant", function(spell, n, reagents, loc)
        calls[#calls + 1] = ("cast %d x%d slot %s"):format(spell, n, loc and loc:GetEquipmentSlot() or "?")
    end)
    World.patch("C_Item.ReplaceEnchant", function() calls[#calls + 1] = "replace" end)
    return calls
end

T.test("the slot comes from the enchant's name; made items have none", function()
    T.eq(EA.SlotFor(guide.recipes[BRACER]), 9)
    T.eq(EA.SlotFor({ name = "Enchant 2H Weapon - Minor Impact" }), 16)
    T.eq(EA.SlotFor({ name = "Enchant Cloak - Minor Protection" }), 15)
    T.eq(EA.SlotFor({ name = "Enchant Boots - Minor Speed" }), 8)
    local _, rod = find("^Runed Copper Rod")
    T.eq(EA.SlotFor(rod), nil, "a rod is crafted, not cast on gear")
    local n = 0
    for _, r in pairs(guide.recipes) do
        if r.step and r.name:find("^Enchant ") and not r.makes then
            n = n + 1
            T.ok(EA.SlotFor(r), "every gear enchant step has a slot: " .. r.name)
        end
    end
    T.ok(n > 10)
end)

T.test("a press casts on the worn item, the next confirms the replace dialog", function()
    local popups = {}
    local calls = game({ [9] = 2000 }, popups)
    local row = { spell = BRACER, recipe = guide.recipes[BRACER] }
    T.eq(EA.Action(row.recipe), "cast")
    T.eq(EA.Label(row.recipe), "Enchant again")
    EA.Press(row)
    T.eq(calls[1], ("cast %d x1 slot 9"):format(BRACER))
    popups.REPLACE_ENCHANT = true
    T.eq(EA.Action(row.recipe), "confirm")
    T.eq(EA.Label(row.recipe), "Confirm replace")
    EA.Press(row)
    T.eq(calls[2], "replace")
    T.eq(calls[3], "hide REPLACE_ENCHANT")
    T.eq(EA.Action(row.recipe), "cast", "ready for the next one")
end)

T.test("nothing worn, mid-cast, or a binding prompt: the press does nothing", function()
    local popups = {}
    local calls = game({}, popups)
    local row = { spell = BRACER, recipe = guide.recipes[BRACER] }
    T.eq(EA.Action(row.recipe), "noitem")
    EA.Press(row)
    T.eq(#calls, 0)
    calls = game({ [9] = 2000 }, popups)
    World.patch("UnitCastingInfo", function() return "Enchant Bracer - Inferior Stamina" end)
    T.eq(EA.Action(row.recipe), "busy")
    EA.Press(row)
    T.eq(#calls, 0)
    calls = game({ [9] = 2000 }, { BIND_ENCHANT = true })
    T.eq(EA.Action(row.recipe), "bind", "the player confirms binding a Bind on Equip item")
    T.eq(EA.Label(row.recipe), "Confirm binding")
    EA.Press(row)
    T.eq(#calls, 0)
end)

T.test("the key binding presses the Guide tab's current enchant", function()
    T.ok(_G[EA.BUTTON] ~= nil, "named button for the binding")
    T.eq(_G["BINDING_NAME_CLICK " .. EA.BUTTON .. ":LeftButton"], "Enchant again")
    T.eq(_G.BINDING_HEADER_PROFLOST, "Professionally Lost")
    local calls = game({ [9] = 2000 }, {})
    -- The gate has its own tests (enchantagain_gate_test.lua); here it lets the press through.
    World.set(CP.GuideTab, "EnchantGate", function() return true end)
    EA.row = { spell = BRACER, recipe = guide.recipes[BRACER] }
    _G[EA.BUTTON]:GetScript("OnClick")(_G[EA.BUTTON], "LeftButton")
    T.eq(calls[1], ("cast %d x1 slot 9"):format(BRACER))
    EA.row = nil
    _G[EA.BUTTON]:GetScript("OnClick")(_G[EA.BUTTON], "LeftButton")
    T.eq(#calls, 1, "no step, no cast")
end)

T.test("if the game blocks the confirm, the dialog is left to the player", function()
    local popups = { REPLACE_ENCHANT = true }
    local calls = game({ [9] = 2000 }, popups)
    World.patch("C_Item.ReplaceEnchant", function()
        calls[#calls + 1] = "replace"
        T.fire("ADDON_ACTION_FORBIDDEN", "ProfessionallyLost", "ReplaceEnchant()")
    end)
    local row = { spell = BRACER, recipe = guide.recipes[BRACER] }
    EA.Press(row)
    T.eq(calls[1], "replace")
    popups.REPLACE_ENCHANT = true
    T.eq(EA.Action(row.recipe), "busy", "no more confirming from the button")
end)

T.test("the enchant card names the worn item, or 'your item' while its name is empty or missing", function()
    local answers = { [2000] = "Rough Bracers", [2001] = "", [2002] = nil }
    World.set(CP, "ItemName", function(id) return answers[id] end)
    T.eq(CP.GuideTab.WornName(2000), "Rough Bracers")
    T.eq(CP.GuideTab.WornName(2001), "your item", "an empty name")
    T.eq(CP.GuideTab.WornName(2002), "your item", "no name yet")
end)

T.test("restore the harness's ItemLocationMixin", function()
    _G.ItemLocationMixin = realLocation
    T.ok(true)
end)
