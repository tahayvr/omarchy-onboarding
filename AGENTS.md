# AGENTS.md

Things that cost time to find out and can't be read off the source. Users
want `README.md`; the flow itself is specced in the plan doc. This file covers
the traps, the contracts with Omarchy, Hyprland and the shell, and how to run
things without touching the real system.

Onboarding is an Omarchy shell plugin (`tahayvr.onboarding`, kind `overlay`)
inside the long-lived Quickshell process. There is no daemon and no compiled
code, because Omarchy ships only bash and QML. Built against Omarchy 4.0.4
(Hyprland 0.56.2 with a Lua config, Quickshell 0.3.1). The `version` file in
`/usr/share/omarchy` wrongly says `4.0.0.alpha`, so read the version from
`omarchy version`. Upstream `quattro` is cloned at `upstream/omarchy` (gitignored).

## Layout

- `Overlay.qml` does the wiring. It loads `steps.json` and the state, listens to
  Hyprland, runs probes and actions as processes, saves each change, and owns
  the two windows.
- `ui/` holds the views.
- `lib/Engine.js` is the state machine.
- `lib/Drills.js` has the event parser, the drill trackers and the probe
  parsers.
- `lib/Ui.js` covers the checklist rows, card placement, key caps, idle hints
  and "Do it for me" plans.
- `lib/*.js` are `.pragma library` files that `node tests/run.js` loads into a
  bare VM context, so they stay plain ES5 with no QML imports. Put logic there,
  not in QML, so it can be tested.
- `steps.json` holds every step's copy, keys, sub-tasks and `requires`. Copy
  changes never need code.
- `bin/omarchy-onboarding` is the CLI. The `onboarding-*` scripts are probes
  the overlay runs.
- `omi/` is Omi, the Omarchy mascot, copied from Meet Omi
  (github.com/tahayvr/meet-omi) by `scripts/sync-omi.sh`; `omi/SOURCE` says
  from which commit. Don't edit it here: fix Meet Omi and sync. New Omi mode
  or reaction ideas go in Meet Omi's `docs/ideas.md`. Which mode Omi shows is
  decided in `lib/Ui.js` (`welcomeOmi`).
- `integration/omarchy-first-run.patch` is the upstream change against
  `quattro`. It adds `omarchy-onboarding login` to `autostart.lua`, and skips
  `welcome.sh` and `wifi.sh` when onboarding is installed. It keeps the agent
  hook, since onboarding doesn't cover agents. Check it with
  `git -C upstream/omarchy apply --check`.

## Safety

- **Never touch the real state** in `~/.local/state/omarchy/onboarding.json`
  or the `onboarding` marker in `~/.local/state/omarchy/done/`. Always pass
  `--state /tmp/…` or set `OMARCHY_ONBOARDING_STATE`.
- **`--state` implies `--dry-run`.** In dry-run, system changes such as updates
  and installs are logged instead of run. `--live` overrides this, so don't use
  it. This rule exists because a scripted "yes" against a non-dry test state
  once launched the real `omarchy-update-firmware`, which stopped at sudo.
- **Never run these for real:** `omarchy update`, Wi-Fi changes, global git
  config, writes to `~/.ssh`.
  - Reversible actions are fine: panels, menus, launching apps, and changing
    the theme, as long as you switch it back.
  - Changing the theme also changes the GTK icon theme. Restore it with
    `omarchy-theme-set-gnome`.
- **System actions need an explicit confirmation in the UI** (`askConfirm`).
- **First-login tests** run in a separate user (`scripts/test-user.sh`) or a VM,
  never on the main account.
- **The user may have onboarding open.** Check before running
  `scripts/reload-shell.sh`, which restarts their shell, and before driving
  keys.

## Shell contract

- The host calls `open(payload)` on summon and `close()` on hide. `close()`
  must be idempotent and must also call `shell.hide(id)`, or `toggle` desyncs.
  The plugin may only summon or hide its own id. It opens other panels by
  running `omarchy-shell shell toggle omarchy.network` (and similar) as a
  process.
- `omarchy-shell shell call tahayvr.onboarding <fn> <arg>` passes exactly one
  string, and the CLI splits on spaces. JSON sent this way needs ` `
  instead of spaces. Functions that take a choice accept a plain id.
- The theme comes from `qs.Commons`: `Color.*` and `Style.*` update live when
  `omarchy theme set` runs. Bind every colour to them. `Color.muted` is nearly
  invisible on Matte Black, so secondary text uses the foreground colour at
  62% opacity.
- **Dev loop:** the shell doesn't see edits through the symlinked checkout and
  can't hot-swap a plugin type in use. After QML changes, run
  `scripts/reload-shell.sh`. JS changes only need `node tests/run.js`. Logs go
  to `journalctl -t omarchy-shell` and to the log next to the state file.
- **Reading files:** don't read the state or log with `FileView`. Right after a
  path change or a shell restart it can return empty, and the overlay once
  started fresh and saved over real progress. Read through `bin/onboarding-read`
  instead, which exits 3 for a missing file and treats any other failure as
  fatal. `FileView` with `atomicWrites` is used for writing only.
- **Launch commands detached.** Commands like `omarchy-launch-terminal` exec
  `setsid` without forking and live as long as the window, so waiting on them
  stalls. Use `Quickshell.execDetached`.

## Windows and layers

- There are two `PanelWindow`s, and never both at once:
  - `omarchy-onboarding` is the centered card over a scrim. It has `Exclusive`
    keyboard focus and is used for welcome, the Super key, finish, pause and
    confirm.
  - `omarchy-onboarding-coach` is the corner card. Its keyboard focus is `None`,
    so Super binds reach Hyprland. The clipboard step switches it to `OnDemand`
    so its field can be clicked. It uses `ExclusionMode.Normal`, so it sits
    below the bar.
- **Keeping the corner card above dimming.** Menus and pickers dim everything
  beneath them. The fix is a Hyprland layer rule set at runtime:
  `hl.layer_rule({ name = "omarchy-onboarding-coach", …, order = -10 })`,
  applied through `hyprctl eval`. Each level is drawn sorted by `order`
  descending, so a negative order draws last, on top. Named rules replace each
  other, so re-applying the rule is safe.
- **Keys for the corner card have to be Hyprland binds**, since it never has
  the keyboard. Ctrl + / (skip) is added with `hl.bind` through
  `bin/onboarding-skip-bind` while a tutorial step is up, removed after, and
  re-added on `configreloaded`. It's left alone when the user has bound that
  combo, and then the Skip button shows no key.
- **Card placement** is `Ui.coachPlacement` and depends on the step, its ticked
  sub-tasks and the bar position from `onboarding-facts`.
- A bare Super press reaches the centered card as `Qt.Key_Super_L`, because
  nothing in Omarchy binds Super alone.

## Hyprland

- **`hyprctl dispatch` takes Lua**, so a command like
  `hyprctl dispatch killactive` fails. Use, for example,
  `hl.dsp.window.close({ window = 'address:0x…' })`. Use `hyprctl eval` for
  config at runtime.
  - Binds show as `__lua` in `hyprctl binds -j`, so match them by description.
  - "Do it for me" uses the Lua form, or the `omarchy-*` command behind a bind.
- **Events** come from Quickshell's `Hyprland.rawEvent` (`name`, `data`).
  - `openwindow>>ADDR,WS,CLASS,TITLE`
  - `closewindow>>ADDR`
  - `activewindowv2>>ADDR`
  - `changefloatingmode>>ADDR,0|1`
  - `fullscreen>>0|1`, which has no address. Pair it with the last
    `activewindowv2`.
  - `workspacev2>>ID,NAME`
  - `movewindowv2>>ADDR,WSID,WSNAME`
  - `openlayer` / `closelayer>>NAMESPACE`
- **`togglesplit` (Super + J) sends no event.** The tiling drill polls
  `hyprctl -j clients` and ticks when the two windows go from side by side to
  stacked, or back.
- **A new window's first focus doesn't count.** Hyprland focuses windows as
  they open, so only focus moving between the drill windows ticks.
- **Onboarding cleans up after itself.** The clipboard terminal has its own
  class (`Ui.SAMPLE_APP_ID`) and closes when that step is over. The class
  must stay under `org.omarchy.`: Omarchy tags only known classes as
  terminals, and Super + C / V copy and paste in a terminal only when it's
  tagged. The tiling drill's terminal and browser close, by address, when
  onboarding closes (finish, quit, pause, or a replay ending), and focus
  returns to the workspace the tutorial began on. Never close a window
  onboarding didn't open or ask for.
- **Close test windows by address**, never by PID. Chromium windows share one
  process with the user's own browser.
- **Window classes.** The terminal is `foot` (the full regex is in
  `default/hypr/apps/terminals.lua`). The browser comes from
  `omarchy default browser` plus the common browser classes. Web apps
  (`chrome-<host>__…`) don't count as the browser.

## Omarchy facts the steps rely on

- **Menu and Super + K** both open the `omarchy-menu` layer. On 4.0.4 that
  fires `openlayer` / `closelayer>>omarchy-menu`. Super + K is told apart by a
  `omarchy-menu-select Keybindings` process that started within the last 2 s
  (`bin/onboarding-keybindings-open`). A running process alone isn't proof,
  because it survives an external hide. Events queue behind the probe.
  - On `quattro` (#13419) these overlays stay mapped, so the per-open layer
    events stop. Poll `hyprctl -j layers` for the layer level instead.
  - No IPC call exposes menu state.
- **Theme picker:** Super + Ctrl + Shift + Space runs
  `omarchy-menu toggle theme`. That opens `omarchy-theme-switcher`, then the
  image picker (layer `omarchy-image-selector`), then `omarchy-theme-set`. The
  step compares `omarchy theme current` against its value at the step's start.
  Esc in the picker changes nothing.
- **Network:**
  - Connectivity is `nmcli networking connectivity`, where `full` means online.
  - The SSID comes from `nmcli -t -f active,ssid device wifi`.
  - The Wi-Fi UI is the shell panel `omarchy.network` (Super + Ctrl + W).
    `omarchy network` is a command group, not a panel launcher.
  - Panels only open if their widget is in the bar.
- **Updates:**
  - `omarchy update available` exits 0 when an update exists. It is
    network-bound and has no state file, so run it async.
  - `omarchy update` needs a TTY and sudo, and takes a snapper snapshot first.
    Launch it with
    `omarchy-launch-floating-terminal-with-presentation omarchy-update`.
- **App bindings:** `omarchy-menu-keybindings` can't print records with their
  commands. `bin/onboarding-apps` sources its functions and calls
  `output_binding_records`, which is fragile. On failure the app list is empty.
  Some launchers (Spotify, 1Password, Signal) install the app on first use, so
  ask before trying them.
- **Bindings differ per machine.** Read them live rather than hardcoding apps.
  - Super + / scales up and Super + Alt + / scales down.
  - Super + L toggles dwindle and scrolling.
- **First run:** `autostart.lua` runs `omarchy-provision-first-run`, gated by
  `omarchy-done check first-run-user`.
  - Markers are empty files in `~/.local/state/omarchy/done/`.
  - First-run sends the welcome and Wi-Fi/update notices. It also installs the
    post-update hooks, and `setup-agent.hook` is the default-agent prompt.
- **Missing commands:** `bin/onboarding-check` checks every `requires` against
  `omarchy commands --json --all` and `command -v`. A missing one auto-skips
  its step with a log line.

## Testing

- `node tests/run.js` covers the engine, the drills and the UI logic. It also
  replays the recorded walkthroughs in `tests/fixtures/*.jsonl`: raw event
  lines, probe results and window positions.
- `scripts/drive-drills.sh` walks the tutorial live through the real plugin, on
  empty workspaces 7 and 8. Pass it a path to record a new fixture.
- **Check the lock first:** run `omarchy-shell lock isLocked`, without `-q`,
  which hides the answer. While locked, `hl.dsp.focus` returns `ok` but
  nothing moves.
- **`wtype` doesn't trigger Hyprland binds.** Keys go only to the focused
  surface. Drive a bind by running what it runs.
  - `wtype -M logo` changes modifier state only and isn't a key press. Use
    `-k Super_L`.
  - Only type while the centered card has focus, or the keys land in another
    window.
- **`--facts`** pins detection for the welcome page, for example
  `'{"online":false}'` or `'{"update":"available"}'`.
- Clean up after live tests: close test terminals by address, and restore the
  theme.
- **`pkill -f`:** use an anchored pattern, or it matches your own shell.
