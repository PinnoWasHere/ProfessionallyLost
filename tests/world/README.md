# Headless worlds

Fakes of the game, Daylight UI and DaylightMogul for the headless tests. A test starts
the worlds it needs, plays a scene against them and checks what ProfLost did.

## Load order

- `tests/world/order.txt` lists the fixtures and worlds in load order.
- They load before every test file and are never shuffled.
  - `tests/own/run.lua` reads `order.txt` and loads every file in it before each test file.
- A new world: add it to `order.txt`.

## Worlds

| File | Global | Models |
|---|---|---|
| `init.lua` | `World` | Patches, closers and world-to-world messages; ends every world after each test |
| `craftworld.lua` | `CraftWorld` | Professions and ranks, known recipes, bags and bank, opening and closing a profession window, casts |
| `solves.lua` | `Solves` | Route.Solve answers shared across the scenes of a test file (opt in per scene) |
| `mapworld.lua` | `MapWorld` | Zone and position, the best map apart from the zone, place names, continent geometry, level, faction, instances |
| `ahworld.lua` | `AHWorld` | Auction house open and shut, item keys, searches and their answers |
| `daylightworld.lua` | `DaylightWorld` | `DaylightUI.API` 1.3: plugin calls, its craft window, pane, events, Paint, settings |
| `mogulworld.lua` | `MogulWorld` | `DaylightMogul.API` 1.6: Price, On, Craft/Ledger/Mail/Vendor, its craft window |
| `peerworld.lua` | `PeerWorld` | Other ProfLost players and the addon-message network: hellos, digests, chunks, guild, group, combat, zone moves |
| `visual.lua` | `Visual` | What the harness keeps no record of: rects from anchors, frame levels, strata, alpha, scale, text widths, children, Daylight UI's window skins; `Visual.Check(label)` runs `Look.Check` |
| `leakwatch.lua` | `LeakWatch` | Not a world: in `check.py --orders` it names each test file that leaves shared state changed (`leakmark.lua` runs it between files) |
| `leak_allow.json` | - | Not a world: the leak watch's allow list, each entry with a reason; a stale entry fails a full `--orders` run |

Each file's header says what it models and what is a guess.

## Fixtures

- `tests/fixtures/items.lua`: item names from Forever's ItemSparse DB2.
- `tests/fixtures/maps.lua`: maps and their world rectangles from UiMap and UiMapAssignment.

## Rules

- A world starts with `<World>.begin(spec)` inside a test, never at file level.
- `T.test` ends every world after the test, pass or fail.
  - Patches come off in reverse order.
  - `World.onEnd` closers run first.
- A world patch calls the harness stub first, so argument checks and `T.calls` still work.
- A patch returns `World.PASS` for the harness stub's own answer.
- `T.stub` on a path a world has patched does nothing until the world ends.
- `craftworld` swaps `CP.charDB` for an empty table, so a scene starts as a new character.
- Every `T.test` runs on a copy of `CP.charDB` and of `CP.db` footprints, finds and skinSeen (`World.LEARNED`), so what it writes there ends with it.
- `World.redraw = true` makes `World.finish` call `Window.Update()` once the patches are off, so the windows show as the restored settings say.
- Each world puts back the shared state its scene writes:
  - `mapworld`: `VendorWatch.current` and `counted`.
  - `craftworld`: `CP.db.windowHeight`, and it sets `World.redraw`.
  - `daylightworld` with `plugin`: every setting `Plugin.Sync` copies into `CP.db`, and the carry-over flags.
- `T.calls` sees only the current test's calls; the harness clears them as each `T.test` starts.
- `mapworld` shares `Waypoint.MapPosZone` answers across scenes and test files.
  - A memo hit makes no `C_Map` calls, so `T.calls` doesn't count them.
  - A test that swaps `MapPosZone`, a `C_Map` map call or `CreateVector2D` gets the live call.
- `MapWorld.begin{ shareSolves = true }` stores each `Route.Solve` answer by its full input (points, zone size, cap, grid, start, tunables) and returns it to a later identical call in the same process, with the new call's own point tables. `solves.lua` holds it. Tests of the solver itself leave it off. `SOLVES_VERIFY = true` runs the real solver beside every stored answer and errors on a difference.
- `MapWorld.begin{ count = true }` counts every `C_Map` call by name in `MapWorld.calls` and turns the memo off.
  - `MapWorld.CallCount()` gives the total.
- The gathering guides build their zones in a background job (`GatherGuide.Warm`).
  - A test that reads guide rows, the launcher's gathering lines or Next up calls `MapWorld.SettleGuides({ line })` first.
  - Call it under the map answers the test reads with; swapping a map call starts the zones over.

## Example

```lua
T.test("a batch counts down", function()
    MapWorld.begin({ zone = 1421, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [165] = 1 }, bags = { [2318] = 10 } })
    CraftWorld.Open(165)
    ProfLost.Crafting.Start(2152, 3)
    CraftWorld.Cast()
    T.eq({ ProfLost.Crafting.Progress() }, { 1, 3 })
end)
```

## Checking the look

- The look scenes walk every state of the guide window and the gathering panel, and the moves between them, on the Daylight UI stub (real Daylight UI, real font widths) and run `Look.Check` in each. The headless tests that still call `Visual.Check` use this world.
- `Visual.Check` fails with every broken rule of `Look.Check` (UI/LookCheck.lua), each line prefixed by the state's label. `/proflost check look` runs the same check in game.
