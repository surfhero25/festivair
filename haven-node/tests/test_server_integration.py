"""End-to-end integration tests against a live HavenRelay over TCP.

These tests bind a real server on a random localhost port, open real
TCP connections, and exercise the auth handshake plus V1 and V2 routing.

Marked with @pytest.mark.integration so they can be deselected in fast
runs (`pytest -m 'not integration'`).
"""

from __future__ import annotations

import asyncio
import importlib
import json
import struct

import pytest

from tests.conftest import frame_bytes, make_v1_envelope, make_v2_envelope

pytestmark = pytest.mark.integration


# ── Server fixture ────────────────────────────────────────────────────


@pytest.fixture
async def relay_server(monkeypatch):
    """Start a HavenRelay on an ephemeral localhost port."""
    monkeypatch.setenv("FESTIVAIR_AUTH_TOKEN", "test-token")
    # Reload config so AUTH_TOKEN picks up the env var
    import relay.config as config
    importlib.reload(config)
    # Reload server so it sees the reloaded config
    import relay.server as server
    importlib.reload(server)

    relay = server.HavenRelay()
    # Bind on an ephemeral port; we don't want collisions in CI.
    relay._server = await asyncio.start_server(
        relay._handle_client, "127.0.0.1", 0,
    )
    host, port = relay._server.sockets[0].getsockname()[:2]

    serve_task = asyncio.create_task(relay._server.serve_forever())
    try:
        yield relay, host, port
    finally:
        relay._server.close()
        await relay._server.wait_closed()
        serve_task.cancel()
        try:
            await serve_task
        except (asyncio.CancelledError, Exception):
            pass
        # Cancel any lingering client tasks
        for task in list(relay._tasks):
            task.cancel()
        if relay._tasks:
            await asyncio.gather(*relay._tasks, return_exceptions=True)


# ── Client helpers ────────────────────────────────────────────────────


async def open_authed_client(host, port, token="test-token"):
    """Open a TCP connection and complete the auth handshake."""
    reader, writer = await asyncio.open_connection(host, port)
    writer.write(frame_bytes({"auth_token": token}))
    await writer.drain()
    return reader, writer


async def read_one_frame(reader, timeout=2.0):
    """Read a single length-prefixed JSON frame, with timeout."""
    header = await asyncio.wait_for(reader.readexactly(4), timeout=timeout)
    (n,) = struct.unpack("!I", header)
    body = await asyncio.wait_for(reader.readexactly(n), timeout=timeout)
    return json.loads(body)


async def expect_no_frame(reader, timeout=0.3):
    """Assert that no frame arrives within `timeout` seconds."""
    try:
        await asyncio.wait_for(reader.readexactly(4), timeout=timeout)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError):
        return
    raise AssertionError("Expected no frame, but received one")


async def register_v1(writer, peer_id, join_code):
    """Send a V1 heartbeat to register peer in a squad. Returns once the
    server has had time to process it."""
    writer.write(frame_bytes(make_v1_envelope(origin=peer_id, join_code=join_code)))
    await writer.drain()
    # Give the server's read loop a tick to process and assign squad membership
    await asyncio.sleep(0.05)


async def register_v2(writer, peer_id, squad_id):
    """Send a V2 presence pulse to register peer in a squad."""
    writer.write(frame_bytes(make_v2_envelope(origin=peer_id, squad_id=squad_id)))
    await writer.drain()
    await asyncio.sleep(0.05)


# ── Auth ──────────────────────────────────────────────────────────────


class TestAuth:
    async def test_correct_token_accepted(self, relay_server):
        _, host, port = relay_server
        reader, writer = await open_authed_client(host, port, "test-token")
        # Send a heartbeat to confirm the connection is alive
        writer.write(frame_bytes(make_v1_envelope()))
        await writer.drain()
        # No reply expected (sender excluded), but socket should stay open.
        await asyncio.sleep(0.1)
        assert not reader.at_eof(), "Server unexpectedly closed connection"
        writer.close()
        await writer.wait_closed()

    async def test_wrong_token_disconnects(self, relay_server):
        _, host, port = relay_server
        reader, writer = await open_authed_client(host, port, "wrong-token")
        # Server should close immediately
        await asyncio.sleep(0.1)
        # Reading should yield EOF (connection closed)
        data = await reader.read(1)
        assert data == b"", "Expected server to close on bad auth"
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

    async def test_missing_auth_token_disconnects(self, relay_server):
        _, host, port = relay_server
        reader, writer = await asyncio.open_connection(host, port)
        # Send a frame with no auth_token field
        writer.write(frame_bytes({"hello": "world"}))
        await writer.drain()
        await asyncio.sleep(0.1)
        data = await reader.read(1)
        assert data == b"", "Expected server to close on missing auth_token"
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

    async def test_server_refuses_to_start_without_token(self, monkeypatch):
        """If FESTIVAIR_AUTH_TOKEN is unset, server.start() must SystemExit."""
        monkeypatch.delenv("FESTIVAIR_AUTH_TOKEN", raising=False)
        import relay.config as config
        importlib.reload(config)
        import relay.server as server
        importlib.reload(server)

        relay = server.HavenRelay()
        with pytest.raises(SystemExit):
            await relay.start()


# ── V1 routing E2E ────────────────────────────────────────────────────


class TestV1RoutingE2E:
    async def test_chat_routes_to_squadmate_only(self, relay_server):
        _, host, port = relay_server

        # Three clients: A and B in squad ABC123, C in XYZ789
        ra, wa = await open_authed_client(host, port)
        rb, wb = await open_authed_client(host, port)
        rc, wc = await open_authed_client(host, port)

        # Stagger registrations so each peer is known to the router
        # before the next sends. After each registration, drain any
        # heartbeats that earlier peers receive as a result.
        await register_v1(wa, "peer-A", "ABC123")
        await register_v1(wb, "peer-B", "ABC123")
        # B's heartbeat reaches A (same squad). Drain it.
        await read_one_frame(ra)
        await register_v1(wc, "peer-C", "XYZ789")
        # C's first message (registration) routes BEFORE C is assigned to
        # XYZ789, so it broadcasts to A and B. Drain those broadcasts.
        await read_one_frame(ra)
        await read_one_frame(rb)

        # Now A sends a chatMessage. Only B should receive it.
        chat = make_v1_envelope(
            msg_type="chatMessage", origin="peer-A", join_code="ABC123",
            extra_message_fields={
                "chat": {"messageId": "m1", "text": "hi", "senderName": "A"}
            },
        )
        wa.write(frame_bytes(chat))
        await wa.drain()

        received = await read_one_frame(rb)
        assert received["originPeerId"] == "peer-A"
        assert received["message"]["type"] == "chatMessage"

        # C must not receive it
        await expect_no_frame(rc)

        # Cleanup
        for w in (wa, wb, wc):
            w.close()
            try:
                await w.wait_closed()
            except Exception:
                pass

    async def test_unknown_join_code_broadcasts(self, relay_server):
        _, host, port = relay_server

        ra, wa = await open_authed_client(host, port)
        rb, wb = await open_authed_client(host, port)

        # B registers a known squad. A registers WITHOUT a joinCode so it
        # has no squad of its own — otherwise A's "unknown" joinCode in the
        # second message would route to A's own (single-member) squad.
        await register_v1(wb, "peer-B", "REGISTERED")
        wa.write(frame_bytes(make_v1_envelope(
            origin="peer-A", join_code=None, msg_type="heartbeat")))
        await wa.drain()
        await asyncio.sleep(0.05)
        # A's no-joinCode heartbeat broadcasts to all peers → B receives it.
        await read_one_frame(rb)

        # A sends with an unknown joinCode → broadcast → B should receive
        wa.write(frame_bytes(make_v1_envelope(
            origin="peer-A", join_code="NOT_A_REAL_SQUAD",
            msg_type="locationUpdate")))
        await wa.drain()

        received = await read_one_frame(rb)
        assert received["originPeerId"] == "peer-A"
        assert received["message"]["type"] == "locationUpdate"

        for w in (wa, wb):
            w.close()
            try:
                await w.wait_closed()
            except Exception:
                pass


# ── V2 routing E2E (the new code path) ────────────────────────────────


class TestV2RoutingE2E:
    async def test_v2_presence_pulse_routes_to_squadmate(self, relay_server):
        """V2 envelopes must route by envelope-level squadId, not joinCode."""
        _, host, port = relay_server

        ra, wa = await open_authed_client(host, port)
        rb, wb = await open_authed_client(host, port)
        rc, wc = await open_authed_client(host, port)

        # Stagger registrations so each peer is known before the next one
        # sends. After B joins, A receives B's pulse (same squad). Drain.
        await register_v2(wa, "peer-A", "ABC123")
        await register_v2(wb, "peer-B", "ABC123")
        await read_one_frame(ra)  # A receives B's registration pulse
        await register_v2(wc, "peer-C", "XYZ789")
        # C's first pulse routes BEFORE C joins XYZ789, so it broadcasts
        # to A and B. Drain those broadcasts.
        await read_one_frame(ra)
        await read_one_frame(rb)

        # Now A sends a fresh pulse. Only B should receive it.
        wa.write(frame_bytes(make_v2_envelope(
            origin="peer-A", squad_id="ABC123")))
        await wa.drain()

        received = await read_one_frame(rb)
        assert received["version"] == 2
        assert received["type"] == "presencePulse"
        assert received["originPeerId"] == "peer-A"
        await expect_no_frame(rc)

        for w in (wa, wb, wc):
            w.close()
            try:
                await w.wait_closed()
            except Exception:
                pass

    async def test_v2_invalid_message_type_is_dropped(self, relay_server):
        """Server should reject V2 envelopes with unknown type without crashing."""
        _, host, port = relay_server

        ra, wa = await open_authed_client(host, port)
        rb, wb = await open_authed_client(host, port)

        # Register both peers in the same squad first.
        await register_v2(wa, "peer-A", "ABC123")
        await register_v2(wb, "peer-B", "ABC123")
        # A receives B's registration pulse — drain.
        await read_one_frame(ra)

        # A sends an invalid V2 type — should be silently dropped by validate_envelope
        bad = make_v2_envelope(origin="peer-A", squad_id="ABC123",
                               msg_type="totallyBogus")
        wa.write(frame_bytes(bad))
        await wa.drain()

        # B should NOT receive the bogus message
        await expect_no_frame(rb, timeout=0.3)

        # And A's connection should still be alive (single protocol error
        # does not exceed MAX_PROTOCOL_ERRORS=3)
        wa.write(frame_bytes(make_v2_envelope(
            origin="peer-A", squad_id="ABC123")))
        await wa.drain()
        # B should now receive the valid follow-up
        received = await read_one_frame(rb)
        assert received["originPeerId"] == "peer-A"

        for w in (wa, wb):
            w.close()
            try:
                await w.wait_closed()
            except Exception:
                pass

    async def test_v1_and_v2_clients_share_squad_namespace(self, relay_server):
        """V1's joinCode and V2's envelope-level squadId share the same
        squad namespace in the router, so a V1 sender and V2 receiver
        (or vice versa) should route to each other when both register
        the same squad code."""
        _, host, port = relay_server

        ra, wa = await open_authed_client(host, port)
        rb, wb = await open_authed_client(host, port)

        # Register A on V1 and B on V2 — both with squad code ABC123.
        await register_v1(wa, "peer-A", "ABC123")
        await register_v2(wb, "peer-B", "ABC123")
        # B's pulse reached A (same squad). Drain it.
        received_at_a = await read_one_frame(ra)
        assert received_at_a["originPeerId"] == "peer-B"
        assert received_at_a.get("version") == 2  # V2 shape

        # Now A sends a fresh V1 chat — B should receive it.
        wa.write(frame_bytes(make_v1_envelope(
            origin="peer-A", join_code="ABC123",
            msg_type="chatMessage",
            extra_message_fields={
                "chat": {"messageId": "x", "text": "hi", "senderName": "A"}
            },
        )))
        await wa.drain()
        received_at_b = await read_one_frame(rb)
        assert received_at_b["originPeerId"] == "peer-A"
        assert "message" in received_at_b  # V1 shape

        for w in (wa, wb):
            w.close()
            try:
                await w.wait_closed()
            except Exception:
                pass
