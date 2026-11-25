-- The vendor world (tests/world/vendorworld.lua): a merchant window and the purse, as
-- its header describes them. Merchant entries are made up, so ProfLost's VendorWatch, which
-- remembers sold-out patterns for the session, never matches one.

local THREAD, SPICE, PATTERN = 2320, 2678, 6401
local SELLER, OTHER = 990001, 990002

-- Every event the world fires, in order, as a frame hears it.
local function listen()
    local heard = {}
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "PLAYER_MONEY", "BAG_UPDATE",
                         "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event, ...)
        heard[#heard + 1] = { event = event, shown = MerchantFrame:IsShown(), ... }
    end)
    World.onEnd(function() f:UnregisterAllEvents() end)
    return heard
end

local function names(heard)
    local out = {}
    for _, h in ipairs(heard) do out[#out + 1] = h.event end
    return out
end

local function scene(money, spec)
    CraftWorld.begin({ professions = {} })
    spec = spec or {}
    spec.money = money
    VendorWorld.begin(spec)
end

local function seller(items)
    return { entry = SELLER, name = "Test seller", items = items or {
        { item = THREAD, price = 10 },
        { item = SPICE, price = 50, stack = 5 },
        { item = PATTERN, price = 1000, limit = 1 },
    } }
end

-- The functions the world answers, as found: another file's stubs may stand there.
local function merchantCalls()
    return { GetMerchantNumItems, GetMerchantItemID, GetMerchantItemLink, C_MerchantFrame.GetItemInfo,
             GetMerchantItemMaxStack, BuyMerchantItem, CloseMerchant, GetMoney, UnitGUID }
end

T.test("the world does nothing until begin(), and the scene's end puts back what it found", function()
    local found = merchantCalls()
    T.eq(VendorWorld.state.begun, nil, "not begun")
    T.eq(rawget(_G, "MerchantFrame"), nil, "no MerchantFrame")
    scene(5000)
    VendorWorld.Open(seller())
    T.ok(GetMerchantNumItems ~= found[1] and GetMoney ~= found[8], "begun, the world answers")
    World.finish()
    T.eq(merchantCalls(), found, "every function as it was")
    T.eq(rawget(_G, "MerchantFrame"), nil)
    T.eq(VendorWorld.state.begun, nil)
end)

T.test("opening shows MerchantFrame, then MERCHANT_SHOW; the slots answer as the client does", function()
    scene(5000)
    local heard = listen()
    VendorWorld.Open(seller())
    T.eq(names(heard), { "MERCHANT_SHOW" })
    T.ok(heard[1].shown, "MerchantFrame already shows when MERCHANT_SHOW is heard")
    T.eq(GetMerchantNumItems(), 3)
    T.eq(GetMerchantItemID(1), THREAD)
    T.ok(GetMerchantItemLink(1):find("|Hitem:" .. THREAD .. ":", 1, true) ~= nil, "an item link")
    local info = C_MerchantFrame.GetItemInfo(1)
    T.eq({ info.price, info.stackCount, info.numAvailable, info.isPurchasable, info.hasExtendedCost },
        { 10, 1, -1, true, false }, "unlimited stock is -1")
    T.eq(C_MerchantFrame.GetItemInfo(3).numAvailable, 1, "limited stock is what is left")
    T.eq(GetMerchantItemMaxStack(1), 20)
    T.eq(UnitGUID("npc"), "Creature-0-0-0-0-990001-0")
    T.eq(select(6, strsplit("-", UnitGUID("npc"))), "990001", "the entry where VendorWatch reads it")
end)

T.test("closing hides MerchantFrame, then MERCHANT_CLOSED; the slots empty", function()
    scene(5000)
    VendorWorld.Open(seller())
    local heard = listen()
    VendorWorld.Close()
    T.eq(names(heard), { "MERCHANT_CLOSED" })
    T.ok(not heard[1].shown, "MerchantFrame hidden when MERCHANT_CLOSED is heard")
    T.eq(GetMerchantNumItems(), 0)
    T.ok(UnitGUID("npc") ~= "Creature-0-0-0-0-990001-0", "no merchant's GUID once closed")
end)

T.test("a purchase takes the copper and fills the bags: PLAYER_MONEY, BAG_UPDATE, BAG_UPDATE_DELAYED, MERCHANT_UPDATE", function()
    scene(5000)
    VendorWorld.Open(seller())
    local heard = listen()
    BuyMerchantItem(1, 3)
    T.eq(GetMoney(), 5000 - 30)
    T.eq(VendorWorld.state.spent, 30)
    T.eq(CraftWorld.Bag(THREAD), 3)
    T.eq(names(heard), { "PLAYER_MONEY", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "MERCHANT_UPDATE" })
    T.eq(heard[2][1], 0, "BAG_UPDATE names the backpack")
    T.eq(VendorWorld.state.bought[1], { item = THREAD, count = 3, cost = 30 })
end)

T.test("no quantity buys one stack, at a stack's price", function()
    scene(5000)
    VendorWorld.Open(seller())
    BuyMerchantItem(2)
    T.eq(CraftWorld.Bag(SPICE), 5)
    T.eq(GetMoney(), 5000 - 50)
    BuyMerchantItem(2, 7)
    T.eq(CraftWorld.Bag(SPICE), 15, "7 items are two whole stacks")
    T.eq(GetMoney(), 5000 - 150)
end)

T.test("without the money a purchase buys nothing and the game says why", function()
    scene(500)
    VendorWorld.Open(seller())
    local heard = listen()
    BuyMerchantItem(3)
    T.eq(GetMoney(), 500)
    T.eq(CraftWorld.Bag(PATTERN), 0)
    T.eq(names(heard), { "UI_ERROR_MESSAGE" })
    T.eq(heard[1][2], "You don't have enough money.")
    T.eq(VendorWorld.state.refused[1].item, PATTERN)
    T.eq(VendorWorld.Left(SELLER, PATTERN), 1, "the stock is untouched")
end)

T.test("limited stock runs out, drops off the list, and stays out until a restock", function()
    scene(50000)
    VendorWorld.Open(seller())
    BuyMerchantItem(3)
    T.eq(CraftWorld.Bag(PATTERN), 1)
    T.eq(VendorWorld.Left(SELLER, PATTERN), 0)
    T.eq(GetMerchantNumItems(), 2, "the sold-out pattern is not listed")
    T.eq(VendorWorld.Listed(PATTERN), nil)
    VendorWorld.Close()
    VendorWorld.Open(seller())
    T.eq(VendorWorld.Listed(PATTERN), nil, "still gone at the next visit")
    local heard = listen()
    VendorWorld.Restock(SELLER)
    T.eq(names(heard), { "MERCHANT_UPDATE" })
    T.eq(VendorWorld.Listed(PATTERN), 3)
    T.eq(C_MerchantFrame.GetItemInfo(3).numAvailable, 1)
end)

T.test("stock is kept per merchant: another one's limited item is its own", function()
    scene(50000)
    VendorWorld.Open(seller())
    BuyMerchantItem(3)
    VendorWorld.Open({ entry = OTHER, name = "Another", items = { { item = PATTERN, price = 900, limit = 2 } } })
    T.eq(VendorWorld.Left(OTHER, PATTERN), 2)
    T.eq(GetMerchantNumItems(), 1)
    T.eq(UnitGUID("npc"), "Creature-0-0-0-0-990002-0")
end)

T.test("soldOut = listed keeps a sold-out item on the list at numAvailable 0, and it buys nothing", function()
    scene(50000, { soldOut = "listed" })
    VendorWorld.Open(seller())
    BuyMerchantItem(3)
    T.eq(GetMerchantNumItems(), 3)
    T.eq(C_MerchantFrame.GetItemInfo(3).numAvailable, 0)
    BuyMerchantItem(3)
    T.eq(CraftWorld.Bag(PATTERN), 1)
    T.eq(VendorWorld.state.refused[1].why, "sold out")
end)

T.test("a fee leaves the purse with PLAYER_MONEY; more than the purse holds is refused", function()
    scene(1000)
    local heard = listen()
    T.ok(VendorWorld.Spend(400))
    T.eq(GetMoney(), 600)
    T.eq(names(heard), { "PLAYER_MONEY" })
    T.ok(not VendorWorld.Spend(601))
    T.eq(GetMoney(), 600)
    T.eq(VendorWorld.state.spent, 400)
end)

T.test("the scene's end closes an open merchant, so ProfLost's Buy sees it go", function()
    scene(1000)
    VendorWorld.Open(seller())
    T.ok(ProfLost.Buying.open, "ProfLost heard MERCHANT_SHOW")
    World.finish()
    T.ok(not ProfLost.Buying.open, "and MERCHANT_CLOSED")
    T.eq(rawget(_G, "MerchantFrame"), nil, "MerchantFrame went with the scene")
end)
