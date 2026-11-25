-- Buying vendor materials from the open merchant.

local CP = ProfLost

-- A merchant: slot 1 Fine Thread (unlimited), slot 2 Gray Dye (3 left), slot 3 Salt (sold out).
local function merchant()
    local slots = {
        { id = 2321, info = { price = 100, stackCount = 1, numAvailable = -1, isPurchasable = true } },
        { id = 4340, info = { price = 350, stackCount = 1, numAvailable = 3, isPurchasable = true } },
        { id = 4289, info = { price = 50, stackCount = 1, numAvailable = 0, isPurchasable = true } },
    }
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i].id end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i) return slots[i] and slots[i].info end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    CP.Buying.open = true
    return slots
end

T.test("only items this merchant has in stock are offered, limited ones capped", function()
    merchant()
    local stock = CP.Buying.Stock()
    T.ok(stock[2321] and stock[4340], "thread and dye")
    T.eq(stock[4289], nil, "sold-out salt isn't offered")
    local lines, total = CP.Buying.Price({
        { itemID = 2321, name = "Fine Thread", count = 22 },
        { itemID = 4340, name = "Gray Dye", count = 11 },
        { itemID = 4289, name = "Salt", count = 5 },
        { itemID = 9999, name = "Not sold here", count = 4 },
    }, stock)
    T.eq(#lines, 2)
    T.eq(lines[1].count, 22)
    T.eq(lines[2].count, 3, "dye capped at the 3 left")
    T.eq(total, 22 * 100 + 3 * 350)
    CP.Buying.open = false
end)

T.test("buying skips anything gone or moved since the popup opened, and buys in stacks", function()
    local slots = merchant()
    local bought = {}
    World.onEnd(function() CP.Buying.ForgetPurse() end)
    World.patch("BuyMerchantItem", function(i, n) bought[#bought + 1] = ("%d:%d"):format(i, n or 1) end)
    local lines = CP.Buying.Price({
        { itemID = 2321, name = "Fine Thread", count = 45 },
        { itemID = 4340, name = "Gray Dye", count = 2 },
    }, CP.Buying.Stock())
    slots[2] = { id = 4289, info = { price = 50, stackCount = 1, numAvailable = 5, isPurchasable = true } }  -- dye slot changed
    CP.Buying.Buy(lines)
    T.eq(table.concat(bought, " "), "1:20", "the first purchase runs inside the click")
    T.advance(CP.Buying.STEP * 4)
    T.eq(table.concat(bought, " "), "1:20 1:20 1:5", "45 thread in stacks of 20, one per step; the changed dye slot is skipped")

    bought = {}
    CP.Buying.open = false
    CP.Buying.Buy(lines)
    T.eq(#bought, 0, "nothing once the merchant closes")
end)
