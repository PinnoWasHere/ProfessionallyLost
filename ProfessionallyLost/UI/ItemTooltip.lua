local _, CP = ...
if CP.stopped then return end

-- Item tooltips name what the player's guides still need of the item, how many are in
-- the bags, bank and mail, and the best zone to farm it. An ore names the guides' need of
-- the bar it smelts into and how much ore is left to mine after the ore held.

local ItemTooltip = {}
CP.ItemTooltip = ItemTooltip

local S = CP.Style
local G = CP.Gather

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- Bags, bank, mail and purchases not yet in the mailbox, as the checklist counts them.
local function have(item) return CP.Purchases.Have(item) end
ItemTooltip.Have = have

-- What each guide still needs of `item`: { { name, need, made } }, largest first. `made` marks
-- an item the guide's own crafts make (Bolt of Linen Cloth), which its raw materials already cover.
function ItemTooltip.Needs(item)
    local out = {}
    for key, needs in pairs(CP.charDB and CP.charDB.gatherNeeds or {}) do
        local n = needs[item]
        local guide = CP.Guides and CP.Guides[key]
        if n and n > 0 and guide then out[#out + 1] = { name = guide.name, need = n, made = guide.prep and guide.prep[item] ~= nil or nil } end
    end
    table.sort(out, function(a, b) return a.need > b.need end)
    return out
end

-- The guides' raw need of `item`: the sum of Needs less what their own crafts make.
local function rawNeed(item)
    local total = 0
    for _, n in ipairs(ItemTooltip.Needs(item)) do
        if not n.made then total = total + n.need end
    end
    return total
end

-- Item -> the smelts (GatherData.smelt) that take it: { { spell, r = recipe, count } }, built once.
local smeltsUsing
local function usedBy(item)
    if not smeltsUsing then
        smeltsUsing = {}
        for spell, r in pairs(CP.GatherData and CP.GatherData.smelt or {}) do
            for _, pair in ipairs(r.reagents or {}) do
                local list = smeltsUsing[pair[1]] or {}
                smeltsUsing[pair[1]] = list
                list[#list + 1] = { spell = spell, r = r, count = pair[2] }
            end
        end
        for _, list in pairs(smeltsUsing) do table.sort(list, function(a, b) return a.spell < b.spell end) end
    end
    return smeltsUsing[item]
end

-- What the guides still need of bar `bar` as Mining smelts it: { needs = Needs(bar), chain =
-- { { item, n } }, total, held, short }. `chain` holds the bars smelted from it (Bronze Bar takes a
-- Copper Bar), each with the bars of `bar` its shortfall asks. Each stage counts what the bags,
-- bank and mail hold of its own bar first, BAR_DEPTH deep.
ItemTooltip.BAR_DEPTH = 3
function ItemTooltip.BarNeed(bar, depth)
    depth = depth or 1
    local out = { needs = ItemTooltip.Needs(bar), chain = {}, total = rawNeed(bar), held = have(bar) }
    for _, s in ipairs(depth < ItemTooltip.BAR_DEPTH and usedBy(bar) or {}) do
        local into = ItemTooltip.BarNeed(s.r.makes, depth + 1)
        if into.short > 0 then
            local n = math.ceil(into.short / (s.r.yield or 1)) * s.count
            out.chain[#out.chain + 1] = { item = s.r.makes, n = n }
            out.total = out.total + n
        end
    end
    out.short = math.max(0, out.total - out.held)
    return out
end

-- The ore a bar shortfall of `short` takes by smelt `s`, less `held` ore: ore, mine.
function ItemTooltip.OreShort(s, short, held)
    local ore = math.ceil(short / (s.r.yield or 1)) * s.count
    return ore, math.max(0, ore - held)
end

-- "(40 ore held, mine 30)", "(mine 70 ore)" or "(70 ore held, smelt them)".
function ItemTooltip.OreText(ore, mine)
    local held = ore - mine
    if held <= 0 then return ("(mine %d ore)"):format(mine) end
    if mine <= 0 then return ("(%d ore held, smelt them)"):format(ore) end
    return ("(%d ore held, mine %d)"):format(held, mine)
end

-- An ore's lines: for each bar it smelts into that a guide needs, who needs how many, the bars held,
-- and the ore the shortfall takes less the ore held ("Have 30 · short x70 (40 ore held, mine 30)").
-- `left` is the ore held beyond the guides' own need of it. Returns the ore still to mine.
local function smeltLines(item, lines, left)
    local c, mined = S.color, 0
    -- An ore is mined from a node and no smelt makes it; a bar or Coal takes no lines here.
    if CP.Farm.SmeltsOf(item) or not CP.Sourcing.FromNodes(item) then return 0 end
    for _, s in ipairs(usedBy(item) or {}) do
        local bar = s.r.makes
        local need = ItemTooltip.BarNeed(bar)
        if need.total > 0 then
            lines[#lines + 1] = { ("Smelts into %s"):format(CP.ItemName(bar) or "a bar"), nil, c.text }
            for _, n in ipairs(need.needs) do
                if not n.made then lines[#lines + 1] = { ("%s needs x%d"):format(n.name, n.need), nil, c.label } end
            end
            for _, ch in ipairs(need.chain) do
                lines[#lines + 1] = { ("x%d more for %s"):format(ch.n, CP.ItemName(ch.item) or "another bar"), nil, c.label }
            end
            local ore, mine = ItemTooltip.OreShort(s, need.short, left)
            left = math.max(0, left - ore)
            lines[#lines + 1] = need.short > 0
                and { ("Have %d · short x%d %s"):format(need.held, need.short, ItemTooltip.OreText(ore, mine)), nil,
                      mine > 0 and c.warn or c.good }
                or { ("Have %d · enough"):format(need.held), nil, c.good }
            mined = mined + mine
        end
    end
    return mined
end

-- The lines for `item`: { { left, right, leftColor, rightColor } }. An ore also gets the guide
-- need of the bars it smelts into.
function ItemTooltip.Lines(item)
    local needs = ItemTooltip.Needs(item)
    local c = S.color
    local lines, total = {}, 0
    for _, n in ipairs(needs) do
        if not n.made then total = total + n.need end
        lines[#lines + 1] = { ("%s needs x%d"):format(n.name, n.need), nil, c.label }
    end
    local held = have(item)
    local short = total - held
    if #needs > 0 and total == 0 then
        lines[#lines + 1] = { ("Have %d · the guide makes these"):format(held), nil, c.label }
    elseif #needs > 0 then
        lines[#lines + 1] = short > 0
            and { ("Have %d · short x%d"):format(held, short), nil, c.warn }
            or { ("Have %d · enough"):format(held), nil, c.good }
    end
    short = math.max(0, short) + smeltLines(item, lines, math.max(0, -short))
    if #lines == 0 then return lines end
    -- The farm zone comes from what is already known; a new search runs in the background
    -- and the line says so until it is done.
    if short > 0 then
        local best, known = CP.Farm.Find(item, {
            level = G.PlayerLevel(), side = UnitFactionGroup("player"), skills = G.Skills(),
            continent = (CP.Waypoint.PlayerWorld()),
        })
        if best then
            local info = C_Map.GetMapInfo(best.zone)
            local here = best.zone == G.PlayerZone()
            lines[#lines + 1] = { "Farm in " .. (info and info.name or "?"),
                here and "you're here" or nil, c.text, c.good }
        elseif not known then
            lines[#lines + 1] = { "Farm in", CP.GatherGuide.WARM.waiting, c.text, c.muted }
        end
    end
    return lines
end

-- Nothing while the lines are left to Glowey's Recipes.
function ItemTooltip.Add(tooltip, item)
    if not (CP.db and CP.db.itemTooltip) or not readable(item) then return false end
    if CP.Glowey and CP.Glowey.Handed("tooltip") then return false end
    local lines = ItemTooltip.Lines(item)
    if #lines == 0 then return false end
    tooltip:AddLine(" ")
    local a = S.color.accent
    tooltip:AddLine("|T" .. CP.MEDIA .. "Icon:14:14|t Professionally Lost", a[1], a[2], a[3])
    for _, l in ipairs(lines) do
        local lc, rc = l[3] or S.color.text, l[4] or S.color.muted
        if l[2] then
            tooltip:AddDoubleLine(l[1], l[2], lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
        else
            tooltip:AddLine(l[1], lc[1], lc[2], lc[3])
        end
    end
    tooltip:Show()
    return true
end

-- Registered at login, after every addon loaded with the UI has added its own, so
-- ProfLost's lines come last.
local registered = false
function ItemTooltip.Register()
    local types = _G.Enum and _G.Enum.TooltipDataType
    if registered or not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and types and types.Item) then
        return
    end
    registered = true
    TooltipDataProcessor.AddTooltipPostCall(types.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= rawget(_G, "ItemRefTooltip") then return end
        local id = data and data.id
        if readable(id) then ItemTooltip.Add(tooltip, id) end
    end)
end
CP:On("PLAYER_LOGIN", ItemTooltip.Register)
