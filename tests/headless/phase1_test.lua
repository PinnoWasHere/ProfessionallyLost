-- Phase 1: fallback ranking and the panel's refresh path against a stubbed profession.

local CP = ProfLost

local RECIPES = {
    [101] = { name = "Bolt of Linen Cloth", relativeDifficulty = 3, learned = true, canSkillUp = true, numSkillUps = 1 },
    [102] = { name = "Linen Bag",           relativeDifficulty = 1, learned = true, canSkillUp = true, numSkillUps = 1 },
    [103] = { name = "Brown Linen Shirt",   relativeDifficulty = 0, learned = true, canSkillUp = true, numSkillUps = 1 },
    [104] = { name = "Linen Belt",          relativeDifficulty = 1, learned = true, canSkillUp = true, numSkillUps = 2 },
    [105] = { name = "Reinforced Pants",    relativeDifficulty = 0, learned = false, canSkillUp = true, numSkillUps = 1 },
    [106] = { name = "Simple Kilt",         relativeDifficulty = 2, learned = true, canSkillUp = false, numSkillUps = 0 },
}
local CRAFTABLE = { [102] = 0, [104] = 3 }

local function stubProfession()
    World.patch("C_TradeSkillUI.GetBaseProfessionInfo", function()
        return { professionID = 197, professionName = "Tailoring", skillLevel = 52, skillModifier = 0, maxSkillLevel = 75 }
    end)
    World.patch("C_TradeSkillUI.GetChildProfessionInfo", function() return { professionID = 0 } end)
    World.patch("C_TradeSkillUI.GetAllRecipeIDs", function() return { 101, 102, 103, 104, 105, 106 } end)
    World.patch("C_TradeSkillUI.GetRecipeInfo", function(id)
        local r = RECIPES[id]
        return r and { recipeID = id, name = r.name, relativeDifficulty = r.relativeDifficulty,
                       learned = r.learned, canSkillUp = r.canSkillUp, numSkillUps = r.numSkillUps }
    end)
    World.patch("C_TradeSkillUI.GetCraftableCount", function(id) return CRAFTABLE[id] or 0 end)
    World.patch("C_TradeSkillUI.IsTradeSkillLinked", function() return false end)
    World.patch("C_TradeSkillUI.IsTradeSkillGuild", function() return false end)
    World.patch("C_TradeSkillUI.IsNPCCrafting", function() return false end)
end

T.test("Current reads skill from the base profession", function()
    stubProfession()
    local p = CP.Professions.Current()
    T.eq(p.name, "Tailoring")
    T.eq(p.skill, 52)
    T.eq(p.max, 75)
end)

T.test("Rank drops grey, unlearned and no-skill-up recipes", function()
    stubProfession()
    local list = CP.Fallback.Rank(CP.Professions.Recipes())
    local names = {}
    for i, r in ipairs(list) do names[i] = r.name end
    T.eq(table.concat(names, ","), "Brown Linen Shirt,Linen Belt,Linen Bag")
end)

T.test("Rank puts craftable recipes ahead within a color", function()
    stubProfession()
    local list = CP.Fallback.Rank(CP.Professions.Recipes())
    T.eq(list[2].name, "Linen Belt")
    T.eq(list[2].craftable, 3)
end)

T.test("Own profession is detected; a linked one is not", function()
    stubProfession()
    T.ok(CP.Professions.IsOwn())
    World.patch("C_TradeSkillUI.IsTradeSkillLinked", function() return true end)
    T.ok(not CP.Professions.IsOwn())
end)

T.test("Panel refresh runs the guide tab without errors", function()
    stubProfession()
    CP.Panel.frame:Show()
    CP.Panel:Refresh()
    T.fire("TRADE_SKILL_LIST_UPDATE")
    T.advance(0.1)
    T.ok(CP.Panel.tabs.guide ~= nil)
end)

T.test("Reagents reads basic slots with bag counts", function()
    World.patch("C_TradeSkillUI.GetRecipeSchematic", function()
        return { reagentSlotSchematics = {
            { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 2996 } } },
            { reagentType = 0, quantityRequired = 1, reagents = { { itemID = 9999 } } },
            { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2320 } } },
        } }
    end)
    World.patch("C_Item.GetItemNameByID", function(id) return id == 2996 and "Bolt of Linen Cloth" or nil end)
    World.patch("C_Item.GetItemIconByID", function() return 132889 end)
    World.patch("C_Item.GetItemCount", function(id) return id == 2996 and 5 or 0 end)

    -- The harness keeps calls for the whole run; count only this one's.
    T.reset_calls()
    local list = CP.Professions.Reagents(102)
    T.eq(#list, 2)
    T.eq(list[1].name, "Bolt of Linen Cloth")
    T.eq(list[1].need, 2)
    T.eq(list[1].have, 5)
    T.eq(list[2].name, "…")
    T.eq(#T.calls("C_Item.RequestLoadItemDataByID"), 1)
end)

T.test("settings point to Daylight UI's options; the panel has no settings page", function()
    CP.Panel:OpenSettings()
    T.eq(CP.Panel.settings, nil)
    T.eq(CP.Panel.gear, nil)
end)

T.test("the guide takes the profession when its data arrives after the window opens", function()
    -- First open after login: the window shows before the profession's data is ready.
    World.set(CP.db, "windowClosed", nil)
    World.patch("C_TradeSkillUI.GetBaseProfessionInfo", function() return nil end)
    CP.Window.Update()
    T.fire("TRADE_SKILL_SHOW")
    World.onEnd(function() T.fire("TRADE_SKILL_CLOSE") end)
    T.advance(3)
    T.ok(CP.Panel.frame:IsShown(), "the guide window stands free meanwhile")
    T.eq(CP.Window.OpenID(), nil, "no profession yet")

    stubProfession()
    T.fire("TRADE_SKILL_LIST_UPDATE")
    T.advance(0.3)
    T.eq(CP.Window.OpenID(), 197, "the data names Tailoring, so it counts as open")
    T.ok(CP.Panel.frame:IsShown(), "still shown, no tab switch needed")
end)

T.test("vendor popups are on by default, one setting for zones, login and reload", function()
    T.eq(CP.db.vendorAlerts, true)
    T.eq(CP.db.vendorAlertsLogin, nil)
end)

T.test("with DaylightUI installed, windows use its shell and redraw it on resize", function()
    local calls = 0
    DaylightUI = { API = { major = 1, minor = 1, Skin = function() calls = calls + 1 end,
        Font = function() return "Fonts\\FRIZQT__.TTF" end } }
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(100, 100)
    ProfLost.Style.Shell(f)
    T.eq(calls, 1)
    f:SetSize(100, 200)
    f:GetScript("OnSizeChanged")(f, 100, 200)  -- the harness doesn't fire it on resize
    T.eq(calls, 2, "skinned again after resizing")
    DaylightUI = nil
end)

