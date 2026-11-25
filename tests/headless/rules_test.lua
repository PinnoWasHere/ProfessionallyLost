-- The shared rules (tests/rules/, decision 0009 1.4) exist, see no world, and judge a state handed to
-- them in ctx alone. The play-throughs fire each rule's plant; this file holds the rules to their shape.

-- Decision 0009's table in 1.4: every row's rule.
local TABLE = { "Known", "Knowledge", "Learnable", "Cooldown", "RankPlace", "SplitRows", "RowPoints", "Locked",
                "Causes", "LevelRow", "Tool", "CardNeed", "Colour", "Cloth" }

T.test("every rule in decision 0009's table is a function in the rules' sandbox", function()
    for _, name in ipairs(TABLE) do
        T.eq(type(Rules[name]), "function", "Rules." .. name)
        if type(Rules[name]) == "function" then
            T.ok(getfenv(Rules[name]) == Rules.ENV, "Rules." .. name .. " runs in Rules.ENV")
        end
    end
end)

T.test("a rule that reads or sets a global raises", function()
    local read = setfenv(function() return GameWorld end, Rules.ENV)
    local ok, err = pcall(read)
    T.ok(not ok and tostring(err):find("GameWorld", 1, true) ~= nil, "a read of GameWorld raises: " .. tostring(err))
    local write = setfenv(function() RulesLeak = 1 end, Rules.ENV)
    ok, err = pcall(write)
    T.ok(not ok and rawget(_G, "RulesLeak") == nil, "a global write raises and leaks nothing: " .. tostring(err))
end)

T.test("rankplace judges rows handed in ctx, with no world", function()
    local rank = { rank = { name = "Journeyman", skill = 50, cap = 150 } }
    local early = { spell = 1, recipe = { name = "Early" }, from = 60, to = 80 }
    local late = { spell = 2, recipe = { name = "Late" }, from = 150, to = 170 }
    local bad = Rules.RankPlace({ rows = { rank, early, late } })
    T.eq(#bad, 1, "a rank before a row that starts under its cap fires")
    T.ok(bad[1] and bad[1]:find("needed only at 150", 1, true) ~= nil, tostring(bad[1]))
    local done = { spell = 1, recipe = { name = "Early" }, from = 100, to = 150 }
    T.eq(#Rules.RankPlace({ rows = { done, rank, late } }), 0, "a rank at its cap holds")
end)

T.test("cardneed counts a made material in its raw material's units", function()
    local BOLT, CLOTH, MAKER = 900001, 900002, 900003
    local guide = { items = {}, prep = { [BOLT] = MAKER },
                    recipes = { [MAKER] = { yield = 1, reagents = { { CLOTH, 2 } } } } }
    local need = Rules.CardNeed({ guide = guide, card = { { item = BOLT, have = 0, need = 3 } },
                                  learned = { [MAKER] = true },
                                  count = function(id) return id == CLOTH and 1 or 0 end })
    T.ok(need ~= nil, "the card is short")
    if need then
        T.eq(need.item, BOLT, "the card's material")
        T.eq(need.short, 3, "short by need less have")
        T.eq(need.raw, CLOTH, "the raw material it is made from")
        T.eq(need.rawShort, 5, "three runs of two, less the one held")
    end
end)

T.test("levelrow fires on a level row the character has outgrown", function()
    local row = { from = 1, to = 50, levelGate = { need = 10, have = 5 }, gather = { zone = 12 } }
    local zoneName = function() return "Elwynn Forest" end
    local bad = Rules.LevelRow({ row = row, level = 12, zoneName = zoneName })
    T.eq(#bad, 1, "a level row for level 10 at level 12")
    T.ok(bad[1] and bad[1]:find("Elwynn Forest (12)", 1, true) ~= nil, tostring(bad[1]))
    T.eq(#Rules.LevelRow({ row = row, level = 9, zoneName = zoneName }), 0, "under the gate it holds")
end)
