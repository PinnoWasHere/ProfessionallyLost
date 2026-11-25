-- The bug report window (UI/BugReport.lua).

local CP = ProfLost
local BR = CP.BugReport

T.test("errors naming ProfLost are kept, newest first, at most five; others are passed by", function()
    local errs = BR.Errors()
    for i = #errs, 1, -1 do errs[i] = nil end
    BR.Capture("Interface/AddOns/OtherAddon/x.lua:1: boom")
    T.eq(#errs, 0, "another addon's error isn't kept")
    for i = 1, 7 do BR.Capture(("Interface/AddOns/ProfessionallyLost/UI/GuideTab.lua:%d: oops"):format(i)) end
    T.eq(#errs, BR.MAX_ERRORS)
    T.ok(errs[1]:find(":7:"), "newest first")
    for i = #errs, 1, -1 do errs[i] = nil end
end)

T.test("the report names versions, place, profession, guide rows and errors, and the window shows it", function()
    BR.Capture("Interface/AddOns/ProfessionallyLost/Engine/Route.lua:12: bad route")
    MapWorld.begin({ zone = 1421, x = 0.45, y = 0.62, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [165] = 100 } })
    CraftWorld.Open(165)
    World.onEnd(function()
        local errs = BR.Errors()
        for i = #errs, 1, -1 do errs[i] = nil end
    end)
    local text = table.concat(BR.Text({ happened = "the route went through Southshore" }), "\n")
    T.ok(text:find("Professionally Lost bug report", 1, true))
    T.ok(text:find("the route went through Southshore", 1, true), "the player's words")
    T.ok(text:find("What I expected:\n(not filled in)", 1, true), "an empty answer says so")
    T.ok(text:find("Daylight UI", 1, true), "Daylight UI's version")
    T.ok(text:find("Profession: Leatherworking 100/150", 1, true), text)
    T.ok(text:find("Horde level 30 · Silverpine Forest (1421) at 45.0, 62.0", 1, true), "where the player stands")
    T.ok(text:find("Guide rows:", 1, true), "the guide's rows")
    T.ok(text:find("bad route", 1, true), "the error")
    local details = BR.Show()
    local win = _G.ProfLost_BugReport
    T.eq(details, table.concat(BR.Details(), "\n"), "the form opens on the details")
    T.ok(win:IsShown())
    T.ok(BR.Details()[1]:sub(1, 2) == "- ", "detail lines are bullets")
    win.happened.box:SetText("panel vanished")
    win:Hide()
    BR.Show()
    T.eq(win.happened.box:GetText(), "panel vanished", "closing without copying keeps what was typed")

    local clicked = win.details.box
    clicked:GetScript("OnMouseDown")(clicked, "LeftButton")
    local report = clicked:GetText()
    T.ok(report:find("What happened:\npanel vanished", 1, true), "a click in the details builds the report")
    clicked:SetText("")
    clicked:GetScript("OnTextChanged")(clicked, true)
    T.eq(clicked:GetText(), report, "a stray Backspace in the report puts it back")
    win:Hide()
    BR.Show()
    T.eq(win.happened.box:GetText(), "", "after a report is selected, the next one starts empty")

    win.expected.box:SetText("the route to skip it")
    BR.Clear()
    T.eq(win.expected.box:GetText(), "", "Clear empties the answers")
    T.eq(win.details.box:GetText(), table.concat(BR.Details(), "\n"), "and puts the details back")
    win:Hide()
end)

T.test("the title bar: close, bug, lock, fold from the right, View and the dropdown on the tab row; no Checklist button", function()
    local P, W = CP.Panel, CP.Window
    World.set(CP.charDB, "guideMode", nil)
    W.Place()
    local function x(b)
        T.ok(b:IsShown())
        local point, rel, _, ox = b:GetPoint(1)
        T.eq(point, "TOPRIGHT")
        T.eq(rel, P.frame)
        return ox
    end
    T.eq(x(W.closeButton), -P.TITLE_EDGE, "close at the far right of the free window")
    T.ok(x(P.bugButton) < x(W.closeButton), "the bug button left of close")
    T.ok(x(W.lockButton) < x(P.bugButton), "the lock left of the bug button")
    T.ok(x(W.foldButton) < x(W.lockButton), "the fold chevron left of the lock")
    T.eq(x(W.switchButton), -P.ROW_EDGE, "View at the tab row's right")
    T.ok(x(W.pickButton) < x(W.switchButton), "the profession dropdown left of View")
    T.eq(P.gatherButton, nil, "the gathering panel's tab replaces the Checklist button")
    T.eq(P.tabs.gather, nil, "no Gather tab")
    T.ok(CP.GatherPanel.tab ~= nil)
    P.bugButton:GetScript("OnClick")(P.bugButton)
    T.ok(_G.ProfLost_BugReport:IsShown(), "the bug button opens the report")
    _G.ProfLost_BugReport:Hide()
end)

-- The State line ---------------------------------------------------------------------

-- The report's State line, without its bullet.
local function stateLine()
    for _, line in ipairs(BR.Details()) do
        if line:sub(1, 9) == "- State: " then return line:sub(3) end
    end
end

local COOKING, FISHING, LEATHER = 185, 356, 165
local SMALLFISH = 7751   -- Brilliant Smallfish

-- The scene of the first player's report: Cooking 40/75 knowing Brilliant Smallfish, Fishing 40/75,
-- nothing saved, the spellbook silent, no profession window opened since login.
local function firstPlayer()
    World.patch("C_SpellBook.IsSpellKnown", function() return false end)
    MapWorld.begin({ zone = 1411, level = 32, side = "Horde" })
    CraftWorld.begin({ professions = {
        [COOKING] = { rank = 40, max = 75, known = { SMALLFISH } },
        [FISHING] = { rank = 40, max = 75, known = {} },
    } })
end

-- The text of the State line's segment that starts with `prefix`, or nil.
local function segment(line, prefix)
    local body = line:gsub("^State: ", ""):gsub("#%x+$", "")
    for part in body:gmatch("[^;]+") do
        if part:sub(1, #prefix) == prefix then return part end
    end
end

-- The lines ProfLost writes for these scenes. A replay tool reads these two constants and turns
-- them into runs, so keep each on one line.
local FIRST_PLAYER_LINE = "State: v1;lv=32,side=H;185:40/75,k=-,src=none,read=0,bk=0;356:40/75;win=none,open=-,ts=none;mode=one,pick=185,collect=1,fishCook=1;held=-#bf36"
local RECOGNISED_LINE = "State: v1;lv=32,side=H;185:40/75,k=5zb,src=live,read=1,bk=0;356:40/75;win=game,open=185,ts=own;mode=one,pick=185,collect=1,fishCook=1;held=-#331d"

T.test("State: no profession window opened since login, nothing saved, the spellbook silent", function()
    firstPlayer()
    T.eq(stateLine(), FIRST_PLAYER_LINE, "the first player's case, exactly")
    T.ok(table.concat(BR.Details(), "\n"):find("Profession: none open", 1, true), "the old line still says none open")
end)

T.test("State: a recognised window gives the live list, marks the profession read and names the window", function()
    firstPlayer()
    CraftWorld.Open(COOKING)
    local line = stateLine()
    T.eq(line, RECOGNISED_LINE, "Cooking open in the game's window, exactly")
    T.eq(segment(line, "185:"), "185:40/75,k=5zb,src=live,read=1,bk=0", line)
    T.eq(segment(line, "win="), "win=game,open=185,ts=own", line)

    CraftWorld.Close()
    line = stateLine()
    T.eq(segment(line, "185:"), "185:40/75,k=5zb,src=saved,read=1,bk=0", "shut again: the saved list, read")
    T.eq(segment(line, "win="), "win=none,open=-,ts=none", line)

    DaylightWorld.begin({ plugin = true })
    CraftWorld.Open(COOKING)
    T.eq(segment(stateLine(), "win="), "win=dui,open=185,ts=own", "Daylight UI's craft window")
    CraftWorld.Close()
end)

T.test("State: DaylightMogul's window is named", function()
    firstPlayer()
    MogulWorld.begin({ craftWindow = true })
    CraftWorld.Open(COOKING)
    T.eq(segment(stateLine(), "win="), "win=mogul,open=185,ts=own")
    CraftWorld.Close()
end)

T.test("State: another addon's window counts as the game's, by its open trade skill", function()
    firstPlayer()
    CraftWorld.Open(COOKING, nil, "foreign")
    local line = stateLine()
    T.eq(segment(line, "win="), "win=game,open=185,ts=own", line)
    T.eq(segment(line, "185:"), "185:40/75,k=5zb,src=live,read=1,bk=0", "the list is read live through it")
    CraftWorld.Close()
    T.eq(segment(stateLine(), "185:"), "185:40/75,k=5zb,src=saved,read=1,bk=0", "and saved once it shuts")
end)

T.test("State: an unread profession's list is the spellbook's, and the spellbook's count is carried", function()
    firstPlayer()
    World.patch("C_SpellBook.IsSpellKnown", function(id) return id == SMALLFISH end)
    local line = stateLine()
    T.eq(segment(line, "185:"), "185:40/75,k=-,src=none,read=0,bk=1", line)
    T.eq(CP.charDB.learned, nil, "building the report saves nothing")
    CP.charDB.learned = { [COOKING] = { SMALLFISH } }
    T.eq(segment(stateLine(), "185:"), "185:40/75,k=5zb,src=book,read=0,bk=1", "unread with ids: the book's")
end)

T.test("State: two professions, each with its own skill, cap and list", function()
    World.patch("C_SpellBook.IsSpellKnown", function() return false end)
    MapWorld.begin({ zone = 1411, level = 60, side = "Alliance" })
    CraftWorld.begin({ professions = {
        [LEATHER] = { rank = 100, max = 150, known = {} },
        [COOKING] = { rank = 40, max = 75, known = { SMALLFISH } },
    } })
    CraftWorld.Open(LEATHER)
    local line = stateLine()
    T.ok(line:find("^State: v1;lv=60,side=A;"), line)
    T.eq(segment(line, "165:"), "165:100/150,k=-,src=live,read=1,bk=0", line)
    T.eq(segment(line, "185:"), "185:40/75,k=-,src=none,read=0,bk=0", "Cooking has not been read")
    T.eq(segment(line, "win="), "win=game,open=165,ts=own", line)
    CraftWorld.Close()
end)

T.test("State: settings, mode, pick and the held counts of what the plan needs", function()
    firstPlayer()
    World.set(CP.db, "collect", false)
    World.set(CP.db, "fishCook", false)
    World.set(CP.charDB, "guideMode", "all")
    World.set(CP.charDB, "guideProf", FISHING)
    local line = stateLine()
    T.eq(segment(line, "mode="), "mode=all,pick=356,collect=0,fishCook=0", line)
    World.set(CP.db, "collect", true)
    World.set(CP.db, "fishCook", true)
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.charDB, "guideProf", COOKING)
    CraftWorld.Open(COOKING)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    T.advance(0.2)
    local live = CP.GuideTab.ui.live
    T.ok(live and live.plan and #live.plan > 0, "the guide drew a plan")
    local item = CP.Guides[COOKING].recipes[live.plan[1].spell].reagents[1][1]
    CraftWorld.SetBag(item, 7)
    CraftWorld.SetBag(6948, 3)    -- Hearthstone: no plan step needs it
    local held = segment(stateLine(), "held=")
    T.ok(held:find(item .. "x7", 1, true), held)
    T.eq(held:find("6948", 1, true), nil, "an item the plan does not need is not listed")
    CraftWorld.SetBag(item, 100000)
    T.ok(segment(stateLine(), "held="):find(item .. "x" .. BR.COUNT_MAX, 1, true), "a count is capped")
    CraftWorld.Close()
end)

T.test("State: no character name, realm, guild or free text in the whole report", function()
    firstPlayer()
    local marker = "Zqxmarker"
    for _, name in ipairs({ "UnitName", "UnitFullName", "GetUnitName", "GetRealmName", "GetNormalizedRealmName" }) do
        World.patch(name, function() return marker end)
    end
    World.patch("GetGuildInfo", function() return marker, marker, 0 end)
    local text = table.concat(BR.Text({ happened = "free text", expected = "more" }), "\n")
    T.ok(text:find("State: v1;", 1, true), "the report has the line")
    T.eq(text:find(marker, 1, true), nil, "no marker anywhere in the report")
    local line = stateLine()
    T.ok(line:match("^State: [%w:/;,=%+%-%?]+#%x%x%x%x$"), "only numbers, ids and fixed tokens: " .. line)
end)

T.test("State: three professions at skill 300 stay short enough to paste", function()
    World.patch("C_SpellBook.IsSpellKnown", function() return false end)
    MapWorld.begin({ zone = 1411, level = 60, side = "Horde" })
    local professions = {}
    for _, line in ipairs({ 164, 165, 171 }) do
        local known = {}
        for id in pairs(CP.Guides[line].recipes) do known[#known + 1] = id end
        professions[line] = { rank = 300, max = 300, known = known }
    end
    CraftWorld.begin({ professions = professions })
    for _, line in ipairs({ 164, 165, 171 }) do
        CraftWorld.Open(line)
        CraftWorld.Close()
    end
    local line = stateLine()
    print("longest State line: " .. #line .. " characters")
    T.ok(#line < 1500, #line .. " characters")
end)

-- What a tester's report says about their setup: every loaded addon with its version, and the
-- shown windows that look like a profession window (DOCKLESS-01).

-- Three addons, two loaded, and the game's answers for them.
local function addons()
    local list = {
        { name = "ProfessionallyLost", loaded = true, version = "1.2.1" },
        { name = "SomeCraftAddon", loaded = true, version = "" },
        { name = "NotLoaded", loaded = false, version = "9" },
    }
    World.patch("C_AddOns.GetNumAddOns", function() return #list end)
    World.patch("C_AddOns.GetAddOnInfo", function(i) return list[i].name, list[i].name, "", true, "", "" end)
    World.patch("C_AddOns.IsAddOnLoaded", function(i)
        for n, a in ipairs(list) do
            if i == n or i == a.name then return a.loaded, a.loaded end
        end
        return false, false
    end)
    World.patch("C_AddOns.GetAddOnMetadata", function(i, key)
        for n, a in ipairs(list) do
            if (i == n or i == a.name) and key == "Version" then return a.version end
        end
    end)
end

T.test("the report lists every loaded addon with its version", function()
    addons()
    T.eq(table.concat(BR.Addons(), ", "), "ProfessionallyLost 1.2.1, SomeCraftAddon")
    local text = table.concat(BR.Details(), "\n")
    T.ok(text:find("Addons (2): ProfessionallyLost 1.2.1, SomeCraftAddon", 1, true), text)
end)

T.test("the report caps the addon list", function()
    addons()
    World.set(BR, "ADDONS_MAX", 1)
    T.eq(table.concat(BR.Addons(), ", "), "ProfessionallyLost 1.2.1")
end)

-- A frame for the scan: a child of UIParent with a name, a size and a shown state.
local function window(name, w, h, shown)
    return { GetName = function() return name end, GetWidth = function() return w end,
             GetHeight = function() return h end, IsVisible = function() return shown end }
end

T.test("the report names the shown windows that look like a profession window", function()
    local kids = {
        window("ProfessionsFrame", 940, 600, true),
        window("SomeAddonTradeSkillFrame", 700, 500, true),
        window("HiddenCraftFrame", 700, 500, false),
        window("CraftTooltipLine", 120, 20, true),
        window("ChatFrame1", 700, 500, true),
        window(nil, 900, 600, true),
    }
    World.set(UIParent, "GetChildren", function() return unpack(kids) end)
    T.eq(table.concat(BR.ProfessionFrames(), ", "), "ProfessionsFrame 940x600, SomeAddonTradeSkillFrame 700x500")
    local text = table.concat(BR.Details(), "\n")
    T.ok(text:find("Profession windows showing: ProfessionsFrame 940x600, SomeAddonTradeSkillFrame 700x500", 1, true), text)
end)

T.test("a frame that answers with an error is skipped, and none showing says so", function()
    local bad = window("ProfessionsFrame", 940, 600, true)
    bad.GetWidth = function() error("forbidden") end
    World.set(UIParent, "GetChildren", function() return bad end)
    T.eq(#BR.ProfessionFrames(), 0)
    T.ok(table.concat(BR.Details(), "\n"):find("Profession windows showing: none", 1, true))
end)
