"""Tests for relay.squad_filter — registration and routing rules."""

from __future__ import annotations

import asyncio
from unittest.mock import MagicMock

import pytest

from relay.squad_filter import ClientInfo, SquadRouter
from tests.conftest import make_v1_envelope, make_v2_envelope


# ── Helpers ───────────────────────────────────────────────────────────


def make_client(peer_id: str) -> ClientInfo:
    """Build a ClientInfo with stub writer + queue. No real I/O."""
    return ClientInfo(
        peer_id=peer_id,
        writer=MagicMock(spec=asyncio.StreamWriter),
        queue=asyncio.Queue(maxsize=64),
    )


@pytest.fixture
def router_with_squad():
    """Two clients in squad ABC123, one in XYZ789, one ungrouped."""
    router = SquadRouter()
    a = make_client("peer-A")
    b = make_client("peer-B")
    c = make_client("peer-C")
    d = make_client("peer-D")
    for client in (a, b, c, d):
        router.register(client)
    router.assign_squad("peer-A", "ABC123")
    router.assign_squad("peer-B", "ABC123")
    router.assign_squad("peer-C", "XYZ789")
    # peer-D stays ungrouped
    return router, {"a": a, "b": b, "c": c, "d": d}


# ── Registration ──────────────────────────────────────────────────────


class TestRegistration:
    def test_register_adds_client(self):
        router = SquadRouter()
        router.register(make_client("p1"))
        assert router.client_count == 1
        assert router.get_client("p1") is not None

    def test_assign_squad_creates_set(self):
        router = SquadRouter()
        router.register(make_client("p1"))
        router.assign_squad("p1", "code1")
        assert router.squad_count == 1

    def test_assign_squad_for_unknown_peer_is_noop(self):
        router = SquadRouter()
        router.assign_squad("ghost", "code1")
        assert router.squad_count == 0

    def test_unregister_removes_from_squad(self):
        router = SquadRouter()
        router.register(make_client("p1"))
        router.assign_squad("p1", "code1")
        router.unregister("p1")
        assert router.client_count == 0
        # Empty squads are pruned
        assert router.squad_count == 0

    def test_unregister_does_not_remove_other_squad_members(self):
        router = SquadRouter()
        router.register(make_client("p1"))
        router.register(make_client("p2"))
        router.assign_squad("p1", "code1")
        router.assign_squad("p2", "code1")
        router.unregister("p1")
        assert router.client_count == 1
        assert router.squad_count == 1

    def test_unregister_unknown_peer_is_noop(self):
        router = SquadRouter()
        router.unregister("ghost")  # no raise


# ── Routing: V1 envelopes ─────────────────────────────────────────────


class TestRouteV1:
    def test_routes_to_squadmates_only_excluding_sender(self, router_with_squad):
        router, peers = router_with_squad
        env = make_v1_envelope(msg_type="chatMessage", join_code="ABC123",
                               origin="peer-A")
        targets = router.route_message(env, sender_peer_id="peer-A")
        target_ids = {t.peer_id for t in targets}
        assert target_ids == {"peer-B"}  # B is the only other squadmate

    def test_does_not_route_to_other_squad(self, router_with_squad):
        router, _ = router_with_squad
        env = make_v1_envelope(join_code="XYZ789", origin="peer-C")
        targets = router.route_message(env, sender_peer_id="peer-C")
        assert {t.peer_id for t in targets} == set()  # C is alone in XYZ789

    def test_target_squad_id_takes_precedence_over_join_code(
            self, router_with_squad):
        router, _ = router_with_squad
        # Sender in ABC123 explicitly targets XYZ789
        env = make_v1_envelope(join_code="ABC123", origin="peer-A",
                               target_squad="XYZ789")
        targets = router.route_message(env, sender_peer_id="peer-A")
        assert {t.peer_id for t in targets} == {"peer-C"}

    def test_unknown_join_code_falls_back_to_broadcast(self, router_with_squad):
        router, _ = router_with_squad
        env = make_v1_envelope(join_code="UNKNOWN", origin="peer-A")
        targets = router.route_message(env, sender_peer_id="peer-A")
        # Broadcast to everyone except sender
        assert {t.peer_id for t in targets} == {"peer-B", "peer-C", "peer-D"}

    def test_no_join_code_falls_back_to_broadcast(self, router_with_squad):
        router, _ = router_with_squad
        env = make_v1_envelope(join_code=None, origin="peer-A")
        targets = router.route_message(env, sender_peer_id="peer-A")
        assert {t.peer_id for t in targets} == {"peer-B", "peer-C", "peer-D"}


# ── Routing: V2 envelopes ─────────────────────────────────────────────
# This is the new code path I just added — most important to cover.


class TestRouteV2:
    def test_routes_by_envelope_squad_id(self, router_with_squad):
        router, _ = router_with_squad
        env = make_v2_envelope(squad_id="ABC123", origin="peer-A")
        targets = router.route_message(env, sender_peer_id="peer-A")
        assert {t.peer_id for t in targets} == {"peer-B"}

    def test_v2_does_not_consult_nested_join_code(self, router_with_squad):
        # If V2 routing accidentally fell through to V1's
        # message.joinCode lookup, this would broadcast. Verify it does NOT.
        router, _ = router_with_squad
        env = make_v2_envelope(squad_id="ABC123", origin="peer-A")
        # Sneak a fake `message.joinCode` attempting to redirect
        env["message"] = {"joinCode": "XYZ789"}
        targets = router.route_message(env, sender_peer_id="peer-A")
        # Should still route by V2's envelope-level squadId, not the fake nested
        assert {t.peer_id for t in targets} == {"peer-B"}

    def test_v2_unknown_squad_falls_back_to_broadcast(self, router_with_squad):
        router, _ = router_with_squad
        env = make_v2_envelope(squad_id="UNKNOWN", origin="peer-A")
        targets = router.route_message(env, sender_peer_id="peer-A")
        assert {t.peer_id for t in targets} == {"peer-B", "peer-C", "peer-D"}

    def test_v2_excludes_sender(self, router_with_squad):
        router, _ = router_with_squad
        env = make_v2_envelope(squad_id="ABC123", origin="peer-A")
        targets = router.route_message(env, sender_peer_id="peer-A")
        assert "peer-A" not in {t.peer_id for t in targets}

    def test_v2_target_squad_id_envelope_field_still_wins(self, router_with_squad):
        # If a V2 envelope ALSO has top-level targetSquadId, the V1-style
        # precedence applies. Currently V2 envelopes don't carry
        # targetSquadId, but routing should still degrade safely.
        router, _ = router_with_squad
        env = make_v2_envelope(squad_id="ABC123", origin="peer-A")
        env["targetSquadId"] = "XYZ789"
        targets = router.route_message(env, sender_peer_id="peer-A")
        assert {t.peer_id for t in targets} == {"peer-C"}
