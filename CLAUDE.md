# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A hunter Auto Shot swing timer for World of Warcraft, targeting **TBC Classic Anniversary 2.5.6 (Interface 20506)** first, with a later WoW Forever port planned. Two parallel artifacts share one timing model:

- `addon/OzzySwingTimer/` — the in-game addon (plain Lua + WoW frames/textures, no external libraries).
- `swing-lab/` — a backend-free web simulator (vanilla ES modules in `swing-lab/dist/`, no build step) used to experiment with the timing model and UI before porting ideas to the addon.

The user communicates in Swedish; always reply to them in Swedish.

Project docs (`PROJEKTBESKRIVNING.md`, `docs/timing-design.md`, `addon/OzzySwingTimer/README.md`) and the simulator UI are written in **Swedish**; keep new user-facing docs/text in Swedish. `PROJEKTBESKRIVNING.md` is the current status/roadmap; `docs/timing-design.md` lists open mechanics questions and test plans.

## Commands

Run from the repository root (paths in the test files are root-relative):

```sh
# Lua addon tests (Fengari, no WoW or system Lua needed)
.diagnostics/lua-runner/node_modules/.bin/fengari addon/tests/run.lua

# Simulator logic checks (node:assert against dist/*.mjs)
node swing-lab/check.mjs

# Headless Chrome check of the simulator UI (serves swing-lab/dist, needs Chrome at the default Windows path)
node .diagnostics/browser-check.mjs
```

There is no test filter; `addon/tests/run.lua` is a single script of `test(name, fn)` calls that stops at the first failure. To focus on one test, temporarily comment out others. Release zips go in `releases/` (e.g. `OzzySwingTimer-0.1.0-TBC.zip`) and must contain the `OzzySwingTimer/` folder at top level so it installs to `Interface/AddOns/OzzySwingTimer/OzzySwingTimer.toc`.

## Addon architecture

Load order (from the `.toc`): `Model.lua` → `Display.lua` → `OzzySwingTimer.lua`. Files share state through the addon namespace (`local _, ns = ...`; `ns.Model`, `ns.Display`, and at runtime `ns.model`/`ns.display`).

- **Model.lua** — pure timing state machine, no WoW API calls. Phases: weapon cooldown (slow fill right→left), wind-up (fast fill left→right), `blocked`. Tracks cast and GCD "locks" and renders their **union** (not sum) as `Segments()`, including GCD carried into the next cycle. `QueueWindow()` is the part of wind-up after the current cast/GCD ends. Flash confirmation is a sequence: `Sent` (eligible attempt in window) → `Shot` → `Confirm` (cast start); `Failed` cancels. `View(now)` produces what the display paints.
- **Display.lua** — WoW frame/texture construction and `Paint(view, ...)`. In-game bar shows no text or numbers by design.
- **OzzySwingTimer.lua** — event wiring, `/ozs` slash command (`SlashCmdList.OZZYSWINGTIMER`), SavedVariables `OzzySwingTimerDB`, debug log (last 200 events), and test/demo mode.

Key modeling rules to preserve (see addon README for detail):
- Shots are anchored to `UNIT_SPELLCAST_SUCCEEDED` for spell 75 (fallback `SPELL_CAST_SUCCESS`), never projectile damage. No reported shot ⇒ no invented new cycle.
- Weapon speed from `UnitRangedDamage`; cast and GCD are read separately from the client — never use the simulator's fixed GCD in the addon.
- Wind-up is a forecast (0.5 s, haste-scaled) until calibrated from an observed shot start/fire pair; weapon swap clears learning.
- GCD does not block Auto Shot; unknown GCD never shows a green cue; movement interrupts wind-up.

`addon/tests/run.lua` loads `Model.lua` directly for unit tests, then stubs WoW globals (`CreateFrame`, `GetTime`, events, `SlashCmdList`, etc.) to load the full addon and drive events through `event(...)` / `update(t)`. When adding WoW API usage, extend those stubs.

## Simulator architecture

`swing-lab/dist/index.html` loads `app.js`, which wires DOM to small pure modules: `engine.mjs` (`Simulation` class: cadence, queueing, movement, auto-cast, simplified equal-damage DPS/clipping), plus view/preview helpers (`pendulum-view`, `queue-window`, `cast-preview`, `schedule-preview`, `action-budget`, `windup-window`). Keep logic in the `.mjs` modules so `check.mjs` can test it without a browser. `dist/` is the deployable static site as-is.

## Epistemic discipline

Much of the mechanics is unverified (queue behavior during wind-up, SpellQueueWindow/latency effects, early GCD start, haste effects, Forever differences). The addon has **not yet been verified in a running client**. When documenting or changing behavior, keep distinguishing hypotheses/working model from verified game mechanics, and keep button press vs. cast request vs. cast start vs. shot fire vs. projectile hit as separate timestamps.
