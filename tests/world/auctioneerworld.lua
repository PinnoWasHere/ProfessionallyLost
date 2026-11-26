-- auctioneerworld: MOCK of Auctioneer's public API (AucAdvanced.API), as ProfLost reads it.
-- Interface only; none of its code. Auctioneer is not installed on the owner's client, so
-- nothing here was read from Auctioneer itself.
--
-- Modelled from Glowey's Recipes 3.3.0-beta3 PriceSources.lua, whose header cites Auctioneer
-- 4.0.9's source (folder Auc-Advanced):
--   * [docs] AucAdvanced.API.GetMarketValue(itemLink, serverKey, confidence) -> copper, seen,
--     modules, or nil (CoreAPI.lua:125). It can raise an error (:222, :242).
--   * [docs] A number goes through GetItemInfo (nil until the item is cached), so "item:<id>"
--     is passed. Its server key exists only after the first PLAYER_ENTERING_WORLD.
-- Guesses:
--   * [guess] A nil serverKey means the player's own auction house.
--   * [guess] It has no public call that starts a scan, and none that says its prices moved.
--   * [guess] Prices are what the test sets; its statistics modules are not modelled.
--
--   AuctioneerWorld.begin({ prices = { [2318] = 42 } })
--   AuctioneerWorld.state.asked: every link asked

AuctioneerWorld = {}

local S

function AuctioneerWorld.begin(spec)
    spec = spec or {}
    S = { prices = {}, asked = {} }
    AuctioneerWorld.state = S
    for id, copper in pairs(spec.prices or {}) do S.prices[id] = copper end

    local API = {}
    function API.GetMarketValue(itemLink)
        S.asked[#S.asked + 1] = itemLink
        local id = type(itemLink) == "string" and tonumber(itemLink:match("item:(%d+)"))
        if not id then return nil end
        local copper = S.prices[id]
        if not copper then return nil end
        return copper, 3
    end

    -- [docs] AucAdvanced.API as Glowey's Recipes' notes on Auctioneer 4.0.9 describe it.
    World.set(_G, "AucAdvanced", { API = API })
end
