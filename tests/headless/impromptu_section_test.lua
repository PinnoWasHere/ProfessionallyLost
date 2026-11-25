-- IMPROMPTU-02: the craft-from-bags area has its own heading and divider, so it does not
-- read as more guide steps.

local CP = ProfLost
local GT = CP.GuideTab
local LW = 165
local DUROTAR = 1411
local SKILL = 60
local LIGHT_LEATHER, COARSE_THREAD = 2318, 2320
local SPARE = 12

local function known()
    local out = {}
    for id, r in pairs(CP.Guides[LW].recipes) do
        if (r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= SKILL then out[#out + 1] = id end
    end
    return out
end

local function scene(mode)
    Visual.begin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    DaylightWorld.begin({ craftWindow = false })
    CraftWorld.begin({ professions = { [LW] = { rank = SKILL, max = 75, known = known() } }, bags = {} })
    World.set(CP.db, "collect", false)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", mode or "one")
    World.set(CP.db, "windowPoint", CP.db.windowPoint)
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel.frame:Show()
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    T.advance(1)
end

local function spare()
    local needs = CP.Gather.Needs()
    CraftWorld.SetBag(LIGHT_LEATHER, (needs[LIGHT_LEATHER] or 0) + SPARE)
    CraftWorld.SetBag(COARSE_THREAD, (needs[COARSE_THREAD] or 0) + SPARE)
    T.advance(1)
end

local function firstShownRow(area)
    for _, r in ipairs(area.rows) do if r:IsShown() then return r end end
end

local function checkSection(label)
    local area = GT.ui.impromptu
    T.ok(area:IsShown(), label .. ": the area shows")
    T.ok(area.heading ~= nil and area.heading:IsShown(), label .. ": the heading shows")
    T.eq(area.heading and area.heading:GetText(), "Available Skill Ups", label .. ": the heading text")
    T.ok(area.divider ~= nil and area.divider:IsShown(), label .. ": the divider shows")
    if not (area.heading and area.divider) then return end
    local row = firstShownRow(area)
    T.ok(row ~= nil, label .. ": a craft row is listed")
    T.ok(area.divider:GetTop() >= area.heading:GetTop() - 0.5, label .. ": the divider is above the heading")
    if row then
        T.ok(area.heading:GetBottom() >= row:GetTop() - 0.5, label .. ": the heading is above the first row")
    end
    return area
end

T.test("Single open: heading and divider sit between the last step row and the craft rows", function()
    scene()
    spare()
    local area = checkSection("open")
    if not area then return end
    T.ok(GT.ui.scroll:GetBottom() >= area.divider:GetTop() - 0.5, "the step list ends above the divider")
    T.ok(area:GetHeight() > area.max * GT.RowHeight(), "the area height counts the heading")
    CraftWorld.Close()
end)

T.test("Single folded: heading and divider show above the craft rows", function()
    scene()
    spare()
    World.set(CP.db, "windowCollapsed", true)
    CP.Panel:Refresh()
    T.advance(1)
    T.ok(CP.Panel.folded, "the window is folded")
    checkSection("folded")
    CraftWorld.Close()
end)

T.test("the heading and divider hide with the area in the All view", function()
    scene("all")
    local area = GT.ui.impromptu
    T.ok(not area:IsVisible(), "the area is hidden in the All view")
    T.ok(not (area.heading and area.heading:IsVisible()), "the heading is not visible")
    T.ok(not (area.divider and area.divider:IsVisible()), "the divider is not visible")
    CraftWorld.Close()
end)
