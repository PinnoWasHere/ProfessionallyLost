local _, CP = ...
if CP.stopped then return end

-- What's New: the changelog's lines (CP.CHANGES, Core/Changes.lua, written from the
-- changelog at release) in Daylight UI's question box with a title and one Okay
-- (Options/Widgets.lua W.Ask). After an update it shows once, every version newer than
-- the one last read (CP.db.newsSeen) up to this one. The settings' What's New button
-- shows this version's again. A first install marks this version read and shows nothing.
--
-- The newer-version notice (Engine/Peers.lua) opens the same box, once a session.
-- Nothing opens in a fight; a note asked for there waits for its end. Without Daylight
-- UI's box the notes go to chat.

local News = {}
CP.News = News

News.KEY, News.NEWER_KEY = "proflost:news", "proflost:newer"
News.TITLE = "What's New in Professionally Lost"
News.NEWER_TITLE = "Professionally Lost"
News.OKAY = "Okay"
News.SHOWN = 1          -- versions the What's New button shows
News.AFTER_UPDATE = 3   -- most versions shown after an update
News.HIGHLIGHTS = 5    -- change lines in a note
News.DELAY = 4         -- seconds after login before the note

local function mine() return CP.Peers.Version() end
local function newer(a, b) return CP.Peers.Compare(a, b) > 0 end

-- Out of a fight -------------------------------------------------------------------

local waiting = {}

local function afterCombat(key, fn)
    if not InCombatLockdown() then return fn() end
    waiting[key] = fn
end

CP:On("PLAYER_REGEN_ENABLED", function()
    for _, key in ipairs({ News.KEY, News.NEWER_KEY }) do
        local fn = waiting[key]
        waiting[key] = nil
        if fn then fn() end
    end
end)

-- Forgets notes held for a fight's end.
function News.Reset()
    for key in pairs(waiting) do waiting[key] = nil end
end

-- The notes ------------------------------------------------------------------------

-- The notes to show, newest first. After an update: those newer than the version read,
-- up to this one (only this one when none was read). `all`: the latest News.SHOWN.
function News.Notes(all)
    local v = mine()
    local seen = not all and CP.db and CP.db.newsSeen or nil
    local out = {}
    for _, n in ipairs(CP.CHANGES or {}) do
        if seen and not newer(n.version, seen) then break end
        if not (v and newer(n.version, v)) then out[#out + 1] = n end
        if #out >= (all and News.SHOWN or seen and News.AFTER_UPDATE or 1) then break end
    end
    return out
end

-- A short note: each version in the accent with its summary. The newest version also gets
-- up to News.HIGHLIGHTS lines behind accent dots (New first, then Changed, then Fixed) and a
-- muted "and N more changes" when some were cut.
function News.Text(notes)
    local accent, muted = CP.Style.Hex(CP.Style.color.accent), CP.Style.Hex(CP.Style.color.muted)
    local parts = {}
    for i, n in ipairs(notes) do
        local lines = { accent .. n.version .. "|r" }
        if n.summary and n.summary ~= "" then lines[#lines + 1] = n.summary end
        if i == 1 then
            local all = {}
            for _, name in ipairs({ "New", "Changed", "Fixed" }) do
                for _, section in ipairs(n.sections or {}) do
                    if section[1] == name then
                        for _, line in ipairs(section[2]) do all[#all + 1] = line end
                    end
                end
            end
            if #all > 0 then lines[#lines + 1] = "" end
            for k = 1, math.min(#all, News.HIGHLIGHTS) do lines[#lines + 1] = accent .. "•|r  " .. all[k] end
            local more = #all - News.HIGHLIGHTS
            if more > 0 then lines[#lines + 1] = muted .. "and " .. more .. " more change" .. (more == 1 and "" or "s") .. "|r" end
        end
        parts[#parts + 1] = table.concat(lines, "\n")
    end
    return table.concat(parts, "\n\n")
end

-- Daylight UI's question box with a title and one Okay. False without it.
local function box(key, title, text)
    local dui = _G.DaylightUI
    local widgets = dui and dui.Widgets
    if not (widgets and type(widgets.Ask) == "function") then return false end
    return (pcall(widgets.Ask, { key = key, title = title, text = text, yes = News.OKAY, no = false }))
end

local function note(key, title, text)
    if box(key, title, text) then return end
    DEFAULT_CHAT_FRAME:AddMessage(title)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then DEFAULT_CHAT_FRAME:AddMessage(line) end
    end
end

-- Shows What's New (`all`: the latest, read or not) and marks this version read.
-- Returns whether there was anything to show.
function News.Show(all)
    local notes = News.Notes(all)
    local v = mine()
    if v and CP.db then CP.db.newsSeen = v end
    if #notes == 0 then return false end
    local text = News.Text(notes)
    afterCombat(News.KEY, function() note(News.KEY, News.TITLE, text) end)
    return true
end

-- A newer version heard ------------------------------------------------------------

-- Opens the newer-version note in Daylight UI's box. False without it: Peers prints its line.
function News.Newer(best, have)
    local dui = _G.DaylightUI
    if not (dui and dui.Widgets and type(dui.Widgets.Ask) == "function") then return false end
    local text = CP.Peers.NOTICE:format(best, have) .. "."
    afterCombat(News.NEWER_KEY, function() note(News.NEWER_KEY, News.NEWER_TITLE, text) end)
    return true
end

-- After an update ------------------------------------------------------------------

-- At load: a first install counts this version read. A player from before What's New
-- has been welcomed but read nothing, and sees this version's notes.
function News.Loaded()
    local v = mine()
    if v and CP.db and CP.db.newsSeen == nil and not CP.db.welcomed then CP.db.newsSeen = v end
end

-- After login: this version's notes once, unless the setting is off. Off still marks it read.
function News.Greet()
    local v = mine()
    if not (v and CP.db) or CP.db.newsSeen == v then return end
    if CP.Settings.Current("whatsNew") == false then
        CP.db.newsSeen = v
        return
    end
    News.Show(false)
end

CP:On("ADDON_LOADED", function(_, name)
    if name == CP.name then News.Loaded() end
end)

CP:On("PLAYER_LOGIN", function()
    C_Timer.After(News.DELAY, News.Greet)
end)
