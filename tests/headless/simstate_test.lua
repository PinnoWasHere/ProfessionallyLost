-- The worlds' snapshot and restore pairs (the simulator's real reload carries them to a new
-- process): a scene started from a snapshot snapshots the same again, and a snapshot is plain
-- data, with no function, frame or shared table.

local CP = ProfLost
local LW, TAILOR, FISHING = 165, 197, 356

-- A snapshot as one line, keys sorted, so two compare as strings.
local function text(v, seen)
    seen = seen or {}
    local t = type(v)
    if t == "table" then
        if seen[v] then error("a snapshot shares a table between two places") end
        seen[v] = true
        if rawget(v, 0) ~= nil then error("a snapshot holds a frame") end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) ~= type(b) then return type(a) < type(b) end
            return a < b
        end)
        local parts = {}
        for _, k in ipairs(keys) do
            if type(k) ~= "number" and type(k) ~= "string" then error("a snapshot key is a " .. type(k)) end
            parts[#parts + 1] = ("[%s]=%s"):format(type(k) == "string" and ("%q"):format(k) or tostring(k), text(v[k], seen))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    if t == "function" or t == "userdata" or t == "thread" then error("a snapshot holds a " .. t) end
    return t == "string" and ("%q"):format(v) or tostring(v)
end

T.test("CraftWorld: a character started from its snapshot is the same character", function()
    CraftWorld.begin({ professions = { [LW] = { rank = 120, max = 150 }, [TAILOR] = 40 }, bags = { [2318] = 7 },
                       bank = { [2319] = 3 } })
    CraftWorld.Learn(LW, 2149)
    CraftWorld.SetBag(4234, 2)
    local snap = CraftWorld.Snapshot()
    local before = text(snap)
    T.eq(snap.order[1], LW, "learning order kept")
    T.ok(#snap.profs[LW].known > 0, "known recipes kept")

    World.finish()
    CraftWorld.begin({ from = snap })
    T.eq(text(CraftWorld.Snapshot()), before, "the same character")
    T.eq(CraftWorld.Bag(2318), 7)
    T.eq(C_Item.GetItemCount(2319, true), 3, "the bank too")
    T.ok(CraftWorld.Known(LW, 2149))
    T.eq(select(3, GetProfessionInfo(1)), 120, "GetProfessions keeps its order")
    snap.bags[2318] = 99
    T.eq(CraftWorld.Bag(2318), 7, "the scene owns its copy")
end)

T.test("CraftWorld: a profession learned and unlearned mid-scene", function()
    CraftWorld.begin({ professions = { [LW] = 60 } })
    local fired = 0
    local f = CreateFrame("Frame")
    f:RegisterEvent("SKILL_LINES_CHANGED")
    f:SetScript("OnEvent", function() fired = fired + 1 end)
    CraftWorld.AddProfession(FISHING, { rank = 1, max = 75, known = {} })
    T.eq(C_SkillInfo.GetSkillLineInfoByID(FISHING).rank, 1)
    CraftWorld.Open(FISHING)
    CraftWorld.DropProfession(FISHING)
    T.eq(C_SkillInfo.GetSkillLineInfoByID(FISHING), nil, "gone from the skill list")
    T.eq(CraftWorld.Opened(), nil, "its window closed")
    T.eq(fired, 2, "SKILL_LINES_CHANGED on each")
    f:UnregisterAllEvents()
end)

T.test("MapWorld: the snapshot starts the same spot", function()
    MapWorld.begin({ zone = 1411, x = 0.3, y = 0.6, level = 22, side = "Horde" })
    MapWorld.Move(1413, 0.4, 0.5)
    local snap = MapWorld.Snapshot()
    local before = text(snap)
    World.finish()
    MapWorld.begin(snap)
    T.eq(text(MapWorld.Snapshot()), before)
    T.eq(C_Map.GetBestMapForUnit("player"), 1413)
    T.eq(UnitLevel("player"), 22)
end)

T.test("VendorWorld: purse, spending and limited stock carry over", function()
    CraftWorld.begin({ professions = { [LW] = 60 } })
    VendorWorld.begin({ money = 5000 })
    VendorWorld.Open({ entry = 3364, name = "Borya", items = { { item = 5083, price = 100, limit = 2 } } })
    BuyMerchantItem(1, 1)
    VendorWorld.Close()
    local snap = VendorWorld.Snapshot()
    local before = text(snap)
    T.eq(snap.stock[3364][5083], 1)

    World.finish()
    CraftWorld.begin({ professions = { [LW] = 60 } })
    VendorWorld.begin({ from = snap })
    T.eq(text(VendorWorld.Snapshot()), before)
    T.eq(GetMoney(), 4900)
    VendorWorld.Open({ entry = 3364, name = "Borya", items = { { item = 5083, price = 100, limit = 2 } } })
    T.eq(C_MerchantFrame.GetItemInfo(1).numAvailable, 1, "one left, not a fresh two")
end)

T.test("GatherWorld: counts, loot and waypoint carry over", function()
    local facts = { zones = { [1411] = { name = "Durotar", nodes = { [1731] = { n = 5 } } } },
                    nodes = { [1731] = { line = 186, name = "Copper Vein", skill = 1, loot = { { 2770, 100, 1, 1 } } } },
                    mobs = {} }
    MapWorld.begin({ zone = 1411, level = 10 })
    CraftWorld.begin({ professions = { [186] = 1 } })
    GatherWorld.begin({ facts = facts, seed = 3 })
    GatherWorld.Gather(186)
    C_Map.SetUserWaypoint({ uiMapID = 1411, position = CreateVector2D(0.2, 0.3) })
    local snap = GatherWorld.Snapshot()
    local before = text(snap)
    T.eq(snap.harvests, 1)

    World.finish()
    MapWorld.begin({ zone = 1411, level = 10 })
    CraftWorld.begin({ professions = { [186] = 1 } })
    GatherWorld.begin({ facts = facts, seed = 3, from = snap })
    T.eq(text(GatherWorld.Snapshot()), before)
    T.eq(GatherWorld.Waypoint().x, 0.2)
end)

T.test("DaylightWorld: settings and picks carry over; its window turns off and on", function()
    CraftWorld.begin({ professions = { [TAILOR] = 60 } })
    DaylightWorld.begin({ settings = { ProfLost = { collect = false } } })
    CraftWorld.Open(TAILOR)
    T.advance(0.1)
    T.ok(DaylightWorld.state.window:IsShown(), "its window took the profession")
    local snap = DaylightWorld.Snapshot()
    local before = text(snap)
    T.ok(snap.picked[TAILOR] ~= nil, "a pick")

    DaylightWorld.SetCraftWindow(false)
    T.ok(not DaylightWorld.state.window:IsShown(), "off: its window hides")
    CraftWorld.Close()
    CraftWorld.Open(TAILOR)
    T.advance(0.1)
    T.ok(not DaylightWorld.state.window:IsShown(), "and takes no profession window")
    T.ok(ProfessionsFrame:IsVisible(), "the game's window shows")
    CraftWorld.Close()

    World.finish()
    CraftWorld.begin({ professions = { [TAILOR] = 60 } })
    DaylightWorld.begin({ from = snap })
    T.eq(text(DaylightWorld.Snapshot()), before)
    T.eq(CP.Settings.Current("collect"), false, "the saved setting answers")
end)
