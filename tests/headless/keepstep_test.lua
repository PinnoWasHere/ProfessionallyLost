-- An update never swaps out the step the player is working on (decision 0007 rule 1). Owner,
-- 2026-11-27: "Make sure we don't change players' current step in case they've been working
-- towards it. I don't want to surprise them with new stuff. It should take over after their next
-- completed step." The case: Leatherworking 165, Green Whelp Bracers 165-175 with 4 of 10 made,
-- saved before the reach rule while Skinning 165 can't skin the scale yet.
-- Each upgrade below leaves the current step's recipe, end, crafts left and material targets as
-- they were: the reach rule's one-time check, a guide data change that moves the picks, a reload,
-- and the version 4 to 5 check. The steps after it re-plan; once the step is done, the new plan
-- takes over.

local CP = ProfLost
local GT = CP.GuideTab
local LW, SKIN, ENCHANTING = 165, 393, 333
local SCALE, BRACERS = 7392, 9202
local SWAMP = 1435

local LEATHER = { [SCALE] = true, [4304] = true, [8170] = true }

local function character(skin, extra)
    MapWorld.begin({ zone = SWAMP, level = 38, side = "Alliance" })
    local profs = { [LW] = { rank = 165, max = 225 }, [SKIN] = { rank = skin, max = 225 } }
    for line, spec in pairs(extra or {}) do profs[line] = spec end
    CraftWorld.begin({ professions = profs })
    CraftWorld.Learn(LW, BRACERS)
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    World.patch("C_Item.GetItemInfoInstant", function(id)
        if LEATHER[id] then return id, "", "", "", 0, 7, 6 end
        return id, "", "", "", 0, 15, 0
    end)
    CP.Plan.Invalidate()
end

-- A plan saved mid-way through the Bracers: 4 of 10 made, a second Bracers step after it.
local function saved(fields)
    local ctx = CP.Plan.Context(LW)
    local c = { version = CP.Plan.COMMIT_VERSION, ctx = ctx, skill = 165, shown = true, made = 4,
                curKey = "9202:165:175", current = 1,
                steps = { { 165, 175, BRACERS, nil, 10, nil, nil, nil, 10 },
                          { 175, 185, BRACERS, nil, 10, nil, nil, nil, 10 } } }
    for k, v in pairs(fields or {}) do c[k] = v end
    World.set(CP.charDB, "committed", { [LW] = { [ctx] = c } })
    World.set(CP.charDB, "lastPlan", nil)
end

local function mainRows()
    local out = {}
    for _, row in ipairs(GT.ui.rows) do
        if row.spell and not row.side and not (row.rank or row.train) then out[#out + 1] = row end
    end
    return out
end

-- The current step as the guide draws it: recipe, range, crafts left and each material's target.
local function look()
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel:Refresh()
    local rows = mainRows()
    local cur = rows[1]
    if not cur then
        CraftWorld.Close()
        return "nothing", rows
    end
    GT.Pick(cur)
    T.advance(0.3)
    local mats = {}
    for _, l in ipairs(GT.ui.details.rows) do
        if l:IsShown() and l.itemID then
            local text = l.count:GetText() or ""
            mats[#mats + 1] = l.itemID .. " x" .. (text:match("/ (%d+)") or text)
        end
    end
    table.sort(mats)
    local text = ("%d %d-%d x%d | %s"):format(cur.spell, cur.from, cur.to, cur.crafts or 0, table.concat(mats, ", "))
    CraftWorld.Close()
    return text, rows
end

local function layout(rows)
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = ("%d %d-%d x%d"):format(row.spell, row.from, row.to, row.crafts or 0) end
    return table.concat(out, "; ")
end

local WANT = "9202 165-175 x6"

T.test("the reach check keeps the current Bracers step and re-plans the steps after it", function()
    character(165)
    saved({ reach = true })
    local before = look()
    T.eq(before:sub(1, #WANT), WANT, "the held plan shows the Bracers with 6 left")

    character(165)
    saved()
    local after, rows = look()
    print(("KEEPSTEP|reach|%s|%s|rows %s"):format(before, after, layout(rows)))
    T.eq(after, before, "the reach check leaves the current step and its materials alone")
    local c = CP.Plan.Committed(LW)
    T.ok(c and c.reach, "the plan is marked checked")
    for i = 2, #rows do
        T.ok(rows[i].spell ~= BRACERS, ("a later Bracers step %d-%d is gone: %s"):format(rows[i].from, rows[i].to, layout(rows)))
    end

    -- The step is done: the reach rule now applies to the whole guide.
    CraftWorld.SetSkill(LW, 175)
    CP.Plan.Invalidate()
    local done, next = look()
    print(("KEEPSTEP|next|%s|rows %s"):format(done, layout(next)))
    T.ok(#next > 0, "a plan after the Bracers")
    for _, row in ipairs(next) do
        T.ok(row.spell ~= BRACERS, ("no Bracers step %d-%d once the scale's out of reach: %s"):format(row.from, row.to, layout(next)))
    end
end)

T.test("a guide data change that moves the picks leaves the current step alone", function()
    character(170)
    saved({ reach = true })
    local before = look()
    T.eq(before:sub(1, #WANT), WANT, "the held plan shows the Bracers with 6 left")

    -- The scale now takes a hundred times the skins: a fresh solve leaves the Bracers out.
    local item = CP.Guides[LW].items[SCALE]
    World.set(item, 4, item[4] * 100)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    CP.Plan.Invalidate()
    local fresh = look()
    T.ok(fresh:sub(1, 5) ~= "9202 ", "a fresh solve picks another step: " .. fresh)

    saved({ reach = true })
    CP.Plan.Invalidate()
    local after = look()
    print(("KEEPSTEP|data|%s|%s|fresh %s"):format(before, after, fresh))
    T.eq(after, before, "the saved plan's current step holds")
end)

T.test("a reload keeps the current step", function()
    character(170)
    saved({ reach = true })
    local before = look()
    T.eq(before:sub(1, #WANT), WANT, "the held plan shows the Bracers with 6 left")
    CP.Plan.ForgetBook()
    CP.Plan.Invalidate()
    local after = look()
    print(("KEEPSTEP|reload|%s|%s"):format(before, after))
    T.eq(after, before, "the current step holds")
end)

T.test("the version 5 check keeps the current step of a plan that took Enchanting's credit", function()
    local ench = { [ENCHANTING] = { rank = 100, max = 150 } }
    character(170, ench)
    saved({ reach = true })
    local before = look()
    T.eq(before:sub(1, #WANT), WANT, "the held plan shows the Bracers with 6 left")
    T.ok(CP.Shared.Disenchants(CP.Guides[LW]), "the guide's greens disenchant, so a version 4 plan took the credit")

    character(170, ench)
    saved({ reach = true, version = 4 })
    local after = look()
    print(("KEEPSTEP|version|%s|%s"):format(before, after))
    T.eq(after, before, "the current step holds")
    T.eq(CP.Plan.Committed(LW).version, CP.Plan.COMMIT_VERSION, "re-marked as the current version")
end)
