-- duiahworld: MOCK of Daylight UI's Auction House prices (DaylightUI.AuctionPrices, API 1.15),
-- as Daylight UI's API.md describes them. Interface only; none of its code.
--
-- Modelled from those notes:
--   * [docs] DaylightUI.AuctionPrices is a table. Item(id) -> price, seenAt; ScannedAt() -> when
--     anything was last seen, nil before a scan; CUT = 0.05. Each call gives nil for an item never
--     seen, never an error.
--   * [docs] DaylightUI.On("AuctionPricesChanged", fn) says when a number moved.
--   * [docs] The table is absent while the Auction House module is off or DaylightMogul owns the
--     Auction House (`mogul = true`).
-- Guesses:
--   * [guess] Prices and times are what the test sets; no ruleset or freshness rule is modelled.
--   * [guess] With daylightworld running, the table and On go onto its DaylightUI; else a bare
--     DaylightUI holds only these.
--
--   DUIAHWorld.begin({ prices = { [2318] = { 45, 1800000000 } }, scannedAt = 1800000000, mogul = false })
--   DUIAHWorld.SetPrice(item, copper, seenAt) / SetScannedAt(t) / Changed() / Publish()

DUIAHWorld = {}

local S

function DUIAHWorld.begin(spec)
    spec = spec or {}
    S = { prices = {}, scannedAt = spec.scannedAt, handlers = {} }
    DUIAHWorld.state = S
    for id, p in pairs(spec.prices or {}) do S.prices[id] = { p[1], p[2] } end

    local P = { CUT = 0.05 }
    function P.Item(id)
        local e = type(id) == "number" and S.prices[id]
        if not e then return nil end
        return e[1], e[2]
    end
    function P.ScannedAt() return S.scannedAt end
    S.table = P

    local dui = rawget(_G, "DaylightUI")
    if type(dui) ~= "table" then
        dui = {}
        -- [guess] No daylightworld: a bare DaylightUI holds only the prices and On.
        World.set(_G, "DaylightUI", dui)
    end
    S.dui = dui
    World.set(dui, "On", function(name, fn)
        S.handlers[#S.handlers + 1] = { name = name, fn = fn }
    end)
    World.set(dui, "AuctionPrices", nil)
    if not spec.mogul then DUIAHWorld.Publish(true) end
end

-- [docs] The Auction House module publishes its table at login and fires the event.
function DUIAHWorld.Publish(quiet)
    S.dui.AuctionPrices = S.table
    if not quiet then DUIAHWorld.Changed() end
end

function DUIAHWorld.SetPrice(itemID, copper, seenAt)
    S.prices[itemID] = copper and { copper, seenAt } or nil
end

function DUIAHWorld.SetScannedAt(t) S.scannedAt = t end

-- A number moved: every AuctionPricesChanged handler hears it.
function DUIAHWorld.Changed()
    for _, h in ipairs(S.handlers) do
        if h.name == "AuctionPricesChanged" then h.fn() end
    end
end

-- The handlers registered for `name`.
function DUIAHWorld.Handlers(name)
    local out = {}
    for _, h in ipairs(S.handlers) do if h.name == name then out[#out + 1] = h.fn end end
    return out
end
