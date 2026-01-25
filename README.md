# FestivAir

EDM Festival Squad Tracker with Offline Mesh Networking

## Features

- **Squad Location Sharing** - See your friends on the map in real-time
- **Works Offline** - Mesh networking via Bluetooth + WiFi, no cell service needed
- **Gateway Sync** - One phone with service syncs the whole squad to iCloud
- **Set Time Tracker** - Never miss your favorite artists
- **Squad Chat** - Message your crew without cell service

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Apple Developer Account (for CloudKit)

## Setup

### 1. Open in Xcode

Create a new iOS App project or open existing:
- Product Name: `FestivAir`
- Bundle Identifier: `com.festivair.app`
- Interface: SwiftUI
- Storage: SwiftData

### 2. Add Source Files

Drag all folders from this directory into Xcode:
- `App/`
- `Models/`
- `Services/`
- `ViewModels/`
- `Views/`
- `Utilities/`
- `Resources/`

### 3. Configure Signing & Capabilities

Add these capabilities in Xcode:

1. **iCloud**
   - Enable CloudKit
   - Container: `iCloud.com.festivair.app`

2. **Background Modes**
   - Location updates
   - Background fetch
   - Remote notifications
   - Uses Bluetooth LE accessories
   - Acts as a Bluetooth LE accessory
   - Background processing

3. **Push Notifications**

4. **App Groups**
   - `group.com.festivair.app`

### 4. Add Swift Packages (Optional)

For QR code scanning, add:
- `https://github.com/twostraws/CodeScanner`

### 5. Configure Info.plist

Copy entries from `Resources/Info.plist` or add manually:
- Location permissions (When In Use + Always)
- Bluetooth permissions
- Local Network permission
- Camera permission (for QR scanning)
- Background modes
- URL schemes (`festivair`)

### 6. Build & Run

Build for a real device (mesh networking doesn't work in Simulator).

## Architecture

```
App/
├── FestivAirApp.swift      # App entry point
├── AppDelegate.swift       # Push notifications, background tasks
Models/
├── User.swift              # User model with location
├── Squad.swift             # Squad with members
├── Event.swift             # Festival events
├── SetTime.swift           # Artist set times
├── ChatMessage.swift       # Chat + mesh message types
Services/
├── MeshNetworkManager.swift    # Multipeer Connectivity
├── MeshCoordinator.swift       # Orchestrates mesh + sync
├── LocationManager.swift       # GPS location
├── GatewayManager.swift        # Gateway election
├── CloudKitService.swift       # iCloud sync
├── SyncEngine.swift            # Offline queue
├── NotificationManager.swift   # Push notifications
├── PeerTracker.swift           # Track peer status
ViewModels/
├── SquadViewModel.swift        # Squad CRUD
├── ChatViewModel.swift         # Chat messages
├── MapViewModel.swift          # Map annotations
├── SetTimesViewModel.swift     # Lineup management
Views/
├── ContentView.swift           # Root view + tabs
├── Onboarding/                 # Welcome flow
├── Squad/                      # Map, members, chat
├── SetTimes/                   # Lineup browser
├── Settings/                   # User preferences
```

## How It Works

### Mesh Networking

Uses Apple's Multipeer Connectivity framework:
- Combines Bluetooth LE + peer-to-peer WiFi
- Auto-discovers squad members nearby
- Relays messages through intermediate devices (3 hops max)
- Works without any internet connection

### Gateway Election

Every 30 seconds, devices broadcast their signal strength:
1. Phone with best cellular signal becomes gateway
2. Gateway syncs pending changes to CloudKit
3. Gateway pushes cloud updates back to mesh
4. If gateway loses signal, next-best takes over
5. Battery-aware: rotates if gateway drops below 30%

### Offline-First

All data stored locally in SwiftData:
- Location updates queued when offline
- Messages cached and synced later
- Last-write-wins for locations
- Merge strategy for favorites

## Testing

### Real Device Required

Mesh networking only works on physical devices:
1. Deploy to 2+ iPhones
2. Put devices in Airplane Mode
3. Enable WiFi and Bluetooth
4. Create/join same squad
5. Watch location updates propagate

### Test Scenarios

- Squad creation and QR code join
- Location sharing with all devices offline
- Gateway handoff when signal changes
- Chat messages via mesh relay
- Set time notifications

## Monetization

Built-in freemium model:
- Free: Up to 4 squad members
- Premium ($2.99/event): Up to 12 members
- Future: Festival partnerships, sponsored stages

## License

MIT
