# FestivAir

Festival squad tracking app. iOS (SwiftUI + SwiftData + MultipeerConnectivity) + Python TCP relay (`haven-node/`, despite the name it's Python asyncio, NOT Node.js).

**Backend:** Hostinger VPS at http://187.124.249.219:8080 (vendor portal + AI event monitor)
**Branch:** `feature/protocol-v2-security` (36 commits, tested on device, NOT yet merged to main)
**SPM deps:** sentry-cocoa (added 2026-04-27 for crash + performance reporting). Otherwise all Apple system frameworks.

## Always do first
- Load architecture map: `architecture_festivair.md` (in memory). All services hang off `AppState` (god object).
- Load project state: `project_festivair.md` for current branch status.

## Landmines
- **`joinCode` is the universal discriminator.** Used by Haven `squad_filter`, ChatViewModel, PeerTracker. ALL THREE must agree. Missing UserDefaults write at squad join = silent message drop everywhere.
- **`squadId` vs `joinCode` confusion.** ChatMessage.squadId = local SwiftData UUID. MeshMessagePayload.squadId is REPURPOSED (emoji in heartbeats, joinCode in chat). MeshMessagePayload.joinCode is the actual routing key. Three different identifiers, all called "squad" — see header comment in `Models/ChatMessage.swift`. Still NOT renamed because the wire-protocol field name is shared with Haven; lockstep iOS+Python rename required.
- **V2 envelope shape ≠ V1.** V2 puts `version`, `type`, `payload`, and `squadId` at the envelope top level (no nested `message`, no `joinCode`). Haven detects V2 by the `version` field — see `protocol.py::is_v2_envelope`. Keep `V2_VALID_MESSAGE_TYPES` (Python) in sync with `V2MessageType` (Swift).
- **`User.firebaseId` is also probably misnamed** (actually stores CloudKit user record ID), but was NOT renamed in the cleanup pass — only `Squad.firebaseId` was. Be cautious before refactoring further.

## Resolved (2026-05-02)
- ~~Hardcoded API key in app config~~ — `Info.plist` now uses build-setting placeholders for `FESTIVAIR_API_BASE_URL` and `FESTIVAIR_API_KEY`; unresolved placeholders are ignored at runtime.
- ~~`MeshEnvelope.isForMySquad` hardcoded string~~ — already uses `Constants.UserDefaultsKeys.currentSquadId`. Landmine note was stale.
- ~~`MeshCoordinator.setupV2()` not called from `start()`~~ — now invoked at end of `start()` (V2 components instantiate alongside V1; presencePulse runs concurrently with heartbeat).
- ~~V2 message types not in Haven whitelist~~ — Haven now dispatches by envelope `version`. `V2_VALID_MESSAGE_TYPES` whitelisted; `route_message` and squad assignment use envelope-level `squadId` for V2.
- ~~Haven auth bypass when `FESTIVAIR_AUTH_TOKEN` unset~~ — server now refuses to start (`SystemExit(1)`) and the per-connection check no longer silently allows empty tokens.
- ~~Background task double registration~~ — `MeshCoordinator.registerBackgroundTasks()` extension was dead code (zero callers); deleted. AppDelegate is the only registration site now.
- ~~`Squad.firebaseId` misnamed~~ — renamed to `cloudKitRecordId` with `@Attribute(originalName: "firebaseId")` to migrate existing SwiftData stores.
- ~~Haven `route_message` "broadcast on unknown squad" rule was unreachable~~ — server.py was assigning the squad BEFORE routing, so any joinCode/squadId in the envelope became a known (1-member) squad before routing checked it. Fixed by reordering to route-then-assign. Found by `pytest tests/test_server_integration.py::TestV1RoutingE2E::test_unknown_join_code_broadcasts`.

## Wire protocol (iOS ↔ Haven)
`[4 bytes big-endian uint32 length] + [UTF-8 JSON]` — both sides must match.

## Verify after changes
- iOS build: `xcodebuild -project FestivAir.xcodeproj -scheme FestivAir -configuration Release -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` (target zero warnings — confirmed clean state).
- iOS tests: `xcodebuild -project FestivAir.xcodeproj -scheme FestivAirTests -destination 'platform=iOS Simulator,id=<UUID>' test` — **DO NOT pass `CODE_SIGNING_ALLOWED=NO` for tests.** That flag strips the team-id prefix from `application-identifier`, and `AppState.init` calls `CloudKitService.shared` → `CKContainer.default()`, which throws an ObjC exception on launch and crashes the test runner before tests start. The default Apple Development signing works fine on the simulator. **Verified working 2026-05-02 on Mac mini: 25 tests pass in ~3s.** The `FestivAirTests` target was added 2026-05-02 via `scripts/add_test_target.rb` (idempotent, also re-syncs new test source files).
- Haven: `cd haven-node && .venv/bin/pytest` (83 tests, ~3s, includes V1/V2 routing E2E and auth fail-closed). Use `pytest -m "not integration"` for fast unit-only feedback. Run server live with `python -m relay.server`.

## Release tooling (added 2026-05-02)
fastlane is configured at `fastlane/Appfile` + `fastlane/Fastfile`. Three lanes:
- `fastlane beta` — auto-bumps to next available TF build number, archives, uploads to TestFlight
- `fastlane archive_only` — local archive only, no upload (use to test the build pipeline)
- `fastlane tf_build_number` — read-only, prints current TestFlight build number

ASC API key: `BYF7TNAA54` at `~/private_keys/AuthKey_BYF7TNAA54.p8` (mode 600, copied from iMac on 2026-05-02).
Issuer: `69a6de85-e2c7-47e3-e053-5b8c7c11a4d1`. Team: `8JZLCG9CS2`. Bundle: `com.festivair.app`.
Last verified TestFlight build: **45** (shipped 2026-05-03 from Mac mini via raw `xcodebuild archive` + `-exportArchive`; fastlane path also works).

The legacy manual flow in `~/.claude/skills/ios-release/SKILL.md` still works as a fallback. Prefer `fastlane beta` for routine ships.

Note: skill memory previously claimed root `ExportOptions.plist` had a stale team `K59N3U8X8K` — this is outdated. The file was already corrected to `8JZLCG9CS2` and works with fastlane out of the box.

## End of session
Update `architecture_festivair.md` if architecture changed. Update `project_festivair.md` if branch status / merge readiness changed.
