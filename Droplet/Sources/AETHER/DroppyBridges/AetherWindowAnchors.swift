// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import AppKit
import SwiftUI

/// Holds a weak reference to the active Droppy Settings window for OAuth sheets without scanning `NSApp.windows`.
@MainActor
public final class AetherWindowAnchorStore {
    public static let shared = AetherWindowAnchorStore()
    public weak var settingsWindow: NSWindow?
    private init() {}
}

/// Captures the hosting `NSWindow` of the SwiftUI Settings view so `ASWebAuthenticationSession` attaches smoothly.
public struct AetherWindowAnchorReader: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> AnchorProbeView {
        AnchorProbeView()
    }

    public func updateNSView(_ nsView: AnchorProbeView, context: Context) {
        if let window = nsView.window {
            AetherWindowAnchorStore.shared.settingsWindow = window
        }
    }

    public final class AnchorProbeView: NSView {
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                AetherWindowAnchorStore.shared.settingsWindow = window
            }
        }
    }
}

/// Applies `window.sharingType = .none` only while a sensitive AETHER surface displaying unmasked
/// plaintext codes is mounted, restoring the window's prior `sharingType` on unmount.
public struct AetherScopedCaptureGuard: NSViewRepresentable {
    let hideFromCapture: Bool

    public init(hideFromCapture: Bool) {
        self.hideFromCapture = hideFromCapture
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> GuardView {
        let view = GuardView()
        view.coordinator = context.coordinator
        return view
    }

    public func updateNSView(_ nsView: GuardView, context: Context) {
        nsView.apply(hide: hideFromCapture, coordinator: context.coordinator)
    }

    public static func dismantleNSView(_ nsView: GuardView, coordinator: Coordinator) {
        coordinator.restore()
    }

    @MainActor
    public final class Coordinator {
        private weak var trackedWindow: NSWindow?
        private var originalSharingType: NSWindow.SharingType?

        func attach(to window: NSWindow?, hide: Bool) {
            guard let window else { return }
            if trackedWindow !== window {
                restore()
                trackedWindow = window
                originalSharingType = window.sharingType
            }
            if hide {
                if window.sharingType != .none {
                    window.sharingType = .none
                }
            } else if let original = originalSharingType {
                window.sharingType = original
            }
        }

        func restore() {
            if let window = trackedWindow, let original = originalSharingType {
                window.sharingType = original
            }
            trackedWindow = nil
            originalSharingType = nil
        }
    }

    public final class GuardView: NSView {
        weak var coordinator: Coordinator?

        func apply(hide: Bool, coordinator: Coordinator) {
            self.coordinator = coordinator
            coordinator.attach(to: window, hide: hide)
        }

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                coordinator?.restore()
            }
        }
    }
}

extension View {
    /// Protects views revealing plaintext verification codes from screen capture when enabled.
    func aetherCaptureProtected(_ enabled: Bool) -> some View {
        background(AetherScopedCaptureGuard(hideFromCapture: enabled))
    }
}
