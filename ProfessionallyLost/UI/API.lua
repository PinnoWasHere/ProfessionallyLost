local _, CP = ...
if CP.stopped then return end

-- The public API other addons call to open ProfLost. The global is documented in
-- API.md in the public repository. Calls here only read the window's state or ask it to show, so a
-- caller cannot damage ProfLost's saved settings.

-- Named `Public` because `API` in ProfLost's files means Daylight UI's API.
local Public = { VERSION = 1 }
ProfessionallyLostAPI = Public

-- Profession id for a skill line id or a name (English or localized), or nil.
local function resolve(profession)
    local Launcher = CP.Launcher
    local gather = Launcher and Launcher.GATHER_NAMES or {}
    if type(profession) == "number" then
        return ((CP.Guides and CP.Guides[profession]) or gather[profession]) and profession or nil
    end
    if type(profession) ~= "string" or profession == "" then return nil end
    local want = profession:lower()
    local ids = {}
    for id in pairs(CP.Guides or {}) do ids[#ids + 1] = id end
    for id in pairs(gather) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local guide = CP.Guides and CP.Guides[id]
        local info = CP.Professions and CP.Professions.SkillLine(id)
        local names = { guide and guide.name, gather[id], info and info.name }
        for i = 1, 3 do
            local name = names[i]
            if type(name) == "string" and name:lower() == want then return id end
        end
    end
    return nil
end

-- True when ProfLost has a guide for the profession (a skill line id or a name).
function Public.Guides(profession)
    return resolve(profession) ~= nil
end

-- True while the guide window shows.
function Public.IsShown()
    return CP.Panel ~= nil and CP.Panel.frame:IsShown() == true
end

-- Shows the guide window. `profession` (skill line id or name) picks the profession; nil
-- keeps the current one. Returns true, or false and a short reason.
function Public.Open(profession)
    local Window = CP.Window
    local id
    if profession ~= nil then
        id = resolve(profession)
        if not id then return false, "no guide for that profession" end
        local has = false
        for _, e in ipairs(Window.Professions()) do
            if e.id == id then has = true end
        end
        if not has then return false, "profession not learned" end
    end
    local why = Window.OpenBlocked()
    if why then return false, why end
    Window.Open()
    if id then Window.Pick(id) end
    return true
end

-- Closes the window when it shows, else opens it. Returns what Open returns.
function Public.Toggle()
    if Public.IsShown() then
        CP.Window.Close()
        return true
    end
    return Public.Open()
end
