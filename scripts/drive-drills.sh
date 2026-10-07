#!/bin/bash
# Walks the whole tutorial through the real plugin on the live desktop, by
# running what each binding runs: the "Learn the keys" drills (menu to
# shortcuts, the clipboard step included), each of which must complete its
# step by itself, then Back and forward again, and Do them now from the
# finish screen through the skipped steps. The run passes when the flow completes. The clipboard is restored
# afterwards.
#
#   scripts/drive-drills.sh [recording.jsonl]
#
# Needs the plugin enabled (see README). Uses a throwaway state file.
#
# Safe to run on a desktop in use:
# - refuses to run while the session is locked (the lock holds keyboard focus)
# - works on two empty workspaces (default 7 and 8), never touching other windows
# - checks the focused window is one it opened before float, full screen, close or move
# - closes its own windows by address and returns to the starting workspace
#
# Virtual keyboards (wtype) don't trigger Hyprland binds, so keys can't be sent;
# the drills see the same compositor events either way.

set -euo pipefail

WS_A=${WS_A:-7}
WS_B=${WS_B:-8}
OUT=${1:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
STATE="$WORK/state.json"
CLI=("$ROOT/bin/omarchy-onboarding" --state "$STATE")
SAMPLE="Omarchy copies and pastes the same way everywhere" # Ui.CLIPBOARD_SAMPLE
SELECTOR='^/bin/bash /usr/share/omarchy/bin/omarchy-menu-select Keybindings'

terminal="" browser="" sample_terminal=""
before_all=$(hyprctl -j clients | jq -c '[.[].address]')
start_ws=$(hyprctl -j activeworkspace | jq -r .id)

say() { printf '\033[1m> %s\033[0m\n' "$*" >&2; }
dispatch() { hyprctl dispatch "$1" >/dev/null; }
active() { hyprctl -j activewindow | jq -r '.address // ""'; }
ws_windows() { hyprctl -j clients | jq --arg ws "$1" '[.[] | select(.workspace.name == $ws)] | length'; }
current_step() { "${CLI[@]}" info | jq -r '.step // ""'; }
info() { "${CLI[@]}" info | jq -r "$1"; }

require_active() {
  if [[ $(active) != "$1" ]]; then
    echo "abort: expected $2 ($1) to be focused, found $(active)" >&2
    exit 1
  fi
}

# Waits for the flow to reach STEP, which means the previous drill completed.
wait_step() {
  for _ in $(seq 1 25); do
    [[ $(current_step) == "$1" ]] && return
    sleep 0.2
  done
  echo "fail: the flow did not reach '$1'; still on '$(current_step)'" >&2
  "${CLI[@]}" info >&2
  exit 1
}

# Waits for a window of CLASS (a jq regex) to appear on a workspace named WS
# (a name, or a jq regex starting with ^) and prints its address.
wait_window() {
  local class=$1 ws=$2 before=$3
  for _ in $(seq 1 50); do
    local addr
    addr=$(hyprctl -j clients | jq -r --arg c "$class" --arg ws "$ws" --argjson before "$before" \
      '[.[] | select((.class | test($c)) and (if ($ws | startswith("^")) then (.workspace.name | test($ws)) else .workspace.name == $ws end) and ((.address) as $a | $before | index($a) | not))][0].address // ""')
    if [[ -n $addr ]]; then
      echo "$addr"
      return
    fi
    sleep 0.2
  done
  echo "abort: no $class window appeared on workspace $ws" >&2
  exit 1
}

# Closes one of our own windows by address, without needing focus.
close_own() {
  local addr=$1
  [[ -z $addr ]] && return
  hyprctl -j clients | jq -e --arg a "$addr" 'any(.[]; .address == $a)' >/dev/null || return 0
  dispatch "hl.dsp.window.close({ window = 'address:$addr' })"
}

cleanup() {
  set +e
  omarchy-shell shell hide omarchy.menu >/dev/null 2>&1
  pkill -f "$SELECTOR"
  "${CLI[@]}" dismiss >/dev/null 2>&1
  omarchy-shell shell hide tahayvr.onboarding >/dev/null 2>&1
  close_own "$browser"
  close_own "$terminal"
  close_own "$sample_terminal"
  # The clipboard step opens its own terminal; close anything new on the test workspaces.
  for addr in $(hyprctl -j clients | jq -r --arg a "$WS_A" --arg b "$WS_B" --argjson before "$before_all" \
      '.[] | select((.workspace.name == $a or .workspace.name == $b) and ((.address) as $x | $before | index($x) | not)) | .address'); do
    close_own "$addr"
  done
  dispatch "hl.dsp.focus({ workspace = '$start_ws' })"
  echo "--- log"
  cat "$WORK/state.log" 2>/dev/null
  rm -rf "$WORK"
}

if [[ $(omarchy-shell lock isLocked 2>/dev/null) == true ]]; then
  echo "abort: the session is locked; unlock it and run again" >&2
  exit 1
fi
for ws in "$WS_A" "$WS_B"; do
  if [[ $(ws_windows "$ws") != 0 ]]; then
    echo "abort: workspace $ws is not empty; set WS_A/WS_B to empty workspaces" >&2
    exit 1
  fi
done
trap cleanup EXIT

record=()
[[ -n $OUT ]] && record=(--record "$OUT")
"${CLI[@]}" "${record[@]}" run
wait_step welcome
"${CLI[@]}" tutorial >/dev/null # "Teach me" on the welcome page
wait_step super-key
"${CLI[@]}" next >/dev/null # super-key needs the overlay's key catcher (M3)
wait_step menu

say "Back (Ctrl + ,) to the Super key step, then forward again"
"${CLI[@]}" previous >/dev/null
wait_step super-key
"${CLI[@]}" next >/dev/null
wait_step menu

say "Step 4: Super + Space, then close"
omarchy-menu toggle; sleep 1.2
omarchy-menu toggle
wait_step tiling

dispatch "hl.dsp.focus({ workspace = '$WS_A' })"; sleep 0.5

say "Step 5: Super + Return, Super + Shift + Return, Super + J, Super + Arrow"
before=$(hyprctl -j clients | jq -c '[.[].address]')
setsid -f omarchy-launch-terminal >/dev/null 2>&1 </dev/null
terminal=$(wait_window '^foot$' "$WS_A" "$before"); sleep 0.6
before=$(hyprctl -j clients | jq -c '[.[].address]')
setsid -f omarchy-launch-browser >/dev/null 2>&1 </dev/null
browser=$(wait_window '^chromium$' "$WS_A" "$before"); sleep 1.5
require_active "$browser" "the browser"
dispatch 'hl.dsp.layout("togglesplit")'; sleep 1.2
direction=$(hyprctl -j clients | jq -r --arg t "$terminal" --arg b "$browser" '
  (map(select(.address == $t))[0].at) as $ta | (map(select(.address == $b))[0].at) as $ba |
  if $ta[0] < $ba[0] then "l" elif $ta[0] > $ba[0] then "r" elif $ta[1] < $ba[1] then "u" else "d" end')
dispatch "hl.dsp.focus({ direction = '$direction' })"
wait_step window-controls

say "Step 6: Super + T twice, Super + F twice, Super + W on the browser"
require_active "$terminal" "the terminal"
dispatch "hl.dsp.window.float({ action = 'toggle' })"; sleep 0.6
dispatch "hl.dsp.window.float({ action = 'toggle' })"; sleep 0.6
dispatch "hl.dsp.window.fullscreen({ mode = 'fullscreen' })"; sleep 0.6
dispatch "hl.dsp.window.fullscreen({ mode = 'fullscreen' })"; sleep 0.6
dispatch "hl.dsp.focus({ window = 'address:$browser' })"; sleep 0.4
require_active "$browser" "the browser"
dispatch "hl.dsp.window.close()"; browser=""
wait_step workspaces

say "Step 7: Super + $WS_B, Super + $WS_A, Super + Shift + $WS_B"
dispatch "hl.dsp.focus({ workspace = '$WS_B' })"; sleep 0.6
dispatch "hl.dsp.focus({ workspace = '$WS_A' })"; sleep 0.6
require_active "$terminal" "the terminal"
# The clipboard step opens a terminal with a line to copy as it begins, on
# whichever test workspace is focused then: note the windows before it can.
before=$(hyprctl -j clients | jq -c '[.[].address]')
dispatch "hl.dsp.window.move({ workspace = '$WS_B' })"
wait_step clipboard
sample_terminal=$(wait_window '^org\.omarchy\.onboarding-sample$' "^($WS_A|$WS_B)$" "$before")

say "Step 8: Super + C on the card's line, Super + V in the terminal"
saved_clipboard=$(wl-paste --no-newline 2>/dev/null || true)
wl-copy "$SAMPLE" >/dev/null 2>&1 # wl-copy forks a server that keeps stdout open; what Super + C on the card's selected line does
sleep 1.5          # the overlay sees it, ticks, and focuses the terminal
require_active "$sample_terminal" "the clipboard terminal"
# What Super + V does in a terminal: Shift + Insert to the focused surface.
dispatch "hl.dsp.send_key_state({ mods = 'SHIFT', key = 'Insert', state = 'down' })"
sleep 0.06
dispatch "hl.dsp.send_key_state({ mods = 'SHIFT', key = 'Insert', state = 'up' })"
wait_step shortcuts
printf '%s' "$saved_clipboard" | wl-copy >/dev/null 2>&1

say "Step 9: Super + K, then Esc"
setsid -f omarchy-menu-keybindings >/dev/null 2>&1 </dev/null
sleep 1.5
omarchy-menu toggle # what Esc does to the list: the menu's layer closes
wait_step theme

say "Steps 10 and 11: skipped, to be done again from the finish screen"
"${CLI[@]}" skip >/dev/null
wait_step display
"${CLI[@]}" skip >/dev/null
wait_step finish
[[ $(info '.openSteps | join(",")') == "theme,display" ]] || { echo "fail: Still to do should list theme and display, got $(info '.openSteps')" >&2; exit 1; }

say "Do them now (D): through the two skipped steps, then the finish screen"
"${CLI[@]}" redo >/dev/null
wait_step theme
"${CLI[@]}" skip >/dev/null
wait_step display
"${CLI[@]}" skip >/dev/null
wait_step finish
"${CLI[@]}" next >/dev/null # Finish: the overlay closes, so read the state file
for _ in $(seq 1 25); do
  [[ $(jq -r .status "$STATE" 2>/dev/null) == completed ]] && break
  sleep 0.2
done
[[ $(jq -r .status "$STATE") == completed ]] || { echo "fail: expected the flow to be completed, got $(jq -r .status "$STATE")" >&2; exit 1; }

say "The whole tutorial completed."
