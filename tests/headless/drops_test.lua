-- Where-found hints on pattern recipes, against the generated guides.

local CP = ProfLost

local function recipe(line, spell) return CP.Guides[line].recipes[spell] end

T.test("a world-drop pattern says which creature levels drop it", function()
    local r = recipe(171, 3172)   -- Alchemy, Minor Magic Resistance Potion
    T.eq(r.src, "pattern")
    T.eq(r.how, "World drop from level 18-26 creatures")
end)

T.test("a creature-drop pattern names the creature and its chance", function()
    local r = recipe(197, 18450)  -- Tailoring, Wizardweave Turban
    T.eq(r.src, "pattern")
    T.eq(r.how, "Drops from Dark Caster (2.1%)")
    T.eq(recipe(197, 18457).how, "Drops from Firebrand Pyromancer (18%)")
end)

T.test("a quest-reward pattern names the quest", function()
    local r = recipe(171, 4942)   -- Alchemy, Lesser Stoneshield Potion
    T.eq(r.src, "quest")
    T.eq(r.how, "Quest reward: Liquid Stone")
end)

T.test("a chest-only pattern says so", function()
    T.eq(recipe(164, 15293).how, "Found in chests")   -- Blacksmithing, Dark Iron Mail
end)

-- Quest rewards are src "quest" where Forever's sources say so, else "pattern".
T.test("only pattern and quest recipes get a hint from the drops data", function()
    for _, g in pairs(CP.Guides) do
        for spell, r in pairs(g.recipes) do
            local label = g.name .. " " .. spell .. " " .. r.name
            if r.how and (r.how:find("^World drop") or r.how:find("^Found in chests")) then
                T.eq(r.src, "pattern", label)
            elseif r.how and r.how:find("^Quest reward") then
                T.ok(r.src == "pattern" or r.src == "quest", label .. ": " .. r.src)
            end
        end
    end
end)
