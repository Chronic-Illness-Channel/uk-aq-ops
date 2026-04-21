#!/usr/bin/env bash
# Installs (or reloads) the live dashboard launchd service.
# Run once after setting up .env with live credentials and creating the .venv.
# The test dashboard and cloudflared tunnel are installed from the CIC-test-uk-aq-ops repo.
set -euo pipefail

PLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$HOME/Library/LaunchAgents"
LOGS_DIR="$(cd "$PLIST_DIR/../.." && pwd)/logs"

mkdir -p "$AGENTS_DIR" "$LOGS_DIR"

PLISTS=(
  co.uk.chronicillnesschannel.aq.dashboard.live.plist
)

for plist in "${PLISTS[@]}"; do
  label="${plist%.plist}"
  src="$PLIST_DIR/$plist"
  dest="$AGENTS_DIR/$plist"

  # Unload first if already loaded (ignore errors if not loaded).
  launchctl unload "$dest" 2>/dev/null || true

  cp "$src" "$dest"
  launchctl load "$dest"
  echo "Loaded: $label"
done

echo ""
echo "Live dashboard installed. Check status:"
echo "  launchctl list | grep chronicillnesschannel"
echo ""
echo "View log:"
echo "  tail -f $LOGS_DIR/dashboard_live.log"
