-- A dropped profession, a restocked vendor, an unloaded merchant slot and a pattern learned
-- with the profession window shut leave no stale advice behind (review items 31, 37, 38, 41, 10).

local CP = ProfLost
local ENCHANTING, TAILOR, ALCHEMY, LW = 333, 197, 171, 165
local DUST = 10940
local SILVERPINE = 1421
local BELT_PATTERN, BELT_SPELL = 5786, 6702   -- Pattern: Murloc Scale Belt, limited, vendor 843 / 3556
local BELT_VENDOR = 843

local function open(line)
    CraftWorld.Open(line)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
end

-- Item 31 ---------------------------------------------------------------------------------

T.test("a dropped profession's greens stop counting toward Enchanting's dust", function()
    MapWorld.begin({ zone = 1429, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 53, max = 75 }, [TAILOR] = { rank = 66, max = 150 } } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    open(ENCHANTING)
    open(TAILOR)
    T.ok(CP.Shared.DEIncomingSplit(DUST).later > 0, "Tailoring feeds dust while the player has it")
    T.ok(CP.Shared.DEIncoming(DUST) > 0)

    CraftWorld.DropProfession(TAILOR)
    T.advance(10)
    CP.Gather.UpdateAllNeeds()
    T.eq(CP.charDB.lastPlan[TAILOR], nil, "the dropped profession's plan is forgotten")
    local split = CP.Shared.DEIncomingSplit(DUST)
    T.eq({ split.now, split.later }, { 0, 0 })
    local n, names = CP.Shared.DEIncoming(DUST)
    T.eq({ n, #names }, { 0, 0 })

    -- Re-solving Enchanting leaves it gone.
    open(ENCHANTING)
    CP.Gather.UpdateAllNeeds()
    T.eq(CP.Shared.DEIncomingSplit(DUST).later, 0)
end)

-- Item 41 ---------------------------------------------------------------------------------

T.test("a dropped profession leaves the data text, launcher tooltip and Next up", function()
    MapWorld.begin({ zone = 1429, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ALCHEMY] = { rank = 60, max = 75 }, [TAILOR] = { rank = 60, max = 75 } } })
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(1)
    open(ALCHEMY)
    open(TAILOR)
    T.eq(CP.charDB.lastProf, TAILOR)
    T.ok(CP.charDB.nextStep[TAILOR] ~= nil)

    CraftWorld.DropProfession(TAILOR)
    T.advance(10)
    T.eq(CP.charDB.nextStep[TAILOR], nil, "no saved next step")
    T.ok(CP.charDB.lastProf ~= TAILOR, "not the last profession")
    T.ok(not CP.Launcher.Text():find("Tailoring", 1, true), CP.Launcher.Text())
    local lines = {}
    local tip = {}
    function tip.AddDoubleLine(_, left) lines[#lines + 1] = left end
    function tip.AddLine(_, text) lines[#lines + 1] = text end
    CP.Launcher.Steps(tip)
    for _, l in ipairs(lines) do T.ok(not l:find("Tailoring", 1, true), l) end
end)

-- Item 38 ---------------------------------------------------------------------------------

T.test("a pattern learned with the profession window shut leaves Patterns to buy here", function()
    MapWorld.begin({ zone = SILVERPINE, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = 150, max = 225 } } })
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.Waypoint, "InZone", function(_, _, zone)
        return zone == SILVERPINE and { name = "Andrew Hilbert", continent = 0, x = 528, y = 1634 } or nil
    end)
    local guide = CP.Guides[LW]
    local watch
    for _, b in ipairs(CP.Guide.VendorBuys(guide, {}, 225)) do
        if b.item == BELT_PATTERN then watch = b end
    end
    T.ok(watch ~= nil, "the guide sells the belt pattern")
    World.set(CP.charDB, "vendorWatch", { [LW] = { watch } })
    local function listed()
        for _, f in ipairs(CP.VendorWatch.Find(SILVERPINE, true)) do
            if f.buy.item == BELT_PATTERN then return true end
        end
        return false
    end
    T.ok(listed(), "listed while unlearned")
    CraftWorld.Learn(LW, BELT_SPELL)
    T.advance(1)
    T.ok(not listed(), "gone once learned, window shut")
end)

-- Items 37 and 10 -------------------------------------------------------------------------

local function merchant(entry, slots)
    World.onEnd(function() T.fire("MERCHANT_CLOSED") end)
    World.patch("UnitGUID", function(unit)
        if unit == "npc" then return ("Creature-0-0-0-0-%d-0000000000"):format(entry) end
        return nil
    end)
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i].id end)
    World.patch("GetMerchantItemLink", function(i)
        return slots[i] and slots[i].link and ("|cffffffff|Hitem:%d::::::::|h[Item]|h|r"):format(slots[i].link) or nil
    end)
    World.patch("C_MerchantFrame.GetItemInfo", function()
        return { price = 100, stackCount = 1, numAvailable = 1, isPurchasable = true }
    end)
end

local function watchBelt()
    World.set(CP.charDB, "vendorWatch", { [LW] = { { name = "Murloc Scale Belt", item = BELT_PATTERN, skill = 120,
        npcs = { BELT_VENDOR }, limited = true } } })
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.onEnd(function() CP.VendorWatch.CheckMerchant(BELT_VENDOR, { [BELT_PATTERN] = true }) end)
end

T.test("a vendor that lists the pattern again clears its sold-out mark", function()
    watchBelt()
    T.ok(not CP.VendorWatch.IsSoldOut(BELT_PATTERN))
    merchant(BELT_VENDOR, { { id = 7451 } })
    T.fire("MERCHANT_SHOW")
    T.ok(CP.VendorWatch.IsSoldOut(BELT_PATTERN), "a vendor showing it gone marks it")
    merchant(BELT_VENDOR, { { id = 7451 }, { id = BELT_PATTERN } })
    T.fire("MERCHANT_SHOW")
    T.ok(not CP.VendorWatch.IsSoldOut(BELT_PATTERN), "the restocked listing clears it")
end)

T.test("a merchant slot whose item has not loaded does not mark the pattern sold out", function()
    watchBelt()
    merchant(BELT_VENDOR, { { id = 7451 }, { id = nil, link = BELT_PATTERN } })
    T.fire("MERCHANT_SHOW")
    T.ok(not CP.VendorWatch.IsSoldOut(BELT_PATTERN), "the link names it")

    merchant(BELT_VENDOR, { { id = 7451 }, { id = nil, link = nil } })
    T.fire("MERCHANT_SHOW")
    T.ok(not CP.VendorWatch.IsSoldOut(BELT_PATTERN), "a slot with nothing loaded says nothing")
end)
