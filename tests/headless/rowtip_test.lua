-- Guide rows have no tooltip (owner, 2026-11-18: "I dont really like the tooltip stuff. feels a bit
-- overwhelming"; chose "No row tooltips"). The card keeps its short reason text.

local CP = ProfLost
local GT = CP.GuideTab
local ENCHANTING, TAILOR = 333, 197
local LINEN, GLOVES = 2589, 3840

-- The guide window open, unfolded, on the Guide tab, showing profession `id`.
local function showGuide(id)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowCollapsedAll", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function() CP.Window.SetFolded(false) CP.Window.Update() end)
    CP.Window.SetFolded(false)
    CP.Window.Update()
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    CP.Window.Pick(id)
    CP.Panel:Refresh()
end

-- What hovering a stand-in row painted with `row` shows: the tooltip's lines, or nil for none.
local function hover(row)
    local b = CreateFrame("Button", nil, UIParent)
    b:SetSize(300, 24)
    GT.PaintRow(b, row)
    local enter = b:GetScript("OnEnter")
    local lines
    if enter then
        lines = {}
        local real = GameTooltip
        local rec = setmetatable({}, { __index = function() return function() end end })
        function rec.SetText(_, t) lines[#lines + 1] = t end
        function rec.AddLine(_, t) lines[#lines + 1] = t end
        World.set(_G, "GameTooltip", rec)
        enter(b)
        World.set(_G, "GameTooltip", real)
    end
    b:Hide()
    return lines and #lines > 0 and table.concat(lines, "\n") or nil
end

T.test("Enchanting 53: no rank, craft or train row shows a tooltip", function()
    MapWorld.begin({ zone = 1429, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 53, max = 75 } } })
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    showGuide(ENCHANTING)
    local kinds = {}
    for _, row in ipairs(GT.ui.rows) do
        local kind = row.rank and "rank" or row.train and "train" or row.side and "or" or "craft"
        kinds[kind] = true
        T.eq(hover(row), nil, kind .. " row")
    end
    T.ok(kinds.rank and kinds.craft, "a rank row and a craft row were hovered")
    T.eq(GT.RowTip, nil, "no row tooltip builder")
    T.eq(GT.RowTipLines, nil)
    CraftWorld.Close()
end)

T.test("a step Enchanting's credit chose keeps its card line, with no tooltip", function()
    MapWorld.begin({ zone = 1429, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 }, [TAILOR] = { rank = 1, max = 75 } },
                       bags = { [LINEN] = 42 } })
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "committed", nil)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    showGuide(TAILOR)
    local gloves
    for _, row in ipairs(GT.ui.rows) do
        if row.spell == GLOVES and not row.side and not gloves then gloves = row end
    end
    T.ok(gloves and gloves.forEnchanting, "the gloves step was chosen for Enchanting")
    if not gloves then return end
    T.eq(hover(gloves), nil, "no tooltip")
    GT.Pick(gloves)
    T.advance(0.3)
    local text = GT.ui.details.sale:GetText() or ""
    T.ok(text:find("For Enchanting: disenchant these for Strange Dust", 1, true) ~= nil, "the card says why: " .. text)
    CraftWorld.Close()
end)
