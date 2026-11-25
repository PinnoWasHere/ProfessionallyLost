-- Route lines: segment clipping to the minimap's edge, and loops drawn per zone.

local CP = ProfLost
local RL = CP.RouteLines

local function near(a, b) return math.abs(a - b) < 1e-6 end

T.test("a segment inside the circle stays whole", function()
    local sx, sy, ex, ey = RL.Clip(-10, 0, 10, 0, 50, false)
    T.ok(near(sx, -10) and near(sy, 0) and near(ex, 10) and near(ey, 0))
end)

T.test("a segment leaving the circle stops at its edge", function()
    local sx, _, ex = RL.Clip(0, 0, 100, 0, 50, false)
    T.ok(near(sx, 0) and near(ex, 50))
end)

T.test("a segment passing outside the circle is dropped", function()
    T.eq(RL.Clip(-100, 80, 100, 80, 50, false), nil)
end)

T.test("a square minimap clips to its sides", function()
    local _, _, ex, ey = RL.Clip(0, 0, 100, 100, 50, true)
    T.ok(near(ex, 50) and near(ey, 50), "the corner")
    T.eq(RL.Clip(60, -100, 60, 100, 50, true), nil, "outside the right side")
end)

T.test("a loop is kept per zone and cleared", function()
    RL.Set(1411, { { x = 0.4, y = 0.4 }, { x = 0.6, y = 0.4 }, { x = 0.5, y = 0.6 } }, { 1, 1, 1 })
    T.ok(RL.Has(1411))
    RL.Set(1411, { { x = 0.4, y = 0.4 } })
    T.ok(not RL.Has(1411), "one point is no loop")
    RL.Set(1411, { { x = 0.4, y = 0.4 }, { x = 0.6, y = 0.4 } })
    RL.Clear()
    T.ok(not RL.Has(1411))
end)
