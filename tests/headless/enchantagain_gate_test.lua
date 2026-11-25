-- Enchant again key binding: it refuses wherever the step card's button refuses, and both
-- cast the player's own spell when the guide knows the step by another id
-- (ENCHAGAIN-01, review items 19 and 54).

local CP = ProfLost
local EA = CP.EnchantAgain
local P = CP.Panel
local ENCH, BRACER = 333, 7418   -- Enchant Bracer - Inferior Stamina
local ELWYNN = 1429
local STOCK = { [247786] = 40, [6218] = 1 }   -- the bracer's reagent and its rod

local FAKE_LOCATION = {
    SetEquipmentSlot = function(self, s) self.slot = s end,
    GetEquipmentSlot = function(self) return self.slot end,
}

-- Enchanting at `o.rank` / `o.max` with a bracer worn, a game that records CraftEnchant
-- casts, and the Guide tab on Enchanting. `o.open` leaves the profession window open,
-- `o.known` is the recipes the character knows (default: the starting set).
local function scene(o)
    local casts = {}
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCH] = { rank = o.rank or 1, max = o.max or 75, known = o.known } },
                       bags = o.bags or STOCK })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function() CP.Window.Update() end)
    World.set(_G, "ItemLocationMixin", FAKE_LOCATION)
    World.patch("GetInventoryItemID", function(_, slot) return slot == 9 and 2000 or nil end)
    World.patch("C_Item.DoesItemExist", function() return true end)
    World.patch("C_Item.IsBound", function() return true end)
    World.patch("StaticPopup_FindVisible", function() return nil end)
    World.patch("UnitCastingInfo", function() return nil end)
    World.patch("C_TradeSkillUI.CraftEnchant", function(spell, n, _, loc)
        casts[#casts + 1] = ("%d x%d slot %s"):format(spell, n, loc and loc:GetEquipmentSlot() or "?")
    end)
    CraftWorld.Open(ENCH)
    T.advance(1)
    if not o.open then
        CraftWorld.Close()
        T.advance(1)
    end
    World.set(CP.charDB, "guideMode", "one")
    CP.Window.Pick(ENCH)
    P.tabs.guide.button:GetScript("OnClick")()
    return casts
end

-- Picks the bracer step; returns its row and the card's one button.
local function pickBracer()
    local ui = CP.GuideTab.ui
    for _, r in ipairs(ui.rows) do
        if r.spell == BRACER then
            CP.GuideTab.Pick(r)
            return r, ui.details.craftAll
        end
    end
end

local function press()
    _G[EA.BUTTON]:GetScript("OnClick")(_G[EA.BUTTON], "LeftButton")
end

T.test("the key casts when the card's button is on", function()
    local casts = scene({ open = true })
    local row, b = pickBracer()
    T.ok(row ~= nil, "the bracer step is listed")
    T.eq(EA.row and EA.row.spell, BRACER, "the step is the key's step")
    T.ok(b.enchantRow ~= nil, "the card shows the Enchant again button")
    T.eq(b.cpOn, true, "button on")
    press()
    T.eq(#casts, 1, "one cast")
end)

T.test("the key does nothing while the profession window is shut", function()
    local casts = scene({})
    local _, b = pickBracer()
    T.eq(b.label:GetText(), "Open", "the card's button reads Open")
    press()
    T.eq(#casts, 0, "no cast with the window shut")
end)

T.test("the key does nothing for a recipe the character has not learned", function()
    local casts = scene({ open = true, known = { 7421 } })
    local row, b = pickBracer()
    T.ok(row ~= nil and not row.learned, "the step is not learned")
    T.eq(b.cpOn, false, "the card's button is greyed")
    press()
    T.eq(#casts, 0, "no cast for an unlearned recipe")
end)

T.test("the key does nothing without the materials, as the card's button", function()
    local casts = scene({ open = true, bags = { [6218] = 1 } })
    local row, b = pickBracer()
    T.eq(row.craftable or 0, 0, "no materials")
    T.eq(b.cpOn, false, "button greyed")
    press()
    T.eq(#casts, 0, "no cast without materials")
end)

T.test("the key does nothing at the skill cap, as the card's button", function()
    local casts = scene({ open = true })
    -- The step waits on the rank that lifts the cap, as a step past 75 does.
    World.set(CP.Guide, "PastCap", function() return { cap = 75, kind = "trainer", name = "Expert Enchanting" } end)
    local row, b = pickBracer()
    T.ok(row ~= nil, "the bracer step is listed")
    T.eq(b.cpOn, false, "button greyed at the cap")
    T.ok((b.tip or ""):find("Skill capped at 75", 1, true) ~= nil, "the card says why: " .. tostring(b.tip))
    press()
    T.eq(#casts, 0, "no cast at the cap")
end)

T.test("the cast and the relabel use the player's aliased spell", function()
    local casts = scene({ open = true })
    pickBracer()
    local ALIAS = BRACER + 100000
    World.set(CP.GuideTab.ui.live, "alias", { [BRACER] = ALIAS })
    press()
    T.eq(casts[1] and casts[1]:match("^(%d+)"), tostring(ALIAS), "CraftEnchant gets the aliased spell")
    local refreshed = 0
    World.set(CP.Panel, "Refresh", function() refreshed = refreshed + 1 end)
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", ALIAS)
    T.advance(1)
    T.ok(refreshed > 0, "the aliased spell's cast relabels the button")
    refreshed = 0
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", BRACER)
    T.advance(1)
    T.eq(refreshed, 0, "the guide's own id is not the player's cast")
end)
