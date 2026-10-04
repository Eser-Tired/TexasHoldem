# Repository Guidelines

## Project Structure & Module Organization

Chinese Texas Hold’em supports single-player practice and 2–4-player LAN rooms. Use Godot 4.7.2 and matching export templates.

- `scripts/`: GDScript source. `poker_rules.gd` evaluates hands and pots; `poker_table.gd` manages betting and AI; `lan_room.gd` owns ENet rooms and authoritative RPCs; `poker_view.gd` provides client views. `menu.gd` and `main.gd` implement the interface.
- `scenes/`: lobby and table scenes; `project.godot` starts the lobby.
- `assets/`: icon and bundled Noto Sans SC font with its license.
- `tests/`: standalone Godot test scripts and the multiplayer PowerShell runner.
- `tools/`: release tooling. `docs/` explains networking and platform builds.

## Build, Test, and Development Commands

Run from the repository root in PowerShell:

```powershell
godot_console --headless --editor --import --quit --path .
godot_console --path .
godot_console --headless --path . --script res://tests/test_poker.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Run-LanTests.ps1
./tools/Build-Release.ps1 -JavaHome 'C:/Program Files/Java/jdk-25.0.2'
```

These commands import resources, launch the game, test rules, exercise 2/3/4-player ENet rooms, and export signed APK/Windows EXE files with checksums. Replace the JDK path; configure Android tooling and signing through `docs/BUILDING.md`.

## Coding Style & Naming Conventions

Follow existing GDScript: tabs for indentation, `snake_case` files/functions/variables, `PascalCase` class names, and `UPPER_SNAKE_CASE` constants. Use typed parameters and return values where practical. Prefix internal helpers with `_`. Keep rule logic separate from UI and networking. Preserve Chinese interface text and tracked `.uid` files. No formatter or linter is configured; check Godot import diagnostics.

## Testing Guidelines

Tests use standalone `SceneTree` scripts and assertions. Name tests `tests/test_<feature>.gd`. Run relevant scripts using the command above: `test_ui.gd`, `test_menu.gd`, `test_lan_rules.gd`, and `test_lan_admission.gd`. For touch layout, append `-- --touch-layout`; run `test_mobile_layout.gd` with that flag to check multiple resolutions. Add regressions for betting boundaries, chip conservation, private-card isolation, and rejected RPCs. No percentage coverage target is configured. Require passing assertions and inspect logs for errors.

## Commit & Pull Request Guidelines

History uses concise, imperative summaries such as “Add 2-4 player LAN rooms with private hand snapshots”; no mandatory prefix exists. Keep commits focused. PRs should explain behavior changes, list validation, link related issues, and include screenshots for UI changes. State platform testing limitations.

## Security & Release Configuration

Validate actions on the host and send only recipient-appropriate cards. Never commit `.private/`, signing passwords, keystores, generated builds, or test logs. Preserve the existing Android signing key for upgrades. Synchronize versions in `project.godot` and `export_presets.cfg`, and retain the font license.
