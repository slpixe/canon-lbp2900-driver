# Experimental Rust driver

**Draft experiment: keep using the C driver for ordinary printing.** The Rust
filter is implemented and can be built, but has not been tested on a physical
LBP2900. Neither implementation is certified or guaranteed safe.

The branch `experiment/rust-driver` leaves the C source, default build, installer,
packages, release workflow and optional Swift menu app unchanged. The Rust binary
has its own filename and is never selected automatically. It accepts only an
IEEE-1284 `MDL:LBP2900` or `MODEL:LBP2900` identification; other models are rejected.

## What is implemented

- CAPT command framing, bounded replies and status decoding in safe Rust.
- Hi-SCoA compression using the existing default parameters, translated from C.
- Raster validation, centered line copying and a bounded cache for page retries.
- LBP2900 job/page setup, data transfer, completion, out-of-paper handling and
  manual-duplex waits. The job state belongs to one driver instance.
- A native user-space CUPS filter using the system raster and side/back channels.
- A separate experimental PPD, generated only by the explicit Rust build script.

The `rust/src/lib.rs` crate forbids unsafe code. It has **zero third-party crates**;
Cargo.lock is committed and Rust 1.98.1 is pinned. Release builds enable integer
overflow checks and abort on unexpected panic. Expected invalid input produces
an error and a failed print job, not a panic or a success message.

This is a port of the protocol implementation, not a Rust wrapper around the old
C compressor or job engine. Original authorship and GPL-3.0-or-later licensing are
preserved; see [provenance](PROVENANCE.md).

## Build as your normal user

Target: native Apple Silicon, macOS 15 or newer. Sequoia 15.7.4 is within the
build target; this is not a claim of hardware validation on that exact OS.
You need Apple's Command Line Tools and Rust/Cargo. Install Rust from the
[official Rust installation instructions](https://www.rust-lang.org/tools/install),
then explicitly install the pinned toolchain:

```sh
rustup toolchain install 1.98.1 --profile minimal --component clippy --component rustfmt
```

Check out the experiment in a separate working directory to retain a C checkout:

```sh
git clone --branch experiment/rust-driver https://github.com/slpixe/canon-lbp2900-driver.git canon-lbp2900-rust
cd canon-lbp2900-rust
./scripts/test-rust.sh
./scripts/build-rust.sh
```

The output is `build/rust/rastertocapt-lbp2900-rust` and
`build/rust/CanonLBP2900-Rust-Experimental.ppd`. Nothing is installed or launched.
Builds use `--locked --offline` and do not download dependencies. Toolchain
installation above is a separate network operation. A compiled filter does not
require Rust on the recipient's computer. Local signatures are ad hoc, not
Developer ID signatures or notarization. There is no Rust installer/release yet.

Core-only tests, which do not need CUPS headers, can also run on Linux:

```sh
cd rust
cargo test --locked --offline
cargo clippy --all-targets --locked --offline -- -D warnings
```

Use `./scripts/test-rust.sh` for the full suite: a plain `cargo test` skips the C
encoder comparison and labels it ignored. The full script builds the oracle, sets
`LBP_C_ORACLE`, and explicitly runs that comparison.
The full suite needs Python 3, Clang and system CUPS headers/libraries
(included in Apple's SDK; `clang` and `libcups2-dev` on Ubuntu). It uses a local synthetic
backend, not the CUPS service, USB or a network connection, and needs no sudo.

## Optional manual hardware experiment

Only after reviewing the branch and passing the checks above, a maintainer with
an LBP2900 can install the two separately named files below. These commands need
administrator authorization to write system printer directories. They do not
replace the C filter or its PPD. Build first **without sudo** and review both
source and output before executing installation commands.

```sh
sudo /usr/bin/install -o root -g wheel -m 0755 \
  build/rust/rastertocapt-lbp2900-rust \
  /usr/libexec/cups/filter/rastertocapt-lbp2900-rust
sudo /usr/bin/install -o root -g wheel -m 0644 \
  build/rust/CanonLBP2900-Rust-Experimental.ppd \
  /Library/Printers/PPDs/Contents/Resources/CanonLBP2900-Rust-Experimental.ppd
```

These assume the standard system-owned printer directories already exist (for
example from the C installation). Do not redirect these paths or relax their
permissions to make an installation succeed. Add a **separate** USB queue in
System Settings → Printers & Scanners. Give it a distinct name such as
`LBP2900 Rust Experiment`, select **Use → Other**, and select the experimental
PPD above. Keep the C queue and default-printer selection. Do not send jobs to
both queues at the same time: they share the same physical USB device. The current
menu app targets the C queue and is outside the Rust experiment.

Start with a non-sensitive single-page document; then use the validation matrix
below. No quarantine removal, Gatekeeper bypass, SIP change, root service, login
item or background updater is required by this experiment. If macOS rejects a
build, stop and inspect its architecture, deployment target and signatures.

To roll back, first cancel jobs in and remove **only the experimental queue** in
System Settings. Once its jobs have stopped, remove the two experimental files:

```sh
sudo /bin/rm /usr/libexec/cups/filter/rastertocapt-lbp2900-rust
sudo /bin/rm /Library/Printers/PPDs/Contents/Resources/CanonLBP2900-Rust-Experimental.ppd
```

The C queue/filter remain available throughout. None of these privileged install,
queue or removal commands are run by the build or test suite.

## Unsafe boundary and remaining risks

`rust/src/bin/cups.rs` is the only Rust FFI module. Each unsafe call documents its
contract. `rust/adapter/cups.c` is a small system-API adapter compiled against the
installed headers. It owns no CAPT parser or compression implementation.

- Rust owns output buffers, passes exact slice capacities, and checks results.
- A raster handle is uniquely owned, closed once by Drop, and cannot outlive its
  owned input file. CUPS owns its internal allocations and does not close that fd.
- The adapter copies CUPS metadata to a fixed field array rather than hard-coding
  the layout of Apple's CUPS structs in Rust.
- The signal handler only sets a `sig_atomic_t` flag; cleanup and protocol calls
  do not run inside the signal handler. Backend output uses nonblocking writes,
  polling, cancellation checks and a 30-second transaction limit.
- The executable is single-threaded. The adapter must not be reused as a general
  concurrent library without another ownership/thread-safety review.

CUPS and the adapter remain C; Rust does not make their internals memory-safe.
CUPS raster decoding is a synchronous foreign call and is not covered by the
protocol's timeouts; a stalled raster source or CUPS defect remains a risk.
Limits cover packet lengths, dimensions, 32 MiB compressed-page caching, 65,535
pages per job, three retries, 30-second status waits and 300-second user waits.
An individual status request can add up to 15 seconds to a surrounding wait.
Resource exhaustion, hardware state, protocol bugs and supply-chain compromise
still need independent controls. Rust is not a malware detector.

The C implementation's legacy binary/BCD reply-length convention is deliberately
preserved at fragment boundaries for comparison. The same header can be ambiguous;
fragmentation can affect which length is accepted. The implementation bounds
memory, but **does not resolve that protocol ambiguity**. Capture sanitized real
LBP2900 replies before replacing it with an explicit model/command length policy.

## Evidence and gates before adoption

The automated suite checks malformed/truncated packets, reply capacities,
status-record boundaries, raster limits, model scope, cancellation, retry limits
and page accounting. It compares 160 encoder cases to the C encoder under
ASan/UBSan, in debug and release Rust builds. The CUPS adapter also has
ASan/UBSan buffer-capacity, metadata-copy and handle/file-ownership tests. A synthetic backend then exercises
both executable filters through **real system CUPS raster and fd 3/4 calls** and
compares complete CAPT transcripts for three raster jobs (including multiple
pages), normalizing only wall-clock timestamps. Failure scenarios include a wrong
model, short job-start reply, cancellation and invalid raster input.

These are regression fixtures, not recordings from a real printer. Agreement with
C can preserve C's protocol mistakes; it is not independent protocol validation.
There is no claim of exhaustive fuzzing, formal verification or reproducible binary
output. No physical printing, sleep/wake or USB recovery result is claimed.

Keep the PR draft and do not switch defaults until all of the following are recorded:

- Independent review of the Rust core and every FFI/adapter contract.
- Sanitized captured CAPT replies/golden raster fixtures, with explicit resolution
  of the binary/BCD length ambiguity and additional automated state scenarios.
- Longer coverage-guided fuzzing of packet, status and raster metadata boundaries.
- On an M1 with Sequoia 15.7.4: single/multiple pages, A4/Letter, margins, dense
  graphics, copies, toner settings, supported media and manual duplex where used.
- Cancellation during raster input, USB send, reply wait, out-of-paper and recovery;
  unplug/replug, power cycle, sleep/wake, concurrent queued jobs and repeated jobs.
- Comparison to C for page count, output quality, timing, memory and failure cleanup.
- A separately reviewed opt-in installer and a signing/notarization/release decision
  before distributing clickable Rust binaries to ordinary users.

Record OS version, printer identity, commit, toolchain, fixture and observed result
in [the hardware testing checklist](HARDWARE-TESTING.md). Do not publish document
contents, USB serial numbers, usernames or raw unredacted captures.
