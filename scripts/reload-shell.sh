#!/bin/bash
# Restarts the Omarchy shell so it loads the plugin's current QML. The shell's
# hot reload can't replace a plugin type that is still in use, and it doesn't
# see edits through a symlinked dev checkout.
set -euo pipefail
omarchy-restart-shell >/dev/null 2>&1
for _ in $(seq 1 40); do
  omarchy-shell shell ping >/dev/null 2>&1 && exit 0
  sleep 0.25
done
echo "the shell did not come back" >&2
exit 1
