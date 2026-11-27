-- gloweyworld: MOCK of Glowey's Recipes (the DaylightRecipes addon), as ProfLost reads it.
-- Interface only; none of its code.
--
-- Modelled from its files, read in 3.3.0-beta3:
--   * [docs] Its public table is DaylightRecipes.API, major 1 (API.lua): API.Price(itemID) -> copper
--     or nil; API.PriceAge(itemID) -> seconds or nil; API.HasPrices() -> bool; API.OnPrices(fn) ->
--     fn() after its prices change.
--   * [docs] Its Daylight UI module "DaylightRecipes" holds its six switches that leave jobs to
--     ProfLost: plGuide, plShop, plTrainer, plTips, plPrices and plStep, all false until the
--     player sets them, and "tooltips" (its own item tooltip lines), true by default (Core.lua
--     DEFAULTS). plShop, plTrainer and plStep count only while plGuide is on (ProfLost.lua
--     FOLLOWS_GUIDE). It writes them through DaylightUI:Set (ProfLost.lua Set).
--   * [docs] Its first-load question is answered once per account: DaylightRecipesDB.proflost.asked
--     (ProfLost.lua Record, PL.Asked).
--   * [docs] With two or more of Glowey's plugins on, their pages fold under one "Glowey's" entry
--     (Hub.lua). Its page "DaylightRecipes.recipes" is then hidden until the hub opens it, and
--     Daylight UI's OptionsPanel.Show shows "home" for a hidden page (DaylightUI Options/Panel.lua
--     Show, Options/Registry.lua GetPage). _G.GloweyHub.impl.Show(addon, pageId) opens the plugin's
--     place first, then shows "<addon>.<pageId>" (Hub.lua I.Show).
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
--   GloweyWorld.begin({ settings = { plGuide = true }, command = false, asked = true, hub = true })
--   GloweyWorld.Hidden(pageId) -> true while its folded hub hides that options page
--   GloweyWorld.SetPrice(item, copper, age) / Changed(); GloweyWorld.Set(key, value)
--   GloweyWorld.state.handlers / .opened (times /recipes ran)

GloweyWorld = {}

local S

function GloweyWorld.begin(spec)
    spec = spec or {}
    S = { prices = {}, ages = {}, handlers = {}, has = spec.has, opened = 0, hub = spec.hub == true }
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
    if spec.asked ~= nil then
        World.set(_G, "DaylightRecipesDB", { proflost = { asked = spec.asked } })
    end
    if spec.hub then
        -- [docs] Hub.lua I.Show: the plugin's place on the hub's list first, then its page.
        local impl = {}
        function impl.Show(addon, pageId)
            S.hubOpen = addon
            local P = _G.DaylightUI and rawget(_G.DaylightUI, "OptionsPanel")
            if type(P) == "table" and type(P.Show) == "function" then
                return pcall(P.Show, addon .. "." .. tostring(pageId))
            end
            return false
        end
        World.set(_G, "GloweyHub", { minor = 1, impl = impl, state = {} })
    end
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

-- True while the folded hub hides its options page `pageId`, so Daylight UI would show "home".
function GloweyWorld.Hidden(pageId)
    if not (S and S.hub) then return false end
    return pageId:find("^DaylightRecipes%.") ~= nil and S.hubOpen ~= "DaylightRecipes"
end

-- One of its switches, as its options page or its first-load window sets it.
function GloweyWorld.Set(key, value)
    DaylightWorld.SetSetting("DaylightRecipes", key, value)
end
