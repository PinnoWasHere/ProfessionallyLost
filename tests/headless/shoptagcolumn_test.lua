-- The Shop row's tag sits in one fixed column, whatever the item name or the tag word.

local CP = ProfLost
local SHORT, LONG = 2319, 2320

local function row(item, auction, mail, vendorGood)
    World.set(_G, "DaylightMogul", nil)
    World.set(CP.Style, "Measure", function(text) return #text * 6 end)
    World.set(CP.Scan, "Price", function() return auction end)
    World.set(CP.charDB, "mail", nil)
    World.set(CP.charDB, "bought", nil)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local guide = { items = { [item] = { 5, vendorGood ~= false } } }
    local entries = { { kind = "craft", recipe = { name = "X", reagents = { { item, 1 } } }, crafts = 1 } }
    local rows = CP.ShopTab.Rows(guide, entries, CP.Pricing.Get)
    CP.ShopTab.Measure(rows)
    local r = CreateFrame("Button", nil, UIParent)
    CP.ShopTab.InitRow(r, rows[1])
    return r
end

T.test("a short and a long item name give the tag the same anchor and width", function()
    World.set(CP, "ItemName", function(id)
        return id == SHORT and "Thread" or "Heavy Leather With A Very Long Name Indeed"
    end)
    local a = row(SHORT, 10)
    local b = row(LONG, 10)
    local ap, af, arp, ax, ay = a.tag:GetPoint()
    local bp, bf, brp, bx, by = b.tag:GetPoint()
    T.eq(ap, bp)
    T.eq(arp, brp)
    T.eq(ax, bx)
    T.eq(ay, by)
    T.eq(a.tag:GetWidth(), b.tag:GetWidth())
    T.ok(a.tag:GetWidth() > 0, "the tag column has a set width")
end)

T.test("a vendor tag and an auction tag fill the same column", function()
    World.set(CP, "ItemName", function() return "Thread" end)
    local v = row(SHORT, 10)
    local au = row(LONG, 1, nil, false)
    T.eq(v.tag:GetText(), "vendor")
    T.eq(au.tag:GetText(), "auction")
    T.eq(v.tag:GetWidth(), au.tag:GetWidth())
    T.eq(v.tag:GetWidth(), #"in mail" * 6, "the column fits the widest tag word")
end)
