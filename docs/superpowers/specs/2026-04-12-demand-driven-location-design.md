# FestivAir: Demand-Driven Location & Battery-Smart Mesh Redesign

**Date:** 2026-04-12
**Status:** Approved
**Goal:** Save battery, stay in touch, find each other — in that priority order.

---

## Problem Statement

The current mesh system broadcasts every device's GPS location every 30 seconds to all peers, regardless of whether anyone is looking. Location is redundantly included in both heartbeats and separate location updates. GPS runs continuously, even in background. All devices burn ~8% battery per hour from mesh activity alone, with no differentiation between active use and idle.

At a 12-hour festival, this kills phones by mid-afternoon.

## Design Principles

1. **Demand-driven, not supply-driven.** No device broadcasts location unless another device is actively requesting it.
2. **Battery cost is proportional to utility.** If nobody's looking, cost is near zero. If someone's navigating, only the target and seeker pay.
3. **Cluster intelligence.** Devices physically together share the work — one reporter handles GPS for the group.
4. **Chat rides free.** Regular messages piggyback on existing mesh activity rather than creating their own traffic.

---

## 1. Location State Machine

Each squad member's device operates in one of three states. A device is always in the highest state that any peer has requested.

### States

**IDLE (default)**
- GPS: OFF
- Broadcasts: `presencePulse` every 5 minutes (battery level, online status, clusterID if in one — NO location)
- MPC: advertising stays on, browsing reduced to every 60 seconds
- Battery cost: ~0.5-1% per hour

**AMBIENT**
- GPS: `kCLLocationAccuracyHundredMeters`, distance filter 50m
- Broadcasts: `locationResponse` every 60 seconds (every 90s if device battery 30-50%), sent only to requesters
- Triggered by: receiving `locationRequest` from any squad member
- Timeout: drops to IDLE 90 seconds after last `requestRenewal` received
- Battery cost: ~3% per hour

**NAVIGATE**
- GPS: `kCLLocationAccuracyBest`
- Broadcasts: `preciseLocationResponse` every 3 seconds, sent ONLY to the requesting peer (not broadcast)
- Triggered by: receiving `preciseLocationRequest` from a specific squad member
- Timeout: drops to previous state when requester sends `stopPreciseLocation` OR 90 seconds with no `requestRenewal`
- Battery cost: ~6% per hour (target device only)

### One-Sided Navigation Principle

Navigation is always one-sided. When User A navigates to User B:
- User B's device activates GPS and streams precise location to User A
- User A's device runs GPS locally ONLY to show their own position on their own screen — it does NOT broadcast to anyone
- User A's location is invisible to User B unless User B independently opens the map (which would send a separate `locationRequest`)
- This means navigating to someone costs battery on the target's device, but the requester's location is never shared as a side effect

The only time both sides see each other is when both independently choose to look.

### State Priority

If 3 people have the map open (AMBIENT) and 1 is navigating to you (NAVIGATE), you're in NAVIGATE. When the navigator stops, you drop to AMBIENT. When all 3 close their maps, you drop to IDLE.

### Transitions

```
IDLE ──(receive locationRequest)──> AMBIENT
AMBIENT ──(receive preciseLocationRequest)──> NAVIGATE
NAVIGATE ──(receive stopPreciseLocation / timeout)──> AMBIENT (if other viewers) or IDLE (if none)
AMBIENT ──(no requestRenewal for 90s)──> IDLE
```

### Background Behavior

When the app enters background:
- IDLE: no change (already minimal — presence pulse continues on BGProcessingTask schedule)
- AMBIENT: drops to IDLE after 90-second timeout (no renewals received while backgrounded)
- NAVIGATE: continues for up to 90 seconds using background location capability, then drops to IDLE if no renewal. This lets a user lock their screen while walking toward a squad member without losing navigation.

When the app returns to foreground:
- Restores to whatever state incoming requests dictate (e.g., if someone has the map open, device re-enters AMBIENT on next `locationRequest`)

### Stale Pin Display

When a user opens the map, there's a 1-3+ second delay while `locationRequest` traverses the mesh (longer with multi-hop). To eliminate perceived delay:
- Immediately show last known positions as **faded/grayed pins** with a timestamp label ("5 min ago")
- As fresh `locationResponse` messages arrive, pins snap to live positions and regain full opacity
- If a peer doesn't respond within 10 seconds, their pin stays faded with "Last seen X min ago"
- Stale pins older than 1 hour are hidden entirely (they've likely left the festival)

### SOS Mode

For genuine emergencies (medical, lost minor, security):
- Activated via dedicated SOS button (long-press to prevent accidental activation)
- Overrides ALL battery tiers — broadcasts precise GPS to entire squad continuously (every 3 seconds)
- Triggers urgent notification to all squad members with distinct alarm sound and vibration pattern
- Shows a persistent red banner on all squad members' screens with the SOS member's live location
- Persists until manually cancelled by the SOS sender
- SOS messages bypass all rate limits and chat queuing

### Low-Power Map Mode

When the requester (person opening the map) is below 15% battery:
- Their own position pin uses last-known location or hundred-meter accuracy — no GPS-best activation
- Peer location requests still work normally (peers handle their own tier based on THEIR battery)
- Navigate mode still available but requester's own pin may be less precise
- A subtle indicator shows "Your location is approximate (low battery)"

---

## 2. Cluster System

### Formation

- Devices detect proximity via BLE RSSI from existing MPC connections
- Threshold: RSSI ~-55 dBm (approximately 5 meters)
- When 2+ squad members are within this threshold, they automatically form a cluster
- A squad can have multiple clusters simultaneously (e.g., 3 members at main stage, 2 at food court — two separate clusters)
- Each cluster gets a unique clusterID (UUID, generated by first member to detect the cluster)
- Solo members (not within 5m of anyone) are not in any cluster — they handle their own location responses directly

### Roles (Battery-Weighted)

| Role | Assignment | Responsibility | GPS Active? |
|---|---|---|---|
| Reporter | Highest battery in cluster | Runs GPS when needed, broadcasts cluster centroid, responds to locationRequests on behalf of cluster | Only when cluster is in AMBIENT or NAVIGATE state |
| Backup | Second highest battery | Ready to take over, contributes RSSI data | No (standby) |
| Passive | Everyone else | Contributes BLE RSSI for triangulation only | No |

### Reporter Election

1. Cluster forms (2+ members within RSSI threshold)
2. Each member's battery level is known from `presencePulse` messages
3. Highest battery = reporter, second highest = backup
4. Re-evaluate every 5 minutes:
   - If reporter battery dropped 10%+ below backup: rotate
   - If reporter drops below 30%: immediate rotation to backup
   - If backup also below 30%: pick next highest
   - If ALL members below 30%: round-robin, 2 minutes each
5. On rotation: old reporter sends `clusterHandoff` with last known GPS fix so new reporter can respond immediately while its own GPS warms up (~2-3 seconds)

### Centroid Calculation

- Reporter's GPS provides absolute position
- Other cluster members' BLE RSSI values provide relative distance estimates
- Centroid = weighted average (reporter's GPS weighted highest)
- At 5m cluster radius in a crowd, reporter's GPS position effectively IS the centroid — RSSI refinement is a bonus

### Non-Squad Peer Contribution

- Universal relay peers (non-squad FestivAir users) nearby passively contribute RSSI data via MPC connections
- They cannot see squad data, but their BLE signal strength helps triangulate positions
- This is free — MPC already maintains these connections

### Navigate-to-Cluster Flow

1. Remote member taps the cluster pin on map
2. `preciseLocationRequest` sent to the cluster's reporter only (not all members)
3. Reporter activates GPS-best, streams centroid every 3 seconds
4. Other cluster members: zero battery cost
5. As remote member approaches within ~50m, their BLE starts picking up cluster members — triangulation assists final approach
6. Within 5m RSSI threshold, remote member joins the cluster, everything goes quiet

---

## 3. Mesh Message Protocol V2

### New Message Types

| Type | Direction | Payload | Frequency |
|---|---|---|---|
| `presencePulse` | Broadcast to squad | battery, isOnline, clusterID, clusterMembers[] | Every 5 min (IDLE) |
| `locationRequest` | Broadcast to squad | requesterID | On map open |
| `locationResponse` | Direct to requester | lat/lng (~100m), clusterID, clusterMembers[], heading | Every 60s while map open |
| `preciseLocationRequest` | Direct to target/reporter | requesterID, targetMemberID | On navigate tap |
| `preciseLocationResponse` | Direct to requester | lat/lng (best), heading, speed, accuracy | Every 3s while navigating |
| `stopPreciseLocation` | Direct to target/reporter | requesterID | On map close / stop navigate |
| `requestRenewal` | Direct to target | requesterID, mode (ambient/precise) | Every 60s to keep session alive |
| `clusterHandoff` | Within cluster | lastGPSFix, newReporterID | On reporter rotation |
| `urgentChat` | Broadcast to squad | message, priority flag | User-initiated |
| `chat` | Broadcast to squad | message | Piggybacks on next mesh activity |
| `squadAnnouncement` | Broadcast to squad | message, pinLocation (optional), announcementID | Squad creator only |
| `sos` | Broadcast to squad | lat/lng (best), heading, speed, userID | Every 3s until cancelled |
| `sosCancelled` | Broadcast to squad | userID | On manual cancel |

### Removed Message Types

- Constant 30-second heartbeats with location: replaced by 5-minute `presencePulse` (no location)
- Separate `locationUpdate` broadcasts: replaced by on-demand `locationResponse`
- Redundant location-in-heartbeat: eliminated

### Direct vs Broadcast

- `locationResponse` and `preciseLocationResponse` are DIRECT — sent via `MCSession.send(toPeers:)` with specific peer array, not broadcast
- Reduces mesh traffic ~80% since most messages no longer flood the network
- Broadcast messages: `presencePulse`, `locationRequest`, `urgentChat`, `chat`, `squadAnnouncement`

### Message Signing & Encryption

All messages in protocol V2 are:
1. Signed with sender's P-256 key (Secure Enclave-backed, via `SecureEnclave.P256.Signing`)
2. Encrypted with squad secret (AES-GCM, random 256-bit key from Keychain)
3. Validated on receipt: signature check, then decrypt, then input validation

Unsigned or invalid-signature messages are dropped silently.

### Input Validation (Built Into Decoder)

- Coordinates: latitude ±90, longitude ±180
- Text fields: max 500 chars, control characters stripped
- Message IDs: UUID format enforced
- TTL: range 1-10
- Battery: 0-100
- Malformed messages: dropped with debug log, no crash

---

## 4. Security Fixes

These are built into the protocol V2 implementation, not separate tasks.

### 4.1 Encryption Key Derivation

**Current (broken):** `SymmetricKey(data: SHA256.hash(data: squadId.utf8))`

**New:** When a user joins a squad, the squad creator's device generates a random 256-bit squad secret and transmits it over the MPC encrypted session. The secret is stored in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never derived from the join code.

- Join code is for discovery only, not encryption
- Key rotation: new secret generated when any member leaves (forward secrecy)
- New members receive the current secret from squad creator during join handshake
- If squad creator is offline during a join, any existing member who has the secret can distribute it

**Squad leader succession (key holder chain):**
- Every member who has the squad secret is a potential key holder
- If the squad creator's device goes offline (battery dies, leaves mesh), the longest-tenured online member becomes the **acting key authority**
- Acting authority can: distribute the secret to new joiners, trigger key rotation if a member is kicked
- Authority is determined by join timestamp (stored with peer info) — no election needed, it's deterministic
- When the original creator comes back online, they automatically resume authority
- This ensures the squad never gets locked out because one phone died

### 4.2 Message Signing

- Each device generates a P-256 keypair on first launch via `SecureEnclave.P256.Signing` (hardware-backed, private key never leaves the chip)
- Public key shared during squad join handshake and stored with peer info
- Every mesh message includes signature over: messageID + payload + timestamp
- Recipients verify against sender's known public key
- Cost: ~0.1ms per sign/verify — negligible

### 4.3 Haven Relay TLS + Auth

- Haven server wrapped in TLS via Python `ssl.SSLContext`
- On connection, client sends SHA256(squadSecret) as auth token
- Haven rejects connections without valid token
- Existing length-prefix JSON framing unchanged, just wrapped in TLS

### 4.4 PII Migration

Move to Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`):
- User ID
- Squad join code
- Squad secret
- Display name
- P-256 signing keypair (Secure Enclave)

Remove from UserDefaults. Delete `restoreToUserDefaults()` migration function.

UserDefaults retains only: theme preference, notification settings, onboarding completion, non-sensitive UI state.

### 4.5 Join Code Improvements

- Increase from 6 to 8 characters (~40 bits entropy vs ~30)
- Validate uniqueness against CloudKit before confirming squad creation
- Rate limit: 3 join attempts per minute per device
- Join code is discovery-only — knowing the code does NOT grant decryption ability

---

## 5. Battery Management

### Device Battery Tiers

| Battery Level | Behavior |
|---|---|
| 100-50% | Full participation. Eligible for reporter and gateway roles. |
| 50-30% | Reduced participation. Eligible for reporter but yields to higher-battery peers. Ambient responses drop to every 90s. |
| 30-15% | Passive only. Never elected reporter or gateway. Only responds to `preciseLocationRequest` if no other cluster member can. GPS stays off. |
| Below 15% | Survival mode. Presence pulse extends to every 10 minutes. Only urgent chat delivered. Regular chat queued. Shows "low battery" badge to squad. |

### Gateway Election (Revised)

**Current:** Runs every 30 seconds, even with 0 peers.

**New:** Event-driven only. Runs when:
- Internet connectivity changes (gained or lost)
- A peer joins or leaves the mesh
- Current gateway's battery drops below rotation threshold (30%)
- Every 15 minutes as a fallback heartbeat

Same battery-weighted scoring (signal 60%, battery 40%), just triggered by events instead of a timer.

### Estimated Battery Impact

| Mode | Current System | New System |
|---|---|---|
| IDLE (nobody looking) | ~8% per hour | ~0.5-1% per hour |
| Ambient (map open) | ~8% per hour | ~3% per hour |
| Navigate (active tracking, target device) | ~8% per hour | ~6% per hour |
| Cluster passive member | ~8% per hour | ~0.5% per hour |
| Cluster reporter (IDLE, no requests) | ~8% per hour | ~1% per hour |

---

## 6. Chat & Communication

### Three Chat Tiers

**Urgent chat** (red send button / long-press send):
- Delivered immediately via mesh broadcast
- Wakes recipient from IDLE with local notification
- Use cases: "Where are you?", "Meet at main stage NOW", emergency
- Rate limited: max 5 urgent messages per 10 minutes per user
- Battery cost: one mesh broadcast cycle

**Regular chat** (normal send):
- Piggybacks on next mesh activity (`presencePulse`, `locationResponse`, any mesh message)
- If no mesh activity within 30 seconds, sends standalone
- Worst-case delay: 30 seconds. Typical: near-instant (mesh is usually active)
- Battery cost: effectively zero — rides existing traffic

**Squad announcement** (squad creator only):
- Immediate broadcast with notification (same as urgent)
- Persisted locally — offline members see announcements on reconnect
- Displays as pinned banner in chat, not a regular message
- Can include a map pin (after party location, meetup point, merch booth, etc.)
- Use cases: after party locations, event updates, stage changes, facility locations

### Chat + Location Interaction

| Scenario | What Happens |
|---|---|
| Squad IDLE, regular chat sent | Delivered within 30 seconds, no GPS wake |
| Squad IDLE, urgent chat sent | Immediate delivery + notification, no GPS wake |
| Map open (AMBIENT), pending regular chats | Delivered instantly on same mesh cycle as locationRequest |
| Navigating (NAVIGATE) | All chat delivered instantly — mesh already active at 3s intervals |

### Offline Handling

- Messages queued locally with timestamp
- On mesh reconnect, queued messages delivered in chronological order
- Messages older than 24 hours auto-expire (stale festival info is worse than no info)
- Gateway syncs chat history to CloudKit when internet available

---

## 7. Files to Modify

### Core Rewrites (New Logic)

| File | Change |
|---|---|
| `Services/MeshCoordinator.swift` | Replace constant broadcast with demand-driven state machine. Remove 30s heartbeat timer. Add request/response handling. |
| `Services/MeshNetworkManager.swift` | Add direct messaging (send to specific peers). Replace seenMessageIds Array with Set. Add message signing/verification. |
| `Services/MeshRelayService.swift` | Replace SHA256 key derivation with Keychain-based squad secret. Add P-256 signing. New message types. |
| `Services/LocationManager.swift` | Replace always-on GPS with tier-based activation. Add IDLE/AMBIENT/NAVIGATE modes. Remove dual timer system. |
| `Services/GatewayManager.swift` | Replace 30s election timer with event-driven election. Add battery tier logic. |
| `Services/PeerTracker.swift` | Add cluster detection via RSSI. Add reporter election. Add cluster centroid calculation. |
| `Services/HavenTransportService.swift` | Add TLS. Add token-based auth handshake. |

### Moderate Changes

| File | Change |
|---|---|
| `Models/ChatMessage.swift` | Add `urgentChat` and `squadAnnouncement` message types. Add `priority` field. Remove location from heartbeat payload. |
| `ViewModels/ChatViewModel.swift` | Add urgent/regular send modes. Add announcement support. Add piggyback delivery logic. |
| `ViewModels/MapViewModel.swift` | Add cluster pin rendering. Add expand-on-zoom behavior. Send locationRequest on map open, stopPreciseLocation on close. |
| `Utilities/Constants.swift` | Update all timing constants to new values. Add battery tier thresholds. |
| `App/FestivAirApp.swift` | Update AppState for new auth requirement. |
| `Services/AppleAuthService.swift` | Make Sign in with Apple mandatory before squad features. |

### Light Changes

| File | Change |
|---|---|
| `Views/ChatView.swift` | Add urgent send button (long-press or toggle). Add announcement banner UI. |
| `Views/SquadMapView.swift` | Add cluster pin view. Handle cluster expand on zoom. |
| `Services/CloudKitService.swift` | Add squad secret distribution. Increase join code to 8 chars. Add uniqueness check. |
| `Utilities/KeychainHelper.swift` | Add keys for squad secret, P-256 signing keypair (Secure Enclave). Update accessibility level. |
| `App/AppDelegate.swift` | Fix force casts. Update background task to work with new state machine. |

### New Files

| File | Purpose |
|---|---|
| `Services/ClusterManager.swift` | Cluster detection, reporter election, centroid calculation, handoff logic |
| `Services/LocationTierManager.swift` | State machine for IDLE/AMBIENT/NAVIGATE transitions, request tracking, timeout management |
| `Services/MessageSigner.swift` | P-256 signing keypair (Secure Enclave) generation, message signing, signature verification |
| `Models/MeshProtocolV2.swift` | New message type definitions, encode/decode with built-in validation |

### Haven Node Changes

| File | Change |
|---|---|
| `haven-node/relay/server.py` | Add TLS wrapper. Add token auth on handshake. Add per-client rate limiting (10 msg/sec). Terminate after 3 protocol errors. |
| `haven-node/relay/protocol.py` | Add JSON nesting depth limit. Add field value validation. |
| `haven-node/relay/config.py` | Add TLS cert/key paths. Add rate limit config. |
| `haven-node/mdns/advertise.py` | No changes needed. |
| `haven-node/scripts/install.sh` | Add TLS cert generation step. |

---

## 8. Satellite Readiness & Gap Bridging

### The Satellite Bridge

iPhone 14+ has Emergency SOS via satellite. iPhone 16+ has satellite messaging. Apple has not yet opened satellite APIs to third-party apps — but our architecture doesn't need them.

**How it works today, with no special code:**
- Squad members are split across a festival. Group A has cell signal. Group B is in a dead zone.
- One device in Group B has an iPhone 16 with satellite data capability
- That device wins the gateway election (it has internet access — the gateway algorithm doesn't care if it's WiFi, cellular, or satellite)
- Gateway syncs tiny squad data to CloudKit over satellite
- Group A's devices pull from CloudKit over their cell signal
- The dead zone gap is bridged. No Pi needed. No special satellite code.

**Why this works with our design:**
- CloudKit handles the transport layer — it syncs over whatever internet the device has
- Our demand-driven protocol generates minimal data — satellite bandwidth is enough
- Gateway election is already connectivity-aware

### Future Satellite Integration (When Apple Opens APIs)

When Apple exposes satellite APIs to third-party apps (likely iOS 19 or 20):
- Add satellite as a third transport alongside MPC mesh and Haven TCP
- Urgent chat + SOS messages sent direct over satellite (no CloudKit round-trip)
- PresencePulse over satellite for basic "I'm alive" when completely off-grid

### Message Payload Budgets

To ensure satellite-friendliness now and future-proof for direct satellite transport, all protocol V2 messages have maximum payload sizes:

| Message Type | Max Payload | Notes |
|---|---|---|
| `presencePulse` | 100 bytes | battery + status + clusterID — no location, minimal data |
| `locationResponse` | 200 bytes | lat/lng + clusterInfo — fits in one satellite frame |
| `preciseLocationResponse` | 150 bytes | lat/lng + heading + speed + accuracy |
| `urgentChat` | 500 bytes | ~250 characters of text + metadata |
| `chat` | 500 bytes | same budget as urgent |
| `squadAnnouncement` | 1,000 bytes | longer text + optional pin coordinates |
| `sos` | 150 bytes | location + identity — must be tiny for fastest delivery |
| `locationRequest` | 50 bytes | just requesterID |
| `preciseLocationRequest` | 80 bytes | requesterID + targetMemberID |

These budgets are enforced at the protocol V2 encoder level. Messages exceeding budget are rejected before sending.

---

## 9. Premium Model

### Principle

The squad is the product, not the person's phone. Premium state lives on the squad record in CloudKit, not on any device. If the paying member's phone dies, the squad stays premium.

### How It Works

- Premium user creates a squad → squad record gets `tier: festivalPass` + `tierExpires: date`
- Members join → their device reads the squad tier from CloudKit → unlocks premium features locally
- Creator's phone dies → nothing changes for the rest of the squad (key holder succession keeps it running)
- Creator comes back online → resumes authority

### Tiers

| Tier | Squad Size | Price | Features |
|---|---|---|---|
| **Free** | 4 members | $0 | Messaging (urgent + regular), location + navigation, SOS, basic map, cluster intelligence |
| **Festival Pass** | 8 members | $2.99/event | Squad announcements, offline venue maps, set time alerts, schedule builder, festival summary card |
| **Crew Pass** | 20 members | $6.99/event | Everything above + custom squad themes, priority relay, after party pins with invite-only access |
| **Season Pass** | 20 members | $14.99/year | Everything, always active, past festival history + memories |

### Free User Value

Free users are not freeloaders — they ARE the mesh infrastructure. Every free user's phone is a relay node that makes the network stronger for everyone. The free tier must be genuinely useful (messaging + location + navigation + SOS) so users stay on the network.

### Conversion Funnel

Free users who join a premium squad experience premium features without paying. When they want those features for their own squad, they upgrade. The experience sells itself.

### Revenue Beyond Subscriptions

**Festival organizer partnerships (B2B):** $500-5,000 per festival. Organizers get an "official festival app" with pre-loaded venue maps, schedules, vendor locations. FestivAir gets promoted to all attendees — massive user acquisition at zero cost.

**Sponsored map pins:** Food vendors, merch booths, sponsors pay $50-200 for a branded pin on the festival map. Non-intrusive and actually useful to users.

### Cost Structure

| Cost | Amount | Notes |
|---|---|---|
| Apple Developer Program | $99/year | Required |
| CloudKit | $0 | Free tier covers millions of records. P2P mesh means minimal server load. |
| Haven Pi hardware | ~$50/unit | Optional, user-purchased or provided by festival partners |
| Domain + hosting | ~$12/year | Static site |
| App Store commission | 15% of IAP | Apple Small Business Program (under $1M) |
| **Marginal cost per squad** | **~$0** | Mesh is P2P. CloudKit syncs are tiny. No custom servers. |

---

## 10. Haven Relay — Optional Accessory

The Haven Pi relay is built into the app from day one but not required.

**Auto-discovery:** App discovers Haven nodes via Bonjour. If one is nearby, it connects with TLS + token auth. If not, mesh-only mode. Zero configuration needed from the user.

**When it's valuable:**
- Early days with low FestivAir adoption (sparse mesh)
- Very large venues (1+ mile across) with dead zones between areas
- Camping areas, parking lots, far stages with low crowd density
- Indoor/underground areas where BLE doesn't carry

**When it's unnecessary:**
- 250+ FestivAir users at a festival (mesh is dense enough)
- Dense crowd areas (main stages, food courts)
- When satellite-capable iPhones bridge the gap via gateway sync

**Distribution model:**
- Festival organizer partnerships include placing 3-4 Pi relays at the venue (we provide, they power)
- Power users / large groups can purchase as an accessory
- Over time as adoption grows, Haven becomes less necessary

---

## 11. What We're NOT Changing

- MPC as the transport layer (stays — it's the right choice for iOS mesh)
- SwiftUI views architecture (MVVM stays)
- CloudKit as the cloud backend (stays)
- Haven relay concept (stays — just gets secured)
- Squad/party/set times features (untouched)
- Onboarding flow (stays, just adds mandatory Sign in with Apple gate)
