-- The guide window, stage 1: the free window, its
-- visibility setting, folding and closing, the All/One switch, plans for shut
-- professions, the Gather tab and the saved-data carry-over.

local CP = ProfLost
local W, P = CP.Window, CP.Panel
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR, COPPER_ORE = 1411, 2770

-- An open free window for this test, hidden in combat ("nocombat") or not ("always"),
-- applied as the options page would.
local function showMode(mode)
    World.set(CP.db, "hideInCombat", mode ~= "always")
    World.set(CP.db, "gatherHideInCombat", mode ~= "always")
    World.set(CP.db, "gatherHideCarried", CP.db.gatherHideCarried)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        T.fire("PLAYER_REGEN_ENABLED")
        W.opened = false
        W.Update()
    end)
    CP.Settings.Find("hideInCombat").apply()
end

local function shown() return P.frame:IsShown() end

-- One scene: Leatherworking and Tailoring, Tailoring's window opened once so its
-- known recipes are saved, then shut.
local function twoProfessions()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    CraftWorld.Open(TAILOR)
    CraftWorld.Close()
end

-- Visibility -----------------------------------------------------------------------

T.test("hide in combat: shown out of combat, hidden in combat, a profession window or not", function()
    twoProfessions()
    showMode("nocombat")
    T.ok(shown(), "shown out of combat")
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not shown(), "hidden in combat")
    T.fire("PLAYER_REGEN_ENABLED")
    T.ok(shown(), "back after combat")
    CraftWorld.Open(LW)
    T.ok(shown(), "shown with the profession window")
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not shown(), "and hidden in combat with it")
    T.fire("PLAYER_REGEN_ENABLED")
    CraftWorld.Close()
    T.ok(shown(), "still shown when it closes")
end)

T.test("hide in combat off: free in combat and out", function()
    twoProfessions()
    showMode("always")
    T.ok(shown())
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(shown(), "stays in combat")
    T.fire("PLAYER_REGEN_ENABLED")
    T.ok(shown())
end)

T.test("a closed window stays shut, saved, until the player opens it; a profession window leaves it shut", function()
    twoProfessions()
    showMode("nocombat")
    T.ok(W.closeButton:IsShown(), "close shows on the free window")
    W.closeButton:GetScript("OnClick")(W.closeButton)
    T.ok(not shown(), "closed")
    T.eq(CP.db.windowClosed, true, "saved, so a reload keeps it shut")
    T.fire("BAG_UPDATE_DELAYED")
    T.fire("PLAYER_REGEN_DISABLED")
    T.fire("PLAYER_REGEN_ENABLED")
    T.ok(not shown(), "combat ending doesn't bring it back")
    T.fire("PLAYER_ENTERING_WORLD")
    T.ok(not shown(), "nor does a loading screen")

    CraftWorld.Open(LW)
    T.ok(not shown(), "a profession window doesn't bring it back")
    CraftWorld.Close()
    T.ok(not shown(), "nor its closing")

    CP.Launcher.minimapObject.OnClick(nil, "LeftButton")
    T.ok(shown(), "the minimap button opens it")
    T.eq(CP.db.windowClosed, nil, "open is saved too")
    T.eq(W.opened, false, "out of combat nothing extra is held open")
    CP.Launcher.object.OnClick(nil, "LeftButton")
    T.ok(not shown(), "the data text's left-click closes it, as the minimap button's does")
    CP.Launcher.object.OnClick(nil, "LeftButton")
    T.ok(shown(), "and opens it")

    showMode("always")
    W.Close()
    T.fire("PLAYER_ENTERING_WORLD")
    T.ok(not shown(), "a loading screen doesn't reopen a closed window")
    SlashCmdList.PROFLOST("")
    T.ok(shown(), "/proflost does")
    SlashCmdList.PROFLOST("")
    T.ok(not shown(), "and closes it")
end)

T.test("hide in combat: opened in a fight it stays for the fight; the next fight hides it", function()
    twoProfessions()
    showMode("nocombat")
    W.Close()
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not shown())
    CP.Launcher.minimapObject.OnClick(nil, "LeftButton")
    T.ok(shown(), "opened in combat")
    T.eq(W.opened, true)
    T.fire("PLAYER_REGEN_ENABLED")
    T.ok(shown() and W.opened == false, "out of combat it simply shows")
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not shown(), "the next fight hides it")
    T.fire("PLAYER_REGEN_ENABLED")
end)

-- Folding and placement -----------------------------------------------------------------

local function fold() W.foldButton:GetScript("OnClick")(W.foldButton) end

T.test("folding keeps the Guide header and the current step's card, and the window's top", function()
    twoProfessions()
    showMode("always")
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(TAILOR)
    local ui = CP.GuideTab.ui
    local full = W.ExpandedHeight()
    T.eq(P.frame:GetHeight(), math.min(P.OpenHeight(), full), "open: its content, at most the saved height")
    fold()
    T.eq(CP.db.windowCollapsed, true, "saved")
    T.ok(P.folded)
    T.ok(not P.tabs.guide.button:IsShown(), "no tab row")
    T.ok(P.tabs.guide.content:IsShown() and ui.one:IsShown(), "the Guide view")
    T.ok(not ui.scroll:IsShown() and not ui.scrollBar:IsShown(), "no step list")
    T.eq(ui.prof:GetText(), "Tailoring", "the header's profession")
    -- Leatherworking's leather changes Tailoring's plan, so the header names it first.
    T.eq(ui.skillText:GetText(), "with Leatherworking · 60 / 75", "and skill")
    T.ok(ui.details:IsShown(), "the current step's card")
    T.ok(ui.details.title:GetText() ~= nil and ui.details.title:GetText() ~= "", "with its step")
    T.ok(ui.details.craftAll:IsShown(), "and its Craft button")
    local want = P.FOLD_TOP + 44 + ui.impromptu:GetHeight() + 8 + 198 + P.BODY_PAD
    T.eq(P.FoldedHeight(), want, "title bar, header, impromptu area, card")
    T.eq(P.frame:GetHeight(), want, "the window shrinks to fit")
    local point, rel, relPoint = P.frame:GetPoint(1)
    T.eq({ point, rel, relPoint }, { "TOPLEFT", W.anchor, "TOPLEFT" }, "its top stays on the anchor's top")

    CraftWorld.Open(LW)
    T.ok(P.folded and not P.tabs.guide.button:IsShown(), "a profession window opening keeps the fold")
    CraftWorld.Close()
    T.ok(P.folded, "and so does its closing")
    T.eq(P.frame:GetHeight(), want)
    fold()
    T.eq(CP.db.windowCollapsed, nil)
    T.eq(P.frame:GetHeight(), math.min(P.OpenHeight(), full), "unfolded")
    T.ok(ui.scroll:IsShown(), "the step list is back")
end)

T.test("All mode starts folded: the title bar and the cards; its fold is its own", function()
    twoProfessions()
    showMode("always")
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowCollapsedAll", nil)
    World.set(CP.charDB, "guideMode", "all")
    P:Refresh()
    local ui = CP.GuideTab.ui
    T.ok(P.folded, "folded by default")
    T.ok(not P.tabs.guide.button:IsShown(), "no tab row")
    T.ok(ui.all:IsShown() and not ui.one:IsShown(), "the cards")
    local n = #ui.cardList
    T.ok(n >= 3, "a card per profession")
    T.eq(P.frame:GetHeight(), P.FOLD_TOP + n * 62 + P.BODY_PAD, "as tall as the cards")
    fold()
    T.eq(CP.db.windowCollapsedAll, false, "unfolding All is saved")
    T.ok(not P.folded and P.tabs.guide.button:IsShown(), "the tab row")
    T.eq(P.frame:GetHeight(), P.TITLE_H + 24 + 8 + n * 62 + P.BODY_PAD, "unfolded: still as tall as the cards")
    W.SetMode("one")
    T.ok(not P.folded, "One mode keeps its own fold")
    T.eq(CP.db.windowCollapsed, nil)
    W.SetMode("all")
    fold()
    T.eq(CP.db.windowCollapsedAll, true)
    T.ok(P.folded)
end)

T.test("the unfolded One view fits Steps shown rows and the card, whatever the saved height", function()
    twoProfessions()
    showMode("always")
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.db, "windowHeight", 4000)
    World.set(CP.db, "guideSteps", 6)
    W.Pick(TAILOR)
    local ui = CP.GuideTab.ui
    T.ok(#ui.rows > 6)
    -- The impromptu area (heading and rows) stands between the rows and the card at a fixed height.
    local area = CP.GuideTab.IMPROMPTU_HEAD_H + CP.Impromptu.ROWS * 24 + 8
    local want = P.TITLE_H + 24 + 8 + 44 + 6 * 24 + 8 + area + 198 + P.BODY_PAD
    T.eq(P.frame:GetHeight(), want, "header, six rows, the impromptu area, the card: no space under them")
    CP.db.windowHeight = 300
    P:Refresh()
    T.eq(P.frame:GetHeight(), want, "the saved height leaves the One view alone; the rest of the list scrolls")
end)

T.test("unfolding brings back the tab the window was on", function()
    twoProfessions()
    showMode("always")
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "collect", false)
    P.Layout()
    P.tabs.shop.button:GetScript("OnClick")()
    T.eq(P.current, "shop")
    fold()
    T.ok(P.tabs.guide.content:IsShown() and not P.tabs.shop.content:IsShown(), "folded: the Guide view")
    fold()
    T.eq(P.current, "shop", "the Shop tab again")
    T.ok(P.tabs.shop.content:IsShown() and not P.tabs.guide.content:IsShown())
    P.tabs.guide.button:GetScript("OnClick")()
end)

-- The Shop tab picked, in Buy-and-power-level. The test ends back on the Guide tab.
local function onShop()
    twoProfessions()
    showMode("always")
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "collect", false)
    World.onEnd(function() P.tabs.guide.button:GetScript("OnClick")() end)
    P.Layout()
    P.tabs.shop.button:GetScript("OnClick")()
    T.eq(P.current, "shop")
end

T.test("Gather it yourself switched on and off again brings back the Shop tab", function()
    onShop()
    CP.Settings.Set("collect", true)
    T.advance(0.2)
    T.eq(P.current, "guide", "the Shop tab hides, so the Guide tab shows")
    CP.Settings.Set("collect", false)
    T.advance(0.2)
    T.eq(P.current, "shop", "the Shop tab again")
    T.ok(P.tabs.shop.content:IsShown() and not P.tabs.guide.content:IsShown(), "its content shows")
end)

T.test("the Guide tab clicked while the Shop tab is hidden holds when it comes back", function()
    onShop()
    CP.Settings.Set("collect", true)
    T.advance(0.2)
    P.tabs.guide.button:GetScript("OnClick")()
    CP.Settings.Set("collect", false)
    T.advance(0.2)
    T.eq(P.current, "guide", "the player's pick")
end)

T.test("the mover's anchor keeps the unfolded size while the window is folded", function()
    twoProfessions()
    showMode("always")
    World.set(CP.db, "windowCollapsed", nil)
    P:Refresh()
    local full = P.frame:GetHeight()
    T.eq({ W.anchor:GetWidth(), W.anchor:GetHeight() }, { P.WIDTH, full }, "unfolded")
    fold()
    T.ok(P.frame:GetHeight() < full)
    T.eq({ W.anchor:GetWidth(), W.anchor:GetHeight() }, { P.WIDTH, full }, "folded: still the whole window")
    fold()
end)

T.test("without Daylight UI's mover the title bar drags the window and saves where it stands", function()
    twoProfessions()
    showMode("always")
    World.set(CP.db, "windowPoint", nil)
    World.set(W.managed, "mover", false)
    W.anchor:ClearAllPoints()
    W.anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 300, 700)
    W.drag:GetScript("OnDragStart")(W.drag)
    W.drag:GetScript("OnDragStop")(W.drag)
    T.eq(CP.db.windowPoint, { "TOPLEFT", "BOTTOMLEFT", 300, 700 })
    W.anchor:ClearAllPoints()
    W.PlaceAnchor()
    local point, rel, relPoint, x, y = W.anchor:GetPoint(1)
    T.eq({ point, relPoint, x, y }, { "TOPLEFT", "BOTTOMLEFT", 300, 700 }, "placed there at the next login")
    T.eq(rel, UIParent)
end)

-- All / One ---------------------------------------------------------------------------

T.test("the switch flips All and One in one click; a card switches to One on its profession", function()
    twoProfessions()
    showMode("always")
    World.set(CP.charDB, "guideMode", nil)
    T.eq(W.Mode(), "one", "One by default")
    T.ok(W.pickButton:IsShown(), "the dropdown shows in One mode")
    T.eq(W.switchButton.label:GetText(), W.ViewLabel("one"), "One mode: One lit, All greyed")
    W.switchButton:GetScript("OnClick")(W.switchButton)
    T.eq(CP.charDB.guideMode, "all")
    T.eq(W.switchButton.label:GetText(), W.ViewLabel("all"), "All mode: All lit")
    T.ok(not W.pickButton:IsShown(), "no dropdown in All mode")
    P.tabs.guide.button:GetScript("OnClick")()
    local ui = CP.GuideTab.ui
    T.ok(ui.all:IsShown() and not ui.one:IsShown(), "All mode stacks cards")
    local names = {}
    for _, card in ipairs(ui.cardList) do names[card.name] = card end
    T.ok(names.Leatherworking and names.Tailoring and names.Mining, "a card per guided profession")
    T.ok(names.Tailoring.step ~= nil and names.Tailoring.need ~= nil, "step and materials left")
    T.ok(names.Mining.step:find("Gather") or names.Mining.step:find("Train"), "Mining's next stretch: " .. names.Mining.step)

    -- A card's click picks its profession.
    W.Pick(names.Tailoring.key)
    T.eq(CP.charDB.guideMode, "one", "back to One")
    T.eq(CP.charDB.guideProf, TAILOR, "on Tailoring")
    T.ok(ui.one:IsShown())
    T.eq(ui.live.prof.id, TAILOR)
    W.switchButton:GetScript("OnClick")(W.switchButton)
    W.switchButton:GetScript("OnClick")(W.switchButton)
    T.eq(W.Mode(), "one", "two clicks: back where it was")
end)

-- The harness has no font engine: a wide stand-in, 7.5 px a letter (the chips' fixed
-- 12 px text in a wide font). Colour codes take no room.
local LETTER = 7.5
local function wideText(fs, text)
    if text then fs:SetText(text) end
    local plain = (fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return math.ceil(#plain * LETTER)
end

-- The title bar's shown pieces as { name, left, right }, from their anchors and widths.
local function titleRects()
    local out = { { "logo", 10, 28 } }
    if P.title:IsShown() then
        local left = 28 + 5
        out[#out + 1] = { "title", left, left + P.TextWidth(P.title) }
    end
    local names = { [W.closeButton] = "close", [P.bugButton] = "bug", [W.foldButton] = "fold", [W.lockButton] = "lock",
                    [W.pickButton] = "dropdown", [W.switchButton] = "switch" }
    for _, t in ipairs(P.titleButtons) do
        local b = t.button
        if b:IsShown() then
            local point, rel, _, x = b:GetPoint(1)
            T.eq({ point, rel }, { "TOPRIGHT", P.frame })
            local right = P.WIDTH + x
            out[#out + 1] = { names[b] or "guest", right - b:GetWidth(), right }
        end
    end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

T.test("no title-bar control overlaps another, for every profession name, in both modes", function()
    twoProfessions()
    showMode("always")
    World.set(P, "TextWidth", wideText)
    local names = {}
    for id, guide in pairs(CP.Guides) do names[#names + 1] = { id = id, name = guide.name } end
    for id, name in pairs(CP.Launcher.GATHER_NAMES) do names[#names + 1] = { id = id, name = name } end
    for _, mode in ipairs({ "one", "all" }) do
        World.set(CP.charDB, "guideMode", mode)
        for _, e in ipairs(names) do
            World.set(W, "Professions", function() return { { id = e.id, name = e.name, skill = 1 } } end)
            World.set(W, "ChosenID", function() return e.id end)
            W.Chrome()
            local where = ("%s, %s mode"):format(e.name, mode)
            if mode == "one" then
                T.eq(W.pickButton.label:GetText(), e.name, where)
                T.ok(P.TextWidth(W.pickButton.label) <= W.pickButton:GetWidth() - 8,
                    where .. ": the name fits inside the dropdown")
            end
            local rects = titleRects()
            T.ok(rects[1][2] >= 0 and rects[#rects][3] <= P.WIDTH, where .. ": inside the window")
            for i = 2, #rects do
                local a, b = rects[i - 1], rects[i]
                T.ok(b[2] - a[3] >= 4, ("%s: %s (%d-%d) and %s (%d-%d) keep 4 px apart"):format(
                    where, a[1], a[2], a[3], b[1], b[2], b[3]))
            end
        end
    end
end)

T.test("One mode: the open window's profession becomes the pick, else the saved pick", function()
    twoProfessions()
    showMode("always")
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(TAILOR)
    T.eq(W.ChosenID(), TAILOR)
    CraftWorld.Open(LW)
    T.eq(W.ChosenID(), LW, "the open window's profession")
    T.eq(CP.charDB.guideProf, LW, "the guide follows the window")
    T.eq(W.pickButton.label:GetText(), "Leatherworking")
    W.Pick(TAILOR)
    T.eq(W.ChosenID(), TAILOR, "a pick while it's open shows that profession")
    T.ok(CP.GuideTab.ui.live.offline, "from its offline plan")
    T.fire("TRADE_SKILL_LIST_UPDATE")
    T.advance(0.1)
    T.eq(W.ChosenID(), TAILOR, "the pick holds while the window stays on its profession")
    CraftWorld.Close()
    T.eq(W.ChosenID(), TAILOR)
    CP.charDB.guideProf = nil
    CP.charDB.lastProf = LW
    T.eq(W.ChosenID(), LW, "no pick: the last profession opened")
    CP.charDB.lastProf = 999
    T.eq(W.ChosenID(), (W.Professions()[1] or {}).id, "neither had: the first by name")
end)

-- Plans with the window shut ---------------------------------------------------------

T.test("a shut profession's tabs read Plan.Offline from its saved recipes and the skill list", function()
    twoProfessions()
    showMode("always")
    T.ok(CP.charDB.learned and #CP.charDB.learned[TAILOR] > 0, "Tailoring's recipes were saved when it was open")
    W.Pick(TAILOR)
    P.tabs.guide.button:GetScript("OnClick")()
    local ui = CP.GuideTab.ui
    T.ok(ui.live and ui.live.offline, "offline plan")
    T.eq(ui.live.prof.skill, 60, "skill from the skill list")
    local learned = {}
    for _, id in ipairs(CP.charDB.learned[TAILOR]) do learned[id] = true end
    local direct = CP.Plan.Offline(CP.Guides[TAILOR], TAILOR, 60, 75, learned)
    T.eq(CP.Plan.Pack(ui.live.plan), CP.Plan.Pack(direct.plan), "the same plan Plan.Offline makes")
    T.ok(#ui.rows > 0 and ui.rows[1].recipe ~= nil, "Guide rows")
    T.ok(not ui.details.craftOne:IsShown() or not CP.Style.IsOn(ui.details.craftOne), "no crafting from a shut window")

    CraftWorld.SetSkill(TAILOR, 70, 75)
    CP.Plan.Invalidate()
    P:Refresh()
    T.eq(ui.live.prof.skill, 70, "a skill-up re-plans")

    T.ok(CP.Plan.Shut(TAILOR).plan ~= nil)
    local tab = P.tabs.shop
    World.set(CP.db, "collect", false)
    tab.refresh(tab.content)
    T.ok(CP.charDB.shopNeeds and next(CP.charDB.shopNeeds) ~= nil, "the Shop list from the shut profession")
    P.tabs.guide.button:GetScript("OnClick")()
end)

T.test("needs re-plan with the window standing free; only an open profession window stops it", function()
    twoProfessions()
    showMode("always")
    T.ok(shown())
    CP.charDB.gatherNeeds = nil
    CP.Gather.UpdateAllNeeds()
    T.ok(CP.charDB.gatherNeeds and CP.charDB.gatherNeeds[LW] ~= nil, "planned while the free window shows")
    CraftWorld.Open(LW)
    CP.charDB.gatherNeeds[TAILOR] = nil
    CP.Gather.UpdateAllNeeds()
    T.eq(CP.charDB.gatherNeeds[TAILOR], nil, "skipped while a profession window is open")
end)

T.test("All mode: Shop merges the lists; there is no Queue tab", function()
    twoProfessions()
    showMode("always")
    W.SetMode("all")
    T.eq(P.tabs.queue, nil, "no Queue tab")
    T.eq(CP.QueueTab, nil)
    local heads = 0
    for _, e in ipairs(CP.Window.AllLives()) do if e.guide then heads = heads + 1 end end
    T.ok(heads >= 2, "two crafting professions")
    local tab = P.tabs.shop
    World.set(CP.db, "collect", false)
    tab.refresh(tab.content)
    T.ok(CP.ShopTab.ui.summary:GetText():find("every profession", 1, true) ~= nil, "the merged list")
    local a ={ { itemID = 1, need = 4, have = 1, left = 3, first = 2 }, { itemID = 2, need = 1, have = 0, left = 1, first = 1 } }
    local b = { { itemID = 1, need = 6, have = 1, left = 5, first = 1, others = { {} } } }
    local merged = CP.ShopTab.Merge({ a, b })
    local one
    for _, m in ipairs(merged) do if m.itemID == 1 then one = m end end
    T.eq(#merged, 2, "one row per item")
    T.eq(one.need, 10, "needs add up")
    T.eq(one.left, 9)
    T.eq(one.others, nil)
    W.SetMode("one")
    P.tabs.guide.button:GetScript("OnClick")()
end)

-- The gathering panel -----------------------------------------------------------------

local GP = CP.GatherPanel

T.test("the gathering panel draws the checklist's rows: the same items, in the same order", function()
    twoProfessions()
    showMode("always")
    T.eq(P.tabs.gather, nil, "no Gather tab")
    CP.charDB.gatherNeeds = { [164] = { [COPPER_ORE] = 40 } }
    local updateAll = CP.Gather.UpdateAllNeeds
    World.set(CP.Gather, "UpdateAllNeeds", function() end)
    T.ok(updateAll ~= nil)
    World.set(CP.db, "gatherOpen", true)
    GP.Layout()
    T.ok(GP.sheet:IsVisible(), "the panel shows")
    T.ok(CP.GatherList.Refresh(), "rows in Durotar for Mining 30")
    local lines, rows, offset = CP.GatherList.Drawn()
    -- Today's checklist: Gather.Rows' items a guide needs, by profession section.
    local G = CP.Gather
    local skills = G.Skills()
    local needs, soon = G.Needs()
    local items = G.Rows(DUROTAR, skills, needs, function(id) return CP.Purchases.Have(id) end, nil,
        { here = G.Farmable }, soon)
    local want = {}
    for _, r in ipairs(items) do if r.need then want[#want + 1] = r.itemID end end
    local got = {}
    for _, l in ipairs(lines) do if l.kind == "item" then got[#got + 1] = l.row.itemID end end
    T.ok(#want > 0, "Copper Ore is needed here")
    T.eq(got, want, "the same items in the same order")
    for i = 1, CP.GatherList.shown do
        T.eq(rows[i].line, lines[offset + i], "row " .. i .. " draws its line")
        T.ok(rows[i]:IsShown())
    end
    T.eq(CP.GatherList.frame:GetParent(), GP.body, "inside the gathering panel")
end)

-- Where the window's centre sits: `x` of a 1920-wide screen.
local function standAt(x)
    World.set(P.frame, "GetCenter", function() return x, 500 end)
    World.set(UIParent, "GetWidth", function() return 1920 end)
end

local function side(v)
    World.set(CP.db, "gatherSide", CP.db.gatherSide)
    World.set(CP.db, "gatherSideCarried", CP.db.gatherSideCarried)
    CP.Settings.Set("gatherSide", v)
end

local function click() GP.tab:GetScript("OnClick")(GP.tab) end

T.test("the fold tab slides the panel out and back over 0.3 s, and saves it", function()
    twoProfessions()
    showMode("always")
    side("right")
    World.set(CP.db, "gatherOpen", false)
    GP.Layout()
    T.ok(GP.tab:IsShown(), "the tab shows on the window's edge")
    T.eq(GP.p, 0, "folded")
    T.ok(not GP.sheet:IsShown())
    T.eq(GP.tab.points, "right", "the chevron points the way it will move")
    click()
    T.eq(CP.db.gatherOpen, true, "saved open")
    T.ok(GP.sheet:IsShown(), "the sheet shows as it starts")
    T.advance(0.15)
    T.ok(GP.p > 0 and GP.p < 1, "half way: " .. GP.p)
    T.ok(GP.clip:GetWidth() < GP.WIDTH, "the clip hides what hasn't slid out yet")
    T.advance(0.2)
    T.eq(GP.p, 1, "out after 0.3 s")
    T.eq(GP.clip:GetWidth(), GP.WIDTH)
    T.eq(GP.tab.points, "left", "now it points back")
    click()
    T.eq(CP.db.gatherOpen, false, "saved folded")
    T.advance(0.35)
    T.eq(GP.p, 0)
    T.ok(not GP.sheet:IsShown(), "gone behind the window")
end)

T.test("Daylight UI's Motion.Tween drives the slide when it is there", function()
    twoProfessions()
    showMode("always")
    side("right")
    World.set(CP.db, "gatherOpen", false)
    GP.Layout()
    local calls = {}
    World.set(_G, "DaylightUI", { Motion = { Tween = function(key, from, to, dur, step)
        calls[#calls + 1] = { key = key, from = from, to = to, dur = dur }
        step(to)
    end } })
    click()
    T.eq(#calls, 1)
    T.eq({ calls[1].from, calls[1].to, calls[1].dur }, { 0, 1, GP.SLIDE })
    T.eq(GP.p, 1)
    click()
    T.eq({ calls[2].from, calls[2].to }, { 1, 0 })
end)

T.test("the panel slides out on the side the setting names, wherever the window stands", function()
    twoProfessions()
    showMode("always")
    World.set(CP.db, "gatherOpen", true)
    side("right")
    T.eq(CP.DEFAULTS.gatherSide, "right", "right of the guide by default, before the carry-over")
    T.eq(GP.side, "right")
    local point, rel, relPoint = GP.clip:GetPoint(1)
    T.eq({ point, rel, relPoint }, { "TOPLEFT", P.frame, "TOPRIGHT" })
    T.eq({ GP.shell:GetPoint(1) }, { "TOPLEFT", P.frame, "TOPLEFT" }, "the shell grows to the right")
    point, rel, relPoint = GP.tab:GetPoint(1)
    T.eq({ point, rel, relPoint }, { "LEFT", GP.shell, "RIGHT" }, "the tab on the shell's right edge")
    standAt(1500)
    T.advance(1)
    T.eq(GP.side, "right", "the right half of the screen changes nothing")
    side("left")
    T.eq(GP.side, "left", "the setting re-lays out at once")
    point, rel, relPoint = GP.clip:GetPoint(1)
    T.eq({ point, rel, relPoint }, { "TOPRIGHT", P.frame, "TOPLEFT" })
    T.eq({ GP.shell:GetPoint(1) }, { "TOPRIGHT", P.frame, "TOPRIGHT" }, "the shell grows to the left; the window stays put")
    point, rel, relPoint = GP.tab:GetPoint(1)
    T.eq({ point, rel, relPoint }, { "RIGHT", GP.shell, "LEFT" })
    T.eq(GP.tab.points, "right", "open on the left: points back right")
    side("right")
end)

T.test("one shell around the window and the panel: no border of their own, a faint seam", function()
    twoProfessions()
    showMode("always")
    side("right")
    World.set(CP.db, "gatherOpen", false)
    GP.Layout()
    T.ok(GP.shell:IsShown(), "the shared shell")
    T.ok(not (P.frame.__shell and P.frame.__shell:IsShown()), "the window draws no shell of its own")
    T.ok(not GP.sheet.__shell:IsShown() and not GP.sheet.__line:IsShown(), "nor does the panel while attached")
    -- The harness keeps no frame levels: the calls are read instead.
    local levels = {}
    World.set(P.frame, "GetFrameLevel", function() return 10 end)
    World.set(GP.shell, "SetFrameLevel", function(_, n) levels.shell = n end)
    World.set(GP.tab, "SetFrameLevel", function(_, n) levels.tab = n end)
    GP.Layout()
    T.eq({ levels.shell, levels.tab }, { 9, 8 }, "the shell behind the window's drawing, the tab behind the shell's border")
    T.eq(GP.shell:GetWidth(), P.WIDTH, "folded: the window's width")
    T.ok(not GP.seam:IsShown(), "no seam with the panel away")
    GP.Toggle()
    T.advance(0.15)
    T.ok(GP.shell:GetWidth() > P.WIDTH and GP.shell:GetWidth() < 2 * P.WIDTH, "widening as it slides")
    T.advance(0.3)
    T.eq(GP.shell:GetWidth(), 2 * P.WIDTH, "out: both widths")
    T.eq(GP.shell:GetHeight(), P.frame:GetHeight(), "as tall as the window")
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "the panel takes the window's height")
    T.ok(GP.seam:IsShown(), "a faint seam between them")

    CraftWorld.Open(LW)
    T.ok(GP.shell:IsShown(), "a profession window open: the same shell")
    CraftWorld.Close()
    GP.Toggle()
    T.advance(0.35)
end)

T.test("the fold tab looks like Daylight UI's and shows only while the mouse is near", function()
    twoProfessions()
    showMode("always")
    side("right")
    GP.Layout()
    T.eq({ GP.tab:GetWidth(), GP.tab:GetHeight() }, { GP.TAB[1] + GP.TUCK, GP.TAB[2] }, "14 x 34, plus what hides behind the border")
    T.eq(GP.tabAlpha, 0, "hidden with the mouse away")
    World.set(GP.shell, "IsMouseOver", function() return true end)
    T.advance(0.1)
    T.eq(GP.tabAlpha, 1, "shown with the mouse over the window or the panel")
    World.set(GP.shell, "IsMouseOver", function() return false end)
    T.advance(0.1)
    T.eq(GP.tabAlpha, 0, "and gone after")

    local calls = {}
    World.set(_G, "DaylightUI", { Motion = { Tween = function(key, from, to, dur, step)
        calls[#calls + 1] = { key = key, to = to, dur = dur }
        step(to)
    end } })
    World.set(GP.tab, "IsMouseOver", function() return true end)
    T.advance(0.1)
    T.eq({ calls[#calls].to, calls[#calls].dur }, { 1, GP.FADE }, "Daylight UI's tween eases it in")
end)

T.test("detached, a first detach takes its rows' height, at least SIZE_MIN, and keeps it", function()
    twoProfessions()
    showMode("nocombat")
    side("right")
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherAttached", false)
    World.set(CP.db, "gatherPanelClosed", nil)
    World.set(CP.db, "gatherSize", nil)
    World.onEnd(function()
        CP.db.gatherAttached = true
        GP.ModeChanged()
    end)
    World.set(CP.Gather, "UpdateAllNeeds", function() end)
    CP.charDB.gatherNeeds = { [164] = { [COPPER_ORE] = 40 } }
    GP.Layout()
    CP.GatherList.Refresh()
    local need = CP.GatherList.NeedHeight() + 2 * P.BODY_PAD + 4
    local first = math.max(GP.SIZE_MIN[2], math.min(W.ExpandedHeight(), need))
    T.eq(GP.sheet:GetHeight(), first, "its rows")
    T.ok(GP.sheet:GetHeight() < W.ExpandedHeight(), "a short list leaves no empty space")
    T.eq(GP.sheet:GetWidth(), P.WIDTH)
    World.set(CP.GatherList, "NeedHeight", function() return 5000 end)
    GP.Fit()
    T.eq(GP.sheet:GetHeight(), first, "a longer list keeps the size and scrolls")
    fold()
    T.ok(GP.sheet:IsVisible())
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not GP.sheet:IsVisible() and not GP.tab:IsVisible(), "hidden in combat with the window")
    T.fire("PLAYER_REGEN_ENABLED")
    T.ok(GP.sheet:IsVisible(), "back with it")
    fold()
end)

T.test("attached, the panel's height is the window's, folded or not", function()
    twoProfessions()
    showMode("nocombat")
    side("right")
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.Gather, "UpdateAllNeeds", function() end)
    CP.charDB.gatherNeeds = { [164] = { [COPPER_ORE] = 40 } }
    GP.Layout()
    CP.GatherList.Refresh()
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "open: the window's height")
    fold()
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "folded: still the window's height")
    fold()
end)

T.test("the free window and its panel take the scale Daylight UI's mover gives the anchor", function()
    twoProfessions()
    showMode("always")
    -- The harness keeps no scale: the anchor answers for the mover, the panel's calls are read.
    local scale = 1.25
    World.set(W.anchor, "GetScale", function() return scale end)
    local got
    local set = P.frame.SetScale
    World.set(P.frame, "SetScale", function(self, v) got = v return set(self, v) end)
    W.anchor:SetScale(scale)
    T.eq(got, 1.25, "the window follows the mover's scale")
    CraftWorld.Open(LW)
    T.eq(got, 1.25, "a profession window open: still the mover's")
    CraftWorld.Close()
    T.eq(got, 1.25, "and after it closes")
    scale = 1
    T.eq({ W.anchor:GetWidth(), W.anchor:GetHeight() }, { P.WIDTH, W.ExpandedHeight() }, "the mover's frame keeps the largest size")
end)

-- The minimap button ------------------------------------------------------------------

T.test("the minimap button registers with LibDBIcon, toggles the window, and follows its setting", function()
    twoProfessions()
    showMode("always")
    local lib = LibStub("LibDBIcon-1.0")
    local got = {}
    World.set(lib, "IsRegistered", function() return got.name ~= nil end)
    World.set(lib, "Register", function(_, name, object, db) got.name, got.object, got.db = name, object, db end)
    World.set(lib, "Hide", function(_, name) got.hidden = name end)
    World.set(lib, "Show", function(_, name) got.hidden = nil end)
    World.set(CP.db, "minimap", nil)
    World.set(CP.db, "minimapButton", true)
    T.ok(CP.Launcher.ShowMinimap())
    T.eq(got.name, "ProfLost", "LibDBIcon10_ProfLost, which Daylight UI's drawer collects")
    T.eq(got.object, CP.Launcher.minimapObject)
    T.eq(got.db, CP.db.minimap, "its place is saved in CP.db.minimap")
    T.eq(got.object.icon, "Interface\\AddOns\\ProfessionallyLost\\Media\\Icon", "the addon's icon")
    T.ok(shown())
    got.object.OnClick(nil, "LeftButton")
    T.ok(not shown(), "left-click hides the window")
    got.object.OnClick(nil, "LeftButton")
    T.ok(shown(), "and shows it")
    T.eq(got.hidden, nil, "shown by default")

    -- The "Minimap button" setting hides it, saved in LibDBIcon's own flag.
    T.ok(CP.Settings.Find("minimapButton") ~= nil, "a setting for it")
    T.ok(CP.Settings.Set("minimapButton", false))
    T.eq(got.hidden, "ProfLost", "off: hidden")
    T.eq(CP.db.minimap.hide, true, "LibDBIcon's hide flag follows")
    T.ok(CP.Settings.Set("minimapButton", true))
    T.eq(got.hidden, nil, "on: shown")
    T.eq(CP.db.minimap.hide, nil)

    -- A reload honours a saved hide; it no longer forces the button back.
    CP.db.minimap.hide = true
    got.hidden = nil
    T.ok(CP.Launcher.ShowMinimap())
    T.eq(got.hidden, "ProfLost", "the saved hide holds across a reload")
    CP.db.minimap.hide = nil
    CP.db.minimapButton = false
    got.hidden = nil
    T.ok(CP.Launcher.ShowMinimap())
    T.eq(got.hidden, "ProfLost", "the setting off hides it at login")
    T.eq(CP.db.minimap.hide, true)
end)

-- Carry-over -------------------------------------------------------------------------

T.test("saved checklist keys carry over to the window once", function()
    local db = CP.CarryOver({ gatherList = false, gatherCollapsed = true, gatherClosed = { [186] = true } })
    T.eq(db.windowClosed, true, "a hidden checklist: the free window starts closed")
    T.eq(db.gatherList, nil, "dropped")
    T.eq(db.windowShow, nil)
    T.eq(db.windowCollapsed, true, "folded stays folded")
    T.eq(db.gatherCollapsed, nil)
    T.eq(db.gatherClosed, { [186] = true }, "the Gather tab's folded sections are kept")
    db.windowClosed = nil
    CP.CarryOver(db)
    T.eq(db.windowClosed, nil, "once: a later load changes nothing")

    local shownList = CP.CarryOver({ gatherList = true, gatherCollapsed = false })
    T.eq(shownList.windowClosed, nil, "a shown checklist: the window is open")
    T.eq(shownList.windowCollapsed, nil)
    T.eq(shownList.gatherOpen, true, "a shown one: open")
    T.eq(CP.CarryOver({ gatherList = false }).gatherOpen, false, "a hidden checklist: the gathering panel starts folded")
    T.eq(CP.CarryOver({}).gatherOpen, true, "nothing saved: open")
    T.eq(CP.CarryOver({ gatherList = false, gatherOpen = true }).gatherOpen, true, "a saved panel state wins")
    T.eq(CP.DEFAULTS.windowShow, nil)
    T.eq(CP.DEFAULTS.gatherList, nil)
end)

T.test("the old windowShow values carry over to closed and hide in combat", function()
    local function from(v) return CP.CarryOver({ windowShow = v, windowShowCarried = true }) end
    local always, nocombat, profession, manual = from("always"), from("nocombat"), from("profession"), from("manual")
    T.eq(always.hideInCombat, false, "always: stays up in combat")
    T.eq(always.hideInCombatCarried, true, "kept against Daylight UI's profile default")
    T.eq(always.windowClosed, nil)
    T.eq(nocombat.hideInCombat, nil, "out of combat: the default, hidden in combat")
    T.eq(nocombat.windowClosed, nil)
    T.eq(profession.windowClosed, true, "with a profession window: the free window starts closed")
    T.eq(manual.windowClosed, true, "when I open it: closed until opened")
    for _, db in ipairs({ always, nocombat, profession, manual }) do
        T.eq(db.windowShow, nil, "the old key goes")
        T.eq(db.windowShowCarried, nil)
    end
    T.eq(CP.CarryOver({ windowShow = "always", hideInCombat = true }).hideInCombat, true, "a saved toggle wins")
    T.eq(CP.CarryOver({ windowShow = "manual", windowClosed = false }).windowClosed, false, "a saved close state wins")
end)

T.test("picking the setting clears the carried flag, so Daylight UI's value is used from then on", function()
    World.set(CP.db, "hideInCombatCarried", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "gatherHideCarried", CP.db.gatherHideCarried)
    World.onEnd(function() W.opened = false W.Update() end)
    CP.Settings.Set("hideInCombat", true)
    T.eq(CP.db.hideInCombatCarried, nil)
end)
