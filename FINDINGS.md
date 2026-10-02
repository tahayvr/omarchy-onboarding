# M0 Findings

Research for the Omarchy first-boot onboarding (spec: "Omarchy First-Boot Onboarding — User Flow and Build Plan", rev 29).
As of 2026-10-01.

- **I** = installed package `omarchy 4.0.4-1` at `/usr/share/omarchy` (its `version` file wrongly says `4.0.0.alpha`; read the version from `omarchy version` / pacman).
- **Q** = upstream `quattro` at `upstream/omarchy`, HEAD `821ae58` (2026-10-02).
- **LIVE** = tested on this machine.

Environment: Hyprland 0.56.2 (Lua config), Quickshell 0.3.1, node 26 (via mise, for tests only), socat, jq. `fwupdmgr`, `fprintd`, `qmlls` are not installed.

## Verify items from the spec

| # | Spec item | Answer |
|---|---|---|
| 1 | First-run entry point | `default/hypr/autostart.lua:7` runs `omarchy-provision-first-run` on `hyprland.start`, right after `omarchy-launch-shell`. It is gated by `omarchy-done check first-run-user` and marks it only if every step succeeds; otherwise it retries next login. Log: `~/.local/state/omarchy/first-run.log`. The steps are hardcoded `run_first_run_step` calls, so there is no drop-in directory. Same in I and Q. |
| 2 | `omarchy-done` | `omarchy-done check|mark|ensure <name>`. Markers are empty files in `~/.local/state/omarchy/done/<name>`. `ensure` is an atomic create-once. Known names: `first-run-user`, `finalize-user`, `agent-setup-invitation`, `fingerprint-setup-invitation`, `voxtype-install-invitation`. |
| 3 | Where the owner form saves name and email | The console form (`install/provisioning/setup-form.sh`) runs from `omarchy-provision-owner.service` on tty1 before SDDM. The full name goes to the passwd GECOS field (`getent passwd $USER | cut -d: -f5`). Name and email go to global git config via `install/user/git.sh`, and nowhere else. Both may be empty, because the form lets the user skip them. The form also sets the timezone. |
| 4 | `setup-agent.hook` | This is a **post-update hook**, not a first-login toast. First-run copies it to `~/.config/omarchy/hooks/post-update.d/`, and it fires on the first `omarchy update`. It only fires when no agent is set and `omarchy-done ensure agent-setup-invitation` succeeds. There are two ways to suppress it: set an agent, or `omarchy-done mark agent-setup-invitation`. Fingerprint and voxtype invitations follow the same pattern. |
| 5 | Read the current default agent | `omarchy default agent` with no argument prints the first line of `~/.config/omarchy/defaults/agent`, or nothing if unset. |
| 6 | Update-available signal | The bar widget `omarchy.system-update` runs `omarchy-update-available` every 6 h (and at start). Exit code 0 means an update exists. To read it: run `omarchy update available` asynchronously (it is network-bound, using `checkupdates`). There is no state file. |
| 7 | How shell plugins load | Third-party plugins live in `~/.config/omarchy/plugins/<author.id>/manifest.json` (`schemaVersion`, `id`, `name`, `version`, `kinds`, `entryPoints`, `keepLoaded`). Install with `omarchy plugin add <git-url> --enable`, or copy the folder then run `omarchy-shell shell rescanPlugins` and `omarchy plugin enable <id>`. The host injects `shell`, `manifest` and `service`. `summon`/`hide`/`toggle` call the plugin's `open(payload)`/`close()`. The `omarchy.` id prefix is reserved for first-party plugins. Same in I and Q (`PluginRegistry.qml` identical). |
| 8 | Menu and Super + K layer events | **LIVE (I):** the menu fires `openlayer>>omarchy-menu` and `closelayer>>omarchy-menu`. Super + K opens the **same** `omarchy-menu` layer, in select mode. **Q (#13419):** the overlay stays mapped (parked 1x1 on the Bottom layer), so these events no longer fire on each open. Only the layer level changes, which is visible via `hyprctl -j layers`. |

## Corrections to the spec

1. **`hyprctl dispatch` takes Lua** on Hyprland 0.56 + Lua config. `hyprctl dispatch killactive` fails; use `hyprctl dispatch "hl.dsp.window.close()"`. Bindings show as dispatcher `__lua` in `hyprctl binds -j`, so verify them by `description`. Any "Do it for me" action must use the Lua form, or call the `omarchy-*` command a binding runs.
2. **There is no timezone notice** in first-run. First-run sends a welcome toast ("Learn Keybindings", which opens Super + K) and runs `wifi.sh`. `wifi.sh` waits up to 30 s for the network. If there is none, it sends a "Setup Wi-Fi" toast that opens the network panel. After connecting it sends "Update System". The spec's "welcome / Wi-Fi / timezone" should read "welcome / Wi-Fi / update".
3. **PR #12515 does not exist.** The `first-run-user` marker is in `bin/omarchy-provision-first-run:40-44`. PR #12415 (`omarchy setup welcome`) is still open, and #12521 adds a conflicting `omarchy-setup-welcome`.
4. **`omarchy network` is a command group, not a panel launcher.** The Wi-Fi UI is the shell panel `omarchy-shell shell toggle omarchy.network`. `nmtui` is not what Omarchy uses.
5. **`omarchy default agent <name>` also installs and launches the agent.** If the agent is missing, it opens a floating terminal and installs it with mise. Afterwards it execs `omarchy-agent`. Step 14 needs a "this opens a terminal" confirmation. To set the agent without launching it, the only option is writing `~/.config/omarchy/defaults/agent` ourselves (not recommended). Names (I): `pi omp opencode claude codex grok gemini openclaw hermes copilot crush cursor-agent muse`. Q adds `ori` and `agy`, and `gemini` becomes an alias of `agy`.
6. **Super + Shift + N opens the default editor** (`omarchy-launch-editor`). That is Neovim only when no editor is set; this machine opens Zed. Step 15 should say "your editor" and only teach LazyVim when it is `nvim`.
7. **Super + L toggles** the current workspace between dwindle and scrolling.
8. **Super + / scales up**; Super + Alt + / scales down. Super + Shift + / is Passwords.
9. **User overrides exist.** On this machine Super + Shift + F runs `flea --gui`, not Nautilus, and Super + Shift + C runs VS Code, not Calendar. Step 13 cards must read the live bindings by description, not hardcode apps.
10. **The panels are shell plugins, not TUIs.** Super + Ctrl + W/A/B/D/P toggle `omarchy.network`, `omarchy.audio`, `omarchy.bluetooth`, `omarchy.monitor` and `omarchy.power` (layer `omarchy-keyboard-panel`). They only open if the widget is in the bar. `omarchy menu summon style.theme` opens the image picker (layer `omarchy-image-selector`), not the menu.
11. **Firmware:** `omarchy-update-firmware` installs fwupd if missing, then refreshes and updates. There is no "firmware updates available" detector, and `fwupdmgr` is absent here. Step 12 should offer firmware as a plain "Check for firmware updates" action.
12. **FIDO2** has no hardware detector (the setup runs `fido2-token -L` after installing). **Fingerprint** has one: `omarchy hw fingerprint`, which uses the exit code. **Bluetooth:** `bluetoothctl list`, or `omarchy bluetooth power is-on`.

## Detection, verified

| Step | Signal | Status |
|---|---|---|
| 2 Internet | `nmcli networking connectivity` returns `full` | LIVE |
| 4 Menu | I: `openlayer`/`closelayer>>omarchy-menu`. Q: poll `hyprctl -j layers` for `omarchy-menu` on level 3 (method from upstream `test/acceptance.d/base-test.sh:87-93`) | LIVE on I; Q from source |
| 5 Launch | `openwindow>>ADDR,WS,CLASS,TITLE`. Terminal class `foot` (also `org.omarchy.*` TUIs; full regex in `default/hypr/apps/terminals.lua`). Browser class `chromium` (read the default via `omarchy default browser`) | LIVE for foot |
| 5 Focus | `activewindowv2>>ADDR` | LIVE |
| 6 Float / full / close | `changefloatingmode>>ADDR,1|0`, `fullscreen>>1|0` (**no address**: pair with the last `activewindowv2`), `closewindow>>ADDR` | LIVE (via Lua dispatchers) |
| 7 Workspaces | `workspacev2>>ID,NAME`, `movewindowv2>>ADDR,WSID,WSNAME` | In the 0.56.2 source; not yet tested live |
| 9 Super + K | Same layer as the menu. A process `omarchy-menu-select Keybindings` runs while it is open, **but it survives an external `hide`** (LIVE: a leftover process stayed alive), so a running process alone is not proof the overlay is open. Workaround: on `openlayer>>omarchy-menu`, check for a `omarchy-menu-select Keybindings` process **started within the last ~2 s** | LIVE |
| 10 Theme | `omarchy theme current` (pretty name); slug in `~/.local/state/omarchy/current/theme.name` | source |
| 11 Display | `hyprctl monitors -j` | — |
| 14 Agent | `omarchy default agent` (empty = unset) | source |
| 15 Dev | `git config --global user.email`; `~/.ssh/id_*.pub` | — |
| 16 Updates | `omarchy update available`, exit code 0 = updates (async) | source |

Every Hyprland event in the spec exists in 0.56.2: `openwindow`, `closewindow`, `activewindowv2`, `workspacev2`, `movewindowv2`, `changefloatingmode`, `fullscreen`, `openlayer`, `closelayer`.

## Shell integration facts

- **Process:** a single Quickshell process, `quickshell -n -p $OMARCHY_PATH/shell`, supervised by `omarchy-launch-shell`. Restart it with `omarchy restart shell`. Logs: `journalctl -t omarchy-shell`.
- **Reference overlay plugin:** `~/.config/omarchy/plugins/tahayvr.postcard`, kinds `overlay` + `bar-widget`, `keepLoaded: true`.
  - It uses `PanelWindow` on `WlrLayer.Overlay` with `keyboardFocus: OnDemand`. Hyprland only grants focus on first map, so it switches briefly to `Exclusive` to reclaim focus.
  - `close()` must be idempotent, and it should also call `shell.hide(id)` so `toggle` stays in sync. See its `AGENTS.md`.
- **Theming:** import `qs.Commons` and bind to `Color.*` (`foreground`, `background`, `accent`, `urgent`, `muted`, `Color.menu.*`) and `Style.*` (fonts, spacing, radius). These bindings update live when `omarchy theme set` pushes `shell applyTheme`.
- **IPC on I:** Quickshell `IpcHandler` only, reached via `omarchy-shell <target> <method> …` or `qs ipc -n -p /usr/share/omarchy/shell call …`.
- **IPC on Q (#13435):** adds a socket at `$XDG_RUNTIME_DIR/omarchy-shell-<hash>.sock`. Framing is `target\x1fmethod\x1fargs\x1e`. It is request/response only, with no events. Only `ShellIpc` handlers answer on it; whether a third-party plugin can register one is unconfirmed.
- **Menu visibility:** no IPC call exposes which menu, or whether any menu, is open (`omarchy.menu` only has `open`, `close`, `refresh`, `ping`). An upstream PR is needed to get this cleanly; until then, use the layer and process heuristics above.
- **Third-party facade:** a plugin can only `summon`/`hide`/`toggle`/`isOpen` its **own** id. To open other panels, the plugin runs `omarchy-shell shell toggle <id>` as a process.
- **Dev loop:** saving a file in a plugin hot-reloads it via `inotifywait -r` on `~/.config/omarchy/plugins`, but inotify does not follow a symlinked plugin dir, so a linked dev checkout needs `omarchy-shell shell rescanPlugins` after edits. A `keepLoaded` plugin needs `omarchy restart shell`.

## CLI integration

- `omarchy commands --json` returns `{ok, commands:[{route, binary, group, name, summary, args, aliases, hidden, requires_sudo, …}]}`. I lists 367 visible commands (440 with `--all`). Snapshot: scratchpad `commands.json`.
- **`omarchy onboarding` is free.** The dispatcher maps `omarchy onboarding …` to an executable `omarchy-onboarding` on the bin path, using the longest prefix. Metadata comes from header comments (`# omarchy:summary=`, `args=`, `examples=`). `omarchy commands --check` rejects a missing summary.
- **Themes:** 22 built-in themes. Each has `preview.png` (1800x1012), `preview-unlock.png` and `backgrounds/`. User themes in `~/.config/omarchy/themes` may lack a preview; there are 7 here and only 3 have one. Fallback order (as `omarchy-theme-switcher` does it): `preview.{png,jpg,jpeg,webp,gif,bmp}`, then the first image in `backgrounds/`. `omarchy theme set` accepts a pretty name or a slug, exits 1 on an unknown name, and holds a lock.
- **`omarchy update [-y]`:** needs a TTY and sudo. Launch it as `omarchy-launch-floating-terminal-with-presentation omarchy-update`. It takes a snapper snapshot (and continues without one if that fails), then migrations, then the post-update hooks. Log: `/tmp/omarchy-update.log`.

## Decisions taken (simplest option, per the ground rules)

- **Super + K detection:** use the layer event plus a "fresh `omarchy-menu-select Keybindings` process" heuristic, and keep the "I see it" fallback. Propose a `shell isPluginOpen` / menu-state IPC upstream.
- **Target I (4.0.4) first** for M1–M5, because it is what runs here. Overlay detection gets two versions: layer events (I) and a layer-level poll (Q). Revisit before M6.
- **First-run integration (M6):** add a `run_first_run_step` for onboarding in `omarchy-provision-first-run`. When onboarding ships, mark `agent-setup-invitation` and skip `welcome.sh` and `wifi.sh` behind a single flag.
- **Step 1 prefill:** read the name from GECOS, falling back to `git config --global user.name`; read the email from `git config --global user.email`.

## Architecture (decided Oct 2): a Quickshell plugin, no Rust

M1 and M2 were first built as a Rust daemon plus CLI. They were rewritten as a pure Omarchy shell plugin before M3, for these reasons:
- **Omarchy ships no compiled code** (only bash and QML). A Rust binary would add a toolchain and build step to Omarchy's packaging, which works against the goal of shipping onboarding with Omarchy.
- **The shell already provides everything the daemon did:**
  - Hyprland events: `Connections { target: Hyprland; function onRawEvent(e) }`, giving `e.name` and `e.data`.
  - Commands: `Process`.
  - The state file: `FileView` with `atomicWrites`.
  - Polling: `Timer`.
- **One process, not two.** No socket or message protocol is needed between a daemon and the overlay.
- **Testing follows `tahayvr.postcard`.** Logic lives in `.pragma library` JS files under `lib/`, run by `node tests/run.js` in a bare VM context. Omarchy itself also has QtTest `tst_*.qml` tests, which M3 can use for the view.

Layout:
- `manifest.json`: plugin `tahayvr.onboarding`, kind `overlay`. The `omarchy.` prefix is reserved for first-party plugins.
- `Overlay.qml`: hosts the flow. It loads `steps.json` and the state file, runs the current step's drill against Hyprland events, and saves each change.
- `lib/Engine.js`: the state machine.
- `lib/Drills.js`: the event parser, drill trackers, drill walker and probe parsers.
- `bin/omarchy-onboarding`: the CLI. It summons the plugin via `omarchy-shell`, reads the state with `jq` for `status`, and guards `reset`. It already carries the `# omarchy:` headers the dispatcher needs.
- `bin/onboarding-facts`, `bin/onboarding-keybindings-open`: probes the overlay runs.
- `scripts/drive-drills.sh`: the live walkthrough.

The plugin's IPC surface (`omarchy-shell shell call tahayvr.onboarding <fn> <arg>`): `next`, `skip`, `pause`, `dismiss`, `track` (`mac` or `mac:code`), `info`. The summon payload takes `state`, `step`, `onlySkipped` and `record`. JSON sent through the `omarchy-shell` CLI must not contain spaces (it splits on them), so the CLI escapes them as `\u0020`.

Dev install: `ln -s ~/dev/omarchy-onboarding ~/.config/omarchy/plugins/tahayvr.onboarding`, then `omarchy-shell shell rescanPlugins` and `omarchy-shell shell setPluginEnabled tahayvr.onboarding true`. `omarchy plugin enable` has no `--yes`.

## Flow decisions (M1)

- **Four tracks, not three.** `new-to-linux`, `mac`, `windows`, `knows-linux`. The welcome screen still shows three choices; "Coming from Mac or Windows" asks which one, because step 3's copy differs ("where ⌘ is" vs "the Windows key").
- **A fifth outcome, `deferred`.** The spec lists done, skipped, auto-skipped and failed. "Needs internet, stays pending" is stored as `deferred` (reason `needs online`). The finish screen lists deferred and failed steps.
- **Unknown facts.** A fact detection hasn't checked is `null`:
  - `skip_if` only skips on a confirmed `true`, so an unknown connection still shows the internet step.
  - `show_if` needs a confirmed `true`, so personal setup stays hidden unless the deferred owner setup is proven.
  - `needs` only defers on a confirmed `false`.
- **Rules are re-checked on resume.** Reopening at the internet step after Ethernet came up skips it automatically.
- **Welcome and finish are never skipped by rules.** `validateManifest` enforces this, and an "only what I skipped" re-run still stops at both.
- **`--step` ignores rules** (the user asked for that lesson by name). It records the result but leaves the flow's current step and status alone.
- **Corrupt or newer-version state.** The overlay refuses it and shows the error. At login (M6) it should be moved aside to `onboarding.json.corrupt-<ts>` and onboarding started fresh.
- **Reset guard.** `reset` against the real state file requires `--yes`.
- **Log location.** The log sits next to the state file (`onboarding.json` → `onboarding.log`), capped at 2,000 lines, and is mirrored to `journalctl -t omarchy-shell`.

## Detection findings (M2)

- **Super + J (toggle split) sends no event.** In Hyprland 0.56.2 `togglesplit` changes the dwindle tree without posting to socket2 (`src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.cpp:679`). The tiling drill polls `hyprctl -j clients` every 400 ms. It ticks "split" when the terminal and browser go from side by side to stacked, or back.
- **Super + K vs menu, LIVE.** On each `openlayer>>omarchy-menu`, the overlay holds the event and runs `bin/onboarding-keybindings-open`. That probe passes when a `omarchy-menu-select Keybindings` process started within the last 2 s (`ps -o etimes`). Events queue behind the probe, so its answer always reaches the drills first. Tested live: the plain menu ticked only step 4, and Super + K ticked only step 9.
- **A new window's first focus doesn't count.** Hyprland focuses a window as it opens, so the tiling drill ignores the first `activewindowv2` for a just-opened window. Only focus moving between the terminal and the browser ticks "focus".
- **The drills are forgiving.** Step 6 accepts float, full screen and close on any window, not just the terminal or browser. Step 7 accepts any workspace switch and any move.
- **Drill windows.** Closing the drill terminal or browser un-ticks only that window's sub-task (spec edge case).
- **Browser classes.** The default browser comes from `omarchy default browser`, plus a list of the common browser window classes. Web apps (`chrome-<host>__…`) don't count.
- **Owner setup detection.** `owner-setup-deferred` is true when `/var/log/omarchy-provision-owner.log` exists. UNVERIFIED that the file survives provisioning cleanup; test in the M6 VM.
- **Fixtures.** Recordings are JSON lines of observations: raw event lines, keybindings probe results, window positions. Both live walkthroughs replay in `tests/run.js`:
  - `walkthrough-4.0.4.jsonl` was read from socket2 directly.
  - `walkthrough-plugin-4.0.4.jsonl` was recorded by the plugin through Quickshell.
- **M2 done, LIVE through the plugin (2026-10-02).** `scripts/drive-drills.sh` opened the real overlay on a throwaway state, picked a track and walked drills 4–7 and 9. Each drill ticked every sub-task and completed its own step, until the flow reached the theme step by itself.
- **Virtual keyboards don't trigger binds.** Keys sent with `wtype` (e.g. Super + Space) never fire Hyprland bindings; they go to the focused window as plain keys. The driver therefore runs what each binding runs: the `omarchy-*` command or the Lua dispatcher. Drill detection only reads compositor events, so it is tested end to end either way.
- **A locked session blocks window focus.** While Omarchy's lock screen is up, `hl.dsp.focus` returns `ok` but focus doesn't move. logind's `LockedHint` stays `no`; the reliable check is `omarchy-shell lock isLocked` (do not pass `-q`, which hides the answer). For onboarding: if the lock engages mid-drill, the drill should just wait, since events stop and nothing ticks falsely.
- **Close by address.** `hl.dsp.window.close({ window = 'address:0x…' })` closes a window without focusing it. Never kill a test browser by PID: Chromium windows share one process with the user's other browser windows.

## Overlay UI (M3)

- **Two layers, never both.**
  - `omarchy-onboarding`: a centered card over a dimmed desktop, with keyboard focus `Exclusive`. Used for welcome, the Super key, the pause dialog and the later steps.
  - `omarchy-onboarding-coach`: a corner card for the drills, with keyboard focus `None`, so Super shortcuts reach Hyprland. The clipboard step switches it to `OnDemand`, so its field can be clicked.
- **Step 3 catches a bare Super press.** Nothing in Omarchy binds Super alone, so with `Exclusive` focus the press reaches the overlay as `Qt.Key_Super_L`. LIVE-tested.
- **Idle hints, LIVE.** At 20 s without progress the key caps grow; at 40 s "Do it for me" appears. Any tick resets the timer.
- **"Do it for me", LIVE.** It walked drills 5–9 to the theme step with no key presses. It acts only on the drill's own windows (the tiling drill's terminal and browser, by address), and skips when it doesn't know them. For step 8 it puts the sample line on the clipboard with `wl-copy`, replacing whatever was there.
- **Launchers don't exit.** `omarchy-launch-terminal` execs `setsid` without forking, so it lives as long as the terminal. Waiting on it stalled the runner. "Do it for me" commands now run detached, with a timed gap between them.
- **Theme restyle, LIVE.** With the overlay open, `omarchy theme set "Tokyo Night"` restyled it immediately (accent, borders, text, background), with no reload. Every colour binds to `qs.Commons` `Color.*` / `Style.*`.
- **Readable secondary text.** `Color.muted` is nearly invisible on Matte Black's background. Secondary text uses the foreground colour at 62% opacity instead.
- **State-read race (fixed).** Reading the state with `FileView` right after changing its path could return empty after a shell restart. The overlay then started fresh and saved over real progress. State and log are now read by `bin/onboarding-read` as a process: it exits 3 for "no file", and any other failure stops the overlay. A fresh state is only written when the file truly doesn't exist, and the log is appended to rather than replaced. Re-tested three times after shell restarts, resuming correctly each time.
- **Dev loop.** The shell's hot reload can't replace a plugin type still in use, and it doesn't see edits through the symlinked checkout. After QML changes run `scripts/reload-shell.sh` (restarts the shell and waits for it). JS-only logic is tested with node and needs no reload.
- **Driving the UI in tests.** `wtype` keys reach the overlay when it has keyboard focus: Tab, Space, Return, Escape, and `-k Super_L` for step 3. `wtype -M logo` only changes the modifier state and is not a key press. Only type while the centered layer is up, or keys land in another window.
- **Not tested with real keys yet.** Pasting with Super + V into the step 8 field. Omarchy's universal paste sends Ctrl + V (Shift + Insert after a terminal) to the focused surface, layer surfaces included (`default/hypr/bindings/clipboard.lua`), so it should work, but it needs a physical click and key press to confirm.

## Action steps (M4)

All six were tested live on 2026-10-02:

| Step | How it's done | Result |
|---|---|---|
| 2 Internet | Polls `nmcli networking connectivity` every 2 s and completes itself once online. Opening the network panel ticks when `openlayer>>omarchy-keyboard-panel` fires. "Do it for me" toggles `omarchy.network`. | Pinned offline, it completed within 2 s of seeing the real connection |
| 10 Theme | A grid from `bin/onboarding-themes` (29 themes, all with previews). Arrows move, and Enter or Apply runs `omarchy theme set <slug>`, which is the explicit confirmation. "Keep current" counts. | A real Enter applied the current theme; the restyle was verified in M3 |
| 11 Display | Polls `hyprctl -j monitors` and `hyprctl hyprsunset temperature` each second. A scale change ticks "scale"; any change from the first temperature reading ticks "night light". "Looks right" completes. | "Do it for me" scaled up and back and toggled the night light on and off; scale 1.6 and 6500 K restored |
| 12 Hardware | Items from detection: Sound (`pw-play` left/right), Bluetooth (adapter present), Fingerprint (`omarchy hw fingerprint`), Firmware (always offered). Each is done or skipped; Continue waits for all. | Bluetooth panel opened; firmware asked, then only logged in a dry run |
| 13 Apps | `bin/onboarding-apps` reads the live bindings (your rebinds included) and their commands. "Try it" dispatches the binding's command, and asks first when the launcher would install the app. | File manager opened `flea`; Music asked before installing |
| 16 Updates | `omarchy update available` (exit 0 means available). "Update now" asks first, then runs `omarchy-update` in the presentation terminal, whose process exits when the terminal closes, which completes the step. "Later" also completes. | The real check said "up to date"; the dry-run update moved to finish |

- **Missing commands, LIVE.** Steps declare `requires` (omarchy routes or programs). `bin/onboarding-check` checks them all at startup against `omarchy commands --json --all` and `command -v`. A step whose requirement is missing is auto-skipped, with the log line `auto skipped theme: command 'omarchy theme set' is missing`.
- **Corner or centered.** Steps that open a shell panel or teach keys use the corner card, so the panel or Hyprland gets the keyboard: internet, display, hardware, apps, updates. The theme grid and all confirmations are centered and take the keyboard.
- **App bindings with commands.** `omarchy-menu-keybindings` has no flag to print records with their commands. `bin/onboarding-apps` loads the script's functions without running its menu and calls `output_binding_records`. This is fragile against upstream changes: on failure the app list is empty and the card points to Super + K. Proposal: an upstream `--records` (or `--json`) flag.
- **Install-on-first-use.** `omarchy-launch-spotify`, `omarchy-launch-1password` and `omarchy-launch-signal` install the app in a terminal when it's missing. "Try it" asks first for those.
- **Facts must be read when used.** The hardware list was built when the step was entered, which on resume came before the facts probe returned, so an absent fingerprint reader showed. It is now a binding on the facts.
- **Incident: a firmware run started during testing.** A test state was opened without `--dry-run`. My scripted "yes" to the firmware confirmation then launched the real `omarchy-update-firmware`. It stopped at its `sudo pacman -S fwupd` password prompt. I closed the terminal and the sudo prompt exited. Nothing was installed (`pacman -Q fwupd` absent, no pacman.log entry). The fix makes it impossible by default: `--state` (or `OMARCHY_ONBOARDING_STATE`) now implies `--dry-run`, and a real run against a test state needs `--live`.
- **Scripting the overlay.** `shell call` passes one string, so `applyTheme`, `hardwareAct` and `tryApp` accept a slug, id or label. `hardwareDone`, `hardwareSkip`, `askUpdate`, `answerConfirm` and `primaryAction` are callable too.

## Developer track (M5)

- **Step 14, choose an agent.** The list comes from the Omarchy menu's `setup.default.agent.*` entries (`bin/onboarding-agents`, 13 agents), so new agents appear without a code change. Choosing one asks first, then runs `omarchy default agent <name>` detached: it installs the agent if needed (in a terminal) and opens it. The step completes when `omarchy default agent` reads back the new name, polled every 1.5 s. Keeping the current agent counts as done. One-line descriptions are given only where they can be stated accurately; the rest show the name.
- **Tested, 2026-10-02.** In the overlay, skip and choose (in dry run) both worked. From the shell, a real `omarchy default agent opencode` (your current agent, so no change) rewrote the setting and opened the agent window (class `org.omarchy.agent`), which I then closed. The overlay never switched your agent for real, because that would install software.
- **Step 15, developer basics.** Git name and email are prefilled from global git config (falling back to the owner form's GECOS name). "Keep these" confirms unchanged values without writing; changed values run `git config --global user.name/user.email`. The SSH key is `ssh-keygen -t ed25519 -C <email> -f ~/.ssh/id_ed25519 -N ""`, behind a confirmation that says it has no passphrase. A wrapper creates `~/.ssh` with mode 700 first (ssh-keygen won't create it) and closes stdin so an existing key is never overwritten. An existing `id_*.pub` is shown selectable (Super + C copies it) with a Copy button.
- **Tested against temp locations.** The exact git commands ran with `GIT_CONFIG_GLOBAL` pointed at a temp file, and the key wrapper with a temp home without `.ssh`: modes 700/600, and a second run refuses to overwrite. In the overlay, the git form was driven by keyboard in dry run: "Keep these" ticked without commands; an edited name logged both commands. Your `~/.config/git/config` checksum and `~/.ssh` were unchanged.
- **The editor Super + Shift + N really opens.** `omarchy-launch-editor` falls back to `nvim` when the configured editor isn't an installed command. Here `omarchy default editor` says `zeditor`, but Zed is installed as `~/.local/bin/zed`, so Super + Shift + N opens Neovim. `bin/onboarding-devinfo` applies the same fallback, so the LazyVim tip appears exactly when Neovim opens. Upstream note: `omarchy-default-editor zed` stores `zeditor`, which fails for Zed installed as `zed`.
- **Not exercised live:** showing and copying an existing SSH public key, since this machine has no `id_*.pub` and I won't create one in your `~/.ssh`. The read path is the same `bin/onboarding-read` used for the state file.
