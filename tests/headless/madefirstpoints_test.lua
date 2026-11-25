-- Made materials held in the bank, and the points their maker gives (decision 0008). A Horde
-- Engineer at skill 1, as in the property findings rowpoints-d61067463d and rowpoints-81d7a6f405.
--   * 5 Gold Power Core: "Gyrochronatom 170-175 ~6 crafts" needs 6, so the card says make 1 first.
--     That craft gives half a point at 170, and the 6 Gyrochronatoms after it play to 176.1.
--   * 5 Mithril Casing: Mithril Frag Bomb 230-233 uses them, yet the settle sized the casing row
--     after it as if the bank still held them. "Mithril Casing 233-239 ~16" plays to 240.4.

local CP = ProfLost
local W, GT = CP.Window, CP.GuideTab
local ENGINEERING = 202
local DUROTAR = 1411
local GOLD_CORE, MITHRIL_CASING = 10558, 10561
local GYRO, FRAG_BOMB, CASING = 3961, 12603, 12599

local function scene(item, count)
    MapWorld.begin({ zone = DUROTAR, level = 10, side = "Horde" })
    CraftWorld.begin({ professions = { [ENGINEERING] = { rank = 1, max = 75 } } })
    CraftWorld.SetBank(item, count)
    World.set(CP.db, "collect", false)
    World.set(CP.db, "deEnchant", true)
    World.set(CP.db, "fishCook", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
        GT.Forget()
    end)
    CraftWorld.Open(ENGINEERING)
    CraftWorld.Close()
    W.Update()
    W.Pick(ENGINEERING)
    CP.Panel:Refresh()
    T.advance(0.1)
end

local function rowOf(spell)
    for _, r in ipairs(GT.ui.rows) do
        if r.spell == spell and not (r.side or r.rank or r.train) then return r end
    end
end

-- Where row's count takes the skill: first the made materials its card says to make, while their
-- maker gives points, then the row's own crafts.
local function played(row)
    local guide = CP.Guides[ENGINEERING]
    local x, said = row.from, {}
    for _, pair in ipairs(row.recipe.reagents) do
        local maker = guide.prep[pair[1]] and guide.recipes[guide.prep[pair[1]]]
        local short = maker and GT.MakeShort(guide, row, { itemID = pair[1], need = pair[2],
            have = CP.Purchases.Have(pair[1]) }) or 0
        if short > 0 and CP.Guide.Chance(maker, math.floor(x)) > 0 then
            local runs = math.ceil(short / (maker.yield or 1))
            x = CP.Solver.Play(maker, x, runs)
            said[#said + 1] = ("%d %s"):format(runs, maker.name)
        end
    end
    local ended = CP.Solver.Play(row.recipe, x, row.crafts)
    return ended, ("%s %d-%d ~%d crafts%s plays to %.2f"):format(row.recipe.name, row.from, row.to, row.crafts,
        #said > 0 and (", with " .. table.concat(said, ", ") .. " first") or "", ended)
end

local function endsAtEnd(spell)
    local row = rowOf(spell)
    T.ok(row ~= nil, "the plan has a row for spell " .. spell)
    if not row then return end
    local ended, text = played(row)
    T.ok(math.abs(ended - row.to) <= 1, text)
end

T.test("Gyrochronatom with a Gold Power Core made first ends at its end", function()
    scene(GOLD_CORE, 5)
    endsAtEnd(GYRO)
end)

T.test("casings in the bank go to the bombs before the casing row", function()
    scene(MITHRIL_CASING, 5)
    endsAtEnd(FRAG_BOMB)
    endsAtEnd(CASING)
end)
