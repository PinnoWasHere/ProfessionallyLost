-- vendorworld: a merchant window and the character's purse, as the client presents them.
--
-- Modelled on what the game shows. Every name and payload is in the Forever client's API
-- documentation (client-docs, build 70790); shapes it leaves out come from the wiki:
--   * [docs] The functions ProfLost calls (UI/Buying.lua, UI/VendorWatch.lua): GetMerchantNumItems,
--     GetMerchantItemID, GetMerchantItemLink, C_MerchantFrame.GetItemInfo,
--     GetMerchantItemMaxStack, BuyMerchantItem, GetMoney; CloseMerchant ends the visit.
--   * [docs] C_MerchantFrame.GetItemInfo(i) gives a MerchantItemInfo (client-docs): name,
--     texture, price (copper for one stack), stackCount, numAvailable, isPurchasable,
--     isUsable, hasExtendedCost. numAvailable is -1 for unlimited stock (wiki,
--     GetMerchantItemInfo), else what is left.
--   * [docs] GetMoney() is the purse in copper (client-docs).
--   * [docs] UnitGUID("npc") is the open merchant's GUID, "Creature-0-0-0-0-<entry>-0" (wiki,
--     GUID); "" while no NPC is open (the harness stub's answer).
--   * [docs] GetMerchantItemLink(i) is an item link "|Hitem:<id>:...|h[name]|h" (wiki).
-- Guesses:
--   * [guess] Opening: the game's MerchantFrame shows, then MERCHANT_SHOW (Blizzard's MerchantFrame
--     handles the event first and shows itself, then addons hear it). Closing:
--     MerchantFrame hides, then MERCHANT_CLOSED. The frame belongs to the world; another
--     test's MerchantFrame comes back when the scene ends.
--   * [guess] A purchase: the copper leaves the purse, PLAYER_MONEY; the items reach the bags
--     (CraftWorld.SetBag), BAG_UPDATE 0 then BAG_UPDATE_DELAYED; then MERCHANT_UPDATE.
--   * [guess] BuyMerchantItem(i) with no quantity buys one stack; with a quantity, that many items,
--     in whole stacks, at the price a stack costs.
--   * [guess] A purchase that costs more than the purse holds buys nothing: UI_ERROR_MESSAGE with
--     ERR_NOT_ENOUGH_MONEY's text. A slot that is sold out, or not there, buys nothing.
--   * [guess] Limited stock: `limit` on an item is its stock at the first visit. It is kept per
--     merchant across visits and refills only on Restock(entry). A sold-out limited item
--     drops off the list (ProfLost's VendorWatch reads a missing pattern as sold out);
--     begin({ soldOut = "listed" }) keeps it listed with numAvailable 0 instead.
--   * [guess] GetMerchantItemMaxStack(i) is the item's `maxStack`, else 20.
-- Nothing happens until begin() is called; every test that loads the world but not
-- this scene sees the harness stubs.
-- Needs CraftWorld.begin first: bought items go to its bags.
--
--   VendorWorld.begin({ money = 100000000, soldOut = "hidden" | "listed", from = snapshot })
--   VendorWorld.Snapshot(): the purse, what was spent and each merchant's limited stock left;
--   begin({ from = it }) starts there, with no merchant open
--   VendorWorld.Open({ entry = 3364, name = "Borya", items = { { item, price, stack = 1, limit, maxStack } } })
--   VendorWorld.Close() / Restock(entry) / Left(entry, item) / Listed(item) / Slots()
--   VendorWorld.Money() / SetMoney(n) / Spend(n) -> false when short
--   VendorWorld.state: { begun, money, spent, open, bought = { { item, count, cost } }, refused = { { item, why } }, events }

VendorWorld = { state = {} }

local S

local ERR_NO_MONEY = "You don't have enough money."
local ERR_TYPE = 1   -- UI_ERROR_MESSAGE's errorType for it (guess; the docs give no number)

local function seen(event)
    S.events[#S.events + 1] = event
    return event
end

local function stockOf(entry)
    S.stock[entry] = S.stock[entry] or {}
    return S.stock[entry]
end

-- The open merchant's slots in list order: { item, price, stack, left, maxStack }.
local function slots()
    local out = {}
    local m = S.open
    if not m then return out end
    local stock = stockOf(m.entry)
    for _, it in ipairs(m.items) do
        local left = it.limit and stock[it.item] or nil
        if not (left == 0 and S.soldOut ~= "listed") then
            out[#out + 1] = { item = it.item, price = it.price or 0, stack = math.max(1, it.stack or 1), left = left,
                              maxStack = it.maxStack or 20 }
        end
    end
    return out
end
VendorWorld.Slots = slots

local function nameOf(item)
    return WorldData and WorldData.items and WorldData.items[item] or ("item " .. item)
end

local function install()

    -- [docs] GetMoney is the purse in copper.
    World.patch("GetMoney", function() return S.money end)

    -- [docs] The merchant list calls ProfLost reads, by slot index.
    World.patch("GetMerchantNumItems", function() return #slots() end)
    World.patch("GetMerchantItemID", function(i)
        local s = slots()[i]
        return s and s.item or nil
    end)
    World.patch("GetMerchantItemLink", function(i)
        local s = slots()[i]
        return s and ("|cffffffff|Hitem:%d::::::::::::::::|h[%s]|h|r"):format(s.item, nameOf(s.item)) or nil
    end)

    -- [docs] MerchantItemInfo; numAvailable is -1 for unlimited stock (wiki).
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        local s = slots()[i]
        if not s then return nil end
        return { name = nameOf(s.item), texture = 134939, price = s.price, stackCount = s.stack,
                 numAvailable = s.left or -1, isPurchasable = true, isUsable = true, hasExtendedCost = false,
                 isQuestStartItem = false }
    end)

    -- [guess] The item's maxStack, else 20.
    World.patch("GetMerchantItemMaxStack", function(i)
        local s = slots()[i]
        return s and s.maxStack or 0
    end)

    -- [guess] A purchase takes copper and fills the bags as the header's purchase rule says.
    World.patch("BuyMerchantItem", function(i, quantity) VendorWorld.Buy(i, quantity) end)
    World.patch("CloseMerchant", function() VendorWorld.Close() end)

    -- [docs] UnitGUID("npc") is the open merchant's GUID (wiki, GUID); the harness stub answers the rest.
    World.patch("UnitGUID", function(unit)
        if unit == "npc" and S.open then return ("Creature-0-0-0-0-%d-0"):format(S.open.entry) end
        return World.PASS
    end)
end

function VendorWorld.begin(spec)
    spec = spec or {}
    S = { begun = true, money = spec.money or 0, spent = 0, open = nil, stock = {}, items = {}, bought = {},
          refused = {}, events = {}, soldOut = spec.soldOut or "hidden" }
    local from = spec.from
    if from then
        S.money, S.spent, S.soldOut = from.money, from.spent, from.soldOut or S.soldOut
        for entry, stock in pairs(from.stock or {}) do
            S.stock[entry] = {}
            for item, n in pairs(stock) do S.stock[entry][item] = n end
        end
    end
    VendorWorld.state = S
    install()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    S.frame = frame

    -- [guess] The MerchantFrame belongs to the world; the previous one comes back when the scene ends.
    World.set(_G, "MerchantFrame", frame)
    World.onEnd(function()
        if S.open then VendorWorld.Close() end
        VendorWorld.state = {}
    end)
end

function VendorWorld.Snapshot()
    local stock = {}
    for entry, items in pairs(S.stock) do
        stock[entry] = {}
        for item, n in pairs(items) do stock[entry][item] = n end
    end
    return { money = S.money, spent = S.spent, soldOut = S.soldOut, stock = stock }
end

function VendorWorld.Money() return S.money end

function VendorWorld.SetMoney(n)
    S.money = n
    T.fire(seen("PLAYER_MONEY"))
end

-- Takes `copper` from the purse (a trainer's fee). False, and nothing taken, when short.
function VendorWorld.Spend(copper)
    if copper > S.money then return false end
    S.money, S.spent = S.money - copper, S.spent + copper
    T.fire(seen("PLAYER_MONEY"))
    return true
end

-- Opens `merchant`'s window: { entry, name, items = { { item, price, stack, limit, maxStack } } }.
function VendorWorld.Open(merchant)
    if S.open then VendorWorld.Close() end
    local stock = stockOf(merchant.entry)
    S.items[merchant.entry] = merchant.items
    for _, it in ipairs(merchant.items) do
        if it.limit and stock[it.item] == nil then stock[it.item] = it.limit end
    end
    S.open = merchant
    S.frame:Show()
    T.fire(seen("MERCHANT_SHOW"))
end

function VendorWorld.Close()
    if not S.open then return end
    S.open = nil
    S.frame:Hide()
    T.fire(seen("MERCHANT_CLOSED"))
end

-- Limited stock back to each item's `limit`, for merchant `entry`.
function VendorWorld.Restock(entry)
    local stock = stockOf(entry)
    for _, it in ipairs(S.items[entry] or {}) do
        if it.limit then stock[it.item] = it.limit end
    end
    if S.open and S.open.entry == entry then T.fire(seen("MERCHANT_UPDATE")) end
end

-- What is left of limited item `item` at merchant `entry`; nil when unlimited or unseen.
function VendorWorld.Left(entry, item) return stockOf(entry)[item] end

-- The open merchant's slot that lists `item`, else nil.
function VendorWorld.Listed(item)
    for i, s in ipairs(slots()) do
        if s.item == item then return i end
    end
end

local function refuse(item, why, err)
    S.refused[#S.refused + 1] = { item = item, why = why }
    if err then T.fire(seen("UI_ERROR_MESSAGE"), ERR_TYPE, err) end
end

-- BuyMerchantItem(i, quantity): see the header.
function VendorWorld.Buy(i, quantity)
    if not S.open then return refuse(nil, "no merchant open") end
    local s = slots()[i]
    if not s then return refuse(nil, "no slot " .. tostring(i)) end
    local stacks = quantity and math.ceil(quantity / s.stack) or 1
    if s.left and s.left < stacks then
        if s.left == 0 then return refuse(s.item, "sold out") end
        stacks = s.left
    end
    local cost = stacks * s.price
    if cost > S.money then
        return refuse(s.item, ("costs %d, the purse holds %d"):format(cost, S.money),
            rawget(_G, "ERR_NOT_ENOUGH_MONEY") or ERR_NO_MONEY)
    end
    local count = stacks * s.stack
    S.money, S.spent = S.money - cost, S.spent + cost
    if s.left then stockOf(S.open.entry)[s.item] = s.left - stacks end
    S.bought[#S.bought + 1] = { item = s.item, count = count, cost = cost }
    T.fire(seen("PLAYER_MONEY"))
    T.fire(seen("BAG_UPDATE"), 0)
    S.events[#S.events + 1] = "BAG_UPDATE_DELAYED"
    CraftWorld.SetBag(s.item, CraftWorld.Bag(s.item) + count)
    T.fire(seen("MERCHANT_UPDATE"))
end
