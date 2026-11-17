// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

struct ConnectedAccountRow: View {
    let account: MailAccount
    @ObservedObject var model: AetherAppModel
    let onEdit: () -> Void
    var onSignInAgain: (() -> Void)? = nil

    @State private var showForgetConfirmation = false
    @State private var errorMessage: String?

    private var status: SourceStatus {
        model.status[account.id.uuidString] ?? (account.enabled ? .live : .off)
    }

    private var statusText: String {
        if !account.enabled {
            return "Paused"
        }
        let credState = account.credentialState(in: model.secrets)
        if credState.isLocked {
            return "Connecting…"
        }
        if status.needsSignIn || credState == .missing {
            return "Needs sign-in"
        }
        switch status {
        case .live, .connecting:
            return "Watching"
        case .off:
            return "Paused"
        case .attention(let s), .failed(let s):
            return s
        }
    }

    private var statusColor: Color {
        if !account.enabled {
            return .secondary
        }
        let credState = account.credentialState(in: model.secrets)
        if credState.isLocked {
            return .secondary
        }
        if status.needsSignIn || credState == .missing {
            return .orange
        }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: DroppySpacing.md) {
                providerIcon
                    .frame(width: 20, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.user)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Menu {
                    Button(account.enabled ? "Stop watching" : "Resume watching") {
                        var updated = account
                        updated.enabled.toggle()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            model.save(updated)
                        }
                    }

                    Button("Edit account…") {
                        onEdit()
                    }

                    if (status.needsSignIn || !account.hasCredential(in: model.secrets)) && !account.credentialState(in: model.secrets).isLocked {
                        Button("Sign in again") {
                            (onSignInAgain ?? onEdit)()
                        }
                    }

                    Divider()

                    Button("Forget this account…", role: .destructive) {
                        showForgetConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More actions for \(account.user)")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 20 + DroppySpacing.md)
            }
        }
        .padding(.horizontal, DroppySettingsLayoutMetrics.rowPadding)
        .padding(.vertical, DroppySettingsLayoutMetrics.rowVerticalPadding)
        .opacity(account.enabled ? 1.0 : 0.65)
        .confirmationDialog(
            "Forget \(account.user)?",
            isPresented: $showForgetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget account", role: .destructive) {
                do {
                    errorMessage = nil
                    try withAnimation(.easeInOut(duration: 0.25)) {
                        try model.forgetAccount(account)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AETHER will stop watching this mailbox and remove its sign-in from this Mac. You can add it again at any time.")
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        if account.isGmail {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.red)
        } else if account.isOutlook {
            Image(systemName: "envelope.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.blue)
        } else if account.host.lowercased().contains("icloud") {
            Image(systemName: "icloud.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.cyan)
        } else if account.host.lowercased().contains("yahoo") {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.purple)
        } else {
            Image(systemName: "server.rack")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary)
        }
    }
}

