-- A row names another profession only when that profession changed that row (fishing-tag lane,
-- 2026-11-18: Storm Gauntlets' Fishing cause spread onto Dusky Bracers, Green Whelp Bracers and
-- Guardian Gloves). A row that changed only because an earlier step moved names no profession.

local CP = ProfLost
local GT = CP.GuideTab
local ENCHANTING, TAILOR = 333, 197
local LINEN, BOLT = 2589, 2964   -- Bolt of Woolen Cloth: the shoulders after it run longer, made to disenchant

T.test("Tailoring 1 with Enchanting: the woolen bolt row moved, and names no profession", function()
    MapWorld.begin({ zone = 1429, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 }, [TAILOR] = { rank = 1, max = 75 } },
                       bags = { [LINEN] = 42 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    local live = CP.Plan.Current()
    local rows = GT.RowsOf(live)
    local bolt
    for _, row in ipairs(rows) do
        if row.spell == BOLT and not row.side and not bolt then bolt = row end
    end
    T.ok(bolt and bolt.cause, "the bolt step differs from the plan without Enchanting")
    if not (bolt and bolt.cause) then return end
    T.eq(GT.CauseWords(bolt.cause), "", "its info names no profession")
    local _, _, info = GT.RowTexts(bolt)
    T.ok(not info:find("Enchanting", 1, true), "info: " .. info)
    -- Every row names only its own causes.
    for _, row in ipairs(rows) do
        local words = row.cause and GT.CauseWords(row.cause) or ""
        if words ~= "" then
            local own = row.spell and live.causes(row.spell, row.recipe) or {}
            local allowed = {}
            for _, line in ipairs(own) do
                allowed[CP.Shared.Name(line)] = true
                if line == ENCHANTING and own.de then allowed[GT.DE_MARK] = true end
            end
            for word in words:gmatch("[^,]+") do
                word = word:gsub("^%s+", "")
                T.ok(allowed[word], ("%s names %s, not its own cause"):format(row.recipe and row.recipe.name or "a stop", word))
            end
        end
    end
    CraftWorld.Close()
end)

T.test("a row that only moved says nothing on its card", function()
    T.eq(GT.CauseText({ cause = GT.ShiftedCause() }), nil)
    T.eq(GT.CAUSE_SHIFTED, nil, "the text is gone")
end)
