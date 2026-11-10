# Security Policy

AETHER processes sensitive verification codes and coordinates ephemeral notifications, so security is paramount. Please report vulnerabilities privately rather than in public issues:

1. Open the repository's **Security** tab on GitHub (`NilambarSonu/AETHER`).
2. Select **Report a vulnerability**.

### Helpful in a Report
- The AETHER build and git commit hash.
- macOS version and hardware architecture.
- Steps to reproduce or sample messages that illustrate the issue (strictly redact all real credentials, codes, links, and addresses).

### In Scope
- Any mechanism that exposes a verification code, sign-in link, raw message, or credential to another unauthorized local application, another user, the network, or the disk.
- Any bypass of Darwin kernel audit token validation (`LOCAL_PEERTOKEN`) or code signature validation (`SecCodeCheckValidity`).
- Any IPC frame boundary or length-prefixed codec buffer overflow / DoS vulnerability.
- Any race condition on local Unix Domain Sockets or session token files.
- Flaws in the update path or permissions boundaries.

### Out of Scope
- Attacks requiring root or kernel privileges on the local machine.
- Vulnerabilities in unmodified upstream dependencies unless exploitable through AETHER.
