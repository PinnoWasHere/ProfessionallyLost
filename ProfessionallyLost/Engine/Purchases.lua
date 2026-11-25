local _, CP = ...
if CP.stopped then return end

-- What the player has of an item, counting auction house purchases on their way.
-- Auction purchases go to the mailbox, so "have" is bags and bank, plus the mailbox
-- as last seen, plus what was bought since. The game reports each purchase with its
-- item and quantity (COMMODITY_PURCHASED for stackable goods, a completed purchase
-- with its auction for single items), which is surer than reading chat lines.

local Purchases = {}
CP.Purchases = Purchases

local MAX_ATTACHMENTS = 16   -- attachments a received mail can carry

local listeners = {}

local function db()
    CP.charDB.mail = CP.charDB.mail or {}
    CP.charDB.bought = CP.charDB.bought or {}
    return CP.charDB
end

function Purchases.InMail(itemID)
    return CP.charDB and CP.charDB.mail and CP.charDB.mail[itemID] or 0
end

function Purchases.Bought(itemID)
    return CP.charDB and CP.charDB.bought and CP.charDB.bought[itemID] or 0
end

-- Bags and bank, plus the mailbox, plus purchases not yet seen in the mailbox.
function Purchases.Have(itemID)
    return (C_Item.GetItemCount(itemID, true) or 0) + Purchases.InMail(itemID) + Purchases.Bought(itemID)
end

-- `fn(itemID, quantity)` runs after each purchase is counted.
function Purchases.OnPurchase(fn)
    listeners[#listeners + 1] = fn
end

function Purchases.Record(itemID, quantity)
    if not itemID or not quantity or quantity <= 0 then return end
    local d = db()
    d.bought[itemID] = (d.bought[itemID] or 0) + quantity
    for _, fn in ipairs(listeners) do fn(itemID, quantity) end
end

-- Count the mailbox as it's listed now. Purchases counted so far are in it, so they
-- stop counting on their own. The game lists only the first mails (numItems) of the
-- totalItems the box holds. While some are unlisted a purchase may sit in them, so the
-- purchases stay counted until a scan lists the whole box.
function Purchases.ScanMail()
    local d, mail = db(), {}
    local listed, total = GetInboxNumItems()
    listed = listed or 0
    for i = 1, listed do
        for a = 1, MAX_ATTACHMENTS do
            local _, itemID, _, count = GetInboxItem(i, a)
            if itemID and count and count > 0 then mail[itemID] = (mail[itemID] or 0) + count end
        end
    end
    d.mail = mail
    if (total or listed) <= listed then d.bought = {} end
end

CP:On("COMMODITY_PURCHASED", function(_, itemID, quantity)
    Purchases.Record(itemID, quantity)
end)

CP:On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, auctionID)
    local info = C_AuctionHouse.GetAuctionInfoByID(auctionID)
    local key = info and info.itemKey
    if key and key.itemID then Purchases.Record(key.itemID, info.quantity or 1) end
end)

local open = false
CP:On("MAIL_SHOW", function() open = true end)
CP:On("MAIL_CLOSED", function() open = false end)
CP:On("MAIL_INBOX_UPDATE", function()
    if open then
        Purchases.ScanMail()
        CP:Soon("purchases", function()
            if CP.Panel then CP.Panel:Refresh() end
            if CP.GatherList then CP.GatherList.Changed() end
        end)
    end
end)
