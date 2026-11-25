-- A green is disenchanted for skill-ups only when that costs less than crafting the points
-- (DESKILL-01b). Early on the craft is Enchant Bracer - Inferior Stamina at one Mote of Magic (10c),
-- so a green's vendor sale value, less what its dust is worth, must stay under that.

local CP = ProfLost
local ENCHANTING = 333
local DUROTAR = 1411
local SPELL = 13262
local GLOVES = 4307           -- green, item level 15, disenchant group 1
local LATE = 4308             -- green, item level 22: needs skill 25
local DEAR = 4309             -- green, item level 15, with its own sale price
local DUST, LESSER = 10940, 10938
local MOTE, BRACER = 247786, 7418

-- A fresh Horde enchanter holding `gloves` greens that vendor for `sale` copper, and `dear` more
-- that vendor for `dearSale`. `prices`: auction prices by item, through DaylightMogul.
local function scene(gloves, sale, prices, dear, dearSale)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 } },
                       bags = { [GLOVES] = gloves or nil, [DEAR] = dear or nil },
                       items = { [GLOVES] = { 2, 15, 4, 1, sale, 1, 0 }, [DEAR] = { 2, 15, 4, 1, dearSale or sale, 1, 0 } } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    World.set(_G, "DaylightMogul", prices and { API = { Price = function(id) return prices[id] end } } or nil)
    World.patch("InCombatLockdown", function() return false end)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    return CP.Plan.Current()
end

local function steps(live)
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        if row.spell and not (row.rank or row.train or row.side) then out[#out + 1] = row end
    end
    return out
end

local function describe(rows)
    local parts = {}
    for i, row in ipairs(rows) do
        if i > 4 then break end
        parts[#parts + 1] = ("%s %s-%s x%s"):format(tostring(row.spell), tostring(row.from), tostring(row.to),
            tostring(row.crafts))
    end
    return table.concat(parts, "; ")
end

T.test("the 1-25 craft route uses Mote of Magic", function()
    local r = CP.Guides[ENCHANTING].recipes[BRACER]
    T.eq(#r.reagents, 1)
    T.eq(r.reagents[1][1], MOTE)
    local rows = steps(scene(0, 1))
    T.eq(rows[1].spell, BRACER, describe(rows))
    T.eq(rows[1].from, 1)
end)

T.test("a green that sells for less than a Mote of Magic craft is disenchanted", function()
    local rows = steps(scene(12, 5))
    T.eq(rows[1].spell, SPELL, describe(rows))
    T.eq(rows[1].crafts, 12)
end)

T.test("a green that sells for more than the craft costs is crafted past", function()
    local rows = steps(scene(12, 50))
    for _, row in ipairs(rows) do T.ok(row.spell ~= SPELL, "no disenchant step: " .. describe(rows)) end
    T.eq(rows[1].spell, BRACER, describe(rows))
end)

T.test("the dust a green gives counts against its sale value", function()
    -- Sells for 50c; group 1 gives 1.2 Strange Dust at 40c, worth 48c, so disenchanting nets 2c.
    local rows = steps(scene(12, 50, { [DUST] = 40 }))
    T.eq(rows[1].spell, SPELL, describe(rows))
    T.eq(rows[1].crafts, 12)
end)

T.test("the card says how many greens were left out for their price", function()
    -- Dust at 100c makes a disenchant worth 120c. The cheap greens net far less than a Mote of Magic
    -- craft; the dear ones sell for 132c and net 12c, more than the 10c craft.
    local live = scene(12, 5, { [DUST] = 100 }, 3, 132)
    local rows = steps(live)
    T.eq(rows[1].spell, SPELL, describe(rows))
    T.eq(rows[1].crafts, 12, "only the cheap greens: " .. describe(rows))
    T.eq(CP.Deskill.Skipped(), 3)
    local text = CP.Deskill.CardText(rows[1].crafts)
    T.eq(text, "Disenchant 12 greens; the Disenchant tab lists them\n3 greens sell for more than crafting these points costs")
    T.eq(CP.Deskill.Chosen()[1].net < 0, true, "the lowest net goes first")
end)
