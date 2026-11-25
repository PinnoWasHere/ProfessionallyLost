-- The public API other addons call (UI/API.lua, API.md): ProfessionallyLostAPI.

local CP = ProfLost
local W, P = CP.Window, CP.Panel
local API = ProfessionallyLostAPI
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR = 1411

-- Leatherworking, Tailoring and Mining known, the window shut by the player.
local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", true)
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.db, "windowAnchorSize", nil)
    World.set(CP.db, "windowPoint", nil)
    World.onEnd(function()
        W.opened = false
        W.Update()
    end)
    W.Update()
end

T.test("the global carries an integer VERSION and the calls", function()
    T.ok(API ~= nil, "the global exists")
    T.eq(API.VERSION, 1)
    for _, name in ipairs({ "Open", "Toggle", "IsShown", "Guides" }) do
        T.eq(type(API[name]), "function", name)
    end
end)

T.test("Guides: ids and names, any case; unknown things are false", function()
    T.ok(API.Guides(TAILOR), "Tailoring by id")
    T.ok(API.Guides("tailoring"), "by name, any case")
    T.ok(API.Guides("Leatherworking"))
    T.ok(API.Guides(MINING), "a gathering skill the window shows")
    T.ok(not API.Guides(99999), "an id with no guide")
    T.ok(not API.Guides("Basket Weaving"))
    T.ok(not API.Guides(nil))
    T.ok(not API.Guides({}))
end)

T.test("Open with no profession shows the window and keeps the current profession", function()
    scene()
    W.Pick(LW)
    T.ok(not API.IsShown(), "shut to start")
    T.eq(API.Open(), true)
    T.ok(API.IsShown() and P.frame:IsShown(), "shown")
    T.eq(W.ChosenID(), LW, "still Leatherworking")
end)

T.test("Open with a profession picks it, by id or by name", function()
    scene()
    T.eq(API.Open(TAILOR), true)
    T.ok(API.IsShown())
    T.eq(W.ChosenID(), TAILOR)
    T.eq(API.Open("Leatherworking"), true)
    T.eq(W.ChosenID(), LW)
end)

T.test("Open refuses a profession with no guide or one the player lacks", function()
    scene()
    local ok, why = API.Open("Basket Weaving")
    T.eq(ok, false)
    T.eq(type(why), "string")
    T.ok(not API.IsShown(), "nothing opened")
    ok, why = API.Open(171)   -- Alchemy has a guide; this character has no Alchemy
    T.eq(ok, false)
    T.eq(why, "profession not learned")
    T.ok(not API.IsShown())
end)

T.test("Open respects Window.OpenBlocked and gives its reason", function()
    scene()
    World.set(W, "OPEN_IN_COMBAT", false)
    World.patch("InCombatLockdown", function() return true end)
    local ok, why = API.Open(TAILOR)
    T.eq(ok, false)
    T.eq(why, W.OPEN_COMBAT_TIP)
    T.ok(not API.IsShown())
    World.patch("InCombatLockdown", function() return false end)
    T.eq(API.Open(TAILOR), true)
end)

T.test("Toggle opens a shut window and closes a shown one", function()
    scene()
    T.eq(API.Toggle(), true)
    T.ok(API.IsShown())
    T.eq(API.Toggle(), true)
    T.ok(not API.IsShown())
end)
