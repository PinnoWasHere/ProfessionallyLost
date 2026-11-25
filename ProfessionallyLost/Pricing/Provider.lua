local _, CP = ...
if CP.stopped then return end

-- Material prices in copper. Order: a vendor that always stocks the item, then the
-- auction price (DaylightMogul's market price, else ProfLost's own scan in Scan.lua),
-- then the item's vendor list price as a rough estimate.

local Pricing = {}
CP.Pricing = Pricing

local MOGUL = "DaylightMogul"   -- optional addon global, looked up at call time
local SOURCE = "market"
-- Staple materials: any one priced means Mogul has scanned (its API has no count).
local STAPLES = { 2589, 2592, 4306, 2770, 2771, 2318, 2319, 2447, 765, 2835 }

local function mogul()
    local m = _G[MOGUL]
    return type(m) == "table" and type(m.API) == "table" and type(m.API.Price) == "function" and m.API or nil
end

-- True while DaylightMogul's price API is loaded.
function Pricing.HasMogul() return mogul() ~= nil end

local function mogulPrice(itemID)
    local api = mogul()
    if not api then return nil end
    local ok, price = pcall(api.Price, itemID, SOURCE)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

-- Mogul's price first, then our own scanned price of any age.
local function auctionPrice(itemID)
    local price = mogulPrice(itemID)
    if price then return price end
    return CP.Scan and CP.Scan.Price(itemID) or nil
end

-- True once DaylightMogul holds a market price for any staple material, or our own
-- scan holds any price for this realm and faction.
function Pricing.HasAuctionData()
    if CP.Scan and CP.Scan.HasData() then return true end
    if not mogul() then return false end
    for _, id in ipairs(STAPLES) do
        if mogulPrice(id) then return true end
    end
    return false
end

-- The auction price for an item, or nil.
function Pricing.Auction(itemID)
    return auctionPrice(itemID)
end

-- Seconds since our own scan saw the item's price; nil when the price is Mogul's or
-- there is none.
function Pricing.AuctionAge(itemID)
    if mogulPrice(itemID) or not CP.Scan then return nil end
    local price, seen = CP.Scan.Price(itemID)
    if not (price and seen) then return nil end
    local now = GetServerTime and GetServerTime() or time()
    return math.max(0, now - seen)
end

-- "5 min", "3 h", "2 d".
function Pricing.FormatAge(seconds)
    if seconds < 3600 then return ("%d min"):format(math.max(1, math.floor(seconds / 60))) end
    if seconds < 86400 then return ("%d h"):format(math.floor(seconds / 3600)) end
    return ("%d d"):format(math.floor(seconds / 86400))
end

-- New market data: plans re-rank on the next refresh.
CP:On("PLAYER_LOGIN", function()
    local api = mogul()
    if api and type(api.On) == "function" then
        api.On("PricesChanged", function()
            if CP.Plan and CP.Plan.Invalidate then CP.Plan.Invalidate() end
            if CP.Panel and CP.Panel.frame and CP.Panel.frame:IsShown() then CP.Panel:Refresh() end
        end)
    end
end)

-- `guideItem` is the guide's { vendorPrice, soldByVendor } entry for the item.
-- Returns price, source ("vendor", "auction" or "estimate"), or nil. A material made
-- only on a cooldown (guideItem.cooldown: Mooncloth) gets no estimate: its list price is
-- far below what it costs, so without an auction price it has none.
function Pricing.Get(itemID, guideItem)
    local listPrice = guideItem and guideItem[1] or 0
    local vendor = guideItem and guideItem[2] and listPrice > 0 and listPrice or nil

    -- A vendor good is always bought from the vendor, whatever the auction house lists.
    if vendor then return vendor, "vendor" end
    local ah = auctionPrice(itemID)
    if ah then return ah, "auction" end
    if listPrice > 0 and not (guideItem and guideItem.cooldown) then return listPrice, "estimate" end
    return nil
end

-- Level-as-you-go weighs materials by the work of collecting them, not by gold: a
-- farmed material costs the kills, skins or nodes one unit typically takes (guide
-- item field 4: ~1.6 for Light Leather, ~22 for Medium Hide); vendor stock costs
-- VENDOR_EFFORT, a short trip; anything else counts 1.
local VENDOR_EFFORT = 0.1

-- A fish is almost free while the player is levelling Fishing anyway: each cast that
-- gives a skill-up also lands one. With Fishing and Cooking paired, Cooking counts it
-- at FISH_EFFORT, so fish recipes win where they give points more cheaply.
local FISH_EFFORT = 0.5      -- cheaper than meat, not free: Cooking shouldn't outrun Fishing
local FISHING = 356
local fishSet

-- A pool's loot counts as a reliable catch only for the pool's own fish (a school gives its
-- fish 85% of the time), or a material that nodes give as well and the pool gives at
-- ALSO_FROM_NODES percent (Stranglekelp). Crates, wreckage and elemental patches give
-- their items too rarely to plan on.
local POOL_CATCH = 80
local ALSO_FROM_NODES = 20

-- True for an item the player can fish up reliably: a fish, or Stranglekelp. Rare finds
-- (crates, wreckage, a patch of Elemental Water) are not.
function Pricing.IsFish(itemID)
    if not fishSet then
        fishSet = {}
        local D = CP.GatherData
        for _, z in pairs(D and D.zones or {}) do
            for _, l in ipairs(z.fish and D.loot[z.fish.loot] or {}) do fishSet[l[1]] = true end
        end
        for _, n in pairs(D and D.nodes or {}) do
            if n[4] == FISHING then
                for _, l in ipairs(D.loot[n[3]] or {}) do
                    if l[2] >= POOL_CATCH or l[2] >= ALSO_FROM_NODES and CP.Sourcing.FromNodes(l[1]) then
                        fishSet[l[1]] = true
                    end
                end
            end
        end
    end
    return fishSet[itemID] == true
end

-- True while the player has Fishing below 300 and the pairing setting is on.
function Pricing.FishingFree()
    if not CP.Settings.FishCook() then return false end
    local info = CP.Professions.SkillLine(FISHING)
    local rank = info and info.rank or 0
    return rank > 0 and rank < 300
end

-- `skills` (optional) is Sourcing.PlayerSkills()'s answer when the caller has it.
function Pricing.GetCollect(itemID, guideItem, skills)
    if guideItem and guideItem[2] then return VENDOR_EFFORT, "vendor" end
    local effort = guideItem and guideItem[4] or 1
    if effort > FISH_EFFORT and Pricing.IsFish(itemID) and Pricing.FishingFree() then
        return FISH_EFFORT, "fishing"
    end
    -- Enchanting materials: disenchanting greens the player crafts can beat world drops.
    if guideItem and guideItem[6] then
        skills = skills or CP.Sourcing.PlayerSkills()
        for line, e in pairs(guideItem[6]) do
            if skills[line] and e < effort then effort = e end
        end
    end
    return effort, "collect"
end

-- GetCollect for one solve: it reads the player's skills at most once.
function Pricing.CollectFn()
    local skills
    return function(itemID, guideItem)
        if not skills and guideItem and guideItem[6] then skills = CP.Sourcing.PlayerSkills() end
        return Pricing.GetCollect(itemID, guideItem, skills)
    end
end

local AH_CUT = 0.95

-- What one of `itemID` sells for: vendor price, and auction price after the 5% cut
-- (nil without auction data). For display only; never ranks recipes.
function Pricing.SaleValue(itemID)
    local vendor = select(11, C_Item.GetItemInfo(itemID))
    local ah = auctionPrice(itemID)
    return vendor and vendor > 0 and vendor or nil, ah and math.floor(ah * AH_CUT) or nil
end

-- "1g 20s", "45s", "8c".
function Pricing.Format(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return s > 0 and ("%dg %ds"):format(g, s) or ("%dg"):format(g) end
    if s > 0 then return ("%ds"):format(s) end
    return ("%dc"):format(c)
end
