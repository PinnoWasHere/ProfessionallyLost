-- mogulworld: DaylightMogul's public API (DaylightMogul.API 1.6), as the header
-- comments of its Bridge/API.lua describe it. Interface only; none of its code.
--
-- Modelled from those notes:
--   * [docs] API.Price(itemID, source) -> copper or nil; source defaults to "market"; an
--     unknown item, source or a bad argument gives nil, never an error.
--   * [docs] API.On(name, fn) -> true for "LedgerChanged", "PricesChanged" (fn(rulesetKey))
--     and "QueueChanged"; nil for anything else.
--   * [docs] API.Craft.Owns() -> true and Craft.Info(recipeID) -> { cost, value, profit, why }
--     or nil; Ledger, Mail and Vendor each Owns() -> true.
--   * [docs] With its profession window on, Mogul's DaylightMogulCraft shows in place of the
--     game's when craftworld opens a profession; the game's frame stays shown, out of sight.
-- Guesses:
--   * [guess] Prices are what the test sets; no ruleset beyond "Testrealm".
--   * [guess] Craft.Info answers only what the test sets.
--   * [guess] Mogul 0.1.1 has no call that selects a recipe in its window; `select = true` adds
--     a stand-in Craft.Select for the call ProfLost would use if Mogul gains one.
--
--   MogulWorld.begin({ prices = { [2318] = 50 }, craftWindow = false })
--   MogulWorld.SetPrice(item, copper, source) / PricesChanged()

MogulWorld = {}

local S

local EVENTS = { LedgerChanged = true, PricesChanged = true, QueueChanged = true }

local function owns() return true end

function MogulWorld.begin(spec)
    spec = spec or {}
    S = { prices = { market = {} }, info = spec.info or {}, handlers = {}, craftWindow = spec.craftWindow == true }
    MogulWorld.state = S
    for id, copper in pairs(spec.prices or {}) do S.prices.market[id] = copper end

    local API = { version = { 1, 6 } }
    function API.Price(itemID, source)
        if source == nil then source = "market" end
        if type(source) ~= "string" then return nil end
        local id = tonumber(type(itemID) == "string" and itemID:match("item:(%d+)") or itemID)
        local t = S.prices[source:lower()]
        return id and t and t[id] or nil
    end
    function API.On(name, fn)
        if type(name) ~= "string" or not EVENTS[name] or type(fn) ~= "function" then return nil end
        S.handlers[#S.handlers + 1] = { name = name, fn = fn }
        return true
    end
    API.Craft = { Owns = owns, Info = function(id)
        local i = type(id) == "number" and S.info[id]
        return i and { cost = i.cost, value = i.value, profit = i.profit, why = i.why } or nil
    end }
    -- `select`: a stand-in for a select call Mogul doesn't have yet (Host.MOGUL_SELECT).
    if spec.select then
        API.Craft.Select = function(id)
            if not (S.window and S.window:IsShown()) then return false end
            S.selected = id
            return true
        end
    end
    API.Ledger, API.Mail, API.Vendor = { Owns = owns }, { Owns = owns }, { Owns = owns }

    -- [docs] DaylightMogul.API 1.6 as the header of its Bridge/API.lua describes it.
    World.set(_G, "DaylightMogul", { API = API })

    if S.craftWindow then
        -- A named frame sets its global: put the old one back, so the frame leaves with the world.
        local before = rawget(_G, "DaylightMogulCraft")
        S.window = CreateFrame("Frame", "DaylightMogulCraft", UIParent)
        rawset(_G, "DaylightMogulCraft", before)
        S.window:SetSize(800, 560)
        S.window:SetPoint("CENTER")
        S.window:Hide()
        function S.window.GetAlpha() return 1 end
        function S.window.GetEffectiveAlpha() return 1 end

        -- [docs] Mogul's craft window stands in for the game's when craftworld opens a profession.
        World.set(_G, "DaylightMogulCraft", S.window)
        local window = S.window
        World.onEnd(function() window:Hide() end)
        World.listen(function(what)
            if what == "craft:show" then
                window:Show()
                return true
            elseif what == "craft:close" then
                window:Hide()
            end
        end)
    end
end

function MogulWorld.SetPrice(itemID, copper, source)
    source = source or "market"
    S.prices[source] = S.prices[source] or {}
    S.prices[source][itemID] = copper
end

-- New market data: every PricesChanged handler hears it.
function MogulWorld.PricesChanged()
    for _, h in ipairs(S.handlers) do
        if h.name == "PricesChanged" then h.fn("Testrealm") end
    end
end

-- ProfLost listens from PLAYER_LOGIN; a test that wants its handler plays a login.
function MogulWorld.Handlers(name)
    local out = {}
    for _, h in ipairs(S.handlers) do if h.name == name then out[#out + 1] = h.fn end end
    return out
end
