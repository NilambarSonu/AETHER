import DroppyKit
import Foundation
import SwiftUI

@objc(AetherPrincipal)
public final class AetherPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject {
        AetherDroplet()
    }
}

public final class AetherDroplet: NSObject, Droplet {
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
        host.log.info("Aether droplet activating...")

        let clientTransport = AetherIPCClientTransport(
            clientIdentifier: "iordv.Droppy",
            serverValidator: AetherHostPeerValidator()
        )
        self.transport = clientTransport

        eventTask = Task { @MainActor [weak self, host, clientTransport] in
            await clientTransport.startAutoReconnect(retryInterval: 1.0)

            for await payload in clientTransport.payloads {
                guard let self else { break }
                self.presentOTPCard(payload: payload, host: host, transport: clientTransport)
            }
        }

        host.log.info("Aether droplet activated successfully")
    }

    @MainActor
    private func presentOTPCard(payload: AetherOTPPayload, host: DropletHost, transport: AetherIPCClientTransport) {
        self.currentEventID = payload.eventID
        let code = payload.otpCode
        let service = payload.serviceLabel
        let eventID = payload.eventID

        // 1. Send .displayed acknowledgment to host
        Task {
            if let ack = try? AetherOTPAcknowledgment(eventID: eventID, status: .displayed) {
                try? await transport.sendAcknowledgment(ack)
            }
        }

        // 2. Configure HUD Card with Copy action
        let card = DropletHUDCard(
            title: "\(service) Code",
            message: code,
            systemImage: "lock.shield.fill",
            tint: .blue,
            actions: [
                DropletHUDAction(id: "copy", title: "Copy", isPrimary: true) { [weak self, host, code, eventID, transport] in
                    _ = host.workspace.copyToPasteboard(code)
                    host.log.info("Aether droplet copied code to pasteboard")
                    Task {
                        if let ack = try? AetherOTPAcknowledgment(eventID: eventID, status: .copied) {
                            try? await transport.sendAcknowledgment(ack)
                        }
                    }
                    if let self {
                        self.host?.hud.dismiss(id: "aether.otp.\(eventID.uuidString)")
                    }
                }
            ]
        )

        let duration = max(5.0, min(60.0, payload.expiresAt.timeIntervalSinceNow))
        let request = DropletHUDRequest(
            id: "aether.otp.\(eventID.uuidString)",
            duration: duration,
            priority: .high,
            accessibilityLabel: "\(service) verification code \(code)",
            card: card,
            isExpanded: true
        ) {
            Image(systemName: "key.fill")
        } trailing: {
            Text(verbatim: code)
        }

        _ = host.hud.present(request)
        host.log.info("Aether droplet presented HUD card for event")
    }

    public func deactivate() {
        host?.log.info("Aether droplet deactivating...")
        if let currentEventID {
            host?.hud.dismiss(id: "aether.otp.\(currentEventID.uuidString)")
            self.currentEventID = nil
        }
        eventTask?.cancel()
        eventTask = nil

        let t = transport
        transport = nil
        Task {
            await t?.stop()
        }

        host = nil
    }
}
