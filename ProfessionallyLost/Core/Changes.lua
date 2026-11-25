-- Generated from the changelog; do not edit. A fix to a line here is welcome as a PR or an issue.
-- What's New (UI/News.lua) reads it, newest entry first.

local _, CP = ...
if CP.stopped then return end

CP.CHANGES = {
    { version = "1.6.0", summary = "A first-run tour, planning another zone's gathering before you go, foldable gathering lists, and a backup recipe for every pattern step.", sections = {
        { "New", {
            "Guide: A short tour shows the guide's main parts the first time you open it",
            "Gathering: Click the zone name to plan another zone's gathering before you go",
            "API: Other addons can open Professionally Lost with a button of their own",
            "Gathering: Skill-ups and For your guides fold like the sections above them",
        } },
        { "Changed", {
            "Gathering: The zone menu lists every zone by name under its continent, with the skill range it holds for your gathering skills",
            "Gathering: A picked zone's header says where you are, and back returns to your own zone",
            "Gathering: Skill-ups lists the herbs, ore and beasts that give you points, and a skill with nothing in the zone says why and where to go instead",
            "Gathering: Farm leads with what the zone's goods sell for, or says it sells for little and names better zones to farm",
            "Gathering: Rows say how many spawns or nodes a zone has, and a beast's level",
        } },
        { "Fixed", {
            "Guide: A pattern step says \"buy pattern\" until you have it, then where the pattern is (in bags, in bank, in mail)",
            "Gathering: Follow the guide lists only materials a guide still needs, and leather grind spots sit under For your guides, not Skill-ups",
            "Gathering: Patterns to buy here follows the zone you picked",
            "Gathering: A zone you picked stays picked after you die, release or enter Dire Maul, so the list and the header name the same zone",
            "Guide: A pattern step always offers a recipe you can train or already know",
            "Guide: An \"or\" row's card no longer shows an empty \"Changed because you have\" line",
        } },
    } },
    { version = "1.5.0", summary = "A resizable guide with Steps shown, a route button on the world map, a full auction house scan, routes only to what you can gather, and tidier settings.", sections = {
        { "New", {
            "Guide: Drag the guide window's corner to resize it; more steps show when it's taller",
            "Settings: Steps shown sets how many guide steps the window lists; dragging the corner changes it too",
            "Gathering: A route button on the world map shows or hides the route's line, stops and grind spots",
            "Settings: Turn ProfLost's icons on the map off or on",
            "Help: What's New shows the changes once after each update, and a What's New button shows them again",
        } },
        { "Changed", {
            "Gathering: The gathering panel is now called the Gathering window everywhere",
            "Settings: Shorter names and a tidier layout; your choices are kept",
            "Settings: The guide window and the Gathering window each have their own scale",
            "Guide: The guide window can be made as narrow as the Gathering window",
            "Gathering: A gathering profession's section splits its skill-up rows from what your guides need",
            "Gathering: Each minimap route stop is one small ring instead of two large ones",
            "Shop: The price scan reads the whole auction house at once, at most every 15 minutes, so it doesn't crowd other addons' searches",
            "Shop: Vendor goods are always bought from the vendor",
            "Help: A newer version from your guild, group or nearby players shows in a window; Newer version notice turns it off",
        } },
        { "Fixed", {
            "Shop: The auction house scan starts instead of saying your realm isn't known",
            "Gathering: Routes only go to herbs, ore and leather you can gather now",
            "Gathering: Picking a crafting profession lists the herbs, ore or leather its guide needs from this zone",
            "Guide: Changing Steps shown keeps the window in place",
            "Guide: Steps shown counts a step and its \"or\" rows as one step",
            "Guide: Changing the guide window's scale lays its text out again at once",
            "Settings: Settings you can't use are greyed out and shown off as soon as the page opens",
            "Daylight UI: The plugins page no longer says Professionally Lost is missing its AddOns list group",
        } },
    } },
    { version = "1.4.0", summary = "Working Overtime support, Blacksmithing specializations, and mail counted on the step card.", sections = {
        { "New", {
            "Guide: Plans count the Working Overtime legacy perk's skill-up bonus",
        } },
        { "Fixed", {
            "Guide: Attaching or detaching the gathering panel from the title bar is remembered after a reload",
            "Guide: The step card and the plan count items in your mailbox, as the Shop does",
            "Guide: A step that makes a part or material first ends at the skill it says",
            "Blacksmithing: The guide offers Armorsmith or Weaponsmith recipes only to a character with that specialization",
        } },
    } },
}
