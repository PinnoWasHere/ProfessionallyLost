# Professionally Lost (DaylightUI Plugin)

I got tired of alt tabbing for the free profession leveling guides or paying for others. I made this plugin for DaylightUI as an alternative to those.

## What it does
- Guides for all professions.
- Picks the cheapest/most efficient recipe for each skill point and marks where you need a trainer or a pattern.
- Pulses a guide step in green when you have a pattern in your bags or bank.
- Alternative steps for when you don't want to buy the pattern.
- Identifies vendors that sell patterns in your current zone on the Gathering window that are needed for future guide steps.
- "One" view walks through a single profession. "All" view shows all your learned professions in a compact single step guide.
- Craft buttons right in the guide, and an Open button when the profession window is shut. Both the blizzard profession window and ProfLost craft buttons work, but ProfLost focuses on the guide steps specifically.
  -- The Max in the guide will only craft the max amount needed to finish the guide step.
  -- Available is to craft the max amount for the materials you have on hand.
- "Gather it yourself" mode tailors the guide dynamically around your current level/zone/profession skill level.
- When this option is off, you are shown a Shop tab with the assumption you want to buy all the materials and powerlevel your chosen professions.
- "Buy for guide" at a vendor buys the materials and patterns your guides need for the active step.
- Auction prices come from DaylightMogul, Daylight UI's Auction House or Auctionator, whichever you use. ProfLost's own Scan prices button at the auction house fills the gaps.
- A Disenchant tab for enchanters that warns you when selling an item is worth more with semi-auto disenchanting.
- A Gathering window that lists what to gather in your zone, grind spots, nearby zones and pattern vendors, with a route on the map and minimap for Herbalism and Mining whereas Skinning would get the top 3 grind spots in the zone for the crating material you want to gather/farm.
- Tooltip lines and bag marks for items your guides need for your current guide step.

And much more!

The window uses your Daylight UI colors and fades and saves with your Daylight profiles. You can hide it in combat, move it with `/dui unlock`, and change its font, size and scale. Every setting is in Daylight UI's options under Plugins, then ProfLost.

## Requirements

- Daylight UI (required)
- DaylightMogul (optional) for auction prices and its profession window
- GatherMate2 (optional) adds your recorded nodes to the gathering route

## Data and licences

The guide data is built from the CMaNGOS classic-db, GUIDZ, GatherLite, ForeverDB and ItemTree (trainer windows and vendor sales its players recorded), with the game's own tables. Data from ForeverDB.net (https://foreverdb.net). The full notices are in `ProfessionallyLost/LICENSE.txt`.

## Commands

- `/proflost` shows or hides the guide
- `/proflost gather` shows or hides the Gathering window
- `/proflost settings` or `/dui pl` opens the settings
- `/proflost bug` opens a bug report you can copy

## Bugs

If something breaks, type `/proflost bug`, copy the report, and post it in the Professionally Lost thread in the forum on [Daylight UI's Discord](https://discord.gg/eeSYZDd6ar).

## Contributing

Bug reports, data fixes and code changes are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first. `python tools/test.py` runs the headless tests.
