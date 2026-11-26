-- gloweyworld: MOCK of Glowey's Recipes (the DaylightRecipes addon), as ProfLost reads it.
-- Interface only; none of its code.
--
-- Modelled from its files, read in 3.3.0-beta3:
--   * [docs] Its public table is DaylightRecipes.API, major 1 (API.lua).
--   * [docs] Its Daylight UI module "DaylightRecipes" holds its switches that leave jobs to
--     ProfLost: plGuide, plShop, plTips, plPrices and plStep, all false until the player sets
--     them, and "tooltips" (its own item tooltip lines), true by default (Core.lua DEFAULTS).
--     plShop counts only while plGuide is on (ProfLost.lua FOLLOWS_GUIDE).
--   * [docs] /recipes and /dr toggle its window through SlashCmdList.DAYLIGHTRECIPES (Core.lua).
--   * [docs] Its options page has the id "recipes", so Daylight UI shows it as
--     "DaylightRecipes.recipes" (Core.lua pages, Host.lua OpenOptions).
-- Guesses:
--   * [guess] Its switches live in DaylightWorld's settings under the scope "DaylightRecipes", so
--     DaylightWorld.begin runs first. Set fires SettingChanged, as DaylightUI:Set does.
--
--   GloweyWorld.begin({ settings = { plGuide = true }, command = false })
--   GloweyWorld.Set(key, value) / GloweyWorld.state.opened (times /recipes ran)

GloweyWorld = {}

local S

function GloweyWorld.begin(spec)
    spec = spec or {}
    local dui = DaylightWorld.state
    if not dui then error("GloweyWorld needs DaylightWorld.begin first", 2) end
    S = { opened = 0 }
    GloweyWorld.state = S
    local saved = {}
    for k, v in pairs(spec.settings or {}) do saved[k] = v end
    dui.settings.DaylightRecipes = saved
    -- [docs] Its API.lua makes the global's API table, major 1.
    World.set(_G, "DaylightRecipes", { API = { major = 1 } })
    if spec.command ~= false then
        World.set(SlashCmdList, "DAYLIGHTRECIPES", function() S.opened = S.opened + 1 end)
    end
end

-- One of its switches, as its options page or its first-load window sets it.
function GloweyWorld.Set(key, value)
    DaylightWorld.SetSetting("DaylightRecipes", key, value)
end
