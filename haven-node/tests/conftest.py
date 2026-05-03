"""Shared fixtures and helpers for the Haven test suite."""

from __future__ import annotations

import datetime
import json
import struct
import sys
import uuid
from pathlib import Path

import pytest

# Make `relay` importable when pytest is invoked from haven-node/
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


# ── Helpers ──────────────────────────────────────────────────────────


def iso_now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def make_v1_envelope(
    *,
    message_id: str | None = None,
    msg_type: str = "heartbeat",
    join_code: str | None = "ABC123",
    origin: str = "peer-A",
    visited: list[str] | None = None,
    ttl: int = 5,
    target_squad: str | None = None,
    extra_message_fields: dict | None = None,
) -> dict:
    """Build a well-formed V1 MeshEnvelope with one optional inner message."""
    msg: dict = {"type": msg_type}
    if join_code is not None:
        msg["joinCode"] = join_code
    if extra_message_fields:
        msg.update(extra_message_fields)
    env: dict = {
        "messageId": message_id or str(uuid.uuid4()),
        "message": msg,
        "originPeerId": origin,
        "visitedPeers": visited if visited is not None else [origin],
        "ttl": ttl,
        "timestamp": iso_now(),
    }
    if target_squad is not None:
        env["targetSquadId"] = target_squad
    return env


def make_v2_envelope(
    *,
    message_id: str | None = None,
    msg_type: str = "presencePulse",
    squad_id: str = "ABC123",
    origin: str = "peer-A",
    visited: list[str] | None = None,
    ttl: int = 5,
    payload: str = "",
    signature: str = "",
    target_peer: str | None = None,
) -> dict:
    """Build a well-formed V2 envelope (post-fix shape)."""
    env: dict = {
        "version": 2,
        "messageId": message_id or str(uuid.uuid4()),
        "type": msg_type,
        "payload": payload,
        "originPeerId": origin,
        "squadId": squad_id,
        "visitedPeers": visited if visited is not None else [origin],
        "ttl": ttl,
        "timestamp": iso_now(),
        "signature": signature,
    }
    if target_peer is not None:
        env["targetPeerId"] = target_peer
    return env


def frame_bytes(obj: dict) -> bytes:
    """Length-prefixed JSON frame, matching encode_frame() format."""
    payload = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    return struct.pack("!I", len(payload)) + payload


# ── Fixtures ─────────────────────────────────────────────────────────


@pytest.fixture(autouse=True)
def _reset_auth_token(monkeypatch):
    """Default every test to a known auth token. Tests can override."""
    monkeypatch.setenv("FESTIVAIR_AUTH_TOKEN", "test-token")
    # Re-import config so the module-level constant picks up the env var.
    import importlib
    import relay.config as config

    importlib.reload(config)
    # Also rebind the AUTH_TOKEN reference in server.py (it does `import relay.config as config`)
    yield
    importlib.reload(config)
