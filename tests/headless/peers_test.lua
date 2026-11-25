-- Hidden sharing between ProfLost players (Engine/Peers.lua), on peerworld's network.

local CP = ProfLost
local P, G, GM = CP.Peers, CP.Gather, CP.GatherMate
local RIVERGLADES = 2548
local PEACEBLOOM = 1618
local BOAR, PROWLER, LONGSNOUT, WOLF = 113, 118, 119, 1131

-- PeerWorld.begin, plus a wait at the test's end for the finds it took in. They sit GatherMate.SETTLE
-- seconds before the zones reset and the panel redraws, and left over they would fire in a later test.
local function begin(spec)
    World.onEnd(function()
        if GM.Pending() then T.advance(GM.SETTLE + 1) end
    end)
    PeerWorld.begin(spec)
end

local function texts(list)
    local out = {}
    for i, m in ipairs(list) do out[i] = m.text end
    return out
end

local function has(list, pattern)
    for _, m in ipairs(list) do
        if m.text:find(pattern) then return true end
    end
    return false
end

-- The requests ProfLost whispered to `name`.
local function asks(name)
    local out = {}
    for _, m in ipairs(PeerWorld.Sent("WHISPER", name)) do
        if m.text:sub(1, 2) == "R " then out[#out + 1] = m.text end
    end
    return out
end

local function near(list, x, y)
    for _, c in ipairs(list or {}) do
        if math.abs(c[1] - x) < 0.002 and math.abs(c[2] - y) < 0.002 then return true end
    end
    return false
end

T.test("a newer version prints one local line a session, for the highest seen", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    local prints = #T.prints()
    PeerWorld.Peer("Ann", { version = "0.2.1" }):Hello("YELL")
    PeerWorld.Peer("Bob", { version = "0.3.0" }):Hello("GUILD")
    T.advance(1)
    T.eq(#PeerWorld.lines, 0, "it waits a moment for a higher one")
    T.advance(P.NOTICE_DELAY)
    T.eq(#PeerWorld.lines, 1)
    T.eq(PeerWorld.lines[1].text, "Professionally Lost 0.3.0 is available (you have 0.2.0)")
    T.eq({ PeerWorld.lines[1].r, PeerWorld.lines[1].g, PeerWorld.lines[1].b }, { 1, 1, 0 }, "system yellow")
    T.eq(CP.db.newestSeen, "0.3.0")
    PeerWorld.Peer("Cy", { version = "0.10.0" }):Hello("YELL")
    T.advance(P.NOTICE_DELAY + 1)
    T.eq(#PeerWorld.lines, 1, "once a session")
    T.eq(CP.db.newestSeen, "0.10.0", "the highest is still remembered (0.10 is newer than 0.3)")
    local details = table.concat(CP.BugReport.Details(), "\n")
    T.ok(details:find("Newest Professionally Lost seen from other players: 0.10.0", 1, true), "the bug report names it")
    for i = prints + 1, #T.prints() do
        T.ok(not tostring(T.prints()[i]):find("available", 1, true), "the notice isn't printed")
    end
    T.eq(#PeerWorld.chat, 0, "nothing sent as chat")
    for _, m in ipairs(PeerWorld.sent) do
        T.eq(m.prefix, "ProfLost")
        T.ok(m.chat ~= "SAY" and m.chat ~= "CHANNEL", "no chat channels")
    end
end)

T.test("older or equal versions, malformed ones and our own echo say nothing", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    PeerWorld.Peer("Ann", { version = "0.2.0" }):Hello("YELL")
    PeerWorld.Peer("Bob", { version = "0.1.99" }):Hello("YELL")
    PeerWorld.Peer("Cy"):Say("H 1 9.9.9.9.9 A 0", "YELL")
    PeerWorld.Peer("Dee"):Say("H 1 1.x A 0", "YELL")
    PeerWorld.Peer("Eve"):Say("H 1 " .. ("9"):rep(30) .. " A 0", "YELL")
    T.fire("CHAT_MSG_ADDON", "ProfLost", "H 1 5.0.0 A 0", "YELL", "Testchar-Testrealm")
    T.fire("CHAT_MSG_ADDON", "OtherAddon", "H 1 5.0.0 A 0", "YELL", "Fay-Testrealm")
    T.advance(P.NOTICE_DELAY + 2)
    T.eq(#PeerWorld.lines, 0)
    T.eq(CP.db.newestSeen, nil)
end)

T.test("hellos go out on the guild at login, the group on joining, and as a yell; never in combat or instances", function()
    World.set(P, "YELL_FIRST_MIN", 30) World.set(P, "YELL_FIRST_MAX", 30)
    World.set(P, "YELL_MIN", 60) World.set(P, "YELL_MAX", 60)
    World.set(P, "YELL_RETRY", 10)
    begin({ version = "0.2.0", zone = RIVERGLADES, guild = true })
    P.Start()
    T.advance(P.LOGIN_DELAY + 1)
    local guild = PeerWorld.Sent("GUILD")
    T.eq(#guild, 1)
    T.ok(guild[1].text:find("^H 1 0%.2%.0 A 1"), guild[1].text)
    PeerWorld.Group("party")
    T.advance(P.GROUP_DELAY + 1)
    T.eq(#PeerWorld.Sent("PARTY"), 1, "joining a group")
    PeerWorld.Group("raid")
    T.advance(P.GROUP_DELAY + 1)
    T.eq(#PeerWorld.Sent("RAID"), 0, "already grouped: no new hello")
    T.advance(30 - P.LOGIN_DELAY - 2 * (P.GROUP_DELAY + 1))
    T.eq(#PeerWorld.Sent("YELL"), 1, "the first yell")
    PeerWorld.Combat(true)
    T.advance(61)
    T.eq(#PeerWorld.Sent("YELL"), 1, "no yell in combat")
    PeerWorld.Combat(false)
    T.advance(11)
    T.eq(#PeerWorld.Sent("YELL"), 2, "the yell once combat ends")
    PeerWorld.Instance(true)
    T.advance(61)
    T.eq(#PeerWorld.Sent("YELL"), 2, "no yell in an instance")
    PeerWorld.Instance(false)
    T.advance(11)
    T.eq(#PeerWorld.Sent("YELL"), 3)
    T.eq(#PeerWorld.chat, 0, "nothing sent as chat")
    T.eq(#PeerWorld.lines, 0, "nothing in the chat frame")
end)

T.test("an older peer gets our hello by whisper, once; other factions never get a whisper", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    local ann = PeerWorld.Peer("Ann", { version = "0.1.0" })
    ann:Hello("YELL")
    T.advance(2)
    T.eq(#PeerWorld.Sent("WHISPER", ann.name), 1)
    ann:Hello("YELL")
    T.advance(2)
    T.eq(#PeerWorld.Sent("WHISPER", ann.name), 1, "once per REPLY_COOLDOWN")
    local horde = PeerWorld.Peer("Grok", { version = "0.1.0", faction = "H",
        finds = { [RIVERGLADES] = { n = { [PEACEBLOOM] = { { 0.3, 0.4 } } } } } })
    horde:Hello("YELL")
    T.advance(3)
    T.eq(#PeerWorld.Sent("WHISPER", horde.name), 0, "no reply, no request across factions")
    local newer = PeerWorld.Peer("Hal", { version = "0.3.0", faction = "H" })
    newer:Hello("YELL")
    T.advance(P.NOTICE_DELAY + 1)
    T.eq(#PeerWorld.lines, 1, "the other faction's version still counts")
end)

T.test("skins: one peer's no isn't enough, two are; a skin from anyone wins; peers never write the player's learning", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    CP.db.skinSeen = { [LONGSNOUT] = true, [WOLF] = G.NO_SKIN }
    local ann = PeerWorld.Peer("Ann", { skin = { no = { BOAR, PROWLER, LONGSNOUT } } })
    ann:Hello("YELL")
    T.advance(5)
    T.eq(asks(ann.name), { "R s" }, "asked for her skin reports")
    T.ok(G.Skinnable(BOAR), "one sender's no")
    PeerWorld.Peer("Bob", { skin = { no = { BOAR, PROWLER, LONGSNOUT }, yes = { WOLF } } }):Hello("YELL")
    T.advance(5)
    T.eq(G.Skinnable(BOAR), false, "two senders say no")
    T.eq(G.Skinnable(PROWLER), false)
    T.ok(G.Skinnable(LONGSNOUT), "the player skinned it")
    T.ok(G.Skinnable(WOLF), "a peer skinned what the player's corpses said no to")
    T.eq(CP.db.skinSeen, { [LONGSNOUT] = true, [WOLF] = G.NO_SKIN }, "the player's learning is untouched")
    PeerWorld.Peer("Cy", { skin = { yes = { PROWLER } } }):Hello("YELL")
    T.advance(5)
    T.ok(G.Skinnable(PROWLER), "a skinnable report wins")
    PeerWorld.Peer("Dee", { skin = { no = { PROWLER } } }):Hello("YELL")
    T.advance(5)
    T.ok(G.Skinnable(PROWLER), "and keeps winning")
end)

T.test("finds: digest, request by whisper, chunks under 255 bytes, reassembly, applied when finds settle", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    local many = {}
    for i = 1, 60 do many[i] = { 0.1 + i * 0.01, 0.6 } end
    local ann = PeerWorld.Peer("Ann", { finds = { [RIVERGLADES] = {
        n = { [PEACEBLOOM] = { { 0.30, 0.40 }, { 0.50, 0.50 }, unpack(many) } },
        m = { [BOAR] = { { 0.20, 0.20 } } } } } })
    local bob = PeerWorld.Peer("Bob", { finds = { [RIVERGLADES] = {
        n = { [PEACEBLOOM] = { { 0.301, 0.401 }, { 0.70, 0.70 } } },
        m = { [BOAR] = { { 0.201, 0.20 } } } } } })
    CP.db.finds = { [RIVERGLADES] = { n = { Peacebloom = { CP.Finds.Pack(0.70, 0.70) } } } }
    T.eq(#GM.Nodes(RIVERGLADES).Peacebloom, 1, "the player's own find")
    ann:Hello("YELL")
    T.advance(10)
    T.eq(asks(ann.name), { "R 2548" })
    T.ok(has(PeerWorld.Sent("WHISPER", ann.name), "^H 1 0%.2%.0 A 1 2548:1:"), "and our digest back, since we share")
    T.ok(#CP.db.peerFinds[RIVERGLADES][ann.name].n.Peacebloom == 62, "every chunk put together")
    T.eq(CP.db.peers[ann.name].g["2548"] ~= nil, true, "her digest is remembered")
    bob:Hello("YELL")
    T.advance(10)
    T.ok(CP.db.peerFinds[RIVERGLADES][bob.name], "Bob's too")
    T.eq(#GM.Nodes(RIVERGLADES).Peacebloom, 1, "nothing rebuilt per message")
    T.ok(GM.Pending())
    T.advance(GM.SETTLE + 1)
    local nodes = GM.Nodes(RIVERGLADES).Peacebloom
    T.ok(near(nodes, 0.30, 0.40), "two senders agree: the spot is used")
    T.ok(not near(nodes, 0.50, 0.50), "one sender alone: not used")
    T.eq(#nodes, 2, "the player's own spot isn't doubled by Bob's matching one")
    T.ok(near(P.Mobs(RIVERGLADES)[BOAR], 0.20, 0.20), "skinning spots likewise")
    ann:Hello("YELL")
    T.advance(5)
    T.eq(#asks(ann.name), 1, "an unchanged digest isn't asked for again")
    for _, m in ipairs(PeerWorld.sent) do T.ok(#m.text <= 255, "under 255 bytes") end
end)

T.test("finds: our own go out in chunks a peer can put back together, own finds only", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    local spots = {}
    for i = 1, 70 do spots[i] = CP.Finds.Pack(0.1 + i * 0.01, 0.3) end
    CP.db.finds = { [RIVERGLADES] = { n = { Peacebloom = spots, ["Not A Herb"] = { CP.Finds.Pack(0.5, 0.5) } } },
                    [1429] = { n = { Peacebloom = { CP.Finds.Pack(0.5, 0.5) } } } }
    CP.db.peerFinds = { [RIVERGLADES] = { ["Zed-Testrealm"] = { t = 1, c = 1, n = { Silverleaf = { CP.Finds.Pack(0.9, 0.9) } }, m = {} } } }
    local hello = P.Hello(true)
    T.ok(hello:find(" 2548:70:%x+$"), hello)
    T.ok(not hello:find("1429"), "only the player's zone")
    local ann = PeerWorld.Peer("Ann")
    ann:Say("R 2548", "WHISPER")
    T.advance(20)
    local parts = {}
    local hash, total
    for _, m in ipairs(PeerWorld.Sent("WHISPER", ann.name)) do
        local key, h, seq, n, part = m.text:match("^C (%w+) (%x+) (%d+) (%d+) (%S+)$")
        T.eq(key, "2548")
        hash, total = h, tonumber(n)
        parts[tonumber(seq)] = part
        T.ok(#m.text <= 255)
    end
    T.ok(total and total > 1, "several chunks")
    local body = table.concat(parts)
    T.eq(PeerWorld.Hash(body), hash)
    T.eq(#body, #"n1618:" + 70 * 6, "own Peacebloom only: no unknown names, no peers' finds")
    ann:Say("R 2548", "WHISPER")
    T.advance(5)
    T.eq(#PeerWorld.Sent("WHISPER", ann.name), total, "the same body to the same peer: not again so soon")
    ann:Say("R 99999", "WHISPER")
    T.advance(5)
    T.eq(#PeerWorld.Sent("WHISPER", ann.name), total, "a zone that doesn't exist isn't served")
    ann:Say("R 1429", "WHISPER")
    T.advance(5)
    T.eq(#PeerWorld.Sent("WHISPER", ann.name), total + 1, "any other zone is, on request")
end)

T.test("validation: bad coordinates, charset, hash, unasked chunks and unknown zones are dropped", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    local bad = PeerWorld.Peer("Ann", { bodies = { ["2548"] = "n1618:zzzzzz" } })
    bad:Hello("YELL")
    T.advance(5)
    T.eq(CP.db.peerFinds, nil, "a coordinate over 1")
    local zero = PeerWorld.Peer("Abe", { bodies = { ["2548"] = "n1618:" .. PeerWorld.B36(5000) } })
    zero:Hello("YELL")
    T.advance(5)
    T.eq(CP.db.peerFinds, nil, "x of 0")
    local liar = PeerWorld.Peer("Bob", { finds = { [RIVERGLADES] = { n = { [PEACEBLOOM] = { { 0.3, 0.4 } } } } },
                                          hash = { ["2548"] = "00000000" } })
    liar:Hello("YELL")
    T.advance(5)
    T.eq(CP.db.peerFinds, nil, "the body doesn't match its hash")
    local cy = PeerWorld.Peer("Cy")
    cy:Say("C 2548 " .. PeerWorld.Hash("n1618:" .. PeerWorld.B36(PeerWorld.Pack(0.3, 0.4))) .. " 1 1 n1618:"
        .. PeerWorld.B36(PeerWorld.Pack(0.3, 0.4)), "WHISPER")
    T.advance(1)
    T.eq(CP.db.peerFinds, nil, "a chunk nobody asked for")
    local dee = PeerWorld.Peer("Dee", { bodies = { ["99999"] = "n1618:" .. PeerWorld.B36(PeerWorld.Pack(0.3, 0.4)) } })
    dee:Hello("YELL")
    T.advance(5)
    T.eq(#PeerWorld.Sent("WHISPER", dee.name), 0, "a zone that doesn't exist isn't asked for")
    local eve = PeerWorld.Peer("Eve", { bodies = { ["2548"] = "n1618:ab|cde" } })
    eve:Hello("YELL")
    T.advance(5)
    T.eq(CP.db.peerFinds, nil, "characters outside the protocol's")
    local fay = PeerWorld.Peer("Fay", { finds = { [RIVERGLADES] = {
        n = { [PEACEBLOOM] = { { 0.3, 0.4 } }, [999999] = { { 0.5, 0.5 } } }, m = { [99001] = { { 0.2, 0.2 } } } } } })
    fay:Hello("YELL")
    T.advance(5)
    local got = CP.db.peerFinds[RIVERGLADES][fay.name]
    T.eq(#got.n.Peacebloom, 1, "an entry this copy lacks is skipped, the rest kept")
    T.eq(next(got.m), nil, "a creature not in the data is skipped")
    local gus = PeerWorld.Peer("Gus", { bodies = { s = "+113,abc-" } })
    gus:Hello("YELL")
    T.advance(5)
    T.eq(CP.db.peerSkin, nil, "a skin body that doesn't parse")
    local hal = PeerWorld.Peer("Hal", { skin = { no = { 30, 99999 } } })   -- Forest Spider: no skinning loot
    hal:Hello("YELL")
    T.advance(5)
    T.eq(next(CP.db.peerSkin), nil, "creatures without skinning loot are ignored")
end)

T.test("caps: per sender, per zone and per minute", function()
    World.set(P, "SPOTS_PER_SENDER", 3)
    World.set(P, "SPOTS_PER_ZONE", 4)
    begin({ version = "0.2.0", zone = RIVERGLADES })
    local four = { { 0.1, 0.1 }, { 0.2, 0.2 }, { 0.3, 0.3 }, { 0.4, 0.4 } }
    local big = PeerWorld.Peer("Ann", { finds = { [RIVERGLADES] = { n = { [PEACEBLOOM] = four } } } })
    big:Hello("YELL")
    T.advance(5)
    T.eq(#PeerWorld.Sent("WHISPER", big.name), 0, "a digest over the cap isn't asked for")
    local liar = PeerWorld.Peer("Abe", { finds = { [RIVERGLADES] = { n = { [PEACEBLOOM] = four } } },
                                         count = { ["2548"] = 2 } })
    liar:Hello("YELL")
    T.advance(5)
    T.eq(CP.db.peerFinds, nil, "a body over the cap is dropped whatever its digest said")
    local three = { { 0.1, 0.1 }, { 0.2, 0.2 }, { 0.3, 0.3 } }
    local bob = PeerWorld.Peer("Bob", { finds = { [RIVERGLADES] = { n = { [PEACEBLOOM] = three } } } })
    bob:Hello("YELL")
    T.advance(5)
    T.advance(2)
    local cy = PeerWorld.Peer("Cy", { finds = { [RIVERGLADES] = { n = { [PEACEBLOOM] = three } } } })
    cy:Hello("YELL")
    T.advance(5)
    T.eq(CP.db.peerFinds[RIVERGLADES][bob.name], nil, "over the zone's cap: the oldest sender goes")
    T.ok(CP.db.peerFinds[RIVERGLADES][cy.name])
    T.eq(CP.db.peers[bob.name].g["2548"], nil, "and can be asked again later")

    World.set(P, "SENDER_PER_MIN", 3)
    local dee = PeerWorld.Peer("Dee")
    for i = 1, 5 do dee:Say("H 1 0.3." .. i .. " A 0", "YELL") end
    T.advance(2)
    T.eq(CP.db.newestSeen, "0.3.3", "past the per-minute cap, a sender's messages are dropped")
    T.advance(60)
    dee:Say("H 1 0.3.9 A 0", "YELL")
    T.advance(1)
    T.eq(CP.db.newestSeen, "0.3.9", "the next minute takes them again")
end)

T.test("combat pauses the queue; a throttled send goes again", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    PeerWorld.Combat(true)
    P.Broadcast("YELL")
    T.advance(5)
    T.eq(#PeerWorld.sent, 0, "nothing sent in combat")
    T.eq(#P.Queue(), 1)
    PeerWorld.Combat(false)
    T.advance(1)
    T.eq(#PeerWorld.Sent("YELL"), 1, "sent once combat ends")
    PeerWorld.Results({ 3 })
    P.Broadcast("YELL")
    T.advance(P.GAP * 3)
    local yells = PeerWorld.Sent("YELL")
    T.eq(#yells, 3, "the throttled hello went again")
    T.eq(yells[2].text, yells[3].text)
    CP.db.finds = { [RIVERGLADES] = { n = { Peacebloom = (function()
        local s = {}
        for i = 1, 70 do s[i] = CP.Finds.Pack(0.1 + i * 0.01, 0.3) end
        return s
    end)() } } }
    P.Hello(true)
    local ann = PeerWorld.Peer("Ann")
    ann:Say("R 2548", "WHISPER")
    T.advance(0.2)
    local before = #PeerWorld.sent
    T.ok(#P.Queue() > 0, "chunks wait their turn")
    PeerWorld.Combat(true)
    T.advance(10)
    T.eq(#PeerWorld.sent, before, "paused mid-way in combat")
    PeerWorld.Combat(false)
    T.advance(P.GAP * #P.Queue() + 2)
    T.eq(#P.Queue(), 0, "and finished after")
end)

local NOT_FOUND = "No player named '%s' is currently playing."

T.test("a 'no player named' line is hidden only for a name ProfLost just whispered", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    World.set(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S", "No player named '%s' is currently playing.")
    local ann = PeerWorld.Peer("Ann", { version = "0.1.0" })
    ann:Hello("YELL")
    T.advance(2)
    T.ok(P.HideSystem(nil, "CHAT_MSG_SYSTEM", NOT_FOUND:format("Ann-Testrealm")))
    T.ok(P.HideSystem(nil, "CHAT_MSG_SYSTEM", NOT_FOUND:format("Ann")))
    T.ok(not P.HideSystem(nil, "CHAT_MSG_SYSTEM", NOT_FOUND:format("Bob")))
    T.advance(P.WHISPER_HIDE + 1)
    T.ok(not P.HideSystem(nil, "CHAT_MSG_SYSTEM", NOT_FOUND:format("Ann")), "only for a while")
end)

T.test("finds sync for the player's zone only; arriving in a zone asks the peers met lately", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    local ELWYNN = 1429
    local ann = PeerWorld.Peer("Ann", { zone = ELWYNN, finds = {
        [ELWYNN] = { n = { [PEACEBLOOM] = { { 0.3, 0.4 } } } },
        [1411] = { n = { [PEACEBLOOM] = { { 0.5, 0.5 } } } } } })
    ann:Hello("YELL")
    T.advance(5)
    T.eq(asks(ann.name), {}, "her zone isn't ours: nothing asked")
    PeerWorld.Move(ELWYNN)
    T.advance(P.ARRIVE_DELAY + 5)
    T.ok(has(PeerWorld.Sent("WHISPER", ann.name), "^Q 1429$"), "asked for her digest of our new zone")
    T.eq(asks(ann.name), { "R 1429" })
    T.ok(CP.db.peerFinds[ELWYNN][ann.name], "and got it")
    T.eq(CP.db.peerFinds[1411], nil, "never the rest of her world")
    for _, m in ipairs(PeerWorld.sent) do T.ok(m.text ~= "Q *", "a normal player never asks for every zone") end
    PeerWorld.Move(1411)
    PeerWorld.Move(ELWYNN)
    T.advance(P.ARRIVE_DELAY + 5)
    T.eq(#asks(ann.name), 1, "a quick pass through a zone asks nothing; her unchanged digest isn't asked again")
end)

T.test("the owner's collector pulls every zone from each peer, one body at a time, never in combat", function()
    begin({ version = "0.2.0", zone = RIVERGLADES })
    SlashCmdList.PROFLOST("collect on")
    T.eq(CP.db.collect_all, true)
    T.ok(not CP.Settings.Find("collect_all"), "not on the options page")
    local three = { [1411] = { n = { [PEACEBLOOM] = { { 0.3, 0.4 } } } },
                    [1429] = { n = { [PEACEBLOOM] = { { 0.5, 0.5 } } } },
                    [2482] = { m = { [BOAR] = { { 0.2, 0.2 } } } } }
    local ann = PeerWorld.Peer("Ann", { zone = 1429, finds = three })
    PeerWorld.Combat(true)
    ann:Hello("YELL")
    T.advance(10)
    T.eq(#PeerWorld.sent, 0, "nothing sent in combat")
    PeerWorld.Combat(false)
    T.advance(1.5)
    T.ok(has(PeerWorld.Sent("WHISPER", ann.name), "^Q %*$"), "asked for every zone's digest")
    T.ok(#asks(ann.name) <= 1, "bodies come one at a time")
    T.advance(20)
    T.eq(asks(ann.name), { "R 1429", "R 1411", "R 2482" }, "every zone, hers first")
    for zone in pairs(three) do T.ok(CP.db.peerFinds[zone][ann.name], "kept zone " .. zone) end
    SlashCmdList.PROFLOST("collect off")
    T.eq(CP.db.collect_all, nil)
    local bob = PeerWorld.Peer("Bob", { zone = 1429, finds = three })
    bob:Hello("YELL")
    T.advance(10)
    T.eq(asks(bob.name), {}, "collector off: a normal player pulls nothing outside its zone")
end)

T.test("the hidden kill switch stops all sharing both ways; a beta tag never goes out", function()
    begin({ version = "0.2.0-beta", zone = RIVERGLADES })
    T.eq(P.Version(), "0.2.0", "the tag is dropped from what's sent")
    SlashCmdList.PROFLOST("share off")
    T.ok(P.Off())
    local ann = PeerWorld.Peer("Ann", { version = "0.2.1", skin = { no = { PROWLER } } })
    ann:Hello("YELL")
    T.advance(P.NOTICE_DELAY + 5)
    T.eq(#PeerWorld.lines, 0, "no notice: nothing is read")
    T.eq(#PeerWorld.Sent("WHISPER", ann.name), 0, "nothing is sent")
    SlashCmdList.PROFLOST("share on")
    T.ok(not P.Off())
end)
