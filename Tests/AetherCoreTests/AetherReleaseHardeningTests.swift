// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CryptoKit
import Darwin
import Foundation
import Testing

@Suite("Aether Release Hardening Tests")
struct AetherReleaseHardeningTests {
    private static func repoRoot() throws -> URL {
        let fromFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: fromFile.appendingPathComponent("Package.swift").path) {
            return fromFile
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("Package.swift").path) {
            return cwd
        }
        throw NSError(domain: "AetherReleaseHardeningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot locate repo root"])
    }

    private static func runExecutable(
        _ executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment {
            env[k] = v
        }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func inode(of path: String) throws -> ino_t {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return st.st_ino
    }

    private static func buildTestUniversalBundle(
        in tempRoot: URL,
        name: String,
        markerVersionString: String,
        repoRoot: URL
    ) throws -> URL {
        let workDir = tempRoot.appendingPathComponent(name)
        let fmwkA = workDir.appendingPathComponent("Frameworks/DroppyKit.framework/Versions/A")
        let bundle = workDir.appendingPathComponent("AETHER.droplet")
        let macOSDir = bundle.appendingPathComponent("Contents/MacOS")
        let resourcesDir = bundle.appendingPathComponent("Contents/Resources")

        try FileManager.default.createDirectory(at: fmwkA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        let fmwkSrc = workDir.appendingPathComponent("DroppyKitStub.swift")
        let dropletSrc = workDir.appendingPathComponent("AetherStub.swift")
        try "public func _testMarker() -> Int { 1 }\n".write(to: fmwkSrc, atomically: true, encoding: .utf8)
        try "import DroppyKit\npublic func aetherVersionTag() -> String { _ = _testMarker(); return \"\(markerVersionString)\" }\n"
            .write(to: dropletSrc, atomically: true, encoding: .utf8)

        let fmwkBinary = fmwkA.appendingPathComponent("DroppyKit").path
        var fmwkSlices: [String] = []
        var modSlices: [String] = []
        for arch in ["arm64", "x86_64"] {
            let dylib = workDir.appendingPathComponent("DroppyKit-\(arch).dylib").path
            let swiftmodDir = workDir.appendingPathComponent("mod-\(arch)")
            try FileManager.default.createDirectory(at: swiftmodDir, withIntermediateDirectories: true)
            let res = try runExecutable(
                "/usr/bin/swiftc",
                arguments: [
                    "-parse-as-library", "-emit-library", "-emit-module",
                    "-enable-library-evolution",
                    "-emit-module-path", swiftmodDir.appendingPathComponent("DroppyKit.swiftmodule").path,
                    "-target", "\(arch)-apple-macos15.0",
                    "-module-name", "DroppyKit",
                    "-Xlinker", "-install_name", "-Xlinker", "@rpath/DroppyKit.framework/Versions/A/DroppyKit",
                    "-o", dylib,
                    fmwkSrc.path,
                ]
            )
            #expect(res.status == 0, "Test fixture DroppyKit compile failed: \(res.output)")
            fmwkSlices.append(dylib)
            modSlices.append(swiftmodDir.path)
        }
        let lipoFmwk = try runExecutable("/usr/bin/lipo", arguments: ["-create"] + fmwkSlices + ["-output", fmwkBinary])
        #expect(lipoFmwk.status == 0)

        try FileManager.default.createSymbolicLink(atPath: workDir.appendingPathComponent("Frameworks/DroppyKit.framework/Versions/Current").path, withDestinationPath: "A")
        try FileManager.default.createSymbolicLink(atPath: workDir.appendingPathComponent("Frameworks/DroppyKit.framework/DroppyKit").path, withDestinationPath: "Versions/Current/DroppyKit")

        var dropletSlices: [String] = []
        for (idx, arch) in ["arm64", "x86_64"].enumerated() {
            let sliceOut = workDir.appendingPathComponent("AETHER-\(arch).dylib").path
            let res = try runExecutable(
                "/usr/bin/swiftc",
                arguments: [
                    "-parse-as-library", "-emit-library",
                    "-enable-library-evolution",
                    "-target", "\(arch)-apple-macos15.0",
                    "-module-name", "AETHER",
                    "-I", modSlices[idx],
                    "-F", workDir.appendingPathComponent("Frameworks").path,
                    "-framework", "DroppyKit",
                    "-Xlinker", "-install_name", "-Xlinker", "@rpath/AETHER",
                    "-o", sliceOut,
                    dropletSrc.path,
                ]
            )
            #expect(res.status == 0, "Test fixture AETHER compile failed: \(res.output)")
            dropletSlices.append(sliceOut)
        }
        let lipoDroplet = try runExecutable("/usr/bin/lipo", arguments: ["-create"] + dropletSlices + ["-output", macOSDir.appendingPathComponent("AETHER").path])
        #expect(lipoDroplet.status == 0)

        let manifestSrc = repoRoot.appendingPathComponent("Droplet/droplet.json")
        try FileManager.default.copyItem(at: manifestSrc, to: resourcesDir.appendingPathComponent("droplet.json"))

        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "AETHER",
            "CFBundleIdentifier": "app.getdroppy.droplet.aether",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "AETHER",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "2.0.0",
            "CFBundleVersion": "2.0.0",
            "NSPrincipalClass": "AETHERPrincipal",
            "DroppyDropletID": "aether",
            "DroppyKitABI": 1,
            "DroppyKitMinAPI": "1.23.0",
            "DroppyMinAppVersion": "16.2.0",
            "LSMinimumSystemVersion": "15.0",
            "DroppyPermissions": [
                "hud",
                "notch-banner",
                "menu-bar",
                "shelf-read",
                "shelf-write",
                "global-shortcuts",
                "network-client",
                "clipboard-write",
                "full-disk-access-probe",
                "accessibility",
                "sound-playback",
            ],
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        return bundle
    }

    @Test("Installer script never disables approval prompts or weakens preferences or uses stubs")
    func installerDoesNotWeakenPreferences() throws {
        let root = try Self.repoRoot()
        let scriptPath = root.appendingPathComponent("scripts/build-droplet.sh").path
        let content = try String(contentsOfFile: scriptPath, encoding: .utf8)

        #expect(!content.contains("defaults write"))
        #expect(!content.contains("askBeforeRunning"))
        #expect(!content.contains("droplet.aether.enabled"))
        #expect(!content.contains("rm -rf \"$TARGET_DIR/Aether.droplet\""))
        #expect(!content.contains("DroppyKitInterface"))
        #expect(!content.contains("STUB_SKELETON"))
    }

    @Test("Droplet build fails cleanly without stub fallback when official SDK unavailable and safely stages installs")
    func buildScriptRequiresOfficialSDKAndSafelyStagesInstalls() throws {
        let root = try Self.repoRoot()
        let scriptPath = root.appendingPathComponent("scripts/build-droplet.sh").path
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AetherHardening.\(UUID())")
        let installDir = tempDir.appendingPathComponent("install")
        let emptyPathDir = tempDir.appendingPathComponent("empty-path")
        try FileManager.default.createDirectory(at: emptyPathDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Building without official DroppyKit SDK fails cleanly with zero stub fallback
        let noSDK = try Self.runExecutable(
            "/bin/bash",
            arguments: [scriptPath],
            environment: [
                "PATH": emptyPathDir.path + ":/usr/bin:/bin",
                "HOME": tempDir.path,
                "DROPPYKIT_DIR": "",
                "DROPPYKIT_BIN": "",
                "DROPPYKIT_DISABLE_AUTO_DISCOVERY": "1",
            ]
        )
        #expect(noSDK.status != 0)
        #expect(noSDK.output.contains("no longer compiles or links against unofficial stub declarations"))

        // If a sibling official DroppyKit checkout exists on disk, ensure no stub fallback occurs even when CLT lacks Xcode
        let siblingDroppyKit = root.deletingLastPathComponent().appendingPathComponent("droppykit")
        if FileManager.default.fileExists(atPath: siblingDroppyKit.appendingPathComponent("Scripts/droppykit").path),
           !FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
        {
            let cltFail = try Self.runExecutable(
                "/bin/bash",
                arguments: [scriptPath],
                environment: ["DROPPYKIT_DIR": siblingDroppyKit.path]
            )
            #expect(cltFail.status != 0)
            #expect(!cltFail.output.contains("STUB_SKELETON"))
            #expect(cltFail.output.contains("Xcode 26") || cltFail.output.contains("Command Line Tools"))
        }

        // 2. Test safe staged installation, swap-failure rollback, and explicit --rollback with real universal bundles
        let bundleV1 = try Self.buildTestUniversalBundle(in: tempDir, name: "v1", markerVersionString: "1.0.0-v1", repoRoot: root)
        let bundleV2 = try Self.buildTestUniversalBundle(in: tempDir, name: "v2", markerVersionString: "1.0.0-v2", repoRoot: root)

        let baseEnv = ["AETHER_DROPLET_INSTALL_DIR": installDir.path]

        let install1 = try Self.runExecutable("/bin/bash", arguments: [scriptPath, "--install", "--bundle", bundleV1.path], environment: baseEnv)
        #expect(install1.status == 0, "Install v1 failed: \(install1.output)")
        #expect(install1.output.contains("User preferences were NOT modified"))
        #expect(install1.output.contains("Manual approval required"))

        let installedBinary = installDir.appendingPathComponent("AETHER.droplet/Contents/MacOS/AETHER").path
        let backupBinary = installDir.appendingPathComponent(".AETHER.droplet.previous/Contents/MacOS/AETHER").path
        let inodeV1 = try Self.inode(of: installedBinary)
        let dataV1 = try Data(contentsOf: URL(fileURLWithPath: installedBinary))

        // 3. Simulated swap failure rolls back and preserves exact v1 inode & bytes untouched
        var failEnv = baseEnv
        failEnv["AETHER_SIMULATE_INSTALL_SWAP_FAILURE"] = "1"
        let failedInstall = try Self.runExecutable("/bin/bash", arguments: [scriptPath, "--install", "--bundle", bundleV2.path], environment: failEnv)
        #expect(failedInstall.status != 0)
        #expect(failedInstall.output.contains("Rollback succeeded"))
        #expect(try Self.inode(of: installedBinary) == inodeV1)
        #expect(try Data(contentsOf: URL(fileURLWithPath: installedBinary)) == dataV1)

        // 4. Successful install v2 installs new binary and preserves v1 exact inode in .AETHER.droplet.previous
        let install2 = try Self.runExecutable("/bin/bash", arguments: [scriptPath, "--install", "--bundle", bundleV2.path], environment: baseEnv)
        #expect(install2.status == 0, "Install v2 failed: \(install2.output)")
        let inodeV2 = try Self.inode(of: installedBinary)
        #expect(inodeV2 != inodeV1)
        #expect(try Self.inode(of: backupBinary) == inodeV1)
        #expect(try Data(contentsOf: URL(fileURLWithPath: installedBinary)) != dataV1)

        // 5. Explicit --rollback replaces v2 with a verified copy of v1 while keeping backup intact
        let rollback = try Self.runExecutable("/bin/bash", arguments: [scriptPath, "--rollback"], environment: baseEnv)
        #expect(rollback.status == 0, "Rollback failed: \(rollback.output)")
        let inodeRestored = try Self.inode(of: installedBinary)
        #expect(inodeRestored != inodeV2)
        #expect(try Self.inode(of: backupBinary) == inodeV1)
        #expect(try Data(contentsOf: URL(fileURLWithPath: installedBinary)) == dataV1)
    }

    @Test("Droplet package complies with official DroppyKit manifest, source parity, and non-stub guarantees")
    func securityDocsManifestsAndIPCParityAreAccurate() throws {
        let root = try Self.repoRoot()

        // No unofficial stub files remain anywhere in Droplet/
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Droplet/DroppyKitInterface.swift").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Droplet/Aether/Info.plist").path))

        // Package.swift uses official DroppyKit dependency matching minAPI
        let pkgSwift = try String(contentsOf: root.appendingPathComponent("Droplet/Package.swift"), encoding: .utf8)
        #expect(pkgSwift.contains("https://gitlab.com/droppyformac1/droppykit.git"))
        #expect(pkgSwift.contains("from: \"1.23.0\""))
        #expect(pkgSwift.contains("\"CodeCatchCore\""))
        #expect(pkgSwift.contains("\"AetherEngine\""))
        #expect(pkgSwift.contains(".library(name: \"AETHER\", type: .dynamic, targets: [\"AETHER\"])"))

        // Manifest rules
        let manifestData = try Data(contentsOf: root.appendingPathComponent("Droplet/droplet.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        #expect(manifest?["id"] as? String == "aether")
        #expect(manifest?["name"] as? String == "AETHER")
        #expect(manifest?["version"] as? String == "2.2.0")
        #expect((manifest?["summary"] as? String ?? "").count <= 60)
        #expect(manifest?["category"] as? String == "System")
        #expect(manifest?["minAppVersion"] as? String == "16.2.0")
        #expect(manifest?["minMacOS"] as? String == "15.0")
        #expect(manifest?["icon"] as? String == "AETHER.icon")

        let surfaces = Set(manifest?["surfaces"] as? [String] ?? [])
        #expect(surfaces.isSuperset(of: ["settings-pane", "menu-bar-extra", "shelf-widget", "live-activity", "hud"]))

        let capabilities = Set(manifest?["capabilities"] as? [String] ?? [])
        #expect(capabilities.isSuperset(of: ["hud", "notch-banner", "menu-bar", "global-shortcuts", "network-client", "clipboard-write", "full-disk-access-probe", "accessibility"]))

        let kit = manifest?["kit"] as? [String: Any]
        #expect(kit?["abi"] as? Int == 1)
        #expect(kit?["minAPI"] as? String == "1.23.0")

        let creator = manifest?["creator"] as? [String: Any]
        #expect(creator?["kind"] as? String == "community")
        #expect(creator?["avatar"] as? String == "aether.png")
        let avatarPath = root.appendingPathComponent("Droplet/Assets/aether.png")
        #expect(FileManager.default.fileExists(atPath: avatarPath.path))

        let source = manifest?["source"] as? [String: Any]
        #expect(source?["repository"] as? String == "https://github.com/NilambarSonu/AETHER")
        #expect(source?["license"] as? String == "GPL-3.0")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Droplet/LICENSE").path))

        // Droplet Swift implementation conforms to all standalone capabilities and embeds first-party AETHER OAuth IDs
        let dropletSrc = try String(contentsOf: root.appendingPathComponent("Droplet/Sources/AETHER/AetherDroplet.swift"), encoding: .utf8)
        let hudSrc = try String(contentsOf: root.appendingPathComponent("Droplet/Sources/AETHER/DroppyBridges/AetherHUDBridge.swift"), encoding: .utf8)
        let oauthSrc = try String(contentsOf: root.appendingPathComponent("Droplet/Sources/AetherEngine/Mail/MailOAuth.swift"), encoding: .utf8)
        #expect(!oauthSrc.contains("374242175460"))
        #expect(!oauthSrc.contains("946bd1c2"))
        #expect(!oauthSrc.contains("uros.codecatch"))
        #expect(oauthSrc.contains("210406503188-m2pr68n1e17pv3pmqnj1hv946r6lbg22.apps.googleusercontent.com"))
        #expect(oauthSrc.contains("3265c45a-7440-4992-aaf7-b176bb294c44"))
        #expect(dropletSrc.contains("HUDPresenting"))
        #expect(dropletSrc.contains("SettingsPagesProviding"))
        #expect(dropletSrc.contains("ShelfWidgetCompositionProviding"))
        #expect(dropletSrc.contains("MenuBarExtraProviding"))
        #expect(dropletSrc.contains("LiveActivityProviding"))
        #expect(dropletSrc.contains("MCPToolProviding"))
        #expect(hudSrc.contains("priority: .normal"))
        #expect(!dropletSrc.contains("priority: .high"))
        #expect(!hudSrc.contains("priority: .high"))
        #expect(!dropletSrc.contains("UserDefaults.standard"))

        // Synchronized AetherIPC sources match AetherCore byte-for-byte
        let syncedFiles = [
            "Protocol/AetherOTPPayload.swift",
            "Protocol/AetherOTPAcknowledgment.swift",
            "Protocol/AetherProtocolError.swift",
            "Codec/AetherFrameCodec.swift",
            "Codec/AetherFrameDecoder.swift",
            "Transport/AetherHandshake.swift",
            "Transport/AetherSocketEndpoint.swift",
            "Transport/AetherTransportError.swift",
            "Transport/AetherPeerAuthentication.swift",
            "Transport/AetherIPCClientTransport.swift",
        ]
        for rel in syncedFiles {
            let coreBytes = try Data(contentsOf: root.appendingPathComponent("Sources/AetherCore/\(rel)"))
            let ipcBytes = try Data(contentsOf: root.appendingPathComponent("Droplet/Sources/AetherIPC/\(rel)"))
            #expect(SHA256.hash(data: coreBytes) == SHA256.hash(data: ipcBytes), "Drift detected in \(rel)")
        }

        // Security disclosures stay accurate
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let architecture = try String(contentsOf: root.appendingPathComponent("ARCHITECTURE.md"), encoding: .utf8)
        let security = try String(contentsOf: root.appendingPathComponent("SECURITY.md"), encoding: .utf8)
        #expect(!readme.lowercased().contains("sandboxed plug-in"))
        #expect(!readme.lowercased().contains("zero disk or credential access"))
        #expect(readme.contains("shares Droppy's process address space"))
        #expect(architecture.contains("not an independent OS sandbox"))
        #expect(security.contains("Droppy.app` process"))

        // Verify Droplet/Package.resolved pins the exact official v1.23.0 commit
        let resolvedData = try Data(contentsOf: root.appendingPathComponent("Droplet/Package.resolved"))
        let resolved = try JSONSerialization.jsonObject(with: resolvedData) as? [String: Any]
        let pins = resolved?["pins"] as? [[String: Any]] ?? []
        let dkPin = try #require(pins.first { ($0["identity"] as? String) == "droppykit" })
        #expect(dkPin["location"] as? String == "https://gitlab.com/droppyformac1/droppykit.git")
        let dkState = dkPin["state"] as? [String: Any]
        #expect(dkState?["version"] as? String == "1.23.0")
        #expect(dkState?["revision"] as? String == "11e4869898bf13991120e26af347b9007521623b")
    }

    @Test("Installer rejects symlinks/traversal, preserves unrelated files across APFS casing, and distinguishes Playground")
    func installerSecuritySymlinkAndPlaygroundChecks() throws {
        let root = try Self.repoRoot()
        let scriptPath = root.appendingPathComponent("scripts/build-droplet.sh").path
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AetherSecurityInstall.\(UUID())")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let validBundle = try Self.buildTestUniversalBundle(in: tempDir, name: "valid", markerVersionString: "1.0.0", repoRoot: root)

        // 1. Escaping relative symlink inside bundle must fail validation
        let evilBundle = tempDir.appendingPathComponent("evil/AETHER.droplet")
        try FileManager.default.createDirectory(at: evilBundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: validBundle, to: evilBundle)
        try FileManager.default.createSymbolicLink(
            atPath: evilBundle.appendingPathComponent("Contents/Resources/escape").path,
            withDestinationPath: "../../../../etc/hosts"
        )
        let evilRes = try Self.runExecutable("/bin/bash", arguments: [scriptPath, "--validate-only", "--bundle", evilBundle.path])
        #expect(evilRes.status != 0)
        #expect(evilRes.output.contains("escaping relative symlink"))

        // 2. Symlinked TARGET_DIR and traversal path are rejected
        let realTarget = tempDir.appendingPathComponent("real-target")
        try FileManager.default.createDirectory(at: realTarget, withIntermediateDirectories: true)
        let symlinkTarget = tempDir.appendingPathComponent("symlink-target")
        try FileManager.default.createSymbolicLink(atPath: symlinkTarget.path, withDestinationPath: realTarget.path)

        let symInstall = try Self.runExecutable(
            "/bin/bash",
            arguments: [scriptPath, "--install", "--bundle", validBundle.path],
            environment: ["AETHER_DROPLET_INSTALL_DIR": symlinkTarget.path]
        )
        #expect(symInstall.status != 0)
        #expect(symInstall.output.contains("Refusing symlinked"))

        let travInstall = try Self.runExecutable(
            "/bin/bash",
            arguments: [scriptPath, "--install", "--bundle", validBundle.path],
            environment: ["AETHER_DROPLET_INSTALL_DIR": tempDir.path + "/../escape"]
        )
        #expect(travInstall.status != 0)
        #expect(travInstall.output.contains("traversal"))

        // 3. Unrelated files survive alongside legacy Aether.droplet casing replacement
        let apfsDir = tempDir.appendingPathComponent("apfs-dir")
        try FileManager.default.createDirectory(at: apfsDir, withIntermediateDirectories: true)
        let unrelated = apfsDir.appendingPathComponent("Other.droplet")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try "keep".write(to: unrelated.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        let legacyCase = apfsDir.appendingPathComponent("Aether.droplet")
        try FileManager.default.copyItem(at: validBundle, to: legacyCase)

        let caseInstall = try Self.runExecutable(
            "/bin/bash",
            arguments: [scriptPath, "--install", "--bundle", validBundle.path],
            environment: ["AETHER_DROPLET_INSTALL_DIR": apfsDir.path]
        )
        #expect(caseInstall.status == 0, "APFS casing install failed: \(caseInstall.output)")
        #expect(try String(contentsOf: unrelated.appendingPathComponent("marker.txt"), encoding: .utf8) == "keep")
        #expect(FileManager.default.fileExists(atPath: apfsDir.appendingPathComponent("AETHER.droplet/Contents/MacOS/AETHER").path))

        // 4. --playground vs default Droppy HOME destinations are distinct
        let fakeHome = tempDir.appendingPathComponent("fake-home")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let pgInstall = try Self.runExecutable(
            "/bin/bash",
            arguments: [scriptPath, "--install", "--playground", "--bundle", validBundle.path],
            environment: ["HOME": fakeHome.path]
        )
        #expect(pgInstall.status == 0, "Playground install failed: \(pgInstall.output)")
        #expect(FileManager.default.fileExists(atPath: fakeHome.appendingPathComponent("Library/Application Support/Droppy Playground/Droplets/aether/AETHER.droplet/Contents/Info.plist").path))
        #expect(!FileManager.default.fileExists(atPath: fakeHome.appendingPathComponent("Library/Application Support/Droppy/Droplets/aether/AETHER.droplet").path))
    }

    @Test("Distribution staging and ZIP round-trip place AETHER.droplet and README-TESTING.md cleanly at root")
    func dropletDistributionZipLayoutMatchesOfficialSpec() throws {
        let root = try Self.repoRoot()
        let scriptPath = root.appendingPathComponent("scripts/build-droplet.sh").path
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AetherZipStage.\(UUID())")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let validBundle = try Self.buildTestUniversalBundle(in: tempDir, name: "dist-src", markerVersionString: "1.0.0", repoRoot: root)
        let distDir = tempDir.appendingPathComponent("dist")

        let stageRes = try Self.runExecutable(
            "/bin/bash",
            arguments: [scriptPath, "--stage-dist", distDir.path, "--bundle", validBundle.path]
        )
        #expect(stageRes.status == 0, "Staging failed: \(stageRes.output)")

        // Create ZIP mirroring GitHub Actions artifact structure (root = contents of distDir)
        let zipPath = tempDir.appendingPathComponent("AETHER-Droplet.zip")
        let zipProc = Process()
        zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProc.currentDirectoryURL = distDir
        zipProc.arguments = ["-qr", zipPath.path, "."]
        try zipProc.run()
        zipProc.waitUntilExit()
        #expect(zipProc.terminationStatus == 0)

        // Extract into clean directory and verify top-level & nested layout
        let extractedDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
        let unzipRes = try Self.runExecutable("/usr/bin/unzip", arguments: ["-q", zipPath.path, "-d", extractedDir.path])
        #expect(unzipRes.status == 0, "Unzip failed: \(unzipRes.output)")

        let topLevel = try FileManager.default.contentsOfDirectory(atPath: extractedDir.path).sorted()
        #expect(topLevel == ["AETHER.droplet", "README-TESTING.md"])

        let binaryPath = extractedDir.appendingPathComponent("AETHER.droplet/Contents/MacOS/AETHER").path
        #expect(FileManager.default.fileExists(atPath: binaryPath))
        #expect(FileManager.default.isExecutableFile(atPath: binaryPath))
        #expect(FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent("AETHER.droplet/Contents/Info.plist").path))
        #expect(FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent("AETHER.droplet/Contents/Resources/droplet.json").path))

        // No forbidden host binaries or build/SDK caches inside extracted archive
        let enumerator = try #require(FileManager.default.enumerator(atPath: extractedDir.path))
        while let item = enumerator.nextObject() as? String {
            let base = (item as NSString).lastPathComponent
            #expect(!["CodeCatch", "CodeCatchCLI", "DroppyKit.framework", ".droppykit", ".build", ".swiftpm", ".git", ".DS_Store", "content"].contains(base), "Forbidden artifact entry: \(item)")
        }
    }
}
