#!/bin/bash
# Walks the "Learn to move" drills (steps 4–7 and 9) through the real plugin on
# the live desktop, by running what each binding runs. Each drill must complete
# its step by itself; the run passes when the flow reaches the theme step.
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
SELECTOR='^/bin/bash /usr/share/omarchy/bin/omarchy-menu-select Keybindings'

terminal="" browser=""
start_ws=$(hyprctl -j activeworkspace | jq -r .id)

say() { printf '\033[1m> %s\033[0m\n' "$*" >&2; }
dispatch() { hyprctl dispatch "$1" >/dev/null; }
active() { hyprctl -j activewindow | jq -r '.address // ""'; }
ws_windows() { hyprctl -j clients | jq --arg ws "$1" '[.[] | select(.workspace.name == $ws)] | length'; }
current_step() { "${CLI[@]}" info | jq -r '.step // ""'; }

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

# Waits for a window of CLASS (a jq regex) to appear on workspace WS and prints its address.
wait_window() {
  local class=$1 ws=$2 before=$3
  for _ in $(seq 1 50); do
    local addr
    addr=$(hyprctl -j clients | jq -r --arg c "$class" --arg ws "$ws" --argjson before "$before" \
      '[.[] | select((.class | test($c)) and .workspace.name == $ws and ((.address) as $a | $before | index($a) | not))][0].address // ""')
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
"${CLI[@]}" track new-to-linux >/dev/null
"${CLI[@]}" next >/dev/null # welcome
# Steps 1 and 2 skip themselves on a machine that is online and not deferred.
wait_step super-key
"${CLI[@]}" next >/dev/null # super-key needs the overlay's key catcher (M3)
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
dispatch "hl.dsp.window.move({ workspace = '$WS_B' })"
wait_step clipboard
"${CLI[@]}" next >/dev/null # clipboard is checked in the overlay's own field (M3)
wait_step shortcuts

say "Step 9: Super + K"
setsid -f omarchy-menu-keybindings >/dev/null 2>&1 </dev/null
wait_step theme

say "All drills completed their steps."
