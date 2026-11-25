-- Owner rule (2026-11-24): vendor goods are always bought from the vendor, even when the
-- auction house lists them cheaper. Coarse Thread: vendor 10, auction 4.

local CP = ProfLost
local THREAD = 2320
local VENDOR, AUCTION = 10, 4

local function setup()
    World.set(_G, "DaylightMogul", nil)
    World.set(CP.Scan, "Price", function() return AUCTION end)
    World.set(CP.charDB, "mail", nil)
    World.set(CP.charDB, "bought", nil)
    World.patch("C_Item.GetItemCount", function() return 0 end)
end

local guide = { items = { [THREAD] = { VENDOR, true } } }

T.test("Pricing.Get gives a vendor good's vendor price and source over a cheaper auction", function()
    setup()
    local price, source = CP.Pricing.Get(THREAD, guide.items[THREAD])
    T.eq(price, VENDOR)
    T.eq(source, "vendor")
end)

T.test("the Shop tags a vendor good vendor at the vendor price", function()
    setup()
    local entries = { { kind = "craft", recipe = { name = "X", reagents = { { THREAD, 1 } } }, crafts = 1 } }
    local rows = CP.ShopTab.Rows(guide, entries, CP.Pricing.Get)
    local r = CreateFrame("Button", nil, UIParent)
    CP.ShopTab.InitRow(r, rows[1])
    T.eq(rows[1].price, VENDOR)
    T.eq(r.tag:GetText(), "vendor")
end)

T.test("the plan's craft cost uses the vendor price", function()
    setup()
    local recipe = { name = "X", reagents = { { THREAD, 3 } } }
    T.eq((CP.Solver.CraftCost(guide, recipe, CP.Pricing.Get)), 3 * VENDOR)
end)

T.test("Buy for guide buys the vendor good at the merchant's price", function()
    setup()
    local slots = { { id = THREAD, info = { price = VENDOR, stackCount = 1, numAvailable = -1, isPurchasable = true } } }
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i].id end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i) return slots[i] and slots[i].info end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    World.set(CP.Buying, "open", true)
    local lines, total = CP.Buying.Price({ { itemID = THREAD, name = "Coarse Thread", count = 5 } }, CP.Buying.Stock())
    T.eq(#lines, 1)
    T.eq(total, 5 * VENDOR)
end)
