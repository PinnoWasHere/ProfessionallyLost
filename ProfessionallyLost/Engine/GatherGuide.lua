local _, CP = ...
if CP.stopped then return end

-- Leveling guides for the gathering professions: Herbalism, Mining, Skinning and
-- Fishing. A guide is a list of rows from the player's skill to 300. Train rows say
-- when the next rank is due; gather rows say what gives skill and in which zones.
-- Pure logic over CP.GatherData, so it runs headless.

local GG = {}
CP.GatherGuide = GG

local G = CP.Gather
local MAX_SKILL = 300
local STEP = 5          -- skill points between zone checks
local MIN_BAND = 15     -- a shorter stretch folds into the one before it
local TOP_ZONES = 3
-- A zone is safe while its low level is at most GG.SAFE_LEVELS above the player. With nothing
-- safe, the margin widens MARGIN_STEP levels at a time up to what the character survives
-- (GG.Workable), then a further GROUND_SLACK so own-faction ground close in level outranks a
-- contested zone. Past that, the stretch asks the character to level first (GG.MAX_MARGIN
-- finds the zone it levels for).
GG.SAFE_LEVELS, GG.MARGIN_STEP, GG.MAX_MARGIN, GG.GROUND_SLACK = 2, 2, 60, 4
-- Creatures GG.SURVIVE levels above the character are the most it can work among; five
-- above con red. A zone whose creatures start at GG.REACH or below suits any character.
GG.SURVIVE, GG.REACH = 4, 12
-- A level row takes the best zone among those opening within this many levels of the nearest.
GG.LEVEL_WINDOW = 2
-- The level cap: past it no level row can help.
GG.MAX_LEVEL = 60

-- The highest low creature level a zone may have, and the highest level a skinning target
-- may be, for a character of `level`.
function GG.Workable(level)
    return math.max(level + GG.SURVIVE, GG.REACH)
end
-- Zones never picked: capital cities (few spawns, on top of their neighbour).
local SKIP = {
    [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true,
}
GG.SKIP = SKIP
GG.MIN_SPAWNS = 20     -- fewer skill-giving spawns than this and a zone isn't worth the trip
local STICKY = 0.8      -- keep the band's zone while it scores at least this share of the best
local HOME = 0.4        -- start in the player's zone while it scores at least this share
GG.HOME_BEHIND = 0.2    -- the same, while the skill trails the player's level
GG.HOME_SKILL = 50      -- a character under HOME_LEVEL stays on their continent below this skill
GG.HOME_LEVEL = 20
local LEVEL_STRETCH = 25 -- skill points the player's current level caps zones and creatures
local RANK_NAMES = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }
local VERB = { [182] = "Pick", [186] = "Mine", [393] = "Skin" }
-- A zone's score by whose ground it is: the player's own side first, contested next,
-- the other side's levelling zones only when nothing else comes close.
local GROUND = { own = 1, contested = 0.6, enemy = 0.25 }

GG.LINES = { [182] = true, [186] = true, [393] = true, [356] = true }

function GG.Has(skillLine)
    return GG.LINES[skillLine] == true
end

-- The band's skill-up chance gathering something that needs `req` at `skill` (cMaNGOS):
-- orange below req+25, yellow below req+50, green below req+100, then grey.
function GG.Band(skill, req)
    if skill < req then return 0 end
    if skill < req + 25 then return 1 end
    if skill < req + 50 then return 0.75 end
    if skill < req + 100 then return 0.25 end
    return 0
end

-- The band's chance with the Working Overtime perk's multiplier (Guide.Boost).
function GG.Chance(skill, req)
    return CP.Guide.Boost(GG.Band(skill, req))
end

-- Weight of a target when choosing zones: green counts for little, so the guide moves
-- on to yellow and orange targets. Spawn points overstate live green nodes too, since
-- many share a spawn pool.
GG.GREEN = 0.1          -- weight of a green target: it gives little, so the guide moves on
GG.GREEN_ONLY = 0.1     -- a zone whose only skill-giving targets are green scores this share: a last resort
-- The least skill points per node found, over every node of the profession in the zone. Below
-- it a zone is thin: most finds give nothing, so the first stretch treats it like a green-only
-- zone and asks for a level. At 0.075, 40 finds without a point have under a 5% chance.
GG.MIN_YIELD = 0.075
GG.AREA_EXP = 0.5       -- score is spawns / area^AREA_EXP: per km² alone lets small dense zones win every band
GG.MAX_BAND = 50        -- longest stretch in one zone before the zone is chosen afresh
GG.LEVEL_FIT = 12       -- levels off the expected one at which a zone scores half (0: off)

GG.LANE = 1.5           -- a zone in the faction's levelling lane at the expected level
GG.LEFT = 0.7           -- a zone the guide already left: no going back and forth
GG.SITE = 2             -- a zone wow-professions.com names for this skill (Data/SiteZones.lua)
GG.SITE_EARLY = 5       -- skill points before a site band that its zones already count

-- True when wow-professions.com's guide for `line` names `zone` at `skill` for `side`.
function GG.InSite(line, zone, side, skill)
    local bands = CP.SiteZones and CP.SiteZones[line]
    for _, band in ipairs(bands and bands[side] or {}) do
        if skill >= band[1] - GG.SITE_EARLY and skill < band[2] then
            for _, z in ipairs(band[3]) do
                if z == zone then return true end
            end
        end
    end
    return false
end

-- True when `zone` is in `side`'s levelling lane (Data/Lanes.lua) at `level`, give or
-- take two levels.
function GG.InLane(zone, side, level)
    for _, step in ipairs(CP.Lanes and CP.Lanes[side] or {}) do
        if level >= step[1] - 2 and level <= step[2] + 2 then
            for _, z in ipairs(step[3]) do
                if z == zone then return true end
            end
        end
    end
    return false
end

-- The level a character gathering at `skill` tends to be (5 at 1, 40 at 175, 60 from 275).
function GG.LevelFor(skill)
    return math.max(1, math.min(60, math.floor(skill / 5) + 5))
end

local function weight(skill, req)
    local c = GG.Band(skill, req)
    return c == 0.25 and GG.GREEN or CP.Guide.Boost(c)
end

-- Difficulty index matching the profession window's colours: 1 orange, 2 yellow, 3 green, 4 grey.
function GG.Difficulty(skill, req)
    if skill < req + 25 then return 1 end
    if skill < req + 50 then return 2 end
    if skill < req + 100 then return 3 end
    return 4
end

-- Everything a profession gathers: { { kind, entry, name, req, level? } }. Herbs and
-- ore are nodes; Skinning is creatures, whose skill comes from their level.
local sources = {}
function GG.Sources(line)
    if sources[line] then return sources[line] end
    local out = {}
    if line == G.SKINNING then
        -- The data's skins index: entry, name, minLevel, maxLevel, loot key per creature.
        local skins = CP.GatherData.Index("skins")
        for i = 1, #skins, 5 do
            local entry = skins[i]
            if G.Skinnable(entry) then
                local level = math.floor((skins[i + 2] + skins[i + 3]) / 2)
                out[#out + 1] = { kind = "mobs", entry = entry, name = skins[i + 1], req = G.CorpseSkill(level),
                                  level = level, loot = skins[i + 4] }
            end
        end
    else
        -- A node with nothing to loot but quest drops is no one's target.
        for entry, n in pairs(CP.GatherData.nodes) do
            if n[4] == line and n[2] and #(CP.GatherData.loot[n[3]] or {}) > 0 then
                out[#out + 1] = { kind = "nodes", entry = entry, name = n[1], req = n[2], loot = n[3] }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.req ~= b.req then return a.req < b.req end
        return a.name < b.name
    end)
    sources[line] = out
    return out
end

-- Per zone, the profession's sources the game places there and how many spawns each
-- has: { [zone] = { { src, n } } }. Zone rectangles overlap, so Gather.Clusters checks
-- each cluster against the map. Built once per profession. `tick` (optional) runs after
-- each map lookup and each cluster list, for the background job.
local placed = {}

local function build(line, tick)
    local out = {}
    for _, src in ipairs(GG.Sources(line)) do
        for zone in pairs(CP.GatherData.zones) do
            if G.Holds(zone, src.kind, src.entry) then
                local n = 0
                for _, c in ipairs(G.Clusters(zone, src.kind, src.entry, tick)) do n = n + c[3] end
                if n > 0 then
                    out[zone] = out[zone] or {}
                    table.insert(out[zone], { src = src, n = n })
                end
                if tick then tick() end
            end
        end
    end
    return out
end

-- The map epoch each line was last built under. The map answers outlast GG.Reset, so a
-- rebuild after a find or a GatherMate2 change asks the map nothing new.
local warmed = {}

local function inZones(line)
    if not placed[line] then
        placed[line] = build(line)
        warmed[line] = G.MapEpoch()
    end
    return placed[line]
end

-- The first build asks the map about every spawn on every continent, too much for one
-- frame. A background job builds it a slice a frame. Callers inside an event check
-- GG.Ready first and show WARM.waiting until the job raises WARM.signal.
GG.WARM = {
    points = 300,       -- map lookups and cluster lists in one frame at most
    frameMs = 4,        -- milliseconds of work in one frame at most
    clockEvery = 25,    -- steps between looks at the clock
    gap = 0.001,        -- seconds between slices; above 0, so each slice runs on a later frame
    waiting = "finding zones",
    signal = "ProfLost_GATHER_ZONES",
}

local job, generation = nil, 0

-- The last finished job: frames, steps (map lookups and cluster lists), the most steps
-- in one frame, and the longest frame's milliseconds.
GG.lastWarm = { frames = 0, steps = 0, most = 0, longest = 0 }

-- True when `line`'s guide rows need no map work (Fishing never does).
function GG.Ready(line)
    return line == G.FISHING or not GG.LINES[line] or placed[line] ~= nil or warmed[line] == G.MapEpoch()
end

function GG.Warming()
    return job ~= nil
end

-- `line` (optional) and the player's gathering skills whose zones aren't built yet.
local function pending(line)
    local out = {}
    if line and not GG.Ready(line) then out[1] = line end
    for id in pairs(G.Skills()) do
        if id ~= line and not GG.Ready(id) then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- One frame's work for job `j`, then the next slice on a later frame. A job that was
-- dropped or replaced stops here.
local function slice(j)
    if job ~= j then return end
    j.steps, j.start = 0, debugprofilestop()
    local ok, err = coroutine.resume(j.co)
    if job ~= j then return end
    local stats = j.stats
    stats.frames, stats.steps = stats.frames + 1, stats.steps + j.steps
    stats.most = math.max(stats.most, j.steps)
    stats.longest = math.max(stats.longest, debugprofilestop() - j.start)
    if not ok then
        job = nil
        CP:Print(("Couldn't find gathering zones. /proflost bug to report it (%s)."):format(tostring(err)))
    elseif coroutine.status(j.co) == "dead" then
        job = nil
        GG.lastWarm = stats
        CP:Emit(GG.WARM.signal)
    else
        C_Timer.After(GG.WARM.gap, function() slice(j) end)
    end
end

-- Starts the job for `line` (optional) and the player's gathering skills, unless it
-- runs or nothing is pending.
function GG.Warm(line)
    if job then return end
    local lines = pending(line)
    if #lines == 0 then return end
    local gen, cfg = generation, GG.WARM
    local j = { stats = { frames = 0, steps = 0, most = 0, longest = 0 } }
    local function tick()
        j.steps = j.steps + 1
        if j.steps >= cfg.points
            or (j.steps % cfg.clockEvery == 0 and debugprofilestop() - j.start >= cfg.frameMs) then
            coroutine.yield()
        end
    end
    j.co = coroutine.create(function()
        for _, line in ipairs(lines) do
            if not placed[line] then
                local out = build(line, tick)
                if generation ~= gen then return end
                placed[line], warmed[line] = out, G.MapEpoch()
            end
        end
    end)
    job = j
    C_Timer.After(cfg.gap, function() slice(j) end)
end

-- Stops the job; what it finished stays. A test's job ends with the test.
function GG.Stop()
    job = nil
end

-- Stops the job and drops what it built, as a fresh login starts. Test scenes call it.
function GG.Forget()
    job = nil
    generation = generation + 1
    wipe(placed)
    wipe(warmed)
end

-- Level ranges that replace the data's. Zephras Isle is a starting isle (a guess of
-- 1-12). Mount Hyjal's creature levels (47-56) come from vanilla spill-over, so its
-- range follows its nodes instead: Rich Thorium (230), Dreamfoil and Mountain
-- Silversage are level 55-60 ground. Moonglade's critters (level 1-5) drag its range down
-- to 1; its guards and furbolgs make it level 50+ ground.
GG.ZONE_LEVELS = { [2521] = { 1, 12 }, [2482] = { 55, 60 }, [1450] = { 50, 60 } }

-- Zephras Isle is the Skyborne starting isle: only a player standing in it gets it. Its
-- two maps (2521, 2665) both stand for the zone the data holds (2521).
GG.START_ONLY = { [2521] = 2521, [2665] = 2521 }

-- Zones offered as an "or" row under any stretch whose targets they cover, even when
-- they score below the stretch's own zone. Mount Hyjal's data holds only the three nodes
-- GatherLite names, so its score understates the zone.
GG.ALT_ZONES = { [2482] = true }

local function levels(zone)
    return GG.ZONE_LEVELS[zone] or CP.GatherData.zones[zone].lvl
end

-- A zone is safe while its low level is at most `margin` (default GG.SAFE_LEVELS) above the
-- player. The player's own zone gets at least what the character survives (GG.Workable), and
-- no more: an errand (a trainer or vendor for a crafting profession) can leave the player in
-- a zone far above them, and the guide must not keep them there.
local function safe(zone, level, here, margin)
    local lvl = levels(zone)
    if not (level and lvl) then return true end
    local most = level + (margin or GG.SAFE_LEVELS)
    if zone == here then most = math.max(most, GG.Workable(level)) end
    return lvl[1] <= most
end

-- Zones for gathering at `skill`, best first: { { zone, score, targets = { src... } } }.
-- A zone scores its skill-giving spawns per square kilometre, each weighted by its
-- skill-up chance, so a dense small zone beats a big sparse one.
-- `level` (optional) drops zones above the player and, for Skinning, creatures too
-- strong; `continent` (optional) keeps zones on that continent. `side` ("Alliance" or
-- "Horde", optional) skips the other faction's home zones. `here` (optional) is the
-- player's zone; GG.START_ONLY zones are offered only from there. `margin` (optional)
-- replaces the GG.SAFE_LEVELS the zone and creature levels may top the player's by.
function GG.Zones(line, skill, level, continent, side, fitLevel, left, here, margin)
    local out = {}
    local onStart = here and GG.START_ONLY[here]
    for zone, list in pairs(inZones(line)) do
        local z = CP.GatherData.zones[zone]
        if not SKIP[zone] and (onStart or not GG.START_ONLY[zone]) and not z.inst and not G.EnemyHome(zone, side) and safe(zone, level, here, margin)
            and not (continent and z.map ~= continent) then
            local score, total, targets, plain, ups, all, nodes = 0, 0, {}, false, 0, 0, false
            for _, p in ipairs(list) do
                local src = p.src
                local chance = weight(skill, src.req)
                all = all + p.n
                nodes = nodes or src.kind == "nodes"
                if chance > 0 and not (level and src.level and src.level > level + (margin or GG.SAFE_LEVELS)) then
                    score = score + p.n * chance
                    total = total + p.n
                    targets[#targets + 1] = src
                    plain = plain or chance > GG.GREEN
                    ups = ups + p.n * GG.Chance(skill, src.req)
                end
            end
            if not plain then score = score * GG.GREEN_ONLY end
            local area = ((z.w and z.h and z.w * z.h or 1e6) / 1e6) ^ GG.AREA_EXP
            local ground = side and GROUND[G.Territory(zone, side)] or 1
            -- Zones near the level a character gathering at this skill would be: a high
            -- zone's herbs are the ones the next stretch wants, a low zone's are leftovers.
            local lvl = levels(zone)
            if fitLevel and GG.LEVEL_FIT > 0 and lvl then
                local off = (lvl[2] - fitLevel) / GG.LEVEL_FIT
                ground = ground / (1 + off * off)
            end
            if fitLevel and side and GG.InLane(zone, side, fitLevel) then ground = ground * GG.LANE end
            if side and GG.InSite(line, zone, side, skill) then ground = ground * GG.SITE end
            if left and left[zone] then ground = ground * GG.LEFT end
            if total >= GG.MIN_SPAWNS then
                local yield = all > 0 and ups / all or 0
                -- Only herbs and ore are thin: a skinner picks the creatures it kills.
                out[#out + 1] = { zone = zone, score = score / area * ground, targets = targets, greenOnly = not plain or nil,
                                  yield = yield, thin = nodes and yield < GG.MIN_YIELD or nil }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.zone < b.zone
    end)
    return out
end

-- Expected gathers from `from` to `to` when the best target needs `req`.
function GG.GathersTo(from, to, targets)
    local total = 0
    for s = from, to - 1 do
        local best = 0
        for _, t in ipairs(targets) do best = math.max(best, GG.Chance(s, t.req)) end
        if best == 0 then return nil end
        total = total + 1 / best
    end
    return math.floor(total + 0.5)
end

-- The trainer ranks still to learn: { { skill = cap, level, npcs, name, at } }, where
-- `at` is the skill the rank can be learned at (25 below the cap it lifts).
function GG.Ranks(line, maxRank)
    local out = {}
    for _, r in ipairs(CP.GatherData.ranks and CP.GatherData.ranks[line] or {}) do
        if r.skill >= maxRank then
            out[#out + 1] = { skill = r.skill, at = r.skill - 25, level = r.level, npcs = r.npcs,
                              name = RANK_NAMES[r.skill] or "Next rank" }
        end
    end
    return out
end

-- Adds `more` sources to `list`, skipping ones already in it.
local function merge(list, more)
    local seen = {}
    for _, t in ipairs(list) do seen[t.kind .. t.entry] = true end
    for _, t in ipairs(more) do
        if not seen[t.kind .. t.entry] then
            seen[t.kind .. t.entry] = true
            list[#list + 1] = t
        end
    end
end

-- Offers `alt` ({ zone, targets }) as the band's "or" zone; one alternative per band.
local function addAlt(band, alt)
    if not alt or alt.zone == band.zone then return end
    band.alt = band.alt or { zone = alt.zone, targets = {} }
    if band.alt.zone == alt.zone then merge(band.alt.targets, alt.targets) end
end

-- The targets of `zone` that give skill at `skill`, within `level` (optional).
local function zoneTargets(line, zone, skill, level)
    local out = {}
    for _, p in ipairs(inZones(line)[zone] or {}) do
        local src = p.src
        if weight(skill, src.req) > 0 and not (level and src.level and src.level > level + GG.SAFE_LEVELS) then
            out[#out + 1] = src
        end
    end
    return out
end

-- The character level a zone of `GG.Zones` asks of `level`: its low creature level less
-- GG.SURVIVE, and for Skinning the lowest creature that gives a point. Always above `level`.
function GG.LevelNeed(line, level, z)
    local lvl = levels(z.zone)
    local need = (lvl and lvl[1] or level) - GG.SURVIVE
    if line == G.SKINNING then
        local lowest
        for _, t in ipairs(z.targets) do lowest = math.min(lowest or t.level, t.level) end
        if lowest then need = math.max(need, lowest - GG.SURVIVE) end
    end
    return math.max(need, level + 1)
end

-- The zone a character of `level` levels for when nothing it can work gives skill at
-- `skill`: the zone that opens at the lowest level, on `continent` first. { zone, score,
-- level, targets, where }, or nil. `level` is the character level the zone asks
-- (GG.LevelNeed). `targets` keeps only creatures the character can kill now; `where` holds
-- them all, for the zone's pin. `plain` (optional) skips zones whose only skill-giving
-- targets are green, and thin ones.
--
-- Among the zones opening within GG.LEVEL_WINDOW levels of the nearest one, the best
-- scoring wins, so a zone one or two levels further on beats a much poorer nearer one.
-- Beyond the window the nearer zone wins even when it scores lower, because a level row
-- that asks for ten more levels costs a player far more than a thinner zone.
function GG.LevelGate(line, skill, level, continent, side, fit, left, here, plain)
    -- The list is best first, so the first zone inside the window is the best there.
    local function pick(list)
        local nearest
        for _, z in ipairs(list) do
            if not (plain and (z.greenOnly or z.thin)) then
                z.need = GG.LevelNeed(line, level, z)
                nearest = math.min(nearest or z.need, z.need)
            end
        end
        for _, z in ipairs(list) do
            if z.need and z.need <= nearest + GG.LEVEL_WINDOW then return z end
        end
    end
    local z = pick(GG.Zones(line, skill, level, continent, side, fit, left, here, GG.MAX_MARGIN))
    if not z and continent then z = pick(GG.Zones(line, skill, level, nil, side, fit, left, here, GG.MAX_MARGIN)) end
    if not z then return nil end
    local targets = {}
    for _, t in ipairs(z.targets) do
        if t.level then
            if t.level <= GG.Workable(level) then targets[#targets + 1] = t end
        else
            targets[#targets + 1] = t
        end
    end
    return { zone = z.zone, score = z.score, level = z.need, targets = targets, where = z.targets }
end

-- True when a zone in `zones` has an orange or yellow target and isn't thin (GG.MIN_YIELD).
local function plainIn(zones)
    for _, z in ipairs(zones) do
        if not z.greenOnly and not z.thin then return true end
    end
    return false
end

-- Gather bands from `skill` to 300: { { from, to, zone, zones = { top 3 }, targets, alt? } }.
-- `alt` is { zone, targets }, a GG.ALT_ZONES zone the stretch can use as well.
-- The band keeps its zone while that zone scores within STICKY of the best, so the
-- guide doesn't hop between near-equal zones; targets merge over the band. The first
-- stretch is capped to the player's level and starts in `here` when it is close to
-- the best. Short stretches fold into the band before.
local function bands(line, skill, level, here, side)
    local out = {}
    here = GG.START_ONLY[here] or here
    -- Checks at the player's skill, then on multiples of STEP, so edges meet the rank caps.
    local s = skill
    while s < MAX_SKILL do
        local nextS = (math.floor(s / STEP) + 1) * STEP
        -- The first stretch stays on the player's continent, within their level.
        local early = s < skill + LEVEL_STRETCH
        -- Zones on the player's continent only: the first stretch, and a low-level
        -- character's guide up to Journeyman.
        local near = early or (s < GG.HOME_SKILL and (level or 1) < GG.HOME_LEVEL)
        local fit = math.max(level or 1, GG.LevelFor(s))
        -- Zones the guide moved on from, so it doesn't swing back to them.
        local left = {}
        for i = 1, #out - 1 do left[out[i].zone] = true end
        if out[#out] then left[out[#out].zone] = nil end
        local continent = near and here and CP.GatherData.zones[here] and CP.GatherData.zones[here].map or nil
        -- The first stretch is capped by the player's level, the rest of a near stretch by
        -- the level a character gathering at `s` tends to be.
        local cap = early and level or near and fit or nil
        local zones = GG.Zones(line, s, cap, continent, side, fit, left, here)
        -- The first stretch counts only zones with an orange or yellow target and enough of them
        -- among the zone's nodes: elsewhere most finds give nothing, and levelling opens a zone
        -- that pays.
        local function usable(list)
            if early then return plainIn(list) end
            return #list > 0
        end
        if cap and not usable(zones) then
            -- The first zones found, kept for when no level helps (level 60).
            local fallback = #zones > 0 and zones or nil
            -- Nothing within reach on the continent: zones a little above that level, then
            -- the other continents. A stretch capped by the player's own level never goes
            -- past what the character survives.
            local most = early and GG.Workable(cap) - cap or GG.MAX_MARGIN
            for margin = GG.SAFE_LEVELS + GG.MARGIN_STEP, most + GG.MARGIN_STEP - 1, GG.MARGIN_STEP do
                margin = math.min(margin, most)
                local list = GG.Zones(line, s, cap, continent, side, fit, left, here, margin)
                if #list > 0 then
                    local slack = margin + GG.GROUND_SLACK
                    list = GG.Zones(line, s, cap, continent, side, fit, left, here, early and math.min(slack, most) or slack)
                    fallback = fallback or list
                    if usable(list) then
                        zones = list
                        break
                    end
                end
            end
            if not usable(zones) and near then
                local list = GG.Zones(line, s, cap, nil, side, fit, left, here, most)
                if #list > 0 then fallback = fallback or list end
                if usable(list) then zones = list end
            end
            -- Nothing the character can work: the stretch asks for the level the next zone needs.
            if not usable(zones) and early and cap < GG.MAX_LEVEL then
                local gate = GG.LevelGate(line, s, cap, continent, side, fit, left, here, true)
                if gate then zones = { gate } end
            end
            if not usable(zones) then zones = fallback or {} end
        end
        -- A first stretch that has a zone that pays drops the thin ones.
        if early and plainIn(zones) then
            local kept = {}
            for _, z in ipairs(zones) do
                if not z.thin then kept[#kept + 1] = z end
            end
            zones = kept
        end
        local best = zones[1]
        local alt
        for _, z in ipairs(zones) do
            if GG.ALT_ZONES[z.zone] then alt = z break end
        end
        if best then
            local last = out[#out]
            -- The first stretch ends where the player's level stops capping it, so its
            -- targets stay within reach.
            -- A level stretch and a gathering stretch never share a band.
            local fresh = last and (last.to - last.from >= GG.MAX_BAND or last.early ~= early or last.level ~= best.level)
            local stay = not fresh and last and zones[1].zone == last.zone and zones[1]
            local prefer = not last and here
            -- A skill behind the player's level stays where they are while it still pays.
            local home = level and level > GG.LevelFor(s) and GG.HOME_BEHIND or HOME
            for _, z in ipairs(zones) do
                -- The player's own zone holds through the first stretch at the start share.
                local keep = (early and z.zone == here) and home or STICKY
                if last and not fresh and z.zone == last.zone and z.score >= best.score * keep then stay = z end
                if prefer and z.zone == prefer and z.score >= best.score * home then best = z end
            end
            if stay then
                last.to = math.min(nextS, MAX_SKILL)
                merge(last.targets, stay.targets)
            else
                local targets = { level = best.level, where = best.where }
                merge(targets, best.targets)
                out[#out + 1] = { from = s, to = math.min(nextS, MAX_SKILL), zone = best.zone, early = early,
                                  level = best.level, zones = { unpack(zones, 1, TOP_ZONES) }, targets = targets }
            end
            addAlt(stay and last or out[#out], alt)
        end
        s = nextS
    end
    -- A zone chosen afresh after MAX_BAND is often the same one: one band again.
    for i = #out, 2, -1 do
        if out[i].zone == out[i - 1].zone and out[i].early == out[i - 1].early and out[i].level == out[i - 1].level then
            out[i - 1].to = out[i].to
            merge(out[i - 1].targets, out[i].targets)
            addAlt(out[i - 1], out[i].alt)
            table.remove(out, i)
        end
    end
    for i = #out, 2, -1 do
        local b = out[i]
        if b.to - b.from < MIN_BAND and b.early == out[i - 1].early and b.level == out[i - 1].level then
            local prev = out[i - 1]
            prev.to = b.to
            if prev.zone == b.zone then
                merge(prev.targets, b.targets)
            else
                -- The folded stretch is gathered in the earlier band's zone, so it
                -- adds that zone's own targets, never the folded band's.
                for t = b.from, b.to - 1, STEP do
                    merge(prev.targets, zoneTargets(line, prev.zone, t, prev.early and level or nil))
                end
            end
            addAlt(out[i - 1], b.alt)
            table.remove(out, i)
        end
    end
    if out[1] then out[1].from = skill end
    return out
end

-- Items `targets` yield that the player's crafting guides still need:
-- { { item, have, need } }. `needs` and `have(item)` come from the caller.
function GG.Feeds(targets, needs, have)
    local seen, out = {}, {}
    for _, t in ipairs(targets) do
        for _, l in ipairs(CP.GatherData.loot[t.loot] or {}) do
            local item = l[1]
            if needs[item] and not seen[item] then
                seen[item] = true
                local got = have(item)
                if got < needs[item] then out[#out + 1] = { item = item, have = got, need = needs[item] } end
            end
        end
    end
    return out
end

-- The biggest spawn cluster of `targets` in `zone`, as { x, y, name }, or nil. A level
-- stretch's targets may be empty; its zone's own sources (`targets.where`) place the pin.
-- Targets the player can gather now come first; the rest only when none of them grows here.
function GG.Spot(zone, targets)
    local skills = G.Skills()
    local best, name, near, nearName
    for _, t in ipairs(#targets > 0 and targets or targets.where or {}) do
        local n = t.kind == "nodes" and CP.GatherData.nodes[t.entry]
        local line = t.kind == "mobs" and G.SKINNING or n and n[4]
        local reach = not line or (skills[line] or -1) >= (t.req or 0)
        for _, c in ipairs(G.Clusters(zone, t.kind, t.entry)) do
            if not best or c[3] > best[3] then best, name = c, t.name end
            if reach and (not near or c[3] > near[3]) then near, nearName = c, t.name end
        end
    end
    if near then best, name = near, nearName end
    return best and { x = best[1], y = best[2], name = name } or nil
end

-- Names of the targets that give skill best at `skill`, highest need first, up to `n`: the
-- orange and yellow ones, else the best one gatherable at `skill`, marked "(green)". Never a
-- target `skill` can't gather yet. A level stretch (`targets.level`) leads with "reach level N".
function GG.TargetNames(targets, skill, n)
    local list = {}
    for _, t in ipairs(targets) do list[#list + 1] = t end
    table.sort(list, function(a, b) return a.req > b.req end)
    local names, seen = {}, {}
    if targets.level then
        names[1] = ("reach level %d"):format(targets.level)
        if #list == 0 then return names end
    end
    local plain = #names
    for _, t in ipairs(list) do
        if #names >= n then break end
        if GG.Band(skill, t.req) >= 0.75 and not seen[t.name] then
            seen[t.name] = true
            names[#names + 1] = t.name
        end
    end
    if #names == plain then
        for _, t in ipairs(list) do
            if GG.Chance(skill, t.req) > 0 then
                names[#names + 1] = t.name .. " (green)"
                break
            end
        end
    end
    return names
end

-- Guide rows for Herbalism, Mining or Skinning. `s` = { line, skill, max, level,
-- zone (the player's), side (faction) }.
-- Rank rows: { gatherRank = rank, key, from }. Gather rows: { gather = band, key, from, to,
-- gathers, current }. A rank sits before the first stretch from its learn skill on.
local function gatherRows(s)
    local rows = {}
    local ranks = GG.Ranks(s.line, s.max)
    -- A rank can be learned from `at`, the skill its row shows. Ranks already learnable
    -- sit first.
    local function rankRow(r)
        rows[#rows + 1] = { gatherRank = r, key = "rank" .. r.skill, from = math.max(r.at, s.skill) }
    end
    local ri = 1
    while ranks[ri] and ranks[ri].at <= s.skill do
        rankRow(ranks[ri])
        ri = ri + 1
    end
    for _, b in ipairs(bands(s.line, s.skill, s.level, s.zone, s.side)) do
        -- A pending rank's learn skill inside the band cuts it, with the rank row between.
        local from = b.from
        while from < b.to do
            local r = ranks[ri]
            local to = r and r.at < b.to and r.at or b.to
            if r and r.at <= from then
                rankRow(r)
                ri = ri + 1
            else
                rows[#rows + 1] = {
                    gather = b, key = "g" .. from, from = from, to = to,
                    gathers = GG.GathersTo(from, to, b.targets), verb = VERB[s.line],
                    levelGate = b.level and { need = b.level, have = s.level,
                        text = ("This stretch needs level %d (you're %d)"):format(b.level, s.level) },
                }
                -- The band's "or" zone, from the skill its lowest target needs.
                local alt = b.alt
                if alt then
                    local lowest = 999
                    for _, t in ipairs(alt.targets) do lowest = math.min(lowest, t.req) end
                    local at = math.max(from, lowest)
                    local gathers = at < to and GG.GathersTo(at, to, alt.targets)
                    if gathers then
                        rows[#rows + 1] = {
                            gather = { zone = alt.zone, targets = alt.targets, zones = {} }, side = true,
                            key = "a" .. at, from = at, to = to, gathers = gathers, verb = VERB[s.line],
                        }
                    end
                end
                from = to
            end
        end
    end
    while ranks[ri] do
        rankRow(ranks[ri])
        ri = ri + 1
    end
    for _, row in ipairs(rows) do
        if row.gather then row.current = true break end
    end
    return rows
end

-- Guide rows for Fishing: rank rows (trainer, book, the Artisan trainer or quest by
-- faction) and one fishing row per rank stretch. `s` adds `zone`, `cook`, `needs` (the Cooking guide's), `have`, `mod` and `distance` for Fishing.Plan.
local function fishingRows(s)
    local F = CP.Fishing
    local rows = {}
    local caps = { 75, 150, 225, MAX_SKILL }
    local from = s.skill
    -- At the cap already: the rank that lifts it comes first.
    if s.skill >= s.max and s.max < MAX_SKILL then
        local r = F.RankFor(s.max, s.side)
        if r then rows[#rows + 1] = { fishRank = r, key = "rank" .. r.skill, from = s.skill, name = F.RankName(r) } end
    end
    -- A fishing stretch from `a` to `b`; the first one follows the player's plan.
    local function fish(a, b)
        if b <= a then return end
        local list = F.Candidates(a + (a == s.skill and s.mod or 0), a == s.skill and s.level or 99, s.side, a == s.skill and s.zone or nil)
        local pick = list[1]
        if a == s.skill then
            local plan = F.Plan({ skill = s.skill, mod = s.mod, maxRank = s.max, level = s.level, zone = s.zone, side = s.side,
                                  cook = s.cook, needs = s.needs, have = s.have, distance = s.distance })
            if plan.kind == "zone" then pick = { zone = plan.zone, land = plan.land, feeds = plan.feeds } end
        end
        -- Back to back with the stretch before, in the same water: one longer stretch.
        local last = rows[#rows]
        if pick and last and last.fish and last.to == a and last.fish.zone == pick.zone then
            last.to, last.gathers = b, F.CatchesTo(last.from, b)
            return
        end
        if pick then
            rows[#rows + 1] = {
                fish = { zone = pick.zone, land = pick.land, feeds = pick.feeds, zones = list },
                key = "f" .. a, from = a, to = b, gathers = F.CatchesTo(a, b), verb = "Fish",
            }
        end
    end
    for _, cap in ipairs(caps) do
        if cap > from then
            local rank = F.RankFor(cap, s.side)
            if rank and s.max <= cap then
                -- The rank sits where it becomes learnable (the Expert book at 125), so the
                -- player never stalls at the cap waiting for it.
                local at = math.min(math.max(rank.at or cap, from), cap)
                fish(from, at)
                rows[#rows + 1] = { fishRank = rank, key = "rank" .. cap, from = at, name = F.RankName(rank) }
                fish(at, cap)
            else
                fish(from, cap)
            end
            from = cap
        end
    end
    for _, row in ipairs(rows) do
        if row.fish then row.current = true break end
    end
    return rows
end

-- Rows for `s`, cached on what changes them. Fishing rows also depend on the bags
-- (Cooking feeds), so they're rebuilt each time.
local cache = {}
function GG.Rows(s)
    if s.line == G.FISHING then return fishingRows(s) end
    local key = table.concat({ s.line, s.skill, s.max, s.level or 0, s.zone or 0, s.side or "" }, ":")
    if not cache[key] then cache[key] = gatherRows(s) end
    return cache[key]
end

-- Rows for the player: their level, zone, faction, guide needs and bags.
function GG.PlayerRows(line, skill, max)
    local fishing = line == G.FISHING
    local info = fishing and CP.Professions.SkillLine(CP.Fishing.SKILL)
    local cooking = CP.charDB and CP.charDB.gatherNeeds and CP.charDB.gatherNeeds[G.COOKING]
    return GG.Rows({
        line = line, skill = skill, max = max, level = G.PlayerLevel(),
        zone = CP.Waypoint.PlayerZone(), side = UnitFactionGroup("player"),
        cook = CP.Settings.FishCook(), needs = fishing and (cooking or {}) or G.Needs(),
        mod = info and info.modifier or nil,
        distance = fishing and CP.GatherList and CP.GatherList.Distance or nil,
        have = function(item) return C_Item.GetItemCount(item, true) end,
    })
end

-- What to do next in a gathering guide: { train = rank name } when the skill sits at
-- its cap, else { zone = the current stretch's zone, level = the level it asks first, if
-- any }. Nil when the guide is empty.
function GG.Next(rows, skill, max)
    if skill >= max and max < MAX_SKILL then
        for _, row in ipairs(rows) do
            if row.gatherRank then return { train = row.gatherRank.name } end
            if row.fishRank then return { train = (row.name:gsub(" Fishing$", "")) } end
        end
    end
    for _, row in ipairs(rows) do
        if row.current then
            local band = row.gather or row.fish
            return { zone = band.zone, level = band.level }
        end
    end
end

-- Drops cached spawn counts and rows (GatherMate2 data or the zone data changed). The
-- lines count as unbuilt and the background job builds them again, so no caller rebuilds
-- every zone in one frame after an import brings coordinates the map never answered.
function GG.Reset()
    local dropped = job ~= nil
    job = nil
    generation = generation + 1
    wipe(placed)
    wipe(warmed)
    wipe(cache)
    wipe(sources)
    -- A dropped job never raises its signal, so the Guide tab waiting on it asks again.
    if dropped then CP:Emit(GG.WARM.signal) end
    GG.Warm()
end
