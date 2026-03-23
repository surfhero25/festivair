"""FestivAir Haven relay -- asyncio TCP server.

Bridges iOS devices over TCP using the MeshEnvelope JSON wire format.
Each client gets a dedicated read task and write task (with an
asyncio.Queue) so slow writers never block the event loop.
"""

from __future__ import annotations

import asyncio
import logging
import signal
import time
from collections import OrderedDict
from typing import Any

from relay.config import (
    DEDUP_MAX_ENTRIES,
    DEDUP_TTL_SECONDS,
    HOST,
    MAX_CLIENTS,
    PORT,
    configure_logging,
)
from relay.protocol import (
    ProtocolError,
    decode_frames,
    encode_frame,
    validate_envelope,
)
from relay.squad_filter import ClientInfo, SquadRouter

log = logging.getLogger(__name__)


# ── Deduplication ────────────────────────────────────────────────────

class MessageDedup:
    """Bounded, time-limited set of seen message IDs."""

    def __init__(
        self,
        max_entries: int = DEDUP_MAX_ENTRIES,
        ttl_seconds: int = DEDUP_TTL_SECONDS,
    ) -> None:
        self._max = max_entries
        self._ttl = ttl_seconds
        self._seen: OrderedDict[str, float] = OrderedDict()

    def is_duplicate(self, message_id: str) -> bool:
        """Return True if *message_id* was already seen (and still valid)."""
        now = time.monotonic()
        ts = self._seen.get(message_id)
        if ts is not None and (now - ts) < self._ttl:
            return True

        # Evict expired entries lazily (oldest first)
        while self._seen and (now - next(iter(self._seen.values()))) >= self._ttl:
            self._seen.popitem(last=False)

        # Evict oldest if at capacity
        while len(self._seen) >= self._max:
            self._seen.popitem(last=False)

        self._seen[message_id] = now
        return False


# ── Relay Server ─────────────────────────────────────────────────────

class HavenRelay:
    """Asyncio TCP relay server for FestivAir mesh envelopes."""

    def __init__(self) -> None:
        self._router = SquadRouter()
        self._dedup = MessageDedup()
        self._server: asyncio.AbstractServer | None = None
        self._tasks: set[asyncio.Task[None]] = set()

    # ── Lifecycle ────────────────────────────────────────────────────

    async def start(self) -> None:
        """Bind the server socket and begin accepting connections."""
        configure_logging()
        self._server = await asyncio.start_server(
            self._handle_client,
            HOST,
            PORT,
        )
        addrs = ", ".join(str(s.getsockname()) for s in self._server.sockets)
        log.info("Haven relay listening on %s", addrs)

        # Install signal handlers for graceful shutdown
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, lambda s=sig: asyncio.create_task(self.stop(s)))

        async with self._server:
            await self._server.serve_forever()

    async def stop(self, sig: signal.Signals | None = None) -> None:
        """Gracefully shut down the server."""
        if sig:
            log.info("Received %s, shutting down...", sig.name)

        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()

        # Cancel all client tasks
        for task in list(self._tasks):
            task.cancel()
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)

        log.info(
            "Shutdown complete. Served %d clients across %d squads.",
            self._router.client_count,
            self._router.squad_count,
        )

    # ── Client handling ──────────────────────────────────────────────

    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        """Entry point for each new TCP connection."""
        addr = writer.get_extra_info("peername")

        if self._router.client_count >= MAX_CLIENTS:
            log.warning("Rejecting connection from %s (max clients reached)", addr)
            writer.close()
            await writer.wait_closed()
            return

        log.info("New connection from %s", addr)

        # We don't know the peer_id until the first heartbeat, so use a
        # temporary placeholder that will be replaced.
        queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=256)
        peer_id: str | None = None
        client: ClientInfo | None = None

        read_task = asyncio.current_task()
        write_task = asyncio.create_task(self._writer_loop(writer, queue))
        self._tasks.add(write_task)
        if read_task is not None:
            self._tasks.add(read_task)

        buffer = b""
        try:
            while True:
                chunk = await reader.read(65536)
                if not chunk:
                    break  # client disconnected

                buffer += chunk

                try:
                    frames = decode_frames(buffer)
                except ProtocolError as exc:
                    log.warning("Protocol error from %s: %s", addr, exc)
                    break

                consumed = sum(size for _, size in frames)
                buffer = buffer[consumed:]

                for envelope, _ in frames:
                    try:
                        validate_envelope(envelope)
                    except ProtocolError as exc:
                        log.warning("Invalid envelope from %s: %s", addr, exc)
                        continue

                    # First valid message: register the client
                    if peer_id is None:
                        peer_id = envelope["originPeerId"]
                        client = ClientInfo(
                            peer_id=peer_id,
                            writer=writer,
                            queue=queue,
                        )
                        self._router.register(client)

                    # Extract joinCode from heartbeat or any message
                    msg = envelope.get("message", {})
                    join_code = msg.get("joinCode")
                    if join_code and client is not None:
                        self._router.assign_squad(peer_id, join_code)

                    # Dedup
                    message_id = envelope["messageId"]
                    if self._dedup.is_duplicate(message_id):
                        log.debug("Duplicate message %s from %s", message_id, peer_id)
                        continue

                    # Route
                    targets = self._router.route_message(envelope, peer_id)
                    if targets:
                        frame = encode_frame(envelope)
                        for target in targets:
                            try:
                                target.queue.put_nowait(frame)
                            except asyncio.QueueFull:
                                log.warning(
                                    "Write queue full for %s, dropping message",
                                    target.peer_id,
                                )

                    log.debug(
                        "Relayed %s from %s to %d clients",
                        msg.get("type", "?"),
                        peer_id,
                        len(targets),
                    )

        except asyncio.CancelledError:
            pass
        except Exception:
            log.exception("Unhandled error for client %s", addr)
        finally:
            write_task.cancel()
            self._tasks.discard(write_task)
            if read_task is not None:
                self._tasks.discard(read_task)

            if peer_id is not None:
                self._router.unregister(peer_id)

            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

            log.info("Connection closed: %s (peer=%s)", addr, peer_id or "unknown")

    @staticmethod
    async def _writer_loop(
        writer: asyncio.StreamWriter,
        queue: asyncio.Queue[bytes],
    ) -> None:
        """Drain the write queue and send frames to the client."""
        try:
            while True:
                data = await queue.get()
                writer.write(data)
                await writer.drain()
        except asyncio.CancelledError:
            pass
        except ConnectionError:
            pass


# ── Entry point ──────────────────────────────────────────────────────

def main() -> None:
    """Run the Haven relay server."""
    relay = HavenRelay()
    try:
        asyncio.run(relay.start())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
