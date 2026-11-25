-- Window opacity: one setting sets the background alpha of the guide window and the
-- gathering panel (attached and detached), live, and nothing else.

local CP = ProfLost
local S = CP.Style

-- The last alpha each shell fill was painted with, recorded from its SetColorTexture.
local painted = setmetatable({}, { __mode = "k" })
local function watch(frame)
    World.set(frame.__shell, "SetColorTexture", function(_, _, _, _, a) painted[frame] = a end)
end
local function alpha(frame) return painted[frame] end

-- Sets the opacity for the rest of the test; the old value comes back at its end.
local function opacity(v)
    local old = CP.db.windowOpacity
    World.onEnd(function() CP.db.windowOpacity = old; S.ApplyOpacity() end)
    CP.Settings.Set("windowOpacity", v)
end

T.test("window opacity is a slider from 0.2 to 1 in the guide window group", function()
    local s = CP.Settings.Find("windowOpacity")
    T.ok(s ~= nil, "the setting exists")
    T.eq(s.kind, "slider")
    T.eq(s.min, 0.2)
    T.eq(s.max, 1)
    T.eq(CP.DEFAULTS.windowOpacity, 0.85, "default is Daylight UI's own window opacity")
    local row
    for _, page in ipairs(CP.Plugin.Pages()) do
        for _, g in ipairs(page.groups) do
            for _, item in ipairs(g.items) do if item.key == "windowOpacity" then row = item end end
        end
    end
    T.ok(row and row.type == "slider", "Daylight UI's options page gets a slider row")
end)

T.test("without Daylight UI the guide window and both gathering shells take the alpha", function()
    local shells = { CP.Panel.frame, CP.GatherPanel.shell, CP.GatherPanel.sheet }
    local frameAlpha = CP.Panel.frame:GetAlpha()
    for _, f in ipairs(shells) do watch(f) end
    S.ApplyOpacity()
    for _, f in ipairs(shells) do T.eq(alpha(f), S.FALLBACK_ALPHA, "unchanged at the default") end
    opacity(0.4)
    for _, f in ipairs(shells) do T.eq(alpha(f), 0.4, "follows the slider live") end
    T.eq(CP.Panel.frame:GetAlpha(), frameAlpha, "the window as a whole keeps its alpha")
    opacity(1)
    for _, f in ipairs(shells) do T.eq(alpha(f), 1) end
end)

T.test("with Daylight UI the shell is skinned again with bgAlpha, window shape kept", function()
    local seen = {}
    World.set(_G, "DaylightUI", { API = { major = 1, minor = 1, Skin = function(f, o) seen[f] = o end } })
    local win = CreateFrame("Frame")
    local tab = CreateFrame("Frame")
    S.Shell(win)
    S.TabShell(tab, 3)
    T.eq(seen[win].window, true)
    T.eq(seen[win].bgAlpha, nil, "default: follows the player's Daylight UI window opacity")
    T.eq(seen[tab].bgAlpha, nil)
    opacity(0.5)
    T.eq(seen[win].bgAlpha, 0.5, "guide shell")
    T.eq(seen[tab].bgAlpha, 0.5, "gathering tab")
    T.eq(seen[tab].borderPx, 3, "tab keeps its border")
    T.eq(seen[win].window, true)
    CP.db.windowOpacity = 0.85
    S.ApplyOpacity()
    T.eq(seen[win].bgAlpha, nil, "back to the default follows Daylight UI again")
end)

T.test("the bug report window stays off the setting", function()
    local seen = {}
    World.set(_G, "DaylightUI", { API = { major = 1, minor = 1, Skin = function(f, o) seen[f] = o end } })
    local f = CreateFrame("Frame")
    S.Shell(f, nil, true)
    opacity(0.3)
    T.eq(seen[f].bgAlpha, nil)
end)
