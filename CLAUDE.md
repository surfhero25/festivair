# FestivAir

Festival squad tracking app. iOS (SwiftUI + SwiftData + MultipeerConnectivity) + Python TCP relay (`haven-node/`, despite the name it's Python asyncio, NOT Node.js).

**Backend:** Hostinger VPS at http://187.124.249.219:8080 (vendor portal + AI event monitor)
**Branch:** `feature/protocol-v2-security` (36 commits, tested on device, NOT yet merged to main)
**SPM deps:** sentry-cocoa (added 2026-04-27 for crash + performance reporting). Otherwise all Apple system frameworks.

## Always do first
- Load architecture map: `architecture_festivair.md` (in memory). All services hang off `AppState` (god object).
- Load project state: `project_festivair.md` for current branch status.

## Landmines
- **V2 message types are NOT in Haven's whitelist.** V2 messages sent through the relay are rejected. V2 works peer-to-peer only until Haven is updated.
- **`MeshCoordinator.setupV2()` exists but is NOT called from `start()`.** V2 components are nil at runtime — wiring incomplete.
- **`joinCode` is the universal discriminator.** Used by Haven `squad_filter`, ChatViewModel, PeerTracker. ALL THREE must agree. Missing UserDefaults write at squad join = silent message drop everywhere.
- **`MeshEnvelope.isForMySquad` reads UserDefaults with the HARDCODED string "FestivAir.CurrentSquadId"**, not Constants. Renaming the constant doesn't fix this — grep for the literal.
- **`squadId` vs `joinCode` confusion.** ChatMessage.squadId = local SwiftData UUID. MeshMessagePayload.squadId is REPURPOSED (emoji in heartbeats, joinCode in chat). MeshMessagePayload.joinCode is the actual routing key. Three different identifiers, all called "squad".
- **`Squad.firebaseId` is misnamed** — actually stores CloudKit record ID.
- **Haven auth bypass:** if `FESTIVAIR_AUTH_TOKEN` env var is unset, server skips auth entirely. Verify before deploying.
- **Hardcoded API key** in `FestivAirAPIService.swift` line 13 — violates env var rule, needs to move.
- **Background task double registration** — both AppDelegate and MeshCoordinator register the same BGTasks IDs. Second registration silently ignored.

## Wire protocol (iOS ↔ Haven)
`[4 bytes big-endian uint32 length] + [UTF-8 JSON]` — both sides must match.

## Verify after changes
- iOS: build Release in Xcode (target zero warnings — confirmed clean state).
- Haven: `cd haven-node && python -m relay.server` for local test.

## End of session
Update `architecture_festivair.md` if architecture changed. Update `project_festivair.md` if branch status / merge readiness changed.
