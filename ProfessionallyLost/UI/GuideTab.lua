local _, CP = ...
if CP.stopped then return end

-- Guide tab. One mode: profession header and skill bar, the guide steps from the
-- player's skill on, and a details box for the picked step with its materials and
-- craft buttons. Clicking a step picks it. All mode: a short card per guided
-- profession with its current step; clicking a card switches to One on it. The folded
-- window shows this tab without the step list.

local S = CP.Style
local Prof = CP.Professions
local ROW_H = 24
local DETAIL_H = 198
local REAGENT_ROWS = 6
local COOKING = 185
local LIST_TOP = -44
local BAR_TOP = -26
local LIST_GAP = 8   -- between the step list and the details box

local ui = {}
CP.GuideTab = { ui = ui }  -- read by other tabs and tests: `ui.rows` holds the last rows drawn

-- px between a step card material's tag and the have / need count right of it.
CP.GuideTab.COUNT_GAP = 6
local skill = 0     -- player's skill at the last refresh
local profID        -- the profession the guide last drew

-- The picked row's `key` per profession id. It lives in the character's saved variables,
-- so a switch or a reload keeps it. A key the plan no longer holds falls back to the
-- current step when the list is next drawn (refreshOne).
local memo = {}
local function picks()
    if not CP.charDB then return memo end
    CP.charDB.guidePicks = CP.charDB.guidePicks or {}
    return CP.charDB.guidePicks
end
local function pickOf(id) return id and picks()[id] or nil end

-- The last pick the fallback replaced, per profession id: { key, skill }. A setting switched
-- off and on again re-plans without the picked step and then with it; at the same skill the
-- pick comes back. The player's own pick clears it.
local displaced = {}
local function setPick(id, key)
    if not id then return end
    picks()[id] = key
    displaced[id] = nil
end

local function diffColor(d) return S.difficulty[d] or S.difficulty[3] end
local difficultyAt = Prof.DifficultyAt

local button, setEnabled = S.Button, S.SetEnabled

-- A plain container that draws nothing: the One and All views, the impromptu area and its rows.
local function container(parent) return CreateFrame("Frame", nil, parent) end
local layoutCard   -- the step card's stacking, with its layout below

-- Gathering guides ------------------------------------------------------------

local GG = CP.GatherGuide
local PROF_NAME = { [182] = "Herbalism", [186] = "Mining", [393] = "Skinning", [356] = "Fishing" }

local function zoneName(zone)
    local info = zone and C_Map.GetMapInfo(zone)
    return info and info.name or "?"
end

-- The gathering skill line of the open profession, or nil.
local function gatherLine(p)
    for _, id in ipairs(p.ids or { p.id }) do
        if GG.Has(id) then return id end
    end
end

local function isGatherRow(row)
    return row.gather or row.fish or row.gatherRank or row.fishRank
end

-- A rank row's waypoint: a stand-in guide holding the NPC table, and a target naming
-- the rank's NPCs. Nil for other rows.
local function rankTarget(row)
    if row.gatherRank then
        return { npcs = CP.GatherData.rankNpcs or {} },
            { name = row.gatherRank.name .. " trainer", npcs = row.gatherRank.npcs }
    elseif row.fishRank then
        return { npcs = CP.GatherData.fishing.npcs or {} }, { name = row.name, npcs = row.fishRank.npcs }
    end
end

-- Title and where-to text for a rank row.
local function rankText(row)
    if row.gatherRank then
        local r = row.gatherRank
        return ("Train %s %s"):format(r.name, PROF_NAME[ui.line] or ""), ("at a trainer  ·  level %d"):format(r.level)
    end
    local r = row.fishRank
    -- What learning it needs: "Fishing 125  ·  level 20".
    local needs = {}
    if r.at and r.at > 0 then needs[#needs + 1] = ("Fishing %d"):format(r.at) end
    if r.level and r.level > 0 then needs[#needs + 1] = ("level %d"):format(r.level) end
    local tail = #needs > 0 and ("  ·  " .. table.concat(needs, "  ·  ")) or ""
    if r.kind == "book" then return "Buy the " .. row.name .. " book", "from a vendor" .. tail end
    if r.kind == "quest" then return row.name .. " quest", "from a quest giver" .. tail end
    return "Train " .. row.name, "at a trainer" .. tail
end
CP.GuideTab.RankText = rankText

-- Where a gather or fishing row's waypoint goes: { zone, x, y, name } or nil.
local function gatherSpot(row)
    if row.gather then
        local spot = GG.Spot(row.gather.zone, row.gather.targets)
        return spot and { zone = row.gather.zone, x = spot.x, y = spot.y, name = spot.name }
    elseif row.fish then
        local spot = CP.Fishing.Spot(row.fish.zone)
        return { zone = row.fish.zone, x = spot and spot[1] or 0.5, y = spot and spot[2] or 0.5,
                 name = spot and "Fishing pool" or "Fishing" }
    end
end

local function gatherPin(row)
    local guide, target = rankTarget(row)
    if guide then return CP.Waypoint.ToRecipe(guide, target) end
    local spot = gatherSpot(row)
    if spot then CP.Waypoint.PlaceOnMap(spot.zone, spot.x, spot.y, spot.name) end
end

local function setCraftShown(shown)
    local d = ui.details
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do b:SetShown(shown) end
end

-- A card with nothing of ours crafting (a stop, a gathering step, an enchant) never keeps
-- the making strip an earlier row left up.
local function noStrip()
    ui.details.making:Hide()
end

-- A craft button's hover text, when it has one: only the reason it is greyed out.
local function craftTip(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

-- Craft all crafts what the step still needs, not every craft the bags allow. Its hover
-- text says so, or, while greyed, what is missing.
CP.GuideTab.CRAFT_ALL_TIP = "Crafts %d, what this step still needs. Not every craft your materials allow."

-- "Need 6 more Heavy Leather, 2 more Coarse Thread" for `crafts` crafts of `reagents`
-- (Prof.Reagents' rows), or nil when the bags hold enough.
function CP.GuideTab.MissingText(reagents, crafts)
    local parts = {}
    for _, m in ipairs(reagents or {}) do
        local short = (m.need or 0) * crafts - (m.have or 0)
        if short > 0 then parts[#parts + 1] = ("%d more %s"):format(short, m.name or ("item " .. tostring(m.itemID))) end
    end
    if #parts == 0 then return nil end
    return "Need " .. table.concat(parts, ", ")
end

-- Craft all's hover text for a step of `crafts` crafts: `ready` while it can run.
function CP.GuideTab.CraftAllTip(crafts, ready, reagents)
    local missing = not ready and CP.GuideTab.MissingText(reagents, crafts)
    return missing or CP.GuideTab.CRAFT_ALL_TIP:format(crafts)
end

-- Back to plain craft buttons: no Open or Learn target, no hover text, each at its width.
CP.GuideTab.CRAFT_ALL_W = 96
CP.GuideTab.CRAFT_W = { 56, 100, CP.GuideTab.CRAFT_ALL_W }   -- Craft 1, Available, Craft all

local function craftReset(d)
    for i, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do
        b.openTo, b.learnTo, b.tip, b.usePattern = nil, nil, nil, nil
        b:SetWidth(CP.GuideTab.CRAFT_W[i])
    end
end

-- The Learn button's hover text: only when it is greyed out, how to learn the recipe
-- without a waypoint.
local function learnTip(guide, recipe, target, gate)
    if gate and gate.tip and not gate.early then return gate.tip end
    if target then return nil end
    return CP.Guide.LearnText(recipe, guide)
end
CP.GuideTab.LearnTip = learnTip

-- The learn button's words for an unlearned recipe with nothing blocking it: where its
-- waypoint goes.
CP.GuideTab.LEARN_LABELS = { trainer = "Go to trainer", vendor = "Go to vendor", other = "Learn" }

-- The All card button for a rank step, by who Guide.WaypointFor says to see.
CP.GuideTab.GO_LABELS = { ["trainer"] = "Go to trainer", ["book vendor"] = "Go to vendor",
                          ["quest giver"] = "Go to quest giver" }

function CP.GuideTab.LearnLabel(recipe)
    local L = CP.GuideTab.LEARN_LABELS
    if not recipe then return L.other end
    if CP.Guide.SourceWord(recipe) == "trainer" then return L.trainer end
    if recipe.src == "vendor" or recipe.src == "reputation" then return L.vendor end
    return L.other
end

-- With the recipe not learned yet, one Go to trainer (or vendor) button stands where Craft
-- all was, whether the window is open or shut. It sets a waypoint to the nearest trainer
-- that teaches the recipe or vendor that sells its pattern, the details pin's target. It
-- opens nothing. A gate's reason (At N, Train <rank>, Level N) takes its place while greyed.
-- The recipe's pattern is in the bags: "Learn pattern", whose click uses it through the
-- secure overlay (PatternLearn.Enter on hover). Not learnable yet, its gate (At N, Level N)
-- greyed; in combat, greyed with the reason.
local function patternState(d, row, item)
    local PL = CP.PatternLearn
    local gate = PL.Gate(row.recipe, ui.live and ui.live.prof)
    local b = d.craftAll
    b.enchantRow, b.recipeID, b.count, b.openTo, b.learnTo = nil, nil, 0, nil, nil
    b.usePattern = { spell = row.spell, item = item }
    local combat = InCombatLockdown()
    b.tip = gate and gate.tip or (combat and PL.COMBAT_TIP) or nil
    b.label:SetText(gate and gate.label or PL.LABEL)
    b:SetWidth(math.max(CP.GuideTab.CRAFT_ALL_W, CP.Panel.TextWidth(b.label) + S.BUTTON_PAD))
    setEnabled(b, not gate and not combat)
end

-- The pattern is held in the bank or mail, not the bags: the button is greyed and says to fetch it.
CP.GuideTab.FETCH_LABEL = "Fetch pattern"
CP.GuideTab.FETCH_TIP = "Take the pattern out of your bank or mailbox, then use it."

-- Where a held pattern is, for the card's status line.
CP.GuideTab.WHERE_LINE = { bags = "In your bags", bank = "In your bank", mail = "In your mail", bought = "Bought already" }

function CP.GuideTab.PatternWhere(item)
    if CP.PatternLearn.InBags(item) > 0 then return "bags" end
    if (C_Item.GetItemCount(item, true) or 0) > 0 then return "bank" end
    if CP.Purchases.InMail(item) > 0 then return "mail" end
    return "bought"
end

-- "In your bank  ·  skill 100" for a recipe whose pattern the player holds.
function CP.GuideTab.HeldLine(recipe)
    return ("%s  ·  skill %d"):format(CP.GuideTab.WHERE_LINE[CP.GuideTab.PatternWhere(recipe.pattern)], recipe.learn or 1)
end

local function fetchState(d, row)
    local b = d.craftAll
    b.enchantRow, b.recipeID, b.count, b.openTo, b.learnTo, b.usePattern = nil, nil, 0, nil, nil, nil
    b.tip = CP.GuideTab.FETCH_TIP
    b.label:SetText(CP.GuideTab.FETCH_LABEL)
    b:SetWidth(math.max(CP.GuideTab.CRAFT_ALL_W, CP.Panel.TextWidth(b.label) + S.BUTTON_PAD))
    setEnabled(b, false)
end

local function learnState(d, row)
    local prof = ui.live and ui.live.prof
    d.making:Hide()
    d.craftOne:Hide()
    d.craftAvail:Hide()
    d.craftAll:Show()
    local item = row.recipe and row.recipe.pattern
    if item and CP.PatternLearn.InBags(item) > 0 then return patternState(d, row, item) end
    if CP.GuideTab.PatternOwned(row.recipe, false) then return fetchState(d, row) end
    local target, who = CP.Guide.WaypointFor(row, prof)
    local gate = CP.Guide.LearnGate(row.recipe, prof)
    local b = d.craftAll
    b.enchantRow, b.recipeID, b.count, b.openTo = nil, nil, 0, nil
    b.learnTo, b.tip = target, learnTip(ui.guide, row.recipe, target, gate)
    b.label:SetText(gate and gate.label or CP.GuideTab.LearnLabel(row.recipe))
    b:SetWidth(math.max(CP.GuideTab.CRAFT_ALL_W, CP.Panel.TextWidth(b.label) + S.BUTTON_PAD))
    setEnabled(b, target ~= nil)
end

-- With the profession's window shut or on another profession, one Open button stands
-- where Craft all was. It opens the window on `spell`.
local function openState(d, spell)
    local why = CP.Window.OpenBlocked()
    d.making:Hide()
    d.craftOne:Hide()
    d.craftAvail:Hide()
    local b = d.craftAll
    b:Show()
    b.enchantRow, b.recipeID, b.count = nil, spell, 0
    b.openTo, b.tip = CP.Window.KeyOf(ui.live), why
    b.label:SetText("Open")
    setEnabled(b, why == nil)
end

-- Detail lines for a gather row: its targets, coloured by difficulty, then what the
-- player's crafting guides still need from them.
local function gatherLines(row)
    local b, lines, seen, list = row.gather, {}, {}, {}
    for _, t in ipairs(b.targets) do
        if GG.Chance(row.from, t.req) > 0 or GG.Chance(row.to - 1, t.req) > 0 then list[#list + 1] = t end
    end
    table.sort(list, function(x, y) return x.req > y.req end)
    for _, t in ipairs(list) do
        if not seen[t.name] then
            seen[t.name] = true
            local loot = CP.GatherData.loot[t.loot]
            lines[#lines + 1] = {
                item = loot and loot[1] and loot[1][1], label = t.name,
                count = t.level and ("lvl %d"):format(t.level) or ("skill %d"):format(t.req),
                color = diffColor(GG.Difficulty(math.max(skill, row.from), t.req)),
            }
        end
    end
    local have = function(i) return C_Item.GetItemCount(i, true) end
    for _, feed in ipairs(GG.Feeds(b.targets, CP.Gather.Needs(), have)) do
        lines[#lines + 1] = { item = feed.item, count = ("%d / %d"):format(feed.have, feed.need), tag = "guides" }
    end
    return lines
end

-- Details for a gathering row: what to gather, where, and what it feeds.
-- A gathering stretch's status line: "101-125  ·  ~60 gathers", led by "This stretch needs
-- level 50 (you're 35)" while the character's level caps it.
function CP.GuideTab.GatherStatus(row)
    local text = row.gathers and ("%d-%d  ·  ~%s gathers"):format(row.from, row.to, row.gathers)
        or ("%d-%d"):format(row.from, row.to)
    local gate = row.levelGate
    if gate and gate.need > (gate.have or 0) then text = gate.text .. ".  " .. text end
    return text
end

local function fillGatherDetails(row)
    local d = ui.details
    setCraftShown(false)
    noStrip()
    d.pin.gatherRow = row
    d.pin:Show()
    local lines = {}
    if row.gatherRank or row.fishRank then
        local title, where = rankText(row)
        d.title:SetText(title)
        d.status:SetText(("Skill %d  ·  %s"):format(row.from, where))
        d.status:SetTextColor(unpack(S.color.label))
        local guide, target = rankTarget(row)
        local npc = CP.Waypoint.NearestFor(guide, target)
        d.sale:SetText(npc and ("Nearest: %s, %s"):format(npc.name, CP.Waypoint.Describe(npc)) or "")
    elseif row.fish then
        local f = row.fish
        d.title:SetText(("Fish in %s"):format(zoneName(f.zone)))
        d.status:SetText(("%d-%d  ·  ~%d catches  ·  lands %d%%"):format(row.from, row.to, row.gathers, f.land))
        d.status:SetTextColor(unpack(S.color.label))
        for _, feed in ipairs(f.feeds or {}) do
            lines[#lines + 1] = { item = feed.item, count = ("%d / %d"):format(feed.have, feed.need), tag = "Cooking" }
        end
        local also = {}
        for i = 2, math.min(4, #(f.zones or {})) do also[#also + 1] = zoneName(f.zones[i].zone) end
        d.sale:SetText(#also > 0 and ("Also: " .. table.concat(also, ", ")) or "Any water works once every bite lands.")
    else
        local b = row.gather
        d.title:SetText(("%s in %s"):format(row.verb or "Gather", zoneName(b.zone)))
        d.status:SetText(CP.GuideTab.GatherStatus(row))
        d.status:SetTextColor(unpack(row.levelGate and S.color.warn or S.color.label))
        lines = gatherLines(row)
        local also = {}
        for _, z in ipairs(b.zones) do
            if z.zone ~= b.zone then also[#also + 1] = zoneName(z.zone) end
        end
        d.sale:SetText(#also > 0 and ("Also good: " .. table.concat(also, ", ")) or "")
        -- The "Also good" line can wrap to two lines: keep the rows above it.
        if #also > 0 then
            for i = #lines, 6, -1 do lines[i] = nil end
        end
    end
    d.title:SetTextColor(unpack(S.color.title))
    d.sale:SetTextColor(unpack(S.color.label))
    for i, line in ipairs(d.rows) do
        local l = lines[i]
        line:SetShown(l ~= nil)
        if l then
            line.itemID = l.item
            line.icon:SetTexture(l.item and C_Item.GetItemIconByID(l.item) or 134400)
            line.name:SetText(l.label or (l.item and CP.ItemName(l.item)) or "?")
            line.name:SetTextColor(unpack(l.color or S.color.label))
            line.count:SetText(l.count or "")
            line.count:SetTextColor(unpack(S.color.label))
            line.tag:SetText(l.tag or "")
            line.done:Hide()
        end
    end
    d.fish:Hide()
    layoutCard()
    d:Show()
end

-- No rows while the guide's zones build in the background; its signal redraws the tab.
local function gatherGuideRows(p, line)
    if not GG.Ready(line) then
        GG.Warm(line)
        CP.GuideTab.waitingZones = true
        return {}
    end
    return GG.PlayerRows(line, p.skill, p.max)
end

-- A gathering row's range, name and info texts.
local function gatherTexts(row)
    if row.gatherRank or row.fishRank then
        local kind = row.fishRank and row.fishRank.kind
        return tostring(row.from), (rankText(row)), kind == "book" and "buy" or kind == "quest" and "quest" or "train"
    end
    local zone = row.gather and row.gather.zone or row.fish.zone
    local what = row.gather and table.concat(GG.TargetNames(row.gather.targets, row.from, 2), ", ")
    return row.side and "" or ("%d-%d"):format(row.from, row.to),
        what and ("%s: %s"):format(zoneName(zone), what) or zoneName(zone),
        row.gathers and ("~%d"):format(row.gathers) or ""
end

local function initGatherRow(btn, row)
    btn.arrow:Hide()
    btn.orText:SetShown(row.side == true)
    btn.pin:Show()
    if row.gatherRank or row.fishRank then
        btn.name:SetTextColor(unpack(S.color.title))
        btn.info:SetTextColor(unpack(S.color.label))
        return
    end
    btn.name:SetTextColor(unpack(row.current and S.color.title or S.color.label))
    btn.info:SetTextColor(unpack(S.color.muted))
end

-- Details box -----------------------------------------------------------------

-- The step card's material row `i`. The card holds REAGENT_ROWS and grows for a recipe with more.
local function reagentRow(d, i)
    local r = CreateFrame("Frame", nil, d)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", 8, -44 - (i - 1) * 17)
    r:SetPoint("RIGHT", -8, 0)
    r:EnableMouse(true)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- The count has no width of its own, so it always shows whole. layoutCard stands the
    -- tag left of the widest count.
    r.count = S.Column(S.Text(r, "small"))
    r.count:SetPoint("RIGHT")
    r.count:SetJustifyH("RIGHT")
    r.tag = S.Column(S.Text(r, "small", S.color.label))
    r.tag:SetPoint("RIGHT", -CP.GuideTab.COUNT_GAP, 0)
    r.tag:SetJustifyH("RIGHT")
    -- A reached target: Daylight UI's tick in its ok ink where the tag stands (Style.Check).
    r.done = S.Check(r, 12)
    r.done:SetPoint("RIGHT", r.tag, "RIGHT")
    r.done:Hide()
    r.name = S.Text(r, "small")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
    -- Long names take more lines; layoutCard stacks the rows by height.
    r.name:SetWordWrap(true)
    r.name:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.itemID)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    d.rows[i] = r
    return r
end

local function buildDetails(c)
    local d = CreateFrame("Frame", nil, c)
    d:SetPoint("BOTTOMLEFT")
    d:SetPoint("BOTTOMRIGHT")
    d:SetHeight(DETAIL_H)
    S.Card(d)
    d:Hide()
    ui.details = d

    -- The title, the status line, the material rows and the sale line each take the
    -- lines they need; the card grows to hold them (layoutCard).
    d.title = S.Text(d, "head")
    d.title:SetPoint("TOPLEFT", 8, -8)
    d.title:SetPoint("RIGHT", -8, 0)
    d.title:SetWordWrap(true)

    -- Waypoint for the picked row: the nearest vendor or trainer it names.
    d.pin = S.PinButton(d, function(self)
        if self.gatherRow then return gatherPin(self.gatherRow) end
        if self.target and ui.guide then CP.Waypoint.ToRecipe(ui.guide, self.target) end
    end)
    d.pin:SetPoint("TOPRIGHT", d.title, "BOTTOMRIGHT", 0, -1)

    d.status = S.Text(d, "small", S.color.label)
    d.status:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -3)
    d.status:SetPoint("RIGHT", d.pin, "LEFT", -4, 0)
    d.status:SetJustifyH("LEFT")
    d.status:SetWordWrap(true)

    -- What the crafted item sells for. Display only; never ranks recipes. Buying happens
    -- at the vendor's own window (Buying.lua).
    d.sale = S.Text(d, "small", S.color.label)
    d.sale:SetPoint("BOTTOMLEFT", 8, 38)
    d.sale:SetPoint("RIGHT", -8, 0)
    d.sale:SetJustifyH("LEFT")
    d.sale:SetWordWrap(true)

    -- Where to fish the step's fish, below its materials.
    d.fish = S.Text(d, "small", S.color.accent)
    d.fish:SetJustifyH("LEFT")
    d.fish:SetWordWrap(true)

    d.rows = {}
    for i = 1, REAGENT_ROWS do reagentRow(d, i) end

    -- Crafting happens on the player's click; works in any profession window.
    -- Open (craftAll with `openTo` set) opens the profession's window on the recipe instead.
    local function craft(self)
        -- Learn pattern: the secure overlay over this button does the click's work. A
        -- preview lays no overlay, so its click lands here.
        if self.usePattern then
            if CP.Preview then CP.Preview.Refuse("learn") end
            return
        end
        if self.learnTo then return CP.Waypoint.ToRecipe(ui.guide, self.learnTo) end
        if self.openTo then
            -- Not a tail call, so the open trace's stack keeps this caller.
            local opened = CP.Window.OpenTo(self.openTo, self.recipeID)
            return opened
        end
        if self.enchantRow then return CP.EnchantAgain.Press(self.enchantRow) end
        CP.Crafting.Start(self.recipeID, self.count)
    end
    -- Craft 1, Available (what the bags allow now), Craft all (the whole step).
    d.craftAll = button(d, CP.GuideTab.CRAFT_ALL_W)
    d.craftAll:SetPoint("BOTTOMRIGHT", -8, 8)
    d.craftAvail = button(d, 100)
    d.craftAvail:SetPoint("RIGHT", d.craftAll, "LEFT", -5, 0)
    d.craftOne = button(d, 56)
    d.craftOne:SetPoint("RIGHT", d.craftAvail, "LEFT", -5, 0)
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do
        b:SetScript("OnClick", craft)
        b:SetMotionScriptsWhileDisabled(true)
        b:SetScript("OnEnter", craftTip)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
    d.craftAll:HookScript("OnEnter", function(self) CP.PatternLearn.Enter(self) end)
    d.making = CP.Crafting.Strip(d)
    d.making:SetPoint("BOTTOMLEFT", 8, 8)
    d.making:SetPoint("BOTTOMRIGHT", -8, 8)
    d.craftOne.label:SetText("Craft 1")
end

-- Impromptu area -------------------------------------------------------------

-- A fixed area between the step list and the step card: crafts that spare raw loot in the bags
-- makes now for points (CP.Impromptu). It holds Impromptu.ROWS step rows and keeps that height
-- when empty. Its rows pick nothing in the plan.
CP.GuideTab.IMPROMPTU_EMPTY = "Nothing to craft from your bags right now."
CP.GuideTab.IMPROMPTU_TIP = "Spare loot in your bags makes %d. Your guides don't need these materials."
CP.GuideTab.IMPROMPTU_CRAFT_W = 64
CP.GuideTab.IMPROMPTU_TITLE = "Available Skill Ups"

-- The divider and the heading above the rows, with room above the divider.
local IMPROMPTU_HEAD_H = 28
CP.GuideTab.IMPROMPTU_HEAD_H = IMPROMPTU_HEAD_H

local function impromptuTip(self)
    local it = self.item
    if not it then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(it.name, 1, 1, 1)
    GameTooltip:AddLine(CP.GuideTab.IMPROMPTU_TIP:format(it.crafts), nil, nil, nil, true)
    GameTooltip:Show()
end

-- Craft crafts the row's count, as the card's buttons do; with the window shut it is Open.
local function impromptuClick(self)
    if self.openTo then
        -- Not a tail call, so the open trace's stack keeps this caller.
        local opened = CP.Window.OpenTo(self.openTo, self.recipeID)
        return opened
    end
    CP.Crafting.Start(self.recipeID, self.count)
end

local function impromptuRow(area, i)
    local C = CP.GuideTab.COLUMNS
    local r = container(area)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -IMPROMPTU_HEAD_H - (i - 1) * ROW_H)
    r:SetPoint("RIGHT")
    r:EnableMouse(true)
    S.Rule(r)
    r.craft = button(r, CP.GuideTab.IMPROMPTU_CRAFT_W)
    r.craft:SetPoint("RIGHT", -C.edge, 0)
    r.craft:SetScript("OnClick", impromptuClick)
    r.craft:SetMotionScriptsWhileDisabled(true)
    r.craft:SetScript("OnEnter", craftTip)
    r.craft:SetScript("OnLeave", GameTooltip_Hide)
    r.info = S.Column(S.Text(r, "small", S.color.muted))
    r.info:SetPoint("RIGHT", r.craft, "LEFT", -C.edge * 2, 0)
    r.info:SetJustifyH("RIGHT")
    r.name = S.OneLine(S.Text(r, "body"))
    r.name:SetPoint("LEFT", C.left, 0)
    r.name:SetPoint("RIGHT", r.info, "LEFT", -C.edge, 0)
    r.name:SetJustifyH("LEFT")
    r:SetScript("OnEnter", impromptuTip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:Hide()
    return r
end

local function buildImpromptu(c)
    local area = container(c)
    area.max = CP.Impromptu.ROWS
    area:SetHeight(IMPROMPTU_HEAD_H + area.max * ROW_H)
    area:SetPoint("BOTTOMLEFT", ui.details, "TOPLEFT", 0, LIST_GAP)
    area:SetPoint("BOTTOMRIGHT", ui.details, "TOPRIGHT", -12, LIST_GAP)
    area.divider = S.Divider(area)
    area.divider:SetPoint("TOPLEFT", 0, -6)
    area.divider:SetPoint("TOPRIGHT", 0, -6)
    area.heading = S.Text(area, "small", S.color.label)
    area.heading:SetPoint("TOPLEFT", CP.GuideTab.COLUMNS.left, -12)
    area.heading:SetJustifyH("LEFT")
    area.heading:SetText(CP.GuideTab.IMPROMPTU_TITLE)
    area.empty = S.Text(area, "small", S.color.muted)
    area.empty:SetPoint("LEFT", area, "TOPLEFT", CP.GuideTab.COLUMNS.left, -IMPROMPTU_HEAD_H - ROW_H / 2)
    area.empty:SetPoint("RIGHT")
    area.empty:SetJustifyH("LEFT")
    area.empty:SetText(CP.GuideTab.IMPROMPTU_EMPTY)
    area.rows = {}
    for i = 1, area.max do area.rows[i] = impromptuRow(area, i) end
    ui.impromptu = area
end

-- Shows the area for `live` (nil hides it) and stands the step list above it or the card.
local function fillImpromptu(live)
    local area = ui.impromptu
    local shown = live ~= nil and live.guide ~= nil and not ui.line
    area:SetShown(shown)
    ui.scroll:SetPoint("BOTTOMRIGHT", shown and area or ui.details, "TOPRIGHT", shown and 0 or -12, LIST_GAP)
    if not shown then return end
    local list = CP.Impromptu.List(live, area.max)
    local spell = CP.Window.KeyOf(live)
    local busy, why = CP.Crafting.Busy(), live.offline and CP.Window.OpenBlocked()
    for i, r in ipairs(area.rows) do
        local it = list[i]
        r.item = it
        r:SetShown(it ~= nil)
        if it then
            r.name:SetText(it.name)
            r.name:SetTextColor(unpack(diffColor(difficultyAt(it.recipe, skill))))
            r.info:SetText(CP.Impromptu.Info(it))
            r.info:SetWidth(S.Measure(r.info:GetText(), "small") + 2)
            local b = r.craft
            b.recipeID, b.count = it.spell, it.crafts
            if live.offline then
                b.openTo, b.tip = spell, why or nil
                b.label:SetText("Open")
                setEnabled(b, not why)
            else
                b.openTo, b.tip = nil, nil
                b.label:SetText("Craft")
                setEnabled(b, not busy)
            end
        end
    end
    area.empty:SetShown(#list == 0)
end
CP.GuideTab.FillImpromptu = fillImpromptu

local GOOD_HEX = "|cff8cd98c"

-- "Disenchant: Strange Dust x27 for Enchanting" when the player has
-- Enchanting and this step's greens yield what that guide still needs; else nil. A step
-- Enchanting's credit chose reads "For Enchanting: disenchant these for Strange Dust x27".
-- The material Enchanting still needs that a craft of `row`'s recipe gives most of when
-- disenchanted: { item, count } a craft, or nil.
function CP.GuideTab.DEBest(row)
    local Sh = CP.Shared
    if not Sh.ForEnchanting() or not row.recipe then return nil end
    if ui.guide == CP.Guides[Sh.ENCHANTING] or not CP.Sourcing.PlayerSkills()[Sh.ENCHANTING] then return nil end
    local needs = CP.charDB.gatherNeeds and CP.charDB.gatherNeeds[Sh.ENCHANTING]
    local best
    for _, y in ipairs(Sh.DEYield(row.recipe)) do
        -- Only what bags, bank and mail don't already cover is still owed.
        if needs and (needs[y.item] or 0) - CP.Purchases.Have(y.item) > 0 and (not best or y.count > best.count) then best = y end
    end
    return best
end

local function deText(row)
    local best = CP.GuideTab.DEBest(row)
    if not best then return nil end
    local name = CP.ItemName(best.item) or "materials"
    local n = CP.Shared.DERound(best.count * row.crafts)
    if row.forEnchanting then return ("For Enchanting: disenchant these for %s x%d"):format(name, n) end
    return ("Disenchant: %s x%d for Enchanting"):format(name, n)
end

-- How many of made material `m` row must make first: its need less the bags and less what earlier
-- rows make and the rows between leave (`row.supplied`), which is theirs to make (decision 0008,
-- rule 6). 0 for any other material.
function CP.GuideTab.MakeShort(guide, row, m)
    if not (guide and guide.prep and guide.prep[m.itemID]) then return 0 end
    local supplied = row.supplied and row.supplied[m.itemID] or 0
    return math.max(0, (m.need or 0) * row.crafts - (m.have or 0) - supplied)
end

-- The card's status part for what the bags make: "materials for 3", or, with none and a
-- made material short (the card's "make N" tag), "make 6 Bolt of Linen Cloth first".
CP.GuideTab.MATERIALS_FOR = "materials for %d"
CP.GuideTab.MAKE_FIRST = "make %d %s first"
function CP.GuideTab.MaterialsText(guide, row, reagents)
    if (row.craftable or 0) == 0 and guide and guide.prep then
        for _, m in ipairs(reagents or {}) do
            local short = CP.GuideTab.MakeShort(guide, row, m)
            if short > 0 then
                return CP.GuideTab.MAKE_FIRST:format(short, m.name or CP.ItemName(m.itemID) or "materials")
            end
        end
    end
    return CP.GuideTab.MATERIALS_FOR:format(row.craftable or 0)
end

-- A maker row whose count is more than its range needs says how many of its crafts give
-- skill-ups (decision 0008, rule 6; owner: "if we left it with just a number, players will
-- wonder why"). Nil for any other row.
CP.GuideTab.SKILL_UPS = "%d for skill-ups"
function CP.GuideTab.SkillUpsText(row)
    if not (row.keep and row.recipe and row.from and row.to) then return nil end
    local ups = CP.Guide.Crafts(row.recipe, row.from, row.to)
    if ups == math.huge or (row.crafts or 0) <= ups then return nil end
    return CP.GuideTab.SKILL_UPS:format(ups)
end

-- An Enchanting material another guide disenchants for: the tag counts what that guide's
-- current step gives now, the note splits now from later (Shared.DEIncomingSplit).
CP.GuideTab.DE_NOW_TAG = "~%d now"
CP.GuideTab.DE_NOW = "~%d now from %s's %s (%d-%d)"
CP.GuideTab.DE_NONE_NOW = "none now"
CP.GuideTab.DE_LATER = "~%d later, from %s (%d-%d) on"
function CP.GuideTab.DENote(name, split)
    local G = CP.GuideTab
    local now = split.nowStep and split.now > 0
        and G.DE_NOW:format(split.now, split.nowStep.guide, split.nowStep.recipe, split.nowStep.from, split.nowStep.to)
        or G.DE_NONE_NOW
    local parts = { ("%s: %s"):format(name or "materials", now) }
    if split.later > 0 and split.laterStep then
        parts[#parts + 1] = G.DE_LATER:format(split.later, split.laterStep.recipe, split.laterStep.from, split.laterStep.to)
    end
    return table.concat(parts, "  \194\183  ")
end

-- "Sells: auction 8s · vendor 1s 20c · 12 for ~1g 36s", the better outlet in green.
local function saleText(row)
    local item = Prof.Output(row.spell)
    if not item then return "" end
    local vendor, ah = CP.Pricing.SaleValue(item)
    if not vendor and not ah then return "" end
    local auctionWins = (ah or 0) > (vendor or 0)
    local parts = {}
    if ah then
        local t = "auction " .. CP.Pricing.Format(ah)
        parts[#parts + 1] = auctionWins and (GOOD_HEX .. t .. "|r") or t
    end
    if vendor then
        local t = "vendor " .. CP.Pricing.Format(vendor)
        parts[#parts + 1] = auctionWins and t or (GOOD_HEX .. t .. "|r")
    end
    local best = math.max(ah or 0, vendor or 0)
    -- Each craft makes `yield` items, and the sale line counts items.
    local made = row.crafts * ((row.recipe and row.recipe.yield) or 1)
    if made > 1 then
        parts[#parts + 1] = ("%d for ~%s"):format(made, CP.Pricing.Format(best * made))
    end
    return "Sells: " .. table.concat(parts, "  ·  ")
end

local function hideReagents(d)
    for _, line in ipairs(d.rows) do line:Hide() end
end

-- Details for a stop row (a rank book or a trainer visit): no materials, no crafting.
-- Point the details pin at the row's vendor or trainer, and say where that is:
-- "from Shandrina, Ashenvale (50.2, 67.1)", or "" when there's no known NPC.
-- A guessed trainer adds "  ·  trainer not confirmed" (Guide.FromText). Also returns the NPC.
local function aimPin(row)
    local d = ui.details
    local target = CP.Guide.WaypointFor(row, ui.live and ui.live.prof)
    d.pin.target = target
    d.pin:SetShown(target ~= nil)
    if not target then return "", nil end
    return CP.Guide.FromText(ui.guide, target)
end

-- Colour roles for card text. A line's own colour is its label ink; a span inside it takes
-- another role with an escape. Warn marks warnings and blockers only.
local function ink(role, text)
    return S.Hex(S.color[role]) .. text .. "|r"
end

-- Skill numbers in `text` stand out from the label ink around them.
local function skillInk(text)
    return (text:gsub("skill %d+", function(m) return ink("text", m) end))
end

-- A source line ("Buy the pattern from ... · skill 130"): label ink, skill in text, and a
-- standing the player lacks in warn.
local function sourceInk(row, text)
    local r = row.recipe
    local needs = r and CP.Guide.StandingText(ui.guide, r)
    local at = needs and CP.Guide.HasStanding(r) == false and text:find(needs, 1, true)
    if at then
        return skillInk(text:sub(1, at - 1)) .. ink("warn", needs) .. skillInk(text:sub(at + #needs))
    end
    return skillInk(text)
end

-- How to learn an unlearned recipe, with where: "Buy the pattern · skill 1 · from Shandrina,
-- Ashenvale (50.2, 67.1)".
-- What else learning needs follows: "needs Zandalar Tribe Friendly", "after the Triage quest".
local function learnLine(row)
    -- Unread, the recipe may be known already: no source, so nothing to buy or train.
    local unread = CP.Plan.OpenOnce(ui.live)
    if unread then
        ui.details.pin.target = nil
        ui.details.pin:Hide()
        return unread
    end
    local r, from = row.recipe, aimPin(row)
    local word = CP.Guide.SourceWord(r)
    local needs = CP.Guide.Needs(ui.guide, r)
    needs = needs and ("  ·  " .. needs) or ""
    if CP.GuideTab.PatternOwned(r, false) then return CP.GuideTab.HeldLine(r) end
    -- The skill number comes before the place, so a wrap never strands it on a line of its own.
    local where = from ~= "" and ("  ·  " .. from:gsub("^ ", "")) or ""
    if word == "trainer" then return ("Train  ·  skill %d%s%s"):format(r.learn, where, needs) end
    if word == "quest" then return ("Quest  ·  skill %d"):format(r.learn) end
    if r.src == "vendor" or r.src == "reputation" then
        return ("Buy the pattern  ·  skill %d%s%s"):format(r.learn, where, needs)
    end
    if word == "favor" or word == "seasonal" then
        if r.how then return ("%s  ·  skill %d"):format(CP.Guide.LearnText(r, ui.guide), r.learn) end
        return ("%s  ·  skill %d"):format(word == "favor" and "Buy for Merchant's Favor" or "Seasonal", r.learn)
    end
    return ("World drop  ·  skill %d"):format(r.learn)
end
CP.GuideTab.LearnLine = learnLine

-- The card's "While you're there" block for `row`'s trip to `npc`, or nil (Trip.Text). `own` is
-- the trip's own cost, `uses` the vendor goods the step itself buys, `skip` what the trip
-- itself learns. Later steps are this guide's rows after `row` and every other guide's rows.
local function tripText(row, npc, own, uses, skip)
    local live = ui.live
    if not (npc and live and live.prof and ui.guide) or not CP.Trip.Far(npc) then return nil end
    local after, found = {}, false
    for _, r in ipairs(ui.rows or {}) do
        if found then after[#after + 1] = r elseif r == row then found = true end
    end
    local p = live.prof
    local at = row.train and row.train.skill or row.at or row.from or p.skill
    local others = {}
    for _, other in ipairs(CP.Window.AllLives()) do
        if other.guide and other.prof and other.prof.id ~= p.id then
            others[#others + 1] = { guide = other.guide, name = other.prof.name, skill = other.prof.skill,
                                    rows = CP.GuideTab.RowsOf(other) }
        end
    end
    local text = CP.Trip.Text({ npc = npc, guide = ui.guide, skill = math.max(p.skill, at), rows = after, own = own,
                                uses = uses, skip = skip }, others)
    if not text then return nil end
    local lead = CP.Trip.LEAD
    if text:sub(1, #lead) == lead then
        return ink("label", lead) .. ink("text", text:sub(#lead + 1))
    end
    return ink("text", text)
end

-- What a stop row's trip costs at trainer `entry`, and the recipes and ranks it learns.
local function stopCost(row, entry)
    local skip = {}
    if row.rank then
        skip[row.rank] = true
        return row.rank.kind == "trainer" and row.rank.fee or row.rank.price or 0, skip
    end
    local own = 0
    for _, r in ipairs(row.train.recipes) do
        skip[r] = true
        if row.train.pattern then
            local it = ui.guide.items and ui.guide.items[r.pattern]
            own = own + (it and it[1] or 0)
        else
            own = own + CP.Guide.Fee(r, entry)
        end
    end
    return own, skip
end

-- A craft step's trip: the pattern's vendor or recipe's trainer while it is unlearned, else the
-- named seller of a vendor good it buys (`topUp`, Guide.VendorTopUp). Returns the NPC, the
-- trip's own cost, the goods it buys (item -> count) and what it learns, or nil.
local function stepTrip(row, topUp)
    local guide, live = ui.guide, ui.live
    if not (guide and live) or live.unread then return nil end
    if not row.learned then
        if CP.GuideTab.PatternOwned(row.recipe, false) then return nil end
        local npc = CP.Guide.Nearest(guide, CP.Guide.WaypointFor(row, live.prof))
        local r = row.recipe
        local own = 0
        if CP.Guide.SourceWord(r) == "trainer" then
            own = CP.Guide.Fee(r, npc and npc.entry)
        else
            local it = guide.items and guide.items[r.pattern]
            own = it and it[1] or 0
        end
        return npc, own, nil, { [r] = true }
    end
    local uses, own, npc = {}, 0, nil
    for _, b in ipairs(topUp or {}) do
        local it = guide.items and guide.items[b.itemID]
        uses[b.itemID] = b.count
        own = own + b.count * (it and it[1] or 0)
        if not npc and it and it.vendors then npc = CP.Guide.NearestSeller(guide, it.vendors) end
    end
    return npc, own, uses, nil
end

-- `text` with the trip block under it, when there is one.
local function withTrip(text, trip)
    if not trip then return text end
    return (text and text ~= "") and (text .. "\n" .. trip) or trip
end

local function fillStopDetails(row)
    local d = ui.details
    noStrip()
    -- The visit's fee is the named trainer's.
    local from, npc = aimPin(row)
    local title, status = CP.Guide.StopText(row, npc and npc.entry)
    local because = CP.GuideTab.CauseText(row)
    if because then status = status .. "  ·  " .. because end
    local stop = row.train
    if stop and stop.pattern and CP.GuideTab.PatternOwned(stop.recipes[1], false) then
        status = CP.GuideTab.HeldLine(stop.recipes[1]) .. (because and ("  ·  " .. because) or "")
        from = ""
    end
    d.title:SetText(title)
    d.title:SetTextColor(unpack(S.color.title))
    d.status:SetText(skillInk(status))
    d.status:SetTextColor(unpack(S.color.label))
    hideReagents(d)
    local sale = from ~= "" and ("Nearest:" .. from:gsub("^ from", "")) or ""
    if from ~= "" then
        local own, skip = stopCost(row, npc and npc.entry)
        sale = withTrip(sale, tripText(row, npc, own, nil, skip))
    end
    d.sale:SetText(sale)
    d.sale:SetTextColor(unpack(S.color.label))
    craftReset(d)
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do
        b.recipeID, b.count = nil, 0
        setEnabled(b, false)
    end
    d.craftOne.label:SetText("Craft 1")
    d.craftAvail.label:SetText("Available")
    d.craftAll.label:SetText("Craft all")
    -- A schematic for a step's material: the step card's own Go to vendor or Learn pattern.
    local stop = row.train
    if stop and stop.pattern then
        learnState(d, { recipe = stop.recipes[1], spell = stop.spells[1], learned = false })
    end
    d.fish:Hide()
    layoutCard()
    d:Show()
end

-- Details for a disenchant step: what to do and what it gives. The Disenchant tab does the
-- disenchanting, so the craft buttons stay off.
local function fillDeskillDetails(row)
    local d = ui.details
    noStrip()
    d.title:SetText(CP.Deskill.NAME)
    d.title:SetTextColor(unpack(S.color.title))
    d.status:SetText(("%d-%d  ·  %s"):format(row.from, row.to, CP.Deskill.CardText(row.crafts)))
    d.status:SetTextColor(unpack(S.color.label))
    d.pin.target = nil
    d.pin:Hide()
    hideReagents(d)
    d.sale:SetText(CP.Deskill.GivesText(row.crafts, function(id) return CP.ItemName(id) or "…" end) or "")
    d.sale:SetTextColor(unpack(S.color.label))
    craftReset(d)
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do
        b.recipeID, b.count = nil, 0
        setEnabled(b, false)
    end
    d.craftOne.label:SetText("Craft 1")
    d.craftAvail.label:SetText("Available")
    d.craftAll.label:SetText("Craft all")
    d.fish:Hide()
    layoutCard()
    d:Show()
end
CP.GuideTab.FillDeskillDetails = fillDeskillDetails

-- The worn item's name for the enchant card, or "your item" while the name is missing
-- or still loading (the game can answer an empty string then).
function CP.GuideTab.WornName(itemID)
    local name = CP.ItemName(itemID)
    if name == nil or name == "" then return "your item" end
    return name
end

-- The spell the player knows `row`'s step by: the guide's id, or the alias the game
-- answers for it.
function CP.GuideTab.PlayerSpell(row)
    local alias = ui.live and ui.live.alias
    return alias and alias[row.spell] or row.spell
end

-- Whether the step card's Enchant again button is on for `row`. The button and the key
-- binding both ask it. A step past the skill cap stays off, and the card's tip says why.
function CP.GuideTab.EnchantGate(row)
    local live = ui.live
    if not row.learned or not live or live.offline or not CP.Window.ProfessionOpen() then return false end
    local p = live.prof
    if p and CP.Guide.PastCap(ui.guide, row.from, p.skill, p.max) then return false end
    local action = CP.EnchantAgain.Action(row.recipe)
    return action == "confirm" or (action == "cast" and (row.craftable or 0) > 0)
end

-- An Enchanting step that enchants gear gets one Enchant again button (and key
-- binding) on the matching equipped item instead of the craft buttons. True when it did.
-- `note` (where to buy a material) goes above the enchant's own line.
local function enchantDetails(row, can, note)
    local d, EA = ui.details, CP.EnchantAgain
    d.craftAll.enchantRow = nil
    d.craftOne:Show()
    d.craftAvail:Show()
    local slot = ui.guide == CP.Guides[CP.Shared.ENCHANTING] and EA.SlotFor(row.recipe)
    if not slot then
        if EA.row and EA.row.key == row.key then EA.row = nil end
        return false
    end
    EA.row = row
    d.craftOne:Hide()
    d.craftAvail:Hide()
    local itemID, loc = EA.Target(row.recipe)
    d.craftAll.enchantRow = row
    d.craftAll.label:SetText(EA.Label(row.recipe))
    setEnabled(d.craftAll, CP.GuideTab.EnchantGate(row) and true or false)
    local text
    if not itemID then
        text = ("Equip an item in your %s slot to enchant it."):format(EA.SlotName(slot))
    else
        local name = CP.GuideTab.WornName(itemID)
        text = ("On %s. Bind a key: Key Bindings, Professionally Lost."):format(name)
        if not C_Item.IsBound(loc) then text = ("Enchanting binds %s to you."):format(name) end
    end
    if note then text = note .. "\n" .. text end
    d.sale:SetText(text)
    d.sale:SetTextColor(unpack(itemID and not note and S.color.label or S.color.warn))
    return true
end

-- "Fish 52 in Tirisfal Glades · Fishing +31", for a step's fish; its name is on the row above.
function CP.GuideTab.FishText(f)
    local info = CP.Professions.SkillLine(CP.Fishing.SKILL)
    local skill = info and info.rank or 0
    if skill <= 0 then return ("Learn Fishing to catch %d"):format(f.short) end
    local water = CP.Fishing.WaterFor(f.item, skill, CP.Gather.PlayerLevel(), UnitFactionGroup("player"),
        CP.GatherList.Distance)
    if not water then return ("Fish %d: no water lands it at your skill yet"):format(f.short) end
    local zone = C_Map.GetMapInfo(water.zone)
    -- The casts it takes, and the Fishing points they give on the way.
    local casts = math.ceil(f.short / (water.chance / 100) / (water.land / 100))
    local gain = CP.Fishing.GainFrom(skill, casts, info.maxRank)
    local text = ("Fish %d in %s"):format(f.short, zone and zone.name or "?")
    return gain > 0 and ("%s · Fishing +%d"):format(text, gain) or text
end

-- A font string's drawn height, or `default` while it has none (no font engine).
local function textHeight(fs, default)
    local h = fs and fs.GetStringHeight and fs:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then return default end
    return math.ceil(h)
end

-- Where the step card's material rows start: below the title and the status line,
-- either of which may wrap.
CP.GuideTab.TITLE_TOP, CP.GuideTab.TITLE_H, CP.GuideTab.STATUS_GAP = 8, 15, 3
function CP.GuideTab.MaterialsTop(d)
    local h = textHeight(d.status, 0)
    if h <= 0 then return LIST_TOP end
    local G = CP.GuideTab
    return math.min(LIST_TOP, -(G.TITLE_TOP + textHeight(d.title, G.TITLE_H) + G.STATUS_GAP + h + 4))
end

-- The card's height: DETAIL_H, or more when its texts wrap (layoutCard).
local function cardHeight()
    local d = ui.details
    return d and d.need or DETAIL_H
end

-- Stacks the card's shown material rows below the status line, each as tall as its
-- name's lines, then the fish line, and grows the card to hold them above the sale
-- line and the buttons.
function layoutCard()
    local d = ui.details
    local y = CP.GuideTab.MaterialsTop(d)
    -- The tags stand left of the widest have / need count, so they line up. A count wider
    -- than measured runs into the gap and still shows whole.
    local counts = {}
    for _, line in ipairs(d.rows) do
        if line:IsShown() then counts[#counts + 1] = line.count:GetText() or "" end
    end
    local countW = S.Widest(counts, "small")
    for _, line in ipairs(d.rows) do
        line.tag:ClearAllPoints()
        line.tag:SetPoint("RIGHT", -(countW + CP.GuideTab.COUNT_GAP), 0)
    end
    for _, line in ipairs(d.rows) do
        if line:IsShown() then
            local height = math.max(18, textHeight(line.name, 0) + 4)
            line:SetHeight(height)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", 8, y)
            line:SetPoint("RIGHT", -8, 0)
            y = y - height + 1
        end
    end
    d.fish:ClearAllPoints()
    d.fish:SetPoint("TOPLEFT", 8, y - 2)
    d.fish:SetPoint("RIGHT", -8, 0)
    if d.fish:IsShown() then y = y - 2 - textHeight(d.fish, 0) end
    local sale = d.sale:GetText() ~= nil and d.sale:GetText() ~= "" and textHeight(d.sale, 0) or 0
    d.need = math.max(DETAIL_H, -y + 4 + sale + 38)
    d:SetHeight(d.need)
end

-- The craft buttons, Craft 1, Available and Craft all, each as wide as its label. When
-- the `long` labels don't fit across the card, the `short` ones (All mode's) do.
CP.GuideTab.CRAFT_PAD, CP.GuideTab.CRAFT_GAP = 16, 5
local function fitCraft(d, long, short)
    local G, P = CP.GuideTab, CP.Panel
    local list = { d.craftOne, d.craftAvail, d.craftAll }
    local room = P.WIDTH - 2 * P.BODY_PAD - 16
    local function widths(set)
        local out, sum = {}, 0
        for i, b in ipairs(list) do
            out[i] = P.TextWidth(b.label, set[i]) + G.CRAFT_PAD
            sum = sum + out[i] + G.CRAFT_GAP
        end
        return out, sum
    end
    local set, w, sum = long, widths(long)
    if sum > room then
        set = short
        w = widths(short)
    end
    for i, b in ipairs(list) do
        b.label:SetText(set[i])
        b:SetWidth(w[i])
    end
end

-- A batch running past the end of the step it started on: the card says so first, in warn ink,
-- until the player stops it. `row` is the card's step; the batch's step is the one shown when
-- it began (Crafting.Track), which a skill-up may already have moved on from.
function CP.GuideTab.OvershootNote(row, live)
    local p = live and live.prof
    if not p or live.offline then return end
    if row.recipe and row.learned and not (row.rank or row.train) then
        CP.Crafting.Track(row.to, row.crafts, row.keep ~= nil and not row.side, row.spell, live.alias)
    end
    local over = CP.Crafting.OvershootText(p.skill)
    local d = ui.details
    -- Stop is the main action while the warning stands, shown or not.
    if d.making then S.Urge(d.making.stop, over ~= nil) end
    if not over then return end
    local was = d.sale:GetText()
    d.sale:SetText((was and was ~= "") and (over .. "\n" .. was) or over)
    d.sale:SetTextColor(unpack(S.color.warn))
    layoutCard()
end

CP.GuideTab.BANK_TAG = "%d in bank"
CP.GuideTab.MAIL_TAG = "%d in mail"

-- Items whose name the card waits on. The item event can come while the name still reads
-- nil, and an item the game already holds raises no second one, so the card asks again on
-- a timer and redraws once the name reads.
local nameWatch = {}
local NAME_RETRY, NAME_TRIES = 1, 15

local function watchName(id, tries)
    if tries == nil then
        if nameWatch[id] then return end
        nameWatch[id] = true
        tries = 0
    end
    C_Timer.After(NAME_RETRY, function()
        local d = ui.details
        local shown = d and d:IsShown()
        if shown and not C_Item.GetItemNameByID(id) and tries < NAME_TRIES then
            CP.RequestItem(id)
            return watchName(id, tries + 1)
        end
        nameWatch[id] = nil
        if not shown then return end
        for _, line in ipairs(d.rows) do
            if line:IsShown() and line.itemID == id then return CP.Panel.Changed() end
        end
    end)
end

local function fillDetails(row)
    ui.details.pin.gatherRow = nil
    if isGatherRow(row) then return fillGatherDetails(row) end
    setCraftShown(true)
    if row.rank or row.train then return fillStopDetails(row) end
    if CP.Deskill.Is(row.recipe) then return fillDeskillDetails(row) end
    local d = ui.details
    local r = row.recipe
    d.title:SetText(r.name)
    d.title:SetTextColor(unpack(diffColor(difficultyAt(r, math.max(skill, row.from)))))

    local reagents = Prof.Reagents(row.spell, r.reagents)
    -- `held` counts the bank and mail too, as the Shop does. `have` stays the bags, which is what a
    -- craft can use now.
    local counted = {}
    for i, m in ipairs(reagents) do
        local held = math.max(m.have, CP.Purchases.Have(m.itemID))
        m.mail = CP.Purchases.InMail(m.itemID) + CP.Purchases.Bought(m.itemID)
        m.held, m.bank = held, math.max(0, held - m.have - m.mail)
        local c = {}
        for k, v in pairs(m) do c[k] = v end
        c.have = held
        counted[i] = c
    end
    local have = CP.GuideTab.MaterialsText(ui.guide, row, reagents)
    if row.side and row.learned then
        local why = row.withFish and "With fishing" or row.limited and "If the pattern above is sold out"
            or row.fallback and "If you can't get the pattern above"
            or "Or instead of the step above"
        d.status:SetText(("%s  ·  %s"):format(why, have))
        d.status:SetTextColor(unpack(S.color.label))
        d.pin:Hide()
    elseif row.learned then
        local keep = row.keep and ("  ·  keep %d for later"):format(row.keep.count) or ""
        local ups = CP.GuideTab.SkillUpsText(row)
        d.status:SetText(("%d-%d  ·  ~%d crafts%s%s  ·  %s"):format(row.from, row.to, row.crafts,
            ups and ("  ·  " .. ups) or "", keep, have))
        d.status:SetTextColor(unpack(S.color.label))
        d.pin:Hide()
    else
        local line = learnLine(row)
        if CP.Plan.OpenOnce(ui.live) then
            d.status:SetText(line)
            d.status:SetTextColor(unpack(S.color.warn))
        else
            d.status:SetText(sourceInk(row, line))
            d.status:SetTextColor(unpack(S.color.label))
        end
    end

    -- Gathered materials on hand set how many crafts are in reach; vendor rows say
    -- how many to buy to match, prep rows (cured hides) how many to make first.
    local _, topUp = CP.Guide.VendorTopUp(ui.guide, counted, row.crafts)
    local buyFor = {}
    for _, b in ipairs(topUp) do buyFor[b.itemID] = b.count end
    local fishing, buyNote, deNote
    for i = #d.rows + 1, #reagents do reagentRow(d, i) end
    for i, line in ipairs(d.rows) do
        local m = reagents[i]
        line:SetShown(m ~= nil)
        if m then
            local need = m.need * row.crafts
            if not fishing and CP.Pricing.IsFish(m.itemID) and need > m.held then
                fishing = { item = m.itemID, name = m.name, short = need - m.held }
            end
            line.itemID = m.itemID
            line.icon:SetTexture(m.icon)
            line.name:SetText(m.name)
            if not C_Item.GetItemNameByID(m.itemID) then watchName(m.itemID) end
            line.count:SetText(("%d / %d"):format(m.held, need))
            -- Green: enough for the whole step. Yellow: at least one craft. Red: none.
            local color = S.color.bad
            if m.held >= need then
                color = S.color.good
            elseif m.held >= m.need then
                color = S.color.warn
            end
            line.count:SetTextColor(unpack(color))
            local tag = ""
            if row.learned and buyFor[m.itemID] then
                tag = "buy " .. buyFor[m.itemID]
                buyNote = buyNote or CP.Guide.BuyNote(ui.guide, m.itemID, m.name)
            elseif CP.GuideTab.MakeShort(ui.guide, row, m) > 0 then
                tag = "make " .. CP.GuideTab.MakeShort(ui.guide, row, m)
            else
                -- Another guide wants the same material (cloth for First Aid and Tailoring),
                -- or will make it by disenchanting its greens (dust for Enchanting).
                tag = CP.Shared.Tag(CP.Shared.KeyOf(ui.guide), m.itemID)
                if not tag and ui.guide == CP.Guides[CP.Shared.ENCHANTING] then
                    -- What the other guides' current steps give now; the note says what comes later.
                    local split = CP.Shared.DEIncomingSplit(m.itemID)
                    if split.now + split.later > 0 then
                        tag = CP.GuideTab.DE_NOW_TAG:format(split.now)
                        deNote = deNote or CP.GuideTab.DENote(m.name, split)
                    end
                end
                tag = tag or ""
            end
            local plain = tag == ""
            -- Stock in the bank or mail says so, since the bags alone don't hold it.
            if plain and m.bank > 0 then
                tag = CP.GuideTab.BANK_TAG:format(m.bank)
            elseif plain and m.mail > 0 then
                tag = CP.GuideTab.MAIL_TAG:format(m.mail)
            end
            line.tag:SetText(tag)
            -- The step's target reached: it stays reached, so the tick says so (Plan.Commit).
            line.done:SetShown(plain and m.held >= need)
        end
    end
    d.fish:SetText(fishing and CP.GuideTab.FishText(fishing) or "")
    d.fish:SetShown(fishing ~= nil)

    -- An unlearned limited pattern shows what to craft instead if it's sold out; a step
    -- whose crafts feed a later one says to keep them rather than what they sell for.
    -- A material whose maker isn't learned and isn't trained says how to get that recipe;
    -- a vendor good to buy whose data names its seller says where.
    local alt = ui.live and CP.Plan.AlternativesText(ui.live, row)
    alt = alt or CP.Guide.PrepNote(ui.guide, r, ui.live and ui.live.learned or {}) or buyNote
    local keep = row.keep and ("Keep %d for %s"):format(row.keep.count, table.concat(row.keep.names, ", "))
    local because = CP.GuideTab.CauseText(row)
    if keep and row.keepForEnchanting then
        keep = keep .. CP.GuideTab.KEEP_DE
    elseif keep and because then
        keep = keep .. ". " .. because
    end
    local de = not alt and not keep and deText(row)
    local cause = not alt and not keep and not de and because
    -- A tool the bags lack comes first: the craft can't start without it.
    local tool = CP.Guide.MissingTool(ui.guide, r)
    local text = alt or keep or de or cause or saleText(row)
    -- A step Enchanting's credit chose always says why, under what else the card says.
    local why = row.forEnchanting and not de and deText(row)
    if why then text = text .. "\n" .. why end
    d.sale:SetText(tool and (text and text ~= "" and (tool.text .. "\n" .. text) or tool.text) or text)
    d.sale:SetTextColor(unpack((tool or alt) and S.color.warn or (keep or de or cause) and S.color.good or S.color.label))

    craftReset(d)
    local can = row.learned and row.craftable or 0
    local note = tool and (buyNote and (tool.text .. "\n" .. buyNote) or tool.text) or buyNote
    if deNote then
        note = note and (note .. "\n" .. deNote) or deNote
        if text == "" then text = deNote else text = deNote .. "\n" .. text end
        d.sale:SetText(tool and (tool.text .. "\n" .. text) or text)
    end
    local enchant = enchantDetails(row, can, note)
    local trip = tripText(row, stepTrip(row, topUp))
    if trip then d.sale:SetText(withTrip(d.sale:GetText(), trip)) end
    layoutCard()
    if not row.learned and ui.live and ui.live.unread then
        openState(d, row.spell)
        return d:Show()
    end
    if not row.learned then
        learnState(d, row)
        return d:Show()
    end
    if ui.live and ui.live.offline then
        openState(d, row.spell)
        return d:Show()
    end
    -- A step past the cap gives no skill until its rank is learned: the buttons stay
    -- greyed and say why.
    local p = ui.live and ui.live.prof
    local held = p and CP.Guide.PastCap(ui.guide, row.from, p.skill, p.max)
    local function capped(list)
        if not held then return end
        for _, b in ipairs(list) do
            b.tip = CP.Guide.CapText(held)
            setEnabled(b, false)
        end
    end
    if enchant then
        noStrip()
        capped({ d.craftAll })
        return d:Show()
    end
    local avail = math.min(can, row.crafts)
    local whole = can >= row.crafts and row.crafts or 0
    -- Crafted through the player's own spell when the guide knows it by another id.
    local spell = ui.live and ui.live.alias and ui.live.alias[row.spell] or row.spell
    d.craftOne.recipeID, d.craftOne.count = spell, 1
    d.craftAvail.recipeID, d.craftAvail.count = spell, avail
    d.craftAll.recipeID, d.craftAll.count = spell, whole
    d.craftAll.tip = CP.GuideTab.CraftAllTip(row.crafts, whole > 0, reagents)
    -- One progress display at a time: our strip for our batches; during Daylight UI's
    -- own batch its window shows progress and our buttons wait, greyed.
    local strip, busy = CP.Crafting.ShowStrip(), CP.Crafting.Busy()
    d.making:SetShown(strip)
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do b:SetShown(not strip) end
    if strip then
        d.making:Update()
    else
        local L = CP.GuideTab.CARD_LABELS
        fitCraft(d, { "Craft 1", avail > 0 and ("Available [%d]"):format(avail) or "Available",
                      ("Craft all [%d]"):format(row.crafts) },
            { L.one, avail > 0 and L.avail:format(avail) or L.availNone, L.all:format(row.crafts) })
        setEnabled(d.craftOne, can > 0 and not busy)
        setEnabled(d.craftAvail, avail > 0 and not busy)
        setEnabled(d.craftAll, whole > 0 and not busy)
        capped({ d.craftOne, d.craftAvail, d.craftAll })
    end
    d:Show()
end
CP.GuideTab.FillDetails = fillDetails

-- Step list -------------------------------------------------------------------

-- Clicking a row picks it in the guide. With its profession's window open it also
-- selects a learned recipe there, landing as Open's pick does (Window.SelectIn), in
-- Daylight UI's window or the game's. With a window open on another profession it
-- switches that window to the row's profession and selects there (Window.OpenTo). With
-- no profession window open nothing opens: only the step card's Open button does.
-- Waypoints come only from the row's pin.
local function pick(row)
    local own = ui.live or CP.Window.Live()
    if own and own.prof then profID = own.prof.id end
    setPick(profID, row.key)
    if CP.Buying then CP.Buying.Changed() end
    local recipe = row.spell and not (row.rank or row.train or isGatherRow(row))
    if recipe and row.learned and ui.live then
        local id = CP.Window.KeyOf(ui.live)
        if not ui.live.offline then
            if CP.Window.SelectIn(id, row.spell) and CP.Host.DaylightWindow() then S.Tick() end
        elseif CP.Window.ProfessionOpen() and not CP.Professions.preview then
            CP.Window.OpenTo(id, row.spell, true)
        end
    end
    CP.Panel:Refresh()
end
CP.GuideTab.Pick = pick

-- Drops what the guide holds in memory, as a fresh login starts. The picks live in the
-- character's saved variables and go with them. The test worlds call it between scenes.
function CP.GuideTab.Forget()
    profID, memo = nil, {}
    CP.GuideTab.waitingZones = false
end

local function pinClick(self)
    local row = self:GetParent().row
    if row and isGatherRow(row) then return gatherPin(row) end
    local target = row and CP.Guide.WaypointFor(row, ui.live and ui.live.prof)
    if target then CP.Waypoint.ToRecipe(ui.guide, target) end
end

-- An unlearned pattern step's info word: where the held pattern is, else how to get it.
CP.GuideTab.PATTERN_WORDS = {
    bags = "in bags", bank = "in bank", mail = "in mail", bought = "bought",
    buy = "buy pattern", drop = "world drop",
}

-- True when `row`'s pattern is held, so its info word reads in the owned row's green.
local function patternHeld(row)
    return CP.GuideTab.PatternOwned(row.recipe, row.learned, row.rank or row.train or row.side)
end

-- An unlearned main step's info column. Before the profession's list is read the recipe
-- may be known already, so an unheld pattern stays plain "pattern".
function CP.GuideTab.SourceInfo(row)
    local r, words = row.recipe, CP.GuideTab.PATTERN_WORDS
    local word = CP.Guide.SourceWord(r)
    if word ~= "pattern" or not r.pattern then return word end
    if patternHeld(row) then return words[CP.GuideTab.PatternWhere(r.pattern)] end
    if ui.live and ui.live.unread then return word end
    if r.src == "vendor" or r.src == "reputation" then return words.buy end
    if r.src == "pattern" then return words.drop end
    return word
end

-- A step row's three texts: its range column, its name and its info column. An "or"
-- row's range is empty; its arrow and "or" stand in the range column.
local function rowTexts(row)
    if isGatherRow(row) then return gatherTexts(row) end
    local words = row.cause and CP.GuideTab.CauseWords(row.cause) or ""
    local mark = words ~= "" and (" · " .. words) or ""
    if row.rank or row.train then
        local stop = row.rank or row.train
        local tag = row.rank and CP.Guide.RankTag(row.rank)
            or stop.pattern and CP.Guide.SourceWord(stop.recipes[1])
            or (stop.fee > 0 and CP.Pricing.Format(stop.fee) or "train")
        return tostring(row.at or stop.skill), (CP.Guide.StopText(row)), tag .. mark
    end
    if CP.Deskill.Is(row.recipe) then
        return ("%d-%d"):format(row.from, row.to), CP.Deskill.NAME, CP.Deskill.Count(row.crafts) .. mark
    end
    if row.side then
        -- A fallback that greys out inside the step says where it stops being worth it.
        local lo = row.lo and row.lo > row.from and (" from " .. row.lo) or ""
        local upto = row.upto and row.upto < row.to and (" to " .. row.upto) or ""
        local info
        if row.fallback and not row.learned then
            info = "trainer"
        else
            info = row.fallback and ("~" .. row.crafts) or (row.crafts == 1 and "1 craft" or (row.crafts .. " crafts"))
        end
        return "", row.recipe.name .. lo .. upto, info .. mark
    end
    local info = row.learned and ("~%d crafts"):format(row.crafts) or CP.GuideTab.SourceInfo(row)
    return ("%d-%d"):format(row.from, row.to), row.recipe.name, info .. mark
end
CP.GuideTab.RowTexts = rowTexts

-- A row another profession changed carries `cause` = { lines, own, de } (markCauses).
-- Its info column ends in the cause: "disenchant" for a step Enchanting's credit chose, else
-- the professions' names ("~30 crafts · Alchemy"). A step keeping its materials for a
-- disenchant step adds KEEP_DE to "Keep 93 for Brown Linen Robe".
-- A gathering profession (Herbalism, Mining, Skinning) changes nearly every row of the guide
-- that uses its materials, so it is named once in the header ("with Herbalism · 1 / 75") and
-- on each changed row's card, not in the info column.
CP.GuideTab.DE_MARK = "disenchant"
CP.GuideTab.KEEP_DE = ", made to disenchant for Enchanting"
CP.GuideTab.CAUSE_HAVE = "Changed because you have %s"
CP.GuideTab.CAUSE_MAKES = "Your %s makes the %s this uses"
CP.GuideTab.CAUSE_GATHERS = "Your %s gathers the %s this uses"
CP.GuideTab.CAUSE_FISH = "Your Fishing catches the %s this uses (Fish for Cooking)"
CP.GuideTab.CAUSE_FISH_ANY = "Your Fishing catches the %s this uses"
CP.GuideTab.CAUSE_GREENS = "Your %s greens disenchant into the %s this uses"
CP.GuideTab.WITH = "with %s"

-- The cause of a row that changed only because an earlier step moved: no profession of its own
-- and no card line, but the header still names the couplings.
function CP.GuideTab.ShiftedCause()
    return { lines = {}, shifted = true }
end
CP.GuideTab.WITHOUT = "without %s"

-- "disenchant", "Alchemy" or "Alchemy, Enchanting" for a row's cause; "" when only gathering
-- professions changed it.
function CP.GuideTab.CauseWords(cause)
    local words = {}
    for _, line in ipairs(cause.lines) do
        local own = cause.own and cause.de and line == CP.Shared.ENCHANTING
        if own then
            words[#words + 1] = CP.GuideTab.DE_MARK
        elseif not CP.Sourcing.IsGathering(line) then
            words[#words + 1] = CP.Shared.Name(line)
        end
    end
    return table.concat(words, ", ")
end

-- The header's coupling text: "with Herbalism" or "with Herbalism, Enchanting" for the
-- professions that changed `live`'s plan (markCauses), else nil.
-- A coupling the header can switch (Settings.Switches) shows while it is on, as "with
-- Enchanting", and while it is off, as "without Enchanting".
function CP.GuideTab.WithText(live)
    local names, named, off = {}, {}, {}
    local has = CP.Sourcing.PlayerSkills()
    -- Never "with X" for a profession the character lacks.
    for _, line in ipairs(live and live.coupled or {}) do
        if has[line] then
            names[#names + 1] = CP.Shared.Name(line)
            named[line] = true
        end
    end
    for _, sw in ipairs(live and live.guide and CP.Settings.Switches(CP.Shared.KeyOf(live.guide)) or {}) do
        if sw.on and not named[sw.line] then
            names[#names + 1] = CP.Shared.Name(sw.line)
            named[sw.line] = true
        elseif not sw.on then
            off[#off + 1] = CP.Shared.Name(sw.line)
        end
    end
    local parts = {}
    if #names > 0 then parts[#parts + 1] = CP.GuideTab.WITH:format(table.concat(names, ", ")) end
    if #off > 0 then parts[#parts + 1] = CP.GuideTab.WITHOUT:format(table.concat(off, ", ")) end
    if #parts == 0 then return nil end
    return table.concat(parts, " \194\183 ")
end

-- The header's switch tooltip: what the setting does, that it is on or off, what a click does.
CP.GuideTab.SWITCH_STATE = "%s: %s"
CP.GuideTab.SWITCH_CLICK = "Click to plan %s %s %s."
function CP.GuideTab.SwitchLines(live)
    local G = CP.GuideTab
    local guide = live and live.guide
    local sw = guide and CP.Settings.Switches(CP.Shared.KeyOf(guide))[1]
    if not sw then return nil end
    local s, who = sw.setting, CP.Shared.Name(sw.line)
    return {
        { text = G.SWITCH_STATE:format(s.label, sw.on and "on" or "off"), color = S.color.title },
        { text = s.desc, color = S.color.label },
        { text = G.SWITCH_CLICK:format(live.prof and live.prof.name or guide.name, sw.on and "without" or "with", who),
          color = S.color.muted },
    }, sw
end

local function switchTip(self)
    local lines = CP.GuideTab.SwitchLines(ui.live)
    if not lines then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    for i, l in ipairs(lines) do
        local c = l.color
        if i == 1 then
            GameTooltip:SetText(l.text, c[1], c[2], c[3], 1, true)
        else
            GameTooltip:AddLine(l.text, c[1], c[2], c[3], true)
        end
    end
    GameTooltip:Show()
end

-- A click on the header's "with Enchanting" turns its setting over.
function CP.GuideTab.SwitchClick()
    local _, sw = CP.GuideTab.SwitchLines(ui.live)
    if not sw then return end
    CP.Settings.Toggle(sw.setting.key)
    if ui.switch:IsMouseOver() then switchTip(ui.switch) end
end

-- "Alchemy" or "Alchemy and Enchanting".
local function causeNames(cause)
    local names = {}
    for _, line in ipairs(cause.lines) do names[#names + 1] = CP.Shared.Name(line) end
    if #names <= 1 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- The card's line for a row another profession changed: what that profession gives the
-- step ("Your Alchemy makes the Truesilver Bar this uses"), else that it changed the step.
-- A row that only moved says nothing.
local function causeText(row)
    local cause = row.cause
    if not cause or cause.shifted then return nil end
    local G = CP.GuideTab
    local via = cause.via and cause.via[1]
    if via then
        local name = CP.ItemName(via.item) or "material"
        if via.how == "fish" then
            -- "Fish for Cooking" governs Cooking's fish only.
            local cooking = ui.guide and CP.Shared.KeyOf(ui.guide) == COOKING
            return (cooking and G.CAUSE_FISH or G.CAUSE_FISH_ANY):format(name)
        end
        local text = via.how == "greens" and G.CAUSE_GREENS or via.how == "gathers" and G.CAUSE_GATHERS or G.CAUSE_MAKES
        return text:format(CP.Shared.Name(via.line), name)
    end
    return G.CAUSE_HAVE:format(causeNames(cause))
end
CP.GuideTab.CauseText = causeText

-- The step list's columns, measured in the current font (CP.GuideTab.Measure): the range
-- column's left edge and its gap to the name, the "or" arrow, the info column's gaps,
-- and the scroll bar's room right of the rows.
CP.GuideTab.COLUMNS = { left = 8, gap = 4, arrowX = 12, arrow = 14, orGap = 2, edge = 4, list = 12 }
ui.rangeW, ui.infoW = 56, 40

local function initRow(btn, row)
    local C = CP.GuideTab.COLUMNS
    if not btn.name then
        S.Interactive(btn)
        S.Rule(btn)
        btn.mark = S.AccentTexture(btn, "OVERLAY")
        btn.mark:SetPoint("TOPLEFT")
        btn.mark:SetPoint("BOTTOMLEFT")
        btn.mark:SetWidth(2)
        btn.range = S.Column(S.Text(btn, "small", S.color.muted))
        btn.range:SetPoint("LEFT", C.left, 0)
        -- Side rows: an arrow from the step above, then "or".
        btn.arrow = btn:CreateTexture(nil, "ARTWORK")
        btn.arrow:SetTexture(CP.MEDIA .. "SideArrow")
        btn.arrow:SetSize(C.arrow, C.arrow)
        btn.arrow:SetPoint("LEFT", C.arrowX, 0)
        btn.arrow:SetVertexColor(unpack(S.color.muted))
        btn.orText = S.Column(S.Text(btn, "small", S.color.muted))
        btn.orText:SetPoint("LEFT", btn.arrow, "RIGHT", C.orGap, 0)
        btn.orText:SetText("or")
        btn.pin = S.PinButton(btn, pinClick)
        btn.pin:SetPoint("RIGHT", -C.edge, 0)
        btn.info = S.Column(S.Text(btn, "small", S.color.muted))
        btn.info:SetPoint("RIGHT", btn.pin, "LEFT", -C.edge, 0)
        btn.info:SetJustifyH("RIGHT")
        -- A long name stays on one line and ends in "..." (Style.OneLine); the row keeps ROW_H.
        btn.name = S.OneLine(S.Text(btn, "body"))
        btn.name:SetPoint("LEFT", btn.range, "RIGHT", C.gap, 0)
        btn.name:SetPoint("RIGHT", btn.info, "LEFT", -C.edge, 0)
        btn.name:SetJustifyH("LEFT")
        btn:SetScript("OnClick", function(self) pick(self.row) end)
    end

    btn.row = row
    btn.range:SetWidth(ui.rangeW)
    btn.info:SetWidth(ui.infoW)
    local range, name, info = rowTexts(row)
    btn.range:SetText(range)
    btn.name:SetText(name)
    btn.info:SetText(info)

    -- Rows are reused: only an "or" row keeps its arrow and "or" in the range column.
    btn.arrow:SetShown(row.side == true)
    btn.orText:SetShown(row.side == true)
    if isGatherRow(row) then
        btn.mark:SetShown(row.current == true)
        return initGatherRow(btn, row)
    end
    -- The picked row's step card has the same pin, so the row's own stands down.
    local target = CP.Guide.WaypointFor(row, ui.live and ui.live.prof)
    btn.pin:SetShown(target ~= nil and row.key ~= pickOf(profID))
    btn.mark:SetShown(row.current)
    if row.rank or row.train then
        btn.name:SetTextColor(unpack(S.color.title))
        local fee = row.rank and row.rank.kind == "trainer" and (row.rank.fee or 0)
            or (not row.rank and not row.train.pattern and row.train.fee) or 0
        -- A price reads in text ink, a source word (pattern, trainer, quest) in label.
        btn.info:SetTextColor(unpack(fee > 0 and S.color.text or S.color.label))
        return
    end
    -- A recipe's name keeps the game's difficulty colour, learned or not.
    btn.name:SetTextColor(unpack(diffColor(difficultyAt(row.recipe, math.max(skill, row.from)))))
    local source = row.side and row.fallback and not row.learned or not row.side and not row.learned
    local ink = patternHeld(row) and S.color.good or source and S.color.label or S.color.muted
    btn.info:SetTextColor(unpack(ink))
end
CP.GuideTab.InitRow = initRow

-- The least room a step row leaves its name, in px at text size 1. Names never widen
-- the window; a longer one wraps onto more lines in a taller row.
CP.GuideTab.NAME_MIN = 120

-- Measures `rows` in the current font: the range and info columns take their widest
-- text. Returns the width the rows need: both columns, the pin and NAME_MIN for the name.
function CP.GuideTab.Measure(rows)
    local C = CP.GuideTab.COLUMNS
    local ranges, infos, words = {}, {}, {}
    for i, row in ipairs(rows) do
        local name
        ranges[i], name, infos[i] = rowTexts(row)
        for word in tostring(name or ""):gmatch("%S+") do words[#words + 1] = word end
    end
    local orRight = C.arrowX + C.arrow + C.orGap + S.Measure("or", "small") - C.left
    ui.rangeW = math.max(S.Widest(ranges, "small"), orRight)
    ui.infoW = S.Widest(infos, "small")
    local fixed = C.left + ui.rangeW + C.gap + C.edge + ui.infoW + C.edge + S.PIN + C.edge
    -- A name wraps at spaces, so its longest word must fit on a line of its own.
    local nameMin = math.max(math.ceil(CP.GuideTab.NAME_MIN * S.TextScale()), S.Widest(words, "body"))
    local list = fixed + nameMin + C.list + 2 * CP.Panel.BODY_PAD
    -- The header: the profession's name and the skill text beside it.
    local header = 0
    if ui.prof and ui.skillText then
        header = CP.Panel.TextWidth(ui.prof) + C.gap * 4 + CP.Panel.TextWidth(ui.skillText) + 2 * CP.Panel.BODY_PAD
    end
    return math.max(list, math.ceil(header))
end

-- The skill text as lines that fit `room` px: one line when it fits, else the professions
-- that shaped the plan broken at spaces, the skill count whole on the last line. `measure`
-- reads a text's width.
function CP.GuideTab.HeaderLines(with, count, room, measure)
    local full = with and (with .. " · " .. count) or count
    if not with or measure(full) <= room then return { full } end
    local lines = S.Lines(with .. " ·", "body", room, measure)
    local last = lines[#lines]
    if last and measure(last .. " " .. count) <= room then
        lines[#lines] = last .. " " .. count
    else
        lines[#lines + 1] = count
    end
    return lines
end

-- Fits the header to the window: the skill text breaks onto lines beside the name when
-- both don't fit on one, and the bar and the list move down by the added lines.
local function fitHeader(with, count)
    local room = CP.Panel.WIDTH - 2 * CP.Panel.BODY_PAD - CP.Panel.TextWidth(ui.prof)
        - CP.GuideTab.COLUMNS.gap * 4
    local measure = function(text) return CP.Panel.TextWidth(ui.skillText, text) end
    local lines = CP.GuideTab.HeaderLines(with, count, math.max(1, room), measure)
    ui.skillText:SetText(table.concat(lines, "\n"))
    ui.headerExtra = (#lines - 1) * S.LineHeight("body")
    ui.bar:SetPoint("TOPLEFT", 0, BAR_TOP - ui.headerExtra)
    ui.empty:SetPoint("TOPLEFT", 0, LIST_TOP - 4 - ui.headerExtra)
    ui.scroll:SetPoint("TOPLEFT", 0, LIST_TOP - ui.headerExtra)
end

-- A step row's height: always ROW_H, since names stay on one line.
function CP.GuideTab.RowHeight() return ROW_H end

-- The room the window leaves a step row's name, in px: the row less both columns, the pin
-- and their gaps (the parts CP.GuideTab.Measure counts).
function CP.GuideTab.NameRoom()
    local C, P = CP.GuideTab.COLUMNS, CP.Panel
    local row = P.WIDTH - 2 * P.BODY_PAD - C.list
    return row - (C.left + ui.rangeW + C.gap + C.edge + ui.infoW + C.edge + S.PIN + C.edge)
end

-- True when `recipe`'s pattern is in the bags, bank or mail and the recipe is not learned.
-- `learned` comes from the live list, or the saved one for a shut window.
function CP.GuideTab.PatternOwned(recipe, learned, stop)
    local item = recipe and recipe.pattern
    if not item or learned or stop then return false end
    return CP.Purchases.Have(item) > 0
end

-- A step row as the list draws it: its text, the pick, and the dimming of unlearned recipes.
function CP.GuideTab.PaintRow(btn, row)
    btn:SetHeight(ROW_H)
    initRow(btn, row)
    S.PickRow(btn, row.key == pickOf(profID))
    S.OwnedRow(btn, CP.GuideTab.PatternOwned(row.recipe, row.learned, row.rank or row.train))

    -- Unlearned recipes can't be picked in the profession window: their name is muted, their range dimmed.
    local alpha = row.spell and row.learned == false and not (row.rank or row.train) and S.UNLEARNED_ALPHA or 1
    btn.name:SetAlpha(1)
    btn.range:SetAlpha(alpha)
end

local function buildOne(c)
    ui.prof = S.Text(c, "title", S.color.title)
    ui.prof:SetPoint("TOPLEFT", 0, -2)

    ui.skillText = S.Text(c, "body", S.color.label)
    ui.skillText:SetPoint("TOPRIGHT", 0, -2)
    ui.skillText:SetJustifyH("RIGHT")

    -- The skill text is a switch while a coupling setting applies (CP.GuideTab.SwitchLines):
    -- Daylight UI's tab ink, brighter on hover.
    ui.switch = S.TextSwitch(c, ui.skillText, function() CP.GuideTab.SwitchClick() end, switchTip)

    ui.bar = S.Bar(c, 8)
    ui.bar:SetPoint("TOPLEFT", 0, BAR_TOP)
    ui.bar:SetPoint("RIGHT")

    ui.empty = S.Text(c, "body", S.color.muted)
    ui.empty:SetPoint("TOPLEFT", 0, LIST_TOP - 4)
    ui.empty:SetPoint("RIGHT")

    buildDetails(c)
    buildImpromptu(c)

    ui.scroll = CreateFrame("Frame", nil, c, "WowScrollBoxList")
    ui.scroll:SetPoint("TOPLEFT", 0, LIST_TOP)
    ui.scroll:SetPoint("BOTTOMRIGHT", ui.impromptu, "TOPRIGHT", 0, LIST_GAP)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    if view.SetElementExtentCalculator then
        view:SetElementExtentCalculator(function(_, row) return CP.GuideTab.RowHeight(row) end)
    end
    view:SetElementInitializer("Button", CP.GuideTab.PaintRow)
    ui.scrolling = S.ListScroll("guide step list", ui.scroll, view, c)
    ui.scrollBar = ui.scrolling.plain
end

-- Rows for the plan's steps, with what the player knows and can craft. `alias` maps a
-- guide recipe to the player's own spell of the same name (Plan.Alias).
local function stepRows(guide, plan, recipes, alias)
    -- A saved plan carries its keeps (Plan.Commit); it doesn't recount them from the bags.
    local keeps = plan.frozen and {} or CP.Guide.Keeps(guide, plan, CP.Plan.Held(guide))
    local known, craftable = {}, {}
    for _, r in ipairs(recipes) do
        known[r.id] = r.learned
        craftable[r.id] = r.craftable
    end
    for id, liveID in pairs(alias or {}) do
        known[id] = known[liveID]
        craftable[id] = craftable[liveID]
    end
    local rows, made = {}, {}
    for i, st in ipairs(plan) do
        if st.spell then
            -- A maker step makes at least what later steps keep from it.
            local keep = st.keepCount and { count = st.keepCount, names = st.keepNames } or keeps[i]
            local crafts = st.first and CP.Plan.StepCrafts(st)
                or math.max(st.crafts, CP.Guide.KeepCrafts(guide.recipes[st.spell], keep and keep.count))
            -- What earlier rows make, less what the rows between use: a later row leaves that much to
            -- them (decision 0008, rule 6).
            local supplied
            for item, n in pairs(made) do
                if n > 0 then
                    supplied = supplied or {}
                    supplied[item] = n
                end
            end
            local r = guide.recipes[st.spell]
            for _, pair in ipairs(r and r.reagents or {}) do
                if made[pair[1]] then made[pair[1]] = math.max(0, made[pair[1]] - pair[2] * crafts) end
            end
            if r and r.makes then made[r.makes] = (made[r.makes] or 0) + crafts * (r.yield or 1) end
            rows[#rows + 1] = {
                keep = keep, planIndex = i, supplied = supplied,
                key = st.from, spell = st.spell, from = st.from, to = st.to, crafts = crafts, cost = st.cost,
                recipe = guide.recipes[st.spell], learned = known[st.spell] == true,
                craftable = craftable[st.spell] or 0, current = #rows == 0,
            }
        end
    end
    return rows, craftable
end

-- A step's "or" rows: its side craft, then any more (a limited pattern's alternatives).
local function sidesOf(side)
    if not side then return {} end
    local list = { side }
    for _, more in ipairs(side.more or {}) do list[#list + 1] = more end
    return list
end

-- Put each side craft (one that uses hides) right under the main step it can stand
-- in for, marked as interchangeable.
local function withSides(rows, sides, craftable)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = row
        for k, side in ipairs(sidesOf(row.planIndex and sides[row.planIndex])) do
            out[#out + 1] = {
                side = true, key = "side" .. row.from .. (k > 1 and ("." .. k) or ""), spell = side.spell,
                recipe = side.recipe, from = row.from, to = row.to, crafts = side.crafts, learned = side.learned,
                craftable = craftable[side.spell] or 0, rareFor = side.rareFor, fallback = side.fallback,
                withFish = side.withFish, limited = side.limited, lo = side.lo, upto = side.upto,
            }
        end
    end
    return out
end

-- The learned step recipes, by the player's own spell id, for Daylight UI's recipe lines:
-- the first one of a profession "current", the rest "step". `marks` collects several
-- professions' marks.
local function stepMarks(rows, alias, marks)
    marks = marks or {}
    local first = true
    for _, row in ipairs(rows) do
        if row.spell and row.learned and not (row.rank or row.train) then
            local id = alias and alias[row.spell] or row.spell
            if marks[id] == nil then marks[id] = first and "current" or "step" end
            first = false
        end
    end
    return marks
end

-- A row as the plan without couplings would have to show it to count as the same row.
local function rowKey(row)
    if row.rank then return "rank " .. tostring(row.rank.name) end
    if row.train then
        local names = {}
        for i, r in ipairs(row.train.recipes) do names[i] = r.name end
        table.sort(names)
        return ("train %d %s"):format(row.train.skill, table.concat(names, ","))
    end
    return ("%s %d-%d %d"):format(tostring(row.spell), row.from, row.to, math.floor((row.crafts or 0) * 100 + 0.5))
end

-- Marks the rows another profession changed: each main and stop row the plan without
-- couplings (Plan's `live.plain`) does not show, and each "or" row under a changed step or
-- on a recipe a coupling let in (the "or" rows come from their own solves, so they are
-- judged by their recipe). A changed row names every coupling that picked a step, a step
-- on a coupled recipe its own causes first (`own`). A step Enchanting's credit chose is
-- `forEnchanting`, and a step keeping its products for one `keepForEnchanting`.
local joinedStops

local function markCauses(live, main, all, alone)
    -- `live.coupled`: the professions the header names, while a row carries a cause.
    live.coupled = nil
    if not live.causes then return end
    local guide = live.guide
    local count
    if live.plain then
        local plainMain = stepRows(guide, live.plain, live.recipes, live.alias)
        -- The same "or" rows train at the same visits.
        local ors = {}
        for _, row in ipairs(main) do
            if row.ors then ors[rowKey(row)] = row.ors end
        end
        for _, row in ipairs(plainMain) do row.ors = ors[rowKey(row)] end
        count = {}
        -- Joined as the shown rows are, so a run counts as the same row on both sides.
        for _, row in ipairs(joinedStops(live, plainMain, alone or {})) do
            local k = rowKey(row)
            count[k] = (count[k] or 0) + 1
        end
    end
    local every, seen = { lines = {} }, {}
    for _, st in ipairs(live.plan) do
        for _, line in ipairs(st.spell and live.causes(st.spell, guide.recipes[st.spell]) or {}) do
            if not seen[line] then
                seen[line] = true
                every.lines[#every.lines + 1] = line
            end
        end
    end
    -- A row names only its own causes: the professions that picked its recipe.
    local function own(r, spell)
        local c = r and live.causes(spell, r)
        if not (c and #c > 0) then return nil end
        local lines = {}
        for _, line in ipairs(c) do lines[#lines + 1] = line end
        return { lines = lines, own = true, de = c.de, via = c.via }
    end
    -- An "or" row's own causes other than the credit: a recipe the credit only cheapens may
    -- stand there without Enchanting too.
    local function admitted(r, spell)
        local c = own(r, spell)
        if not c then return nil end
        local lines = {}
        for _, line in ipairs(c.lines) do
            if not (c.de and line == CP.Shared.ENCHANTING) then lines[#lines + 1] = line end
        end
        return #lines > 0 and { lines = lines, own = true, via = c.via } or nil
    end
    local parent
    for _, row in ipairs(all) do
        if row.side then
            row.cause = parent and (own(row.recipe, row.spell) or parent) or admitted(row.recipe, row.spell)
        elseif count then
            local k = rowKey(row)
            if (count[k] or 0) > 0 then
                count[k] = count[k] - 1
                parent = nil
            else
                local step = row.spell and not (row.rank or row.train)
                -- A row that changed only because an earlier step moved names no profession,
                -- and neither do its "or" rows.
                row.cause = step and own(row.recipe, row.spell) or CP.GuideTab.ShiftedCause(every)
                parent = step and { lines = row.cause.lines, shifted = row.cause.shifted } or nil
            end
        end
    end
    -- The header names every profession that picked a step, once any row changed.
    local chosen, any = {}, false
    for _, row in ipairs(all) do if row.cause then any = true end end
    if any and #every.lines > 0 then
        live.coupled = {}
        for i, line in ipairs(every.lines) do live.coupled[i] = line end
    end
    for _, row in ipairs(all) do
        if row.cause and row.cause.own and row.cause.de then
            row.forEnchanting = true
            if not row.side then chosen[row.recipe.name] = true end
        end
    end
    for _, row in ipairs(main) do
        for _, name in ipairs(row.keep and row.keep.names or {}) do
            if chosen[name] then row.keepForEnchanting = true end
        end
    end
end

local function runKey(row) return ("%d:%d:%d"):format(row.spell, row.from, row.to) end

-- The main rows that stay rows of their own when Guide.JoinRuns joins a recipe's run: the steps
-- the saved plan locks (Plan.Locks) and the steps with "or" rows. A set of runKey strings.
local function aloneKeys(live, main)
    local keys = {}
    local c = CP.Plan.Committed and CP.Plan.Committed(live.prof.id)
    if c and c.steps and CP.Plan.Locks then
        for i in pairs(CP.Plan.Locks(c, live.guide, live.prof.skill, live.learned or {}, live.dead)) do
            local f = c.steps[i]
            keys[("%d:%d:%d"):format(f[3], f[1], f[2])] = true
        end
    end
    for _, row in ipairs(main) do
        if #sidesOf(live.sides and live.sides[row.planIndex]) > 0 then keys[runKey(row)] = true end
    end
    return keys
end

-- WithStops' rows for `main` with each recipe's run joined into one row (Guide.JoinRuns).
function joinedStops(live, main, alone)
    local p = live.prof
    return CP.Guide.JoinRuns(CP.Guide.WithStops(live.guide, main, live.learned or {}, p.skill, p.max),
        function(row) return alone[runKey(row)] end)
end

-- The step list's rows for a guided `live`: main steps with their stops, each recipe's run
-- one row, each side craft under the step it can stand in for.
local function guideRows(live)
    local guide = live.guide
    if not (guide and live.plan and live.recipes) then return {} end
    local main, craftable = stepRows(guide, live.plan, live.recipes, live.alias)
    -- A limited pattern's "or" rows train at the visit before it (Guide.TrainStops).
    for _, row in ipairs(main) do
        for _, side in ipairs(sidesOf(live.sides and live.sides[row.planIndex])) do
            if side.limited then
                row.ors = row.ors or {}
                row.ors[#row.ors + 1] = side.spell
            end
        end
    end
    local alone = aloneKeys(live, main)
    local all = withSides(joinedStops(live, main, alone), live.sides or {}, craftable)
    markCauses(live, main, all, alone)
    return all
end

-- The row the vendor Buy works from for `live`: the picked row while it belongs to this
-- profession and is a craft (a main step or an "or" row), else the current step, the first
-- main craft row. `usePick` false skips the pick. Returns the row, nil when none.
CP.GuideTab.RowsOf = guideRows

function CP.GuideTab.Selected(live, usePick)
    local rows = guideRows(live)
    local function craft(row) return row.recipe and row.spell and not (row.rank or row.train or row.recipe.deskill) end
    local picked = usePick and pickOf(live.prof.id)
    if picked then
        for _, row in ipairs(rows) do
            if row.key == picked and craft(row) then return row end
        end
    end
    for _, row in ipairs(rows) do
        if craft(row) and not row.side then return row end
    end
end

-- What the selection hangs on, so the vendor Buy offers again when it changes.
function CP.GuideTab.PickKey()
    return tostring(profID) .. ":" .. tostring(pickOf(profID))
end

-- Sets Daylight UI's recipe-line marks from the guide's steps, whatever the mode, the tab or
-- whether the window shows: One mode marks the chosen profession, All mode every guided one.
function CP.GuideTab.UpdateMarks()
    if not CP.CraftRows then return end
    local lives = CP.Window.Mode() == "all" and CP.Window.AllLives() or { CP.Window.Live() }
    local marks = {}
    for _, live in ipairs(lives) do
        if live.guide and not live.offline then stepMarks(guideRows(live), live.alias, marks) end
    end
    CP.CraftRows.Set(marks)
end

-- Steps move with skill, recipes, bags and the profession window: the marks follow, shown or not.
for _, event in ipairs({ "ProfLost_SKILLS", "NEW_RECIPE_LEARNED", "BAG_UPDATE_DELAYED", "TRADE_SKILL_SHOW",
                         "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE" }) do
    CP:On(event, function()
        -- A shown One-mode guide tab redraws on these events and sets the marks itself.
        local P = CP.Panel
        local drawn = P.frame:IsShown() and (P.folded or P.current == "guide") and CP.Window.Mode() == "one"
        if not drawn then CP:Soon("stepMarks", CP.GuideTab.UpdateMarks) end
    end)
end

local function refreshOne()
    local live = CP.Window.Live()
    ui.live = live
    -- Folded, the header sits right above the details box: no step list.
    local folded = CP.Panel.folded
    ui.scroll:SetShown(not folded)
    ui.scrollBar:SetShown(not folded)
    if not live then
        ui.prof:SetText("")
        fitHeader(nil, "")
        ui.switch:Hide()
        ui.bar:SetValue(0)
        ui.empty:SetText("No profession to guide yet. Learn one at a trainer.")
        ui.empty:Show()
        ui.rows = {}
        CP.Panel.SetNeed("guide", nil)
        ui.details:Hide()
        fillImpromptu(nil)
        ui.scroll:SetDataProvider(CreateDataProvider({}), true)
        return
    end
    local p, guide = live.prof, live.guide

    profID = p.id
    skill = p.skill

    ui.prof:SetText(p.name)
    ui.bar:SetMinMaxValues(0, math.max(p.max, 1))
    ui.bar:SetValue(p.skill)

    ui.guide = guide

    local rows = {}
    ui.line = not guide and gatherLine(p) or nil
    if ui.line then
        rows = gatherGuideRows(p, ui.line)
    elseif guide then
        rows = guideRows(live)
    end
    -- The professions that changed this plan, once, beside the skill.
    local with = not ui.line and CP.GuideTab.WithText(live)
    local skillText = ("%d / %d"):format(p.skill, p.max)
    ui.skillText:SetText(with and (with .. " · " .. skillText) or skillText)

    if ui.line and not GG.Ready(ui.line) then
        ui.empty:SetText("Finding the zones for this guide.")
    elseif ui.line then
        ui.empty:SetText("Skill maxed. Nothing left to level.")
    elseif not guide then
        ui.empty:SetText("No guide for this profession yet.")
    else
        ui.empty:SetText("Guide complete. No more steps above your skill.")
    end
    ui.empty:SetShown(#rows == 0)
    ui.rows = rows
    if CP.CraftRows and not live.offline then CP.CraftRows.Set(stepMarks(rows, live.alias)) end

    local chosen
    local picked = pickOf(p.id)
    local away = displaced[p.id]
    if away and away.skill ~= p.skill then away, displaced[p.id] = nil, nil end
    for _, row in ipairs(rows) do
        if away and row.key == away.key then chosen = row end
    end
    if chosen then
        setPick(p.id, chosen.key)
    else
        for _, row in ipairs(rows) do
            if row.key == picked then chosen = row end
        end
    end
    if not chosen and rows[1] then
        chosen = rows[1]
        displaced[p.id] = picked ~= nil and { key = picked, skill = p.skill } or away
        picks()[p.id] = chosen.key
    end
    ui.switch:SetShown(not ui.line and CP.GuideTab.SwitchLines(live) ~= nil)
    local need = CP.GuideTab.Measure(rows)
    CP.Panel.SetNeed("guide", need)
    if CP.Panel.ApplyWidth() then CP.Window.Chrome() end
    fitHeader(with, skillText)

    if chosen then
        fillDetails(chosen)
        CP.GuideTab.OvershootNote(chosen, live)
    else
        ui.details:Hide()
    end
    if not (ui.details:IsShown() and ui.details.craftAll.usePattern) then CP.PatternLearn.Release() end
    fillImpromptu(live)

    -- Second argument keeps the scroll position across refreshes.
    ui.scroll:SetDataProvider(CreateDataProvider(rows), true)
end

-- A recipe picked in the profession window: pick the guide row for it, a main step before
-- an "or" row. Nothing when no row has it or a row of it is already picked (our own pick
-- echoing back, an "or" row's too).
function CP.GuideTab.Follow(recipeID)
    local alias = ui.live and ui.live.alias or {}
    local found
    local picked = pickOf(profID)
    for _, row in ipairs(ui.rows or {}) do
        if row.spell and (row.spell == recipeID or alias[row.spell] == recipeID) then
            if row.key == picked then return false end
            if not row.side then found = found and not found.side and found or row end
            found = found or row
        end
    end
    if not found then return false end
    setPick(profID, found.key)
    if CP.Buying then CP.Buying.Changed() end
    CP.Panel:Refresh()
    return true
end

-- All mode ----------------------------------------------------------------------

local CARD_H = 62

-- A card for `live`: { key, name, skill, step, need, needColor, spell, learned, open }.
-- Crafting professions read the plan's next step (Gather.NextStep); gathering ones read
-- their gathering guide's next stretch.
local function baseCard(live)
    local p, guide = live.prof, live.guide
    local card = { key = CP.Window.KeyOf(live), name = p.name or "", skill = ("%d / %d"):format(p.skill, p.max),
                   open = not live.offline }
    if guide then
        local st = live.plan and CP.Gather.NextStep(guide, p, live.plan, live.learned)
        if not st then
            card.step, card.need, card.needColor = "Guide complete", "", S.color.good
            return card
        end
        if st.rank then
            card.step = CP.Guide.StopText({ rank = st.rank })
            local target, who = CP.Guide.WaypointFor({ rank = st.rank }, p)
            card.go, card.goLabel, card.guide = target, target and CP.GuideTab.GO_LABELS[who], guide
            card.need, card.needColor = ("Skill capped at %d"):format(p.max), S.color.warn
            if st.levelShort then card.need = ("%s. %s"):format(card.need, st.levelShort.text) end
            return card
        end
        -- A disenchant step: the Disenchant tab does it, so the card casts nothing.
        if st.deskill then
            card.step = ("%s  %d-%d"):format(CP.Deskill.NAME, st.from or p.skill, st.to)
            card.need, card.needColor, card.deskill = CP.Deskill.CardText(st.crafts), S.color.label, true
            return card
        end
        card.step = ("%s  %d-%d"):format(st.name, st.from or p.skill, st.to)
        local stepRecipe = guide.recipes[st.spell]
        if stepRecipe then
            card.stepColor = diffColor(difficultyAt(stepRecipe, math.max(p.skill, st.from or p.skill)))
        end
        card.spell, card.learned = (live.alias and live.alias[st.spell]) or st.spell, st.learned
        -- Its crafts and what the bags make, as the One view's row for the step counts them.
        if not live.offline and live.recipes then
            for _, row in ipairs((stepRows(guide, live.plan, live.recipes, live.alias))) do
                if row.spell == st.spell and row.to > p.skill then
                    card.crafts, card.craftable = row.crafts, row.craftable
                    card.reagents = Prof.Reagents(row.spell, row.recipe and row.recipe.reagents)
                    -- What Craft all's tooltip reads, as one comparable string.
                    local counts = {}
                    for i, m in ipairs(card.reagents) do counts[i] = ("%s:%s:%s"):format(tostring(m.itemID), tostring(m.need), tostring(m.have)) end
                    card.reagentKey = table.concat(counts, ",")
                    if guide == CP.Guides[CP.Shared.ENCHANTING] and CP.EnchantAgain.SlotFor(row.recipe) then
                        card.enchant = row
                    end
                    break
                end
            end
        end
        local item = st.item and (CP.ItemName(st.item) or ("item " .. st.item))
        if not st.learned and live.unread then
            -- It may be known already: the card's one button reads Open.
            card.unread = true
            card.need, card.needColor = CP.Plan.OpenOnce(live), S.color.warn
        elseif not st.learned then
            -- Learn's waypoint target, or false when no trainer or vendor is known.
            local r = guide.recipes[st.spell]
            local target, who
            if r then target, who = CP.Guide.WaypointFor({ recipe = r, learned = false }, p) end
            card.learn, card.who, card.recipe, card.guide = target or false, who, r, guide
            card.gate = r and CP.Guide.LearnGate(r, p) or nil
            card.gateLabel = card.gate and card.gate.label
            card.need, card.needColor = "Learn " .. st.name, S.color.warn
            card.owned = CP.GuideTab.PatternOwned(r, false) or nil
            card.inBags = card.owned and CP.PatternLearn.InBags(r.pattern) > 0 or nil
            -- In the bags the pattern's own gate (skill, level) stands, not the trainer's.
            if card.inBags then
                card.gate = CP.PatternLearn.Gate(r, p)
                card.gateLabel = card.gate and card.gate.label
            end
        elseif st.short > 0 and item then
            card.need, card.needColor = CP.Gather.NeedText(st, function() return item end), S.color.warn
        elseif st.bank then
            local name = CP.ItemName(st.bank.item) or ("item " .. st.bank.item)
            card.need, card.needColor = ("Bank: %s x%d"):format(name, st.bank.count), S.color.warn
        else
            local text, tool = CP.Gather.ReadyText(st, guide)
            card.need, card.needColor, card.ready = text, tool and S.color.warn or S.color.good, not tool
        end
        -- Past the cap the craft buttons grey with the reason; the rank comes first.
        local held = CP.Guide.PastCap(guide, st.from, p.skill, p.max)
        if held then
            card.capped = CP.Guide.CapText(held)
            card.need, card.needColor, card.ready = card.capped, S.color.warn, nil
        end
        -- A rank the skill has opened but the level can't train yet.
        if st.levelShort then
            card.need, card.needColor = ("%s  ·  %s"):format(card.need, st.levelShort.text), S.color.warn
        end
        return card
    end
    local line = gatherLine(p)
    local ready = not line or GG.Ready(line)
    local nextUp = line and ready and GG.Next(GG.PlayerRows(line, p.skill, p.max), p.skill, p.max)
    if not line or p.skill >= 300 then
        card.step, card.need, card.needColor = "Maxed", "", S.color.good
    elseif not ready then
        GG.Warm(line)
        CP.GuideTab.waitingZones = true
        card.step, card.need, card.needColor = "Gather", GG.WARM.waiting, S.color.label
    elseif nextUp and nextUp.train then
        card.step, card.need, card.needColor = "Train " .. nextUp.train, "at a trainer", S.color.warn
    elseif nextUp and nextUp.zone and nextUp.level and nextUp.level > (CP.Gather.PlayerLevel() or 0) then
        card.step = "Gather in " .. zoneName(nextUp.zone)
        card.need, card.needColor = ("Reach level %d first"):format(nextUp.level), S.color.warn
    elseif nextUp and nextUp.zone then
        card.step = "Gather in " .. zoneName(nextUp.zone)
        card.need, card.needColor = nextUp.zone == CP.Gather.PlayerZone() and "You're in this zone" or "", S.color.label
    else
        card.step, card.need, card.needColor = "Gather", "", S.color.label
    end
    return card
end

-- The All card's impromptu line: the best craft the spare loot in the bags makes (CP.Impromptu),
-- on the Single view's rules. Gathering professions have no guide and so no line.
function CP.GuideTab.Card(live)
    local card = baseCard(live)
    local best = live.guide and CP.Impromptu.List(live, 1)[1]
    if best then
        card.impLine = CP.Impromptu.Info(best, true)
        card.impSpell, card.impCount, card.impItem = best.spell, best.crafts, best
    end
    return card
end

-- Card craft buttons: the step card's Craft 1, Available and Craft all, with short
-- labels so the three fit beside the card's need line.
CP.GuideTab.CARD_LABELS = { one = "Craft 1", avail = "Avail %d", availNone = "Avail", all = "All %d" }
local CARD_BTN_H, CARD_BTN_PAD, CARD_BTN_GAP = 18, 14, 4

-- The room the impromptu line takes at the foot of a card that has one.
local IMPROMPTU_H = CARD_BTN_H + 4
function CP.GuideTab.ImpromptuHeight() return IMPROMPTU_H end

-- The making strip on the open profession's card while a batch of ours runs: the step
-- card's strip at the card buttons' height.
CP.GuideTab.CARD_STRIP = { height = CARD_BTN_H, stop = 48, text = "small" }

-- A card button's width for its label.
local function fitCard(b)
    b:SetWidth(CP.Panel.TextWidth(b.label) + CARD_BTN_PAD)
end

local function cardClick(self)
    if self.learnTo then return CP.Waypoint.ToRecipe(self.guide, self.learnTo) end
    if self.openTo then
        -- OpenTradeSkill first, while the click's hardware event holds: the switch to the
        -- One Prof view on this profession hides the card and its button.
        local opened = CP.Window.OpenTo(self.openTo, self.spell)
        CP.Window.Pick(self.openTo)
        return opened
    end
    if self.enchantRow then return CP.EnchantAgain.Press(self.enchantRow) end
    -- Drawn while this profession's window was open, pressed after another opened: the
    -- game would refuse the craft, so the press opens the card's window, as Open does.
    local card = self:GetParent().card
    if card and CP.Window.OpenID() ~= card.key then
        local opened = CP.Window.OpenTo(card.key, self.spell)
        CP.Window.Pick(card.key)
        return opened
    end
    CP.Crafting.Start(self.spell, self.count)
end

local function cardButton(btn)
    local b = button(btn, 56)
    b:HookScript("OnEnter", function(self) CP.PatternLearn.Enter(self) end)
    b:SetHeight(CARD_BTN_H)
    b:SetScript("OnClick", cardClick)
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnEnter", craftTip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- What a card's buttons read: `craft` (Craft all, or the one Open, Learn or enchant
-- button), and with the profession's window open `avail` and `one`; `making` while a
-- batch of ours runs. Its craft state: here, learn, can, open.
local function cardLabels(card)
    local here = card.open and CP.Window.OpenID() == card.key
    local learn = card.spell ~= nil and not card.learned and not card.unread
    local can = here and card.learned and card.spell
    local open = not here and (card.spell ~= nil or card.deskill == true)
    local go = card.go ~= nil and card.goLabel ~= nil
    local state = { here = here, learn = learn, can = can, open = open, go = go }
    if go then return { craft = card.goLabel }, state end
    if can and not card.enchant and CP.Crafting.ShowStrip() then return { making = true }, state end
    if learn and card.owned then
        if not card.inBags then return { craft = CP.GuideTab.FETCH_LABEL }, state end
        return { craft = card.gate and card.gate.label or CP.PatternLearn.LABEL }, state
    end
    if learn then
        return { craft = card.gate and card.gate.label or CP.GuideTab.LearnLabel(card.recipe) }, state
    end
    if can and card.enchant then return { craft = CP.EnchantAgain.Label(card.enchant.recipe) }, state end
    if can then
        local L = CP.GuideTab.CARD_LABELS
        local crafts, have = card.crafts or 1, card.craftable or 0
        local avail = math.min(have, crafts)
        return { one = L.one, avail = avail > 0 and L.avail:format(avail) or L.availNone, craft = L.all:format(crafts) }, state
    end
    if open then return { craft = "Open" }, state end
    return {}, state
end

-- A card's height: CARD_H, taller when its step line or its need line wraps. The need line
-- takes the room its buttons leave; the step line the card's width.
function CP.GuideTab.CardHeight(card)
    local w = CP.Panel.WIDTH - 2 * CP.Panel.BODY_PAD - 12 - 16
    local step = math.max(1, #S.Lines(card.step or "", "body", math.max(1, w)))
    local labels = cardLabels(card)
    local buttons = 0
    for _, key in ipairs({ "one", "avail", "craft" }) do
        if labels[key] then buttons = buttons + S.Measure(labels[key], "small") + CARD_BTN_PAD + CARD_BTN_GAP end
    end
    local need = labels.making and 1 or #S.Lines(card.need or "", "small", math.max(1, w - buttons - 6))
    return CARD_H + math.max(0, need - 1) * S.LineHeight("small") + (step - 1) * S.LineHeight("body")
        + (card.impLine and IMPROMPTU_H or 0)
end

local function allCardHeight(card) return card and card.height or CARD_H end

local function initCard(btn, card)
    if not btn.name then
        S.Interactive(btn)
        S.Rule(btn)
        btn.name = S.Text(btn, "head", S.color.title)
        btn.name:SetPoint("TOPLEFT", 8, -6)
        btn.skill = S.Column(S.Text(btn, "small", S.color.label))
        btn.skill:SetPoint("TOPRIGHT", -8, -8)
        btn.skill:SetJustifyH("RIGHT")
        btn.step = S.Text(btn, "body")
        btn.step:SetPoint("TOPLEFT", 8, -24)
        btn.step:SetPoint("RIGHT", -8, 0)
        btn.step:SetWordWrap(true)
        btn.step:SetJustifyH("LEFT")
        -- Right to left: Craft all (or the one Open, Learn or enchant button), Available, Craft 1.
        btn.craft = cardButton(btn)
        btn.craft:SetPoint("BOTTOMRIGHT", -8, 4)
        btn.avail = cardButton(btn)
        btn.avail:SetPoint("RIGHT", btn.craft, "LEFT", -CARD_BTN_GAP, 0)
        btn.one = cardButton(btn)
        btn.one:SetPoint("RIGHT", btn.avail, "LEFT", -CARD_BTN_GAP, 0)
        btn.need = S.Text(btn, "small")
        btn.need:SetWordWrap(true)
        -- The impromptu line sits at the card's foot, its button at the right.
        btn.impBtn = cardButton(btn)
        btn.impBtn:SetPoint("BOTTOMRIGHT", -8, 4)
        btn.impLine = S.OneLine(S.Text(btn, "small", S.color.muted))
        btn.impLine:SetPoint("BOTTOMLEFT", 8, 8)
        btn.impLine:SetPoint("RIGHT", btn.impBtn, "LEFT", -6, 0)
        btn.impLine:SetJustifyH("LEFT")
        btn:SetScript("OnClick", function(self) CP.Window.Pick(self.card.key) end)
    end
    btn.card = card
    S.OwnedRow(btn, card.owned)
    btn.name:SetText(card.name)
    btn.skill:SetText(card.skill)
    btn.step:SetText(card.step or "")
    btn.step:SetTextColor(unpack(card.stepColor or S.color.text))
    btn.need:SetText(card.need or "")
    btn.need:SetTextColor(unpack(card.needColor or S.color.muted))
    -- The impromptu line and its button, on the card's craft rules: Craft with this profession's
    -- window open, else Open. The card's own buttons stand above it.
    local lift = card.impLine and IMPROMPTU_H or 0
    btn.impLine:SetShown(card.impLine ~= nil)
    btn.impBtn:SetShown(card.impLine ~= nil)
    if card.impLine then
        btn.impLine:SetText(card.impLine)
        local ib = btn.impBtn
        ib.spell, ib.count, ib.learnTo, ib.enchantRow, ib.usePattern = card.impSpell, card.impCount, nil, nil, nil
        if card.open and CP.Window.OpenID() == card.key then
            ib.openTo, ib.tip = nil, nil
            ib.label:SetText("Craft")
            S.SetEnabled(ib, not CP.Crafting.Busy())
        else
            local why = CP.Window.OpenBlocked()
            ib.openTo, ib.tip = card.key, why
            ib.label:SetText("Open")
            S.SetEnabled(ib, why == nil)
        end
        fitCard(ib)
        -- Room for the line: the card's width less its edges and the button. The name gives way first.
        local room = (btn:GetWidth() or 0) - 8 - 6 - (ib:GetWidth() or 0) - 8
        if card.impItem and room > 0 then
            btn.impLine:SetText(CP.Impromptu.Info(card.impItem, true, function(text)
                btn.impLine:SetText(text)
                return btn.impLine:GetStringWidth() <= room
            end))
        end
    end
    -- Craft only while this profession's window is open: the game crafts from it. Then
    -- the card has the step card's three buttons, on by the same rules. Shut, or on
    -- another profession, one button reads Open. A step not learned yet reads Learn
    -- either way: a waypoint to its trainer or pattern vendor.
    local labels, st = cardLabels(card)
    local learn, can, open = st.learn, st.can, st.open
    local b = btn.craft
    b:ClearAllPoints()
    b:SetPoint("BOTTOMRIGHT", -8, 4 + lift)
    b:SetShown((learn or can or open or st.go) and true or false)
    btn.one:Hide()
    btn.avail:Hide()
    -- A batch of ours on this card's profession: the making strip in place of its buttons.
    local making = labels.making
    if making and not btn.making then
        btn.making = CP.Crafting.Strip(btn, CP.GuideTab.CARD_STRIP)
    end
    if btn.making then
        btn.making:ClearAllPoints()
        btn.making:SetPoint("BOTTOMLEFT", 8, 4 + lift)
        btn.making:SetPoint("BOTTOMRIGHT", -8, 4 + lift)
        btn.making:SetShown(making and true or false)
    end
    btn.need:SetShown(not making)
    if making then
        b:Hide()
        btn.making:Update()
        return
    end
    b.spell, b.count, b.enchantRow = card.spell, 1, nil
    b.learnTo, b.guide, b.openTo, b.tip, b.usePattern = nil, nil, nil, nil, nil
    btn.one.tip, btn.avail.tip = nil, nil
    b.label:SetText(labels.craft or "")
    if st.go then
        -- A rank step: the button sets the waypoint to its trainer, book vendor or quest giver.
        b.learnTo, b.guide = card.go, card.guide
        S.SetEnabled(b, true)
    elseif learn and card.owned then
        -- The pattern is held: in the bags it is used through the secure overlay (PatternLearn.Enter);
        -- in the bank or mail it is fetched first.
        if card.inBags then
            b.usePattern = { spell = card.spell, item = card.recipe.pattern }
            b.tip = card.gate and card.gate.tip or nil
            S.SetEnabled(b, not card.gate and not InCombatLockdown())
        else
            b.tip = CP.GuideTab.FETCH_TIP
            S.SetEnabled(b, false)
        end
    elseif learn then
        local target = card.learn or nil
        b.learnTo, b.guide = target, card.guide
        b.tip = card.recipe and learnTip(card.guide, card.recipe, target, card.gate) or nil
        S.SetEnabled(b, target ~= nil)
    elseif can and card.enchant then
        local action = CP.EnchantAgain.Action(card.enchant.recipe)
        b.enchantRow = card.enchant
        S.SetEnabled(b, action == "confirm" or (action == "cast" and (card.craftable or 0) > 0))
    elseif can then
        local busy = CP.Crafting.Busy()
        local crafts, have = card.crafts or 1, card.craftable or 0
        local avail = math.min(have, crafts)
        local whole = have >= crafts and crafts or 0
        btn.one.spell, btn.one.count = card.spell, 1
        btn.avail.spell, btn.avail.count = card.spell, avail
        b.count = whole
        b.tip = CP.GuideTab.CraftAllTip(crafts, whole > 0, card.reagents)
        btn.one.label:SetText(labels.one)
        btn.avail.label:SetText(labels.avail)
        btn.one:Show()
        btn.avail:Show()
        S.SetEnabled(btn.one, have > 0 and not busy)
        S.SetEnabled(btn.avail, avail > 0 and not busy)
        S.SetEnabled(b, whole > 0 and not busy)
        if card.capped then
            for _, x in ipairs({ btn.one, btn.avail, b }) do
                x.tip = card.capped
                S.SetEnabled(x, false)
            end
        end
    elseif open then
        local why = CP.Window.OpenBlocked()
        b.openTo, b.tip = card.key, why
        S.SetEnabled(b, why == nil)
    end
    for _, x in ipairs({ btn.one, btn.avail, b }) do fitCard(x) end
    if CP.PatternLearn.over == b and not b.usePattern then CP.PatternLearn.Release() end
    -- The need line takes what the buttons leave.
    local left = btn.one:IsShown() and btn.one or b:IsShown() and b or nil
    btn.need:ClearAllPoints()
    btn.need:SetPoint("BOTTOMLEFT", 8, 8 + lift)
    if left then btn.need:SetPoint("RIGHT", left, "LEFT", -6, 0) else btn.need:SetPoint("RIGHT", -8, 0) end
end
CP.GuideTab.InitCard = initCard
CP.GuideTab.CardLabels = cardLabels

local function buildAll(c)
    ui.cards = CreateFrame("Frame", nil, c, "WowScrollBoxList")
    ui.cards:SetPoint("TOPLEFT")
    ui.cards:SetPoint("BOTTOMRIGHT", -12, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(CARD_H)
    -- A card whose need line wraps is taller (CP.GuideTab.CardHeight).
    if view.SetElementExtentCalculator then
        view:SetElementExtentCalculator(function(_, card) return allCardHeight(card) end)
    end
    view:SetElementInitializer("Button", initCard)
    ui.cardScrolling = S.ListScroll("All-mode cards", ui.cards, view, c)
    ui.allEmpty = S.Text(c, "body", S.color.muted)
    ui.allEmpty:SetPoint("TOPLEFT", 0, -4)
    ui.allEmpty:SetPoint("RIGHT")
    ui.allEmpty:SetText("No profession to guide yet. Learn one at a trainer.")
end

local CARD_FIELDS = { "key", "name", "skill", "step", "need", "needColor", "spell", "learned", "unread", "open", "ready", "learn", "gateLabel",
                      "crafts", "craftable", "reagentKey", "owned", "inBags", "height", "impLine", "impSpell", "impCount", "impItem" }

local function sameCards(a, b)
    if not a or #a ~= #b then return false end
    for i = 1, #a do
        for _, k in ipairs(CARD_FIELDS) do
            if a[i][k] ~= b[i][k] then return false end
        end
    end
    return true
end

local function reinitCard(btn)
    if btn.card then initCard(btn, btn.card) end
end

-- Unchanged cards keep their buttons; only the Craft or Open state is read again.
local function refreshAll()
    local cards = {}
    for _, live in ipairs(CP.Window.AllLives()) do
        local card = CP.GuideTab.Card(live)
        card.height = CP.GuideTab.CardHeight(card)
        cards[#cards + 1] = card
    end
    ui.allEmpty:SetShown(#cards == 0)
    CP.GuideTab.UpdateMarks()
    if sameCards(ui.cardList, cards) and ui.cards.ForEachFrame then
        ui.cards:ForEachFrame(reinitCard)
        return
    end
    ui.cardList = cards
    ui.cards:SetDataProvider(CreateDataProvider(cards), true)
end

local function build(c)
    ui.one = container(c)
    ui.one:SetAllPoints()
    buildOne(ui.one)
    ui.all = container(c)
    ui.all:SetAllPoints()
    ui.all:Hide()
    buildAll(ui.all)
end

local function refresh()
    local all = CP.Window.Mode() == "all"
    ui.one:SetShown(not all)
    ui.all:SetShown(all)
    if all then return refreshAll() end
    refreshOne()
end

-- The body height the folded window needs. One mode: the header, the impromptu area, then the details box
-- (or the empty line). All mode: the cards.
local EMPTY_H = 24

function CP.GuideTab.FoldedHeight()
    if CP.Window.Mode() == "all" then
        local h = 0
        for _, card in ipairs(ui.cardList or {}) do h = h + allCardHeight(card) end
        return h > 0 and h or EMPTY_H
    end
    local area = ui.impromptu and ui.impromptu:IsShown() and ui.impromptu:GetHeight() + LIST_GAP or 0
    return -LIST_TOP + (ui.headerExtra or 0) + area + (ui.details and ui.details:IsShown() and cardHeight() or EMPTY_H)
end

-- The steps the One view lists: the "Steps shown" setting. A step is a main row and the
-- "or" rows under it.
function CP.GuideTab.Steps()
    local v = CP.db and CP.db.guideSteps
    return CP.Settings.Bound("guideSteps", type(v) == "number" and v or CP.DEFAULTS.guideSteps)
end

-- The height of the first `n` steps, each with its "or" rows, and how many steps the guide
-- has of those `n`.
local function stepsHeight(n)
    local h, steps = 0, 0
    for _, row in ipairs(ui.rows or {}) do
        if not row.side then
            if steps == n then break end
            steps = steps + 1
        end
        h = h + CP.GuideTab.RowHeight(row)
    end
    return h, steps
end

-- The step list's height: Steps shown steps, fewer when the guide has fewer. The rest scroll.
function CP.GuideTab.ListHeight()
    local h = stepsHeight(CP.GuideTab.Steps())
    return h > 0 and h or EMPTY_H
end

-- The list's height at `n` steps as the corner grip measures it: a step the guide lacks
-- counts one row, so a drag still moves Steps shown on a short guide.
function CP.GuideTab.GripHeight(n)
    local h, steps = stepsHeight(n)
    return h + (n - steps) * CP.GuideTab.RowHeight()
end

-- The body height the unfolded Guide view needs. One mode: the header, the step list,
-- the impromptu area, then the details box. All mode: the cards.
function CP.GuideTab.OpenHeight()
    if CP.Window.Mode() == "all" then return CP.GuideTab.FoldedHeight() end
    local list = CP.GuideTab.ListHeight()
    local area = ui.impromptu and ui.impromptu:IsShown() and ui.impromptu:GetHeight() + LIST_GAP or 0
    return -LIST_TOP + (ui.headerExtra or 0) + list + LIST_GAP + area + (ui.details and ui.details:IsShown() and cardHeight() or 0)
end

CP.Panel:AddTab("guide", "Guide", build, refresh)
CP.Panel:SetTabNeed("guide", CP.GuideTab.OpenHeight)
