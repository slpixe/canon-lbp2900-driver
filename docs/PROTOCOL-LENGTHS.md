# Deterministic CAPT reply lengths (issue #7)

Framed replies use the unsigned little-endian binary total length in bytes 2–3, including the four-byte header. The minimum is six bytes and the maximum is 65,535. The receiver reads exactly that many bytes, with existing deadlines and capacity checks. The raw IEEE-1284 command is outside this framing API.

This is the explicit policy for the LBP2900 commands used by this driver (identification, status and job acknowledgements), and the default for inherited models. There are currently **no registered BCD exceptions**. A future exception requires an identified model/command and a captured fixture; never select an encoding using read sizes, short reads, timing or destination capacity. Unknown short replies fail the job rather than being accepted under another length interpretation.

## Evidence and regression

The inherited `captdriver/SPECS` section 1.1 describes the binary format and mentions an unspecified firmware BCD quirk without identifying a model/command. The previous implementation accepted either length when a read happened to end there. That is not a safe way to distinguish encodings on a byte stream.

The published, public-domain LBP2900 capability fixture in [tests/fixtures](../tests/fixtures/README.md) begins `a1 a1 38 00` and contains **56 bytes**, not 38. The new test failed against the old receiver when a fragment ended at byte 38. Tests now exercise every split and fixed fragment size, checking full payload equality and that the next response is not consumed. Synthetic BCD-short packets are rejected. This is a functional framing regression, not an exploit test.

Local successful C/Rust printing before this change is recorded separately in HARDWARE-TESTING.md. Those jobs establish the prior transfer fix; they do not constitute a physical retest of this length change. Published capability data establishes the binary interpretation for that command; other command shapes are supported by the protocol specification and synthetic full-job checks. No new local packet capture is claimed.

Compatibility limit: a device/firmware genuinely using an undocumented BCD length can now fail closed. It needs a specific evidenced quirk, not restoration of the fragment-dependent heuristic. Printing and recovery across other models/firmware are not certified by this change.
