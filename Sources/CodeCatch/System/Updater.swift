import Foundation
import Sparkle

/// Sparkle: checks the appcast at SUFeedURL (Info.plist) daily and installs updates signed
/// with the EdDSA key behind SUPublicEDKey. scripts/install.sh --release writes the appcast.
@MainActor enum Updater {
    /// Nil in an unbundled build (swift run, tests): there is no feed to check.
    static let controller: SPUStandardUpdaterController? =
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") == nil
        ? nil
        : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
    private static let delegate = UpdaterDelegate()
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// The downloaded update's install, while its update cycle lasts.
    private var install: (() -> Void)?
    private var lockObserver: NSObjectProtocol?

    /// A menu bar app is rarely quit, so an update left for quit could wait weeks. It installs and
    /// relaunches when the screen locks instead: CodeCatch locks itself then and nobody sees it.
    /// Codes are read again from the sources at launch, so the relaunch loses none.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock install: @escaping () -> Void) -> Bool {
        self.install = install
        if AppModel.screenIsLocked {
            installNow()
        } else if lockObserver == nil {
            lockObserver = DistributedNotificationCenter.default().addObserver(
                forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
            ) { [weak self] _ in self?.installNow() }
        }
        return true
    }

    /// An aborted install ends its cycle; a later update brings its own install.
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) { install = nil }

    private func installNow() {
        guard let install else { return }
        // The 90-second clear runs in this process, so it would not survive the relaunch.
        if Prefs[Prefs.clearClipboard] { Clipboard.clearIfOurs() }
        install()
    }
}
