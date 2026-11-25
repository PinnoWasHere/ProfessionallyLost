-- What's New after an update and the newer-version notice (UI/News.lua), in Daylight UI's
-- question box (Options/Widgets.lua W.Ask) through a stand-in that records each note.

local CP = ProfLost
local News = CP.News

-- Mock changelog: three versions, newest first, as the release tooling writes them.
local CHANGES = {
    { version = "1.6.0", summary = "Not out yet.", sections = { { "New", { "Guide: From the future" } } } },
    { version = "1.5.0", summary = "A resizable guide.", sections = {
        { "New", { "Guide: Drag the corner to resize it" } },
        { "Fixed", { "Shop: The scan starts" } } } },
    { version = "1.4.0", summary = "Working Overtime.", sections = { { "New", { "Guide: Plans count Working Overtime" } } } },
}

-- This copy runs `version`, the changelog is the mock, and Daylight UI's box records each note.
local function scene(version)
    local metadata = C_AddOns.GetAddOnMetadata
    World.set(C_AddOns, "GetAddOnMetadata", function(addon, field)
        if addon == CP.name and field == "Version" then return version end
        return metadata(addon, field)
    end)
    World.set(CP, "CHANGES", CHANGES)
    local notes = {}
    -- Only the box: the rest of ProfLost still draws its own look.
    World.set(_G, "DaylightUI", { Widgets = { Ask = function(spec) notes[#notes + 1] = spec end } })
    for _, key in ipairs({ "newsSeen", "whatsNew", "newerNotice", "welcomed" }) do World.set(CP.db, key, CP.db[key]) end
    News.Reset()
    World.onEnd(News.Reset)
    return notes
end

T.test("an update from 1.4.0 to 1.5.0 shows 1.5.0's lines once, and not again after a reload", function()
    local notes = scene("1.5.0")
    CP.db.newsSeen = "1.4.0"
    News.Greet()
    T.eq(#notes, 1, "one note")
    local n = notes[1]
    T.eq(n.title, "What's New in Professionally Lost")
    T.eq(n.yes, "Okay")
    T.eq(n.no, false, "one button")
    T.ok(n.text:find("Drag the corner to resize it", 1, true), n.text)
    T.ok(n.text:find("The scan starts", 1, true), "every section's lines")
    T.ok(n.text:find("A resizable guide.", 1, true), "the summary")
    T.ok(not n.text:find("Working Overtime", 1, true), "not the version already read")
    T.ok(not n.text:find("From the future", 1, true), "never a version newer than this one")
    T.eq(CP.db.newsSeen, "1.5.0", "marked read")
    News.Greet()
    T.eq(#notes, 1, "a reload shows nothing more")
end)

local function count(text, pat)
    local n = 0
    for _ in text:gmatch(pat) do n = n + 1 end
    return n
end

T.test("a long entry shows the summary, five lines (New first), and how many more", function()
    local notes = scene("1.5.0")
    World.set(CP, "CHANGES", { { version = "1.5.0", summary = "Big one.", sections = {
        { "New", { "N1", "N2", "N3" } },
        { "Changed", { "C1", "C2", "C3" } },
        { "Fixed", { "F1", "F2", "F3", "F4" } } } } })
    CP.db.newsSeen = "1.4.0"
    News.Greet()
    local text = notes[1].text
    T.ok(text:find("Big one.", 1, true), "the summary")
    T.eq(count(text, "•"), 5, "five change lines")
    T.ok(text:find("N1", 1, true) and text:find("N3", 1, true) and text:find("C1", 1, true) and text:find("C2", 1, true), text)
    T.ok(not text:find("C3", 1, true) and not text:find("F1", 1, true), "cut after five, New then Changed then Fixed")
    T.ok(text:find("and 5 more changes", 1, true), text)
    T.ok(text:find("N1", 1, true) < text:find("C1", 1, true), "New before Changed")
end)

T.test("a short entry shows every line and no 'more' line", function()
    local notes = scene("1.5.0")
    CP.db.newsSeen = "1.4.0"
    News.Greet()
    T.eq(count(notes[1].text, "•"), 2)
    T.ok(not notes[1].text:find("more change", 1, true), notes[1].text)
end)

T.test("several versions show one summary each, and the newest's highlights", function()
    local notes = scene("1.5.0")
    World.set(CP, "CHANGES", { CHANGES[2], CHANGES[3] })
    CP.db.newsSeen = "1.3.0"
    News.Greet()
    local text = notes[1].text
    T.ok(text:find("A resizable guide.", 1, true) and text:find("Working Overtime.", 1, true), "both summaries")
    T.ok(text:find("Drag the corner", 1, true), "newest's lines")
    T.ok(not text:find("Plans count Working Overtime", 1, true), "older versions' lines left out")
end)

T.test("a first install shows nothing and counts this version read", function()
    local notes = scene("1.5.0")
    CP.db.newsSeen, CP.db.welcomed = nil, nil
    News.Loaded()
    News.Greet()
    T.eq(#notes, 0)
    T.eq(CP.db.newsSeen, "1.5.0")
end)

T.test("an update from before What's New shows this version's lines only", function()
    local notes = scene("1.5.0")
    CP.db.newsSeen, CP.db.welcomed = nil, true
    News.Loaded()
    News.Greet()
    T.eq(#notes, 1)
    T.ok(not notes[1].text:find("Working Overtime", 1, true), "only 1.5.0")
end)

T.test("Show What's New off: no note after an update", function()
    local notes = scene("1.5.0")
    CP.db.newsSeen, CP.db.whatsNew = "1.4.0", false
    News.Greet()
    T.eq(#notes, 0)
    T.eq(CP.db.newsSeen, "1.5.0", "the update counts as read, so turning it on later shows nothing old")
end)

T.test("the What's New button shows this version's lines again, read or not", function()
    local notes = scene("1.5.0")
    CP.db.newsSeen = "1.5.0"
    local row
    for _, s in ipairs(CP.Settings.LIST) do
        if s.kind == "button" and s.label == "What's New" then row = s end
    end
    T.ok(row ~= nil, "a What's New row")
    T.eq(row.button, "Show")
    local item
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, it in ipairs(g.items) do
            if it.type == "button" and it.label == "What's New" then item = it end
        end
    end
    T.ok(item ~= nil and item.text == "Show", "the page's row: What's New, with a Show button")
    item.func()
    T.eq(#notes, 1)
    T.ok(notes[1].text:find("Drag the corner to resize it", 1, true))
    item.func()
    T.eq(#notes, 2, "every click")
end)

T.test("a note asked for in a fight waits for the fight's end", function()
    local notes = scene("1.5.0")
    CP.db.newsSeen = "1.4.0"
    local fight = true
    World.patch("InCombatLockdown", function() return fight end)
    News.Greet()
    T.eq(#notes, 0, "nothing in the fight")
    fight = false
    T.fire("PLAYER_REGEN_ENABLED")
    T.eq(#notes, 1, "after it")
end)

T.test("a newer version heard from a peer opens one note a session; equal or lower opens none", function()
    local notes = scene("0.2.0")
    PeerWorld.begin({ version = "0.2.0" })
    PeerWorld.Peer("Ann", { version = "0.2.0" }):Hello("YELL")
    PeerWorld.Peer("Bob", { version = "0.1.9" }):Hello("GUILD")
    T.advance(CP.Peers.NOTICE_DELAY + 1)
    T.eq(#notes, 0, "equal or lower: nothing")
    PeerWorld.Peer("Cy", { version = "0.3.0" }):Hello("YELL")
    T.advance(CP.Peers.NOTICE_DELAY + 1)
    T.eq(#notes, 1, "a newer one")
    T.eq(notes[1].title, "Professionally Lost")
    T.ok(notes[1].text:find("0.3.0", 1, true), notes[1].text)
    T.eq(#PeerWorld.lines, 0, "in the window, not chat")
    PeerWorld.Peer("Dee", { version = "0.4.0" }):Hello("YELL")
    T.advance(CP.Peers.NOTICE_DELAY + 1)
    T.eq(#notes, 1, "once a session")
end)

T.test("Newer version notice off: a newer peer opens nothing", function()
    local notes = scene("0.2.0")
    PeerWorld.begin({ version = "0.2.0" })
    CP.db.newerNotice = false
    PeerWorld.Peer("Cy", { version = "0.3.0" }):Hello("YELL")
    T.advance(CP.Peers.NOTICE_DELAY + 1)
    T.eq(#notes, 0)
    T.eq(#PeerWorld.lines, 0, "and no chat line")
    T.eq(CP.db.newestSeen, "0.3.0", "the bug report still names it")
end)
