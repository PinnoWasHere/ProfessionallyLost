local _, CP = ...
if CP.stopped then return end

-- Hidden sharing between ProfLost players through addon messages. It carries the
-- addon's version, which creatures Forever lets be skinned, and gathering finds. Nothing
-- shows in chat. The one thing a player sees is a local notice of a newer version, once
-- per session, in Daylight UI's window (UI/News.lua).
--
-- Transports, all addon messages:
--   GUILD          hello at login
--   PARTY / RAID   hello on joining a group
--   YELL           hello every 15-30 min, out of combat and instances (reaches both factions)
--   WHISPER        replies to a hello, digests, requests and data, same faction only
--
-- Finds sync one zone at a time: the zone the player stands in. A hello carries its
-- digest; on arriving in a zone, ProfLost asks the peers it met lately for theirs.
-- The owner's collector (ProfLostDB.collect_all, /proflost collect on) asks each
-- peer for every zone instead and keeps all it gets, for baking into Data/Gather.lua.
--
-- Messages (prefix "ProfLost", fields split by single spaces):
--   H <proto> <version> <A|H|N> <share 0|1> [<key>:<count>:<hash> ...]   hello
--   Q <zone|*>                                                           ask for digests
--   D <key>:<count>:<hash> ...                                           digests
--   R <key>                                                              request
--   C <key> <hash> <seq> <total> <part>                                  chunk of a body
-- A key is "s" (skin reports) or a zone id. A hello's digest covers "s" and the
-- sender's zone. A body is one key's data as text, cut into parts of PART characters;
-- <hash> is its djb2 hash mod 2^32 in 8 hex digits.
--   skin body  "+<id>,<id>...-<id>,<id>..."   skinnable, then not skinnable
--   zone body  "n<node entry>:<spots>;m<creature id>:<spots>;..."
--              each spot is Finds.Pack(x, y) as 6 base-36 digits
-- Only the player's own learning and finds go out; peers' data is never passed on,
-- so two senders agreeing means two players saw it.

local Peers = {}
CP.Peers = Peers

-- Builds from before the rename send on another prefix, so the two never hear each other.
Peers.PREFIX = "ProfLost"
Peers.PROTO = 1

-- Forever's new zones, which Data/Gather.lua lacks; finds there count as real zones.
Peers.NEW_ZONES = { [2482] = true, [2521] = true, [2665] = true, [2548] = true, [2652] = true }

-- Sending.
Peers.GAP = 1.2             -- seconds between messages sent
Peers.QUEUE_MAX = 200       -- messages waiting to send
Peers.PART = 200            -- body characters per chunk; a chunk stays under 255 bytes
Peers.CHUNKS_MAX = 80       -- chunks per body
Peers.LOGIN_DELAY = 15      -- seconds after login before the guild hello
Peers.GROUP_DELAY = 3       -- seconds after joining a group before its hello
Peers.YELL_FIRST_MIN, Peers.YELL_FIRST_MAX = 60, 300
Peers.YELL_MIN, Peers.YELL_MAX = 900, 1800
Peers.YELL_RETRY = 120      -- seconds to wait when combat or an instance holds a yell
Peers.BODY_TTL = 60         -- seconds a built body is reused before a rebuild
Peers.REPLY_COOLDOWN = 1800 -- one whispered hello per peer this often
Peers.SERVE_COOLDOWN = 600  -- the same body to the same peer this often
Peers.NOTICE_DELAY = 5      -- seconds to wait for a higher version before the notice
Peers.ARRIVE_DELAY = 10     -- seconds in a new zone before asking peers for its digest
Peers.ASK_PEERS = 5         -- peers asked on arrival, the most recently met
Peers.MET_TTL = 1800        -- seconds a met peer stays worth asking
Peers.MET_MAX = 100         -- met peers remembered this session
Peers.DIGEST_MSGS = 20      -- digest messages in one answer to "Q *"

-- Receiving.
Peers.ASK_WAIT = 300        -- seconds a request stays open without a chunk
Peers.OPEN_MAX = 8          -- bodies being put together at once
Peers.RECV_PER_MIN = 150    -- messages taken per minute, all senders
Peers.SENDER_PER_MIN = 80   -- messages taken per minute from one sender
Peers.SPOTS_PER_SENDER = 2000 -- spots per zone from one sender (and the most we send)
Peers.SPOTS_PER_ZONE = 5000 -- peers' spots kept per zone
Peers.SENDERS_PER_ZONE = 40 -- senders kept per zone
Peers.SKIN_PER_SENDER = 1500 -- creature ids in one skin body
Peers.SKIN_MAX = 5000       -- creatures kept from peers' skin reports
Peers.SKIN_SENDERS = 5      -- "not skinnable" senders kept per creature
Peers.PEERS_MAX = 300       -- peers remembered
Peers.CONSENSUS = 2         -- senders needed to believe a spot or "not skinnable"
Peers.COLLECT_SPOTS_PER_ZONE = 20000 -- the collector's caps
Peers.COLLECT_SENDERS_PER_ZONE = 200

Peers.NOTICE = "Professionally Lost %s is available (you have %s)"
Peers.NOTICE_COLOR = { 1, 1, 0 }   -- the game's system message yellow

local SKINNING = 393
local THROTTLED = { [3] = true, [8] = true }   -- AddonMessageThrottle, ChannelThrottle
local BODY_CHARS = "^[%w+,;:%-]+$"

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function store(key)
    if not CP.db then return nil end
    CP.db[key] = CP.db[key] or {}
    return CP.db[key]
end

-- Sharing is always on (owner's rule). The one way out is the hidden `/proflost share off`,
-- a kill switch: nothing is sent or read at all. The "Newer version notice" setting silences
-- only the notice.
function Peers.Off() return CP.db ~= nil and CP.db.shareOff == true end
function Peers.Sharing() return CP.db ~= nil and not Peers.Off() end
function Peers.Collecting() return Peers.Sharing() and CP.db.collect_all == true end

-- A zone whose finds can be shared: an outdoor zone of the data, or a new one.
function Peers.ZoneOK(zone)
    if type(zone) ~= "number" then return false end
    if Peers.NEW_ZONES[zone] then return true end
    local z = CP.GatherData.zones[zone]
    return z ~= nil and z.inst == nil
end

-- The zone the player stands in, or nil.
function Peers.Zone()
    local ok, zone = pcall(CP.Waypoint.PlayerZone)
    return ok and zone or nil
end

-- Names --------------------------------------------------------------------------

local function full(name)
    if type(name) ~= "string" or name == "" or #name > 64 then return nil end
    if name:find("-", 1, true) then return name end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(realm) ~= "string" or realm == "" then
        realm = UnitFullName and select(2, UnitFullName("player"))
    end
    if type(realm) ~= "string" or realm == "" then return name end
    return name .. "-" .. realm
end

function Peers.Me() return full(UnitName("player")) end

local function side()
    local f = UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or "N"
end

-- Versions -----------------------------------------------------------------------

-- { major, minor, patch[, build] } from "0.2.1", or nil when it isn't a version.
function Peers.ParseVersion(v)
    if type(v) ~= "string" or #v > 20 or not v:match("^%d[%d%.]*%d$") and not v:match("^%d$") then return nil end
    if v:find("..", 1, true) then return nil end
    local out = {}
    for n in v:gmatch("%d+") do out[#out + 1] = tonumber(n) end
    if #out > 4 then return nil end
    return out
end

-- -1, 0 or 1 as version `a` is older, equal or newer than `b`.
function Peers.Compare(a, b)
    local pa, pb = Peers.ParseVersion(a) or {}, Peers.ParseVersion(b) or {}
    for i = 1, 4 do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

-- The addon's version without a pre-release tag ("0.2.0-beta" goes out as "0.2.0").
function Peers.Version()
    if not (C_AddOns and C_AddOns.GetAddOnMetadata) then return nil end
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, CP.name, "Version")
    v = ok and type(v) == "string" and v:match("^([%d%.]+)") or nil
    return Peers.ParseVersion(v) and v or nil
end

-- Session state --------------------------------------------------------------------

local S

-- Clears what this session remembers: the queue, requests, notices and timers.
function Peers.Forget()
    S = {
        queue = {}, timer = false, last = -math.huge, combat = false,
        asked = {}, open = {}, served = {}, replied = {}, whispered = {},
        met = {}, wants = {}, inflight = {}, queried = {}, collected = {}, arrival = 0,
        window = -1, total = 0, bySender = {},
        best = nil, noticed = false, noticeTimer = false,
        gen = (S and S.gen or 0) + 1, started = false, grouped = false,
        bodies = {},
        cache = {},
    }
end
Peers.Forget()

function Peers.Queue() return S.queue end

-- Sending --------------------------------------------------------------------------

local function inCombat() return S.combat or InCombatLockdown() == true end

local pump

local function schedule()
    if S.timer or #S.queue == 0 or inCombat() then return end
    local wait = S.last + Peers.GAP - GetTime()
    if wait < 0.05 then wait = 0 end
    S.timer = true
    local gen = S.gen
    C_Timer.After(wait, function() if gen == S.gen then pump() end end)
end

pump = function()
    S.timer = false
    if inCombat() then return end
    local m = table.remove(S.queue, 1)
    while m and m.data and not Peers.Sharing() do m = table.remove(S.queue, 1) end
    if not m then return end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, Peers.PREFIX, m.text, m.chat, m.target)
    S.last = GetTime()
    if ok and THROTTLED[res] and m.tries < 2 then
        m.tries = m.tries + 1
        table.insert(S.queue, 1, m)
    end
    if m.chat == "WHISPER" then S.whispered[m.target] = S.last end
    schedule()
end

-- Queues one message. `data` marks finds and skin traffic, dropped while sharing is off.
local function send(text, chat, target, data, front)
    if Peers.Off() then return false end
    if not text or #text > 255 or #S.queue >= Peers.QUEUE_MAX then return false end
    local m = { text = text, chat = chat, target = target, data = data, tries = 0 }
    if front then table.insert(S.queue, 1, m) else S.queue[#S.queue + 1] = m end
    schedule()
    return true
end

-- Bodies: the player's own data, built for sending -------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

function Peers.Base36(n)
    local out = {}
    for i = 6, 1, -1 do
        local d = n % 36
        out[i] = DIGITS:sub(d + 1, d + 1)
        n = (n - d) / 36
    end
    return table.concat(out)
end

function Peers.Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return ("%08x"):format(h)
end

local function skinnableMob(id)
    local mob = CP.GatherData.mobs[id]
    return mob ~= nil and mob[4] ~= nil and mob[4][SKINNING] ~= nil
end

local function skinBody()
    local yes, no = {}, {}
    for id, seen in pairs(CP.db and CP.db.skinSeen or {}) do
        if type(id) == "number" and skinnableMob(id) then
            if seen == true then yes[#yes + 1] = id
            elseif type(seen) == "number" and seen >= CP.Gather.NO_SKIN then no[#no + 1] = id end
        end
    end
    if #yes + #no == 0 then return nil end
    table.sort(yes)
    table.sort(no)
    while #yes + #no > Peers.SKIN_PER_SENDER do
        if #no > 0 then no[#no] = nil else yes[#yes] = nil end
    end
    return "+" .. table.concat(yes, ",") .. "-" .. table.concat(no, ","), #yes + #no
end

local function zoneBody(zone)
    local z = CP.db and CP.db.finds and CP.db.finds[zone]
    if not z then return nil end
    local recs, count = {}, 0
    local function add(tag, id, list)
        local spots = {}
        for _, p in ipairs(list) do
            if count >= Peers.SPOTS_PER_SENDER then break end
            spots[#spots + 1] = p
            count = count + 1
        end
        if #spots == 0 then return end
        table.sort(spots)
        for i, p in ipairs(spots) do spots[i] = Peers.Base36(p) end
        recs[#recs + 1] = { tag, id, tag .. id .. ":" .. table.concat(spots) }
    end
    local names = {}
    for name, list in pairs(z.n or {}) do
        local entry = CP.Gather.NodeEntry(name)
        if entry then names[#names + 1] = { entry, list } end
    end
    table.sort(names, function(a, b) return a[1] < b[1] end)
    for _, e in ipairs(names) do add("n", e[1], e[2]) end
    local mobs = {}
    for id, list in pairs(z.m or {}) do
        if type(id) == "number" and CP.GatherData.mobs[id] then mobs[#mobs + 1] = id end
    end
    table.sort(mobs)
    for _, id in ipairs(mobs) do add("m", id, z.m[id]) end
    if count == 0 then return nil end
    local parts = {}
    for i, r in ipairs(recs) do parts[i] = r[3] end
    return table.concat(parts, ";"), count
end

-- { body, count, hash } for key "s" or a zone id string, or nil when the player has
-- nothing there. Each key is rebuilt at most every BODY_TTL.
function Peers.Body(key, fresh)
    local now = GetTime()
    local c = S.bodies[key]
    if c and not fresh and now - c.t < Peers.BODY_TTL then return c.b or nil end
    local body, count
    if key == "s" then
        body, count = skinBody()
    elseif Peers.ZoneOK(tonumber(key)) then
        body, count = zoneBody(tonumber(key))
    end
    local b = body and { body = body, count = count, hash = Peers.Hash(body) } or false
    S.bodies[key] = { b = b, t = now }
    return b or nil
end

-- Zones holding the player's finds, as sorted key strings.
function Peers.OwnZones()
    local zones = {}
    for zone in pairs(CP.db and CP.db.finds or {}) do
        if Peers.ZoneOK(zone) then zones[#zones + 1] = zone end
    end
    table.sort(zones)
    for i, zone in ipairs(zones) do zones[i] = tostring(zone) end
    return zones
end

local function digest(key, b) return ("%s:%d:%s"):format(key, b.count, b.hash) end

-- Our hello: version, faction, sharing, and when sharing the digests of the skin
-- reports and the player's zone.
function Peers.Hello(fresh)
    local v = Peers.Version()
    if not v then return nil end
    local parts = { "H", Peers.PROTO, v, side(), Peers.Sharing() and 1 or 0 }
    if Peers.Sharing() then
        local zone = Peers.Zone()
        for _, key in ipairs({ "s", zone and Peers.ZoneOK(zone) and tostring(zone) or nil }) do
            local b = Peers.Body(key, fresh)
            if b then parts[#parts + 1] = digest(key, b) end
        end
    end
    return table.concat(parts, " ")
end

-- True when a hello of ours carries any digest.
local function hasData()
    if not Peers.Sharing() then return false end
    local zone = Peers.Zone()
    return Peers.Body("s") ~= nil or (zone ~= nil and Peers.ZoneOK(zone) and Peers.Body(tostring(zone)) ~= nil)
end

-- Sends our hello on `chat` ("GUILD", "PARTY", "RAID", "YELL"), ahead of other traffic.
function Peers.Broadcast(chat)
    return send(Peers.Hello(true), chat, nil, false, true)
end

-- Version notice -------------------------------------------------------------------

function Peers.SawVersion(v)
    local mine = Peers.Version()
    if not mine or Peers.Compare(v, mine) <= 0 then return end
    if CP.db and (not CP.db.newestSeen or Peers.Compare(v, CP.db.newestSeen) > 0) then CP.db.newestSeen = v end
    if not S.best or Peers.Compare(v, S.best) > 0 then S.best = v end
    if S.noticed or S.noticeTimer or not CP.db then return end
    S.noticeTimer = true
    local gen = S.gen
    C_Timer.After(Peers.NOTICE_DELAY, function()
        if gen ~= S.gen then return end
        S.noticeTimer = false
        if S.noticed or not CP.db then return end
        S.noticed = true
        if CP.Settings.Current("newerNotice") == false then return end
        -- Daylight UI's window (UI/News.lua), else one chat line.
        if CP.News and CP.News.Newer(S.best, mine) then return end
        local c = Peers.NOTICE_COLOR
        DEFAULT_CHAT_FRAME:AddMessage(Peers.NOTICE:format(S.best, mine), c[1], c[2], c[3])
    end)
end

-- Peers' data ----------------------------------------------------------------------

local function peer(sender)
    local peers = store("peers")
    if not peers then return { g = {} } end
    if not peers[sender] then
        local n, oldest, oldT = 0, nil, math.huge
        for name, p in pairs(peers) do
            n = n + 1
            if (p.t or 0) < oldT then oldest, oldT = name, p.t or 0 end
        end
        if n >= Peers.PEERS_MAX and oldest then peers[oldest] = nil end
        peers[sender] = { g = {} }
    end
    peers[sender].t = GetServerTime()
    peers[sender].g = peers[sender].g or {}
    return peers[sender]
end

local function skinChanged()
    if CP.Gather.SkinChanged then CP.Gather.SkinChanged() end
end

-- True, false (CONSENSUS senders say no and none yes) or nil (peers don't say).
function Peers.Skin(id)
    if not Peers.Sharing() then return nil end
    local e = CP.db and CP.db.peerSkin and CP.db.peerSkin[id]
    if not e then return nil end
    if e.y then return true end
    local n = 0
    for _ in pairs(e.n or {}) do n = n + 1 end
    if n >= Peers.CONSENSUS then return false end
    return nil
end

local function ids(list)
    local out = {}
    if list == "" then return out end
    for s in (list .. ","):gmatch("([^,]*),") do
        local id = s:match("^%d+$") and tonumber(s)
        if not id then return nil end
        out[#out + 1] = id
    end
    return out
end

local function applySkin(sender, body)
    local yesText, noText = body:match("^%+([%d,]*)%-([%d,]*)$")
    local yes, no = yesText and ids(yesText), noText and ids(noText)
    if not (yes and no) or #yes + #no > Peers.SKIN_PER_SENDER then return false end
    local ps = store("peerSkin")
    if not ps then return false end
    local size = 0
    for _ in pairs(ps) do size = size + 1 end
    local before, touched = {}, {}
    local function entry(id)
        if not skinnableMob(id) then return nil end
        if not ps[id] then
            if size >= Peers.SKIN_MAX then return nil end
            ps[id], size = {}, size + 1
        end
        if before[id] == nil then
            before[id] = CP.Gather.Skinnable(id)
            touched[#touched + 1] = id
        end
        return ps[id]
    end
    for _, id in ipairs(yes) do
        local e = entry(id)
        if e then e.y, e.n = true, nil end
    end
    for _, id in ipairs(no) do
        local e = entry(id)
        if e and not e.y then
            e.n = e.n or {}
            local n = 0
            for _ in pairs(e.n) do n = n + 1 end
            if e.n[sender] or n < Peers.SKIN_SENDERS then e.n[sender] = true end
        end
    end
    for _, id in ipairs(touched) do
        if CP.Gather.Skinnable(id) ~= before[id] then skinChanged() break end
    end
    return true
end

-- Drops senders, oldest first, until the zone is within its caps.
local function trim(zone, pz, keep)
    while true do
        local senders, spots, oldest, oldT = 0, 0, nil, math.huge
        for sender, d in pairs(pz) do
            senders, spots = senders + 1, spots + (d.c or 0)
            if sender ~= keep and (d.t or 0) < oldT then oldest, oldT = sender, d.t or 0 end
        end
        local maxSenders = Peers.Collecting() and Peers.COLLECT_SENDERS_PER_ZONE or Peers.SENDERS_PER_ZONE
        local maxSpots = Peers.Collecting() and Peers.COLLECT_SPOTS_PER_ZONE or Peers.SPOTS_PER_ZONE
        if not oldest or (senders <= maxSenders and spots <= maxSpots) then return end
        pz[oldest] = nil
        local p = CP.db.peers and CP.db.peers[oldest]
        if p and p.g then p.g[tostring(zone)] = nil end
    end
end

local function applyZone(sender, zone, body)
    local n, m, count = {}, {}, 0
    for rec in body:gmatch("[^;]+") do
        local tag, id, spots = rec:match("^([nm])(%d+):(%w+)$")
        if not tag or #spots % 6 ~= 0 then return false end
        id = tonumber(id)
        -- An entry this copy's data lacks (a newer ProfLost's) is skipped, not fatal.
        local list
        if tag == "n" then
            local node = CP.GatherData.nodes[id]
            if node then n[node[1]] = n[node[1]] or {}; list = n[node[1]] end
        elseif CP.GatherData.mobs[id] then
            m[id] = m[id] or {}
            list = m[id]
        end
        for i = 1, #spots, 6 do
            local p = tonumber(spots:sub(i, i + 5), 36)
            local xi, yi = p and math.floor(p / 1e4), p and p % 1e4
            if not p or xi < 1 or xi > 1e4 or yi < 1 or yi > 1e4 then return false end
            count = count + 1
            if count > Peers.SPOTS_PER_SENDER then return false end
            if list then list[#list + 1] = p end
        end
    end
    local pf = store("peerFinds")
    if not pf then return false end
    pf[zone] = pf[zone] or {}
    pf[zone][sender] = { t = GetServerTime(), c = count, n = n, m = m }
    trim(zone, pf[zone], sender)
    if CP.GatherMate then CP.GatherMate.Added(zone) end
    return true
end

local function apply(sender, key, body)
    if key == "s" then return applySkin(sender, body) end
    local zone = tonumber(key)
    if not Peers.ZoneOK(zone) then return false end
    return applyZone(sender, zone, body)
end

-- Corroborated spots ------------------------------------------------------------------

-- Peers' spots in `zone` that 2+ senders share, minus those the player already has.
-- { [key] = { { x, y, 1 }, ... } }, cached until Reset.
local function corroborated(zone, group)
    local ck = group .. zone
    if S.cache[ck] then return S.cache[ck] end
    local out = {}
    S.cache[ck] = out
    local pz = Peers.Sharing() and CP.db and CP.db.peerFinds and CP.db.peerFinds[zone]
    if not pz then return out end
    local same = CP.Finds.SAME
    local function cell(x, y) return math.floor(x / same) * 1000 + math.floor(y / same) end
    local function near(grid, x, y, other)
        local cx, cy = math.floor(x / same), math.floor(y / same)
        for dx = -1, 1 do
            for dy = -1, 1 do
                for _, s in ipairs(grid[(cx + dx) * 1000 + cy + dy] or {}) do
                    if (other == nil or s[3] ~= other) and math.abs(s[1] - x) < same and math.abs(s[2] - y) < same then
                        return true
                    end
                end
            end
        end
        return false
    end
    local keys = {}
    for _, d in pairs(pz) do
        for key in pairs(d[group] or {}) do keys[key] = true end
    end
    local own = CP.db.finds and CP.db.finds[zone] and CP.db.finds[zone][group] or {}
    for key in pairs(keys) do
        local grid, all = {}, {}
        for sender, d in pairs(pz) do
            for _, p in ipairs(d[group] and d[group][key] or {}) do
                local x, y = CP.Finds.Unpack(p)
                local s = { x, y, sender }
                local c = cell(x, y)
                grid[c] = grid[c] or {}
                table.insert(grid[c], s)
                all[#all + 1] = s
            end
        end
        local mine, kept = {}, {}
        for _, p in ipairs(own[key] or {}) do
            local x, y = CP.Finds.Unpack(p)
            local c = cell(x, y)
            mine[c] = mine[c] or {}
            table.insert(mine[c], { x, y })
        end
        for _, s in ipairs(all) do
            local x, y = s[1], s[2]
            if near(grid, x, y, s[3]) and not near(mine, x, y) and not near(kept, x, y) then
                local c = cell(x, y)
                kept[c] = kept[c] or {}
                table.insert(kept[c], { x, y })
                out[key] = out[key] or {}
                table.insert(out[key], { x, y, 1 })
            end
        end
    end
    return out
end

-- { [node name] = { { x, y, 1 }, ... } }: peers' corroborated herb and ore spots.
function Peers.Nodes(zone) return corroborated(zone, "n") end

-- { [creature id] = { { x, y, 1 }, ... } }: peers' corroborated skinning spots.
function Peers.Mobs(zone) return corroborated(zone, "m") end

-- Forget corroborated spots; GatherMate's settle calls it with its own reset.
function Peers.Reset() wipe(S.cache) end

-- Receiving -------------------------------------------------------------------------

local function admit(sender)
    local now = math.floor(GetTime() / 60)
    if now ~= S.window then S.window, S.total = now, 0; wipe(S.bySender) end
    if S.total >= Peers.RECV_PER_MIN then return false end
    S.total = S.total + 1
    local n = (S.bySender[sender] or 0) + 1
    S.bySender[sender] = n
    return n <= Peers.SENDER_PER_MIN
end

local function capOf(key)
    return key == "s" and Peers.SKIN_PER_SENDER or Peers.SPOTS_PER_SENDER
end

local function keyOK(key)
    return key == "s" or (key:match("^%d+$") ~= nil and Peers.ZoneOK(tonumber(key)))
end

-- Keys worth asking for: skins, the player's zone, or any zone while collecting.
local function wanted(key)
    if key == "s" then return true end
    return Peers.Collecting() or tonumber(key) == Peers.Zone()
end

-- Asks `sender` for its next wanted body, one at a time. A request without a chunk
-- for ASK_WAIT seconds gives way to the next.
local askNext
askNext = function(sender)
    local now = GetTime()
    local key = S.inflight[sender]
    if key then
        local id = sender .. " " .. key
        local idle = now - (S.asked[id] or -math.huge)
        if idle < Peers.ASK_WAIT then
            local gen = S.gen
            C_Timer.After(Peers.ASK_WAIT - idle + 1, function() if gen == S.gen then askNext(sender) end end)
            return
        end
        S.asked[id], S.open[id] = nil, nil
    end
    S.inflight[sender] = nil
    local list = S.wants[sender]
    key = list and table.remove(list, 1)
    if not key then
        S.wants[sender] = nil
        return
    end
    S.inflight[sender] = key
    S.asked[sender .. " " .. key] = now
    send("R " .. key, "WHISPER", sender, true)
    local gen = S.gen
    C_Timer.After(Peers.ASK_WAIT + 1, function() if gen == S.gen then askNext(sender) end end)
end

-- Takes digest entries ("key:count:hash") from `sender` and queues the bodies we lack.
local function digests(sender, entries, from)
    local p = peer(sender)
    for i = from, #entries do
        local key, count, hash = entries[i]:match("^(%w+):(%d+):(%x+)$")
        count = tonumber(count)
        if key and keyOK(key) and wanted(key) and #hash == 8 and count > 0 and count <= capOf(key)
            and p.g[key] ~= hash and S.inflight[sender] ~= key then
            local list = S.wants[sender] or {}
            S.wants[sender] = list
            local dup = false
            for _, k in ipairs(list) do dup = dup or k == key end
            if not dup then list[#list + 1] = key end
        end
    end
    if S.wants[sender] then askNext(sender) end
end

local function meet(sender, now)
    S.met[sender] = now
    local n, oldest, oldT = 0, nil, math.huge
    for name, t in pairs(S.met) do
        n = n + 1
        if t < oldT then oldest, oldT = name, t end
    end
    if n > Peers.MET_MAX then S.met[oldest] = nil end
end


local function hello(sender, text, channel)
    local f = {}
    for w in text:gmatch("%S+") do
        f[#f + 1] = w
        if #f > 12 then return end
    end
    local proto, ver, fac, share = tonumber(f[2]), f[3], f[4], f[5]
    if not proto or not Peers.ParseVersion(ver) then return end
    Peers.SawVersion(ver)
    -- Whispers don't cross factions, so the rest needs the same side.
    if proto ~= Peers.PROTO or fac ~= side() then return end
    peer(sender)
    local now = GetTime()
    if channel ~= "WHISPER" and now - (S.replied[sender] or -math.huge) >= Peers.REPLY_COOLDOWN then
        local mine = Peers.Version()
        local useful = mine and Peers.Compare(ver, mine) < 0 or (share == "1" and hasData())
        if useful then
            S.replied[sender] = now
            send(Peers.Hello(), "WHISPER", sender)
        end
    end
    if not Peers.Sharing() or share ~= "1" then return end
    meet(sender, now)
    digests(sender, f, 6)
    if Peers.Collecting() and now - (S.collected[sender] or -math.huge) >= Peers.REPLY_COOLDOWN then
        S.collected[sender], S.queried[sender] = now, now
        send("Q *", "WHISPER", sender, true)
    end
end

-- "Q <zone>" or "Q *": our digests, by whisper.
local function query(sender, text)
    local what = text:match("^Q (%S+)$")
    if not what or (what ~= "*" and not keyOK(what)) or what == "s" then return end
    local id = "Q " .. sender .. " " .. what
    local now = GetTime()
    if now - (S.served[id] or -math.huge) < Peers.SERVE_COOLDOWN then return end
    S.served[id] = now
    local keys = what == "*" and Peers.OwnZones() or { what }
    local line, msgs = "D", 0
    for _, key in ipairs(keys) do
        local b = Peers.Body(key)
        if b then
            local entry = digest(key, b)
            if #line + 1 + #entry > 255 then
                send(line, "WHISPER", sender, true)
                msgs = msgs + 1
                if msgs >= Peers.DIGEST_MSGS then return end
                line = "D"
            end
            line = line .. " " .. entry
        end
    end
    if line ~= "D" then send(line, "WHISPER", sender, true) end
end

-- "D ...": digests we asked for with Q.
local function digestAnswer(sender, text)
    if GetTime() - (S.queried[sender] or -math.huge) >= Peers.ASK_WAIT then return end
    local f = {}
    for w in text:gmatch("%S+") do
        f[#f + 1] = w
        if #f > 40 then return end
    end
    digests(sender, f, 2)
end

local function request(sender, text)
    local key = text:match("^R (%w+)$")
    if not (key and keyOK(key)) then return end
    local id = sender .. " " .. key
    local now = GetTime()
    if now - (S.served[id] or -math.huge) < Peers.SERVE_COOLDOWN then return end
    local b = Peers.Body(key)
    if not b then return end
    local total = math.ceil(#b.body / Peers.PART)
    if total > Peers.CHUNKS_MAX or #S.queue + total > Peers.QUEUE_MAX then return end
    S.served[id] = now
    for i = 1, total do
        local part = b.body:sub((i - 1) * Peers.PART + 1, i * Peers.PART)
        send(("C %s %s %d %d %s"):format(key, b.hash, i, total, part), "WHISPER", sender, true)
    end
end

local function chunk(sender, text)
    local key, hash, seq, total, part = text:match("^C (%w+) (%x+) (%d+) (%d+) (%S+)$")
    seq, total = tonumber(seq), tonumber(total)
    if not (key and keyOK(key) and #hash == 8) or seq < 1 or seq > total or total > Peers.CHUNKS_MAX
        or #part > Peers.PART or not part:match(BODY_CHARS) then return end
    local id = sender .. " " .. key
    local now = GetTime()
    if now - (S.asked[id] or -math.huge) >= Peers.ASK_WAIT then return end   -- not asked for
    S.asked[id] = now
    local o = S.open[id]
    if not o or o.hash ~= hash or o.total ~= total then
        local n = 0
        for k, v in pairs(S.open) do
            if now - v.t >= Peers.ASK_WAIT then S.open[k] = nil else n = n + 1 end
        end
        if not o and n >= Peers.OPEN_MAX then return end
        o = { hash = hash, total = total, parts = {}, n = 0 }
        S.open[id] = o
    end
    o.t = now
    if not o.parts[seq] then o.parts[seq], o.n = part, o.n + 1 end
    if o.n < o.total then return end
    S.open[id], S.asked[id] = nil, nil
    local body = table.concat(o.parts)
    if Peers.Hash(body) == hash and apply(sender, key, body) then peer(sender).g[key] = hash end
    if S.inflight[sender] == key then
        S.inflight[sender] = nil
        askNext(sender)
    end
end

function Peers.Received(prefix, text, channel, sender)
    if Peers.Off() then return end
    if secret(prefix) or prefix ~= Peers.PREFIX or secret(text) or secret(sender) then return end
    if type(text) ~= "string" or #text > 255 then return end
    sender = full(sender)
    if not sender or sender == Peers.Me() or not admit(sender) then return end
    local kind = text:sub(1, 2)
    if kind == "H " then
        hello(sender, text, channel)
    elseif not Peers.Sharing() or channel ~= "WHISPER" then
        return
    elseif kind == "R " then
        request(sender, text)
    elseif kind == "Q " then
        query(sender, text)
    elseif kind == "D " then
        digestAnswer(sender, text)
    elseif kind == "C " then
        chunk(sender, text)
    end
end

-- Timing ---------------------------------------------------------------------------

function Peers.Yell(gen)
    gen = gen or S.gen
    if gen ~= S.gen then return end
    local inside = IsInInstance()
    local wait
    if inCombat() or inside then
        wait = Peers.YELL_RETRY
    else
        Peers.Broadcast("YELL")
        wait = math.random(Peers.YELL_MIN, Peers.YELL_MAX)
    end
    C_Timer.After(wait, function() Peers.Yell(gen) end)
end

local function groupChat() return IsInRaid() and "RAID" or "PARTY" end

-- The session's start: guild and group hellos, then the yell timer.
function Peers.Start()
    if S.started then return end
    S.started = true
    local gen = S.gen
    if CP.db and CP.db.newestSeen and Peers.Compare(CP.db.newestSeen, Peers.Version()) <= 0 then
        CP.db.newestSeen = nil
    end
    S.grouped = IsInGroup() == true
    C_Timer.After(Peers.LOGIN_DELAY, function()
        if gen ~= S.gen then return end
        if IsInGuild() then Peers.Broadcast("GUILD") end
        if IsInGroup() then Peers.Broadcast(groupChat()) end
    end)
    C_Timer.After(math.random(Peers.YELL_FIRST_MIN, Peers.YELL_FIRST_MAX), function() Peers.Yell(gen) end)
end

function Peers.GroupChanged()
    local now = IsInGroup() == true
    if now and not S.grouped then
        local gen = S.gen
        C_Timer.After(Peers.GROUP_DELAY, function()
            if gen == S.gen and IsInGroup() then Peers.Broadcast(groupChat()) end
        end)
    end
    S.grouped = now
end

-- On arrival in a zone, the peers met lately are asked for their digest of it.
function Peers.Arrived()
    S.arrival = S.arrival + 1
    local token, gen = S.arrival, S.gen
    local zone = Peers.Zone()
    C_Timer.After(Peers.ARRIVE_DELAY, function()
        if gen ~= S.gen or token ~= S.arrival or not Peers.Sharing() then return end
        if not zone or zone ~= Peers.Zone() or not Peers.ZoneOK(zone) then return end
        local now, list = GetTime(), {}
        for name, t in pairs(S.met) do
            if now - t < Peers.MET_TTL then list[#list + 1] = { name, t } end
        end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for i = 1, math.min(#list, Peers.ASK_PEERS) do
            S.queried[list[i][1]] = now
            send("Q " .. zone, "WHISPER", list[i][1], true)
        end
    end)
end

function Peers.CombatChanged(on)
    S.combat = on
    if not on then schedule() end
end

-- A whisper to a player who just went offline prints the client's "No player named ..."
-- line (ERR_CHAT_PLAYER_NOT_FOUND_S). That line is hidden for names ProfLost whispered in
-- the last WHISPER_HIDE seconds. The line is built from the client's own string with
-- format and compared whole, so word order and punctuation follow the language.
Peers.WHISPER_HIDE = 30

-- The line the client prints for `name`, lowercased, or nil without the global string.
function Peers.NotFoundLine(name)
    local fmt = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
    if type(fmt) ~= "string" or fmt == "" or type(name) ~= "string" then return nil end
    local ok, line = pcall(string.format, fmt, name)
    return ok and type(line) == "string" and line:lower() or nil
end

function Peers.HideSystem(_, _, msg)
    if type(msg) ~= "string" or secret(msg) then return false end
    local now = GetTime()
    local low
    for name, t in pairs(S.whispered) do
        if now - t >= Peers.WHISPER_HIDE then
            S.whispered[name] = nil
        else
            low = low or msg:lower()
            if low == Peers.NotFoundLine(name) or low == Peers.NotFoundLine(name:match("^[^-]+")) then
                return true
            end
        end
    end
    return false
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(Peers.PREFIX)
end
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", Peers.HideSystem)
end

CP:On("CHAT_MSG_ADDON", function(_, ...) Peers.Received(...) end)
CP:On("PLAYER_ENTERING_WORLD", function() Peers.Start() end)
CP:On("GROUP_ROSTER_UPDATE", function() Peers.GroupChanged() end)
CP:On("ZONE_CHANGED_NEW_AREA", function() Peers.Arrived() end)
CP:On("PLAYER_REGEN_DISABLED", function() Peers.CombatChanged(true) end)
CP:On("PLAYER_REGEN_ENABLED", function() Peers.CombatChanged(false) end)
