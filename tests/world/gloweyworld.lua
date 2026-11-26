-- gloweyworld: MOCK of Glowey's Recipes (the DaylightRecipes addon), as ProfLost reads it.
-- Interface only; none of its code.
--
-- Modelled from its files, read in 3.3.0-beta3:
--   * [docs] Its public table is DaylightRecipes.API, major 1 (API.lua): API.Price(itemID) -> copper
--     or nil; API.PriceAge(itemID) -> seconds or nil; API.HasPrices() -> bool; API.OnPrices(fn) ->
--     fn() after its prices change.
--   * [docs] Its Daylight UI module "DaylightRecipes" holds its switches that leave jobs to
--     ProfLost: plGuide, plShop, plTips, plPrices and plStep, all false until the player sets
--     them, and "tooltips" (its own item tooltip lines), true by default (Core.lua DEFAULTS).
--     plShop counts only while plGuide is on (ProfLost.lua FOLLOWS_GUIDE).
--   * [docs] /recipes and /dr toggle its window through SlashCmdList.DAYLIGHTRECIPES (Core.lua).
--   * [docs] Its options page has the id "recipes", so Daylight UI shows it as
--     "DaylightRecipes.recipes" (Core.lua pages, Host.lua OpenOptions).
-- Guesses:
--   * [guess] Prices and ages are what the test sets; its own book and source choice are not modelled.
--   * [guess] Its switches live in DaylightWorld's settings under the scope "DaylightRecipes", so
--     DaylightWorld.begin runs first when a test gives settings. Set fires SettingChanged, as
--     DaylightUI:Set does.
--
--   GloweyWorld.begin({ prices = { [2318] = 42 }, ages = { [2318] = 600 }, has = true })
--   GloweyWorld.begin({ settings = { plGuide = true }, command = false })
--   GloweyWorld.SetPrice(item, copper, age) / Changed(); GloweyWorld.Set(key, value)
--   GloweyWorld.state.handlers / .opened (times /recipes ran)

GloweyWorld = {}

local S

function GloweyWorld.begin(spec)
    spec = spec or {}
    S = { prices = {}, ages = {}, handlers = {}, has = spec.has, opened = 0 }
    GloweyWorld.state = S
    for id, copper in pairs(spec.prices or {}) do S.prices[id] = copper end
    for id, age in pairs(spec.ages or {}) do S.ages[id] = age end

    if spec.settings then
        local dui = DaylightWorld.state
        if not dui then error("GloweyWorld settings need DaylightWorld.begin first", 2) end
        local saved = {}
        for k, v in pairs(spec.settings) do saved[k] = v end
        dui.settings.DaylightRecipes = saved
    end

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
    if spec.command ~= false then
        World.set(SlashCmdList, "DAYLIGHTRECIPES", function() S.opened = S.opened + 1 end)
    end
end

function GloweyWorld.SetPrice(itemID, copper, age)
    S.prices[itemID] = copper
    S.ages[itemID] = age
end

-- Its prices moved: every OnPrices handler hears it.
function GloweyWorld.Changed()
    for _, fn in ipairs(S.handlers) do fn() end
end

-- One of its switches, as its options page or its first-load window sets it.
function GloweyWorld.Set(key, value)
    DaylightWorld.SetSetting("DaylightRecipes", key, value)
end
