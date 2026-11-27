-- tsmworld: MOCK of TradeSkillMaster's public API (TSM_API), as ProfLost reads it. Interface
-- only; none of its code.
--
-- Read from TSM v4.15.9 as installed (TradeSkillMaster/):
--   * [docs] TSM_API is a global table made as App/API.lua loads (:30), before its data exists.
--   * [docs] TSM_API.GetCustomPriceValue(priceString, itemString) -> copper, or nil and an error
--     text (App/API.lua:279-284, LibTSMApp Price/CustomPrice.lua:128-135). A dot call; a colon call
--     raises an error (App/API.lua:554-558).
--   * [docs] itemString must match "^[ip]:%d+", else it raises an error (App/API.lua:535-544); a
--     plain item is "i:<id>".
--   * [docs] "DBMarket" and "DBMinBuyout" are AuctionDB sources (LibTSMApp Config/AuctionDBConfig.lua:38-39),
--     in copper. Their data comes only from the TSM desktop app, loaded once in TSM's PLAYER_LOGIN
--     handler (LibTSMService AuctionDB/AuctionDB.lua:41-43, 135-159; LibTSMWoW Service/Lifecycle.lua:65).
--     Until then, and for an item it has no data for, the answer is nil.
--   * [docs] It keeps no age per item, has no call that starts a scan, and says nothing when its
--     data loads (App/API.lua has no price callback).
-- Guesses:
--   * [guess] Prices are what the test sets; the app's data and realms are not modelled.
--
--   TSMWorld.begin({ market = { [2318] = 42 }, minBuyout = { [2318] = 40 } })
--   TSMWorld.begin({ ..., login = false }), then TSMWorld.Login(): data arrives at login
--   TSMWorld.state.asked: every { priceString, itemString } asked

TSMWorld = {}

local S

local SOURCES = { DBMarket = "market", DBMinBuyout = "minBuyout" }

function TSMWorld.begin(spec)
    spec = spec or {}
    S = { market = {}, minBuyout = {}, asked = {}, loaded = spec.login ~= false }
    TSMWorld.state = S
    for id, copper in pairs(spec.market or {}) do S.market[id] = copper end
    for id, copper in pairs(spec.minBuyout or {}) do S.minBuyout[id] = copper end

    local API = {}
    function API.GetCustomPriceValue(priceString, itemString)
        if priceString == API then error("Invalid usage of colon operator to call TSM_API function") end
        if type(itemString) ~= "string" or not itemString:match("^[ip]:%d+") then
            error("Invalid 'itemString' argument type (must be a TSM item string): " .. tostring(itemString))
        end
        S.asked[#S.asked + 1] = { priceString, itemString }
        local t = S[SOURCES[priceString] or ""]
        if not t then return nil, "Invalid price string" end
        local id = tonumber(itemString:match("^i:(%d+)$"))
        local copper = S.loaded and id and t[id] or nil
        if not copper then return nil, "No value" end
        return copper
    end

    -- [docs] TSM_API as TSM v4.15.9's App/API.lua makes it.
    World.set(_G, "TSM_API", API)
end

-- TSM's login handler has loaded the desktop app's data.
function TSMWorld.Login() S.loaded = true end
