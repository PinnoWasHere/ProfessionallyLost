-- auctioneerworld: MOCK of Auctioneer's public API (AucAdvanced.API), as ProfLost reads it.
-- Interface only; none of its code.
--
-- Read from Auctioneer 4.0.11 as installed (Auc-Advanced/, its Auc-Stat-* modules):
--   * [code] AucAdvanced.API.GetMarketValue(itemLink, serverKey, confidence) -> copper, seen,
--     modules, or nil (CoreAPI.lua:125-151). It can raise an error (:222, :242).
--   * [code] "item:<id>" is read as item <id> (CoreAPI.lua:929-955, GetStoreKeyFromLinkB :1163-1167);
--     a number goes through GetItemInfo first and is nil until the item is cached (:127-128).
--   * [code] A nil serverKey is the player's own auction house, set only once Auctioneer is active
--     after the first PLAYER_ENTERING_WORLD (CoreServers.lua:188, 299-302; CoreMain.lua:719); until
--     then the answer is nil.
--   * [code] AucAdvanced.SendProcessorMessage(msg, ...) tells its modules: "gameactive" once it is
--     active (CoreMain.lua:722), "scanstats" once a scan's prices are stored (CoreScan.lua:2097),
--     which can be after the auction house closed. Its callers look it up on AucAdvanced each time.
-- Guesses:
--   * [guess] Prices are what the test sets; its statistics modules are not modelled.
--
--   AuctioneerWorld.begin({ prices = { [2318] = 42 } })
--   AuctioneerWorld.begin({ ..., active = false }), then AuctioneerWorld.Message("gameactive")
--   AuctioneerWorld.Message("scanstats"): a scan's prices are stored
--   AuctioneerWorld.state.asked: every link asked

AuctioneerWorld = {}

local S

function AuctioneerWorld.begin(spec)
    spec = spec or {}
    S = { prices = {}, asked = {}, active = spec.active ~= false, messages = {} }
    AuctioneerWorld.state = S
    for id, copper in pairs(spec.prices or {}) do S.prices[id] = copper end

    local API = {}
    function API.GetMarketValue(itemLink)
        S.asked[#S.asked + 1] = itemLink
        if not S.active then return nil end
        local id = type(itemLink) == "string" and tonumber(itemLink:match("item:(%d+)"))
        if not id then return nil end
        local copper = S.prices[id]
        if not copper then return nil end
        return copper, 3, 2
    end

    local auc = { API = API }
    function auc.SendProcessorMessage(msg) S.messages[#S.messages + 1] = msg end
    World.set(_G, "AucAdvanced", auc)
end

-- Auctioneer sends `msg` to its modules, as its own code calls it.
function AuctioneerWorld.Message(msg, ...)
    if msg == "gameactive" then S.active = true end
    AucAdvanced.SendProcessorMessage(msg, ...)
end
