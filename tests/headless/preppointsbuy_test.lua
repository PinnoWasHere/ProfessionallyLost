-- Maker rows in buy mode play to their end (decision 0008). Gate on 43759fe, Engineering and
-- Leatherworking buy runs:
--   * "Silver Contact 122-123 ~11 crafts plays to 127.7" and "Cured Rugged Hide 225-232 ~24 crafts plays
--     to 234.5": both rows kept their product's count (11 contacts, 24 hides) as crafts, though one craft
--     makes 5 contacts or 2 hides (rule 1).
--   * "Whirring Bronze Gizmo 138-145 ~15 crafts plays to 147.7": Ice Deflector took in Bronze Framework
--     160-167 after the settle sized the gizmos (rule 9).
--   * "Coarse Blasting Powder 75-90 ~45 crafts plays to 95.0": the powder also drops, so it is no prep,
--     yet the row kept every later step's powder (rule 10).

local CP = ProfLost
local GT = CP.GuideTab
local ENGINEERING, LEATHERWORKING = 202, 165
local SILVER_CONTACT, CURED_RUGGED_HIDE = 3973, 19047
local POWDER, GIZMO, FRAMEWORK, DEFLECTOR = 3929, 3942, 3953, 3957
local DUROTAR = 1411

local function scene(prof)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [prof] = { rank = 1, max = 75 } }, bags = {} })
    World.set(CP.db, "collect", false)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    CraftWorld.Open(prof)
    T.advance(1)
    CP.Panel:Refresh()
    T.advance(0.3)
end

local function rowOf(spell)
    for _, row in ipairs(GT.ui.rows or {}) do
        if row.spell == spell and not row.side and not (row.rank or row.train) then return row end
    end
end

-- The row's count makes what later rows keep, and played from its start it ends at the row's end.
local function check(label, prof, spell, crafts, keep)
    scene(prof)
    local row = rowOf(spell)
    T.ok(row ~= nil, label .. ": the plan has the row")
    if not row then
        CraftWorld.Close()
        return
    end
    local played = CP.Solver.Play(row.recipe, row.from, row.crafts)
    print(("PREPPOINTSBUY|%s|%s %d-%d x%d keep %s|plays to %.2f"):format(label, row.recipe.name, row.from, row.to,
        row.crafts, row.keep and row.keep.count or "-", played))
    T.eq(row.keep and row.keep.count, keep, label .. ": the row keeps its product's count")
    T.eq(row.crafts, crafts, label .. ": the row's count is the crafts that make it")
    T.ok(math.abs(played - row.to) <= 1, ("%s: %d crafts from %d play to %.1f, not %d"):format(label, row.crafts,
        row.from, played, row.to))
    local c = CP.Plan.Committed(prof)
    for _, f in ipairs(c and c.steps or {}) do
        if f[3] == spell and f[2] == row.to then
            T.eq(f[9], crafts, label .. ": the saved step's count is the same crafts")
        end
    end
    CraftWorld.Close()
end

T.test("Engineering, buy mode: Silver Contact makes 11 contacts in 3 crafts", function()
    check("Engineering", ENGINEERING, SILVER_CONTACT, 3, 11)
end)

T.test("Leatherworking, buy mode: Cured Rugged Hide makes 24 hides in 12 crafts", function()
    check("Leatherworking", LEATHERWORKING, CURED_RUGGED_HIDE, 12, 24)
end)

local function text(row)
    return row and ("%s %d-%d x%d"):format(row.recipe.name, row.from, row.to, row.crafts) or "none"
end

-- Main rows of `spell`, in order.
local function rowsOf(spell)
    local out = {}
    for _, row in ipairs(GT.ui.rows or {}) do
        if row.spell == spell and not row.side and not (row.rank or row.train) then out[#out + 1] = row end
    end
    return out
end

local function plays(row)
    return row and CP.Solver.Play(row.recipe, row.from, row.crafts) or 0
end

T.test("Engineering, buy mode: Ice Deflector does not take in Bronze Framework 160-167", function()
    scene(ENGINEERING)
    local gizmo, frames, deflector = rowOf(GIZMO), rowsOf(FRAMEWORK), rowOf(DEFLECTOR)
    print(("PREPPOINTSBUY|rule 9|%s keep %s plays %.2f|%s|%s|%s"):format(text(gizmo),
        gizmo and gizmo.keep and gizmo.keep.count or "-", plays(gizmo), text(frames[1]), text(frames[2]),
        text(deflector)))
    T.ok(gizmo and math.abs(plays(gizmo) - gizmo.to) <= 1, "the gizmo row plays to its end: " .. text(gizmo))
    T.eq(text(gizmo), "Whirring Bronze Gizmo 138-145 x11", "the gizmo row")
    T.eq(gizmo and gizmo.keep and gizmo.keep.count, 8, "the gizmo row keeps the deflectors' 8")
    T.eq(text(frames[2]), "Bronze Framework 160-167 x11", "Bronze Framework keeps its own step")
    T.eq(text(deflector), "Ice Deflector 167-175 x8", "Ice Deflector starts where the framework ends")

    -- The pattern keeps its "or" rows over its own range.
    local sides = 0
    for _, row in ipairs(GT.ui.rows or {}) do
        if row.side and row.from == 167 and row.to == 175 then sides = sides + 1 end
    end
    T.ok(sides > 0, "Ice Deflector has its 'or' rows")
    CraftWorld.Close()
end)

T.test("Engineering, buy mode: the powder row keeps only what its crafts make", function()
    scene(ENGINEERING)
    local row = rowOf(POWDER)
    T.ok(row ~= nil, "the plan has the powder row")
    if not row then
        CraftWorld.Close()
        return
    end
    GT.Pick(row)
    T.advance(0.3)
    local note = GT.ui.details.sale:GetText() or ""
    print(("PREPPOINTSBUY|rule 10|%s keep %s plays %.2f|%s"):format(text(row), row.keep and row.keep.count or "-",
        plays(row), note))
    T.ok(math.abs(plays(row) - row.to) <= 1, "the powder row plays to its end: " .. text(row))
    T.eq(text(row), "Coarse Blasting Powder 75-90 x17", "the powder row")
    T.eq(row.keep and row.keep.count, 17, "it keeps its own 17")
    T.ok(note:find("Keep 17 for Coarse Dynamite, Large Copper Bomb", 1, true) ~= nil, "card note: " .. note)
    CraftWorld.Close()
end)
