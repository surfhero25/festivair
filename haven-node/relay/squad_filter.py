"""Squad-aware message routing.

Clients register with the router when they send their first heartbeat
containing a ``joinCode``.  Messages with a matching ``joinCode`` (or
``targetSquadId``) are routed only to clients in that squad.  Messages
without squad affinity are broadcast to all connected clients.
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from typing import Any

log = logging.getLogger(__name__)


@dataclass
class ClientInfo:
    """Metadata attached to a connected client."""

    peer_id: str
    writer: asyncio.StreamWriter
    queue: asyncio.Queue[bytes]
    join_code: str | None = None
    squad_ids: set[str] = field(default_factory=set)


class SquadRouter:
    """Route MeshEnvelopes to the correct set of clients.

    Thread-safety: all public methods are plain (non-async) and must be
    called from the same asyncio event-loop thread that manages clients.
    """

    def __init__(self) -> None:
        # peer_id -> ClientInfo
        self._clients: dict[str, ClientInfo] = {}
        # join_code -> set of peer_ids
        self._squads: dict[str, set[str]] = {}

    # ── Registration ─────────────────────────────────────────────────

    def register(self, client: ClientInfo) -> None:
        """Register a new client (before join_code is known)."""
        self._clients[client.peer_id] = client
        log.info("Client registered: %s", client.peer_id)

    def assign_squad(self, peer_id: str, join_code: str) -> None:
        """Associate *peer_id* with a squad identified by *join_code*."""
        client = self._clients.get(peer_id)
        if client is None:
            return

        client.join_code = join_code
        client.squad_ids.add(join_code)
        self._squads.setdefault(join_code, set()).add(peer_id)
        log.info("Client %s joined squad %s", peer_id, join_code)

    def unregister(self, peer_id: str) -> None:
        """Remove a client and clean up squad memberships."""
        client = self._clients.pop(peer_id, None)
        if client is None:
            return

        for code in client.squad_ids:
            peers = self._squads.get(code)
            if peers:
                peers.discard(peer_id)
                if not peers:
                    del self._squads[code]

        log.info("Client unregistered: %s", peer_id)

    # ── Routing ──────────────────────────────────────────────────────

    def route_message(
        self,
        envelope: dict[str, Any],
        sender_peer_id: str,
    ) -> list[ClientInfo]:
        """Determine which clients should receive *envelope*.

        Routing rules (in priority order):
            1. If the envelope has a ``targetSquadId``, send only to
               clients in that squad (excluding the sender).
            2. If the inner message carries a ``joinCode``, send to
               clients sharing that code (excluding the sender).
            3. Otherwise broadcast to every connected client except the
               sender.
        """
        target_squad = envelope.get("targetSquadId")
        join_code = (envelope.get("message") or {}).get("joinCode")

        # Determine the set of candidate peer IDs
        if target_squad and target_squad in self._squads:
            candidate_ids = self._squads[target_squad]
        elif join_code and join_code in self._squads:
            candidate_ids = self._squads[join_code]
        else:
            candidate_ids = set(self._clients.keys())

        targets: list[ClientInfo] = []
        for pid in candidate_ids:
            if pid == sender_peer_id:
                continue
            client = self._clients.get(pid)
            if client is not None:
                targets.append(client)

        return targets

    # ── Introspection ────────────────────────────────────────────────

    @property
    def client_count(self) -> int:
        return len(self._clients)

    @property
    def squad_count(self) -> int:
        return len(self._squads)

    def get_client(self, peer_id: str) -> ClientInfo | None:
        return self._clients.get(peer_id)
