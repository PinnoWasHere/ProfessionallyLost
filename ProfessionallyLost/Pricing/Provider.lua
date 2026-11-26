local _, CP = ...
if CP.stopped then return end

-- Material prices in copper. Order: a vendor that always stocks the item, then the
-- auction price, then the item's vendor list price as a rough estimate.
--
-- The auction price comes from the first source in `config.order` that prices the item:
-- DaylightMogul, Daylight UI's Auction House (DaylightUI.AuctionPrices), Auctionator
-- (its public v1 API), then ProfLost's own scan (Scan.lua). Each addon is looked up at
-- call time, so one that publishes late or switches off is followed.

local Pricing = {}
CP.Pricing = Pricing

Pricing.config = {
    order = { "mogul", "daylight", "auctionator", "scan" },
    names = {
        mogul = "DaylightMogul",
        daylight = "Daylight UI's Auction House",
        auctionator = "Auctionator",
        scan = "ProfLost's scan",
    },
    mogulSource = "market",
    caller = "ProfessionallyLost",   -- Auctionator's callerID
    day = 86400,                     -- Auctionator ages its prices in whole days

    -- Staple materials: any one priced means a source with no count of its own has data.
    staples = { 2589, 2592, 4306, 2770, 2771, 2318, 2319, 2447, 765, 2835 },
}
local config = Pricing.config

local function now() return GetServerTime and GetServerTime() or time() end

-- A pcall's answer as a price: a positive number and what came after it, else nil.
local function positive(ok, price, ...)
    if ok and type(price) == "number" and price > 0 then return price, ... end
    return nil
end

-- DaylightMogul's API while it is loaded.
local function mogul()
    local m = rawget(_G, "DaylightMogul")
    return type(m) == "table" and type(m.API) == "table" and type(m.API.Price) == "function" and m.API or nil
end

-- DaylightUI.AuctionPrices. Absent while its Auction House module is off or DaylightMogul
-- owns the Auction House.
local function daylight()
    local d = rawget(_G, "DaylightUI")
    local p = type(d) == "table" and d.AuctionPrices
    return type(p) == "table" and type(p.Item) == "function" and p or nil
end

-- Auctionator's public v1 API while it is loaded.
local function auctionator()
    local a = rawget(_G, "Auctionator")
    local v1 = type(a) == "table" and type(a.API) == "table" and a.API.v1
    return type(v1) == "table" and type(v1.GetAuctionPriceByItemID) == "function" and v1 or nil
end

-- Each source has present(), price(id) -> copper and its age in seconds (nil when the
-- source gives none), and optionally data() -> true once it holds any price.
local sources = {}

sources.mogul = {
    present = function() return mogul() ~= nil end,
    price = function(id)
        local api = mogul()
        if not api then return nil end
        return (positive(pcall(api.Price, id, config.mogulSource)))
    end,
}

sources.daylight = {
    present = function() return daylight() ~= nil end,
    price = function(id)
        local p = daylight()
        if not p then return nil end
        local price, seen = positive(pcall(p.Item, id))
        if not price then return nil end
        return price, type(seen) == "number" and math.max(0, now() - seen) or nil
    end,
    data = function()
        local p = daylight()
        return p ~= nil and type(p.ScannedAt) == "function" and positive(pcall(p.ScannedAt)) ~= nil
    end,
}

sources.auctionator = {
    present = function() return auctionator() ~= nil end,
    price = function(id)
        local v1 = auctionator()
        if not v1 then return nil end
        local price = positive(pcall(v1.GetAuctionPriceByItemID, config.caller, id))
        if not price then return nil end
        local age
        if type(v1.GetAuctionAgeByItemID) == "function" then
            local ok, days = pcall(v1.GetAuctionAgeByItemID, config.caller, id)
            if ok and type(days) == "number" then age = math.max(0, days) * config.day end
        end
        return price, age
    end,
}

sources.scan = {
    present = function() return CP.Scan ~= nil end,
    price = function(id)
        local price, seen = CP.Scan.Price(id)
        if not price then return nil end
        return price, seen and math.max(0, now() - seen) or nil
    end,
    data = function() return CP.Scan.HasData() end,
}

local function holdsData(src)
    if not src.present() then return false end
    if src.data then return src.data() == true end
    for _, id in ipairs(config.staples) do
        if src.price(id) then return true end
    end
    return false
end

-- The auction price, its source key and its age in seconds, from the first source that
-- prices the item.
local function auctionPrice(itemID)
    for _, key in ipairs(config.order) do
        local src = sources[key]
        if src.present() then
            local price, age = src.price(itemID)
            if price then return price, key, age end
        end
    end
    return nil
end

-- The first other addon that holds prices: its key and name, or nil.
function Pricing.AddonSource()
    for _, key in ipairs(config.order) do
        if key ~= "scan" and holdsData(sources[key]) then return key, config.names[key] end
    end
    return nil
end

-- True once any source holds a price for this realm and faction.
function Pricing.HasAuctionData()
    for _, key in ipairs(config.order) do
        if holdsData(sources[key]) then return true end
    end
    return false
end

-- The auction price for an item, or nil.
function Pricing.Auction(itemID)
    return (auctionPrice(itemID))
end

-- The auction price, the key of its source and its age in seconds, or nil.
function Pricing.AuctionFrom(itemID)
    return auctionPrice(itemID)
end

-- Seconds since the winning source saw the item's price. Nil when that source gives no
-- age (DaylightMogul) or there is no price.
function Pricing.AuctionAge(itemID)
    return (select(3, auctionPrice(itemID)))
end

-- When Daylight UI's Auction House last saw anything, or nil.
function Pricing.DaylightScannedAt()
    local p = daylight()
    if not (p and type(p.ScannedAt) == "function") then return nil end
    return (positive(pcall(p.ScannedAt)))
end

-- "5 min", "3 h", "2 d".
function Pricing.FormatAge(seconds)
    if seconds < 3600 then return ("%d min"):format(math.max(1, math.floor(seconds / 60))) end
    if seconds < 86400 then return ("%d h"):format(math.floor(seconds / 3600)) end
    return ("%d d"):format(math.floor(seconds / 86400))
end

local listeners = {}

-- `fn()` runs whenever another addon's prices move.
function Pricing.OnChange(fn) listeners[#listeners + 1] = fn end

-- New market data: plans re-rank on the next refresh.
function Pricing.Changed()
    if CP.Plan and CP.Plan.Invalidate then CP.Plan.Invalidate() end
    if CP.Panel and CP.Panel.frame and CP.Panel.frame:IsShown() then CP.Panel:Refresh() end
    for _, fn in ipairs(listeners) do fn() end
end

local auctionatorHeard = false   -- Auctionator calls back when its prices move

-- Listens to every price source that says when its prices move. Runs at login.
function Pricing.Listen()
    local api = mogul()
    if api and type(api.On) == "function" then
        pcall(api.On, "PricesChanged", Pricing.Changed)
    end
    local dui = rawget(_G, "DaylightUI")
    if type(dui) == "table" and type(dui.On) == "function" then
        pcall(dui.On, "AuctionPricesChanged", Pricing.Changed)
    end
    local v1 = auctionator()
    auctionatorHeard = false
    if v1 and type(v1.RegisterForDBUpdate) == "function" then
        auctionatorHeard = pcall(v1.RegisterForDBUpdate, config.caller, Pricing.Changed)
    end
end

CP:On("PLAYER_LOGIN", function() Pricing.Listen() end)

-- An Auctionator without its update callback: its prices count as new once the auction
-- house closes.
CP:On("AUCTION_HOUSE_CLOSED", function()
    if not auctionatorHeard and auctionator() then Pricing.Changed() end
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
