-- cloth, the truth half (decision 0006): every shipped zone's cloth rows
-- are backed by droppers the side may kill at most FARM_SAFE_LEVELS above it, and a plainly good pool
-- shows a row. The truth lists every creature of a zone that drops a cloth, with its levels, spawns,
-- cloth a kill and NPC side; the guide pools them into bands of CLOTH_BAND levels whose highest
-- minimum level must be at most FARM_SAFE_LEVELS above the player.
--
-- ctx: CP, level, side, cloth (the cloth truth, or nil), zoneName(zone) (the map's name for a zone).
-- Returns the violations and how many rows were checked.

setfenv(1, Rules.ENV)

Rules.CLOTH_NAMES = { [2589] = "Linen Cloth", [2592] = "Wool Cloth", [4306] = "Silk Cloth",
                      [4338] = "Mageweave Cloth", [14047] = "Runecloth", [14256] = "Felcloth" }
Rules.CLOTH_BAND = 5            -- the guide's band width (the cloth generator's BAND)
Rules.CLOTH_YIELD = 0.05        -- a creature counts at this cloth a kill (cloth.py MIN_YIELD)
Rules.CLOTH_PLAIN = { kills = 30, per = 0.1 }   -- a pool this good must show a row

local function clothZone(ctx, zone)
    return ("%s (%d)"):format(ctx.zoneName(zone) or "zone", zone)
end

-- The truth's spawns of `item` droppers in `zone` the side may kill at `level`, and the lowest
-- minimum level of any dropper the side may kill (for the message).
local function safeTruth(ctx, zone, item, level, side)
    local by = ctx.cloth.zones[zone] and ctx.cloth.zones[zone][item] or {}
    local mine = side == "Alliance" and "A" or "H"
    local n, lowest = 0, nil
    for _, d in pairs(by) do
        if d.side ~= mine then
            lowest = math.min(lowest or d.min, d.min)
            if d.min <= level + ctx.CP.Gather.FARM_SAFE_LEVELS then n = n + d.n end
        end
    end
    return n, lowest
end

-- One row's claim `c` in `zone` against the truth, as violations. `where` prefixes each.
-- ctx: CP, level, side, cloth, zoneName.
-- @rule[ClothClaim] independent: the cloth truth's droppers and levels against one row's claim
function Rules.ClothClaim(ctx, zone, c, where)
    local level, side = ctx.level, ctx.side
    local out = {}
    local n, lowest = safeTruth(ctx, zone, c.item, level, side)
    local name = Rules.CLOTH_NAMES[c.item] or ("item " .. c.item)
    local top = level + ctx.CP.Gather.FARM_SAFE_LEVELS
    if n <= 0 then
        out[#out + 1] = ("%s%s: a %s row at level %d (%d-%d), but the truth has no creature the %s may kill "
            .. "at level %d or less that drops it%s"):format(where or "", clothZone(ctx, zone), name, level, c.lo, c.hi, side,
            top, lowest and (" (lowest %d)"):format(lowest) or " (none at all)")
    end
    for i, s in ipairs(c.spots or {}) do
        if s.lo > top then
            out[#out + 1] = ("%s%s: %s spot #%d (%s) starts at level %d, over %d"):format(where or "", clothZone(ctx, zone),
                name, i, s.name, s.lo, top)
        end
    end
    return out
end

-- @rule[Cloth] self: the missing-row half counts a band safe through the addon's Gather.ClothSafe
function Rules.Cloth(ctx)
    local CP, level, side, cloth = ctx.CP, ctx.level, ctx.side, ctx.cloth
    local out, rows = {}, 0
    if not cloth then return out, 0 end
    local zones = {}
    for zone in pairs(cloth.zones) do zones[#zones + 1] = zone end
    table.sort(zones)
    for _, zone in ipairs(zones) do
        if CP.GatherData.zones[zone] then
            for _, item in ipairs(CP.Gather.CLOTH) do
                local c = CP.Gather.Cloth(zone, item, level, side)
                if c then
                    rows = rows + 1
                    for _, v in ipairs(Rules.ClothClaim(ctx, zone, c)) do out[#out + 1] = v end
                else
                    -- A band is safe once its highest minimum level is: count only droppers whose whole
                    -- band is, of any kind, that either faction may kill.
                    local kills, got = 0, 0
                    for _, d in pairs(cloth.zones[zone][item] or {}) do
                        local band = math.floor(d.min / Rules.CLOTH_BAND) * Rules.CLOTH_BAND + Rules.CLOTH_BAND - 1
                        if d.side ~= "A" and d.side ~= "H" and d.per >= Rules.CLOTH_YIELD and CP.Gather.ClothSafe(band, level) then
                            kills, got = kills + d.n, got + d.n * d.per
                        end
                    end
                    if kills >= Rules.CLOTH_PLAIN.kills and got / kills >= Rules.CLOTH_PLAIN.per then
                        out[#out + 1] = ("%s: the truth has %d spawns the %s may kill at level %d giving %s at %.2f a "
                            .. "kill, and the panel would show no row"):format(clothZone(ctx, zone), math.floor(kills + 0.5),
                            side, level, Rules.CLOTH_NAMES[item], got / kills)
                    end
                end
            end
        end
    end
    return out, rows
end
