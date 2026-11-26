local _, CP = ...
if CP.stopped then return end

-- Material prices in copper. Order: a vendor that always stocks the item, then the
-- auction price, then the item's vendor list price as a rough estimate.
--
-- The game lets one addon scan the auction house at a time, so the player picks one price
-- addon (config.choices, saved per account in CP.db.priceSource). Its sources are read
-- first and the rest fill gaps in `config.order`: DaylightMogul, Daylight UI's Auction House
-- (DaylightUI.AuctionPrices), Auctionator (its public v1 API), TSM (TSM_API), Auctioneer
-- (AucAdvanced.API), ProfLost's own scan (Scan.lua), then Glowey's Recipes (its public
-- DaylightRecipes.API). With no pick saved, or a pick whose addon isn't loaded, the order
-- alone decides. Each addon is looked up at call time, so one that publishes late or
-- switches off is followed.

local Pricing = {}
CP.Pricing = Pricing

Pricing.config = {
    order = { "mogul", "daylight", "auctionator", "tsm", "auctioneer", "scan", "glowey" },
    names = {
        mogul = "DaylightMogul",
        daylight = "Daylight UI's Auction House",
        auctionator = "Auctionator",
        tsm = "TSM",
        auctioneer = "Auctioneer",
        scan = "ProfLost's scan",
        glowey = "Glowey's Recipes",
    },
    mogulSource = "market",
    caller = "ProfessionallyLost",   -- Auctionator's callerID
    day = 86400,                     -- Auctionator ages its prices in whole days

    -- TSM_API price strings, tried in turn: its market value, then its lowest buyout.
    tsmSources = { "DBMarket", "DBMinBuyout" },
    tsmItem = "i:%d",                -- TSM's item string for a plain item
    auctioneerItem = "item:%d",      -- Auctioneer reads a link; a bare id needs the item cached

    -- What the player picks from, in the options' order. `reads`: the sources read first.
    -- `folders`: the addon folders that count it as installed.
    choices = {
        { key = "tsm", label = "TSM", name = "TSM", reads = { "tsm" }, folders = { "TradeSkillMaster" } },
        { key = "auctioneer", label = "Auctioneer", name = "Auctioneer", reads = { "auctioneer" },
          folders = { "Auc-Advanced" } },
        { key = "auctionator", label = "Auctionator", name = "Auctionator", reads = { "auctionator" },
          folders = { "Auctionator" } },
        { key = "daylight", label = "Daylight UI", name = "Daylight UI", reads = { "mogul", "daylight" },
          folders = { "DaylightMogul", "DaylightUI_AuctionHouse" } },
        { key = "glowey", label = "Glowey's Recipes", name = "Glowey's Recipes", reads = { "glowey" },
          folders = { "DaylightRecipes" } },
        { key = "scan", label = "ProfLost's own scan", name = "ProfLost", reads = { "scan" } },
    },

    -- Staple materials: any one priced means a source with no count of its own has data.
    staples = { 2589, 2592, 4306, 2770, 2771, 2318, 2319, 2447, 765, 2835 },
}
local config = Pricing.config

local choiceBy = {}
for _, c in ipairs(config.choices) do choiceBy[c.key] = c end

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

-- Glowey's Recipes' public API (DaylightRecipes.API, major 1) while it is loaded.
local function glowey()
    local g = rawget(_G, "DaylightRecipes")
    local api = type(g) == "table" and g.API
    return type(api) == "table" and type(api.Price) == "function" and api or nil
end

-- TSM's public API while it is loaded.
local function tsm()
    local t = rawget(_G, "TSM_API")
    return type(t) == "table" and type(t.GetCustomPriceValue) == "function" and t or nil
end

-- Auctioneer's public API while it is loaded.
local function auctioneer()
    local a = rawget(_G, "AucAdvanced")
    local api = type(a) == "table" and a.API
    return type(api) == "table" and type(api.GetMarketValue) == "function" and api or nil
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

-- TSM keeps no age per item.
sources.tsm = {
    present = function() return tsm() ~= nil end,
    price = function(id)
        local api = tsm()
        if not api then return nil end
        local item = config.tsmItem:format(id)
        for _, src in ipairs(config.tsmSources) do
            local price = positive(pcall(api.GetCustomPriceValue, src, item))
            if price then return price end
        end
        return nil
    end,
}

-- Auctioneer's market value. Its second answer counts sightings, not time, so no age.
sources.auctioneer = {
    present = function() return auctioneer() ~= nil end,
    price = function(id)
        local api = auctioneer()
        if not api then return nil end
        return (positive(pcall(api.GetMarketValue, config.auctioneerItem:format(id))))
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

sources.glowey = {
    present = function() return glowey() ~= nil end,
    price = function(id)
        local api = glowey()
        if not api then return nil end
        local price = positive(pcall(api.Price, id))
        if not price then return nil end
        local age
        if type(api.PriceAge) == "function" then
            local ok, seconds = pcall(api.PriceAge, id)
            if ok and type(seconds) == "number" then age = math.max(0, seconds) end
        end
        return price, age
    end,
    data = function()
        local api = glowey()
        return api ~= nil and type(api.HasPrices) == "function" and select(2, pcall(api.HasPrices)) == true
    end,
}

local function holdsData(src)
    if not src.present() then return false end
    if src.data then return src.data() == true end
    for _, id in ipairs(config.staples) do
        if src.price(id) then return true end
    end
    return false
end

-- The player's pick ------------------------------------------------------------------

local readsFirst = {}   -- choice key -> { [source key] = true }
for _, c in ipairs(config.choices) do
    readsFirst[c.key] = {}
    for _, key in ipairs(c.reads) do readsFirst[c.key][key] = true end
end

local function pcallOk(ok, ...) if ok then return ... end end

-- True when the game lists the addon folder as loaded, or present and switched on for this
-- character, so it answers before that addon loads.
local function folderOn(folder)
    local A = rawget(_G, "C_AddOns")
    if type(A) ~= "table" then return false end
    if type(A.IsAddOnLoaded) == "function" and pcallOk(pcall(A.IsAddOnLoaded, folder)) then return true end
    if type(A.DoesAddOnExist) ~= "function" or type(A.GetAddOnEnableState) ~= "function" then return false end
    if not pcallOk(pcall(A.DoesAddOnExist, folder)) then return false end
    local guid = type(UnitGUID) == "function" and pcallOk(pcall(UnitGUID, "player")) or nil
    local state = type(guid) == "string" and pcallOk(pcall(A.GetAddOnEnableState, folder, guid)) or nil
    if type(state) ~= "number" then state = pcallOk(pcall(A.GetAddOnEnableState, folder)) end
    return type(state) == "number" and state > 0
end

function Pricing.Choices() return config.choices end
function Pricing.ChoiceInfo(key) return choiceBy[key] end

-- The saved pick, or nil.
function Pricing.Choice()
    local key = CP.db and CP.db.priceSource
    return choiceBy[key] and key or nil
end

-- True while choice `key`'s addon is loaded and readable now.
function Pricing.Present(key)
    local c = choiceBy[key]
    if not c then return false end
    for _, s in ipairs(c.reads) do
        if sources[s].present() then return true end
    end
    return false
end

-- True when choice `key`'s addon is loaded or the game lists it as switched on.
function Pricing.Installed(key)
    local c = choiceBy[key]
    if not c then return false end
    if Pricing.Present(key) then return true end
    for _, folder in ipairs(c.folders or {}) do
        if folderOn(folder) then return true end
    end
    return false
end

-- The best choice loaded now, by `config.order`. ProfLost's scan stands ahead of every
-- source after it.
function Pricing.Best()
    for _, key in ipairs(config.order) do
        if sources[key].present() then
            for _, c in ipairs(config.choices) do
                if readsFirst[c.key][key] then return c.key end
            end
        end
    end
    return "scan"
end

-- The choice whose switch shows on: the saved pick, else the best loaded now.
function Pricing.Selected()
    return Pricing.Choice() or Pricing.Best()
end

-- The pick read first: the saved one while its addon is loaded, else nil (the order alone).
function Pricing.Active()
    local key = Pricing.Choice()
    if key and Pricing.Present(key) then return key end
    return nil
end

-- The saved pick's name while its addon isn't loaded, so prices come from the order alone.
function Pricing.FellBack()
    local key = Pricing.Choice()
    if key and not Pricing.Present(key) then return choiceBy[key].name end
    return nil
end

-- True while ProfLost's own scan is the one to run: picked, or nothing picked and nothing
-- ahead of it holds prices.
function Pricing.ScanChosen()
    local key = Pricing.Active()
    if key then return key == "scan" end
    return Pricing.AddonSource() == nil
end

-- Saves choice `key`. Prices re-rank, and the options page redraws so the old switch shows off.
function Pricing.Choose(key)
    if not (choiceBy[key] and CP.db) then return false end
    if CP.db.priceSource == key then return true end
    CP.db.priceSource = key
    Pricing.Changed()
    if CP.Plugin and CP.Plugin.RefreshOptions then CP.Plugin.RefreshOptions() end
    return true
end

-- The note under the switches.
function Pricing.ChoiceNote()
    local gone = Pricing.FellBack()
    if gone then
        local _, name = Pricing.AddonSource()
        return ("%s isn't loaded, so prices come from %s first."):format(gone, name or config.names.scan)
    end
    local c = choiceBy[Pricing.Selected()]
    if c.key == "scan" then return "ProfLost scans at the auction house. Other addons' prices fill gaps." end
    return ("Prices come from %s first. Other addons' prices fill gaps."):format(c.name)
end

-- Prices ---------------------------------------------------------------------------

local function from(key, itemID)
    local src = sources[key]
    if not src.present() then return nil end
    return src.price(itemID)
end

-- The auction price, its source key and its age in seconds: the pick's sources first, then
-- the first other source in the order that prices the item.
local function auctionPrice(itemID)
    local active = Pricing.Active()
    local first = active and readsFirst[active]
    if first then
        for _, key in ipairs(choiceBy[active].reads) do
            local price, age = from(key, itemID)
            if price then return price, key, age end
        end
    end
    for _, key in ipairs(config.order) do
        if not (first and first[key]) then
            local price, age = from(key, itemID)
            if price then return price, key, age end
        end
    end
    return nil
end

-- The addon whose prices come first: its source key and name, or nil for ProfLost's scan.
-- With a pick loaded, the pick. Else the first addon ahead of ProfLost's scan in the order
-- that holds prices; addons after the scan only fill what it lacks.
function Pricing.AddonSource()
    local active = Pricing.Active()
    if active == "scan" then return nil end
    if active then
        for _, key in ipairs(choiceBy[active].reads) do
            if sources[key].present() then return key, config.names[key] end
        end
    end
    for _, key in ipairs(config.order) do
        if key == "scan" then return nil end
        if holdsData(sources[key]) then return key, config.names[key] end
    end
    return nil
end

-- True when source `key` holds any price now.
function Pricing.HoldsData(key)
    return sources[key] ~= nil and holdsData(sources[key])
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
-- age (DaylightMogul, TSM, Auctioneer) or there is no price.
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
    local g = glowey()
    local gOn = g and rawget(_G, "DaylightRecipes").API.OnPrices
    if type(gOn) == "function" then pcall(gOn, Pricing.Changed) end
    local v1 = auctionator()
    auctionatorHeard = false
    if v1 and type(v1.RegisterForDBUpdate) == "function" then
        auctionatorHeard = pcall(v1.RegisterForDBUpdate, config.caller, Pricing.Changed)
    end
end

CP:On("PLAYER_LOGIN", function() Pricing.Listen() end)

-- Auctioneer, and an Auctionator without its update callback, say nothing when their
-- prices move: those count as new once the auction house closes.
CP:On("AUCTION_HOUSE_CLOSED", function()
    if (not auctionatorHeard and auctionator()) or auctioneer() then Pricing.Changed() end
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
