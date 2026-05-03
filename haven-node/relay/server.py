"""FestivAir Haven relay -- asyncio TCP server.

Bridges iOS devices over TCP using the MeshEnvelope JSON wire format.
Each client gets a dedicated read task and write task (with an
asyncio.Queue) so slow writers never block the event loop.
"""

from __future__ import annotations

import asyncio
import json
import logging
import signal
import ssl
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
import relay.config as config
from relay.protocol import (
    ProtocolError,
    decode_frames,
    encode_frame,
    validate_envelope,
)
from relay.squad_filter import ClientInfo, SquadRouter

log = logging.getLogger(__name__)


# ── Auth frame helper ────────────────────────────────────────────────

async def read_frame(reader: asyncio.StreamReader) -> bytes:
    """Read a single length-prefixed frame from the stream."""
    from relay.protocol import HEADER_SIZE, MAX_PAYLOAD_SIZE
    import struct
    header = await reader.readexactly(HEADER_SIZE)
    (payload_len,) = struct.unpack("!I", header)
    if payload_len > MAX_PAYLOAD_SIZE:
        raise ProtocolError(f"Declared payload length {payload_len} exceeds maximum")
    return await reader.readexactly(payload_len)


# ── Rate limiter ─────────────────────────────────────────────────────

class ClientRateLimiter:
    """Simple token bucket rate limiter."""
    def __init__(self, rate: float = 10.0, burst: int = 20):
        self.rate = rate  # tokens per second
        self.burst = burst
        self.tokens = burst
        self.last_refill = time.monotonic()

    def allow(self) -> bool:
        now = time.monotonic()
        elapsed = now - self.last_refill
        self.tokens = min(self.burst, self.tokens + elapsed * self.rate)
        self.last_refill = now
        if self.tokens >= 1:
            self.tokens -= 1
            return True
        return False


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
        if not config.AUTH_TOKEN:
            log.critical(
                "FESTIVAIR_AUTH_TOKEN is unset; refusing to start. "
                "Set the env var to a non-empty secret."
            )
            raise SystemExit(1)
        ssl_context = None
        if config.TLS_CERT_PATH and config.TLS_KEY_PATH:
            ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ssl_context.load_cert_chain(config.TLS_CERT_PATH, config.TLS_KEY_PATH)
            ssl_context.minimum_version = ssl.TLSVersion.TLSv1_3
            log.info("TLS enabled (TLS 1.3)")
        self._server = await asyncio.start_server(
            self._handle_client,
            HOST,
            PORT,
            ssl=ssl_context,
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

        # Authenticate: first frame must contain auth_token
        try:
            auth_frame = await asyncio.wait_for(
                read_frame(reader),
                timeout=10.0
            )
            auth_data = json.loads(auth_frame)
            token = auth_data.get("auth_token")
            if token != config.AUTH_TOKEN:
                log.warning("Auth failed from %s", addr)
                writer.close()
                await writer.wait_closed()
                return
            log.info("Client authenticated: %s", addr)
        except (asyncio.TimeoutError, json.JSONDecodeError, Exception) as e:
            log.warning("Auth handshake failed from %s: %s", addr, e)
            writer.close()
            await writer.wait_closed()
            return

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

        rate_limiter = ClientRateLimiter(rate=config.MAX_MSG_PER_SEC, burst=config.MAX_BURST)
        protocol_errors = 0

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
                    protocol_errors += 1
                    if protocol_errors >= config.MAX_PROTOCOL_ERRORS:
                        log.warning("Too many protocol errors from %s, disconnecting", addr)
                        break
                    continue

                consumed = sum(size for _, size in frames)
                buffer = buffer[consumed:]

                disconnect = False
                for envelope, _ in frames:
                    if not rate_limiter.allow():
                        log.warning("Rate limited client %s", addr)
                        continue

                    try:
                        validate_envelope(envelope)
                    except ProtocolError as exc:
                        log.warning("Invalid envelope from %s: %s", addr, exc)
                        protocol_errors += 1
                        if protocol_errors >= config.MAX_PROTOCOL_ERRORS:
                            log.warning("Too many protocol errors from %s, disconnecting", addr)
                            disconnect = True
                            break
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

                    # Extract squad key — V2 envelopes carry `squadId` at the top
                    # level; V1 envelopes nest `joinCode` inside `message`.
                    if "version" in envelope:
                        msg = {"type": envelope.get("type")}
                        join_code = envelope.get("squadId")
                    else:
                        msg = envelope.get("message", {})
                        join_code = msg.get("joinCode")

                    # Dedup
                    message_id = envelope["messageId"]
                    if self._dedup.is_duplicate(message_id):
                        log.debug("Duplicate message %s from %s", message_id, peer_id)
                        # Still update squad membership so the peer is
                        # routable for future messages from others.
                        if join_code and client is not None:
                            self._router.assign_squad(peer_id, join_code)
                        continue

                    # Route against the squad map AS IT IS NOW. Assigning
                    # the squad must happen AFTER routing — otherwise a
                    # peer announcing a squad that no other peer has joined
                    # would route to its own one-member squad (excluding
                    # itself) and reach nobody, instead of the documented
                    # broadcast-fallback behavior.
                    targets = self._router.route_message(envelope, peer_id)

                    if join_code and client is not None:
                        self._router.assign_squad(peer_id, join_code)
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

                if disconnect:
                    break

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
