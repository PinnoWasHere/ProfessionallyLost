-- Three leftovers from the 1.3.0 screenshots: the All card's skill-up line keeps its numbers, the
-- Shop list's unloaded names fill in, and a greyed Plan for Enchanting draws off.

local CP = ProfLost
local ENCHANTING, TAILOR = 333, 197
local ELWYNN = 1429

T.test("the skill-up line drops its prefix and the name gives way to an ellipsis before the numbers", function()
    local item = { name = "Heavy Silk Bandage", crafts = 23, points = 7.2 }
    T.eq(CP.Impromptu.Info(item, true), "Heavy Silk Bandage x23 · ~7.2 pts")
    local room = 24
    local line = CP.Impromptu.Info(item, true, function(text) return #text <= room end)
    T.ok(#line <= room, "fits: " .. line)
    T.ok(line:find("x23 · ~7.2 pts", 1, true) ~= nil, "numbers stay: " .. line)
    T.ok(line:find("…", 1, true) ~= nil, "the name is cut with an ellipsis: " .. line)
    local roomy = CP.Impromptu.Info(item, true, function() return true end)
    T.eq(roomy, "Heavy Silk Bandage x23 · ~7.2 pts")
end)

T.test("a Shop row whose name loads late fills in on its own", function()
    local ITEM = 2319
    local ui = CP.ShopTab.ui
    World.set(ui, "content", { IsShown = function() return true end })
    World.set(CP.Scan, "Price", function() return nil end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local loaded = false
    local was = C_Item.GetItemNameByID
    World.patch("C_Item.GetItemNameByID", function(id)
        if id == ITEM and not loaded then return nil end
        return was(id)
    end)
    local redraws = 0
    World.set(CP.Panel, "Changed", function() redraws = redraws + 1 end)
    local guide = { items = { [ITEM] = { 5, true } } }
    local entries = { { kind = "craft", recipe = { name = "X", reagents = { { ITEM, 1 } } }, crafts = 1 } }
    local rows = CP.ShopTab.Rows(guide, entries, CP.Pricing.Get)
    local r = CreateFrame("Button", nil, UIParent)
    CP.ShopTab.InitRow(r, rows[1])
    T.eq(r.name:GetText(), "…", "stand-in while unloaded")
    T.advance(3)
    T.eq(redraws, 0, "no redraw while the name is missing")
    loaded = true
    T.advance(3)
    T.ok(redraws >= 1, "asked again and redrew once the name read")
    CP.ShopTab.InitRow(r, rows[1])
    T.ok(r.name:GetText() ~= "…", "the name fills in: " .. tostring(r.name:GetText()))
end)

local function character(lines)
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    local professions = {}
    for _, l in ipairs(lines) do professions[l] = { rank = 1, max = 75 } end
    CraftWorld.begin({ professions = professions })
end

local function deRow()
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, it in ipairs(g.items) do
            if it.key == "deEnchant" then return it end
        end
    end
end

T.test("a greyed Plan for Enchanting draws off and keeps the saved choice", function()
    World.set(CP.db, "deEnchant", true)
    character({ TAILOR })
    local row = deRow()
    T.ok(row ~= nil and type(row.get) == "function", "the row has its own displayed value")
    if not (row and row.get) then return end
    T.eq(row.disabled(function() end), true, "greyed")
    T.eq(row.get(), false, "draws off while greyed")
    T.eq(CP.db.deEnchant, true, "saved choice untouched")
    character({ TAILOR, ENCHANTING })
    T.eq(row.get(), true, "draws the saved choice when available")
    World.set(CP.db, "deEnchant", false)
    T.eq(row.get(), false, "and off when the player turned it off")
    T.eq(type(row.set), "function", "Daylight UI needs set beside get")
end)
