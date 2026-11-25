-- An All view card keeps its lines clear of its skill count at the narrowest window and the
-- largest text size. Fonts come from the visual world (tests/world/visual.lua).

local CP = ProfLost
local W, P, GT, S = CP.Window, CP.Panel, CP.GuideTab, CP.Style
local LW, TAILOR = 165, 197
local DUROTAR = 1411

local function settle() T.advance(0.5) end

local function scene()
    Visual.begin()
    DaylightWorld.begin({ plugin = true })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 5, [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowCollapsedAll", nil)
    World.set(CP.db, "windowWidth", W.LeastWidth())
    World.set(CP.db, "font", "wide")
    World.set(CP.db, "textScale", 1.15)
    World.set(CP.charDB, "guideMode", "all")
    World.set(W.managed, "mover", false)
    World.onEnd(function()
        CraftWorld.Close()
        S.ApplyScale()
        S.ApplyFont()
        W.SetMode("one")
        W.Update()
    end)
    S.ApplyScale()
    S.ApplyFont()
    W.SetMode("all")
    W.Update()
    P:Refresh()
    settle()
end

local function box(r)
    local l, rt, b, t = r:GetLeft(), r:GetRight(), r:GetBottom(), r:GetTop()
    if not (l and rt and b and t) then return nil end
    return { l, b, rt, t }
end

-- The span of a string's rect its text covers, by its justification.
local function ink(fs, r)
    local w = math.min(fs:GetUnboundedStringWidth() or 0, r[3] - r[1])
    if fs:GetJustifyH() == "RIGHT" then return r[3] - w, r[3] end
    return r[1], r[1] + w
end

T.test("an All card's lines stay clear of its skill count at the narrowest width and text size 1.15", function()
    scene()
    local card = GT.ui.cardList[1]
    T.ok(card ~= nil, "a card is listed")
    if not card then return end
    card.need = "Learn Embossed Leather Gloves 9483 Journeyman Leatherworking needs level 10 (you're 5)"
    card.skill = "64 / 75"
    card.height = GT.CardHeight(card)
    local b = CreateFrame("Button", nil, GT.ui.cards)
    b:SetPoint("TOPLEFT", GT.ui.cards, "TOPLEFT", 0, 0)
    b:SetPoint("TOPRIGHT", GT.ui.cards, "TOPRIGHT", 0, 0)
    b:SetHeight(card.height)
    GT.InitCard(b, card)
    local count = box(b.skill)
    T.ok(count ~= nil, "the count has a rect")
    if not count then return end
    local c1, c2 = ink(b.skill, count)
    for _, key in ipairs({ "name", "step", "need" }) do
        local fs = b[key]
        local r = fs:IsShown() and (fs:GetText() or "") ~= "" and box(fs)
        if r then
            local a1, a2 = ink(fs, r)
            local w = math.min(a2, c2) - math.max(a1, c1)
            local h = math.min(r[4], count[4]) - math.max(r[2], count[2])
            T.ok(not (w > 0.5 and h > 0.5), ("the card's %s line lies under the count %q"):format(key, card.skill))
        end
    end
    -- The need line fits inside the card's height: its top stays below the card's top edge.
    local card_box, need = box(b), box(b.need)
    T.ok(need and card_box and need[4] <= card_box[4] + 0.5, "the need line stays inside the card")
    b:Hide()
end)
