# Security Policy

AETHER processes sensitive verification codes, sign-in links, TOTP secrets, and mail credentials, so security is paramount. Please report vulnerabilities privately rather than in public issues:

1. Open the repository's **Security** tab on GitHub (`NilambarSonu/AETHER`).
2. Select **Report a vulnerability**.

### Helpful in a Report
- The AETHER build and git commit hash.
- macOS version and hardware architecture.
- Steps to reproduce or sample messages that illustrate the issue (strictly redact all real credentials, codes, links, and addresses).

### In Scope
- Any mechanism that exposes a verification code, sign-in link, raw message, Bitwarden TOTP secret, or OAuth/IMAP credential to an unauthorized local application, another user, the network, or the disk.
- Any bypass of Touch ID / lock protection, DMARC sender verification, agent rate limits, or approval prompts in `AetherAgentAccess` or `AetherMCPBridge`.
- Any bypass of Darwin kernel audit token validation (`LOCAL_PEERTOKEN`) or code signature validation (`SecCodeCheckValidity`) in the legacy UDS IPC transport.
- Any symlink / path traversal / race condition in `AgentSkillsManager`, Bitwarden CLI invocation, or installer scripts.

### Process Trust Boundary & Residual Risks
- **Shared Droppy Process Context:** `AETHER.droplet` is loaded dynamically (`dlopen`) inside `Droppy.app` (`iordv.Droppy`) and shares Droppy's address space, entitlements, and security context. It is not isolated inside a droplet-specific macOS App Sandbox. Co-loaded third-party droplets running inside `Droppy.app` share the same process space and host Keychain/FDA grants.
- **Process-Level Audit Tokens:** Darwin kernel audit tokens (`LOCAL_PEERTOKEN`) in the IPC module authenticate the `Droppy.app` process (`iordv.Droppy`, Team `NARHG44L48`), not an individual droplet inside it.
- **POSIX DAC Scope:** Mode `0700` directories and `0600` session token files enforce macOS UID boundaries against other system users, not same-UID processes.

### Out of Scope
- Attacks requiring root or kernel privileges on the local machine.
- Vulnerabilities in unmodified upstream dependencies unless exploitable through AETHER.
