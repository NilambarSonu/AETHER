# AETHER Phase 3C: Secure IPC Event Contract & Length-Prefixed Frame Codec

**Architecture:** Option A — In-Process AetherCore Engine + Separate Droppy UI Client  
**Target Module:** `AetherCore`  
**Hardware Baseline:** MacBook Air M5, 32GB Unified Memory, Apple Silicon  
**OS Baseline:** macOS 15.0+  
**Implementation Date:** November 2026  
**Status:** COMPLETE / APPROVED FOR PHASE 3D

---

## 1. Executive Summary

Phase 3C establishes the versioned data contract and length-prefixed framing codec within the `AetherCore` target. This pure protocol layer defines how ephemeral OTP events and client acknowledgments are serialized, framed, and safely parsed between the AETHER host process and future external consumers (such as the Droppy droplet UI client).

In strict accordance with Phase 3C scope constraints:
- **No network, socket, Mach port, or XPC transport is created in this phase.**
- Protocol models and framing algorithms are pure, stateless/incremental, thread-safe, and bounded.
- The binary frame codec enforces hard allocation boundaries (maximum 4,096 bytes per frame) and buffer caps (maximum 16,384 bytes), rejecting corrupted or oversized inputs before body memory allocation.
- Plaintext OTP secrets are strictly masked across all error strings, descriptions, and debug representations. Leading zeros are preserved through dedicated string representations.

---

## 2. Protocol Versioning & Compatibility Policy

The AETHER IPC protocol is versioned to ensure backward compatibility and fail-closed security as the engine and external UI components evolve independently:

- **Current Version:** `UInt32 = 1` (`AetherOTPPayload.currentProtocolVersion` and `AetherOTPAcknowledgment.currentProtocolVersion`).
- **Compatibility Invariant:** Any frame received with a `protocolVersion` different from the supported version is rejected immediately with `AetherProtocolError.unsupportedProtocolVersion`.
- **Evolution Strategy:**
  - *Minor / Additive Evolution:* Within Protocol Version 1, new optional fields may be decoded by newer receivers without breaking existing senders, provided JSON decoding defaults or ignores unknown keys.
  - *Major / Breaking Evolution:* Structural schema changes, authentication alterations, or cryptographic format updates require incrementing `protocolVersion` to `2`. Version negotiation or explicit failure ensures mismatched binaries do not misinterpret payload semantics.

---

## 3. Data Contract Schemas

The data contract consists of two core models conforming to `Codable`, `Sendable`, and `Equatable`.

### 3.1. `AetherOTPPayload`

Represents an ephemeral OTP detection event broadcast by the AETHER engine:

```json
{
  "protocolVersion": 1,
  "eventID": "4E3F788B-9E39-44F4-931B-E8016DC19A62",
  "createdAt": "2026-11-10T01:30:00Z",
  "expiresAt": "2026-11-10T01:35:00Z",
  "source": "messages",
  "serviceLabel": "GitHub",
  "otpCode": "482913",
  "eventType": "otpAvailable"
}
```

#### Fields & Types
| Field | Type | Description |
| :--- | :--- | :--- |
| `protocolVersion` | `UInt32` | Schema version (`1`). |
| `eventID` | `UUID` | Cryptographically random unique identifier for tracking and replay prevention. |
| `createdAt` | `Date` | Timestamp when the OTP was extracted (ISO-8601). |
| `expiresAt` | `Date` | Expiration deadline for droplet presentation (ISO-8601). |
| `source` | `AetherSourceType` | Origin source (`messages`, `mail`, `gmail`, `outlook`, `imap`). |
| `serviceLabel` | `String` | Sanitized service or sender name (e.g., `"GitHub"`, `"Google"`). |
| `otpCode` | `String` | The raw verification code or token. Stored strictly as a `String` to preserve leading zeroes. |
| `eventType` | `AetherEventType` | Lifecycle state (`otpAvailable`, `otpExpired`, `otpRevoked`). |

### 3.2. `AetherOTPAcknowledgment`

Sent by the Droppy UI client back to the AETHER engine to acknowledge event receipt and lifecycle state:

```json
{
  "protocolVersion": 1,
  "eventID": "4E3F788B-9E39-44F4-931B-E8016DC19A62",
  "status": "copied",
  "timestamp": "2026-11-10T01:30:12Z",
  "errorCode": null
}
```

#### Status Enumeration (`AetherAcknowledgmentStatus`)
- `.received`: The client parsed the frame and verified validity.
- `.displayed`: The droplet presented the OTP notification/pill to the user.
- `.copied`: The user clicked or auto-copied the OTP to the clipboard.
- `.expired`: The client discarded the event due to deadline expiration.
- `.rejected`: The client rejected the event due to validation or security errors (accompanied by `errorCode`).

---

## 4. Field Constraints & Real-World OTP Compatibility

### 4.1. Real-World OTP Formats (Extracted from CodeCatch Fixtures)
Inspection of `CodeExtractor.swift` and the 704 real-world email fixtures revealed that OTP formats are not limited to 6 numeric digits:
- **Numeric PINs:** 4, 6, 7, 8 digits (`"004921"`, `"482913"`, `"0123"`).
- **Alphanumeric Codes:** 4 to 10 characters (`"K7PX2Q"`, `"KXQ-7PM"`, `"GH-88219"`).
- **Hyphenated / Word Tokens:** Multi-segmented confirmation tokens up to 35 characters (`"amivi-ndigo-rinit-raman"`).

### 4.2. Invariant Bounds
- **OTP String:**
  - Length: `3 <= count <= 64` characters (`AetherOTPPayload.minOTPLength` ... `maxOTPLength`).
  - Character Set: ASCII alphanumeric characters (`A-Z`, `a-z`, `0-9`) and hyphens (`-`).
  - No whitespace, control characters, quotes, or punctuation.
  - Strict preservation of leading zeros (`"0123"` is never cast to an integer).
- **Service Label:**
  - Length: `1 <= count <= 128` characters.
  - Rejection of control characters (`0x00`-`0x1F` except tabs/newlines, `0x7F`, and `0x80`-`0x9F`).
  - Non-empty after trimming whitespace.
- **Timestamps:**
  - `expiresAt > createdAt`.
  - Maximum allowable lifetime: 1,800 seconds (30 minutes).
  - Validation rejects events where `referenceDate >= expiresAt` (`AetherProtocolError.expiredEvent`).

---

## 5. Binary Frame Codec & Incremental Decoder

### 5.1. Wire Format
Each frame sent over IPC uses a binary length-prefixed encoding:
```
+-----------------------------------+---------------------------------------------+
|  4-Byte UInt32 Length (Big-Endian) |  N-Byte UTF-8 Encoded JSON Payload          |
+-----------------------------------+---------------------------------------------+
```
- **Byte Order:** Network Byte Order (Big Endian).
- **Header Size:** Exactly 4 bytes (`AetherFrameCodec.headerSize`).
- **Maximum Payload Size:** 4,096 bytes (`AetherFrameCodec.maxPayloadSize`).
- **Zero-Length Frames:** Rejected immediately with `AetherProtocolError.zeroLengthFrame`.

### 5.2. Memory Denial-of-Service Defense
A critical vulnerability in length-prefixed protocols is allocating buffer memory based on an unverified length header sent by an adversary or corrupted stream:
1. **Pre-Allocation Size Validation:** The decoder reads the 4-byte big-endian header and immediately validates `payloadLength <= 4096`. If `payloadLength > 4096`, it throws `AetherProtocolError.oversizedFrame` **without allocating any memory for the body**.
2. **Internal Buffer Exhaustion Guard:** The incremental decoder enforces a maximum accumulation limit of 16,384 bytes (`AetherFrameDecoder.maxInternalBufferSize`). If a misbehaved sender streams data without valid frame boundaries, the decoder triggers `AetherProtocolError.decoderBufferExceeded` and resets, preventing slow-drip memory exhaustion.

### 5.3. Incremental Decoder (`AetherFrameDecoder`)
Real-world streaming transports (e.g. Unix domain sockets) deliver bytes in arbitrary chunks:
- **Partial Headers:** Reads `< 4` bytes and pauses until the remainder arrives.
- **Partial Payloads:** Accumulates body bytes until the declared length is reached.
- **Concatenated Frames:** Processes multiple consecutive frames in a single incoming chunk.
- **Thread Safety:** Protected via an internal `NSLock` to allow thread-safe ingestion.
- **Reset & Recovery:** Provides `reset()` to purge corrupted state and resume parsing clean frames.

---

## 6. Privacy & Threat Mitigations

| Threat Vector | Mitigation Strategy |
| :--- | :--- |
| **Log Leakage (Secret OTP Exposure)** | `AetherOTPPayload` and `AetherProtocolError` implement custom `description` and `debugDescription` that systematically redact the OTP code (`[REDACTED (N chars)]`). Even in debug builds, raw OTP secrets never appear in logs. |
| **Heap Exhaustion (DoS)** | Hard 4,096 byte frame limit verified before body slicing or allocation. 16,384 byte buffer cap on streaming decoder. |
| **Leading Zero Truncation** | OTPs are modeled and serialized strictly as Swift `String` primitives, guaranteeing `"004921"` is never parsed as integer `4921`. |
| **Control Character Injection** | Service labels are checked against ASCII and C0/C1 control character ranges to avoid terminal or UI escape code injection. |
| **Replay Attacks** | UUID `eventID` uniquely distinguishes every broadcast. External UI clients maintain a sliding deduplication window, rejecting duplicate `eventID`s or events with expired timestamps. |
| **Protocol Mismatch** | Explicit `protocolVersion == 1` enforcement fail-closes immediately on version skew. |

---

## 7. Deferred Responsibilities (Phase 3D)

The following items are explicitly **out of scope** for Phase 3C and deferred to Phase 3D:
- Unix domain socket creation and filesystem path resolution.
- Peer code signature validation using macOS `SecCode` / `AuditToken`.
- Socket lifecycle management, reconnection logic, and backoff.
- Client Droppy droplet bridge implementation.

---

## 8. Verification & Test Coverage

### 8.1. Test Suite Results
A comprehensive unit test suite (`Tests/AetherCoreTests/AetherProtocolCodecTests.swift`) was implemented containing 26 dedicated protocol and codec tests:

1. `validOTPPayloadRoundTrip`: Full serialization/deserialization cycle.
2. `leadingZeroesAreStrictlyPreserved`: Multi-zero prefix test cases (`"0123"`, `"004921"`).
3. `extractorCompatibleOTPLengthsAndFormats`: 4-digit PINs, 6-char alphanumeric, 8-digit codes, hyphenated multi-word tokens.
4. `emptyOTPCodeThrowsError`: Rejection of empty strings.
5. `invalidCharactersInOTPThrowsError`: Rejection of punctuation, spaces, emojis, symbols.
6. `oversizedOrEmptyServiceLabelThrowsError`: Bounds enforcement on service labels.
7. `controlCharactersInServiceLabelAreRejected`: Rejection of ANSI escapes, bells, null bytes.
8. `expiredEventIsRejectedOnValidation`: Rejection of past timestamps.
9. `excessiveLifetimeThrowsError`: Rejection of lifetimes > 1,800 seconds.
10. `unsupportedProtocolVersionThrowsError`: Protocol version incompatibility.
11. `descriptionNeverExposesPlaintextOTP`: Audit confirming redaction in logs/debug strings.
12. `validAcknowledgmentRoundTrip`: Acknowledgment model round-trip.
13. `acknowledgmentAllStatusesRoundTrip`: Covers `.received`, `.displayed`, `.copied`, `.expired`, `.rejected`.
14. `unsupportedAcknowledgmentVersionThrows`: Version mismatch rejection.
15. `exactMaxFrameBoundarySucceeds`: Exactly 4,096 byte frame boundary acceptance.
16. `oversizedFrameExceedingMaxIsRejectedBeforeAllocation`: 4,097 byte frame rejection prior to memory allocation.
17. `zeroLengthFrameIsRejected`: 0-byte payload rejection.
18. `partialHeaderThenCompletion`: Incremental streaming across 4-byte header boundaries.
19. `partialPayloadThenCompletion`: Incremental streaming across body chunk boundaries.
20. `multipleConcatenatedFramesDecodedInSequence`: Multiple frames arriving in a single read.
21. `largeDeclaredLengthWithoutBodyWaitsGracefully`: Frame header waiting for payload.
22. `decoderBufferExceededThrowsError`: Buffer exhaustion beyond 16,384 bytes.
23. `invalidJSONThrowsMalformedError`: Corrupted JSON payload rejection.
24. `invalidTimestampsThrowsError`: `createdAt >= expiresAt` rejection.
25. `resetClearsBufferAndEnablesRecovery`: Incremental decoder recovery after error.
26. `randomCorruptedByteStreamDoesNotCrash`: Adversarial fuzzing with pseudorandom binary input.

### 8.2. Comprehensive Test Run Summary
- **`AetherCoreTests`:** 31 tests passed in 0.054 seconds (26 codec tests + 5 core tests).
- **`CodeCatchCoreTests`:** 38 tests passed in 0.428 seconds (including 704 real-world OTP corpus samples in 0.424s).
- **`CodeCatchTests`:** 241 tests passed in 2.595 seconds.
- **Total Passing Tests:** **310 tests across 24 suites (100% pass rate, 0 regressions).**
- **Production Packaging:** `./scripts/install.sh --build-only` built `.build-release/CodeCatch.app` with universal architectures and all code signatures intact.

---

## 9. Changed File Inventory

| File Path | Action | Description |
| :--- | :--- | :--- |
| `Sources/AetherCore/Protocol/AetherProtocolError.swift` | Created | Strongly typed, redacted error representations for protocol and codec failures. |
| `Sources/AetherCore/Protocol/AetherOTPPayload.swift` | Created | Immutable, validated OTP event data contract with redacted descriptions. |
| `Sources/AetherCore/Protocol/AetherOTPAcknowledgment.swift` | Created | Immutable, validated client acknowledgment contract. |
| `Sources/AetherCore/Codec/AetherFrameCodec.swift` | Created | Stateless 4-byte big-endian length-prefixed frame encoder/decoder. |
| `Sources/AetherCore/Codec/AetherFrameDecoder.swift` | Created | Thread-safe incremental frame decoder with DoS and exhaustion guards. |
| `Tests/AetherCoreTests/AetherProtocolCodecTests.swift` | Created | 26 unit tests covering framing, bounds, security, and edge cases. |
| `docs/phase-3c-ipc-contract-and-frame-codec.md` | Created | Architecture and technical specification deliverable for Phase 3C. |

---

## 10. Rollback Procedure

If rollback of Phase 3C is required:
1. Remove `Sources/AetherCore/Protocol/` and `Sources/AetherCore/Codec/`.
2. Remove `Tests/AetherCoreTests/AetherProtocolCodecTests.swift`.
3. Remove `docs/phase-3c-ipc-contract-and-frame-codec.md`.
4. Run `./scripts/test.sh` to confirm return to the Phase 3B baseline (284 tests passing).
5. The baseline backup remains untouched and accessible at `/Users/nilambarbehera/Documents/Projects/Aether_Backups/Aether_baseline_20261109`.

