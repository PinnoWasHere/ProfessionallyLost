-- "Plan for Enchanting" greys out and draws off for a character without Enchanting (or without a
-- profession whose items disenchant), on the first page build and after professions load late.
-- It re-reads when the skills move, and the open options page redraws then.

local CP = ProfLost
local ENCHANTING, TAILOR, MINING = 333, 197, 186
local ELWYNN = 1429

local function row(key)
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, it in ipairs(g.items) do if it.key == key then return it end end
    end
end

local function character(professions)
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = professions })
end

local function get(k) return CP.Settings.Current(k) end

local function rank() return { rank = 1, max = 75 } end

T.test("Plan for Enchanting: without Enchanting the first page build is greyed and draws off", function()
    World.set(CP.db, "deEnchant", true)
    character({ [TAILOR] = rank() })
    local r = row("deEnchant")
    T.eq(r.disabled(get), true, "greyed")
    T.eq(r.get(), false, "draws off")
    T.eq(CP.db.deEnchant, true, "the saved choice stays")
    character({})
    T.eq(row("deEnchant").disabled(get), true, "greyed with no professions")
    character({ [ENCHANTING] = rank() })
    T.eq(row("deEnchant").disabled(get), true, "greyed with Enchanting alone")
    T.eq(row("deEnchant").get(), false)
end)

T.test("Plan for Enchanting: with Enchanting and Tailoring it is live and draws the saved value", function()
    World.set(CP.db, "deEnchant", true)
    character({ [ENCHANTING] = rank(), [TAILOR] = rank() })
    local r = row("deEnchant")
    T.eq(r.disabled(get), false, "live")
    T.eq(r.get(), true)
    World.set(CP.db, "deEnchant", false)
    T.eq(row("deEnchant").get(), false, "an off choice draws off")
end)

T.test("Plan for Enchanting: professions that load late flip the row without a rebuild", function()
    World.set(CP.db, "deEnchant", true)
    character({})
    local r = row("deEnchant")
    T.eq(r.disabled(get), true, "greyed before the skills load")
    character({ [ENCHANTING] = rank(), [TAILOR] = rank() })
    T.fire("SKILL_LINES_CHANGED")
    T.advance(1)
    T.eq(r.disabled(get), false, "live once the skills are in")
    T.eq(r.get(), true)
    character({ [TAILOR] = rank() })
    T.fire("SKILL_LINES_CHANGED")
    T.advance(1)
    T.eq(r.disabled(get), true, "greyed again when Enchanting goes")
end)

T.test("a skills change redraws the open options page", function()
    local redraws = 0
    local panel = { IsShown = function() return true end, Refresh = function() redraws = redraws + 1 end }
    World.set(CP.Settings, "Daylight", function() return { OptionsPanel = panel } end)
    character({ [TAILOR] = rank() })
    CP:Emit("ProfLost_SKILLS")
    T.advance(1)
    T.ok(redraws >= 1, "the page redrew")
end)

T.test("the other greyed rows still grey: Mapzeroth, Fish for Cooking, Other zones", function()
    World.set(_G, "MapzerothAPI", nil)
    T.eq(row("mapzRoute").disabled(get), true, "Route with Mapzeroth")
    World.set(CP.db, "collect", false)
    T.eq(row("fishCook").disabled(get), true, "Fish for Cooking")
    World.set(CP.db, "collect", true)
    T.eq(row("fishCook").disabled(get), false)
    World.set(CP.db, "mapIcons", false)
    T.eq(row("otherZones").disabled(get), true, "Other zones")
    World.set(CP.db, "mapIcons", true)
    T.eq(row("otherZones").disabled(get), false)
end)
