"""MeshEnvelope wire protocol: length-prefix framing and schema validation.

Frame format:
    [4 bytes big-endian uint32: payload length][JSON payload]

The JSON payload must conform to the MeshEnvelope schema used by the
FestivAir iOS app.
"""

from __future__ import annotations

import json
import struct
from typing import Any

# ── Length-prefix constants ───────────────────────────────────────────
HEADER_SIZE: int = 4  # bytes
MAX_PAYLOAD_SIZE: int = 1_048_576  # 1 MiB safety cap
MAX_JSON_DEPTH: int = 5

# ── Required top-level MeshEnvelope fields ───────────────────────────
_REQUIRED_ENVELOPE_FIELDS: set[str] = {
    "messageId",
    "message",
    "originPeerId",
    "visitedPeers",
    "ttl",
    "timestamp",
}

# ── Valid MeshMessagePayload types ───────────────────────────────────
VALID_MESSAGE_TYPES: set[str] = {
    "locationUpdate",
    "chatMessage",
    "gatewayAnnounce",
    "syncRequest",
    "syncResponse",
    "heartbeat",
    "findMe",
    "statusUpdate",
    "meetupPin",
}


class ProtocolError(Exception):
    """Raised when a frame or envelope fails validation."""


# ── JSON depth validation ─────────────────────────────────────────────

def _check_depth(obj: Any, depth: int = 0) -> None:
    """Reject deeply nested JSON to prevent CPU abuse."""
    if depth > MAX_JSON_DEPTH:
        raise ProtocolError(f"JSON nesting depth exceeds {MAX_JSON_DEPTH}")
    if isinstance(obj, dict):
        for v in obj.values():
            _check_depth(v, depth + 1)
    elif isinstance(obj, list):
        for v in obj:
            _check_depth(v, depth + 1)


# ── Encoding ─────────────────────────────────────────────────────────

def encode_frame(data: dict[str, Any]) -> bytes:
    """Serialize *data* as a length-prefixed JSON frame.

    Returns:
        ``bytes`` containing the 4-byte big-endian length header followed
        by the UTF-8 encoded JSON payload.

    Raises:
        ProtocolError: If the resulting payload exceeds MAX_PAYLOAD_SIZE.
    """
    payload = json.dumps(data, separators=(",", ":")).encode("utf-8")
    if len(payload) > MAX_PAYLOAD_SIZE:
        raise ProtocolError(
            f"Payload too large: {len(payload)} bytes (max {MAX_PAYLOAD_SIZE})"
        )
    header = struct.pack("!I", len(payload))
    return header + payload


# ── Decoding ─────────────────────────────────────────────────────────

def decode_frames(buffer: bytes) -> list[tuple[dict[str, Any], int]]:
    """Extract all complete frames from *buffer*.

    Returns:
        A list of ``(parsed_dict, total_bytes_consumed)`` tuples for each
        complete frame found in the buffer.  The caller should slice off
        the consumed bytes.

    Raises:
        ProtocolError: On invalid length headers or malformed JSON.
    """
    results: list[tuple[dict[str, Any], int]] = []
    offset = 0

    while offset + HEADER_SIZE <= len(buffer):
        (payload_len,) = struct.unpack("!I", buffer[offset : offset + HEADER_SIZE])

        if payload_len > MAX_PAYLOAD_SIZE:
            raise ProtocolError(
                f"Declared payload length {payload_len} exceeds maximum"
            )

        frame_end = offset + HEADER_SIZE + payload_len
        if frame_end > len(buffer):
            break  # incomplete frame; wait for more data

        raw = buffer[offset + HEADER_SIZE : frame_end]
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ProtocolError(f"Malformed JSON in frame: {exc}") from exc

        _check_depth(data)
        results.append((data, frame_end - offset))
        offset = frame_end

    return results


# ── Validation ───────────────────────────────────────────────────────

def validate_envelope(data: dict[str, Any]) -> None:
    """Validate that *data* matches the MeshEnvelope schema.

    Checks:
        - All required top-level fields are present.
        - ``message`` is a dict with a valid ``type`` field.
        - ``visitedPeers`` is a list.
        - ``ttl`` is an integer >= 0.

    Raises:
        ProtocolError: On any schema violation.
    """
    missing = _REQUIRED_ENVELOPE_FIELDS - set(data.keys())
    if missing:
        raise ProtocolError(f"Missing required envelope fields: {missing}")

    message = data["message"]
    if not isinstance(message, dict):
        raise ProtocolError("'message' must be a JSON object")

    msg_type = message.get("type")
    if msg_type not in VALID_MESSAGE_TYPES:
        raise ProtocolError(
            f"Invalid message type '{msg_type}'; expected one of {VALID_MESSAGE_TYPES}"
        )

    if not isinstance(data["visitedPeers"], list):
        raise ProtocolError("'visitedPeers' must be an array")

    ttl = data["ttl"]
    if not isinstance(ttl, int) or ttl < 0:
        raise ProtocolError(f"'ttl' must be a non-negative integer, got {ttl!r}")
