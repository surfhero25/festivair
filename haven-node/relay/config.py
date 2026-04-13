"""Haven relay server configuration."""

import logging
import os
import sys

# ── Network ──────────────────────────────────────────────────────────
HOST: str = "0.0.0.0"
PORT: int = 7331
MAX_CLIENTS: int = 100

# ── Deduplication ────────────────────────────────────────────────────
DEDUP_MAX_ENTRIES: int = 1000
DEDUP_TTL_SECONDS: int = 300  # 5 minutes

# ── TLS Configuration ────────────────────────────────────────────────
TLS_CERT_PATH: str = os.environ.get("FESTIVAIR_TLS_CERT", "")
TLS_KEY_PATH: str = os.environ.get("FESTIVAIR_TLS_KEY", "")

# ── Authentication ────────────────────────────────────────────────────
AUTH_TOKEN: str = os.environ.get("FESTIVAIR_AUTH_TOKEN", "")

# ── Rate Limiting ─────────────────────────────────────────────────────
MAX_MSG_PER_SEC: float = 10.0
MAX_BURST: int = 20
MAX_PROTOCOL_ERRORS: int = 3

# ── mDNS ─────────────────────────────────────────────────────────────
MDNS_SERVICE_TYPE: str = "_festivair-haven._tcp.local."
MDNS_SERVICE_NAME: str = "FestivAir Haven._festivair-haven._tcp.local."
HAVEN_VERSION: str = "1.0.0"

# ── Logging ──────────────────────────────────────────────────────────
LOG_FORMAT: str = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
LOG_LEVEL: int = logging.INFO


def configure_logging() -> None:
    """Set up structured logging to stdout."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter(LOG_FORMAT))
    root = logging.getLogger()
    root.setLevel(LOG_LEVEL)
    # Avoid duplicate handlers on repeated calls
    if not root.handlers:
        root.addHandler(handler)
