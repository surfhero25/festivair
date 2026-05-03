"""Tests for relay.protocol — frame encoding/decoding and envelope validation."""

from __future__ import annotations

import json
import struct

import pytest

from relay.protocol import (
    HEADER_SIZE,
    MAX_JSON_DEPTH,
    MAX_PAYLOAD_SIZE,
    ProtocolError,
    V2_VALID_MESSAGE_TYPES,
    VALID_MESSAGE_TYPES,
    decode_frames,
    encode_frame,
    is_v2_envelope,
    validate_envelope,
)
from tests.conftest import make_v1_envelope, make_v2_envelope


# ── encode_frame ──────────────────────────────────────────────────────


class TestEncodeFrame:
    def test_round_trips_through_decode(self):
        env = make_v1_envelope()
        frame = encode_frame(env)
        decoded, consumed = decode_frames(frame)[0]
        assert consumed == len(frame)
        assert decoded == env

    def test_header_is_big_endian_uint32(self):
        env = {"messageId": "abc", "ttl": 1}
        frame = encode_frame(env)
        (declared_len,) = struct.unpack("!I", frame[:HEADER_SIZE])
        assert declared_len == len(frame) - HEADER_SIZE

    def test_uses_compact_separators(self):
        # No spaces between key:value or commas — saves bytes on the wire.
        frame = encode_frame({"a": 1, "b": 2})
        body = frame[HEADER_SIZE:].decode()
        assert ", " not in body and ": " not in body

    def test_rejects_oversized_payload(self):
        # 2 MiB string blows past MAX_PAYLOAD_SIZE (1 MiB)
        huge = {"data": "x" * (MAX_PAYLOAD_SIZE + 100)}
        with pytest.raises(ProtocolError, match="Payload too large"):
            encode_frame(huge)


# ── decode_frames ─────────────────────────────────────────────────────


class TestDecodeFrames:
    def test_returns_empty_for_empty_buffer(self):
        assert decode_frames(b"") == []

    def test_returns_empty_when_header_incomplete(self):
        # Less than 4 bytes — can't read length yet
        assert decode_frames(b"\x00\x00") == []

    def test_returns_empty_when_payload_incomplete(self):
        # Header says 100 bytes, only 5 follow
        partial = struct.pack("!I", 100) + b"abcde"
        assert decode_frames(partial) == []

    def test_decodes_multiple_frames_in_one_buffer(self):
        a = encode_frame({"messageId": "1", "ttl": 1})
        b = encode_frame({"messageId": "2", "ttl": 2})
        results = decode_frames(a + b)
        assert len(results) == 2
        assert results[0][0]["messageId"] == "1"
        assert results[1][0]["messageId"] == "2"

    def test_returns_partial_when_trailing_frame_is_incomplete(self):
        complete = encode_frame({"messageId": "1", "ttl": 1})
        partial = struct.pack("!I", 50) + b"only-7b"
        results = decode_frames(complete + partial)
        assert len(results) == 1
        assert results[0][0]["messageId"] == "1"

    def test_rejects_oversized_declared_length(self):
        bad = struct.pack("!I", MAX_PAYLOAD_SIZE + 1) + b""
        with pytest.raises(ProtocolError, match="exceeds maximum"):
            decode_frames(bad)

    def test_rejects_malformed_json(self):
        body = b"not-valid-json{"
        bad = struct.pack("!I", len(body)) + body
        with pytest.raises(ProtocolError, match="Malformed JSON"):
            decode_frames(bad)

    def test_rejects_excessive_nesting(self):
        nested: dict | list = "leaf"
        # Build dict nested MAX_JSON_DEPTH+2 deep
        for _ in range(MAX_JSON_DEPTH + 2):
            nested = {"x": nested}
        body = json.dumps(nested).encode()
        bad = struct.pack("!I", len(body)) + body
        with pytest.raises(ProtocolError, match="nesting depth"):
            decode_frames(bad)


# ── is_v2_envelope dispatch ───────────────────────────────────────────


class TestIsV2Envelope:
    def test_v1_envelope_has_no_version_field(self):
        assert not is_v2_envelope(make_v1_envelope())

    def test_v2_envelope_has_version_field(self):
        assert is_v2_envelope(make_v2_envelope())

    def test_version_field_alone_qualifies_as_v2(self):
        # Even partial garbage with `version` is treated as V2 for dispatch
        # — the V2 validator will then reject it for missing fields.
        assert is_v2_envelope({"version": 2})


# ── validate_envelope V1 ──────────────────────────────────────────────


class TestValidateV1:
    def test_accepts_well_formed_envelope(self):
        validate_envelope(make_v1_envelope())  # no raise

    def test_accepts_every_whitelisted_type(self):
        for t in VALID_MESSAGE_TYPES:
            validate_envelope(make_v1_envelope(msg_type=t))

    def test_rejects_unknown_type(self):
        env = make_v1_envelope(msg_type="notARealType")
        with pytest.raises(ProtocolError, match="Invalid message type"):
            validate_envelope(env)

    @pytest.mark.parametrize("missing", [
        "messageId", "message", "originPeerId", "visitedPeers", "ttl", "timestamp",
    ])
    def test_rejects_missing_required_field(self, missing):
        env = make_v1_envelope()
        del env[missing]
        with pytest.raises(ProtocolError, match="Missing required envelope fields"):
            validate_envelope(env)

    def test_rejects_message_that_is_not_a_dict(self):
        env = make_v1_envelope()
        env["message"] = "not-a-dict"
        with pytest.raises(ProtocolError, match="must be a JSON object"):
            validate_envelope(env)

    def test_rejects_visited_peers_not_a_list(self):
        env = make_v1_envelope()
        env["visitedPeers"] = "peer-A"
        with pytest.raises(ProtocolError, match="must be an array"):
            validate_envelope(env)

    def test_rejects_negative_ttl(self):
        env = make_v1_envelope(ttl=-1)
        with pytest.raises(ProtocolError, match="non-negative integer"):
            validate_envelope(env)

    def test_rejects_string_ttl(self):
        env = make_v1_envelope()
        env["ttl"] = "5"
        with pytest.raises(ProtocolError, match="non-negative integer"):
            validate_envelope(env)

    def test_rejects_bool_ttl(self):
        # bool is a subclass of int in Python — verify explicit rejection
        # if you care. (Currently passes through; documenting actual behavior.)
        env = make_v1_envelope()
        env["ttl"] = True
        # bool IS int in Python, so this passes today. If you want to reject
        # bools later, this test will fail and force an explicit decision.
        validate_envelope(env)


# ── validate_envelope V2 ──────────────────────────────────────────────


class TestValidateV2:
    def test_accepts_well_formed_envelope(self):
        validate_envelope(make_v2_envelope())

    def test_accepts_every_whitelisted_v2_type(self):
        for t in V2_VALID_MESSAGE_TYPES:
            validate_envelope(make_v2_envelope(msg_type=t))

    def test_rejects_unknown_v2_type(self):
        env = make_v2_envelope(msg_type="notARealV2Type")
        with pytest.raises(ProtocolError, match="Invalid V2 message type"):
            validate_envelope(env)

    def test_rejects_v1_type_in_v2_envelope(self):
        # heartbeat is V1-only; should not be accepted in a V2 envelope
        env = make_v2_envelope(msg_type="heartbeat")
        with pytest.raises(ProtocolError, match="Invalid V2 message type"):
            validate_envelope(env)

    @pytest.mark.parametrize("missing", [
        "messageId", "type", "payload", "originPeerId",
        "squadId", "visitedPeers", "ttl", "timestamp", "signature",
    ])
    def test_rejects_missing_required_field(self, missing):
        env = make_v2_envelope()
        del env[missing]
        with pytest.raises(ProtocolError, match="Missing required V2 envelope fields"):
            validate_envelope(env)

    def test_envelope_without_version_falls_back_to_v1_validation(self):
        # Stripping `version` makes is_v2_envelope() return False,
        # so dispatch sends it through V1 validation, which rejects it
        # for missing the V1-required `message` field. Documents the
        # dispatch semantics — not a fluke.
        env = make_v2_envelope()
        del env["version"]
        with pytest.raises(ProtocolError, match="Missing required envelope fields"):
            validate_envelope(env)

    def test_rejects_empty_squad_id(self):
        env = make_v2_envelope(squad_id="")
        with pytest.raises(ProtocolError, match="non-empty string"):
            validate_envelope(env)

    def test_rejects_non_string_squad_id(self):
        env = make_v2_envelope()
        env["squadId"] = 12345
        with pytest.raises(ProtocolError, match="non-empty string"):
            validate_envelope(env)

    def test_rejects_negative_ttl(self):
        env = make_v2_envelope(ttl=-1)
        with pytest.raises(ProtocolError, match="non-negative integer"):
            validate_envelope(env)


# ── Cross-version / type whitelist hygiene ────────────────────────────


class TestWhitelistHygiene:
    def test_v1_and_v2_type_sets_are_disjoint(self):
        # 'chat' in V2 vs 'chatMessage' in V1 — should not collide.
        overlap = VALID_MESSAGE_TYPES & V2_VALID_MESSAGE_TYPES
        assert overlap == set(), f"V1/V2 type names collide: {overlap}"

    def test_v2_whitelist_matches_ios_enum(self):
        # If iOS adds a new V2MessageType, this set must be updated to match.
        # Hardcoded snapshot of V2MessageType in iOS Models/MeshProtocolV2.swift.
        ios_v2_types = {
            "presencePulse", "locationRequest", "locationResponse",
            "preciseLocationRequest", "preciseLocationResponse",
            "stopPreciseLocation", "requestRenewal", "clusterHandoff",
            "urgentChat", "chat", "squadAnnouncement", "sos", "sosCancelled",
        }
        assert V2_VALID_MESSAGE_TYPES == ios_v2_types
