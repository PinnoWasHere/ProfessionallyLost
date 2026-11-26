-- The options page's layout (owner, 2026-11-24): every label four words or fewer, groups and
-- rows in the designed order, and every saved key with the same default as before the tidy,
-- so no player's choice resets.

local CP = ProfLost
local S = CP.Settings

-- Every key and default before the tidy. A key that goes or a default that moves resets a choice.
local BEFORE = {
    collect = true, deEnchant = true, mapzRoute = true, vendorAlerts = true,
    unitTooltip = true, itemTooltip = true, neededMarks = true, mapIcons = true,
    otherZones = false, fishCook = true, hideInCombat = true, gatherHideInCombat = true,
    gatherAttached = true, gatherSide = "right", minimapButton = true, guideSteps = 4,
    textScale = 1, windowOpacity = 0.85, font = "general",
    -- Added after the tidy, on by default.
    whatsNew = true, newerNotice = true,
    -- The Glowey's Recipes hand-offs (2026-11-26), off by default.
    gloweyGuide = false, gloweyBuy = false, gloweyTips = false,
}

-- The designed page: group, then each row's key (or label for a keyless row, "note" for the note).
local ORDER = {
    { "Guides", { "collect", "note", "fishCook", "deEnchant", "mapzRoute" } },
    { "Guide window", { "guideSteps", "Guide window scale", "textScale", "font", "windowOpacity",
                        "hideInCombat", "minimapButton" } },
    { "Gathering window", { "gatherAttached", "gatherSide", "Gathering window scale", "vendorAlerts",
                           "mapIcons", "otherZones", "gatherHideInCombat" } },
    { "Tooltips and bags", { "itemTooltip", "unitTooltip", "neededMarks" } },
    { "Prices", { "TSM", "Auctioneer", "Auctionator", "Daylight UI", "Glowey's Recipes", "ProfLost's own scan", "note" } },
    { "Glowey's Recipes", { "gloweyGuide", "gloweyBuy", "gloweyTips", "Open Glowey's Recipes",
                            "Glowey's Recipes settings", "Put everything back" } },
    { "Help", { "Report a bug", "whatsNew", "What's New", "newerNotice", "Take the tour" } },
}

local function words(text)
    local n = 0
    for _ in tostring(text):gmatch("%S+") do n = n + 1 end
    return n
end

local function rowId(s)
    if s.kind == "note" then return "note" end
    return s.key or s.label
end

-- Daylight UI's API stand-in: only the font row, as API.FontRow builds it.
local API = { FontRow = function(key, label, desc) return { type = "font", key = key, label = label, desc = desc } end }

T.test("every key from before is still there with the same default", function()
    for key, default in pairs(BEFORE) do
        T.ok(S.Find(key) ~= nil, key .. " is still a setting")
        T.eq(CP.DEFAULTS[key], default, key .. " keeps its default")
        T.eq(CP.Plugin.Defaults()[key], default, key .. " reaches Daylight UI with the same default")
    end
    local keyless = 0
    for _, s in ipairs(S.LIST) do
        if s.key then T.ok(BEFORE[s.key] ~= nil, s.key .. ": a new key needs adding here") end
        if s.kind == "slider" and not s.key then
            keyless = keyless + 1
            T.eq(s.default(), 1, s.label .. " defaults to 1")
        end
    end
    T.eq(keyless, 2, "the two scale sliders keep their values in Daylight UI's movers")
end)

T.test("every label on the page is four words or fewer", function()
    for _, s in ipairs(S.LIST) do
        if s.label then T.ok(words(s.label) <= 4, ("%q has %d words"):format(s.label, words(s.label))) end
    end
    for _, g in ipairs(CP.Plugin.Pages(API)[1].groups) do
        T.ok(words(g.label) <= 4, ("group %q has %d words"):format(g.label, words(g.label)))
        for _, item in ipairs(g.items) do
            for _, text in ipairs({ item.text, type(item.label) == "string" and item.label or nil }) do
                T.ok(words(text) <= 4, ("%q has %d words"):format(text, words(text)))
            end
        end
    end
end)

T.test("groups and rows sit in the designed order", function()
    local groups = S.Groups()
    T.eq(#groups, #ORDER, "as many groups")
    for i, want in ipairs(ORDER) do
        local g = groups[i]
        T.eq(g and g.name, want[1], "group " .. i)
        local got = {}
        for _, s in ipairs(g and g.items or {}) do got[#got + 1] = rowId(s) end
        T.eq(got, want[2], want[1] .. "'s rows")
    end
    local page = CP.Plugin.Pages(API)[1].groups
    for i, want in ipairs(ORDER) do T.eq(page[i] and page[i].label, want[1], "the page's group " .. i) end
end)

T.test("a switch that greys another sits right above it", function()
    local at = {}
    for i, s in ipairs(S.LIST) do if s.key then at[s.key] = i end end
    T.eq(at.otherZones, at.mapIcons + 1, "Other zones under Icons on the map")
    T.eq(at.gatherSide, at.gatherAttached + 1, "Side when attached under Attach to guide window")
    T.eq(at.fishCook, at.collect + 2, "Fish for Cooking under Gather it yourself and its note")
end)

T.test("the two Hide in combat rows name their own window in the description", function()
    T.eq(S.Find("hideInCombat").label, "Hide in combat")
    T.eq(S.Find("gatherHideInCombat").label, "Hide in combat")
    T.ok(S.Find("hideInCombat").desc:find("guide window", 1, true) ~= nil)
    T.ok(S.Find("gatherHideInCombat").desc:find("detached Gathering window", 1, true) ~= nil)
end)
