# Professionally Lost (DaylightUI Plugin) changelog

## 1.6.0
A first-run tour, planning another zone's gathering before you go, foldable gathering lists, and a backup recipe for every pattern step.

### New
- Guide: A short tour shows the guide's main parts the first time you open it
- Gathering: Click the zone name to plan another zone's gathering before you go
- API: Other addons can open Professionally Lost with a button of their own
- Gathering: Skill-ups and For your guides fold like the sections above them

### Changed
- Gathering: The zone menu lists every zone by name under its continent, with the skill range it holds for your gathering skills
- Gathering: A picked zone's header says where you are, and back returns to your own zone
- Gathering: Skill-ups lists the herbs, ore and beasts that give you points, and a skill with nothing in the zone says why and where to go instead
- Gathering: Farm leads with what the zone's goods sell for, or says it sells for little and names better zones to farm
- Gathering: Rows say how many spawns or nodes a zone has, and a beast's level

### Fixed
- Guide: A pattern step says "buy pattern" until you have it, then where the pattern is (in bags, in bank, in mail)
- Gathering: Follow the guide lists only materials a guide still needs, and leather grind spots sit under For your guides, not Skill-ups
- Gathering: Patterns to buy here follows the zone you picked
- Gathering: A zone you picked stays picked after you die, release or enter Dire Maul, so the list and the header name the same zone
- Guide: A pattern step always offers a recipe you can train or already know
- Guide: An "or" row's card no longer shows an empty "Changed because you have" line

## 1.5.0
A resizable guide with Steps shown, a route button on the world map, a full auction house scan, routes only to what you can gather, and tidier settings.

### New
- Guide: Drag the guide window's corner to resize it; more steps show when it's taller
- Settings: Steps shown sets how many guide steps the window lists; dragging the corner changes it too
- Gathering: A route button on the world map shows or hides the route's line, stops and grind spots
- Settings: Turn ProfLost's icons on the map off or on
- Help: What's New shows the changes once after each update, and a What's New button shows them again

### Changed
- Gathering: The gathering panel is now called the Gathering window everywhere
- Settings: Shorter names and a tidier layout; your choices are kept
- Settings: The guide window and the Gathering window each have their own scale
- Guide: The guide window can be made as narrow as the Gathering window
- Gathering: A gathering profession's section splits its skill-up rows from what your guides need
- Gathering: Each minimap route stop is one small ring instead of two large ones
- Shop: The price scan reads the whole auction house at once, at most every 15 minutes, so it doesn't crowd other addons' searches
- Shop: Vendor goods are always bought from the vendor
- Help: A newer version from your guild, group or nearby players shows in a window; Newer version notice turns it off

### Fixed
- Shop: The auction house scan starts instead of saying your realm isn't known
- Gathering: Routes only go to herbs, ore and leather you can gather now
- Gathering: Picking a crafting profession lists the herbs, ore or leather its guide needs from this zone
- Guide: Changing Steps shown keeps the window in place
- Guide: Steps shown counts a step and its "or" rows as one step
- Guide: Changing the guide window's scale lays its text out again at once
- Settings: Settings you can't use are greyed out and shown off as soon as the page opens
- Daylight UI: The plugins page no longer says Professionally Lost is missing its AddOns list group

## 1.4.0
Working Overtime support, Blacksmithing specializations, and mail counted on the step card.

### New
- Guide: Plans count the Working Overtime legacy perk's skill-up bonus

### Fixed
- Guide: Attaching or detaching the gathering panel from the title bar is remembered after a reload
- Guide: The step card and the plan count items in your mailbox, as the Shop does
- Guide: A step that makes a part or material first ends at the skill it says
- Blacksmithing: The guide offers Armorsmith or Weaponsmith recipes only to a character with that specialization

## 1.3.1
Tidier text across the guide, the All view and settings.

### Changed
- Settings: Plan for Enchanting always shows, greyed out and off until you have the professions it needs

### Fixed
- Guide: A Gather card in your zone says "You're in this zone" instead of "Here"
- Settings: The gathering panel side setting no longer cuts off its label and choices
- Guide: A trainer's or vendor's line keeps "skill N" with the step instead of wrapping it alone
- All view: The skill-up line fits its card and always shows the count and points
- Shop: Item names that load late fill in

## 1.3.0
Crafts from your bags, Escape and window opacity, clearer colours, Mapzeroth routing and skinning for Forever's new zones.

### New
- Guide: Escape closes the guide and the gathering panel; lock the window to keep it open
- Gathering: The gathering panel has its own close button when detached
- Guide: Title bar buttons open the gathering panel and attach or detach it
- Enchanting: The guide uses disenchanting for skill-ups where it pays, like the first levels
- Guide: Crafts your bag loot can make for skill points show above the step card
- Guide: A far trainer or vendor step lists what else to do there for later steps, and the gold to bring
- Skinning: Beasts the data lacks learn their skinning loot as you skin them, and their tooltip shows it
- Mapzeroth: Professionally Lost works with Mapzeroth. With it installed, waypoints route through Mapzeroth and the nearest trainer or vendor is picked by travel time
- Skinning: Zones the data lacks get skinning grind spots estimated from their beasts' levels
- Skinning: Forever's new beasts show skinning loot and grind spots from recorded data
- Settings: Window opacity slider for the guide and gathering windows

### Changed
- Gathering: When you need to level up first, the guide names the nearest level that opens a good zone
- Farm: Farm shows and lets you pick only what this zone gives, and keeps Skinning when its beasts drop a picked leather
- Farm: The map shows only this zone's grind spots and route
- Enchanting: Early levels disenchant a green only when that beats crafting with Mote of Magic
- Guide: Colours mean something: warnings stand out, labels are quiet, and every step, learned or not and in the All view, shows its recipe colour
- Guide: Crafts you can make from your bags sit in their own Available Skill Ups section

### Fixed
- Guide: A profession you hadn't opened yet no longer keeps a wrong first step after you open it
- Enchanting: The plan is the same with the profession window open or shut
- Enchanting: Dust from your other profession's items counts only once your Enchanting can disenchant them
- Enchanting: Looting greens no longer replaces a step you have already started
- Guide: Crafting runs fewer plan updates

## 1.2.2
The guide window stands free of the profession window, intermediates count their skill-ups, and a long list of fixes from a full review: bank and mail counts, rank books, Fishing, Skinning, routes, prices and Enchanting's dust.

### Changed
- Guide: A material step's card says how many of its crafts give skill-ups
- Guide: A saved plan that undercounted its material steps is planned afresh once
- Disenchant: The ignore button and the Show ignored items link light up and click like Daylight UI's own
- Guide: Rows light up and fade out on hover as Daylight UI's lists do
- Crafting: The craft progress bar is Daylight UI's own and follows its bar texture
- Guide: The guide window always stands free; it no longer docks beside the profession window
- Guide: Closing the guide window closes it, profession window or not, until you open it again
- General: The setting for the guide window's side of the profession window is gone
- General: Bug reports list your addons and the profession windows on screen
- Guide: Step names stay on one line; the step card shows the full name
- Prices: Neutral auction houses no longer feed prices; only your faction's do
- Disenchant: A value with one unpriced material shows what the rest is worth, marked as at least

### Fixed
- Shop: A row says where its price came from
- Disenchant: Gear you made for dust is no longer marked to sell
- Shop: The vendor and auction tags line up in one column
- Guide: Bolts and other materials you craft now count their skill-ups
- Guide: The stop-the-batch line waits until the step's crafts are done
- Guide: A later step's card no longer asks you to make bolts an earlier step makes
- Guide: A later step's card asks you to make only the bolts earlier steps leave short
- Guide: Material rows that make several per craft ask for the right number of crafts
- Guide: Material rows that also drop from monsters no longer ask you to craft more than their range needs
- Guide: A limited-stock pattern's step no longer swallows the step before it when that changes how many materials you craft
- Guide: With Enchanting, a guide no longer depends on which profession window you opened first
- Guide: Cooking's and First Aid's Expert ranks say to read the book, and Artisan First Aid says to do Triage
- Shop: A rank book's price counts in the total and the training figure
- Fishing: A lure or pole no longer tells you to train the next rank early or hides the plan near 300
- Fishing: The Guide tab's Fishing row follows Fish for Cooking and lists only Cooking's fish
- Fishing: The heading and the fish sources show the same chance to land a catch
- Skinning: A beast someone else is looting no longer drops off your list
- Skinning: A beast whose levels need different skill shows the range
- Guide: The step card counts materials in your bank before telling you to buy them
- Guide: Disenchant for Enchanting skips dust and essence you already hold
- Items: The item tooltip counts mail and pending purchases
- Skinning: A corpse's tooltip counts leather waiting in your mail or bought and on its way
- Fishing: A lure no longer keeps you fishing in water far above your level
- Guide: A dropped profession no longer leaves its next step, launcher text or Enchanting dust count behind
- Patterns: A pattern comes back once the vendor restocks it
- Patterns: A pattern learned with the profession window shut leaves Patterns to buy here
- Patterns: A merchant slot that has not loaded no longer marks a pattern sold out
- Guide: The stop warning no longer fires on a batch of another recipe from Daylight UI's window
- Guide: A recipe sold for Merchant's Favor says where to get it
- Tooltip: Items the guide makes itself are no longer called short or sent to farm
- Guide: Sitting by a campfire no longer flashes the guide window or fights Daylight UI's fade setting
- Guide: The guide no longer errors when another addon's button hides its size
- Guide: Items a vendor sells in limited stock are no longer counted as always available
- Shop: An item the latest full price scan no longer saw stops showing its old auction price
- Buy for guide: A vendor material two professions both need is bought for both, not once
- Routes: Herbs and ore you only know from GatherMate2, your own finds or other players now get stops on the route
- Routes: A loop that crosses bare ground no longer loses stops while the walk is well under the cap
- Routes: The loop length shows the yards you walk
- Enchanting: The dust note names the steps the other guide really shows
- Enchanting: The Strange Dust now count drops as you craft the other guide's step
- Shop: Purchases whose mail hasn't loaded yet stay counted
- Farm: A creature you can't skin leaves the checklist and leather list at once
- Guide: A reset while zones are being found no longer leaves it stuck on finding zones
- Route: Stop rings change colour as soon as your skill rank does
- Guide: The craft button shows after a /reload with your profession window open
- Enchanting: The dust count matches on the Tailoring and Enchanting cards
- Enchanting: The Enchant again key does nothing when the card's button would not enchant
- Enchanting: Enchant again casts the spell your character knows the step by
- Guide: The step's sale line counts the items it makes, not the crafts
- Guide: The profession menu shows your skill rank as the launcher does, with any bonus beside it
- Guide: Daylight UI's recipe-line step marks follow your steps in All mode, on other tabs and while the guide is closed
- Guide: The All-mode Craft all tooltip shows the materials you still need after buying some
- Gathering guide: Importing GatherMate2 data no longer freezes the game for a moment
- Routes: Redrawing a route on the map no longer stutters
- Disenchant: The Disenchant button no longer does layout work every frame
- Gathering: Long names in the gathering list wrap without being cut by the scroll bar
- Guide: Pattern, reputation and quest recipes say where to get them instead of "Learn from a trainer"
- Buying: The patterns popup only lets you buy what you can afford after the materials are paid
- Guide: Side crafts that tie are picked the same way every session
- Route: A route redraws when new footprints are learned
- Guide: Material names on the step card fill in once the game loads them
- Guide: A pattern you already own in your bags, bank or mail no longer sends you to the vendor
- Gathering: The guide asks you to level up instead of sending you to a zone where almost every node is too low to give skill

## 1.2.1
Hotfix: the craft button works again with Daylight UI 2.0's profession window open.

### Fixed
- Guide: The craft button shows again when Daylight UI 2.0's (or another addon's) profession window is open

## 1.2.0
Renamed to Professionally Lost with the /proflost command. The plan holds steady, the guide trains the recipes for a step's materials, and the gathering panel shows where to farm cloth. Settings start fresh once under the new name.

### New
- Guide: Click "with Enchanting" in the header to plan with or without it
- Guide: Right-click the window's title to open the settings
- Guide: When a step's count goes up, its card says why
- Gathering: Show one profession or all in the gathering panel (its menu)
- Gathering: Open the guide window from the gathering panel
- Gathering: The gathering panel shows where to farm the cloth your guides need
- Gathering: A pattern you can learn right now pulses green in Patterns to buy here
- Guide: A warning on the step card tells you to stop a batch once your skill passes the step's end

### Changed
- General: The addon list names it Professionally Lost (DaylightUI Plugin)
- Guide: Training for the next rank shows when you reach the cap or visit the trainer anyway
- Guide: A step picked to disenchant for Enchanting always says so on its card
- Guide: A step you can't craft yet says which material to make first
- Guide: Enchanting shows how much dust your other profession gives now and how much later
- Guide: The craft count of the step you're working holds steady and counts down as you craft
- Gathering: The gathering panel no longer has a Next up section
- Guide: The plan holds still: targets you reach stay reached, and the route only changes when a step ends or something becomes impossible
- Guide: The closed docked guide folds into a button beside the profession window that fades in
- Gathering panel: The guide button and its menu entry now close the guide when it is open
- General: The data bar lists the minimap button as Professionally Lost, without "(button)"
- Gathering: Cloth rows count every creature that drops the cloth, not only humanoids
- Gathering: Cooking and Fishing sit at the bottom of the gathering panel
- Guide: The title tooltip reads "Right click to open settings"
- Guide: The step you're on, and any step you've started gathering for, stay as they are; the rest of the guide keeps improving
- Guide: Guide rows have no tooltips
- Guide: Re-plan is gone
- Guide: A step that only moved no longer says "Moved because an earlier step changed"
- Commands: The chat command is now /proflost
- Key Bindings: Rebind "Enchant again" under Key Bindings > Professionally Lost
- Name: The short name is now ProfLost, as on the auction house's ProfLost Scan button and in the Plugins rail
- Name: Chat, tooltips and the bug report say Professionally Lost
- Settings: Settings start fresh under the new name; set them up again once

### Fixed
- Guide: A fishing lure or a better pole no longer moves the fishing guide past your real skill
- Guide: Long step names show in full instead of ending in "..."
- Guide: The vendor buy count covers the whole step, not only what your gathered materials make now
- Guide: Fishing no longer changes other guides through rare items you might fish up
- Guide: A row names another profession only when that profession changed that row
- Gathering panel: Picking a profession or route option no longer flashes the game's menu
- Gathering panel: The patterns count comes back when you fold Patterns to buy here again
- Guide: With Enchanting, greens such as Copper Chain Belt count toward the dust they disenchant into
- Guide: Recipes turn green in the guide at the same skill the game shows them green
- Guide: The header names only professions you have
- Guide: Closing the docked guide leaves just its button, with no empty bar beside the profession window
- Gathering panel: Cooking and Fishing show again with Farm picked, with the meat and eggs creatures drop and the fish the water gives
- Gathering panel: a profession's grind spots are numbered from #1, so a lone spot is never "#3"
- Gathering: In Farm, each profession keeps its own grind spots on the map
- Gathering: Farm's fishing lists only fish you can really catch
- Settings: Options for a profession you don't have are hidden, not stuck on
- Guide: Recipes that make a step's materials (bolts, oils, grinding stones, blasting powder...) get their own Train row
- Guide: Picking an "or" row keeps it picked when the profession window selects its recipe
- Guide: A recipe no longer shows as two rows in a row

## 1.1.0
Gathering nodes that spawn several kinds show their odds, counts on the folded window show in full, and settings and picks stay put.

### New
- Gathering: A node that can spawn as different ores or herbs shows its odds, like "Tin Vein 80% · Silver Vein 20%"

### Changed
- Gathering: Node pins on the minimap are open rings, so the game's own tracking circle shows inside them
- Gathering: Guides weigh a spot that can spawn several kinds by its odds, so some stretches pick other zones

### Fixed
- Guide: Your picked row stays when you switch professions and back, and after a reload
- Gathering: Routes run straight between nodes in open ground instead of swinging wide round creatures
- Gathering: Low-level gathering routes keep more nodes nearby instead of one long loop across the zone
- Gathering: A red node pin no longer sits on top of a route stop that can spawn that node
- Guide: A gathering step held back by your level no longer shows "~? gathers"
- Guide: Tailoring's Artisan rank asks for level 35, like every other profession's
- Guide: Material counts on the folded guide window show in full
- Guide: The skill beside the profession's name no longer runs over the name in a narrow window
- Guide: The font setting reaches every line of the guide window, also ones drawn after login
- Guide: The row you picked stays picked when you switch a setting off and on again
- Guide: The Shop tab comes back when you turn Gather it yourself off again
- Gathering: Patterns to buy in your zone show as soon as a profession needs them, not after you change zone

## 1.0.24
Every profession that changes another's guide now says so, the docked window closes, a cleaner gathering panel, and a big round of fixes.

### New
- Settings: "Plan for Enchanting". With Enchanting, your other guides favor crafts you can disenchant for what Enchanting needs. Turn it off to plan each guide on its own
- Guide: A step another profession changed says which one, like "· Enchanting", "· Alchemy" or "· Fishing", and its card says why. A gathering profession that changes a guide is named at the top of the guide
- Guide: A step that needs a tool says so: "Needs Blacksmith Hammer", "Make Runed Copper Rod first" or "Take it from the bank". A better rod or hammer counts
- Guide window: Close it while it sits beside a profession window. A small tab on the profession window brings it back
- Gathering: A zone you can't work yet reads "Thousand Needles: reach level 22" instead of sending you there
- Trainers: A trainer visit names the trainer and their fee, and the cheaper trainer when another charges less. A trainer we aren't sure of says "trainer not confirmed"
- Fishing: Horde can train Artisan Fishing from Katoom the Angler, and Buy for guide offers the Expert Fishing book

### Changed
- Settings: "Fish for Cooking" off plans Cooking as if you had no Fishing
- Next up: Names the step's own material and how many it lacks, like "Heavy Leather x57" or "Make Mote of Magic x23". How much you need by the next skill cap is in its tooltip. A step that lacks nothing reads "Ready to craft" and the recipe
- Enchanting: Mote of Magic is bought from Enchanting Supplies vendors for 10 copper, and the card names the nearest vendor
- Gathering: Grind spots read as one line, like "Level 21-24", with each material's average drop chance. Open a spot to see its creatures
- Gathering: Farm lists only what you picked and what the zone has: grind spots, herbs, ore and nearby zones. It no longer shows or weighs what your guides need
- Gathering: Zone levels count only the creatures you fight, so zones are suggested at the right level
- Gathering: Fishing stays on your own faction's ground. Alliance fish Loch Modan, not the Barrens
- Gathering: A row names only what you can gather when you start it, and a row of green targets says "(green)"
- Trainers: Journeyman and higher trainers teach every recipe up to their rank, so more trainers are listed
- Guides: More accurate vendors, trainers and learn levels, using what players saw in Forever (data from ForeverDB.net and ItemTree). Copper Chain Pants learns at 15, Linen Bag at 5, Healing Potion and Mana Potion are bought from vendors, and Mote of Magic has more sellers
- Tooltip: A creature's item your guides are short of shows in your accent color
- Guide window: The view switch reads Single / All, and the craft buttons read Craft 1, Available and Craft all
- Bug reports: A report carries your profession skills, known recipes and settings, with no names, so the problem can be replayed
- General: Works with Daylight UI 1.9.0

### Fixed
- Guide: A recipe you already know is no longer planned as a pattern to buy, whichever profession window you use. If ProfLost hasn't read a profession yet, it asks you to open it once
- Guide: The step you're working on holds. Making bolts no longer hands the step to Linen Cloak, and a step that still gives points doesn't jump to a pattern you just became able to learn
- Guide: The same steps with the profession window open or shut, and the guide no longer shifts after a reload or a setting turned off and on
- Guide: A recipe list that is still loading no longer gives a different plan
- Guide: A sold-out pattern leaves another recipe to carry on
- Guide: Trainer visits never send you to a trainer who doesn't teach the recipe
- Guide: All mode's Craft opens the right profession window first
- Guide: The Stop strip goes away when a batch ends
- Guide: Robe of the Archmage's card shows all seven materials
- Next up: Counts what the step card counts, and stays right after you read a profession through another addon's window
- Gathering: Leathers, herbs or ore you untick in Farm no longer disappear from Follow the guide, and folded sections stay folded per mode
- Gathering: Grind spot levels, drop chances and map pins update as your skill rises
- Gathering: No more being sent somewhere deadly because an errand left you there
- Gathering: A level up redraws the guide, and a skinner stuck on green creatures is told the level to reach
- Gathering panel: /proflost gather and Shift-click on the minimap button undo themselves when pressed again, and the panel slides out again after you detach and re-attach it
- Pattern vendors: The unseen pattern count comes back after the setting is turned off and on, and never follows you into another zone
- Chat: No more debug lines in chat
- Little touches: The enchant card says "On your item" while the item's name loads
- Performance: The gathering panel no longer rebuilds itself over and over after a route is worked out
