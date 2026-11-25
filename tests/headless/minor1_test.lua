-- MINOR-01: the checklist keeps room for its scroll bar when wrapping adds the bar, a
-- recipe with no how line says where it comes from, and the pattern popup counts the
-- materials' copper before it lights Buy.

local CP = ProfLost
local GL, B, G = CP.GatherList, CP.Buying, CP.Guide

T.test("review 48: names wrap for the narrower width when wrapping itself brings the scroll bar", function()
    local rows = GL.RoomRows()
    local W = 300
    World.set(GL, "width", W)
    World.set(GL, "Measure", function(text) return #text end)
    local room = W - 18   -- a plan row's name room with no info and no bar
    local word = "abcde"
    local name = {}
    while #table.concat(name, " ") < room + 10 do name[#name + 1] = word end
    local list = {}
    for i = 1, rows - 1 do
        list[i] = { kind = "plan", text = i <= 2 and table.concat(name, " ") or "short" }
    end
    local out = GL.Wrap(list)
    T.ok(#out > rows, "wrapping pushes the count past the rows that fit: " .. #out .. " vs " .. rows)
    local bar = CP.Style.ScrollRoom(GL.scrolling)
    T.ok(bar > 0, "a bar takes room")
    for _, line in ipairs(out) do
        T.ok(#line.text <= room - bar, "piece fits beside the bar (" .. #line.text .. " <= " .. (room - bar) .. ")")
    end
end)

T.test("review 48: a list that fits without a bar keeps the full width", function()
    World.set(GL, "width", 300)
    World.set(GL, "Measure", function(text) return #text end)
    local out = GL.Wrap({ { kind = "plan", text = "short" } })
    T.eq(#out, 1)
    T.eq(out[1].text, "short")
end)

T.test("review 50: pattern, reputation and quest recipes with no how line say where they come from", function()
    for _, src in ipairs({ "pattern", "reputation", "quest" }) do
        local text = G.LearnText({ src = src, learn = 215 })
        T.ok(not text:find("trainer"), src .. " does not say trainer: " .. text)
        T.ok(text:find("215", 1, true), src .. " keeps the skill: " .. text)
    end
    T.ok(G.LearnText({ src = "trainer", learn = 40 }):find("trainer"), "a trainer recipe still says trainer")
    T.ok(G.LearnText({ src = "pattern", learn = 215, how = "Drops from Boss" }):find("Drops from Boss"), "a how line wins")
end)

T.test("review 52: the pattern popup counts the materials' copper before the server has taken it", function()
    local purse, pending = 1000, 0
    B.ForgetPurse()
    World.patch("GetMoney", function() return purse end)
    World.patch("GetMerchantNumItems", function() return 1 end)
    World.patch("GetMerchantItemID", function(i) return i == 1 and 2321 or nil end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        return i == 1 and { price = 100, stackCount = 1, numAvailable = -1, isPurchasable = true } or nil
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    World.patch("BuyMerchantItem", function(_, n) pending = pending + 100 * (n or 1) end)
    World.set(B, "open", true)
    World.onEnd(function()
        if B.ForgetPurse then B.ForgetPurse() end
        if B.popup then B.popup:Hide() end
    end)
    local mats = B.Price({ { itemID = 2321, name = "Fine Thread", count = 6 } }, B.Stock())
    local patterns = { { itemID = 1, name = "Pattern", count = 1, index = 1, stack = 1, cost = 500, skill = 1, have = 1 } }
    B.Confirm(mats, 600, "materials", function() B.Confirm(patterns, 500, "patterns") end)
    local f = B.popup
    T.ok(CP.Style.IsOn(f.all), "materials Buy lit: 600 of 1000")
    f.all:GetScript("OnClick")(f.all, "LeftButton")
    T.eq(f.kind, "patterns", "the patterns popup follows")
    T.eq(pending, 600, "six thread sent, copper not yet taken")
    T.ok(not CP.Style.IsOn(f.all), "Buy greys: 400 left after the materials, 500 asked")
    purse, pending = purse - 600, 0
    T.fire("PLAYER_MONEY")
    T.ok(not CP.Style.IsOn(f.all), "still greyed once the server takes the copper")
    purse = 2000
    T.fire("PLAYER_MONEY")
    T.ok(CP.Style.IsOn(f.all), "lights when the purse covers it")
end)
