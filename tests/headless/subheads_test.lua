-- A gathering profession's section in Follow the guide splits its skill-up rows from the rows
-- for what the guides need, under two small headings. A crafting profession's section has none.
-- Scene: Stonetalon's Charred Vale, Skinning 233, the guide short of Medium Leather.

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local SKIN, STONETALON = 393, 1442
local MEDIUM, ALCHEMY, DUROTAR, PEACEBLOOM = 2319, 171, 1411, 2447

local function scene(needs)
    MapWorld.begin({ zone = STONETALON, x = 0.33, y = 0.68, level = 30, side = "Horde", shareSolves = true })
    for _, key in ipairs({ "routeSkip", "skinSkip", "gatherClosed", "farmClosed" }) do World.set(CP.db, key, nil) end
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", true)
    World.set(CP.db, "routeMode", nil)
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "panelProf", nil)
    World.set(CP.charDB, "gatherNeeds", needs)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN then return { skillID = id, rank = 233, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 3 end)
    World.set(CP.GatherPanel, "Showing", function() return true end)
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    World.set(G, "UpdateAllNeeds", function() end)
    G.ResetClusters()
    World.onEnd(function()
        G.ResetClusters()
        RM.Update(false, {})
    end)
end

-- The Skinning section's lines, header first.
local function skinning()
    GL.Refresh()
    for _ = 1, 60 do
        T.advance(1)
        if not RM.ZonesReport()[1]:find("running", 1, true) then break end
    end
    T.advance(1)
    local out, inside = {}, false
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "section" then inside = l.key == SKIN end
        if inside then out[#out + 1] = l end
    end
    return out
end

local function pos(lines, pred)
    for i, l in ipairs(lines) do
        if pred(l) then return i end
    end
end

local function head(text) return function(l) return l.subhead and l.text == text end end

T.test("Skill-ups lists what gives points; For your guides holds the needs and their grind spots", function()
    scene({ [165] = { [MEDIUM] = 50 } })
    local lines = skinning()
    local skill = pos(lines, head(GL.SKILLUPS_HEAD))
    local guide = pos(lines, head(GL.GUIDE_HEAD))
    local firstUp = pos(lines, function(l) return l.kind == "source" and not l.spot and l.skill end)
    local firstSpot = pos(lines, function(l) return l.kind == "source" and l.spot end)
    local firstItem = pos(lines, function(l) return l.kind == "item" end)
    T.ok(skill and guide and firstUp and firstSpot and firstItem, "both headings, skill-ups, a need and its spots")
    if not (skill and guide and firstUp and firstSpot and firstItem) then return end
    T.ok(skill < firstUp and firstUp < guide and guide < firstItem and firstItem < firstSpot,
        "skill-ups lead; the need, then its grind spots, follow under the guide heading")
    for i = skill + 1, guide - 1 do
        local l = lines[i]
        T.ok(not l.spot, "no grind spot under Skill-ups: " .. tostring(l.text))
        local up = l.skill and CP.GatherGuide.Band(233, l.skill) > 0
        T.ok(up, "every Skill-ups line gives points at 233: " .. tostring(l.text) .. " " .. tostring(l.info))
    end
    T.eq(lines[1].info, nil, "the section header no longer carries the column note")
    T.eq(lines[guide].info, "have / need", "the guide-needs heading carries it")
    T.eq(lines[skill].textColor, CP.Style.color.label, "label ink")
end)

T.test("only one heading shows when only one kind of row exists", function()
    scene({ [165] = { [MEDIUM] = 50 } })
    World.set(GL, "SkillUpLines", function() return {} end)
    local lines = skinning()
    T.eq(pos(lines, head(GL.SKILLUPS_HEAD)), nil, "no skill-up rows, no heading")
    T.ok(pos(lines, head(GL.GUIDE_HEAD)), "guide rows keep theirs")
end)

T.test("only the Skill-ups heading shows when the guides need nothing here", function()
    scene({})
    local lines = skinning()
    T.ok(pos(lines, head(GL.SKILLUPS_HEAD)), "skill-up rows keep theirs")
    T.eq(pos(lines, head(GL.GUIDE_HEAD)), nil, "no guide rows, no heading")
    T.eq(pos(lines, function(l) return l.spot end), nil, "no grind spot without a need")
end)

T.test("a crafting profession's section has no headings", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.db, "collect", true)
    World.set(CP.db, "routeMode", nil)
    World.set(CP.charDB, "gatherNeeds", { [ALCHEMY] = { [PEACEBLOOM] = 20 } })
    World.set(CP.charDB, "gatherSoon", nil)
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        return (id == ALCHEMY or id == 182) and { skillID = id, rank = 40, modifier = 0, maxRank = 300 } or nil
    end)
    World.set(CP.Window, "Professions", function() return { { id = ALCHEMY, name = "Alchemy" } } end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.charDB, "panelProf", ALCHEMY)
    G.ResetClusters()
    World.onEnd(function() G.ResetClusters() end)
    GL.Refresh()
    local sawItem = false
    for _, l in ipairs((GL.Drawn())) do
        T.ok(not l.subhead, "no heading line: " .. tostring(l.text))
        sawItem = sawItem or l.kind == "item"
        if l.kind == "section" and l.key == ALCHEMY then T.eq(l.info, "have / need") end
    end
    T.ok(sawItem, "the Alchemy section still lists its herb")
end)

-- Folding -------------------------------------------------------------------------------
-- Each heading folds like the section header above it: a click on its row hides its rows,
-- a folded heading shows a dim count of them, and the fold is saved per character by
-- profession and heading.

local MINING = 186

-- The drawn row showing the heading `text`, or nil.
local function headRow(text)
    local _, rows = GL.Drawn()
    for _, r in ipairs(rows) do
        if r:IsShown() and r.line and r.line.subhead and r.line.text == text then return r end
    end
end

local function click(r) r:GetScript("OnClick")(r, "LeftButton") end

-- The lines between heading `text` and the next heading or the section's end.
local function under(lines, text)
    local out, inside = {}, false
    for _, l in ipairs(lines) do
        if l.subhead then inside = l.text == text
        elseif inside then out[#out + 1] = l end
    end
    return out
end

T.test("a click on Skill-ups folds its rows and leaves the guide's; a second click opens them", function()
    scene({ [165] = { [MEDIUM] = 50 } })
    World.set(CP.charDB, "gatherSubClosed", nil)
    local lines = skinning()
    local ups = #under(lines, GL.SKILLUPS_HEAD)
    local needs = #under(lines, GL.GUIDE_HEAD)
    T.ok(ups > 0 and needs > 0, "both headings start open with rows under them")
    local r = headRow(GL.SKILLUPS_HEAD)
    T.ok(r, "the Skill-ups heading is drawn")
    if not r then return end
    T.ok(r.toggle:IsShown() and r.toggle.open, "it wears the section's chevron, open")
    click(r)
    lines = skinning()
    T.eq(#under(lines, GL.SKILLUPS_HEAD), 0, "folded, Skill-ups hides its rows")
    T.eq(#under(lines, GL.GUIDE_HEAD), needs, "For your guides keeps its rows")
    T.eq(CP.charDB.gatherSubClosed[SKIN .. ":" .. GL.SUB_SKILLUPS], true, "saved per character by profession")
    r = headRow(GL.SKILLUPS_HEAD)
    T.ok(r and not r.toggle.open, "the chevron reads closed")
    T.eq(r and r.count:GetText(), tostring(ups), "a dim count of what it hides")
    click(r)
    lines = skinning()
    T.eq(#under(lines, GL.SKILLUPS_HEAD), ups, "a second click opens it again")
    T.eq(CP.charDB.gatherSubClosed[SKIN .. ":" .. GL.SUB_SKILLUPS], nil, "open is the default, saved as nothing")
    r = headRow(GL.SKILLUPS_HEAD)
    T.eq(r and r.count:GetText(), "", "an open heading shows no count")
end)

T.test("folded For your guides keeps the column note and hides its items and grind spots", function()
    scene({ [165] = { [MEDIUM] = 50 } })
    World.set(CP.charDB, "gatherSubClosed", nil)
    local lines = skinning()
    local hides = 0
    for _, l in ipairs(under(lines, GL.GUIDE_HEAD)) do
        if l.kind == "item" or l.spot then hides = hides + 1 end
    end
    click(headRow(GL.GUIDE_HEAD))
    lines = skinning()
    T.eq(#under(lines, GL.GUIDE_HEAD), 0, "folded, no item or grind spot shows")
    T.ok(#under(lines, GL.SKILLUPS_HEAD) > 0, "Skill-ups stays open")
    local r = headRow(GL.GUIDE_HEAD)
    T.eq(r and r.line.info, "have / need", "the column note stays on the heading")
    T.eq(r and r.info:GetText(), "have / need", "and is drawn")
    T.eq(r and r.count:GetText(), tostring(hides), "the count is its items and grind spots")
end)

T.test("a fold is kept per profession and heading, and survives a reload", function()
    scene({ [165] = { [MEDIUM] = 50 } })
    World.set(CP.charDB, "gatherSubClosed", { [MINING .. ":" .. GL.SUB_SKILLUPS] = true,
        [SKIN .. ":" .. GL.SUB_GUIDE] = true })
    local lines = skinning()
    T.ok(#under(lines, GL.SKILLUPS_HEAD) > 0, "Mining's folded Skill-ups leaves Skinning's open")
    T.eq(#under(lines, GL.GUIDE_HEAD), 0, "Skinning's saved guide fold holds after a reload")
end)

T.test("a folded section still hides its headings", function()
    scene({ [165] = { [MEDIUM] = 50 } })
    World.set(CP.charDB, "gatherSubClosed", nil)
    World.set(CP.db, "gatherClosed", { [SKIN] = true })
    local lines = skinning()
    T.eq(#lines, 1, "only the section header shows")
    T.ok(lines[1] and lines[1].closed, "and it reads closed")
end)

T.test("the count shows only when it fits beside the heading", function()
    scene({ [165] = { [MEDIUM] = 50 } })
    World.set(CP.charDB, "gatherSubClosed", { [SKIN .. ":" .. GL.SUB_SKILLUPS] = true })
    skinning()
    local r = headRow(GL.SKILLUPS_HEAD)
    T.ok(r and r.count:GetText() ~= "", "the count shows at the list's width")
    local measure = GL.Measure
    World.set(GL, "Measure", function(text, size, fixed)
        if tostring(text):match("^%d+$") then return GL.width end
        return measure(text, size, fixed)
    end)
    skinning()
    r = headRow(GL.SKILLUPS_HEAD)
    T.eq(r and r.count:GetText(), "", "no room, no count")
end)
