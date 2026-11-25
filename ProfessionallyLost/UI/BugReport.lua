local _, CP = ...
if CP.stopped then return end

-- /proflost bug: a window holding a report to copy into a bug report. It carries the
-- versions, where the player is, the open profession and the guide's next rows, the
-- route, and the last Lua errors that came from ProfLost.

local BugReport = {}
CP.BugReport = BugReport

BugReport.MAX_ERRORS = 5
BugReport.ROWS = 6

-- Where reports go: the addon's forum thread on Daylight UI's Discord.
BugReport.REPORT_URL = "https://discord.gg/eeSYZDd6ar"
BugReport.SEND_TO = "Paste it in the Professionally Lost thread in Daylight UI's Discord forum:"

local errors = {}

-- Keeps errors whose text names the addon's folder, then hands every error on unchanged.
function BugReport.Capture(msg)
    if type(msg) == "string" and msg:find(CP.name, 1, true) then
        table.insert(errors, 1, msg)
        errors[BugReport.MAX_ERRORS + 1] = nil
    end
end

function BugReport.Errors() return errors end

-- Keeps a failure ProfLost handled itself (and kept out of chat) for the report's error list.
function BugReport.Record(msg)
    table.insert(errors, 1, tostring(msg))
    errors[BugReport.MAX_ERRORS + 1] = nil
end

if geterrorhandler and seterrorhandler then
    local previous = geterrorhandler()
    seterrorhandler(function(msg, ...)
        pcall(BugReport.Capture, msg)
        if previous then return previous(msg, ...) end
    end)
end

-- An addon's version, "not loaded", or "?" when the game won't say.
local function version(addon)
    if not C_AddOns then return "?" end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, addon)
    if ok and not loaded then return "not loaded" end
    local got, v = pcall(C_AddOns.GetAddOnMetadata, addon, "Version")
    return got and v or "?"
end

-- Every loaded addon as "Name version" (the name alone when it has no version), in the
-- game's order, at most ADDONS_MAX. Empty when the game won't say.
BugReport.ADDONS_MAX = 120

function BugReport.Addons()
    local out = {}
    local A = C_AddOns
    if not (A and A.GetNumAddOns and A.GetAddOnInfo and A.IsAddOnLoaded) then return out end
    local ok, n = pcall(A.GetNumAddOns)
    if not ok or type(n) ~= "number" then return out end
    for i = 1, n do
        local got, name = pcall(A.GetAddOnInfo, i)
        local on, loaded = pcall(A.IsAddOnLoaded, i)
        if got and type(name) == "string" and on and loaded and #out < BugReport.ADDONS_MAX then
            local v = version(i)
            out[#out + 1] = (v ~= "?" and v ~= "") and (name .. " " .. v) or name
        end
    end
    return out
end

-- Shown windows that look like a profession window, as "Name WxH", sorted: children of
-- UIParent at least FRAME_MIN across and tall whose name holds one of FRAME_WORDS. A
-- tester's report then says whose window showed the profession. ProfLost itself never
-- finds a profession window by name (Window.ProfessionOpen).
BugReport.FRAME_WORDS = { "profession", "tradeskill", "craft" }
BugReport.FRAME_MIN = { 250, 250 }

local function professionLike(fr)
    local shown = fr:IsVisible()
    if (issecretvalue and issecretvalue(shown)) or shown ~= true then return nil end
    local name = fr:GetName()
    if type(name) ~= "string" then return nil end
    local low, hit = name:lower(), false
    for _, word in ipairs(BugReport.FRAME_WORDS) do
        if low:find(word, 1, true) then hit = true end
    end
    if not hit then return nil end
    local w, h = fr:GetWidth(), fr:GetHeight()
    if not (type(w) == "number" and type(h) == "number") then return nil end
    if w < BugReport.FRAME_MIN[1] or h < BugReport.FRAME_MIN[2] then return nil end
    return ("%s %dx%d"):format(name, math.floor(w + 0.5), math.floor(h + 0.5))
end

function BugReport.ProfessionFrames()
    local out = {}
    local ok, kids = pcall(function() return { UIParent:GetChildren() } end)
    if not ok then return out end
    for _, fr in ipairs(kids) do
        local got, line = pcall(professionLike, fr)
        if got and line then out[#out + 1] = line end
    end
    table.sort(out)
    return out
end

local function where()
    local zone = CP.Waypoint.PlayerZone()
    if not zone then return "unknown" end
    local info = C_Map.GetMapInfo(zone)
    -- The game gives the position on the map the player stands on, not the zone's.
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    local x, y
    if pos then x, y = pos:GetXY() end
    local coords = (type(x) == "number" and type(y) == "number") and ("%.1f, %.1f"):format(x * 100, y * 100) or "?"
    return ("%s (%d) at %s"):format(info and info.name or "?", zone, coords)
end

local function rowText(row)
    local name = row.recipe and row.recipe.name or (row.rank and row.rank.name)
        or (row.gather and ("zone " .. row.gather.zone))
    if row.train then
        local names = {}
        for _, r in ipairs(row.train.recipes or {}) do names[#names + 1] = r.name end
        name = "Train " .. (#names > 0 and table.concat(names, ", ") or "recipes")
    end
    name = name or "?"
    local range = row.from and row.to and ("%d-%d"):format(row.from, row.to) or tostring(row.at or "")
    local flags = {}
    if row.side then flags[#flags + 1] = "or" end
    if row.learned == false then flags[#flags + 1] = "unlearned" end
    if row.spell then flags[#flags + 1] = "spell " .. row.spell end
    return ("  %s %s%s"):format(range, name, #flags > 0 and (" [" .. table.concat(flags, ", ") .. "]") or "")
end

-- The State line --------------------------------------------------------------------
-- One compact line that lets the developer replay a player's state headless. Only numbers, ids and short fixed tokens: no name, realm,
-- guild or free text. Grammar, version 1, with no spaces after "State: ":
--
--   State: v1;lv=<level>,side=<H|A|?>;<professions>;win=...;mode=...;held=...#<check>
--
--   <profession>  <id>:<skill>/<cap>   every profession the guide covers, by id; a crafting
--                 profession adds ,k=<ids>,src=<where>,read=<0|1>,bk=<n>
--     k     the recipe ids ProfLost plans with, sorted, each as its base 36 difference from the
--           one before (the first from 0), joined by "+"; "-" for none
--     src   live (the open window's recipe list), saved (a list read earlier, charDB.learned),
--           book (unread: ids the spellbook or a learned pattern added) or none
--     read  1 when the profession's list was read (charDB.recipesRead)
--     bk    how many guide recipes the spellbook says are known
--   win=<game|dui|mogul|none>,open=<id|->,ts=<own|other|none>
--     who shows the open profession (game: the game's or any other addon's window), the
--     profession ProfLost treats as open, and whether trade skill data is live (own, or
--     linked/guild/NPC, or none)
--   mode=<one|all>,pick=<id|->,collect=<0|1>,fishCook=<0|1|->
--     the guide's mode, the profession it shows, and the settings Plan.Current's key reads
--   held=<item>x<count>+...   or "-": what the guide's plan steps need and the bags hold
--   #<check>      four hex digits, a checksum of everything before the "#"
--
-- A change to the grammar bumps the version, and the replay tooling changes with it.
BugReport.STATE_VERSION = 1
BugReport.HELD_MAX = 30       -- items listed in held=
BugReport.COUNT_MAX = 9999    -- one count in held=

-- An integer as text, or "?".
local function whole(v)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return "?" end
    return ("%d"):format(math.floor(v))
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

-- A whole number in base 36, lower case.
local function base36(n)
    if n == 0 then return "0" end
    local out = ""
    while n > 0 do
        local d = n % 36
        out = DIGITS:sub(d + 1, d + 1) .. out
        n = (n - d) / 36
    end
    return out
end

-- Sorted, distinct whole numbers as base 36 differences ("5ww+1a+x", the first from 0)
-- joined by "+", or "-" for none.
local function idText(list)
    local out, seen = {}, {}
    for _, v in ipairs(list) do
        if type(v) == "number" and v > 0 and v == math.floor(v) and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    table.sort(out)
    local last = 0
    for i, v in ipairs(out) do
        out[i] = base36(v - last)
        last = v
    end
    return #out > 0 and table.concat(out, "+") or "-"
end

-- The checksum of `text`: a rolling sum, four hex digits.
function BugReport.StateCheck(text)
    local h = 0
    for i = 1, #text do h = (h * 31 + text:byte(i)) % 65521 end
    return ("%04x"):format(h)
end

-- The guide ids of `ids` (a list or a set's keys), as a list.
local function guideIds(guide, ids)
    local out = {}
    for _, id in ipairs(ids) do
        if guide.recipes[id] then out[#out + 1] = id end
    end
    return out
end

-- The recipe ids ProfLost plans with for profession `id`, and where they came from.
local function believed(id, guide, openId)
    local Prof, Plan = CP.Professions, CP.Plan
    local read = Plan.Read(id)
    if openId == id and Prof.IsOwn() then
        local recipes = Prof.Recipes(Prof.Current())
        local learned = Prof.Learned(recipes)
        Plan.Alias(guide, recipes, learned)
        local list = {}
        for spell in pairs(learned) do list[#list + 1] = spell end
        return guideIds(guide, list), "live", read
    end
    local list = guideIds(guide, CP.charDB and CP.charDB.learned and CP.charDB.learned[id] or {})
    return list, read and "saved" or (#list > 0 and "book" or "none"), read
end

local function professionPart(id, skill, cap, openId)
    local part = ("%s:%s/%s"):format(whole(id), whole(skill), whole(cap))
    local guide = CP.Guides and CP.Guides[id]
    if not guide then return part end
    local list, src, read = believed(id, guide, openId)
    local book = 0
    for spell in pairs(guide.recipes) do
        if CP.Professions.SpellKnown(spell) == true then book = book + 1 end
    end
    return ("%s,k=%s,src=%s,read=%d,bk=%d"):format(part, idText(list), src, read and 1 or 0, book)
end

-- Every profession the guides cover that the character has: { id, skill, cap }, by id.
local function professions()
    local ids = {}
    for id in pairs(CP.Guides or {}) do ids[#ids + 1] = id end
    for id in pairs(CP.Launcher and CP.Launcher.GATHER_NAMES or {}) do
        if not (CP.Guides and CP.Guides[id]) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local out = {}
    if not (CP.Professions.preview or (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID)) then return out end
    for _, id in ipairs(ids) do
        local info = CP.Professions.SkillLine(id)
        if info and not info.isHeader then
            local skill = (info.rank or 0) + (info.modifier or 0)
            if skill > 0 then out[#out + 1] = { id, skill, info.maxRank or skill } end
        end
    end
    return out
end

local WINDOW = { daylight = "dui", mogul = "mogul", game = "game" }

-- What the guide's plan needs that the bags and bank hold: "<item>x<count>+...", or "-".
local function heldText()
    local live = CP.GuideTab and CP.GuideTab.ui and CP.GuideTab.ui.live
    local guide = live and live.guide
    if not (guide and live.plan) then return "-" end
    local items, seen = {}, {}
    for _, st in ipairs(live.plan) do
        local r = st.spell and guide.recipes[st.spell]
        for _, pair in ipairs(r and r.reagents or {}) do
            if not seen[pair[1]] then
                seen[pair[1]] = true
                items[#items + 1] = pair[1]
            end
        end
    end
    table.sort(items)
    local out = {}
    for _, item in ipairs(items) do
        local n = C_Item.GetItemCount(item, true)
        if type(n) == "number" and n > 0 and #out < BugReport.HELD_MAX then
            out[#out + 1] = ("%sx%s"):format(whole(item), whole(math.min(n, BugReport.COUNT_MAX)))
        end
    end
    return #out > 0 and table.concat(out, "+") or "-"
end

local function flag(v)
    if v == nil then return "-" end
    return v and "1" or "0"
end

-- The State line (see the grammar above), or nil when the game would not say.
function BugReport.State()
    local Prof, Window, Host = CP.Professions, CP.Window, CP.Host
    local side = ({ Horde = "H", Alliance = "A" })[UnitFactionGroup("player")] or "?"
    local openId = Window.ProfessionOpen() and Window.OpenID() or nil
    local parts = { "v" .. BugReport.STATE_VERSION, ("lv=%s,side=%s"):format(whole(UnitLevel("player")), side) }
    for _, p in ipairs(professions()) do parts[#parts + 1] = professionPart(p[1], p[2], p[3], openId) end
    local holder = Host.Holder()
    parts[#parts + 1] = ("win=%s,open=%s,ts=%s"):format(WINDOW[holder or ""] or "none", openId and whole(openId) or "-",
        Prof.IsOwn() and "own" or (Prof.Current() and "other" or "none"))
    local chosen = Window.ChosenID()
    parts[#parts + 1] = ("mode=%s,pick=%s,collect=%s,fishCook=%s"):format(Window.Mode(), chosen and whole(chosen) or "-",
        CP.db and CP.db.collect == false and "0" or "1", flag(CP.db and CP.db.fishCook))
    parts[#parts + 1] = "held=" .. heldText()
    local body = table.concat(parts, ";")
    return ("State: %s#%s"):format(body, BugReport.StateCheck(body))
end

-- What the report fills in by itself, as lines of plain text.
function BugReport.Details()
    local out = {}
    -- Each line a bullet; a line starting with two spaces sits under the one before.
    local function add(s)
        out[#out + 1] = s:sub(1, 2) == "  " and ("  - " .. s:sub(3)) or ("- " .. s)
    end
    local build, buildNo = GetBuildInfo()
    add(("Professionally Lost %s · Daylight UI %s · DaylightMogul %s · game %s (%s)"):format(
        version(CP.name), version("DaylightUI"), version("DaylightMogul"), tostring(build), tostring(buildNo)))
    local addons = BugReport.Addons()
    add(("Addons (%d): %s"):format(#addons, #addons > 0 and table.concat(addons, ", ") or "the game won't say"))
    local frames = BugReport.ProfessionFrames()
    add("Profession windows showing: " .. (#frames > 0 and table.concat(frames, ", ") or "none"))
    if CP.db and CP.db.newestSeen then
        add("Newest Professionally Lost seen from other players: " .. tostring(CP.db.newestSeen))
    end
    add(("%s level %s · %s"):format(tostring(UnitFactionGroup("player")), tostring(UnitLevel("player")), where()))

    local Prof = CP.Professions
    local p = Prof and Prof.Current()
    if p then
        add(("Profession: %s %d/%d · mode %s"):format(p.name or "?", p.skill or 0, p.max or 0,
            CP.db and CP.db.collect == false and "Buy" or "Level-as-you-go"))
    else
        add("Profession: none open")
    end

    local ok, state = pcall(BugReport.State)
    add(ok and state or "State: unavailable")

    local rows = CP.GuideTab and CP.GuideTab.ui and CP.GuideTab.ui.rows or {}
    if #rows > 0 then
        add("Guide rows:")
        for i = 1, math.min(#rows, BugReport.ROWS) do add(rowText(rows[i])) end
    end

    if CP.db and CP.db.route ~= false then
        local status = CP.RouteMap and CP.RouteMap.Status and CP.RouteMap.Status()
        add(("Route: on, %s%s"):format(CP.GatherList.MODE_LABEL[CP.db.routeMode or "level"] or CP.db.routeMode, status and (" · " .. status) or ""))
    end

    if #errors > 0 then
        add("Recent errors:")
        for _, e in ipairs(errors) do add("  " .. e:gsub("\n", " | ")) end
    else
        add("Recent errors: none")
    end
    return out
end

-- The whole report: the player's answers first, then the details.
-- `answers` = { happened = text, expected = text }.
function BugReport.Text(answers)
    answers = answers or {}
    local function said(v) return (type(v) == "string" and v:match("%S")) and v or "(not filled in)" end
    local out = { "Professionally Lost bug report", "", "What happened:", said(answers.happened), "",
                  "What I expected:", said(answers.expected), "", "Details:" }
    for _, line in ipairs(BugReport.Details()) do out[#out + 1] = line end
    return out
end

-- The window -----------------------------------------------------------------------
-- Two boxes for the player's words, the details filled in, and Select report, which
-- puts the whole report in the details box and selects it for Ctrl+C. Addons can't
-- write to the clipboard: CopyToClipboard is protected.

local frame
local WIDTH, BOX_H, URL_H = 520, 58, 28
BugReport.STRATA = "FULLSCREEN_DIALOG"

-- A framed multi-line text box; `height` 0 leaves its size to its anchors.
local function textBox(parent, height)
    local S = CP.Style
    local holder = CreateFrame("Frame", nil, parent)
    if height > 0 then holder:SetHeight(height) end
    S.Control(holder)
    local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetWidth(WIDTH - 70)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    S.FrameScroll("bug report", scroll, holder)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)
    holder.box = box
    return holder
end

-- Makes `holder`'s box a read-only copy field: a click selects `text()`, and a keystroke
-- puts it back, still selected.
local function copyField(holder, text)
    local box = holder.box
    local function select()
        box:SetFocus()
        box:HighlightText()
    end
    box:SetText(text())
    box:SetScript("OnMouseDown", select)
    holder:SetScript("OnMouseDown", select)
    box:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        self:SetText(text())
        self:HighlightText()
    end)
end

local function label(parent, text, anchor, y)
    local S = CP.Style
    local fs = S.Text(parent, "body", S.color.label)
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
    fs:SetText(text)
    return fs
end

local function build()
    local S = CP.Style
    frame = CreateFrame("Frame", "ProfLost_BugReport", UIParent)
    frame:SetSize(WIDTH, 530)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    S.Shell(frame, nil, true)
    tinsert(UISpecialFrames, "ProfLost_BugReport")

    local title = S.Text(frame, "head", S.color.title)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Report a bug")

    local l1 = label(frame, "What happened?", title, -12)
    frame.happened = textBox(frame, BOX_H)
    frame.happened:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 0, -4)
    frame.happened:SetPoint("RIGHT", -14, 0)

    local l2 = label(frame, "What did you expect?", frame.happened, -10)
    frame.expected = textBox(frame, BOX_H)
    frame.expected:SetPoint("TOPLEFT", l2, "BOTTOMLEFT", 0, -4)
    frame.expected:SetPoint("RIGHT", -14, 0)

    local l3 = label(frame, "Details (filled in for you)", frame.expected, -10)
    frame.details = textBox(frame, 0)
    frame.details:SetPoint("TOPLEFT", l3, "BOTTOMLEFT", 0, -4)
    frame.details:SetPoint("BOTTOMRIGHT", -14, 48 + URL_H + 26)
    -- A click in the details does what Select report does.
    frame.details.box:SetScript("OnMouseDown", function() BugReport.Select() end)
    frame.details:SetScript("OnMouseDown", function() BugReport.Select() end)
    -- Read-only: a keystroke puts the text back, still selected for copying.
    frame.details.box:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        self:SetText(frame.shown or "")
        self:HighlightText()
    end)

    -- Where to send it, in a field that selects for Ctrl+C like the report.
    frame.url = textBox(frame, URL_H)
    frame.url:SetPoint("BOTTOMLEFT", 14, 48)
    frame.url:SetPoint("BOTTOMRIGHT", -14, 48)
    copyField(frame.url, function() return BugReport.REPORT_URL end)
    frame.sendTo = S.Text(frame, "body", S.color.label)
    frame.sendTo:SetPoint("BOTTOMLEFT", frame.url, "TOPLEFT", 0, 4)
    frame.sendTo:SetText(BugReport.SEND_TO)

    frame.hint = S.Text(frame, "small", S.color.muted)
    frame.hint:SetPoint("BOTTOMLEFT", 14, 18)
    frame.hint:SetText("")

    local close = S.Button(frame, 80)
    close:SetPoint("BOTTOMRIGHT", -14, 12)
    close.label:SetText("Close")
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.select = S.Button(frame, 120)
    frame.select:SetPoint("RIGHT", close, "LEFT", -8, 0)
    frame.select.label:SetText("Select report")
    frame.select:SetScript("OnClick", function() BugReport.Select() end)

    local clear = S.Button(frame, 70)
    clear:SetPoint("RIGHT", frame.select, "LEFT", -8, 0)
    clear.label:SetText("Clear")
    clear:SetScript("OnClick", function() BugReport.Clear() end)
end

-- Above every window, Daylight UI's options included (a toplevel DIALOG): the strata
-- its own profile box takes (Profiles.lua), toplevel, and raised on each opening.
local function lift()
    frame:SetFrameStrata(BugReport.STRATA)
    frame:SetToplevel(true)
    frame:Raise()
end

local function showDetails(text)
    frame.shown = text
    frame.details.box:SetText(text)
end

-- Empties both answers and puts the details back.
function BugReport.Clear()
    if not frame then build() end
    frame.happened.box:SetText("")
    frame.expected.box:SetText("")
    frame.copied = nil
    showDetails(table.concat(BugReport.Details(), "\n"))
    frame.hint:SetText("")
end

-- Opens the form with fresh details. What the player typed stays, so closing it by
-- accident loses nothing, until a report is selected for copying: the next opening
-- then starts empty. Returns the details text.
function BugReport.Show()
    if not frame then build() end
    if frame.copied then BugReport.Clear() end
    local text = table.concat(BugReport.Details(), "\n")
    showDetails(text)
    frame.hint:SetText("")
    lift()
    frame:Show()
    frame.happened.box:SetFocus()
    return text
end

-- Puts the whole report, answers included, in the details box and selects it.
-- Returns the report text.
function BugReport.Select()
    if not frame then build() end
    local text = table.concat(BugReport.Text({
        happened = frame.happened.box:GetText(), expected = frame.expected.box:GetText(),
    }), "\n")
    showDetails(text)
    frame.copied = true
    frame.details.box:SetFocus()
    frame.details.box:HighlightText()
    frame.hint:SetText("Selected: press Ctrl+C to copy")
    return text
end
