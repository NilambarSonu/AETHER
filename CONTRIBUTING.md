# Contributing to AETHER

AETHER is a macOS 15+ Swift project targeting Apple Silicon. It builds with Xcode or the Apple
Command Line Tools (Swift 5.10+ / Swift 6.0+). Use the checked-in `Package.resolved`.

```sh
# Run the test suite
scripts/test.sh --force-resolved-versions

# Build release binaries
swift build -c release --scratch-path .build-release --force-resolved-versions

# Build AETHER droplet for Droppy
scripts/build-droplet.sh
```

These commands need no mail accounts, Full Disk Access, Accessibility, signing
certificate or release secrets. Tests use synthetic messages, isolated settings,
in-memory vaults and private pasteboards. CI runs them on GitHub-hosted macOS runners.
Do not use a personal inbox or vault as a test fixture.

## Layout

| Path | What it holds |
|---|---|
| `Sources/AetherCore/` | Extracted headless verification engine, binary frame codecs, IPC transport actor and peer validators |
| `Sources/CodeCatchCore/` | Deterministic code extraction, regex patterns, TOTP and mime parsing |
| `Sources/CodeCatch/` | The host application: macOS adapters, local store watchers, menus and UI |
| `Sources/CodeCatchCLI/` | The `codecatch` CLI tool |
| `Droplet/` | The Droppy droplet plug-in bundle and DroppyKit interface definitions |
| `Tests/` | Test suites for `AetherCore`, `CodeCatchCore`, and `CodeCatch` |
| `Resources/` | `Info.plist` and app icon assets |
| `scripts/` | Build, test, droplet packaging and release tooling |
| `docs/` | Phase reports, architecture gates and security audit records |

Swift package folders are capitalized as SwiftPM expects; `functions/` is the name Cloudflare
Pages looks for; everything else is lowercase.

Swift follows `.swift-format` and Python scripts follow `ruff.toml`; CI checks both. To format
and check before a commit:

```sh
swift format -i -r -p Sources Tests Package.swift && swift format lint --strict -r -p Sources Tests Package.swift
ruff format scripts && ruff check scripts
```

The one-time reformat is listed in `.git-blame-ignore-revs`; run
`git config blame.ignoreRevsFile .git-blame-ignore-revs` so `git blame` skips it.

## Changes

Keep a change focused on a failure or a concrete simplification. For bugs, first
add a failing case to the closest existing test. Preserve behavioral assertions
when moving code. Tests around sensitive actions should exercise rejection,
cancellation and stale state, not just the successful path.

`Sources/CodeCatchCore` contains parsing and deterministic logic; macOS adapters
and UI live in `Sources/CodeCatch`. See [ARCHITECTURE.md](ARCHITECTURE.md) for the
privacy boundaries. New sources deliver `IncomingMessage` through the existing
ingestion path. Do not create another clipboard, storage or authentication path.
Add a line to `Tests/CodeCatchCoreTests/code-samples.txt` for every new code
format or false positive. `@Local` stands in for `@State`, whose macro plugin
only ships with Xcode.

Never commit inbox exports, real verification links, credentials, signing keys
or screenshots containing personal data. Use `example.com` or `.invalid` for
synthetic addresses. Report exposure bugs through [SECURITY.md](SECURITY.md).

Running the actual app is different from running tests: it can read the current
user's configured sources. Use a separate macOS account and synthetic messages
for permission, lock, sleep/wake and update checks.

## Debug tools

Debug builds have extra tools, such as `--probe` (prints the codes each mail
account would give, masked), `--snapshot <dir>` (renders the UI to PNGs) and
`--import-env`. The full list is in `Sources/CodeCatch/Debug/DebugCommand.swift`. Run them with
`scripts/debug.sh <flag>`; it signs the build like a release, so the Keychain
doesn't ask for your password after every rebuild. Release builds leave these
tools out.

Preview the site with `python3 -m http.server --directory site`.

The site is in English at the top and in other languages under `site/<lang>/`
(`de`, `ja`, `fr`, `it`, `es`, `pt`). Each page names its versions in `<link rel="alternate"
hreflang>` tags and in the footer's language links. `python3 scripts/check-site.py`
checks those, every link within the site and the sitemap; the deploy runs it too.
Changing an English page means changing its translations in the same commit.
To add a language, add its folder name to `LANGUAGES` in `scripts/check-site.py`
and `functions/_middleware.js`.

## Releasing

| Command | Result |
|---|---|
| `scripts/install.sh --build-only` | Tests, then builds a signed universal app in `.build-release/` |
| `scripts/install.sh --release` | Also makes `CodeCatch.dmg`, notarizes it, and writes `site/appcast.xml` |
| `scripts/install.sh --publish` | Also uploads the DMG as a GitHub release, then commits and pushes `site/appcast.xml` |

CI then deploys `site/` to Cloudflare Pages, and installed copies update
themselves from `https://codecatch.app/appcast.xml`.

Release builds remap source paths, strip object-file debug records, and scan the
app for embedded home directories before signing. Run the guard tests with
`python3 scripts/test-release-privacy.py`.

A release needs:

- a Developer ID certificate (`Developer ID Application` in the login keychain;
  set `CODECATCH_IDENTITY` to pick another)
- a `notarytool` Keychain profile named `codecatch` (or set `CODECATCH_NOTARY_PROFILE`)
- Sparkle's EdDSA key in the Keychain
- `uvx`, for `dmgbuild`
- `gh` and push access to `main`, with `main` checked out, pushed and clean

The build number is the commit count plus 100 (`CODECATCH_BUILD_NUMBER`
overrides it). Before a release, test the download on a fresh macOS account: on
Intel, on a Mac without Touch ID, and through Messages, mail and password unlock.
