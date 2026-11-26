-- auctionatorworld: MOCK of Auctionator's public API (Auctionator.API.v1), as its
-- Source/API/v1/README.md and the v1 files of Auctionator 354 describe it. Interface only;
-- none of its code.
--
-- Modelled from those files:
--   * [docs] GetAuctionPriceByItemID(callerID, itemID) -> the last scanned price in copper, or nil.
--   * [docs] GetAuctionAgeByItemID(callerID, itemID) -> whole days since the item was last seen,
--     or nil (never seen, or over 21 days).
--   * [docs] RegisterForDBUpdate(callerID, callback): callback() after a search's prices are
--     processed or a full scan ends. Only the ModernAH and LegacyAH builds define it
--     (`callback = false` leaves it out).
--   * [docs] Every call raises an error for a callerID that is not a non-empty string, and for an
--     itemID that is not a number.
-- Guesses:
--   * [guess] Prices and ages are what the test sets; its database and realms are not modelled.
--
--   AuctionatorWorld.begin({ prices = { [2318] = 42 }, ages = { [2318] = 1 }, callback = true })
--   AuctionatorWorld.SetPrice(item, copper, days) / Updated(); AuctionatorWorld.state.callers

AuctionatorWorld = {}

local S

local function verify(callerID, itemID)
    if type(callerID) ~= "string" or callerID == "" then
        error("Invalid callerID. Use the name of your add-on.")
    end
    if itemID ~= nil and type(itemID) ~= "number" then error("Usage: itemID must be a number") end
    S.callers[callerID] = true
end

function AuctionatorWorld.begin(spec)
    spec = spec or {}
    S = { prices = {}, ages = {}, callbacks = {}, callers = {} }
    AuctionatorWorld.state = S
    for id, copper in pairs(spec.prices or {}) do S.prices[id] = copper end
    for id, days in pairs(spec.ages or {}) do S.ages[id] = days end

    local v1 = {}
    function v1.GetAuctionPriceByItemID(callerID, itemID)
        verify(callerID, itemID)
        return S.prices[itemID]
    end
    function v1.GetAuctionAgeByItemID(callerID, itemID)
        verify(callerID, itemID)
        return S.ages[itemID]
    end
    if spec.callback ~= false then
        function v1.RegisterForDBUpdate(callerID, callback)
            verify(callerID)
            if type(callback) ~= "function" then error("Usage: callback must be a function") end
            S.callbacks[#S.callbacks + 1] = callback
        end
    end

    -- [docs] Auctionator.API.v1 as its README.md and v1 files describe it.
    World.set(_G, "Auctionator", { API = { v1 = v1 } })
end

function AuctionatorWorld.SetPrice(itemID, copper, days)
    S.prices[itemID] = copper
    S.ages[itemID] = days
end

-- A search or full scan finished: every RegisterForDBUpdate callback runs.
function AuctionatorWorld.Updated()
    for _, fn in ipairs(S.callbacks) do fn() end
end
