# FestivAir Haven Node

TCP relay server for bridging FestivAir iOS devices over WiFi. Runs on a Raspberry Pi (or any Linux/macOS host) and speaks the same MeshEnvelope JSON protocol as the iOS mesh layer.

## What it does

- Accepts TCP connections from FestivAir iOS apps on port 7331
- Routes messages between clients using squad-based filtering (joinCode)
- Deduplicates mesh messages by messageId (bounded, 5-min TTL)
- Advertises itself on the LAN via mDNS (`_festivair-haven._tcp`) so iOS devices discover it automatically

## Quick start (development)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r relay/requirements.txt
export PYTHONPATH="$(pwd)"

# Run relay only
python -m relay.server

# Run mDNS only
python -m mdns.advertise

# Run both
bash scripts/start.sh
```

## Raspberry Pi setup

```bash
chmod +x scripts/install.sh scripts/start.sh
./scripts/install.sh
```

This installs dependencies, creates a virtualenv, and registers a systemd service that starts on boot.

```bash
sudo systemctl status festivair-haven   # check status
journalctl -u festivair-haven -f        # tail logs
sudo systemctl restart festivair-haven  # restart
```

## Wire protocol

Messages use length-prefix framing: a 4-byte big-endian uint32 payload length followed by a UTF-8 JSON body conforming to the MeshEnvelope schema.

## Testing with netcat

```bash
# Send a raw heartbeat frame (for manual testing, you'd need to
# prepend the 4-byte length header -- use the Python REPL instead):
python3 -c "
from relay.protocol import encode_frame
import sys, uuid, datetime
frame = encode_frame({
    'messageId': str(uuid.uuid4()),
    'message': {'type': 'heartbeat', 'joinCode': 'ABCD'},
    'originPeerId': 'test-peer',
    'visitedPeers': [],
    'ttl': 3,
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
})
sys.stdout.buffer.write(frame)
" | nc localhost 7331
```

## Tests

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r relay/requirements-dev.txt
pytest                            # full suite (~3s; includes integration)
pytest -m "not integration"       # unit tests only (~0.1s)
pytest tests/test_protocol.py -v  # one file
```

83 tests covering: V1 + V2 envelope validation and dispatch, frame
encoding/decoding, protocol fuzzing (oversized payloads, malformed JSON,
deep nesting), squad routing rules for V1 and V2, MessageDedup TTL +
capacity eviction, ClientRateLimiter token bucket, end-to-end TCP
integration with auth handshake (correct/wrong/missing token + server
refusal to start without `FESTIVAIR_AUTH_TOKEN`).

## Project structure

```
haven-node/
  relay/
    config.py         -- server and dedup settings
    protocol.py       -- wire format encoding/decoding/validation
    squad_filter.py   -- squad-aware message routing
    server.py         -- asyncio TCP relay server
    requirements.txt  -- Python dependencies
  mdns/
    advertise.py      -- mDNS service advertisement via zeroconf
  scripts/
    install.sh        -- Raspberry Pi installer (venv + systemd)
    start.sh          -- launcher for both relay + mDNS
```
