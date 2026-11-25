-- A step short of nothing says what is ready: "Ready to craft <recipe>", or "Ready to cast
-- <enchant>" for an enchant, which makes no item (owner, 2026-11-16). Next up, the launcher
-- tooltip and the All-mode card say the same.

local CP = ProfLost
local ENCHANTING, TAILOR = 333, 197
local MOTE, LINEN, COPPER_ROD = 247786, 2589, 6218

-- The Next up line under `profession`, and the launcher tooltip's right text for it.
local function nextUp(profession)
    World.set(CP.GatherList, "nextOpen", true)
    World.set(CP.Launcher, "GatherLines", function() return {} end)
    local lines, line = CP.GatherList.NextLines(), nil
    for i, l in ipairs(lines) do
        if l.text == profession then line = lines[i + 1] end
    end
    local right
    local tip = {}
    function tip:AddDoubleLine(left, r) if left:find("^" .. profession) then right = r end end
    function tip:AddLine() end
    CP.Launcher.Steps(tip)
    return line, right
end

local function open(line, rank, bags)
    MapWorld.begin({ zone = 1453, x = 0.6, y = 0.7, level = 10, side = "Alliance" })
    CraftWorld.begin({ professions = { [line] = { rank = rank, max = 75 } }, bags = bags })
    CraftWorld.Open(line)
    T.advance(1)
    local live = CP.Plan.Current()
    return live, CP.Gather.NextStep(live.guide, live.prof, live.plan, live.learned)
end

T.test("A ready craft step says what it crafts, in Next up, the launcher and the card", function()
    local live, st = open(TAILOR, 1, { [LINEN] = 400 })
    T.eq(st.short, 0, "nothing short")
    local want = "Ready to craft " .. live.guide.recipes[st.spell].name
    local line, launcher = nextUp("Tailoring")
    T.ok(line ~= nil, "Tailoring listed")
    T.eq(line.text, want)
    T.eq(line.textColor, CP.Style.color.good)
    T.eq(launcher, want, "the launcher tooltip")
    T.eq(CP.GuideTab.Card(live).need, want, "the All-mode card")
    CraftWorld.Close()
end)

T.test("A ready enchant step says Ready to cast", function()
    local live, st = open(ENCHANTING, 1, { [MOTE] = 200, [COPPER_ROD] = 1 })
    T.eq(st.short, 0, "nothing short")
    local r = live.guide.recipes[st.spell]
    T.eq(r.makes, nil, "an enchant makes no item: " .. r.name)
    local want = "Ready to cast " .. r.name
    local line, launcher = nextUp("Enchanting")
    T.eq(line and line.text, want)
    T.eq(launcher, want, "the launcher tooltip")
    T.eq(CP.GuideTab.Card(live).need, want, "the All-mode card")
    CraftWorld.Close()
end)

T.test("The ready line wraps in the gathering list, never cut with ...", function()
    local _, st = open(ENCHANTING, 1, { [MOTE] = 200, [COPPER_ROD] = 1 })
    T.ok(st.short == 0)
    World.set(CP.GatherList, "nextOpen", true)
    World.set(CP.Launcher, "GatherLines", function() return {} end)
    local lines = CP.GatherList.Wrap(CP.GatherList.NextLines(), false)
    local seen = {}
    for _, l in ipairs(lines) do
        T.ok(not tostring(l.text):find("...", 1, true), tostring(l.text))
        seen[#seen + 1] = tostring(l.text)
    end
    local joined = table.concat(seen, " ")
    T.ok(joined:find("Ready to cast", 1, true) ~= nil, joined)
    CraftWorld.Close()
end)
