-- The gathering data lists only loot anyone can gather: no quest-only or conditional drops
-- (Root Sample, Tainted Vitriol, the yeti hides). A herb that gives nothing but a quest
-- item (Doom Weed) still spawns in the data, and the guides offer it to no one (simulator
-- cross-check, 2026-11-16).

local CP = ProfLost
local D = CP.GatherData
local ROOT_SAMPLE, TAINTED_VITRIOL, THICK_YETI_HIDE, BLOOD_SHARD = 5056, 11513, 8973, 5075
local SILVERLEAF, MITHRIL, FERAL_SCAR_YETI, COPPER, DOOM_WEED = 1617, 2040, 5292, 1731, 176753

local function items(key)
    local out = {}
    for _, l in ipairs(D.loot[key] or {}) do out[l[1]] = l[2] end
    return out
end

T.test("quest-only and conditional drops are not gathering loot", function()
    T.eq(items(D.nodes[SILVERLEAF][3])[ROOT_SAMPLE], nil, "Root Sample from Silverleaf")
    T.eq(items(D.nodes[MITHRIL][3])[TAINTED_VITRIOL], nil, "Tainted Vitriol from Mithril")
    T.eq(items(D.nodes[COPPER][3])[BLOOD_SHARD], nil, "Blood Shard from Copper")
    T.eq(items(D.mobs[FERAL_SCAR_YETI][4][393])[THICK_YETI_HIDE], nil, "Thick Yeti Hide")
    T.ok(next(items(D.nodes[SILVERLEAF][3])) ~= nil, "Silverleaf still gives its herb")
end)

T.test("a quest-only herb spawns in the data and is no one's target", function()
    local n = D.nodes[DOOM_WEED]
    T.ok(n ~= nil, "Doom Weed is a node")
    T.eq(#(D.loot[n[3]] or {}), 0, "with no loot anyone can gather")
    for _, src in ipairs(CP.GatherGuide.Sources(182)) do
        T.ok(src.entry ~= DOOM_WEED, "Doom Weed offered as a Herbalism target")
    end
end)
