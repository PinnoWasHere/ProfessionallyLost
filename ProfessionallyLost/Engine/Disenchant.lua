local _, CP = ...
if CP.stopped then return end

-- Disenchanting: which group a green or blue falls in, what it yields, the skill it
-- needs, the bag queue, and whether selling it is worth more gold. Data is
-- CP.DisenchantData (Data/Disenchant.lua). Pure logic apart from Bags().

local Disenchant = {}
CP.Disenchant = Disenchant

Disenchant.SPELL = 13262      -- Disenchant
Disenchant.ENCHANTING = 333
Disenchant.SELL_MARGIN = 1.1  -- selling must beat disenchanting by this much to warn

local KIND = { [2] = "weapon", [4] = "armor" }
local BAGS = 4                 -- backpack 0 and bags 1-4

-- Skill needed to disenchant (Classic's item-level rule): greens up to item level 20
-- need 1, blues up to 25 need 25, then 25 more for every 5 item levels. Given a `group`
-- instead of an item, the skill its band needs (the band's lowest item level; bands are five
-- levels wide), or nil when no band names it.
function Disenchant.Skill(ilvl, quality, group)
    if group then
        local best
        for q, kinds in pairs(CP.DisenchantData.bands or {}) do
            for _, list in pairs(kinds) do
                local prev = 0
                for _, b in ipairs(list) do
                    local need = b[2] == group and Disenchant.Skill(prev + 1, q)
                    if need and (not best or need < best) then best = need end
                    prev = b[1]
                end
            end
        end
        return best
    end
    if quality == 2 and ilvl <= 20 then return 1 end
    if quality == 3 and ilvl <= 25 then return 25 end
    if quality ~= 2 and quality ~= 3 then return nil end
    return 25 * math.ceil((ilvl - 20) / 5)
end

-- The disenchant group of an item: the data's own entry, else the band for its
-- quality, kind (weapon or armor) and item level. Nil when it can't be disenchanted.
function Disenchant.Group(itemID, quality, ilvl, classID)
    local D = CP.DisenchantData
    if D.items[itemID] then return D.items[itemID] end
    local kind = KIND[classID]
    local bands = kind and D.bands[quality] and D.bands[quality][kind]
    if not bands or #bands == 0 then return nil end
    for _, b in ipairs(bands) do
        if ilvl <= b[1] then return b[2] end
    end
    return bands[#bands][2]
end

-- Expected materials per disenchant: { { item, count } }, likeliest first.
function Disenchant.Yield(group)
    local out = {}
    for _, g in ipairs(CP.DisenchantData.groups[group] or {}) do
        out[#out + 1] = { item = g[1], count = g[2] / 100 * g[3] }
    end
    return out
end

-- Gold worth of one disenchant at `priceFn(item)` prices: the sum of chance x price over
-- the priced materials. Second result lists the items with no price (nil when all are
-- priced); the value is then a floor. Nil value when no material has a price.
function Disenchant.Value(group, priceFn)
    local total, priced, missing = 0, 0, nil
    for _, y in ipairs(Disenchant.Yield(group)) do
        local p = priceFn(y.item)
        if p then
            total = total + p * y.count
            priced = priced + 1
        else
            missing = missing or {}
            missing[#missing + 1] = y.item
        end
    end
    if priced == 0 then return nil, missing end
    return total, missing
end

-- A money text for an advice's disenchant value: "at least 1g 20s" when it is a floor.
function Disenchant.Money(a, amount)
    local text = CP.Pricing.Format(amount or a.de)
    return a.floor and ("at least " .. text) or text
end

-- Disenchant or sell? `info` = { group, vendor, ah, name }: ah is what the item sells
-- for at auction after the cut (nil when bound or unknown). Materials are worth their
-- auction price, which is also what buying them instead would cost.
-- Returns { de, vendor, ah, verdict = "de" | "sell" | "unknown", text }.
function Disenchant.Advice(info, priceFn, nameOf)
    local de, missing = Disenchant.Value(info.group, priceFn)
    local out = { de = de, vendor = info.vendor, ah = info.ah, floor = de and missing and true or nil,
        missing = de and missing or nil }
    local fmt = CP.Pricing.Format
    if not de then
        out.verdict = "unknown"
        out.text = info.vendor and info.vendor > 0 and ("No auction prices; vendor %s"):format(fmt(info.vendor))
            or "No auction prices"
        return out
    end
    local sell = math.max(info.vendor or 0, info.ah or 0)
    local deText = Disenchant.Money(out)

    -- A floor value is compared as it stands, so an unpriced material can only make
    -- "sell" appear early, never hide it.
    if sell > de * Disenchant.SELL_MARGIN then
        out.verdict = "sell"
        local main = Disenchant.Yield(info.group)[1]
        local mat = main and nameOf and nameOf(main.item) or "the materials"
        if (info.ah or 0) >= (info.vendor or 0) then
            out.text = ("Sells for %s at auction; disenchanting gives %s. Sell it and buy %s."):format(
                fmt(info.ah), deText, mat)
        else
            out.text = ("Vendor pays %s; disenchanting gives %s. Sell it and buy %s."):format(
                fmt(info.vendor), deText, mat)
        end
    else
        out.verdict = "de"
        out.text = ("Disenchanting gives %s; selling %s."):format(deText, fmt(sell))
    end
    return out
end

-- Greens and blues in the bags: { { bag, slot, itemID, name, link, quality, ilvl,
-- classID, bound, vendor, icon } }. Items whose data hasn't loaded are asked for.
function Disenchant.Bags()
    local out = {}
    for bag = 0, BAGS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local c = C_Container.GetContainerItemInfo(bag, slot)
            if c and c.itemID and (c.quality == 2 or c.quality == 3) then
                local name, link, _, ilvl, _, _, _, _, _, icon, vendor, classID = C_Item.GetItemInfo(c.itemID)
                if name then
                    out[#out + 1] = { bag = bag, slot = slot, itemID = c.itemID, name = name, link = c.hyperlink or link,
                        quality = c.quality, ilvl = ilvl or 0, classID = classID, bound = c.isBound,
                        vendor = vendor or 0, icon = c.iconFileID or icon }
                else
                    CP.RequestItem(c.itemID)
                end
            end
        end
    end
    return out
end

-- An item a guide made for Enchanting's dust: disenchanting it is the plan, so it is never
-- told "sell". `advice` keeps both values; `sellBetter` says when selling would pay more.
function Disenchant.ForDust(advice)
    local fmt = CP.Pricing.Format
    local sell = math.max(advice.vendor or 0, advice.ah or 0)
    advice.sellBetter = advice.verdict == "sell"
    advice.verdict = "dust"
    advice.text = advice.de and ("Made for Enchanting's dust. Disenchanting gives %s; selling %s."):format(
        Disenchant.Money(advice), fmt(sell)) or "Made for Enchanting's dust."
    return advice
end

-- The disenchant queue from bag items: those the player's `skill` can disenchant and
-- that aren't in `ignored` (unless `showIgnored`), each with group, yield and advice.
-- `planned` = { [itemID] = count } marks that many of each item `forDust`, in bag order
-- (Disenchant.ForDust). Made for dust first, then disenchant by best value, unknowns,
-- and "sell" ones last.
function Disenchant.Queue(items, skill, ignored, priceFn, ahFn, nameOf, showIgnored, planned)
    local out, left = {}, {}
    for id, n in pairs(planned or {}) do left[id] = n end
    for _, it in ipairs(items) do
        local need = Disenchant.Skill(it.ilvl, it.quality)
        local group = need and Disenchant.Group(it.itemID, it.quality, it.ilvl, it.classID)
        local skip = ignored[it.itemID] and not showIgnored
        if group and need <= skill and not skip then
            it.group, it.need, it.ignored = group, need, ignored[it.itemID] == true
            it.yield = Disenchant.Yield(group)
            local ah = not it.bound and ahFn(it.itemID) or nil
            it.advice = Disenchant.Advice({ group = group, vendor = it.vendor, ah = ah and math.floor(ah * 0.95) },
                priceFn, nameOf)
            it.forDust = nil
            if (left[it.itemID] or 0) >= 1 then
                left[it.itemID] = left[it.itemID] - 1
                it.forDust = true
                Disenchant.ForDust(it.advice)
            end
            out[#out + 1] = it
        end
    end
    local rank = { dust = 0, de = 1, unknown = 2, sell = 3 }
    table.sort(out, function(a, b)
        if a.ignored ~= b.ignored then return not a.ignored end
        local ra, rb = rank[a.advice.verdict], rank[b.advice.verdict]
        if ra ~= rb then return ra < rb end
        if (a.advice.de or 0) ~= (b.advice.de or 0) then return (a.advice.de or 0) > (b.advice.de or 0) end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return out
end

