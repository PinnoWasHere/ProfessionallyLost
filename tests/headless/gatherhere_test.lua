-- An errand leaves the player in a zone far above them (a crafting trainer or vendor in
-- Booty Bay or Feralas), and the gathering guide must not keep them there. The first stretch
-- stays within what the character survives (GG.Workable) wherever the player stands, or asks
-- a level first (farm picks lane, 2026-11-16: with Blacksmithing beside it, Mining 150 at
-- level 20 went to Stranglethorn Vale; with Alchemy, Herbalism 175 at level 20 to Feralas).

local CP = ProfLost
local GG = CP.GatherGuide
local HERB, MINE, SKIN = 182, 186, 393
local FERALAS = 1444

local function warm(line)
    local frames = 0
    repeat
        GG.Warm(line)
        T.advance(0.02, 0.02)
        frames = frames + 1
    until not GG.Warming() and GG.Ready(line) or frames > 100000
end

-- The first gathering row for `line` at `skill` and `level`, standing in `here`.
local function first(line, skill, max, level, here, side)
    for _, r in ipairs(GG.Rows({ line = line, skill = skill, max = max, level = level, zone = here, side = side })) do
        if r.gather and not r.side then return r end
    end
end

local function low(zone)
    local lvl = GG.ZONE_LEVELS[zone] or (CP.GatherData.zones[zone] and CP.GatherData.zones[zone].lvl)
    return lvl and lvl[1]
end

-- The row works for the character: its zone within GG.Workable, or a level row.
local function fits(row, level, what)
    T.ok(row ~= nil, what .. ": a first stretch")
    if not row then return end
    local zone, gate = row.gather.zone, row.gather.level
    local lo = low(zone)
    T.ok(gate ~= nil or not lo or lo <= GG.Workable(level),
        ("%s: zone %d (low level %s) for a level %d character, no level row"):format(what, zone, tostring(lo), level))
end

T.test("Herbalism 175 at level 20, standing in Feralas: the first stretch is not Feralas", function()
    warm(HERB)
    local row = first(HERB, 175, 225, 20, FERALAS, "Alliance")
    T.ok(row and row.gather.zone ~= FERALAS, "Feralas (41-47) is no place for level 20")
    fits(row, 20, "Herbalism 175")
end)

T.test("standing in any zone far above the character, the first stretch stays workable", function()
    local checked = 0
    for _, line in ipairs({ HERB, MINE, SKIN }) do
        warm(line)
        for zone, z in pairs(CP.GatherData.zones) do
            local lo = low(zone)
            if z.map and lo and lo > GG.Workable(20) and not GG.SKIP[zone] and not z.inst then
                for _, skill in ipairs({ 150, 175 }) do
                    for _, side in ipairs({ "Alliance", "Horde" }) do
                        fits(first(line, skill, 225, 20, zone, side), 20,
                            ("line %d skill %d %s standing in %d"):format(line, skill, side, zone))
                        checked = checked + 1
                    end
                end
            end
        end
    end
    T.ok(checked > 50, "cases checked: " .. checked)
end)

T.test("the player's own zone still holds within what the character survives", function()
    warm(HERB)
    -- Durotar (low 5) for a level 10 herbalist at 1: the guide starts where the player stands.
    local row = first(HERB, 1, 75, 10, 1411, "Horde")
    T.eq(row and row.gather.zone, 1411)
end)
