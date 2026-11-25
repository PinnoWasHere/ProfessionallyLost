-- ahworld: the auction house, open or shut, its window, its answers to searches and its
-- full auction list.
--
-- Modelled on the game's C_AuctionHouse:
--   * [docs] Talking to an auctioneer fires AUCTION_HOUSE_SHOW; leaving, AUCTION_HOUSE_CLOSED.
--     The game's window, AuctionHouseFrame, shows while the auction house is open.
--   * [docs] MakeItemKey builds { itemID, itemLevel, itemSuffix, battlePetSpeciesID }.
--     GetItemKeyInfo answers { itemID, isCommodity } once the item's data is cached,
--     nil before; the cache filling fires ITEM_KEY_ITEM_INFO_RECEIVED(itemID).
--   * [docs] SendSearchQuery sends a search; the server answers later, one at a time, with
--     COMMODITY_SEARCH_RESULTS_UPDATED(itemID) for commodities or
--     ITEM_SEARCH_RESULTS_UPDATED(itemKey) for the rest. Results are read with
--     GetNum/Get...SearchResult(s)Info: commodity rows carry unitPrice and quantity,
--     item rows buyoutAmount (nil for bid only), bidAmount and quantity.
--   * [docs] IsThrottledMessageSystemReady is false while the server holds searches back.
--   * [docs] ReplicateItems asks for every auction at once; REPLICATE_ITEM_LIST_UPDATE says it
--     came. GetNumReplicateItems counts it (0 before), GetReplicateItemInfo(index), 0-based,
--     answers name, texture, count, qualityID, usable, level, levelType, minBid,
--     minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner,
--     ownerFullName, saleStatus, itemID, hasAllInfo (the API docs, forever).
-- Guesses:
--   * [guess] Searches and the full list are answered only when the test says (Answer, SendList),
--     never on their own.
--   * [guess] Rows come back in the order the test lists them; the sort asked for isn't applied.
--   * [guess] A full-list row may come with no itemID at first (blank) and fill in later (Fill).
--   * [guess] A row whose item the client hasn't cached (uncached) answers its itemID, count and
--     buyout, no name, and hasAllInfo false until the item loads (Load).
--   * [guess] GetRealmName and GetServerTime answer the scene's realm and clock.
--   * [guess] The game's window draws at full alpha unless parked (Park), as DaylightMogul's
--     Windows/Dock.lua parks it under its own window.
--
--   AHWorld.begin({ listings = { [2319] = { rows = { { unitPrice = 150, quantity = 20 } } },
--                                [4234] = { commodity = false, rows = { ... } },
--                                [2318] = { uncached = true } },
--                   replicate = { { itemID = 2319, count = 20, buyout = 3000 }, { itemID = 2318, blank = true, ... } },
--                   realm = "Testrealm", now = 1800000000 })
--   AHWorld.Open() / Close() / Answer() / Cache(itemID) / SetReady(bool) / SendList() / Fill(index) / Load(index)
--   AHWorld.AddRows(rows) / SetNow(t) / Park(bool); AHWorld.state.sent, .asks, .reads; AHWorld.window

AHWorld = {}

local S

local function listing(id) return S.listings[id] or { rows = {} } end

local function install()
    local AH = "C_AuctionHouse."

    -- [guess] The scene names the realm and the clock; the game's own answers are not modelled.
    World.patch("GetRealmName", function() return S.realm end)
    World.patch("GetServerTime", function() return S.now end)

    -- [docs] MakeItemKey and GetItemKeyInfo, as C_AuctionHouse documents their tables.
    World.patch(AH .. "MakeItemKey", function(id, level, suffix, pet)
        return { itemID = id, itemLevel = level or 0, itemSuffix = suffix or 0, battlePetSpeciesID = pet or 0 }
    end)
    World.patch(AH .. "GetItemKeyInfo", function(key)
        local l = listing(key.itemID)
        if l.uncached then return nil end
        return { itemID = key.itemID, isCommodity = l.commodity ~= false }
    end)

    -- [docs] Searches wait while the throttled message system is not ready.
    World.patch(AH .. "IsThrottledMessageSystemReady", function() return S.ready end)
    World.patch(AH .. "SendSearchQuery", function(key, sorts)
        if not S.open then return end
        S.sent[#S.sent + 1] = { id = key.itemID, key = key, sorts = sorts, at = GetTime() }
        S.pending[#S.pending + 1] = key
    end)

    -- [docs] Search results by item, commodity or item key; [guess] the order is the order the test listed.
    World.patch(AH .. "GetNumCommoditySearchResults", function(id) return #listing(id).rows end)
    World.patch(AH .. "GetCommoditySearchResultInfo", function(id, i) return listing(id).rows[i] end)
    World.patch(AH .. "GetNumItemSearchResults", function(key) return #listing(key.itemID).rows end)
    World.patch(AH .. "GetItemSearchResultInfo", function(key, i) return listing(key.itemID).rows[i] end)

    -- [docs] The player's GUID carries the server id; realm names answer "" on Forever 1.60.1
    -- (owner's in-game /dump, 2026-11-24: "Player-6935-007319DC").
    World.patch("UnitGUID", function(unit)
        if unit == "player" then return "Player-6935-007319DC" end
        return World.PASS
    end)

    -- [docs] ReplicateItems and the replicate list getters (the API docs, forever).
    World.patch(AH .. "ReplicateItems", function()
        if not S.open then return end
        S.asks[#S.asks + 1] = GetTime()
    end)
    World.patch(AH .. "GetNumReplicateItems", function() return S.listSent and #S.replicate or 0 end)
    World.patch(AH .. "GetReplicateItemInfo", function(index)
        S.reads = S.reads + 1
        local r = S.listSent and S.replicate[index + 1]
        if not r then return nil end
        local id = not r.blank and r.itemID or nil
        local all = id ~= nil and not r.uncached
        return all and "Item " .. tostring(r.itemID) or nil, 134400, r.count, 1, true, 1, nil, 0, 0, r.buyout or 0, 0,
            nil, nil, nil, nil, 0, id, all
    end)
end

function AHWorld.begin(spec)
    spec = spec or {}
    S = { listings = spec.listings or {}, realm = spec.realm or "Testrealm", now = spec.now or 1800000000,
          ready = true, open = false, sent = {}, pending = {}, replicate = spec.replicate or {}, asks = {},
          listSent = false, reads = 0 }
    AHWorld.state = S
    install()
    -- A named frame sets its global: put the old one back, so the frame leaves with the world.
    local before = rawget(_G, "AuctionHouseFrame")
    AHWorld.window = AHWorld.window or CreateFrame("Frame", "AuctionHouseFrame", UIParent)
    rawset(_G, "AuctionHouseFrame", before)
    AHWorld.window:SetSize(800, 538)
    AHWorld.window:Hide()
    S.alpha = 1

    -- [guess] The window draws at full alpha unless parked.
    World.set(AHWorld.window, "GetAlpha", function() return S.alpha end)
    World.set(AHWorld.window, "GetEffectiveAlpha", function() return S.alpha end)
    World.set(_G, "AuctionHouseFrame", AHWorld.window)
    World.onEnd(function() if S.open then AHWorld.Close() end end)
end

function AHWorld.Open()
    S.open = true
    AHWorld.window:Show()
    T.fire("AUCTION_HOUSE_SHOW")
end

function AHWorld.Close()
    S.open, S.pending, S.listSent = false, {}, false
    AHWorld.window:Hide()
    T.fire("AUCTION_HOUSE_CLOSED")
end

-- The server answers the oldest search still waiting. Returns its item, or nil.
function AHWorld.Answer()
    local key = table.remove(S.pending, 1)
    if not key then return nil end
    if listing(key.itemID).commodity == false then
        T.fire("ITEM_SEARCH_RESULTS_UPDATED", key)
    else
        T.fire("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID)
    end
    return key.itemID
end

-- The item's data arrives in the cache.
function AHWorld.Cache(id)
    local l = S.listings[id] or { rows = {} }
    S.listings[id] = l
    l.uncached = nil
    T.fire("ITEM_KEY_ITEM_INFO_RECEIVED", id)
end

function AHWorld.SetReady(ready) S.ready = ready end

function AHWorld.SetListing(id, l) S.listings[id] = l end

-- The server sends the full list asked for.
function AHWorld.SendList()
    S.listSent = true
    T.fire("REPLICATE_ITEM_LIST_UPDATE")
end

-- A blank row (0-based) gets its item.
function AHWorld.Fill(index) S.replicate[index + 1].blank = nil end

-- An uncached row's item (0-based) finishes loading.
function AHWorld.Load(index) S.replicate[index + 1].uncached = nil end

-- More rows arrive at the end of the list.
function AHWorld.AddRows(rows)
    for _, r in ipairs(rows) do S.replicate[#S.replicate + 1] = r end
end

function AHWorld.SetNow(t) S.now = t end

-- DaylightMogul parks the game's window out of sight at alpha 0 while its own stands in.
function AHWorld.Park(on) S.alpha = on and 0 or 1 end
