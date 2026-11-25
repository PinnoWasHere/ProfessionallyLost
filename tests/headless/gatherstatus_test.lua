-- A gathering step's status line never shows a "?" for a count it does not have: a stretch held
-- behind a level has no gather count yet (found by the simulator's tips check on Skinning).

local CP = ProfLost

T.test("a level-gated stretch's status reads its range and the gate, with no unknown count", function()
    local row = { from = 135, to = 150, levelGate = { need = 22, have = 14, text = "This stretch needs level 22 (you're 14)" } }
    local status = CP.GuideTab.GatherStatus(row)
    T.ok(not status:find("?", 1, true), "no \"?\" in: " .. status)
    T.ok(status:find("135-150", 1, true) ~= nil, "the range in: " .. status)
    T.ok(status:find("level 22", 1, true) ~= nil, "the gate in: " .. status)
end)

T.test("a stretch with a count says it", function()
    local status = CP.GuideTab.GatherStatus({ from = 101, to = 125, gathers = 60 })
    T.eq(status, "101-125  \194\183  ~60 gathers")
end)
