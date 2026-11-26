-- gloweyworld: MOCK of Glowey's Recipes' public API (DaylightRecipes.API, major 1), as the
-- header of its API.lua describes it. Interface only; none of its code.
--
-- Modelled from that file:
--   * [docs] API.Price(itemID) -> copper or nil; API.PriceAge(itemID) -> seconds or nil;
--     API.HasPrices() -> bool; API.OnPrices(fn) -> fn() after its prices change.
--   * [docs] The global DaylightRecipes holds the table as .API.
-- Guesses:
--   * [guess] Prices and ages are what the test sets; its own book and source choice are not modelled.
--
--   GloweyWorld.begin({ prices = { [2318] = 42 }, ages = { [2318] = 600 }, has = true })
--   GloweyWorld.SetPrice(item, copper, age) / Changed(); GloweyWorld.state.handlers

GloweyWorld = {}

local S

function GloweyWorld.begin(spec)
    spec = spec or {}
    S = { prices = {}, ages = {}, handlers = {}, has = spec.has }
    GloweyWorld.state = S
    for id, copper in pairs(spec.prices or {}) do S.prices[id] = copper end
    for id, age in pairs(spec.ages or {}) do S.ages[id] = age end

    local API = { major = 1 }
    function API.Price(itemID) return S.prices[itemID] end
    function API.PriceAge(itemID) return S.ages[itemID] end
    function API.HasPrices()
        if S.has ~= nil then return S.has end
        return next(S.prices) ~= nil
    end
    function API.OnPrices(fn) S.handlers[#S.handlers + 1] = fn end

    -- [docs] DaylightRecipes.API as its API.lua header describes it.
    World.set(_G, "DaylightRecipes", { API = API })
end

function GloweyWorld.SetPrice(itemID, copper, age)
    S.prices[itemID] = copper
    S.ages[itemID] = age
end

-- Its prices moved: every OnPrices handler hears it.
function GloweyWorld.Changed()
    for _, fn in ipairs(S.handlers) do fn() end
end
