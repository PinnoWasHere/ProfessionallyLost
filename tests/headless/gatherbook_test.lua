-- "Buy for guide" offers the Expert Fishing book where it is sold, as crafting rank books
-- are offered: while Fishing sits under the 150 cap the book lifts and none is held (simulator
-- finding, 2026-11-16: at Old Man Heming the bot had to buy the book itself).

local CP = ProfLost
local FISHING, BOOK, HEMING = 356, 16083, 2626

local function atHeming(rank, max, bags)
    MapWorld.begin({ zone = 1434, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [FISHING] = { rank = rank, max = max } }, bags = bags or {} })
    VendorWorld.begin({ money = 100000 })
    VendorWorld.Open({ entry = HEMING, name = "Old Man Heming", items = { { item = BOOK, price = 10000 }, { item = 6256, price = 23 } } })
    T.advance(1)
end

local function bookLine()
    local _, _, patterns = CP.Buying.Wants()
    for _, l in ipairs(patterns) do
        if l.itemID == BOOK then return l end
    end
end

T.test("Buy for guide offers the Expert Fishing book to an angler under the 150 cap", function()
    atHeming(130, 150)
    local l = bookLine()
    T.ok(l ~= nil, "the book is offered")
    T.eq(l and l.cost, 10000)
    T.eq(l and l.skill, 125, "learnable at 125")
    T.eq(l and CP.Buying.PatternText(l):find("learnable now", 1, true) ~= nil, true, l and CP.Buying.PatternText(l))
    T.advance(CP.Buying.CHECK_EVERY * 2)
    T.eq(CP.Buying.Reason(), nil, "the button is on")
    VendorWorld.Close()
end)

T.test("the book is not offered past its cap or when held", function()
    atHeming(160, 225)
    T.eq(bookLine(), nil, "Expert already learned")
    VendorWorld.Close()
    atHeming(130, 150, { [BOOK] = 1 })
    T.eq(bookLine(), nil, "one in the bags")
    VendorWorld.Close()
end)
