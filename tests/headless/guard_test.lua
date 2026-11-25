-- A second copy of ProfLost (the Dev folder beside the stable one) stops at load and prints
-- one line naming the copy that runs (Core/Guard.lua). Every file after the guard begins
-- "if CP.stopped then return end".

local CP = ProfLost

T.test("the copy that loads first runs", function()
    T.ok(not CP.stopped, "the running copy is not stopped")
    T.eq(type(CP.Guard), "function")
end)

T.test("a second copy stops, prints one line naming the first, and touches nothing else", function()
    local said = {}
    World.set(_G, "print", function(...) said[#said + 1] = table.concat({ ... }, " ") end)
    local frames = 0
    World.patch("CreateFrame", function() frames = frames + 1 end)

    local second = {}
    T.ok(CP.Guard(second, "ProfessionallyLost_Dev"), "the guard reports a stop")
    T.ok(second.stopped, "the second copy is flagged")
    T.eq(#said, 1, "one chat line")
    T.ok(said[1]:find(CP.name, 1, true), "names the copy that runs")
    T.ok(said[1]:find("ProfessionallyLost_Dev", 1, true), "names the copy that stopped")
    T.eq(frames, 0, "no frame")
    T.ok(not CP.stopped, "the running copy stays running")
end)

T.test("the running copy never stops itself", function()
    local said = 0
    World.set(_G, "print", function() said = said + 1 end)
    T.ok(not CP.Guard(CP, CP.name))
    T.eq(said, 0)
end)

T.test("media paths follow the folder the addon loaded from", function()
    T.eq(CP.MEDIA, "Interface\\AddOns\\" .. CP.name .. "\\Media\\")
end)
