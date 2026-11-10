# AETHER Droplet

AETHER displays ephemeral verification codes captured by the local AETHER host application directly inside Droppy's notch HUD with one-click copy.

A Droplet for [Droppy](https://getdroppy.app), built with [DroppyKit](https://getdroppy.app/docs/droppykit).

## What it does

- **Verification code HUD.** Displays the sender label and verification code in Droppy's expanded HUD card as soon as AETHER delivers an event.
- **One-click copy & dismiss.** Copies the verification code to the macOS pasteboard when `Copy Code` is clicked, sends a `.copied` acknowledgment back to AETHER, and dismisses the HUD.
- **Local-only IPC bridge.** Connects solely to the same-user AETHER Unix Domain Socket using an ephemeral session token and Darwin kernel audit-token verification (`LOCAL_PEERTOKEN`).

## How to use it

1. Run the AETHER host application so it watches your local verification code sources and exposes its authenticated Unix Domain Socket.
2. Enable **AETHER** in Droppy (`~/Library/Application Support/Droppy/Droplets/aether/AETHER.droplet`) or Droppy Playground (`~/Library/Application Support/Droppy Playground/Droplets/aether/AETHER.droplet`) and review its requested capabilities.
3. Approve **AETHER** when Droppy prompts before running the droplet.

## Privacy

- **`hud`**: Required to display transient verification code cards on the Droppy notch surface.
- **`clipboard-write`**: Required so clicking **Copy Code** can place the verification code on the pasteboard.
- No email databases, Messages databases, Keychain secrets, or OAuth tokens are accessed by this droplet, and no verification codes are written to logs or sent off your Mac.

## Credits

- Built on **AETHER**, which evolved from [CodeCatch](https://github.com/ugzv/CodeCatch) by Uros (GNU GPLv3).

## License

GPL-3.0. See [LICENSE](LICENSE).
