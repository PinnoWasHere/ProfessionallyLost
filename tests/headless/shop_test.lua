-- Shop tab and auction house purchase tracking.

local CP = ProfLost
local P = CP.Purchases
local MEDIUM, HEAVY = 2319, 4234

local function reset()
    CP.charDB.mail, CP.charDB.bought, CP.charDB.shopNeeds = nil, nil, nil
    World.patch("C_Item.GetItemCount", function() return 0 end)
end

T.test("a commodity purchase counts at once, before the mail is opened", function()
    reset()
    T.fire("COMMODITY_PURCHASED", MEDIUM, 20)
    T.eq(P.Bought(MEDIUM), 20)
    T.eq(P.Have(MEDIUM), 20)
    T.fire("COMMODITY_PURCHASED", MEDIUM, 5)
    T.eq(P.Have(MEDIUM), 25)
end)

T.test("a single-item purchase is read from its auction", function()
    reset()
    World.patch("C_AuctionHouse.GetAuctionInfoByID", function(id)
        return id == 77 and { itemKey = { itemID = HEAVY }, quantity = 3 } or nil
    end)
    T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
    T.eq(P.Have(HEAVY), 3)
    T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 78)
    T.eq(P.Have(HEAVY), 3, "an auction it can't read adds nothing")
end)

T.test("opening the mailbox takes over from the purchases, with no double count", function()
    reset()
    T.fire("COMMODITY_PURCHASED", MEDIUM, 20)
    World.patch("GetInboxNumItems", function() return 2 end)
    World.patch("GetInboxItem", function(i, a)
        if i == 1 and a == 1 then return "Medium Leather", MEDIUM, 0, 20 end
        if i == 2 and a == 1 then return "Medium Leather", MEDIUM, 0, 4 end
    end)
    T.fire("MAIL_SHOW")
    T.fire("MAIL_INBOX_UPDATE")
    T.eq(P.InMail(MEDIUM), 24, "20 bought plus 4 already there")
    T.eq(P.Bought(MEDIUM), 0)
    T.eq(P.Have(MEDIUM), 24)
    -- Taking the 20 out: bags have them, the mail doesn't.
    World.patch("C_Item.GetItemCount", function(id) return id == MEDIUM and 20 or 0 end)
    World.patch("GetInboxNumItems", function() return 1 end)
    World.patch("GetInboxItem", function(i, a) if i == 1 and a == 1 then return "Medium Leather", MEDIUM, 0, 4 end end)
    T.fire("MAIL_INBOX_UPDATE")
    T.eq(P.Have(MEDIUM), 24, "same total once looted")
    T.fire("MAIL_CLOSED")
end)

T.test("the Shop tab shows only in Buy-and-power-level", function()
    local collect = CP.db.collect
    CP.db.collect = true
    CP.Panel:Refresh()
    T.ok(not CP.Panel.tabs.shop.button:IsShown(), "hidden while collecting")
    CP.db.collect = false
    CP.Panel:Refresh()
    T.ok(CP.Panel.tabs.shop.button:IsShown(), "shown when buying")
    CP.db.collect = collect
    CP.Panel:Refresh()
end)

T.test("shop rows count what's left to buy and its cost", function()
    reset()
    T.fire("COMMODITY_PURCHASED", MEDIUM, 6)
    local guide = { items = { [MEDIUM] = { 200, false }, [2321] = { 100, true } } }
    local recipe = { name = "X", reagents = { { MEDIUM, 4 }, { 2321, 1 } } }
    local entries = { { kind = "craft", recipe = recipe, crafts = 5 }, { kind = "train", train = { fee = 500 } } }
    local price = function(_, item) return item and item[1] end
    local rows = CP.ShopTab.Rows(guide, entries, price)
    local medium, thread
    for _, r in ipairs(rows) do
        if r.itemID == MEDIUM then medium = r else thread = r end
    end
    T.eq(medium.need, 20)
    T.eq(medium.left, 14, "6 bought")
    T.eq(medium.mail, 6, "shows as on its way")
    T.ok(thread.vendor, "thread is vendor stock")
    local total = CP.Queue.Cost(guide, entries, rows, price)
    T.eq(total, 14 * 200 + 5 * 100 + 500)
end)

T.test("a purchase of a listed item says how far along it is", function()
    reset()
    CP.charDB.shopNeeds = { [MEDIUM] = 40 }
    local said
    local print0 = CP.Print
    CP.Print = function(_, msg) said = msg end
    T.fire("COMMODITY_PURCHASED", MEDIUM, 20)
    T.advance(2)   -- the line waits for the burst of purchases to end
    CP.Print = print0
    T.ok(said and said:find("20") and said:find("20 / 40"), tostring(said))
    said = nil
    CP.Print = function(_, msg) said = msg end
    T.fire("COMMODITY_PURCHASED", 9999, 1)
    CP.Print = print0
    T.eq(said, nil, "items off the list stay quiet")
end)

T.test("the Shop tab lists Tailoring's materials to the cap with a cost line", function()
    reset()
    local collect = CP.db.collect
    CP.db.collect = false
    World.patch("C_TradeSkillUI.GetBaseProfessionInfo", function()
        return { professionID = 197, professionName = "Tailoring", skillLevel = 52, skillModifier = 0, maxSkillLevel = 75 }
    end)
    World.patch("C_TradeSkillUI.GetChildProfessionInfo", function() return { professionID = 0 } end)
    World.patch("C_TradeSkillUI.GetAllRecipeIDs", function() return {} end)
    World.patch("C_TradeSkillUI.IsTradeSkillLinked", function() return false end)
    World.patch("C_TradeSkillUI.IsTradeSkillGuild", function() return false end)
    World.patch("C_TradeSkillUI.IsNPCCrafting", function() return false end)
    World.set(CP.Professions, "tradeSkillOpen", true)   -- Tailoring's window is open
    local tab = CP.Panel.tabs.shop
    tab.refresh(tab.content)
    T.ok(CP.charDB.shopNeeds and next(CP.charDB.shopNeeds) ~= nil, "the list was built and remembered")
    CP.db.collect = collect
end)
