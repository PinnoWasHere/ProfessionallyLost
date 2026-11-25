-- Blacksmithing specializations: only a Weaponsmith trains Blight, only an Armorsmith trains
-- Truesilver Breastplate (classic-db: their trainers' TrainerSpell). The guide offers such a
-- recipe only to a character holding that specialization, and plans the others around it.

local CP = ProfLost
local BS = 164
local DUROTAR = 1411
local WEAPONSMITH, ARMORSMITH = 9787, 9788
local BLIGHT, BREASTPLATE = 10011, 9974

-- The guide's rows for a Horde Blacksmith at 200/300 holding `spec` (a spell, or nil). Without
-- "Gather it yourself" the plan has Blight as an "or" row where the character may learn it.
local function rowsFor(spec)
    MapWorld.begin({ zone = DUROTAR, level = 60, side = "Horde" })
    CraftWorld.begin({ professions = { [BS] = { rank = 200, max = 300 } } })
    World.set(CP.db, "collect", false)
    World.patch("C_SpellBook.IsSpellKnown", function(id) return spec ~= nil and id == spec end)
    CraftWorld.Open(BS)
    T.advance(1)
    return CP.GuideTab.RowsOf(CP.Plan.Current())
end

-- The rows that send the character to learn recipe `spell` (a step, an "or" row or a visit to a
-- trainer), as text.
local function offered(rows, spell)
    local recipe, out = CP.Guides[BS].recipes[spell], {}
    for _, row in ipairs(rows) do
        for _, r in ipairs(row.train and row.train.recipes or {}) do
            if r == recipe then out[#out + 1] = ("train at %d"):format(row.train.skill) end
        end
        if not row.train and row.spell == spell and row.learned == false then
            out[#out + 1] = ("%s %d-%d"):format(row.side and "or" or "step", row.from, row.to)
        end
    end
    return table.concat(out, ", ")
end

T.test("the guide data names the specialization each specialist recipe asks", function()
    local recipes = CP.Guides[BS].recipes
    T.eq(recipes[BLIGHT].spec, WEAPONSMITH, "Blight asks Weaponsmith")
    T.eq(recipes[BREASTPLATE].spec, ARMORSMITH, "Truesilver Breastplate asks Armorsmith")
end)

T.test("an Armorsmith is never offered Blight", function()
    T.eq(offered(rowsFor(ARMORSMITH), BLIGHT), "", "Blight rows for an Armorsmith")
end)

T.test("a character with no specialization is never offered Truesilver Breastplate or Blight", function()
    local rows = rowsFor(nil)
    T.eq(offered(rows, BREASTPLATE), "", "Truesilver Breastplate rows without a specialization")
    T.eq(offered(rows, BLIGHT), "", "Blight rows without a specialization")
end)

T.test("a Weaponsmith is still offered Blight", function()
    T.ok(offered(rowsFor(WEAPONSMITH), BLIGHT) ~= "", "a Weaponsmith's guide offers Blight")
end)

T.test("a recipe that asks a specialization is learnable only while the spellbook holds it", function()
    local guide, side = CP.Guides[BS], "H"
    local blight = guide.recipes[BLIGHT]
    World.patch("C_SpellBook.IsSpellKnown", function() return false end)
    T.eq(CP.Sourcing.CanLearn(guide, BLIGHT, blight, {}, side), false, "without Weaponsmith")
    T.eq(CP.Sourcing.CanLearn(guide, BLIGHT, blight, { [BLIGHT] = true }, side), true, "a known recipe stays usable")
    World.patch("C_SpellBook.IsSpellKnown", function(id) return id == WEAPONSMITH end)
    T.eq(CP.Sourcing.CanLearn(guide, BLIGHT, blight, {}, side), true, "with Weaponsmith")
end)
