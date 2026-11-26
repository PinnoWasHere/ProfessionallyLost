-- tsmworld: MOCK of TradeSkillMaster's public API (TSM_API), as ProfLost reads it. Interface
-- only; none of its code. TSM is not installed on the owner's client, so nothing here was read
-- from TSM itself.
--
-- Modelled from Glowey's Recipes 3.3.0-beta3 PriceSources.lua, whose header cites TSM 4.15.9's
-- source:
--   * [docs] TSM_API.GetCustomPriceValue(priceString, itemString) -> copper or nil, plus an error
--     text (App/API.lua:279-284). A dot call; a colon call errors (:554-558).
--   * [docs] A plain item's itemString is "i:<id>" (App/API.lua:535-544).
--   * [docs] "DBMarket" and "DBMinBuyout" are its AuctionDB sources (LibTSMApp AuctionDBConfig.lua:30-54).
--     Their data comes only from the TSM desktop app, loaded at login; no per-item age.
-- Guesses:
--   * [guess] An unknown price string answers nil and an error text, never a raised error.
--   * [guess] Prices are what the test sets; the app's data and realms are not modelled.
--   * [guess] TSM_API has no call that starts an auction scan, and none that says its prices moved.
--
--   TSMWorld.begin({ market = { [2318] = 42 }, minBuyout = { [2318] = 40 } })
--   TSMWorld.state.asked: every { priceString, itemString } asked

TSMWorld = {}

local S

local SOURCES = { DBMarket = "market", DBMinBuyout = "minBuyout" }

function TSMWorld.begin(spec)
    spec = spec or {}
    S = { market = {}, minBuyout = {}, asked = {} }
    TSMWorld.state = S
    for id, copper in pairs(spec.market or {}) do S.market[id] = copper end
    for id, copper in pairs(spec.minBuyout or {}) do S.minBuyout[id] = copper end

    local API = {}
    function API.GetCustomPriceValue(priceString, itemString)
        if priceString == API then error("TSM_API: called with a colon") end
        S.asked[#S.asked + 1] = { priceString, itemString }
        local t = S[SOURCES[priceString] or ""]
        if not t then return nil, "Invalid price string" end
        local id = type(itemString) == "string" and tonumber(itemString:match("^i:(%d+)$"))
        if not id then return nil, "Invalid item" end
        return t[id]
    end

    -- [docs] TSM_API as Glowey's Recipes' notes on TSM 4.15.9 describe it.
    World.set(_G, "TSM_API", API)
end
