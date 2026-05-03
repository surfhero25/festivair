#!/usr/bin/env bash
set -euo pipefail

# ── FestivAir Haven Node Launcher ───────────────────────────────────
# Activates the virtual environment and runs both the TCP relay server
# and the mDNS advertiser as background processes.  When either exits
# (or a signal is caught), both are shut down cleanly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$PROJECT_DIR/.venv"

if [ ! -d "$VENV_DIR" ]; then
    echo "ERROR: Virtual environment not found at $VENV_DIR"
    echo "       Run install.sh first."
    exit 1
fi

source "$VENV_DIR/bin/activate"
export PYTHONPATH="$PROJECT_DIR"

ENV_FILE="$PROJECT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
else
    echo "WARNING: $ENV_FILE not found. Run install.sh or set FESTIVAIR_AUTH_TOKEN manually."
fi

# Trap signals to forward them to child processes
cleanup() {
    echo "Shutting down Haven node..."
    kill "$RELAY_PID" "$MDNS_PID" 2>/dev/null || true
    wait "$RELAY_PID" "$MDNS_PID" 2>/dev/null || true
    echo "Haven node stopped."
}
trap cleanup SIGINT SIGTERM EXIT

# Start relay server
python -m relay.server &
RELAY_PID=$!
echo "Relay server started (PID $RELAY_PID)"

# Start mDNS advertiser
python -m mdns.advertise &
MDNS_PID=$!
echo "mDNS advertiser started (PID $MDNS_PID)"

# Wait for either process to exit
wait -n "$RELAY_PID" "$MDNS_PID"
