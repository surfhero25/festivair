# Review brief — FestivAir session 2026-05-03

This is a hand-off note for a peer (e.g. ChatGPT / Codex) to review what shipped in this session and weigh in. The work is on branch `feature/protocol-v2-security`, pushed to `origin`.

## What shipped

Builds 45 → 49 went out to TestFlight today. Each is on App Store Connect now (all VALID), distributed to internal `Ftest` + `testers` and submitted for external beta review on `beta testers`.

| Build | Commit  | Headline |
|------:|---------|----------|
| 45    | `e798af0` | First ship after the launch-stability fixes; **crashed on launch** in the field |
| 46    | `72d1f5f` | **Fix:** invalid hex `R` in `BLEBeaconService` UUIDs (`CBUUID.__allocating_init` was throwing at static-let init) |
| 47    | `3ded463` | **Refactor:** drop in-app `DebugLogger` viewer; route call sites to `SentrySDK.addBreadcrumb` |
| 48    | `9049212` + `f66c815` | **Feat:** UWB `NearbyInteraction` precision finder + 89 festivals + 12,745 OSM POIs |
| 49    | `e6a2f67` | **UI fix:** Places overlay → bottom sheet (`.presentationDetents`, was floating mid-screen) |
| also  | `b2dd0f8` | **Build hygiene:** SPM product `Sentry` → `Sentry-Dynamic` so `Sentry.framework.dSYM` lands in the archive |

## Files most worth a careful read

```
Services/UWBPrecisionFinder.swift          ← new, ~325 lines, the gnarliest piece
Services/MeshNetworkManager.swift          ← small diff: UWB inbound publisher + magic-prefix sniff in didReceive
ViewModels/MapViewModel.swift              ← small diff: configureUWB(_:), bearing override under isPrecisionMode
App/FestivAirApp.swift                     ← UWBPrecisionFinder lifecycle owner
Resources/Info.plist                       ← NSNearbyInteractionUsageDescription added
Views/Squad/SquadMapView.swift             ← Places overlay → .sheet refactor
Resources/festivals.json                   ← 89 entries; schema in commit 9049212
scripts/build_festival_poi.py              ← Overpass scraper; output cached in Resources/festival_pois/
```

## Architecture decisions I'd want a second opinion on

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
