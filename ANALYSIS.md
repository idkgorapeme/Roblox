# BrainrotPolice — Repository Analysis

_Generated 2026-07-26. Snapshot: branch `arena/019f9f73-roblox`, base commit `e612f29`._

## 1. What this is

A **Roblox exploit/executor script** ("BrainrotPolice", by esore/vaehz) distributed as a
`loadstring(game:HttpGet(...))()` one-liner pointing at
`raw.githubusercontent.com/IcantAffordSynapse/BrainrotPolice/refs/heads/main/src/init.lua`.

It provides a draggable in-game GUI with per-game automation ("autofarm") modules for ~30
"brainrot" Roblox experiences. Apache-2.0 licensed, 34 Lua files, ~2.7k LOC total.

```
src/
  init.lua          49 LOC  bootstrap: env globals, config file, auto-rejoin, loads ui.lua
  ui.lua           200 LOC  loads the GUI asset, tab logic, dragging, game-module dispatch
  elements.lua     123 LOC  widget factory (Label/Button/Toggle/Textbox/Unsupported/addGame/Searchbar/Cred*)
  gameslist.json    30 entries: {game, id, status 🟢/🟡/🔴}
  credits.json      Developer / UI / Contributors
  games/<placeId>.lua  31 per-game modules, each `return function(section, data)`
```

## 2. Architecture

**Load chain:** `init.lua` → waits for `game.Loaded` → creates `BrainrotPolice/` workspace
folder + `Config.json` → defines globals `import`, `getgitpath`, `setconfig` → hooks
`GuiService.ErrorMessageChanged` for auto-rejoin → `loadstring(HttpGet(ui.lua))()` →
`queue_on_teleport` to persist across teleports.

**UI:** `ui.lua` pulls the GUI from `rbxassetid://75281832304062` via `game:GetObjects`,
parents it to `gethui()`/CoreGui, wires 5 tabs (Home, Game, GamesList, Settings, Credits),
then fetches `src/games/<PlaceId>.lua` over HTTP. Falls back to a local file in
`BrainrotPolice/<PlaceId>.lua` when `getgenv().FileScripts` is set, else renders the
"Unsupported" panel.

**Game module contract:** `return function(section, data)` where `section` is the container
instance and `data` is the decoded `Config.json`. Modules call
`elements:Toggle/Button/Label/Textbox` and persist state via `setconfig(key, value)`.

**Persistence:** single `BrainrotPolice/Config.json` with a `settings` table plus one
sub-table per PlaceId.

## 3. Correctness issues found

### 3.1 Data / manifest bugs (user-visible)

| Issue | Detail |
|---|---|
| Wrong place ID in `gameslist.json` | "Pole obby for Brainrots" is listed as `102515477731035`, but the module file is `105215477731035.lua` (digits transposed). The list entry launches a non-existent/wrong place, and the working script is unreachable from the list. |
| Orphan module | `games/99435399946069.lua` ("reel for brainrots new plr") is not in `gameslist.json` — it works if you're in that place, but is invisible in the UI. |
| Typo'd config key | `94780005879799.lua:11` — `setdata.farmsleepy = setdata.farmrofarmsleepyts or false` (garbled key), so the "Auto Spin Sleepy Mutation" toggle never restores its saved state. |
| Key mismatch | `137233438285284.lua` writes `setconfig("farmrots", v)` but reads `setdata.farming` — saved state never reloads. |
| No persistence call | `114640202062357.lua` (swing obby) initializes `setdata.farming` and writes the file, but the toggle never calls `setconfig`, and it seeds its default from `env.Farming` (always `false`) instead of `setdata.farming`. |
| Same pattern elsewhere | 10 toggles across `110627433764494`, `99255447043899` (both toggles), `114640202062357`, `77862067599263`, `83569851223739`, `94780005879799` default from `env.*` (always `false` at load) instead of `setdata.*` — "restore last state" silently doesn't work for them. |

### 3.2 Robustness

- **`setconfig` called bare vs. `getgenv().setconfig`** — both forms appear (7 files use the
  bare global, 16 use `getgenv().`). Works today only because `getgenv()` writes to the global
  env; brittle if the loader is ever sandboxed.
- **Config schema is never migrated.** `init.lua` only writes defaults when the file is
  *absent*. An existing `Config.json` from an older version lacking `settings.*` makes
  `ui.lua:188` (`dec1.settings.disable_3d_rendering`) throw and kill the whole UI. Same for a
  corrupt/truncated JSON — `JSONDecode` is unprotected in `ui.lua` at 4 call sites.
- **Every game module re-downloads `elements.lua`** (30 duplicate `HttpGet` calls in the
  codebase); `ui.lua` already has an `elements` instance it could pass in. Extra latency and
  extra rate-limit exposure against raw.githubusercontent.com.
- **`elements:Textbox` ignores its `def` parameter** — the default value is accepted but never
  applied to `tbbg.Inp.Text`, and the callback ignores the `enterPressed` arg (`ep` unused).
- **`elements:Searchbar` is marked `-- to finish`.** It destroys and rebuilds `GameElement`
  children on every keystroke, and because it re-reads the module-level `gameList`, an empty
  query re-adds the full list on top of the one `ui.lua` already rendered → duplicate rows.
- **Unbounded busy loops.** Toggle callbacks run `while getgenv().X do ... end` *inline on the
  callback thread* (`task.defer`'d from `elements:Toggle`), so enabling a farm blocks that
  coroutine indefinitely; several loops have `task.wait()` with no yield guard inside `pcall`
  retries. Only 14/31 modules use `pcall` around remote/instance access, so a missing
  `workspace.X` child hard-errors the toggle.
- **Toggle fires its callback on construction** (`task.defer(cb, isTog)`), meaning a saved
  `true` state auto-starts a farm loop at load — intended, but it means a bad saved config
  can wedge the UI at startup.
- **Auto-rejoin** relies on `getgenv().autorjjjj` set only by the Settings toggle's callback;
  the flag is not initialized from `Config.json` at `init.lua` time, so it only takes effect
  after `ui.lua` builds the settings tab.

### 3.3 Style / hygiene

- **Mixed line endings:** 14 of 31 game modules are CRLF, the rest LF. No `.gitattributes`,
  no `.editorconfig`.
- `84332574190497.lua` mixes tabs and spaces (line 99 is tab-indented `continue`).
- `108207853263201.lua` has no trailing newline.
- No linting/formatting config (`selene`, `stylua`), no CI, no `.gitignore`, no tests.
- README has a Lua syntax error in its own template: `elements:Textbox("This is a TextBox, section, "", ...)` — unbalanced quote.
- README "last update 02/07/2026" while `ui.lua` reports `Version: 0.33 BETA` — version string
  is hardcoded in the UI, not derived from anything.
- `gameslist.json` formatting is inconsistent (alignment collapses halfway through, one stray
  blank line, trailing space after the closing bracket).

### 3.4 Syntax validation

All 34 files parse cleanly as **Luau** (they use `continue` and generalized `for ... in
instance:GetChildren()`, which are Luau-only — they are *not* valid Lua 5.1, so any Lua 5.x
linter will report false errors). No syntax errors found.

## 4. Security / trust review

Nothing malicious found — no webhooks, no `HttpPost`, no clipboard exfiltration, no reading of
tokens or cookies. The only `setclipboard` writes the Discord invite. `plr.UserId` is used only
for plot lookups.

That said, the distribution model is inherently high-trust:

- The loader executes **whatever is on `main` at that moment**, unpinned — every run is a fresh
  remote code fetch, and `queue_on_teleport` re-executes it after every teleport. Anyone with
  push access to the upstream repo (or anyone able to MITM/serve that path) has arbitrary code
  execution in every user's executor.
- The GUI comes from `rbxassetid://75281832304062` and the element templates from
  `rbxassetid://113037265185555` via `game:GetObjects` — opaque binary assets, unversioned and
  unreviewable in-repo. If those asset IDs are ever repurposed, behavior changes silently.
- `getgenv().FileScripts` loads and executes arbitrary user `.lua` from the executor workspace
  by PlaceId with no validation — documented feature, but worth flagging.
- Functionally this is cheating automation (remote-event spam, `firetouchinterest`,
  `fireproximityprompt`, teleport-to-collectible loops) and violates the Roblox ToS; the
  `.\ ..LockpickGateOpen` / "Steal from all" logic in `98868317791094.lua` fires remotes on
  other players' plots.

## 5. Suggested priorities

1. **Fix `102515477731035` → `105215477731035`** in `gameslist.json`; add the orphan
   `99435399946069` entry (or delete the file).
2. **Fix the three broken persistence paths** (`94780005879799` typo, `137233438285284` key
   mismatch, `114640202062357` missing `setconfig`) and normalize all toggles to default from
   `setdata.*`.
3. **Harden `init.lua`/`ui.lua`:** deep-merge missing config defaults instead of write-if-absent,
   and `pcall` every `JSONDecode` with a reset-to-defaults fallback.
4. **Pass the `elements` table into game modules** (`gameModule(section, data, elements)`,
   keeping the current `HttpGet` as a fallback) to kill 30 redundant network round-trips.
5. **Normalize line endings** with `.gitattributes` (`*.lua text eol=lf`) and add
   `stylua.toml` + `selene.toml` (Luau std) with a small CI job that at minimum parses every
   file and validates `gameslist.json` against `src/games/*.lua`.
6. Finish or remove `elements:Searchbar`; apply `def` in `elements:Textbox`.
7. Fix the README template's quote bug.
