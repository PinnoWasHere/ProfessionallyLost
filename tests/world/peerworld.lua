-- peerworld: other ProfLost players and the hidden addon-message network between them.
--
-- Modelled on what the game does:
--   * [docs] C_ChatInfo.SendAddonMessage(prefix, text, chatType, target) reaches the players
--     on that chat type; each gets CHAT_MSG_ADDON(prefix, text, chatType, sender) with
--     the sender as "Name-Realm". GUILD, PARTY, RAID and YELL come back to the sender too.
--   * [docs] A message over 255 bytes is refused (InvalidMessage, 2); PARTY or RAID outside a
--     group gives NotInGroup (5); GUILD outside a guild gives GeneralError (9).
--   * [docs] Combat fires PLAYER_REGEN_DISABLED / ENABLED and InCombatLockdown follows it.
--     Joining or changing a group fires GROUP_ROSTER_UPDATE.
-- Guesses:
--   * [guess] Every message arrives LATENCY seconds later, in order; none is lost.
--   * [guess] YELL reaches peers of both factions; WHISPER only peers of the player's faction.
--   * [guess] A peer stands in its `zone` (default: its lowest zone with finds); its hello
--     carries the digests of its skin reports and that zone.
--   * [guess] A peer runs ProfLost's protocol 1 as Engine/Peers.lua's header describes it. Its
--     side is written here from that description, not from Peers.lua's code.
--
--   PeerWorld.begin({ version = "0.2.0", side = "Alliance", guild = true, group = "party", instance = false })
--   local ann = PeerWorld.Peer("Ann", { version = "0.2.1", faction = "A", share = true,
--       skin = { yes = { 113 }, no = { 118 } },
--       finds = { [2548] = { n = { [1618] = { { 0.3, 0.4 } } }, m = { [113] = { { 0.2, 0.2 } } } } },
--       bodies = { ["2548"] = "raw body" }, hash = { ["2548"] = "00000000" }, count = { ["2548"] = 1 } })
--   ann:Hello("YELL") / ann:Say(text, chat) / PeerWorld.Combat(on) / PeerWorld.Group(kind)
--   PeerWorld.Move(zone): the player arrives in `zone` (begin's `zone` sets the first)
--   PeerWorld.sent: every addon message ProfLost sent; PeerWorld.chat: chat messages it
--   sent (always none); PeerWorld.lines: lines added to the chat frame.

PeerWorld = {}

local CP = ProfLost
local S
local GEN = 0   -- one per scene, so a past scene's deliveries never land

PeerWorld.PREFIX = "ProfLost"
PeerWorld.LATENCY = 0.1
PeerWorld.PART = 200
PeerWorld.REALM = "Testrealm"

local function me() return UnitName("player") .. "-" .. GetNormalizedRealmName() end

local function mySide()
    local f = UnitFactionGroup("player")
    return f == "Horde" and "H" or "A"
end

-- Delivers `text` to ProfLost as from `sender`, `delay` seconds from now.
local function deliver(text, chat, sender, delay)
    local gen = S.gen
    C_Timer.After(delay or PeerWorld.LATENCY, function()
        if S and S.gen == gen then
            T.fire("CHAT_MSG_ADDON", PeerWorld.PREFIX, text, chat, sender, sender, 0, 0, "", 0)
        end
    end)
end

-- The protocol, peer side --------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

function PeerWorld.B36(n)
    local s = ""
    for _ = 1, 6 do
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = (n - d) / 36
    end
    return s
end

function PeerWorld.Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return ("%08x"):format(h)
end

function PeerWorld.Pack(x, y)
    return math.floor(x * 1e4 + 0.5) * 1e4 + math.floor(y * 1e4 + 0.5)
end

local function sortedKeys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- { order, [key] = { body, count, hash } } for a peer.
local function bodiesOf(p)
    local out = { order = {} }
    local function put(key, body, count)
        out[key] = { body = body, count = count, hash = PeerWorld.Hash(body) }
        out.order[#out.order + 1] = key
    end
    if p.skin then
        local yes, no = {}, {}
        for _, id in ipairs(p.skin.yes or {}) do yes[#yes + 1] = id end
        for _, id in ipairs(p.skin.no or {}) do no[#no + 1] = id end
        table.sort(yes) table.sort(no)
        put("s", "+" .. table.concat(yes, ",") .. "-" .. table.concat(no, ","), #yes + #no)
    end
    for _, zone in ipairs(sortedKeys(p.finds)) do
        local z, recs, count = p.finds[zone], {}, 0
        for _, tag in ipairs({ "n", "m" }) do
            for _, id in ipairs(sortedKeys(z[tag])) do
                local packed = {}
                for _, s in ipairs(z[tag][id]) do packed[#packed + 1] = PeerWorld.Pack(s[1], s[2]) end
                table.sort(packed)
                for i, v in ipairs(packed) do packed[i] = PeerWorld.B36(v) end
                count = count + #packed
                recs[#recs + 1] = tag .. id .. ":" .. table.concat(packed)
            end
        end
        put(tostring(zone), table.concat(recs, ";"), count)
    end
    for _, key in ipairs(World.keys(p.bodies)) do
        local body = p.bodies[key]
        if not out[key] then out.order[#out.order + 1] = key end
        out[key] = { body = body, count = 1, hash = PeerWorld.Hash(body) }
    end
    for key, h in pairs(p.hash or {}) do out[key].hash = h end
    for key, n in pairs(p.count or {}) do out[key].count = n end
    return out
end

local Peer = {}
Peer.__index = Peer

local function digest(key, b) return ("%s:%d:%s"):format(key, b.count, b.hash) end

function Peer:HelloText()
    local parts = { "H", 1, self.version, self.faction, self.share and 1 or 0 }
    if self.share then
        local b = bodiesOf(self)
        for _, key in ipairs({ "s", self.zone and tostring(self.zone) }) do
            if b[key] then parts[#parts + 1] = digest(key, b[key]) end
        end
    end
    return table.concat(parts, " ")
end

-- The peer's hello on `chat`.
function Peer:Hello(chat)
    deliver(self:HelloText(), chat or "YELL", self.name)
end

-- Any text from the peer.
function Peer:Say(text, chat)
    deliver(text, chat or "WHISPER", self.name)
end

-- What the peer does with a message from ProfLost.
function Peer:Hear(text, chat)
    self.heard[#self.heard + 1] = { text = text, chat = chat }
    local what = text:match("^Q (%S+)$")
    if what and chat == "WHISPER" and self.share then
        local b = bodiesOf(self)
        local entries = {}
        for _, key in ipairs(b.order) do
            if key ~= "s" and (what == "*" or what == key) then entries[#entries + 1] = digest(key, b[key]) end
        end
        if #entries > 0 then deliver("D " .. table.concat(entries, " "), "WHISPER", self.name) end
        return
    end
    local key = text:match("^R (%w+)$")
    if not (key and chat == "WHISPER" and self.share) then return end
    local b = bodiesOf(self)[key]
    if not b then return end
    local total = math.ceil(#b.body / PeerWorld.PART)
    for i = 1, total do
        local part = b.body:sub((i - 1) * PeerWorld.PART + 1, i * PeerWorld.PART)
        deliver(("C %s %s %d %d %s"):format(key, b.hash, i, total, part), "WHISPER", self.name,
            PeerWorld.LATENCY * (i + 1))
    end
end

-- A peer on the network. `name` gets the realm when it has none.
function PeerWorld.Peer(name, spec)
    spec = spec or {}
    local full = name:find("-", 1, true) and name or (name .. "-" .. PeerWorld.REALM)
    local p = setmetatable({
        name = full, version = spec.version or "0.2.0", faction = spec.faction or "A",
        share = spec.share ~= false, skin = spec.skin, finds = spec.finds,
        bodies = spec.bodies, hash = spec.hash, count = spec.count,
        zone = spec.zone or sortedKeys(spec.finds)[1] or tonumber(next(spec.bodies or {}) or nil),
        hears = spec.hears or { GUILD = true, YELL = true, PARTY = true, RAID = true },
        heard = {},
    }, Peer)
    S.peers[#S.peers + 1] = p
    return p
end

-- The network ---------------------------------------------------------------------

local function reaches(p, chat, target)
    if chat == "WHISPER" then return p.name == target and p.faction == mySide() end
    return p.hears[chat] == true
end

local KEEP = { "peers", "peerSkin", "peerFinds", "finds", "skinSeen", "newestSeen",
               "collect_all" }

function PeerWorld.begin(spec)
    spec = spec or {}
    GEN = GEN + 1
    S = { gen = GEN, guild = spec.guild == true, group = spec.group, combat = false,
          zone = spec.zone, instance = spec.instance == true, version = spec.version or "0.2.0", side = spec.side or "Alliance",
          peers = {}, results = {} }
    PeerWorld.sent, PeerWorld.chat, PeerWorld.lines = {}, {}, {}
    local saved = {}
    for _, k in ipairs(KEEP) do saved[k] = CP.db[k] end
    for _, k in ipairs(KEEP) do CP.db[k] = nil end
    CP.Peers.Forget()
    CP.GatherMate.Reset()

    -- [docs] SendAddonMessage refuses over 255 bytes, PARTY or RAID outside a group, and GUILD outside a guild.
    World.patch("C_ChatInfo.SendAddonMessage", function(prefix, text, chat, target)
        PeerWorld.sent[#PeerWorld.sent + 1] = { prefix = prefix, text = text, chat = chat, target = target }
        local forced = table.remove(S.results, 1)
        if forced then return forced end
        if #text > 255 then return 2 end
        if (chat == "PARTY" or chat == "RAID") and not S.group then return 5 end
        if chat == "GUILD" and not S.guild then return 9 end
        if chat ~= "WHISPER" then deliver(text, chat, me()) end
        for _, p in ipairs(S.peers) do
            if reaches(p, chat, target) then p:Hear(text, chat) end
        end
        return 0
    end)

    -- [guess] ProfLost sends no chat; the world records any it tries.
    World.patch("C_ChatInfo.SendChatMessage", function(...)
        PeerWorld.chat[#PeerWorld.chat + 1] = { ... }
    end)
    World.patch("SendChatMessage", function(...)
        PeerWorld.chat[#PeerWorld.chat + 1] = { ... }
    end)
    -- Set, not patched: the harness stub takes only an addon index, the game a name too.
    local metadata = C_AddOns.GetAddOnMetadata
    World.set(C_AddOns, "GetAddOnMetadata", function(addon, field)
        if addon == CP.name and field == "Version" then return S.version end
        return metadata(addon, field)
    end)

    -- [guess] The player's faction is the scene's.
    World.patch("UnitFactionGroup", function(unit)
        if unit == "player" then return S.side, S.side end
        return World.PASS
    end)

    -- [docs] The guild, group, raid, combat and instance calls answer from the scene's state.
    World.patch("IsInGuild", function() return S.guild end)
    World.patch("IsInGroup", function() return S.group ~= nil end)
    World.patch("IsInRaid", function() return S.group == "raid" end)
    World.patch("InCombatLockdown", function() return S.combat end)
    World.patch("IsInInstance", function()
        if S.instance then return true, "party" end
        return false, "none"
    end)
    World.set(CP.Waypoint, "PlayerZone", function() return S.zone end)

    -- [guess] The server clock runs from a fixed start with the harness clock.
    World.patch("GetServerTime", function() return 1800000000 + math.floor(T.clock()) end)
    World.set(DEFAULT_CHAT_FRAME, "AddMessage", function(_, text, r, g, b)
        PeerWorld.lines[#PeerWorld.lines + 1] = { text = text, r = r, g = g, b = b }
    end)
    World.onEnd(function()
        for _, k in ipairs(KEEP) do CP.db[k] = saved[k] end
        CP.Peers.Forget()
        CP.GatherMate.Reset()
        S.gen = nil
    end)
end

function PeerWorld.Combat(on)
    S.combat = on
    T.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

-- "party", "raid" or nil (no group).
function PeerWorld.Group(kind)
    S.group = kind
    T.fire("GROUP_ROSTER_UPDATE")
end

function PeerWorld.Instance(on) S.instance = on end

function PeerWorld.Move(zone)
    S.zone = zone
    T.fire("ZONE_CHANGED_NEW_AREA")
end

-- The next sends get these results instead (3 = AddonMessageThrottle).
function PeerWorld.Results(list)
    for _, r in ipairs(list) do S.results[#S.results + 1] = r end
end

-- What ProfLost sent on `chat` (any when nil), optionally only to `target`.
function PeerWorld.Sent(chat, target)
    local out = {}
    for _, m in ipairs(PeerWorld.sent) do
        if (chat == nil or m.chat == chat) and (target == nil or m.target == target) then out[#out + 1] = m end
    end
    return out
end
