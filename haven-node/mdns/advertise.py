"""Advertise the Haven relay via mDNS/DNS-SD.

Registers a ``_festivair-haven._tcp`` service so iOS devices on the
same LAN can discover the relay automatically using Bonjour / NWBrowser.
"""

from __future__ import annotations

import asyncio
import logging
import signal
import socket

from zeroconf import IPVersion
from zeroconf.asyncio import AsyncServiceInfo, AsyncZeroconf

from relay.config import (
    HAVEN_VERSION,
    MDNS_SERVICE_NAME,
    MDNS_SERVICE_TYPE,
    PORT,
    configure_logging,
)

log = logging.getLogger(__name__)


def _get_local_ip() -> str:
    """Return the primary LAN IP address of this host."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            # Doesn't actually send traffic; used to find the default route IP
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


async def advertise() -> None:
    """Register the mDNS service and block until shutdown signal."""
    configure_logging()

    local_ip = _get_local_ip()
    hostname = socket.gethostname()

    info = AsyncServiceInfo(
        MDNS_SERVICE_TYPE,
        MDNS_SERVICE_NAME,
        addresses=[socket.inet_aton(local_ip)],
        port=PORT,
        properties={
            "hostname": hostname,
            "version": HAVEN_VERSION,
        },
        server=f"{hostname}.local.",
    )

    azc = AsyncZeroconf(ip_version=IPVersion.V4Only)

    try:
        await azc.async_register_service(info)
        log.info(
            "mDNS: advertising %s on %s:%d (hostname=%s, version=%s)",
            MDNS_SERVICE_TYPE,
            local_ip,
            PORT,
            hostname,
            HAVEN_VERSION,
        )

        # Block until a shutdown signal arrives
        stop_event = asyncio.Event()
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, stop_event.set)

        await stop_event.wait()
    finally:
        log.info("mDNS: unregistering service...")
        await azc.async_unregister_service(info)
        await azc.async_close()
        log.info("mDNS: shutdown complete.")


def main() -> None:
    """Run the mDNS advertiser."""
    try:
        asyncio.run(advertise())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
