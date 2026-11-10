// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherIPC
import DroppyKit
import Foundation
import SwiftUI

/// Principal class instantiated by Droppy's bundle loader (`NSPrincipalClass`).
@objc(AETHERPrincipal)
public final class AETHERPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject {
        AetherDroplet()
    }
}

/// Droppy droplet bridging ephemeral OTP events from the local AETHER host over authenticated UDS.
@MainActor
public final class AetherDroplet: NSObject, HUDPresenting {
    public nonisolated static let id: DropletID = "aether"

    private var transport: AetherIPCClientTransport?
    private var host: DropletHost?
    private var eventTask: Task<Void, Never>?
    private var currentEventID: UUID?

    public override init() {
        super.init()
    }

    public func activate(host: DropletHost) throws {
        self.host = host
        host.log.info("AETHER droplet activating")

        let clientTransport = AetherIPCClientTransport(
            clientIdentifier: "iordv.Droppy",
            serverValidator: AetherHostPeerValidator()
        )
        self.transport = clientTransport

        eventTask = Task { @MainActor [weak self, clientTransport] in
            await clientTransport.startAutoReconnect(retryInterval: 1.0)

            for await payload in clientTransport.payloads {
                guard let self, !Task.isCancelled else { break }
                self.presentOTPCard(payload: payload)
            }
        }

        host.log.info("AETHER droplet activated")
    }

    public func deactivate() {
        host?.log.info("AETHER droplet deactivating")
        if let currentEventID {
            host?.hud.dismiss(id: Self.hudIdentifier(for: currentEventID))
            self.currentEventID = nil
        }
        eventTask?.cancel()
        eventTask = nil

        let activeTransport = transport
        transport = nil
        Task {
            await activeTransport?.stop()
        }

        host = nil
    }

    private static func hudIdentifier(for eventID: UUID) -> String {
        "aether.otp.\(eventID.uuidString)"
    }

    private func presentOTPCard(payload: AetherOTPPayload) {
        guard let host else { return }

        currentEventID = payload.eventID
        let code = payload.otpCode
        let service = payload.serviceLabel
        let eventID = payload.eventID
        let hudID = Self.hudIdentifier(for: eventID)
        let canCopy = host.isGranted(.clipboardWrite)

        // Notify the host that the verification code was presented.
        sendAcknowledgment(eventID: eventID, status: .displayed)

        // Clamp duration to Droppy's 30-second HUD fairness bound while respecting expiry.
        let duration = max(5.0, min(30.0, payload.expiresAt.timeIntervalSinceNow))

        let request = DropletHUDRequest(
            id: hudID,
            duration: duration,
            priority: .normal,
            accessibilityLabel: "\(service) verification code",
            isExpanded: true,
            expandedContentHeight: 108
        ) {
            // Compact strip: icon at left wing, code at right wing, center clear around camera cutout.
            HStack(spacing: 0) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                Spacer(minLength: 0)
                Text(verbatim: code)
                    .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        } expanded: { [weak self] in
            AetherOTPHUDCardView(
                service: service,
                code: code,
                canCopy: canCopy,
                onCopy: { self?.copyCodeAndDismiss(code, eventID: eventID) },
                onDismiss: { self?.dismissHUD(eventID: eventID) }
            )
        }

        _ = host.hud.present(request)
        host.log.info("Presented verification code HUD")
    }

    private func copyCodeAndDismiss(_ code: String, eventID: UUID) {
        guard let host else { return }
        if host.workspace.copyToPasteboard(code) {
            host.log.info("Copied verification code to pasteboard")
            sendAcknowledgment(eventID: eventID, status: .copied)
        } else {
            host.log.notice("Pasteboard copy refused (missing clipboard-write capability)")
        }
        dismissHUD(eventID: eventID)
    }

    private func dismissHUD(eventID: UUID) {
        host?.hud.dismiss(id: Self.hudIdentifier(for: eventID))
        if currentEventID == eventID {
            currentEventID = nil
        }
    }

    private func sendAcknowledgment(eventID: UUID, status: AetherAcknowledgmentStatus) {
        guard let activeTransport = transport else { return }
        Task {
            if let ack = try? AetherOTPAcknowledgment(eventID: eventID, status: status) {
                try? await activeTransport.sendAcknowledgment(ack)
            }
        }
    }
}

private struct AetherOTPHUDCardView: View {
    let service: String
    let code: String
    let canCopy: Bool
    let onCopy: @MainActor @Sendable () -> Void
    let onDismiss: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            HStack(alignment: .center, spacing: DroppySpacing.xs) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: service)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .lineLimit(1)
                    Text(verbatim: "Verification code")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: DroppySpacing.xs)

                Text(verbatim: code)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(spacing: DroppySpacing.xs) {
                if canCopy {
                    Button(action: onCopy) {
                        Text(verbatim: "Copy Code")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                }

                Button(action: onDismiss) {
                    Text(verbatim: "Dismiss")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
