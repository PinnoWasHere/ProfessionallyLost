# Contributing to Professionally Lost

Bug reports, data fixes and code changes are welcome.

## Reporting a bug

- Type `/proflost bug` in game, copy the report, and paste it into a new issue.
- Say what you did, what you saw and what you expected.
- Wrong guide data (a recipe, vendor, trainer or location) has its own issue form.

## Running the tests

- Needs Python 3.9 or newer and LuaJIT (or Lua 5.1) on the PATH.
- `python tools/test.py` runs every headless test.
- `python tools/test.py tests/headless/clamp_test.lua` runs one file.
- Each file loads a fake game (`tests/own`), the addon by its `.toc`, the fake worlds (`tests/world`) and
  the shared rules (`tests/rules`), then the test.
- The same tests run on every pull request.

## Pull requests

- One change per pull request.
- Add or change a headless test that fails before your change and passes after it.
- Describe the change as a player would notice it. The maintainer writes the changelog line from it.
- Write Lua 5.1, the game's own Lua. LuaJIT-only names and escapes break in game.
- With Daylight UI loaded, every frame, button, menu, fade and sound comes from Daylight UI's own
  builders. Never draw a lookalike.

## Data fixes

- The files under `ProfessionallyLost/Data/` are generated from game data.
- A fix is still welcome as a pull request that edits the file.
- Say where the fact comes from: an in-game check, a screenshot, or a database page.
- A merged data fix is also recorded where the data is built, so the next rebuild keeps it.

## Licence of contributions

- Professionally Lost's code and art are under Part 1 of `ProfessionallyLost/LICENSE.txt`.
  The generated data files are under the GNU GPL version 3 (Part 3).
- By opening a pull request you confirm the contribution is your own work, or that you have the
  right to submit it.
- For code and art, you grant PinnoWasHere a perpetual, worldwide, non-exclusive, royalty-free,
  irrevocable licence to use, change, sublicense and distribute your contribution as part of
  Professionally Lost, under the addon's licence.
- For the generated data files, your contribution is licensed under the GNU GPL version 3, the same
  as the file you change.
