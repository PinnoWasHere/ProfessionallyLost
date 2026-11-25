-- A skinnable corpse's tooltip counts leather in the mail and bought leather on its way,
-- as the item tooltip and the checklist do (BANKMAIL-01b).

local CP = ProfLost
local UT = CP.UnitTooltip
local GUID = "Creature-0-1-0-1-113-0000000001"   -- Stonetusk Boar, skinnable

-- The first item line the corpse tooltip draws, with the guides needing `need` of that item.
local function firstLine(need)
    local lines = {}
    local tip = { AddDoubleLine = function(_, l) lines[#lines + 1] = l end,
        AddLine = function() end, Show = function() end }
    World.patch("UnitGUID", function() return GUID end)
    World.patch("UnitLevel", function() return 6 end)
    World.patch("C_SkillInfo.GetSkillLineInfoByID", function(id) if id == 393 then return { rank = 1 } end end)
    World.patch("C_Item.GetItemNameByID", function() return "Ruined Leather Scraps" end)
    local item = UT.Blocks(UT.CreatureID(GUID), { [393] = 1 }, 6)[1].items[1].item
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.Gather, "Needs", function() return { [item] = need } end)
    T.ok(UT.Add(tip, "mouseover"))
    return lines[1], item
end

T.test("a corpse's tooltip counts leather in the mail and bought leather on its way", function()
    local text, item = firstLine(5)
    T.ok(text:find("short x5", 1, true) ~= nil, "nothing held: " .. text)

    World.set(CP.Purchases, "InMail", function(id) return id == item and 3 or 0 end)
    text = firstLine(5)
    T.ok(text:find("short x2", 1, true) ~= nil, "3 in the mail: " .. text)

    World.set(CP.Purchases, "Bought", function(id) return id == item and 2 or 0 end)
    text = firstLine(5)
    T.ok(not text:find("short", 1, true), "mail and purchases cover it: " .. text)
end)
