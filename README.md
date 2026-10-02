# Omarchy onboarding

First-boot onboarding for [Omarchy](https://omarchy.org), built as an Omarchy shell plugin (`tahayvr.onboarding`). It teaches the keys by having you press them: an overlay watches Hyprland and ticks each step off as you do it.

Work in progress. Milestones M0–M2 are done: the step flow, state file and drill detection for steps 4–7 and 9. The overlay UI is M3. See `FINDINGS.md` for what was verified on Omarchy 4.0.4 and why things are built the way they are.

## Install for development

```bash
ln -s ~/dev/omarchy-onboarding ~/.config/omarchy/plugins/tahayvr.onboarding
omarchy-shell shell rescanPlugins
omarchy-shell shell setPluginEnabled tahayvr.onboarding true
```

The shell doesn't watch files through the symlink, so run `omarchy-shell shell rescanPlugins` after editing.

## Use

```bash
bin/omarchy-onboarding                     # start or resume
bin/omarchy-onboarding --step theme        # replay one lesson
bin/omarchy-onboarding status              # where the flow is
bin/omarchy-onboarding steps               # step names
```

While developing, always pass `--state /tmp/onboarding-test.json` (or set `OMARCHY_ONBOARDING_STATE`) so the real state in `~/.local/state/omarchy/onboarding.json` is never touched. With the overlay open, `next`, `skip`, `pause`, `dismiss`, `info` and `track <track> [--code]` drive the flow by hand.

## Test

```bash
node tests/run.js              # engine, drills and recorded walkthroughs; no display needed
scripts/drive-drills.sh        # live: walks drills 4–7 and 9 through the real plugin
```

`drive-drills.sh` uses empty workspaces 7 and 8. It only acts on windows it opened, and it refuses to run while the screen is locked. Pass a path to save the walkthrough as a new fixture.
