# Lending Shop (working title)

A dungeon lending-shop sim: lend gear to adventurers, watch their runs play out, take one card from each survivor's haul. Built in **Godot 4.7.2** (GDScript, Compatibility renderer). Ships on itch.io first, then Steam, and is set up so other stores can be added without touching game code.

## Run it

1. Open the folder in Godot 4.7.2 and press F5. Boot → Title → "New season" plays days with a placeholder shop; "Sim sandbox" lets you roll heroes and watch delves.
2. Tests: `GODOT=/path/to/godot tools/test.sh` (unit tests + scene smoke test; also runs in GitHub Actions).
3. Balance tables:
   - `godot --headless --path . -s res://tools/balance_sim.gd -- --runs 500` → death rate per class × gear tier × floor, also written to `build/balance.csv`.
   - `godot --headless --path . -s res://tools/season_sim.gd -- --seasons 200` → whole seasons played by a bot: win rate, which day seasons are lost, gold curve. Run it overnight after big changes.

## The four rules of this codebase

1. **Content is data.** Heroes, traits, items, mods, materials, monsters, floors, achievements and every tuning number live in `data/*.json`. Code never hard-codes a sword or a damage number. Typos are caught at boot and shown on screen.
2. **The simulation decides, playback only shows.** `RunSimulator` resolves a whole delve from a seed and returns an event log. `RunPlayback` animates the log. So the 1x/2x/4x speeds and Skip cost nothing, estimates run 200 sims in ~50 ms, and a save made mid-delve replays exactly.
3. **One save object.** `GameState` is the whole saved game. Scenes call `Game` (the autoload), `Game` calls `Season` (the rules), nobody edits state from UI code. Autosaves every dawn and right after heroes leave.
4. **Juice is one line.** `Juice.shake()`, `Juice.hitstop()`, `Juice.pop()`, `Juice.popup()`, `Juice.roll_number()`, `Juice.bind_button()`, `Audio.play()` with pitch variation. If it takes more than a line, add a helper to `juice.gd`.

## Layout

```
data/                 all game content (JSON, one row per thing, unique "id")
src/
  core/               pure logic, no nodes: Rng, ContentDB, GameState, Season rules, SaveSystem, AutoPlayer
  sim/                pure logic: RunSimulator (+ event types), Hero, Gear, HaulGenerator, SurvivalEstimator
  platform/           PlatformBackend (local / itch) and SteamBackend
  presentation/       RunPlayback, PlaybackActor, CharacterSprites, UiTheme, InputActions
  autoload/           Events, Content, Platform, Audio, Settings, Juice, Game, Router
scenes/               boot, title, shop (placeholder day loop), dev/sim_sandbox
tests/                headless unit tests + scene smoke test
tools/                balance_sim, season_sim, capture (screenshots), test.sh
assets/               characters/, audio/sfx, audio/music, fonts/, icons/, ui/, vfx/
```

Everything in `src/core` and `src/sim` is plain code over Dictionaries, with no scene or autoload access. That is what lets tests and the balance tools run thousands of seasons headless.

## Determinism

All randomness in rules goes through `Rng`, seeded from the season seed plus labels (`Rng.derive(seed, ["delve", day, hero_uid])`). Never use the global `randf()`/`randi()` in `core/` or `sim/` (cosmetic randomness in juice is fine). Saves keep dictionary order (`sort_keys = false`) so a reloaded season continues identically. Tests check that the same seed gives the same run and the same whole season.

If you change simulation rules, bump `RunSimulator.SIM_VERSION`. Saved event logs still play back because they are stored, not re-simulated.

## Art drop-in

Character sprites load at runtime from `assets/characters/<Sprite>/<Sprite>-<Anim>.png` (Zerie pack layout, flattened: e.g. `assets/characters/Soldier/Soldier-Attack01.png`). `<Sprite>` is the `sprite` field in `classes.json` / `monsters.json`, so match those to the pack's folder names. Sheets are rows of 100×100 frames. Until a sprite exists, a placeholder block plays the same timing, so nothing waits on art.

Pixel settings are already set: 640×360 viewport, integer scaling, nearest filtering, pixel snapping. Drop a pixel font at `assets/fonts/body.ttf` and the UI uses it. Sounds go in `assets/audio/sfx/<name>.ogg|wav` with the names the code already calls (`hit`, `hit_crit`, `hurt`, `block`, `kill`, `death`, `treasure`, `trap`, `heal`, `click`, `hover`, `coin` ...); missing sounds are silent, not errors.

## Stores and platforms

Game code only ever calls `Platform.unlock("first_loan")`, `Platform.storage()`, `Platform.open_store_page()`, etc. Which backend runs is picked by **export feature tags**:

| Export preset | Tag | Backend |
|---|---|---|
| Windows / Linux / Web (itch) | `itch` | `PlatformBackend`: saves in `user://saves/`, achievements stored locally |
| Windows / Linux-Steam Deck (Steam) | `steam` | `SteamBackend` via GodotSteam; falls back to local if Steam isn't running |

Achievements are defined once in `data/achievements.json` with a per-store id map (`"store_ids": {"steam": "ACH_FIRST_LOAN"}`).

**Going to Steam:** install the GodotSteam GDExtension into `addons/`, set `game/steam/app_id` in Project Settings, turn on Steam Auto-Cloud for the `saves` folder in Steamworks (no code needed), export with a Steam preset.

**Adding another store** (GOG, Epic, consoles): subclass `PlatformBackend`, override what that store offers, add a feature tag and a branch in `Platform._create_backend()`, add export presets. No game code changes.

Export templates are not committed. Install them from the editor (Editor → Manage Export Templates) before exporting. `data/*.json` is in every preset's include filter; keep it there or exported builds won't find their content.

## The party

You keep a party of up to 4 heroes (`balance.json` → `party`). Day 1 brings 4 walk-ins; the ones you kit out join, the rest leave for the tavern. Each later morning there is a chance of one walk-in (one is guaranteed per empty seat). Taking a walk-in into a full party means letting someone go; they go to the tavern and may walk in again later, keeping their level. Party members you don't kit out rest that day. Every hero has one trait, rolled Common / Uncommon / Rare (`trait_rarity_weights`), affecting stats, gold, materials, mod finds or potions.

Potions go in a fourth "pack" slot and are sold by the merchant. Run-long potions (Haste Tonic, Courage Draught) are used up every run; a Healing Draught is drunk automatically at low HP and only used up if drunk.

## Combat timing (Haste)

Combat uses action meters, the same as the haste meter in Ore Heroes. Every tick, each unit adds its **Haste** to a meter, and when the meter reaches 100 it acts (overflow carries over). A Haste 12 archer acts about twice as often as a Haste 6 slime. Ranged heroes and casters start a fight with a full meter, so they shoot first. Frost's *chill* halves a monster's Haste; Shock's *stun* wastes a full meter. Haste comes from the class, gear (light weapons +, heavy armor and axes -), the Quicksilver mod and some traits. Events where someone acts carry `tick` and a `meters` snapshot so playback can draw action bars that match the simulation exactly.

## Event log

`RunSimulator` documents every event type at the top of `src/sim/run_simulator.gd` (`run_start`, `room_enter`, `spawn`, `attack`, `hit`, `block`, `dodge`, `status`, `kill`, `drop`, `treasure`, `trap`, `heal`, `retreat`, `death`, `run_end`). Adding a mechanic means: emit a new event in the sim, add a case in `RunPlayback._show()`, add a beat length in `RunPlayback.BEAT`.
