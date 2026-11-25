local _, CP = ...
if CP.stopped then return end

-- /proflost preview: a developer's look at ProfLost's windows as a character with another
-- profession would see them.
--
-- The preview character has one profession, at a chosen skill, knowing the guide's
-- trainer and starting recipes up to it. Professions.SkillLine and Sourcing.PlayerSkills
-- answer for it. CP.db becomes a copy and CP.charDB a fresh character's table, so nothing
-- the addon writes meanwhile reaches the saved variables. Crafting, buying, learning and
-- the profession window need a real character: each refuses with one chat line.
-- Session only: a reload or logout drops it, and the saved globals were never touched.

local Prof = CP.Professions
local Preview = {}
CP.Preview = Preview

Preview.DEFAULT_LINE = 333     -- `/proflost preview on` with nothing previewed yet: Enchanting
Preview.DEFAULT_SKILL = 1      -- a preview named without a skill starts here
Preview.SKILL_MAX = 300
Preview.RANK = 75              -- each trained rank lifts the cap this far
Preview.DE_SAMPLES = 6         -- sample items on an Enchanting preview's Disenchant tab
Preview.DE_CANDIDATES = 24     -- data items tried for them, so loading items can't stall the tab
Preview.SAMPLE_BAG = -1        -- the bag a sample sits in: none

Preview.MARKER = "Preview: %s %d"
Preview.ACTIONS = {
    open = "Opening a profession window", craft = "Crafting", enchant = "Enchanting",
    learn = "Learning a pattern", buy = "Buying", disenchant = "Disenchanting",
}

-- What the preview stands in for: the saved tables, the vendor watch's session notes and the
-- gathering panel's Next up fold. `/proflost preview off` puts them all back.
local real
local last   -- { line, skill }: this session's last preview

-- Every profession ProfLost knows: { [line] = name }.
function Preview.Names()
    local out = {}
    for line, guide in pairs(CP.Guides or {}) do out[line] = guide.name end
    for line, name in pairs(CP.Launcher and CP.Launcher.GATHER_NAMES or {}) do out[line] = out[line] or name end
    return out
end

-- The profession `word` names, letters only and any case: its whole name, else the one
-- name it starts. Nil and the names it could mean when it names none or several.
function Preview.Find(word)
    local key = (word or ""):lower():gsub("[^%a]", "")
    if key == "" then return nil, {} end
    local hits = {}
    for line, name in pairs(Preview.Names()) do
        local full = name:lower():gsub("[^%a]", "")
        if full == key then return line end
        if full:sub(1, #key) == key then hits[#hits + 1] = name end
    end
    table.sort(hits)
    if #hits == 1 then
        for line, name in pairs(Preview.Names()) do
            if name == hits[1] then return line end
        end
    end
    return nil, hits
end

-- The cap a character at `skill` has with every rank trained it can reach.
function Preview.Cap(skill)
    return math.min(Preview.SKILL_MAX, (math.floor(skill / Preview.RANK) + 1) * Preview.RANK)
end

-- The guide recipes of profession `line` a character at `skill` knows: trainer and
-- starting recipes it can learn there. A set and a sorted list.
function Preview.Known(line, skill)
    local set, list = {}, {}
    local guide = CP.Guides and CP.Guides[line]
    for id, r in pairs(guide and guide.recipes or {}) do
        if (r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= skill then
            set[id] = true
            list[#list + 1] = id
        end
    end
    table.sort(list)
    return set, list
end

-- A copy of `t` and every table in it.
local function copy(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do out[copy(k, seen)] = copy(v, seen) end
    return out
end
Preview.Copy = copy

-- True while a preview is on.
function Preview.On()
    return Prof.preview ~= nil
end

-- "Preview: Enchanting 150" while a preview is on, else nil.
function Preview.Marker()
    local pv = Prof.preview
    return pv and Preview.MARKER:format(pv.name, pv.skill) or nil
end

-- Every cache that read the old character drops, and the windows draw the new one.
local function settle()
    Prof.DropRecipes()
    if CP.Plan then
        CP.Plan.Invalidate()
        CP.Plan.ForgetBook()
    end
    if CP.GuideTab then CP.GuideTab.Forget() end
    if CP.Window then
        CP.Window.CancelPick()
        CP.Window.ForgetFollow()
    end
    Prof.SkillsMoved()
    CP:Emit("ProfLost_SKILLS")
    if CP.Gather then CP.Gather.UpdateAllNeeds() end
    CP:Emit("ProfLost_NEEDS")

    -- The patterns a crafting preview could buy, as its window's last open would have saved
    -- them, so the zone's vendors show; the zone's list is read again either way.
    local pv = Prof.preview
    local live = pv and CP.Guides and CP.Guides[pv.line] and CP.Plan and CP.Plan.Shut(pv.line)
    if live and CP.VendorWatch then CP.VendorWatch.Update(live) end
    if CP.VendorWatch then CP.VendorWatch.Recheck() end
    if CP.Launcher then CP.Launcher.Update() end
    if CP.Window then CP.Window.Update() end
    if CP.GatherList then CP.GatherList.Changed() end
    CP.Panel:Refresh()
    -- The header's marker line, shown or hidden.
    CP.Panel.LayoutTitle()
end

-- Starts a preview of profession `line` at `skill` (default DEFAULT_SKILL, held to
-- 1-SKILL_MAX), or switches to it. Each start begins from the real tables again. False
-- for a profession ProfLost doesn't know, before the saved variables load, and in combat,
-- where the Disenchant button keeps its aim until the fight ends.
function Preview.Start(line, skill)
    local name = Preview.Names()[line]
    if not (name and CP.db and CP.charDB) then return false end
    if InCombatLockdown() then
        CP:Print("preview: not in combat. Try again once the fight ends.")
        return false
    end
    skill = math.max(1, math.min(Preview.SKILL_MAX, math.floor(tonumber(skill) or Preview.DEFAULT_SKILL)))
    real = real or { db = CP.db, charDB = CP.charDB, notes = CP.VendorWatch and CP.VendorWatch.Notes(),
                     nextOpen = CP.GatherList and CP.GatherList.nextOpen }
    local known, list = Preview.Known(line, skill)
    Prof.preview = { line = line, name = name, skill = skill, max = Preview.Cap(skill), known = known }
    last = { line = line, skill = skill }

    -- The account's settings and places, with sharing off: a preview's data is no one's.
    local db = copy(real.db)
    db.shareOff, db.windowClosed = true, nil
    CP.db = db

    -- A new character with this profession, its known recipes already read.
    local char = { guideMode = "one", guideProf = line, lastProf = line }
    if CP.Guides and CP.Guides[line] then
        char.learned, char.recipesRead = { [line] = list }, { [line] = true }
    end
    CP.charDB = char

    settle()
    CP:Print(("previewing %s %d (cap %d). Nothing is saved while it is on; crafting, buying and learning are off. /proflost preview off ends it.")
        :format(name, skill, Prof.preview.max))
    return true
end

-- `/proflost preview on`: the session's last preview again, else DEFAULT_LINE.
function Preview.Resume()
    local l = last or { line = Preview.DEFAULT_LINE, skill = Preview.DEFAULT_SKILL }
    return Preview.Start(l.line, l.skill)
end

-- Ends the preview and puts the real tables back. `quiet` prints nothing. False when no
-- preview was on.
function Preview.Stop(quiet)
    if not real then
        if not quiet then CP:Print("preview: no preview is on.") end
        return false
    end
    local was = Prof.preview
    Prof.preview = nil
    CP.db, CP.charDB = real.db, real.charDB
    if real.notes then CP.VendorWatch.SetNotes(real.notes) end
    if CP.GatherList then CP.GatherList.nextOpen = real.nextOpen end
    real = nil
    settle()
    if not quiet then CP:Print(("preview of %s %d ended; your own professions are back."):format(was.name, was.skill)) end
    return true
end

-- Forgets the preview without touching CP.db or CP.charDB, as a load starts
-- (CP.LoadSaved sets both right after).
function Preview.Drop()
    Prof.preview, real, last = nil, nil, nil
end

-- `/proflost preview <profession> [skill]`, or the forms and the state for anything else.
function Preview.Command(args)
    local words = {}
    for w in (args or ""):gmatch("%S+") do words[#words + 1] = w end
    local skill = tonumber(words[#words] or "")
    if skill then table.remove(words) end
    local word = table.concat(words, " ")
    if word == "" then
        local now = Preview.Marker()
        CP:Print(("preview: /proflost preview <profession> [skill], /proflost preview on, /proflost preview off. Now: %s.")
            :format(now and now:gsub("^Preview: ", "") or "off"))
        return false
    end
    local line, hits = Preview.Find(word)
    if not line then
        CP:Print(("preview: %s names %s."):format(word, #hits > 0 and table.concat(hits, " or ") or "no profession"))
        return false
    end
    return Preview.Start(line, skill)
end

-- Says why `what` (a Preview.ACTIONS key) can't happen while a preview is on. True when
-- it refused, so the caller stops; false with no preview.
function Preview.Refuse(what)
    local pv = Prof.preview
    if not pv then return false end
    CP:Print(("%s isn't possible in a preview of %s %d. /proflost preview off ends it.")
        :format(Preview.ACTIONS[what] or "That", pv.name, pv.skill))
    return true
end

-- The Disenchant tab's samples ------------------------------------------------------

-- Disenchant data items in the highest item-level band of each quality and kind that
-- `skill` reaches, ascending, at most DE_CANDIDATES. Kept per skill.
local candidates = {}

function Preview.Candidates(skill)
    if candidates[skill] then return candidates[skill] end
    local D, DE = CP.DisenchantData, CP.Disenchant
    local want = {}
    for quality, kinds in pairs(D.bands) do
        for _, bands in pairs(kinds) do
            local lo, best = 0, nil
            for _, b in ipairs(bands) do
                local need = DE.Skill(lo + 1, quality)
                if need and need <= skill then best = b[2] end
                lo = b[1]
            end
            if best then want[best] = true end
        end
    end
    local ids = {}
    for id, group in pairs(D.items) do
        if want[group] then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for i = #ids, Preview.DE_CANDIDATES + 1, -1 do ids[i] = nil end
    candidates[skill] = ids
    return ids
end

-- Up to DE_SAMPLES items an Enchanting preview's character could disenchant, shaped as
-- Disenchant.Bags gives bag items, in no bag (SAMPLE_BAG). Items still loading are asked
-- for and join on a later draw. Empty for any other preview.
function Preview.DisenchantSamples()
    local pv = Prof.preview
    if not (pv and pv.line == CP.Disenchant.ENCHANTING) then return {} end
    local out = {}
    for _, id in ipairs(Preview.Candidates(pv.skill)) do
        if #out >= Preview.DE_SAMPLES then break end
        local name, link, quality, ilvl, _, _, _, _, _, icon, vendor, classID = C_Item.GetItemInfo(id)
        if name then
            local need = CP.Disenchant.Skill(ilvl or 0, quality)
            if need and need <= pv.skill then
                out[#out + 1] = { bag = Preview.SAMPLE_BAG, slot = #out + 1, itemID = id, name = name, link = link,
                    quality = quality, ilvl = ilvl or 0, classID = classID, vendor = vendor or 0, icon = icon,
                    sample = true }
            end
        else
            CP.RequestItem(id)
        end
    end
    return out
end
