-- State that must not outlive its cause (STALE-01, review items 32 to 34): a partial mailbox
-- keeps purchases it hasn't listed, an unskinnable creature leaves the checklist and Farm
-- leather list at once, and a reset during the zone warm-up restarts the Guide tab's search.

local CP = ProfLost
local P, G, GG, GL, GT = CP.Purchases, CP.Gather, CP.GatherGuide, CP.GatherList, CP.GuideTab
local MEDIUM = 2319
local SKIN, MINE, HERB, FISH = 393, 186, 182, 356
local DUROTAR = 1411

-- Item 32 ---------------------------------------------------------------------------

local function mailbox(listed, total, mails)
    World.patch("GetInboxNumItems", function() return listed, total end)
    World.patch("GetInboxItem", function(i, a)
        local m = mails[i]
        if m and a == 1 then return "Medium Leather", m[1], 0, m[2] end
    end)
end

T.test("item 32: a purchase whose mail isn't loaded yet stays counted", function()
    World.set(CP.charDB, "mail", nil)
    World.set(CP.charDB, "bought", nil)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    T.fire("COMMODITY_PURCHASED", MEDIUM, 20)
    -- One mail loaded (4 already there); the mailbox holds more than that.
    mailbox(1, 3, { { MEDIUM, 4 } })
    T.fire("MAIL_SHOW")
    World.onEnd(function() T.fire("MAIL_CLOSED") end)
    T.fire("MAIL_INBOX_UPDATE")
    T.eq(P.InMail(MEDIUM), 4, "the loaded mail")
    T.eq(P.Bought(MEDIUM), 20, "the purchase may sit in mail beyond the window")
    T.eq(P.Have(MEDIUM), 24)
    mailbox(2, 3, { { MEDIUM, 4 }, { MEDIUM, 20 } })
    T.fire("MAIL_INBOX_UPDATE")
    T.eq(P.Bought(MEDIUM), 20, "still a partial listing")
    -- Everything loaded: the purchases are in the mail, and stop counting.
    mailbox(2, 2, { { MEDIUM, 4 }, { MEDIUM, 20 } })
    T.fire("MAIL_INBOX_UPDATE")
    T.eq(P.Bought(MEDIUM), 0, "a full listing takes over from the purchases")
    T.eq(P.Have(MEDIUM), 24)
end)

-- Item 33 ---------------------------------------------------------------------------

T.test("item 33: a creature that turns unskinnable leaves the checklist rows and the Farm leather list", function()
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = 40, side = "Horde", shareSolves = true })
    CraftWorld.begin({ professions = {} })
    World.set(CP.db, "skinSeen", {})
    World.set(CP.charDB, "gatherNeeds", { [165] = { [2318] = 200 } })
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN then return { skillID = id, rank = 300, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    G.ResetClusters()
    World.onEnd(function() G.ResetClusters() end)

    local skills = { [SKIN] = 300 }
    local opts = { cache = true }
    local zones = { DUROTAR }
    local function skinners(rows)
        local out = {}
        for _, row in ipairs(rows) do
            for _, src in ipairs(row.sources) do
                if src.kind == "mob" and src.prof == SKIN then out[src.entry] = true end
            end
        end
        return out
    end

    local before = skinners(G.ForZone(DUROTAR, skills, opts))
    T.ok(next(before), "Durotar has skinnable creatures")
    T.ok(#G.ContinentSkins(zones, skills, 40, "Horde") > 0, "and leather to farm")
    T.eq(#GL.FarmLeathers(DUROTAR, skills) > 0, true)

    -- Every one of them turns out unskinnable: two looted corpses each, without the line.
    for entry in pairs(before) do
        G.LearnSkin(entry, false, "stale-a-" .. entry)
        G.LearnSkin(entry, false, "stale-b-" .. entry)
        T.ok(not G.Skinnable(entry))
    end
    local after = skinners(G.ForZone(DUROTAR, skills, opts))
    T.eq(next(after), nil, "the checklist's zone rows drop them at once")
    T.eq(#G.ContinentSkins(zones, skills, 40, "Horde"), 0, "the continent's leather list too")
end)

-- Item 34 ---------------------------------------------------------------------------

T.test("item 34: a reset during the zone warm-up tells the Guide tab, which asks again", function()
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = 20, side = "Horde" })
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN or id == MINE or id == HERB or id == FISH then
            return { skillID = id, rank = 60, modifier = 0, maxRank = 150 }
        end
        return nil
    end)
    World.set(G, "UpdateAllNeeds", function() end)
    GG.Forget()
    World.onEnd(function()
        GG.Forget()
        GT.Forget()
        T.advance(1)
    end)
    GG.Warm(MINE)
    T.ok(GG.Warming(), "the job runs")
    GT.waitingZones = true
    T.advance(0.02, 0.02)
    T.ok(GG.Warming(), "and is still going")

    GG.Reset()
    T.ok(not GT.waitingZones, "the Guide tab was told and stops waiting on the dropped job")
end)
