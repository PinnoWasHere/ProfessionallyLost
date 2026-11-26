local _, CP = ...
if CP.stopped then return end

-- Impromptu crafts: learned recipes of the shown profession that still give points and that
-- spare raw loot in the bags makes now. Vendor goods never limit a craft; the row says what to buy. Spare means beyond what the plans still need, so the
-- plan never moves. The guide's step card shows the best few (GuideTab).

local Impromptu = {}
CP.Impromptu = Impromptu

-- Rows the guide's area holds. It keeps this height when empty.
Impromptu.ROWS = 3

local TRADE_GOODS = 7

-- Trade goods subclasses that are raw loot when no recipe makes them: cloth and meat (eggs too).
-- Leather, hides, scales, ore, stone, herbs and fish count through the gathering loot instead,
-- so smelted bars and cured hides never do.
Impromptu.LOOT_SUBCLASS = { [5] = true, [8] = true }

-- Every item the gathering data lists as loot (skinning, nodes, pools, creature drops), and
-- every item a guide recipe makes, built once.
local looted, made
local function sets()
    if looted then return looted, made end
    looted, made = {}, {}
    local D = CP.GatherData
    for _, item in ipairs(D and D.Index("looted") or {}) do looted[item] = true end
    for _, g in pairs(CP.Guides or {}) do
        for _, r in pairs(g.recipes or {}) do
            if r.makes then made[r.makes] = true end
        end
    end
    return looted, made
end

-- The one rule for raw material. Raw is what the player gathers, skins, fishes, loots or buys
-- from a vendor without limit (thread, dye, salt, vials). Bars, bolts, cured hides, potions,
-- greens and every other made item are not.
function Impromptu.IsRaw(guide, itemID)
    local item = guide and guide.items and guide.items[itemID]
    if item and item[2] then return true end
    local loot, makes = sets()
    if loot[itemID] then return true end
    if CP.Pricing and CP.Pricing.IsFish(itemID) then return true end
    if makes[itemID] then return false end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return classID == TRADE_GOODS and Impromptu.LOOT_SUBCLASS[subclassID] == true
end

-- What the plans still need, every guided profession summed (Gather.Needs, to 300), plus what
-- a needed made material is made from (the cloth for a needed bolt): { [itemID] = count }.
function Impromptu.Needs()
    local out = {}
    for item, n in pairs(CP.Gather.Needs()) do out[item] = (out[item] or 0) + n end
    local direct = {}
    for item, n in pairs(out) do direct[item] = n end
    for item, n in pairs(direct) do
        for _, g in pairs(CP.Guides or {}) do
            local maker = g.prep and g.prep[item] and g.recipes[g.prep[item]]
            if maker then
                local runs = math.ceil(n / (maker.yield or 1))
                for _, pair in ipairs(maker.reagents or {}) do
                    out[pair[1]] = (out[pair[1]] or 0) + pair[2] * runs
                end
                break
            end
        end
    end
    return out
end

-- How many of `itemID` the bags hold beyond `need`. The bank covers the need first but is
-- never offered, since a craft can't use it.
function Impromptu.Spare(itemID, need)
    local bags = C_Item.GetItemCount(itemID) or 0
    local held = math.max(bags, C_Item.GetItemCount(itemID, true) or 0)
    return math.max(0, math.min(bags, held - (need or 0)))
end

-- Crafts worth making from `cover` crafts' materials at `skill` under `cap`, and the points they
-- are expected to give (Guide.Chance, skill rising as they land).
local function expected(recipe, skill, cap, cover)
    local s, pts, n = skill, 0, 0
    while n < cover do
        local at = math.floor(s)
        local p = at < cap and CP.Guide.Chance(recipe, at) or 0
        if p <= 0 then break end
        local up = p * (recipe.ups or 1)
        pts, s, n = pts + up, s + up, n + 1
    end
    return n, pts
end

-- What one craft's materials cost at vendor price, for ties.
local function cost(guide, recipe)
    local total = 0
    for _, pair in ipairs(recipe.reagents or {}) do
        local item = guide.items and guide.items[pair[1]]
        total = total + (item and item[1] or 0) * pair[2]
    end
    return total
end

-- The impromptu crafts for `live` (Plan.Current or Plan.Shut), best first, at most `limit`:
-- { { spell, recipe, name, crafts, now, points, buy, perCraft } }. `spell` is the player's own
-- spell. `now` is how many the bags make before buying; `buy` is what the crafts still need bought.
-- Recipes the plan has a step for are left to the step card.
function Impromptu.List(live, limit, needs)
    local guide, p = live and live.guide, live and live.prof
    if not (guide and p and live.plan) or p.skill >= p.max then return {} end
    needs = needs or Impromptu.Needs()
    local inPlan = {}
    for _, st in ipairs(live.plan) do
        if st.spell then inPlan[st.spell] = true end
    end
    local learned, dead = live.learned or {}, live.dead or {}
    local out, spare = {}, {}
    for id, r in pairs(guide.recipes) do
        local ok = learned[id] and not dead[id] and not inPlan[id] and r.makes and r.reagents and #r.reagents > 0
            and not (CP.Deskill and CP.Deskill.Is(r)) and CP.Guide.Chance(r, p.skill) > 0
            and not CP.Guide.MissingTool(guide, r)
        local cover, loot, vendor = math.huge, false, {}
        for _, pair in ipairs(ok and r.reagents or {}) do
            local item = guide.items and guide.items[pair[1]]
            if item and item[2] then
                -- Sold without limit: never limits the count, bought when the bags lack it.
                vendor[#vendor + 1] = pair
            elseif Impromptu.IsRaw(guide, pair[1]) then
                loot = true
                spare[pair[1]] = spare[pair[1]] or Impromptu.Spare(pair[1], needs[pair[1]])
                cover = math.min(cover, math.floor(spare[pair[1]] / pair[2]))
            else
                ok = false
                break
            end
        end
        ok = ok and loot
        if ok and cover >= 1 then
            local n, pts = expected(r, p.skill, p.max, cover)
            if n > 0 then
                local buy, now = {}, n
                for _, pair in ipairs(vendor) do
                    local held = C_Item.GetItemCount(pair[1]) or 0
                    now = math.min(now, math.floor(held / pair[2]))
                    local short = n * pair[2] - held
                    if short > 0 then
                        local name = CP.ItemName(pair[1])
                        if not name or name == "" then name = nil end
                        buy[#buy + 1] = { itemID = pair[1], count = short, name = name or ("item " .. pair[1]) }
                    end
                end
                out[#out + 1] = { spell = live.alias and live.alias[id] or id, guideID = id, recipe = r, name = r.name,
                                  crafts = n, now = now, points = pts, buy = buy,
                                  perCraft = CP.Guide.Chance(r, p.skill) * (r.ups or 1), cost = cost(guide, r) }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.perCraft ~= b.perCraft then return a.perCraft > b.perCraft end
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.name < b.name
    end)
    for i = #out, (limit or #out) + 1, -1 do out[i] = nil end
    return out
end

-- "x4  ·  ~3 pts  ·  buy 4 Coarse Thread" for a row. With `card`, the All view's short line
-- "Heavy Silk Bandage x23 · ~7.2 pts", which leaves the buy list to the Single view. The
-- optional `fits(text)` says whether a line fits its room. When it does not, a card's name or
-- a row's buy list is cut short with an ellipsis, so the count and points always show.
function Impromptu.Info(item, card, fits)
    local pts = math.floor(item.points * 10 + 0.5) / 10
    local text = pts == math.floor(pts) and ("%d"):format(pts) or ("%.1f"):format(pts)
    if card then
        local tail = (" x%d · ~%s pts"):format(item.crafts, text)
        local name = item.name
        local line = name .. tail
        while fits and #name > 1 and not fits(line) do
            name = name:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")   -- one whole character
            line = name:gsub("%s+$", "") .. "…" .. tail
        end
        return line
    end
    local out = ("x%d  ·  ~%s pts"):format(item.crafts, text)
    local lead = "  ·  buy"
    local tail = ""
    for _, b in ipairs(item.buy or {}) do tail = tail .. ("%s %d %s"):format(lead, b.count, b.name) end
    local line = out .. tail
    while fits and tail ~= "" and not fits(line) do
        tail = tail:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")   -- one whole character
        local kept = tail:gsub("[%s·]+$", "")
        if #kept <= #lead then
            -- "buy…" is the least that says something must be bought; the tooltip lists it.
            local least = out .. lead .. "…"
            return fits(least) and least or out
        end
        line = out .. kept .. "…"
    end
    return line
end
