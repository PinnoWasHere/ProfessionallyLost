-- Review items 27 and 28: the step card's sale line counts
-- the items a step makes (crafts times yield), and the profession dropdown shows the rank the
-- launcher and the guide use, with the modifier apart.

local CP = ProfLost
local W = CP.Window
local LW, TAILOR = 165, 197
local DUROTAR = 1411

local function scene(tailorRank)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = { rank = tailorRank or 60, max = 150 } } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowPoint", CP.db.windowPoint)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function()
        if W.MenuOpen() then W.CloseMenu() end
        W.CancelPick()
        W.opened = false
        W.Update()
    end)
    W.Update()
    T.advance(0.1)
end

-- Sale line -------------------------------------------------------------------------------

T.test("the sale line counts the items a step makes: crafts times the recipe's yield", function()
    scene()
    CraftWorld.Open(TAILOR)
    CraftWorld.Close()
    W.Pick(TAILOR)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    local ui = CP.GuideTab.ui
    local row
    for _, r in ipairs(ui.rows) do
        if r.spell and r.learned and r.recipe and not (r.rank or r.train or r.side or r.keep or r.forEnchanting) then row = r break end
    end
    T.ok(row ~= nil, "a learned step")
    World.set(CP.Professions, "Output", function() return 2589 end)
    World.set(CP.Pricing, "SaleValue", function() return 100, nil end)
    World.set(row.recipe, "yield", 1)
    CP.GuideTab.Pick(row)
    local text = ui.details.sale:GetText() or ""
    local crafts = tonumber(text:match("(%d+) for ~"))
    T.ok(crafts and crafts > 1, "several crafts: " .. text)
    T.ok(text:find(crafts .. " for ~" .. CP.Pricing.Format(100 * crafts), 1, true) ~= nil, text)

    World.set(row.recipe, "yield", 4)
    CP.GuideTab.Pick(row)
    text = ui.details.sale:GetText() or ""
    T.ok(text:find((crafts * 4) .. " for ~" .. CP.Pricing.Format(100 * crafts * 4), 1, true) ~= nil, text)
end)

-- Dropdown --------------------------------------------------------------------------------

T.test("the dropdown shows the rank the launcher shows; a modifier stands apart in brackets", function()
    scene(75)
    World.set(CraftWorld, "Modifier", function(line) return line == TAILOR and 10 or 0 end)
    DaylightWorld.begin({ plugin = true })
    local list = W.Professions()
    local e
    for _, p in ipairs(list) do if p.id == TAILOR then e = p end end
    T.ok(e ~= nil, "Tailoring listed")
    T.eq(e.skill, 75, "the rank alone")
    local owner = W.pickButton
    W.Menu(owner)
    local line = DaylightWorld.state.menu.values[TAILOR]
    T.ok(line:find("75 (+10)", 1, true) ~= nil, line)
    T.ok(line:find("85", 1, true) == nil, line)
    T.ok(line:find("^Tailoring") ~= nil, line)
    DaylightWorld.CloseMenu()
end)
