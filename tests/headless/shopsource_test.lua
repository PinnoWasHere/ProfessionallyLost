-- The Shop row's tag names the source its price came from: vendor, or auction for an item no vendor always stocks.

local CP = ProfLost
local ITEM = 2319
local CHEAP, DEAR = 5, 10

local function rowTag(item, auction)
    World.set(_G, "DaylightMogul", nil)
    World.set(CP.Scan, "Price", function() return auction end)
    World.set(CP.charDB, "mail", nil)
    World.set(CP.charDB, "bought", nil)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local guide = { items = { [ITEM] = item } }
    local entries = { { kind = "craft", recipe = { name = "X", reagents = { { ITEM, 1 } } }, crafts = 1 } }
    local rows = CP.ShopTab.Rows(guide, entries, CP.Pricing.Get)
    local r = CreateFrame("Button", nil, UIParent)
    CP.ShopTab.InitRow(r, rows[1])
    return r.tag:GetText(), rows[1].price
end

T.test("a vendor cheaper than the auction: the row says vendor", function()
    local tag, price = rowTag({ CHEAP, true }, DEAR)
    T.eq(price, CHEAP)
    T.eq(tag, "vendor")
end)

T.test("an auction cheaper than the vendor: the row still says vendor, at the vendor price", function()
    local tag, price = rowTag({ DEAR, true }, CHEAP)
    T.eq(price, DEAR)
    T.eq(tag, "vendor")
end)

T.test("no vendor stock, an auction price: the row says auction", function()
    local tag, price = rowTag({ 0, false }, CHEAP)
    T.eq(price, CHEAP)
    T.eq(tag, "auction")
end)
