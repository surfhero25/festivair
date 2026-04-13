#!/usr/bin/env bash
set -euo pipefail

# ── FestivAir Haven Node Installer ──────────────────────────────────
# Designed for Raspberry Pi OS (Debian-based).
# Installs Python 3.11+, creates a venv, installs dependencies,
# and sets up a systemd service for auto-start.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICE_NAME="festivair-haven"
VENV_DIR="$PROJECT_DIR/.venv"

echo "==> FestivAir Haven Node Installer"
echo "    Project directory: $PROJECT_DIR"
echo ""

# ── 1. System packages ──────────────────────────────────────────────
echo "==> Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq python3 python3-pip python3-venv libavahi-compat-libdnssd-dev

# Verify Python version >= 3.11
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || { [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 11 ]; }; then
    echo "ERROR: Python 3.11+ required, found $PYTHON_VERSION"
    echo "       Install Python 3.11+ manually and re-run this script."
    exit 1
fi
echo "    Python $PYTHON_VERSION found."

# ── 2. Virtual environment ──────────────────────────────────────────
echo "==> Creating virtual environment at $VENV_DIR..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip -q
pip install -r "$PROJECT_DIR/relay/requirements.txt" -q
echo "    Dependencies installed."

# ── 3. TLS certificate ──────────────────────────────────────────────
CERT_DIR="$PROJECT_DIR/certs"
if [ ! -f "$CERT_DIR/server.crt" ]; then
    echo "Generating self-signed TLS certificate..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" -days 365 -nodes \
        -subj "/CN=festivair-haven/O=FestivAir"
    echo "    Certificate generated at $CERT_DIR/"
fi

# ── 4. Auth token ────────────────────────────────────────────────────
ENV_FILE="$PROJECT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    TOKEN=$(openssl rand -hex 32)
    cat > "$ENV_FILE" << EOF
FESTIVAIR_TLS_CERT=$CERT_DIR/server.crt
FESTIVAIR_TLS_KEY=$CERT_DIR/server.key
FESTIVAIR_AUTH_TOKEN=$TOKEN
EOF
    echo "    Auth token generated in $ENV_FILE"
fi

# ── 5. Systemd service ──────────────────────────────────────────────
echo "==> Creating systemd service: $SERVICE_NAME..."

CURRENT_USER=$(whoami)

sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=FestivAir Haven Relay Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/scripts/start.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

echo ""
echo "==> Installation complete!"
echo "    Service status:  sudo systemctl status $SERVICE_NAME"
echo "    View logs:       journalctl -u $SERVICE_NAME -f"
echo "    Restart:         sudo systemctl restart $SERVICE_NAME"
