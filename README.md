# Omarchy onboarding

First-boot onboarding for [Omarchy](https://omarchy.org), built as an Omarchy shell plugin (`tahayvr.onboarding`). A welcome checklist gets you online and up to date and shows where every shortcut lives; an optional tutorial then teaches the keys by having you press them, while an overlay watches Hyprland and ticks each step off as you do it.

Work in progress. The welcome checklist (Wi-Fi, Omarchy update, keybindings) and the tutorial (Super key, menu, tiling, window controls, workspaces, clipboard, Super + K, theme, display, apps) work end to end. The login hook is built; its first-login test on a fresh user is still to do. See `AGENTS.md` for the contracts with Omarchy and Hyprland and the traps found along the way.

## Install for development

```bash
ln -s ~/dev/omarchy-onboarding ~/.config/omarchy/plugins/tahayvr.onboarding
omarchy-shell shell rescanPlugins
omarchy-shell shell setPluginEnabled tahayvr.onboarding true
```

The shell doesn't see edits through the symlink and can't hot-swap a plugin in use, so run `scripts/reload-shell.sh` after changing QML. Logic in `lib/` is tested with node and needs no reload.

## Use

```bash
bin/omarchy-onboarding                     # start or resume
bin/omarchy-onboarding --step theme        # replay one lesson
bin/omarchy-onboarding status              # where the flow is
bin/omarchy-onboarding steps               # step names
```

While developing, always pass `--state /tmp/onboarding-test.json` (or set `OMARCHY_ONBOARDING_STATE`) so the real state in `~/.local/state/omarchy/onboarding.json` is never touched. A test state also turns on `--dry-run`: theme changes, updates, firmware and app installs are logged instead of run, unless you add `--live`. With the overlay open, `tutorial`, `close-welcome`, `connect`, `update`, `keys`, `back`, `next`, `skip`, `pause`, `dismiss`, `do-it` and `info` drive the flow by hand. `--facts '{"online":false}'` or `--facts '{"update":"available"}'` shows the checklist's other states.

## Test

```bash
node tests/run.js              # engine, drills and recorded walkthroughs; no display needed
scripts/drive-drills.sh        # live: walks drills 4–7 and 9 through the real plugin
```

`drive-drills.sh` uses empty workspaces 7 and 8. It only acts on windows it opened, and it refuses to run while the screen is locked. Pass a path to save the walkthrough as a new fixture.
