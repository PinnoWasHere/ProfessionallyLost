local _, CP = ...
if CP.stopped then return end

-- ProfLost's own auction price scan. DaylightMogul's prices win where it has one.
--
-- A scan asks the game for every auction at once (C_AuctionHouse.ReplicateItems), then
-- reads the list a slice a frame within a time budget, so a big auction house never stalls
-- a frame. It keeps the lowest unit buyout of every item on the list. The game allows one
-- full list every `cooldown` seconds, counted from the ask. A client without
-- ReplicateItems doesn't scan: one search per item would crowd other addons' searches.
--
-- Prices live in CP.db.prices[key][itemID] = { price, time }, key from Scan.RealmKey().

local Scan = {}
CP.Scan = Scan

Scan.config = {
    cooldown = 900,       -- seconds between full scans, from the ask (Mogul's figure; the client documents none)
    answerWait = 90,      -- seconds a big auction house may take to send its list
    readyWait = 0.5,      -- seconds between looks while the game holds messages back
    slice = 500,          -- most rows read in one frame
    budgetMs = 4,         -- milliseconds of reading in one frame at most
    clockEvery = 50,      -- rows between looks at the clock
    frameGap = 0.001,     -- seconds between slices; above 0, so each slice runs on a later frame
    settle = 2,           -- seconds the list must hold still before the read is done
    emptyWait = 15,       -- seconds an empty list gets to fill
    waitingWait = 30,     -- seconds rows without their item get to fill once the list is read
    look = 0.25,          -- seconds between looks while the list settles

    -- Neutral auction houses (Booty Bay, Gadgetzan, Everlook) feed no prices. The client has
    -- no call that names an auction house's faction, so the zone's UI map id stands in; each
    -- of these zones holds one auction house, the neutral one. Ids are the "forever" client's.
    neutralMaps = { [1434] = true, [1446] = true, [1452] = true },   -- Stranglethorn Vale, Tanaris, Winterspring
    neutralLine = "Neutral auction house: prices not recorded",
    noFullLine = "This game client can't read the whole auction house, so it can't scan prices.",
}

Scan.open = false
Scan.neutral = false   -- the open auction house is neutral

local state            -- the scan running now, or nil
local token = 0        -- bumps on every step, so stale timers do nothing
local listeners = {}
local interest         -- the profession item set, built once
local traceFrom = 0    -- GetTime() when the scan began, for the trace

local SLACK = 0.01     -- seconds; clock arithmetic leaves crumbs like 1e-15

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function num(v)
    if v == nil or secret(v) then return nil end
    return tonumber(v)
end

-- "12,000".
function Scan.Thousands(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- Trace ---------------------------------------------------------------------------

-- Hidden: /proflost trace scan on|off prints the scan's phases, counts and timings. On for
-- this session only.
function Scan.Tracing()
    return CP.trace.scan == true
end

function Scan.Trace(fmt, ...)
    if not Scan.Tracing() then return end
    CP.TraceLine("scan", GetTime() - traceFrom, fmt, ...)
end
local trace = Scan.Trace

function Scan.SetTrace(on)
    CP.SetTracing("scan", on)
    CP:Print("Scan trace " .. (on and "on: open the auction house, click ProfLost Scan, and paste what follows." or "off."))
end

-- Where prices live -----------------------------------------------------------------

-- Prices are kept under "Server-<id>-<faction>", the server id taken from the player's GUID.
-- The Forever client answers realm names with "" and may answer the id with 0 too; then the
-- key is "Forever-<faction>". Saves from before keep "<Realm>-<faction>" keys.
local keyServer, keyFaction, realmKey, movedKey

local FIELDS = { "prices", "priceScans", "priceAsked" }

-- A usable string, or nil for anything else (absent, empty, secret).
local function text(v)
    if type(v) ~= "string" or secret(v) or v == "" then return nil end
    return v
end

-- Letters and digits only, lower case, so "Area 52" and "Area52" compare equal.
local function fold(s) return (s:gsub("[^%w]", ""):lower()) end

-- Every realm name the game answers with now.
local function realmNames()
    local names = {}
    if GetNormalizedRealmName then names[#names + 1] = text(GetNormalizedRealmName()) end
    if GetRealmName then names[#names + 1] = text(GetRealmName()) end
    if UnitFullName then names[#names + 1] = text(select(2, UnitFullName("player"))) end
    return names
end

local function serverKey(k) return k:find("^Server%-%d+%-") ~= nil end

-- A "<Realm>-<faction>" key from before server keys.
local function realmStyle(k, faction)
    return not serverKey(k) and k ~= "Forever-" .. faction
end

-- Saved keys of this faction that may hold this player's prices: realm-style keys, plus the
-- Forever key for a server key, or every server key for the Forever key.
local function candidates(key, faction)
    local tail, forever = "-" .. faction, "Forever-" .. faction
    local seen, list = {}, {}
    for _, field in ipairs(FIELDS) do
        local t = CP.db[field]
        if type(t) == "table" then
            for k in pairs(t) do
                if type(k) == "string" and k ~= key and not seen[k] and k:sub(-#tail) == tail
                    and (not serverKey(k) or key == forever) then
                    seen[k] = true
                    list[#list + 1] = k
                end
            end
        end
    end
    return list
end

local function move(from, to)
    for _, field in ipairs(FIELDS) do
        local t = CP.db[field]
        if type(t) == "table" and t[to] == nil and t[from] ~= nil then t[to], t[from] = t[from], nil end
    end
end

-- Moves this player's prices saved under another key to `key`, once. A realm-style key moves
-- when its realm name matches the game's. With no realm name to match, a lone candidate
-- moves; two or more stay put, since nothing says which is this realm. True once settled, so
-- a call that found two candidates and no name tries again later.
local function adoptOldKeys(key, faction)
    local db = CP.db
    if not db then return false end
    if type(db.prices) == "table" and db.prices[key] ~= nil then return true end
    local list = candidates(key, faction)
    if #list == 0 then return true end
    local names = realmNames()
    local tail = "-" .. faction
    for _, k in ipairs(list) do
        if realmStyle(k, faction) then
            local realm = fold(k:sub(1, -#tail - 1))
            for _, n in ipairs(names) do
                if fold(n) == realm then
                    move(k, key)
                    return true
                end
            end
        end
    end
    if #list == 1 and (#names == 0 or not realmStyle(list[1], faction)) then
        move(list[1], key)
        return true
    end
    return #names > 0
end

-- The key prices are kept under; nil until the GUID and faction answer.
function Scan.RealmKey()
    local guid = UnitGUID and text(UnitGUID("player"))
    local faction, localized
    if UnitFactionGroup then faction, localized = UnitFactionGroup("player") end
    faction = text(faction) or text(localized)
    if not (guid and faction) or not guid:find("^Player%-") then return nil end
    local server = guid:match("^Player%-(%d+)%-")
    if not server or tonumber(server) == 0 then server = false end
    if server ~= keyServer or faction ~= keyFaction then
        keyServer, keyFaction = server, faction
        realmKey = server and ("Server-" .. server .. "-" .. faction) or ("Forever-" .. faction)
        movedKey = nil
    end
    if movedKey ~= realmKey and CP.db and adoptOldKeys(realmKey, faction) then
        movedKey = realmKey
    end
    return realmKey
end

local function now() return GetServerTime and GetServerTime() or time() end

local function store(create)
    local key = CP.db and Scan.RealmKey()
    if not key then return nil end
    if create then
        CP.db.prices = CP.db.prices or {}
        CP.db.prices[key] = CP.db.prices[key] or {}
    end
    return CP.db.prices and CP.db.prices[key]
end

-- Our scanned price for an item and when it was seen (epoch seconds), or nil.
function Scan.Price(itemID)
    local t = store(false)
    local e = t and t[itemID]
    if type(e) ~= "table" or type(e[1]) ~= "number" or e[1] <= 0 then return nil end
    return e[1], e[2]
end

-- True when this realm and faction has any scanned price.
function Scan.HasData()
    local t = store(false)
    return t ~= nil and next(t) ~= nil
end

-- When this realm and faction last finished a scan, or nil.
function Scan.LastTime()
    local key = CP.db and CP.db.priceScans and Scan.RealmKey()
    return key and CP.db.priceScans[key] or nil
end

-- True when the client can send the whole auction list at once.
function Scan.FullAvailable()
    return C_AuctionHouse ~= nil and type(C_AuctionHouse.ReplicateItems) == "function"
end

-- Seconds until the game allows another full scan; 0 when it does. Counts from the later
-- of the last ask and the last finished scan. A clock that went back holds nothing up.
function Scan.CooldownLeft()
    if not (CP.db and Scan.FullAvailable()) then return 0 end
    local key = Scan.RealmKey()
    if not key then return 0 end
    local asked = CP.db.priceAsked and CP.db.priceAsked[key]
    local last = CP.db.priceScans and CP.db.priceScans[key]
    if type(asked) == "number" and (type(last) ~= "number" or asked > last) then last = asked end
    if type(last) ~= "number" then return 0 end
    local ago = now() - last
    if ago < 0 or ago >= Scan.config.cooldown then return 0 end
    return Scan.config.cooldown - ago
end

-- The profession item set --------------------------------------------------------------

-- Every item any guide uses or makes, alternatives included, as { [itemID] = true },
-- vendor stock left out. The tooltip and the done line count it. Built once: the guides
-- never change in a session.
function Scan.Interest()
    if interest then return interest end
    local all, vendor = {}, {}
    for _, g in pairs(CP.Guides or {}) do
        for id, item in pairs(g.items or {}) do
            all[id] = true
            if item[2] == true then vendor[id] = true end
        end
        for _, r in pairs(g.recipes or {}) do
            for _, re in ipairs(r.reagents or {}) do all[re[1]] = true end
            if r.makes then all[r.makes] = true end
        end
    end
    interest = {}
    for id in pairs(all) do
        if type(id) == "number" and not vendor[id] then interest[id] = true end
    end
    return interest
end

-- Forgets the built set, for tests that change the guides.
function Scan.ResetInterest() interest = nil end

-- How many items the set holds.
function Scan.InterestCount()
    local n = 0
    for _ in pairs(Scan.Interest()) do n = n + 1 end
    return n
end

-- Progress ------------------------------------------------------------------------

function Scan.Running() return state ~= nil end

-- Rows read and the list's size (0, 0 until it arrives).
function Scan.Progress()
    if not state then return nil end
    return state.read, state.total
end

-- What the scan is doing, for the button and the Shop tab.
function Scan.ProgressText()
    if not state then return nil end
    if state.phase == "asking" then return "Asking the auction house" end
    return ("Reading %s / %s"):format(Scan.Thousands(state.read), Scan.Thousands(state.total))
end

-- `fn()` runs whenever the scan starts, steps, stops, or the auction house opens or closes.
function Scan.OnChange(fn) listeners[#listeners + 1] = fn end

local function notify()
    for _, fn in ipairs(listeners) do fn() end
end

local function pricesChanged()
    if CP.Plan and CP.Plan.Invalidate then CP.Plan.Invalidate() end
    if CP.Panel and CP.Panel.frame and CP.Panel.frame:IsShown() then CP.Panel:Refresh() end
end

local STOPPED = {
    closed = "the auction house closed. Nothing was kept.",
    timeout = "the auction house didn't answer. The game allows one full scan every %d min.",
    empty = "the auction house sent no auctions. The game allows one full scan every %d min.",
    error = "something went wrong. Try again in a moment.",
    stopped = "stopped. Nothing was kept.",
}

-- The chat line a finished scan prints.
local function doneLine(s)
    if not s.complete then
        return "Price scan stopped: " .. STOPPED[s.reason or "error"]:format(math.floor(Scan.config.cooldown / 60))
    end
    local profession = 0
    local set = Scan.Interest()
    for id in pairs(s.best) do
        if set[id] then profession = profession + 1 end
    end
    return ("Price scan done: %s items priced (%s profession items), %s auctions read in %d s."):format(
        Scan.Thousands(s.stored), Scan.Thousands(profession), Scan.Thousands(s.read),
        math.floor(GetTime() - s.began + 0.5))
end

local function finish(reason)
    local s = state
    state = nil
    token = token + 1
    if not s then return end
    s.reason = s.reason or reason
    if s.complete then
        CP.db.priceScans = CP.db.priceScans or {}
        CP.db.priceScans[s.realm] = now()
    end
    if s.stored > 0 then pricesChanged() end
    trace("finish: %s, %d priced, %.2f s", s.complete and "done" or (s.reason or "stopped"), s.stored, GetTime() - s.began)
    CP:Print(doneLine(s))
    notify()
end

local function later(delay, fn)
    local t = token
    C_Timer.After(delay, function()
        if t == token and state then fn() end
    end)
end

-- Reading the list --------------------------------------------------------------------

local function listSize()
    return num(C_AuctionHouse.GetNumReplicateItems()) or 0
end

-- One row (0-based) of the list into the lowest unit buyouts. A row without its item yet,
-- or whose item the client hasn't loaded, waits to be read again; a loaded item's price is
-- kept at once.
local function readRow(s, index)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAllInfo =
        C_AuctionHouse.GetReplicateItemInfo(index)
    itemID = num(itemID)
    if not itemID then
        s.waiting[#s.waiting + 1] = index
        return
    end
    if hasAllInfo == false then
        s.waiting[#s.waiting + 1] = index
        if not s.loading[itemID] then
            s.loading[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    count, buyout = num(count), num(buyout)
    if not (count and count > 0 and buyout and buyout > 0) then return end   -- bid only
    local unit = math.floor(buyout / count)
    if unit < 1 then return end
    if not s.best[itemID] then
        s.stored = s.stored + 1
        s.best[itemID] = unit
    elseif unit < s.best[itemID] then
        s.best[itemID] = unit
    end
end

local settle, safeSlice

-- One frame's reading: up to `slice` rows, stopping early once `budgetMs` has gone.
local function slice()
    local s = state
    if not Scan.open then return finish("closed") end
    local cfg = Scan.config
    local size = listSize()
    if size > s.total then s.total = size end
    local start = debugprofilestop()
    local n = 0
    while s.read < s.total and n < cfg.slice do
        readRow(s, s.read)
        s.read = s.read + 1
        n = n + 1
        if n % cfg.clockEvery == 0 and debugprofilestop() - start >= cfg.budgetMs then break end
    end
    local ms = debugprofilestop() - start
    s.frames = s.frames + 1
    if n > s.mostRows then s.mostRows = n end
    if ms > s.mostMs then s.mostMs = ms end
    notify()
    if s.read < s.total then return later(cfg.frameGap, safeSlice) end
    trace("read %d rows in %d frames, at most %d rows and %.1f ms a frame, %d waiting",
        s.read, s.frames, s.mostRows, s.mostMs, #s.waiting)
    settle()
end

local function guarded(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then
            trace("error: %s", tostring(err))
            finish("error")
        end
    end
end
safeSlice = guarded(slice)

-- Every row is read: the list's prices replace this realm's, and the scan is dated. An item
-- the whole list did not show has no listing now.
local function complete()
    local s = state
    local t = store(true)
    local at = now()
    for id in pairs(t) do
        if not s.best[id] then t[id] = nil end
    end
    for id, price in pairs(s.best) do t[id] = { price, at } end
    s.complete = true
    trace("stored %d prices", s.stored)
    finish()
end

-- Reads waiting rows again, a slice a look within the time budget, the ones still waiting
-- going to the back. True when one filled.
local function rereadWaiting(s)
    local cfg = Scan.config
    local queue, before = s.waiting, #s.waiting
    s.waiting = {}
    local start = debugprofilestop()
    local n = 0
    while n < before and n < cfg.slice do
        n = n + 1
        readRow(s, queue[n])
        if n % cfg.clockEvery == 0 and debugprofilestop() - start >= cfg.budgetMs then break end
    end
    local again = s.waiting
    s.waiting = {}
    for i = n + 1, before do s.waiting[#s.waiting + 1] = queue[i] end
    for _, index in ipairs(again) do s.waiting[#s.waiting + 1] = index end
    s.swept = s.swept + n
    return #s.waiting < before
end

-- The game's "list ready" can come before the list is, so the read counts as done once
-- the list stopped growing, every waiting row was read again with none filling, and
-- `settle` seconds went by so (`emptyWait` while the list is empty). Rows still waiting
-- after `waitingWait` stay unpriced.
settle = function()
    local s = state
    local cfg = Scan.config
    local t = GetTime()
    s.phase = "settling"
    s.settleFrom = s.settleFrom or t
    local size = listSize()
    if size > s.total then
        s.total, s.still = size, nil
        return later(cfg.frameGap, safeSlice)
    end
    if #s.waiting > 0 and rereadWaiting(s) then s.still, s.swept = nil, 0 end
    s.still = s.still or t
    local quiet = s.total > 0 and cfg.settle or cfg.emptyWait
    local swept = s.swept >= #s.waiting
    if (swept and t - s.still >= quiet - SLACK) or t - s.settleFrom >= cfg.waitingWait - SLACK then
        if s.total == 0 then return finish("empty") end
        return complete()
    end
    later(cfg.look, guarded(settle))
end

-- The list arrived: read it.
local function arrived()
    local s = state
    token = token + 1   -- drops the answer timeout
    s.phase = "reading"
    s.total = listSize()
    trace("list arrived: %d rows after %.2f s", s.total, GetTime() - s.asked)
    notify()
    later(Scan.config.frameGap, safeSlice)
end

local function ask()
    local s = state
    local ready = not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
    if not ready then
        if GetTime() - s.began >= Scan.config.answerWait then return finish("timeout") end
        return later(Scan.config.readyWait, ask)
    end
    if not pcall(C_AuctionHouse.ReplicateItems) then return finish("error") end
    -- The game's cooldown starts with the ask, whatever happens next.
    CP.db.priceAsked = CP.db.priceAsked or {}
    CP.db.priceAsked[s.realm] = now()
    s.asked = GetTime()
    trace("asked for the full list")
    later(Scan.config.answerWait, function() finish("timeout") end)
end

-- Starting and stopping ---------------------------------------------------------------

-- Starts a full scan. False and a sentence when it can't: the auction house is shut or
-- neutral, a scan runs, the client has no full list, or the cooldown holds.
function Scan.Start()
    if not Scan.open then return false, "Open the auction house first." end
    if state then return false, "A price scan is already running." end
    if not CP.db then return false, "Not loaded yet." end
    if Scan.neutral then return false, Scan.config.neutralLine end
    local realm = Scan.RealmKey()
    if not realm then return false, "Your realm isn't known yet; try again in a moment." end
    if not Scan.FullAvailable() then
        trace("no full list in this client")
        return false, Scan.config.noFullLine
    end
    local left = Scan.CooldownLeft()
    if left > 0 then
        return false, ("A full scan is allowed again in %d min."):format(math.max(1, math.ceil(left / 60)))
    end
    state = { phase = "asking", realm = realm, began = GetTime(), asked = GetTime(), best = {}, waiting = {},
              loading = {}, swept = 0, read = 0, total = 0, stored = 0, frames = 0, mostRows = 0, mostMs = 0 }
    traceFrom = state.began
    token = token + 1
    trace("start: full scan")
    notify()
    ask()
    return true
end

-- Stops the scan and keeps nothing, since half a list can't say which price is lowest.
function Scan.Stop()
    if state then finish("stopped") end
end

CP:On("REPLICATE_ITEM_LIST_UPDATE", function()
    if state and state.phase == "asking" then arrived() end
end)

CP:On("AUCTION_HOUSE_SHOW", function()
    Scan.open = true
    -- The zone's UI map id says which auction house this is (see config.neutralMaps).
    local map = C_Map and C_Map.GetBestMapForUnit and num(C_Map.GetBestMapForUnit("player"))
    Scan.neutral = map ~= nil and Scan.config.neutralMaps[map] == true
    notify()
end)

CP:On("AUCTION_HOUSE_CLOSED", function()
    Scan.open = false
    Scan.neutral = false
    if state then finish("closed") else notify() end
end)
