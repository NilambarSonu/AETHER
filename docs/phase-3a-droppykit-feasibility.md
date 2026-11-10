# AETHER Phase 3A — DroppyKit SDK Feasibility & Capability Investigation

## 1. Executive Summary

This investigation independently validates the integration feasibility between AETHER and DroppyKit. Findings are derived from direct reverse engineering and symbol inspection of the live Droppy installation at `/Applications/Droppy.app`, its embedded framework `/Applications/Droppy.app/Contents/Frameworks/DroppyKit.framework`, and active community droplets installed in `~/Library/Application Support/Droppy/Droplets/`.

**Verdict: HIGHLY FEASIBLE.**  
DroppyKit provides native APIs for ephemeral Notch HUD cards (`DropletHUDCard`), action buttons (`DropletHUDAction`), auto-dismiss timers (`duration:`), and unsandboxed clipboard access (`clipboardWrite`), with lifecycle callbacks (`activate` / `deactivate`).

---

## 2. Capability Matrix

| Capability | SDK Evidence (Direct Inspection) | Feasible? | Technical Limitations / Constraints |
|---|---|---|---|
| **In-Process Droplet Execution** | Droplets compile to Mach-O universal `MH_DYLIB` (`file <Droplet>`), loaded by `Droppy.app` via `dlopen`. | `VERIFIED` | Droplet crashes will terminate `Droppy.app`. Heavy computation blocks Droppy's UI thread. |
| **External Process Communication** | `Droppy.app` entitlement `com.apple.security.app-sandbox: false`. Unrestricted POSIX Unix Domain Sockets and Mach ports. | `VERIFIED` | Must authenticate peer to prevent local spoofing or unauthorized message injection. |
| **OTP Card Presentation** | `DropletHUDService.present(DropletHUDRequest)` with `DropletHUDCard(title:message:systemImage:tint:progress:actions:)`. | `VERIFIED` | Content rendered in Droppy's dynamic notch overlay. Card width and height governed by Notch metrics. |
| **Asynchronous Event Delivery** | Swift Concurrency runtime and libdispatch linked. Droplet can maintain background async tasks and event loops. | `VERIFIED` | Tasks must be explicitly cancelled on `deactivate()` to avoid memory/thread leaks. |
| **Auto-Dismiss Behavior** | `DropletHUDRequest.duration: Double?` and `DropletHUDService.dismiss(id: String)`. | `VERIFIED` | Native auto-dismiss supported out-of-the-box by Droppy's HUD scheduler. |
| **Clipboard Interaction** | Declared capability `DropletPermission.clipboardWrite`. Unsandboxed access to `NSPasteboard.general`. | `VERIFIED` | Writing to clipboard must remain strictly user-authorized or follow configured preferences. |
| **Lifecycle Callbacks** | `Droplet` protocol: `activate(host: DropletHost)` and `deactivate()`. Principal class: `makeDroplet()`. | `VERIFIED` | `deactivate()` must immediately close IPC socket and tear down UI subscriptions. |
| **Settings Pane UI** | `SettingsPaneProviding.makeSettingsPane(context:) -> SwiftUI.AnyView`. | `VERIFIED` | Embedded inside Droppy's unified Settings window. |

---

## 3. SDK Architecture & Object Model

### 3.1 Droplet Bundle Architecture
Community and official droplets adhere to the standard macOS bundle structure:
```
Aether.droplet/
└── Contents/
    ├── Info.plist                     # Declares NSPrincipalClass, CFBundleIdentifier, DroppyKit ABI
    ├── MacOS/
    │   └── Aether                     # Mach-O dynamic library (MH_DYLIB) linked against DroppyKit
    └── Resources/
        ├── droplet.json               # Manifest (id, capabilities, surfaces, minAPI, creator)
        ├── Aether.icon/               # Liquid glass / SVG / PNG droplet icons
        └── Assets.car                 # Compiled asset catalog
```

### 3.2 Key DroppyKit Protocols & Interfaces (Demangled)

#### 1. Entry Point & Lifecycle:
```swift
public protocol Droplet: AnyObject {
    static var id: DropletID { get }
    func activate(host: DropletHost) throws
    func deactivate()
}
```

#### 2. HUD Presentation Service:
```swift
public protocol DropletHUDService {
    func present(_ request: DropletHUDRequest) -> Bool
    func dismiss(id: String)
}

public struct DropletHUDRequest {
    public init<Content: View, Expanded: View>(
        id: String,
        duration: Double?,
        priority: DropletHUDPriority,
        accessibilityLabel: String,
        card: DropletHUDCard,
        isExpanded: Bool,
        leading: @MainActor @Sendable () -> Content,
        trailing: @MainActor @Sendable () -> Expanded
    )
}

public struct DropletHUDCard {
    public init(
        title: String,
        message: String?,
        systemImage: String?,
        tint: SwiftUI.Color?,
        progress: Double?,
        actions: [DropletHUDAction]
    )
}

public struct DropletHUDAction {
    public init(
        id: String?,
        title: String,
        isPrimary: Bool,
        perform: @MainActor @Sendable () -> Void
    )
}
```

---

## 4. DroppyKit Manifest (`droplet.json`) Specification

To register with Droppy, `AetherDroplet` must define a valid `droplet.json`:
```json
{
  "id": "aether-otp",
  "name": "AETHER OTP",
  "version": "1.0.0",
  "summary": "Instant verification codes in your notch",
  "description": "Displays incoming email and message OTP verification codes directly in Droppy's notch HUD with one-click clipboard copy.",
  "category": "Productivity",
  "kit": {
    "abi": 1,
    "minAPI": "1.9.0"
  },
  "minAppVersion": "15.3.0",
  "minMacOS": "15.0",
  "capabilities": [
    "hud",
    "clipboard-write"
  ],
  "surfaces": [
    "hud",
    "settings-pane"
  ],
  "icon": "Aether.icon",
  "creator": {
    "name": "Nilambar Behera",
    "kind": "community",
    "url": "https://github.com/NilambarSonu/AETHER"
  },
  "keywords": ["otp", "2fa", "verification", "email", "messages", "security"]
}
```

---

## 5. Feasibility Verdict & Constraints

1. **Feasible Without Workarounds:** DroppyKit provides every primitive necessary to present verification codes in the notch, handle copy actions, and dismiss on timeout.
2. **Strict Boundary Rule:** `AetherDroplet` must **not** attempt to inspect mail databases, parse MIME emails, or poll sockets on its own. It acts purely as a presentation projection for the AETHER host process.
