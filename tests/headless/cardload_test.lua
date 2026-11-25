-- CARDLOAD-01: a step card's material names fill in once item data loads.

local CP = ProfLost
local GT = CP.GuideTab
local LW = 165
local DUROTAR = 1411
local HEAVY_LEATHER, FINE_THREAD = 4234, 2321

local function shownNames()
    local out = {}
    for _, line in ipairs(GT.ui.details.rows) do
        if line:IsShown() then out[#out + 1] = line.name:GetText() or "" end
    end
    return table.concat(out, " | ")
end

T.test("a material whose item data loads late shows its name without re-picking the row", function()
    DaylightWorld.begin({ plugin = true })
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = 136, max = 225 } },
                       bags = { [HEAVY_LEATHER] = 60, [FINE_THREAD] = 20 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    local was = C_Item.GetItemNameByID
    local loaded = false
    World.patch("C_Item.GetItemNameByID", function(id)
        if id == HEAVY_LEATHER and not loaded then return nil end
        return was(id)
    end)
    CraftWorld.Open(LW)
    T.advance(2)
    CP.Panel:Refresh()
    T.ok(shownNames():find("…", 1, true), "an unloaded name shows its stand-in: " .. shownNames())

    -- The item event arrives while the name still reads nil: that redraw learns nothing.
    T.fire("GET_ITEM_INFO_RECEIVED", HEAVY_LEATHER, true)
    T.advance(2)

    -- The name reads now and no second event comes; the card asks again on its own.
    loaded = true
    T.advance(3)
    T.ok(not shownNames():find("…", 1, true), "the name filled in after the data arrived: " .. shownNames())
    CraftWorld.Close()
end)
