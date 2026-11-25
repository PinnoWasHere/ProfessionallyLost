-- The guide with no window open (Plan.Shut) shows the steps, stops and "or" rows the open
-- window (Plan.Current) shows for the same character. Only what needs the live list may
-- differ: craftable counts, the live spell a guide recipe is crafted through, and recipes
-- the game marks grey.

local CP = ProfLost
local LINES = { 129, 164, 165, 171, 185, 197, 202, 333 }
local SKILLS = { 1, 60, 160 }
local DUROTAR = 1411

-- Every row the list draws: main steps, stops and "or" rows, without craftable counts.
local function rows(live)
    local out = {}
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        local kind = row.rank and "rank" or row.train and "train" or row.side and "or" or "step"
        local stop = row.rank or row.train
        out[#out + 1] = ("%s:%s-%s:%s:%s:%s"):format(kind, tostring(row.at or row.from), tostring(row.to),
            tostring(row.spell or (stop and (stop.name or stop.skill))), tostring(row.crafts), tostring(row.learned))
    end
    return table.concat(out, ";")
end

-- The first row two row lists differ at.
local function firstDiff(a, b)
    local pa, pb = {}, {}
    for part in a:gmatch("[^;]+") do pa[#pa + 1] = part end
    for part in b:gmatch("[^;]+") do pb[#pb + 1] = part end
    for i = 1, math.max(#pa, #pb) do
        if pa[i] ~= pb[i] then return ("row %d: %s | %s"):format(i, tostring(pa[i]), tostring(pb[i])) end
    end
    return "same"
end

for _, collect in ipairs({ true, false }) do
    T.test(("shut and open draw the same rows (%s)"):format(collect and "collect" or "buy"), function()
        local bad = {}
        for _, line in ipairs(LINES) do
            for _, skill in ipairs(SKILLS) do
                MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
                CraftWorld.begin({ professions = { [line] = { rank = skill } } })
                World.set(CP.db, "collect", collect)
                CraftWorld.Open(line)
                T.advance(1)
                CP.charDB.lastPlan = nil
                CP.Plan.Invalidate()
                local open = rows(CP.Plan.Current())
                CraftWorld.Close()
                T.advance(0.5)
                CP.charDB.lastPlan = nil
                CP.Plan.Invalidate()
                local shut = rows(CP.Plan.Shut(line))
                if shut ~= open then
                    bad[#bad + 1] = ("%s %d: %s"):format(CP.Guides[line].name, skill, firstDiff(shut, open))
                end
                World.finish()
            end
        end
        T.eq(#bad, 0, table.concat(bad, "\n"))
    end)
end
