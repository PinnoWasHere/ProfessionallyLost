-- A level-up redraws the guide: a "<zone>: reach level N" row leaves once the character has N.

local CP = ProfLost
local SKIN, BADLANDS = 393, 1418

local function show(prof)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        CP.Window.opened = false
        CP.Window.Update()
    end)
    World.set(CP.charDB, "guideMode", "one")
    CP.Window.Update()   -- shows the window: an earlier scene may have left it closed
    CP.Window.Pick(prof)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    return CP.GuideTab.ui
end

-- The level the drawn rows ask first, or nil.
local function asked(rows)
    for _, row in ipairs(rows or {}) do
        if row.levelGate then return row.levelGate.need end
    end
end

T.test("PLAYER_LEVEL_UP redraws a level row the character now meets", function()
    MapWorld.begin({ zone = BADLANDS, level = 35, side = "Alliance" })
    CraftWorld.begin({ professions = { [SKIN] = { rank = 295, max = 300, known = {} } } })
    MapWorld.SettleGuides({ SKIN })
    local ui = show(SKIN)
    local need = asked(ui.rows)
    T.ok(need ~= nil and need > 35, "a level row at level 35: " .. tostring(need))
    if not need then return end
    MapWorld.SetLevel(need)
    T.advance(2)
    local after = asked(ui.rows)
    T.ok(after == nil or after > need, ("at level %d the guide still asks level %s"):format(need, tostring(after)))
end)
