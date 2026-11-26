-- Quest rank rows (First Aid's Triage, Cooking's Clamlette Surprise) carry a map pin to the giver.

local CP = ProfLost
local G = CP.Guide

local function rankOf(guide, spell)
    for _, r in ipairs(guide.ranks) do
        if r.spell == spell then return r end
    end
end

T.test("a quest rank row's pin shows and aims at a quest giver", function()
    for _, case in ipairs({ { 129, 10846 }, { 185, 18260 } }) do
        local guide = CP.Guides[case[1]]
        local rank = rankOf(guide, case[2])
        local row = { key = "rank" .. rank.skill, rank = rank, at = rank.skill }
        local btn = CreateFrame("Button", nil, UIParent)
        CP.GuideTab.InitRow(btn, row)
        T.ok(btn.pin:IsShown(), guide.name .. " " .. rank.name .. ": the row pin shows")
        T.eq(select(2, G.WaypointFor(row)), "quest giver")
    end
end)

T.test("every quest rank in every guide has a giver with a spawn", function()
    for _, guide in pairs(CP.Guides) do
        for _, rank in ipairs(guide.ranks or {}) do
            if rank.kind == "quest" then
                T.ok(rank.npcs and #rank.npcs > 0, guide.name .. " " .. rank.name .. " names a giver")
                for _, n in ipairs(rank.npcs or {}) do
                    local npc = guide.npcs[n]
                    T.ok(npc and npc[3] and #npc[3] > 0, guide.name .. " giver " .. n .. " has a spawn")
                end
            end
        end
    end
end)

local FIRST_AID = 129
local DUROTAR, STORMWIND = 1411, 1453
local W, P = CP.Window, CP.Panel

local function openFirstAid(side, zone)
    MapWorld.begin({ zone = zone, level = 40, side = side })
    CraftWorld.begin({ professions = { [FIRST_AID] = { rank = 225, max = 225 } } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
    end)
    CraftWorld.Open(FIRST_AID)
    CraftWorld.Close()
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(FIRST_AID)
    P.tabs.guide.button:GetScript("OnClick")()
    return CP.GuideTab.ui
end

-- The All view's card for a profession held at a rank cap names the rank step, and its
-- button is the waypoint to that rank's giver.
for _, case in ipairs({ { "Horde", DUROTAR, 12920 }, { "Alliance", STORMWIND, 12939 } }) do
    T.test("the All card for First Aid's Artisan quest has a Go to quest giver button for " .. case[1], function()
        local ui = openFirstAid(case[1], case[2])
        local card = CP.GuideTab.Card(ui.live)
        T.eq(card.step, "Artisan First Aid", "the card is on the rank step")
        local placed = {}
        World.set(CP.Waypoint, "ToRecipe", function(guide, recipe) placed[#placed + 1] = recipe end)
        local btn = CreateFrame("Button", nil, UIParent)
        CP.GuideTab.InitCard(btn, card)
        T.ok(btn.craft:IsShown(), "the card has a button")
        T.eq(btn.craft.label:GetText(), "Go to quest giver")
        T.ok(CP.Style.IsOn(btn.craft), "on")
        btn.craft:GetScript("OnClick")(btn.craft)
        T.eq(#placed, 1, "the click sets a waypoint")
        local npc = CP.Guide.Nearest(ui.guide, placed[1])
        T.eq(npc and npc.entry, case[3], "to the giver for the player's side")
    end)
end

for _, case in ipairs({ { "Horde", DUROTAR, 12920 }, { "Alliance", STORMWIND, 12939 } }) do
    T.test("First Aid's Artisan quest row has a pin for " .. case[1], function()
        local ui = openFirstAid(case[1], case[2])
        local row
        for _, r in ipairs(ui.rows) do
            if r.rank and r.rank.kind == "quest" then row = r end
        end
        T.ok(row ~= nil, "the Artisan quest row is in the guide")
        local btn = CreateFrame("Button", nil, UIParent)
        CP.GuideTab.Forget()
        CP.GuideTab.InitRow(btn, row)
        T.ok(btn.pin:IsShown(), "the row's pin shows")
        CP.GuideTab.Pick(row)
        T.ok(ui.details.pin:IsShown(), "the card's pin shows")
        local npc = CP.Guide.Nearest(ui.guide, ui.details.pin.target)
        T.eq(npc and npc.entry, case[3], "the pin leads to the giver for the player's side")
    end)
end
