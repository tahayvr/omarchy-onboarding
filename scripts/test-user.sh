#!/bin/bash
# A throwaway user for testing onboarding's first login (M6). Never test that
# on your own account.
#
#   sudo scripts/test-user.sh setup     create the user with the plugin installed
#   sudo scripts/test-user.sh cleanup   log it out and delete it with its home
#
# The user is "onbtest", password "onboarding". Log in on a text console
# (Ctrl + Alt + F3) and the Omarchy session starts by itself; Ctrl + Alt + F1
# returns to your own session, which keeps running.
#
# setup also lets the user who ran sudo read and write the test user's
# onboarding state and markers (~/.local/state/omarchy), so the test can be
# watched and driven from the main session.

set -euo pipefail

TEST_USER=onbtest
PASSWORD=onboarding
PLUGIN=tahayvr.onboarding

die() { echo "test-user: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
caller=${SUDO_USER:-}
[[ -n $caller && $caller != root ]] || die "run with sudo from your own account"
repo=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
home=/home/$TEST_USER

setup() {
  id "$TEST_USER" >/dev/null 2>&1 && die "$TEST_USER already exists; run cleanup first"

  # A real full name exercises the GECOS prefill in step 15.
  useradd -m -s /bin/bash -c "Onboarding Tester" "$TEST_USER"
  echo "$TEST_USER:$PASSWORD" | chpasswd

  # The plugin, as in the working tree (committed or not), without git or
  # ignored files.
  local dest=$home/.config/omarchy/plugins/$PLUGIN
  mkdir -p "$dest"
  (cd "$repo" && git ls-files -co --exclude-standard -z | xargs -0 cp --parents -t "$dest")
  chmod +x "$dest"/bin/* "$dest"/scripts/*

  # Enable it, as `omarchy plugin enable` would.
  local shell_json=$home/.config/omarchy/shell.json
  local tmp
  tmp=$(mktemp)
  jq --arg id "$PLUGIN" '.plugins = (((.plugins // []) + [{id: $id}]) | unique_by(.id))' "$shell_json" >"$tmp"
  mv "$tmp" "$shell_json"

  chown -R "$TEST_USER:$TEST_USER" "$home/.config"

  # The login hook, added the way a user would add it.
  sudo -u "$TEST_USER" HOME="$home" "$dest/bin/omarchy-onboarding" install

  # Start the Omarchy session on console login, as SDDM would.
  cat >>"$home/.bash_profile" <<'EOF'

# Added by omarchy-onboarding's test-user.sh: start Omarchy on console login.
if [[ -z $WAYLAND_DISPLAY && $(tty) == /dev/tty[2-6] ]]; then
  exec uwsm start -g -1 -e -D Hyprland hyprland.desktop
fi
EOF
  chown "$TEST_USER:$TEST_USER" "$home/.bash_profile"

  # Let the caller watch and drive the onboarding state.
  local state=$home/.local/state/omarchy
  mkdir -p "$state"
  chown -R "$TEST_USER:$TEST_USER" "$home/.local"
  setfacl -m "u:$caller:x" "$home" "$home/.local" "$home/.local/state"
  setfacl -R -m "u:$caller:rwX" "$state"
  setfacl -R -d -m "u:$caller:rwX" "$state"

  echo
  echo "Created $TEST_USER (password: $PASSWORD) with $PLUGIN enabled and the login hook installed."
  echo "Log in on a text console: Ctrl + Alt + F3, then Ctrl + Alt + F1 to come back."
}

cleanup() {
  if ! id "$TEST_USER" >/dev/null 2>&1; then
    echo "$TEST_USER doesn't exist"
    return
  fi
  loginctl terminate-user "$TEST_USER" 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -u "$TEST_USER" >/dev/null || break
    sleep 0.5
  done
  pkill -KILL -u "$TEST_USER" 2>/dev/null || true
  userdel -r "$TEST_USER" 2>/dev/null || userdel -rf "$TEST_USER"
  echo "Deleted $TEST_USER and its home."
}

case ${1:-} in
  setup) setup ;;
  cleanup) cleanup ;;
  *) die "usage: sudo $0 setup|cleanup" ;;
esac
