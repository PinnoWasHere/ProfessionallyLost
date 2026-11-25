-- One profession changing another's guide: every row the coupling changed names its cause,
-- and the coupling's setting off gives the guide the character would have without the
-- other profession (owner, 2026-11-16: "show the enchanting dependency or allow the user to
-- toggle these dependencies on or off like fishing and cooking").

local CP = ProfLost
local ENCHANTING, TAILOR, BS, ALCHEMY, COOKING, FISHING, ENG = 333, 197, 164, 171, 185, 356, 202
local ZONE = { Horde = 1411, Alliance = 1429 }
local ARMORSMITH = 9788

-- A character with `line` at `skill` and the professions in `extra`; each crafting one's
-- window opened once, so its needs are saved, as play does.
local function character(line, skill, side, extra, settings)
    MapWorld.begin({ zone = ZONE[side], level = 20, side = side })
    local profs = { [line] = { rank = skill, max = 75 } }
    for _, y in ipairs(extra or {}) do profs[y] = { rank = CP.Guides[y] and 1 or skill, max = 75 } end
    CraftWorld.begin({ professions = profs })
    World.set(CP.db, "collect", true)
    for k, v in pairs(settings or {}) do World.set(CP.db, k, v) end
    for _, y in ipairs(extra or {}) do
        if CP.Guides[y] then
            CraftWorld.Open(y)
            T.advance(0.5)
            CP.Plan.Current()
            CraftWorld.Close()
            T.advance(0.5)
        end
    end
end

-- `line`'s guide rows, from a fresh solve.
local header
local function rows(line)
    CP.charDB.lastPlan = nil
    CP.charDB.committed = nil
    CP.Plan.Invalidate()
    CraftWorld.Open(line)
    T.advance(0.5)
    local live = CP.Plan.Current()
    local out = CP.GuideTab.RowsOf(live)
    -- The header's coupling words for this plan, whichever profession the window shows.
    header = CP.GuideTab.WithText(live)
    CraftWorld.Close()
    return out
end

-- A row as the influence check compares it.
local function sig(row)
    if row.rank then return "rank " .. tostring(row.rank.name) end
    if row.train then
        local names = {}
        for i, r in ipairs(row.train.recipes) do names[i] = r.name end
        table.sort(names)
        return ("train at %d: %s"):format(row.train.skill, table.concat(names, ","))
    end
    return ("%s%s %d-%d x%.2f"):format(row.side and "or " or "", tostring(row.spell), row.from, row.to, row.crafts or 0)
end

-- The rows of `with` that `solo` does not show.
local function changed(solo, with)
    local count = {}
    for _, r in ipairs(solo) do count[sig(r)] = (count[sig(r)] or 0) + 1 end
    local out = {}
    for _, r in ipairs(with) do
        local s = sig(r)
        if (count[s] or 0) > 0 then count[s] = count[s] - 1 else out[#out + 1] = r end
    end
    return out
end

local function names(text, words)
    local low = tostring(text or ""):lower()
    for _, w in ipairs(words) do
        if low:find(w, 1, true) then return true end
    end
    return false
end

-- X alone against X with Y: something changes. Each changed row Y picked names Y in its info
-- column; a row that moved only because an earlier step did names no profession and its card
-- says nothing of it (owner, 2026-11-18: "'moved because an earlier step changed' means nothing
-- at all to me"). The header names Y.
local function marked(line, skill, side, y, words, settings)
    character(line, skill, side, nil, settings)
    local solo = rows(line)
    character(line, skill, side, { y }, settings)
    local with = rows(line)
    local diff = changed(solo, with)
    T.ok(#diff > 0, "the coupling changes the guide")
    for _, row in ipairs(diff) do
        local _, name, info = CP.GuideTab.RowTexts(row)
        if row.cause and row.cause.shifted then
            T.ok(not names(info, words), ("moved row %q names no profession: %q"):format(tostring(name), tostring(info)))
            T.eq(CP.GuideTab.CauseText(row), nil, tostring(name) .. "'s card says nothing about it")
        else
            T.ok(names(info, words), ("changed row %q names its cause: %q"):format(tostring(name), tostring(info)))
        end
    end
    T.ok(names(header, words), "the header names it: " .. tostring(header))
    return diff, with
end

T.test("Tailoring with Enchanting: every changed row, trainer visits too, names Enchanting", function()
    marked(TAILOR, 1, "Alliance", ENCHANTING, { "disenchant", "enchanting" })
end)

T.test("Blacksmithing with Alchemy: every changed row names Alchemy", function()
    -- Alchemy changes the plan through Truesilver Breastplate, which only an Armorsmith trains.
    World.patch("C_SpellBook.IsSpellKnown", function(id) return id == ARMORSMITH end)
    local diff = marked(BS, 1, "Horde", ALCHEMY, { "alchemy" })
    -- A step that uses what Alchemy makes says so on its card.
    local direct
    for _, row in ipairs(diff) do
        if row.spell and not (row.rank or row.train or row.side) and row.cause and row.cause.own then direct = row end
    end
    T.ok(direct ~= nil, "a step uses a material Alchemy makes")
    if not direct then return end
    CraftWorld.Open(BS)
    T.advance(0.5)
    local live = CP.Plan.Current()
    for _, row in ipairs(CP.GuideTab.RowsOf(live)) do
        if row.key == direct.key then direct = row end
    end
    CP.GuideTab.Pick(direct)
    T.advance(0.3)
    local sale = CP.GuideTab.ui.details.sale:GetText() or ""
    T.ok(sale:find("Alchemy", 1, true) ~= nil, "the card says Alchemy: " .. sale)
end)

T.test("Enchanting with Engineering: every changed row names Engineering", function()
    marked(333, 1, "Horde", ENG, { "engineering" })
end)

-- Simulator finding, 2026-11-16 (nightly triples): Engineering changes Enchanting's plan, so its
-- saved needs and the disenchant credit Tailoring takes from them; Tailoring's changed rows
-- named Enchanting only. A step the credit chose names Enchanting first, then what shaped its needs.
T.test("Tailoring with Enchanting and Engineering: a step the credit chose names what shaped Enchanting's needs", function()
    character(TAILOR, 1, "Horde", { ENCHANTING })
    for _, row in ipairs(rows(TAILOR)) do
        local _, name, info = CP.GuideTab.RowTexts(row)
        T.ok(not names(info, { "engineering" }), ("without Engineering, %q names none: %q"):format(tostring(name), tostring(info)))
    end
    character(TAILOR, 1, "Horde", { ENCHANTING, ENG })
    T.ok(CP.charDB.needsShapedBy and CP.charDB.needsShapedBy[ENCHANTING] ~= nil,
        "Enchanting's saved needs remember that Engineering changed its plan")
    local credited = 0
    for _, row in ipairs(rows(TAILOR)) do
        if row.cause and row.cause.de then
            credited = credited + 1
            local _, name, info = CP.GuideTab.RowTexts(row)
            T.eq(row.cause.lines[1], ENCHANTING, "its own cause, the credit, comes first")
            T.ok(names(info, { "disenchant" }) and names(info, { "engineering" }),
                ("credit row %q names disenchant, then Engineering: %q"):format(tostring(name), tostring(info)))
        end
    end
    T.ok(credited > 0, "the credit chose a step")
end)

T.test("Cooking with Fishing: the fish rows name Fishing", function()
    marked(COOKING, 1, "Horde", FISHING, { "fishing" })
end)

T.test("Cooking with Fishing, Fish for Cooking off: the guide Cooking alone shows", function()
    character(COOKING, 1, "Horde", nil, { fishCook = false })
    local solo = rows(COOKING)
    character(COOKING, 1, "Horde", { FISHING }, { fishCook = false })
    local with = rows(COOKING)
    local diff = changed(solo, with)
    T.eq(#diff, 0, "no row differs: " .. (diff[1] and sig(diff[1]) or ""))
    T.eq(#with, #solo, "as many rows")
end)

T.test("Fish for Cooking's description says what turning it off does", function()
    local s = CP.Settings.Find("fishCook")
    T.ok(not s.desc:find("either way", 1, true), s.desc)
    T.ok(s.desc:find("Cooking guide", 1, true) ~= nil, s.desc)
end)

-- The game answers herbs as Trade Goods > Herb, from the herb nodes' loot, so Herbalism gates them.
local function herbClasses()
    local classes = {}
    local D = CP.GatherData
    for _, n in pairs(D.nodes) do
        if n[4] == 182 then
            for _, l in ipairs(D.loot[n[3]] or {}) do classes[l[1]] = { 7, 9, 182 } end
        end
    end
    GatherWorld.AnswerClasses(classes)
end

-- Simulator finding, 2026-11-16: with Herbalism, 32 of 34 Alchemy rows changed and none said why.
-- The header names Herbalism once; each changed step's card says what it gathers; the info
-- column stays clean.
T.test("Alchemy with Herbalism: the header names Herbalism and a changed step's card says what it gathers", function()
    herbClasses()
    character(ALCHEMY, 1, "Horde")
    local solo = rows(ALCHEMY)
    character(ALCHEMY, 1, "Horde", { 182 })
    local with = rows(ALCHEMY)
    local diff = changed(solo, with)
    T.ok(#diff > 0, "Herbalism changes the guide")
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.Open(ALCHEMY)
    T.advance(0.5)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    local ui = CP.GuideTab.ui
    T.ok((ui.skillText:GetText() or ""):find("^with Herbalism · 1 / 75") ~= nil, "header: " .. tostring(ui.skillText:GetText()))
    local card
    for _, row in ipairs(ui.rows) do
        local _, name, info = CP.GuideTab.RowTexts(row)
        T.ok(not tostring(info):find("Herbalism", 1, true), ("%s: the info column stays clean: %s"):format(tostring(name), tostring(info)))
        if not card and row.cause and row.cause.own and row.spell and not (row.rank or row.train or row.side) then card = row end
    end
    T.ok(card ~= nil, "a step on a recipe Herbalism let in")
    if card then
        CP.GuideTab.Pick(card)
        local sale = ui.details.sale:GetText() or ""
        T.ok(sale:find("^Your Herbalism gathers the .+ this uses$") ~= nil, "card: " .. sale)
    end
    CraftWorld.Close()
end)

T.test("Plan for Enchanting off: nothing names Enchanting as a cause", function()
    character(TAILOR, 1, "Alliance", { ENCHANTING }, { deEnchant = false })
    for _, row in ipairs(rows(TAILOR)) do
        T.ok(row.cause == nil, "no cause on " .. sig(row))
    end
end)

-- Owner report, 2026-11-18: Leatherworking with Skinning and Fishing tagged rows "Fishing" because
-- Essence of Water (a patch's loot) counted as a fish. Only a reliable catch makes Fishing a cause.
T.test("Fishing is no cause through rare fishing loot", function()
    for _, item in ipairs({ 7070, 7079, 7080, 20708, 20709, 21113, 21114 }) do
        T.ok(not CP.Pricing.IsFish(item), item .. " is rare fishing loot, not a catch")
    end
    for _, item in ipairs({ 6359, 6522, 13758, 3820 }) do
        T.ok(CP.Pricing.IsFish(item), item .. " is a catch")
    end
    MapWorld.begin({ zone = ZONE.Horde, level = 40, side = "Horde" })
    CraftWorld.begin({ professions = { [165] = { rank = 150, max = 225 }, [393] = { rank = 200, max = 300 },
                                       [FISHING] = { rank = 100, max = 150 } } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "fishCook", true)
    CP.charDB.lastPlan = nil
    CP.Plan.Invalidate()
    CraftWorld.Open(165)
    T.advance(0.5)
    local live = CP.Plan.Current()
    local checked = 0
    for _, st in ipairs(live.plan) do
        local r = st.spell and CP.Guides[165].recipes[st.spell]
        for _, line in ipairs(r and live.causes(st.spell, r) or {}) do
            T.ok(line ~= FISHING, ("%s %d-%d names Fishing"):format(r.name, st.from, st.to))
        end
        checked = checked + 1
    end
    T.ok(checked > 5, "the plan has steps")
    CraftWorld.Close()
end)
