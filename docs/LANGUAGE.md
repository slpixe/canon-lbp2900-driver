# Should the driver move to Rust or Go?

**Rust is the preferred candidate for a future protocol-core rewrite.** Safe Rust gives bounds-checked slices, ownership and explicit error types; it can eliminate many of the buffer-lifetime and uninitialized-state errors found in C. A small, reviewed unsafe boundary would still be needed to use the system CUPS raster and side-channel APIs. Those C libraries do not become memory-safe merely because the caller is Rust. Protocol errors, insecure installation and poor release signing are also language-independent.

Go is memory-safe for ordinary Go code, but accessing CUPS through cgo keeps a C/FFI boundary and adds a garbage-collected runtime. That is not inherently unsafe or incompatible with a CUPS filter, but offers less benefit here than Rust's fit for compact byte-oriented parsing and controlled FFI. Replacing only the command-line wrapper with Go would leave the risky C core intact.

For this first fork, retain the existing CAPT implementation, fix identifiable defects and establish regression tests before changing languages. The current native Swift menu app does not need a Go or Rust rewrite. A full immediate port without hardware coverage would replace known defects with unmeasured protocol and integration risk.

A sensible migration sequence is:

1. Obtain sanitized golden CAPT/raster fixtures and a reproducible physical-printer test matrix.
2. Move packet parsing, status decoding and compression to safe Rust, with no `unsafe` in those modules.
3. Keep the CUPS boundary in a small separate module; audit each unsafe call and ownership rule.
4. Differential-test C and Rust outputs, test malformed-input rejection, then compare physical printing, cancellation and recovery.
5. Switch implementations only after those tests pass, pin dependencies and maintain the new toolchain.

The `experiment/rust-driver` branch now implements the protocol, status, compression and job engine in safe Rust, with an isolated CUPS FFI boundary and a small C adapter. It has zero third-party Rust crates. Both C and Rust have a confirmed single-page LBP2900 print on M1 Pro / macOS 26.6.2. C remains the default; Rust remains experimental pending broader use and independent review. See [Rust instructions](https://github.com/slpixe/canon-lbp2900-driver/blob/experiment/rust-driver/docs/RUST.md) and [remaining validation](HARDWARE-TESTING.md). No Go port is present. A language change reduces certain memory risks; it does not establish protocol correctness or make system CUPS memory-safe.

References: [Rust FFI safety](https://doc.rust-lang.org/nomicon/ffi.html), [unsafe Rust](https://doc.rust-lang.org/book/ch20-01-unsafe-rust.html), [Go cgo documentation](https://pkg.go.dev/cmd/cgo).
