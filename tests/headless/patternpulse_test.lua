-- A pattern in "Patterns to buy here" the player can learn right now wears the guide's green
-- pulse (Style.OwnedRow): skill reached, recipe not known, purse covers a known price.

local CP = ProfLost
local GL, VW = CP.GatherList, CP.VendorWatch
local ALCHEMY, HERB = 171, 182
local DUROTAR = 1411

-- A vendor recipe of the Alchemy guide that has a pattern item.
local function vendorRecipe()
    local best
    for spell, r in pairs(CP.Guides[ALCHEMY].recipes) do
        if r.pattern and (not best or spell < best.spell) then best = { spell = spell, r = r } end
    end
    return best
end

-- Durotar with the character's Alchemy at `skill` and one watched pattern of skill `need`.
local function scene(skill, need, price)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.charDB, "panelProf", nil)
    World.set(CP.charDB, "learned", {})
    World.set(CP.charDB, "gatherNeeds", {})
    World.set(CP.charDB, "gatherSoon", nil)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == ALCHEMY then return { skillID = id, rank = skill, modifier = 0, maxRank = 300 } end
        if id == HERB then return { skillID = id, rank = 50, modifier = 0, maxRank = 300 } end
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.Gather, "UpdateAllNeeds", function() end)
    local v = vendorRecipe()
    local buy = { item = v.r.pattern, name = "Pattern", skill = need, price = price, npcs = {} }
    World.set(CP.charDB, "vendorWatch", { [ALCHEMY] = { buy } })
    World.set(VW, "current", { zone = DUROTAR, found = { { buy = buy, target = { name = "V", continent = 1, x = 1, y = 1 } } } })
    World.set(GL, "patternsOpen", true)
    return buy, v
end

-- The drawn pattern row's state: nil when no pattern row shows.
local function row()
    GL.Refresh()
    local _, rows = GL.Drawn()
    for _, r in ipairs(rows) do
        if r:IsShown() and r.line and r.line.kind == "pattern" then
            return { owned = r.owned, tint = r.ownTint and r.ownTint:IsShown() or false }
        end
    end
end

T.test("a pattern whose skill is not reached does not pulse", function()
    scene(80, 175)
    T.eq(row(), { owned = false, tint = false })
end)

T.test("a pattern at the character's skill pulses green, and stops when the skill is lost", function()
    scene(175, 175)
    T.eq(row(), { owned = true, tint = true })
    scene(174, 175)
    T.eq(row(), { owned = false, tint = false }, "one point short")
end)

T.test("a pattern the recipe of which is already known does not pulse", function()
    local _, v = scene(200, 175)
    T.eq(row().owned, true)
    World.set(CP.charDB, "learned", { [ALCHEMY] = { v.spell } })
    T.eq(row().owned, false, "learned: the pulse stops")
end)

T.test("a known price the purse cannot meet stops the pulse; an unknown price does not", function()
    scene(200, 175, 5000)
    World.patch("GetMoney", function() return 4999 end)
    T.eq(row().owned, false, "one copper short")
    World.patch("GetMoney", function() return 5000 end)
    T.eq(row().owned, true, "enough")
    scene(200, 175, nil)
    World.patch("GetMoney", function() return 0 end)
    T.eq(row().owned, true, "no price known: skill and not-known decide")
end)

T.test("a profession the character does not have never pulses", function()
    scene(200, 175)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function() return nil end)
    T.eq(row().owned, false)
end)
