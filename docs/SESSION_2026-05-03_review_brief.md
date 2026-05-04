# Review brief — FestivAir session 2026-05-03

This is a hand-off note for a peer (e.g. ChatGPT / Codex) to review what shipped in this session and weigh in. The work is on branch `feature/protocol-v2-security`, pushed to `origin`.

> **Round-2 update (build 50):** OpenAI/Codex already reviewed builds 45-49 once and flagged 5 issues. All 5 were addressed in builds 50. This brief was updated to reflect the round-2 work in commits `a820f76` and `2f0d283`. New scrutiny welcome.

## What shipped

Builds 45 → 49 went out to TestFlight today. Each is on App Store Connect now (all VALID), distributed to internal `Ftest` + `testers` and submitted for external beta review on `beta testers`.

| Build | Commit  | Headline |
|------:|---------|----------|
| 45    | `e798af0` | First ship after the launch-stability fixes; **crashed on launch** in the field |
| 46    | `72d1f5f` | **Fix:** invalid hex `R` in `BLEBeaconService` UUIDs (`CBUUID.__allocating_init` was throwing at static-let init) |
| 47    | `3ded463` | **Refactor:** drop in-app `DebugLogger` viewer; route call sites to `SentrySDK.addBreadcrumb` |
| 48    | `9049212` + `f66c815` | **Feat:** UWB `NearbyInteraction` precision finder + 89 festivals + 12,745 OSM POIs |
| 49    | `e6a2f67` | **UI fix:** Places overlay → bottom sheet (`.presentationDetents`, was floating mid-screen) |
| 50    | `a820f76` + `2f0d283` | **Security:** addresses all 5 OpenAI review findings — peer-ID stability, UWB gate, festival data wired up, V2 signature scope/verification, CloudKit chat encryption |
| also  | `b2dd0f8` | **Build hygiene:** SPM product `Sentry` → `Sentry-Dynamic` so `Sentry.framework.dSYM` lands in the archive |

## Files most worth a careful read

```
─── Round 2 (build 50, security hardening) ───────────────────────────────────
Services/PublicKeyDirectory.swift          ← NEW; in-memory + UserDefaults TOFU directory keyed by userId
Services/SquadCrypto.swift                 ← NEW; HKDF-SHA256 → AES-GCM keyed by squad join code
Models/MeshProtocolV2.swift                ← V2Envelope.signingInput(...) covers full integrity scope; senderPublicKey field added
Services/MeshCoordinator.swift             ← handleV2Message now enforces signature verify; preciseLocationRequest gated to target
Services/MeshNetworkManager.swift          ← MCPeerID.embeddedUserId/humanDisplayName extension; peerById is now a userId lookup
Services/UWBPrecisionFinder.swift          ← keyed by userId; rejects peers without embedded userId; honours currentSquadMemberIds allow-list
Services/CloudKitService.swift             ← sendMessage/getMessages encrypt/decrypt via SquadCrypto; legacy plaintext passthrough during transition
Services/OfflineMapService.swift           ← loadBundledFestivals + loadBundledFacilities replace sample data with real OSM POIs
ViewModels/MapViewModel.swift              ← UWB ranging now calls startRanging(to: member.id) + keeps allow-list synced from memberAnnotations
ViewModels/ChatViewModel.swift             ← passes joinCode through to CloudKit chat calls
Utilities/Constants.swift                  ← UserDefaultsKeys.peerStableId for pre-onboarded peer-ID stability

─── Round 1 (builds 45-49) ───────────────────────────────────────────────────
Services/UWBPrecisionFinder.swift          ← ~325 lines, NearbyInteraction handshake over MPC side-channel
Resources/Info.plist                       ← NSNearbyInteractionUsageDescription
Views/Squad/SquadMapView.swift             ← Places overlay → .sheet refactor
Resources/festivals.json                   ← 89 entries; schema in commit 9049212
scripts/build_festival_poi.py              ← Overpass scraper; output cached in Resources/festival_pois/
```

## Round-2 specifics (build 50) — explicit asks for the reviewer

OpenAI's previous review found 5 issues; here's what each became and what to scrutinise this round.

### A. Stable peer-ID via embedded userId
- `MCPeerID.displayName` is now `"<humanDisplayName>|<userId>"`. `peerById(userId)` looks up by the suffix.
- For users without an Apple userId yet (pre-onboarding), a per-install UUID persisted in `UserDefaults` is used so the peer-ID stays stable across launches.
- **Scrutiny ask:** is `MCPeerID.displayName`'s 63-byte cap a real risk? Current display name is trimmed to 40 chars + `|` + 36-char UUID = ~77 bytes — uh oh, MCPeerID may truncate or reject. Worth checking: does `MCPeerID(displayName:)` raise on >63 bytes, or silently truncate? Both would break the embeddedUserId parse.

### B. UWB squad-membership gate
- `UWBPrecisionFinder.currentSquadMemberIds: Set<String>?` — when set, inbound `tokenRequest` from peers not in that set is dropped.
- Synced from `MapViewModel.memberAnnotations` via Combine.
- Sessions are now keyed by `peerUserId`, not `displayName`.
- **Scrutiny ask:** the allow-list is mirrored from `memberAnnotations`, which depends on presence pulses. There's a window between joining a squad and receiving the first presence pulse where the allow-list is empty → all UWB rejected. Is that a problem in practice, or is it the right fail-closed default?

### C. Wire bundled festival data to OfflineMapService
- `loadBundledFestivals()` reads `Resources/festivals.json` (89 entries, slug-keyed).
- `loadBundledFacilities(for:)` reads `Resources/festival_pois/<slug>.geojson`. OSM categories map to `FacilityType` via a static dictionary.
- Slug→UUID mapping is kept in a private `[UUID: String]` map; cleared on every fetch.
- **Scrutiny ask:** the slug map is per-process. Does anything persist `FestivalVenue` JSON across launches expecting that the UUIDs are stable? If venue UUIDs are regenerated each launch from the JSON ordering, cached venue downloads keyed by UUID would orphan.

### D. V2 signature: scope + enforcement
- Signing input now covers `version | messageId | type | originPeerId | targetPeerId | squadId | timestamp | ttl | payload`. `signature` and `senderPublicKey` are excluded; `visitedPeers` is excluded (relay mutates it).
- Every `V2Envelope` carries `senderPublicKey: Data?` (DER P-256, ~91 bytes). Bumps wire size but bootstraps TOFU.
- `MessageSignerProtocol` gained `var publicKeyData: Data` so callers don't need to pass it separately.
- `PublicKeyDirectory` is in-memory + UserDefaults-persisted. First key per userId pins; conflicts drop.
- `MeshCoordinator.handleV2Message` drops everything that fails verify.
- **Scrutiny asks:**
  - The signing input is a newline-delimited text format. `payload` is appended *raw bytes* after `payload=`. That mixes binary into a text format and could confuse a future parser, but it's only used for signing/verifying — never re-parsed. Is there a cleaner encoding (e.g. CBOR / a length-prefixed binary scheme) that's worth the migration cost?
  - TOFU bootstrap: the *first* envelope from a userId trusts whatever key it claims. An attacker who pre-emptively floods the squad with envelopes claiming victim's userId before the victim joins would pin themselves as the victim's key. Mitigation idea: bind userIds to public keys via CloudKit user records (anchored to Apple ID / non-user-controlled). Worth doing in round 3?
  - Backward-incompat: 50 envelopes are unverifiable by 45-49 (different signing scope, no `senderPublicKey`). 45-49 envelopes will be dropped by 50 (missing `senderPublicKey` → no key available → drop). Acceptable for the small TestFlight beta. Should we also bump `Constants.ProtocolV2.version` to make this explicit?

### E. CloudKit chat encryption
- `SquadCrypto`: `HKDF<SHA256>(input: joinCode, salt: "FestivAir.SquadCrypto.HKDF.v1", info: "squad-payload-key", out: 32)` → AES-256-GCM.
- Wire format: `"v1:" + base64([1-byte version || AES.GCM.SealedBox.combined])`.
- `CloudKitService.sendMessage(...joinCode:)` encrypts; `getMessages(...joinCode:)` decrypts and returns `"[encrypted message]"` on failure.
- `ChatViewModel` threads the join code through.
- **Scrutiny asks:**
  - Join codes are 6 digits — only 1M possibilities. HKDF doesn't slow down brute force. An attacker with the CloudKit dump can offline-attack the join code in seconds. Is this acceptable given that the join code is also the *only* gate to mesh chat (which is the same trust boundary), or do we want a high-entropy squad master key derived independently and stored in CloudKit (encrypted to each member's public key) as the actual KDF input?
  - Mesh broadcast chat is still plaintext (only signed). For the typical short-range attacker (someone within MPC range with a sniffer), is "signed but not encrypted" the right tradeoff, or should mesh chat also be encrypted with the squad key?

## Architecture decisions I'd want a second opinion on (round 1, still relevant)

### 1. UWB token transport via MPC side-channel
Rather than adding `niTokenExchange` as a new `V2MessageType` (which would have required Haven Python whitelist sync, V2 envelope payload-budget changes, and signature wiring), I bypassed the V2 envelope entirely:

- New binary frame format on `MCSession`: `[8-byte magic "FAUWB!\0\0"][1-byte kind: tokenRequest|tokenResponse|stop][NIDiscoveryToken NSKeyedArchive]`
- `MeshNetworkManager.session(_:didReceive:fromPeer:)` sniffs the prefix **before** JSON parsing and routes through a new `uwbInboundPublisher`.
- Rationale: UWB ranging only matters between two phones already physically near each other and connected via MPC. Haven internet relay is useless for hardware ranging. Keeping it off the V2 path means no protocol drift, no Python sync, no signature scope creep.

**Question for review:** is there a downside I'm missing? E.g.:
- Should this still be signed (squad-membership proof)? Currently it's not.
- The 8-byte magic is short; is collision with future V2 envelopes a real concern?
- Is there a privacy issue with shipping NSKeyedArchive blobs over the wire (NSKeyedArchiver schema changes between iOS versions)?

### 2. Bilateral UWB handshake
Two NISessions per pair (one per side). When A initiates:
1. A creates session, gets `NIDiscoveryToken_A`, sends `.tokenRequest(token=A)` to B
2. B receives, creates session, gets `NIDiscoveryToken_B`, calls `session.run(NINearbyPeerConfiguration(peerToken: A))`, sends `.tokenResponse(token=B)` back
3. A receives, calls `session.run(NINearbyPeerConfiguration(peerToken: B))`
4. Both sessions now produce direction/distance updates.

**Race / robustness questions:**
- What if `MeshNetworkManager.peerById(_:)` returns `nil` because the MPC connection is still establishing when A calls `startRanging`? Currently we silently no-op. Should we queue and retry, or surface a "not connected" UI state?
- `sessionSuspensionEnded` re-sends a `.tokenRequest` to bootstrap a fresh handshake — is that correct, or does NISession allow re-using prior peer tokens after suspension?
- If A stops ranging while B is still observing, B keeps its session alive until `.stop` reaches it. A drops the MCPeerID mapping in `stopRanging` — could the `.stop` frame fail to send because of an out-of-order assignment?

### 3. Bearing semantics
The existing `MapViewModel.bearingToTarget` is "degrees clockwise from user-facing direction" (0 = target straight ahead). The UWB direction is a `simd_float3` unit vector in device-local horizon coordinates (`+x` = right, `+y` = up, `-z` = forward). I'm converting:

```swift
let degrees = Double(atan2(dir.x, -dir.z)) * 180 / .pi
self.bearingToTarget = (degrees + 360).truncatingRemainder(dividingBy: 360)
```

This treats the device's z-axis as "forward" and ignores the y-component (vertical). For a flat map arrow that's fine. **Question:** in landscape orientation or when the phone is held flat (face-up) the device frame rotates — does NearbyInteraction normalize the direction to world-up, or does the consumer need to apply `CMMotion`-derived attitude to flatten it onto the horizon plane?

### 4. Sentry product: dynamic vs static
Switched the SPM product from `Sentry` → `Sentry-Dynamic` (commit `b2dd0f8`). Tradeoff: dynamic linkage means a separate `Sentry.framework.dSYM` lands in the archive (so ASC can symbolicate Sentry-frame crashes in Xcode Organizer), but the binary is slightly larger and load time slightly slower.

**Question:** is there a third option — keep static linkage and run a post-archive script that extracts the embedded debug info via `dsymutil`? That would avoid the dynamic-linkage cost. The Sentry docs imply yes for accessory toolchains; not sure the `xcframework` actually contains the DWARF.

### 5. Bundle size from POI data
`Resources/festival_pois/` adds ~5 MB to the app bundle (89 GeoJSON files, 12,745 features). Folder reference, copied verbatim. Acceptable for a beta but at scale (more festivals, more categories) this won't scale.

**Options if it ever bothers us:**
- Compress each GeoJSON with gzip, decompress on demand (typically 70-80% reduction).
- Move to CloudKit and download on first app launch per festival.
- Use a binary format (FlatBuffers, MessagePack).

## Open questions explicitly worth a second pair of eyes

1. **Background BLE in production.** The launch-crash fix (build 46) was the first build where `BLEBeaconService` could actually initialize. The full BLE-as-doorbell + MPC-as-conversation architecture (with `RestoreIdentifierKey`, state-restoration delegates, `bluetooth-central`/`bluetooth-peripheral` background modes, BGTaskScheduler) is *wired up* but has never been exercised in real "two phones backgrounded, walk past each other in a crowd" conditions. That's the next major test.

2. **Display name uniqueness.** UWB peer routing keys on `MCPeerID.displayName`, which is the user's chosen display name from onboarding (defaults to "Festival Fan"). Two users sharing the same display name in one squad would collide in `peerById(_:)`. Should `MeshNetworkManager` append a stable suffix (last 4 of userId) when constructing the MCPeerID?

3. **Festival POI trust.** The pin-trust model David and I agreed on for *future* user-droppable global pins lives at `~/.claude/projects/-Users-mini-pro/memory/festivair_pin_trust_model.md`. Today's `MeetupPin` is squad-only via mesh, so the lure threat is structurally absent. When global pins ship, the model is: GPS-presence required at drop, 2-confirm minimum (3 for medical/exit/lost-and-found), author + drop-time visible, reportable, festival-staff "official" badge bypass. Anything missing?

## How to verify

```bash
# fast-forward
git pull

# compile (Release, no signing — fastest sanity check)
xcodebuild -project FestivAir.xcodeproj -scheme FestivAir \
  -configuration Release -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO

# tests (do NOT pass CODE_SIGNING_ALLOWED=NO — see CLAUDE.md, breaks
# CKContainer.default() at AppState.init in the simulator)
xcodebuild -project FestivAir.xcodeproj -scheme FestivAirTests \
  -destination 'platform=iOS Simulator,id=<UUID>' test
```

## Sentry status (live data)

As of the last check, three open issues:

- `APPLE-FESTIVAIR-IOS-4` — UUID-typo crash, build 45 only. Should auto-resolve once builds 46+ have replaced 45 in the field.
- `APPLE-FESTIVAIR-IOS-3` — same root cause, earlier event group.
- `APPLE-FESTIVAIR-IOS-2` — `CKException: (null)` from 19+ hours ago, hasn't recurred since the launch-stability fixes.

---

Reviewer: please flag anything that looks structurally wrong, brittle, or inconsistent with parts of the codebase I might not have read. The UWB integration is the highest-stakes new code.
