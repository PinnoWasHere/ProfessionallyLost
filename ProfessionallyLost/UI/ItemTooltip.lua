local _, CP = ...
if CP.stopped then return end

-- Item tooltips name what the player's guides still need of the item, how many are in
-- the bags, bank and mail, and the best zone to farm it.

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

-- The lines for `item`: { { left, right, leftColor, rightColor } }.
function ItemTooltip.Lines(item)
    local needs = ItemTooltip.Needs(item)
    if #needs == 0 then return {} end
    local c = S.color
    local lines, total = {}, 0
    for _, n in ipairs(needs) do
        if not n.made then total = total + n.need end
        lines[#lines + 1] = { ("%s needs x%d"):format(n.name, n.need), nil, c.label }
    end
    local held = have(item)
    local short = total - held
    if total == 0 then
        lines[#lines + 1] = { ("Have %d · the guide makes these"):format(held), nil, c.label }
        return lines
    end
    lines[#lines + 1] = short > 0
        and { ("Have %d · short x%d"):format(held, short), nil, c.warn }
        or { ("Have %d · enough"):format(held), nil, c.good }
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

function ItemTooltip.Add(tooltip, item)
    if not (CP.db and CP.db.itemTooltip) or not readable(item) then return false end
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
