-- A profession window whose recipe list is still on the way (CraftWorld's "list" mode:
-- the profession answers, IsDataSourceChanging is true, the list is empty) plans from
-- what ProfLost already knows, not from an empty list, and takes the live list when it comes.

local CP = ProfLost
local TAILOR = 197

local function rows(live)
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        local kind = row.rank and "rank" or row.train and "train" or row.side and "or" or "step"
        out[#out + 1] = ("%s:%s:%s:%s"):format(kind, tostring(row.from or row.at), tostring(row.spell),
            tostring(row.learned))
    end
    return table.concat(out, ";")
end

-- Known recipes the plan's rows call unlearned or send to a trainer.
local function wrongRows(live)
    local known = CraftWorld.state.profs[TAILOR].known
    local bad = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        if row.spell and known[row.spell] and (row.learned == false or row.train) then
            bad[#bad + 1] = live.guide.recipes[row.spell].name
        end
    end
    return bad
end

local function character()
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 60, max = 75 } } })
    World.set(CP.db, "collect", true)
end

T.test("a read profession's late list: the saved list until the live one comes", function()
    character()
    CraftWorld.Open(TAILOR)
    T.advance(1)
    local want = rows(CP.Plan.Current())
    T.ok(CP.Plan.Read(TAILOR), "the list was read and saved")
    CraftWorld.Close()

    CraftWorld.Open(TAILOR, "list")
    T.advance(1)
    T.ok(CP.Professions.Changing(), "the list is on its way")
    local live = CP.Plan.Current()
    T.ok(live ~= nil and live.guide ~= nil, "a guided plan")
    local bad = wrongRows(live)
    T.eq(#bad, 0, "known recipes planned as known: " .. table.concat(bad, ", "))
    T.ok(not live.unread, "read before, so not unread")

    CraftWorld.DataArrives()
    T.advance(1)
    T.eq(rows(CP.Plan.Current()), want, "the live list's plan once it arrives")
end)

T.test("a never-read profession's late list says it is unread, then plans from the list", function()
    character()
    World.set(C_SpellBook, "IsSpellKnown", function() return false end)
    CraftWorld.Open(TAILOR, "list")
    T.advance(1)
    local live = CP.Plan.Current()
    T.ok(live ~= nil and live.unread == true, "unread until the list comes")
    T.ok(CP.Plan.OpenOnce(live) ~= nil, "the step says so")
    CraftWorld.DataArrives()
    T.advance(1)
    live = CP.Plan.Current()
    T.ok(not live.unread, "read once it arrives")
    local bad = wrongRows(live)
    T.eq(#bad, 0, "known recipes planned as known: " .. table.concat(bad, ", "))
end)
