-- A recipe's tools (`tools = { itemID... }` on the guide recipe): a tool the bags lack reads on
-- the step card and in place of "Ready to craft" in Next up, the launcher and the All card
-- (simulator finding, 2026-11-16: no row or card named the Blacksmith Hammer, the Arclight
-- Spanner or the runed rods). The generator emits `tools` from Forever's SpellTotems and
-- TotemCategory, and the guide's `toolsAlso` names the items that serve for a tool.

local CP = ProfLost
local BS, ENCHANTING, ENGINEERING, LW = 164, 333, 202, 165
local HAMMER, COPPER_ROD, ARCANITE_ROD, SPANNER = 5956, 6218, 16207, 6219
local COPPER_CHAIN_BELT, INFERIOR_STAMINA, COPPER_MODULATOR, STORM_GAUNTLETS = 2661, 7418, 3926, 16661

local function list(t)
    return table.concat(t or {}, ",")
end

local function nameOf(id)
    local name = CP.ItemName(id)
    return name and name ~= "" and name or ("item " .. id)
end

T.test("the guide data carries the client's tools", function()
    T.eq(list(CP.Guides[BS].recipes[COPPER_CHAIN_BELT].tools), tostring(HAMMER), "Copper Chain Belt")
    T.eq(list(CP.Guides[ENCHANTING].recipes[INFERIOR_STAMINA].tools), tostring(COPPER_ROD), "Inferior Stamina")
    T.eq(list(CP.Guides[ENGINEERING].recipes[COPPER_MODULATOR].tools), HAMMER .. "," .. SPANNER, "Copper Modulator")
    -- Forever's SpellTotems gives Storm Gauntlets (Leatherworking there) no tool.
    T.eq(CP.Guides[LW].recipes[STORM_GAUNTLETS].tools, nil, "Storm Gauntlets")
    local also = CP.Guides[ENCHANTING].toolsAlso or {}
    T.ok(list(also[COPPER_ROD]):find(tostring(ARCANITE_ROD), 1, true) ~= nil, "an arcanite rod serves for a copper rod")
end)

T.test("an item that serves for the tool counts as the tool", function()
    local guide = CP.Guides[ENCHANTING]
    local r = { tools = { COPPER_ROD } }
    World.patch("C_Item.GetItemCount", function(item) return item == ARCANITE_ROD and 1 or 0 end)
    T.eq(CP.Guide.MissingTool(guide, r), nil, "a Runed Arcanite Rod in the bags")
    World.patch("C_Item.GetItemCount", function(item, bank) return item == ARCANITE_ROD and bank and 1 or 0 end)
    local tool = CP.Guide.MissingTool(guide, r)
    T.eq(tool and tool.text, ("Take %s from the bank"):format(nameOf(ARCANITE_ROD)), "only the bank holds the stand-in")
end)

-- Every recipe of `line`'s guide needs `tool`.
local function needEverywhere(line, tool)
    for _, r in pairs(CP.Guides[line].recipes) do World.set(r, "tools", { tool }) end
end

-- `line` at `rank` with its window open and the Guide tab drawn on the first step.
local function open(line, rank, bags)
    World.set(CP.charDB, "guideMode", "one")
    CraftWorld.begin({ professions = { [line] = { rank = rank, max = 75 } }, bags = bags or {} })
    CraftWorld.Open(line)
    T.advance(1)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    local ui = CP.GuideTab.ui
    for _, row in ipairs(ui.rows) do
        if row.spell and row.learned and not (row.rank or row.train or row.side) then
            CP.GuideTab.Pick(row)
            return ui, row
        end
    end
    return ui, nil
end

T.test("a tool the bags lack leads the step card", function()
    needEverywhere(BS, HAMMER)
    local ui, row = open(BS, 1)
    T.ok(row ~= nil, "a learned step")
    if not row then return end
    local sale = ui.details.sale:GetText() or ""
    T.ok(sale:find("^Needs " .. nameOf(HAMMER)) ~= nil, "card: " .. sale)
    CraftWorld.Close()
end)

T.test("with the tool in the bags the card says nothing of it", function()
    needEverywhere(BS, HAMMER)
    local ui, row = open(BS, 1, { [HAMMER] = 1 })
    if not row then return T.ok(false, "a learned step") end
    local sale = ui.details.sale:GetText() or ""
    T.ok(not sale:find(nameOf(HAMMER), 1, true), "card: " .. sale)
    CraftWorld.Close()
end)

T.test("a tool only the bank holds says to take it out", function()
    local guide = CP.Guides[BS]
    local r = { tools = { HAMMER } }
    World.patch("C_Item.GetItemCount", function(item, bank) return item == HAMMER and bank and 1 or 0 end)
    local tool = CP.Guide.MissingTool(guide, r)
    T.eq(tool and tool.text, ("Take %s from the bank"):format(nameOf(HAMMER)))
end)

T.test("a tool the guide makes reads Make <tool> first; Ready to craft gives way to it", function()
    local guide = CP.Guides[ENCHANTING]
    local maker
    for _, r in pairs(guide.recipes) do
        if r.makes == COPPER_ROD then maker = r end
    end
    T.ok(maker ~= nil, "the Enchanting guide makes the Runed Copper Rod")
    local first
    for id, r in pairs(guide.recipes) do
        if r.src == "auto" and not r.makes then first = { id = id, r = r } break end
    end
    T.ok(first ~= nil, "an enchant every Enchanter knows")
    if not first then return end
    World.set(first.r, "tools", { COPPER_ROD })
    local tool = CP.Guide.MissingTool(guide, first.r)
    T.eq(tool and tool.text, ("Make %s first"):format(nameOf(COPPER_ROD)))
    local text, missing = CP.Gather.ReadyText({ spell = first.id }, guide)
    T.eq(text, ("Make %s first"):format(nameOf(COPPER_ROD)), "Next up, the launcher and the All card")
    T.eq(missing, true)
    World.patch("C_Item.GetItemCount", function(item) return item == COPPER_ROD and 1 or 0 end)
    text, missing = CP.Gather.ReadyText({ spell = first.id }, guide)
    T.eq(text, ("Ready to cast %s"):format(first.r.name), "with the rod in the bags")
    T.eq(missing, nil)
end)
