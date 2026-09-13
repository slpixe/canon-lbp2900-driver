# Building from source

Supported output target: arm64, macOS 15.0+. Build on macOS using Apple's Xcode Command Line Tools. The normal build uses no Homebrew packages, vendored executable, network fetch, or root access. The C filter links the system CUPS and C runtime; the optional Swift app uses system frameworks and `/usr/bin/ipptool`.

```sh
xcode-select --install  # only if Apple's tools are missing
./build.sh --driver
./build.sh --menubar    # optional
./build.sh --all        # both
```

The script is short enough to inspect before use. `build/` contains all generated output. Ad hoc signing of your locally built app supplies a local structural signature, not a publisher identity or notarization.

Equivalent driver compilation at this revision:

```sh
mkdir -p build
xcrun clang -D_DARWIN_C_SOURCE -std=gnu11 -O2 -Wall -Wextra -Werror \
  -fstack-protector-strong -D_FORTIFY_SOURCE=2 -ftrivial-auto-var-init=zero \
  -arch arm64 -mmacosx-version-min=15.0 \
  captdriver/src/*.c -lcups -o build/rastertocapt-lbp2900
```

The script also removes the local workspace prefix from compiler paths. The inherited autotools files remain for upstream context, but `build.sh` is the supported macOS path for this fork. Do not follow the inherited `captdriver/` installation instructions to install system-wide; use the fork's explicit installer.

## Inspect the result

```sh
file build/rastertocapt-lbp2900
otool -L build/rastertocapt-lbp2900
otool -l build/rastertocapt-lbp2900
codesign -dvvv build/rastertocapt-lbp2900
codesign --verify --strict build/rastertocapt-lbp2900
shasum -a 256 build/rastertocapt-lbp2900
```

Expect arm64 and minimum macOS 15.0. Successful signature verification does not establish who wrote the code or whether it is safe. A local hash identifies your build; different Apple compilers, SDKs and signing operations can produce different binaries. This project does not claim bit-for-bit reproducible builds.

## Tests

Python 3 is needed to orchestrate tests; it is not a runtime dependency of the driver. The script deliberately does not install Python or any other tool automatically.

```sh
./scripts/test.sh
```

Tests use AddressSanitizer and UndefinedBehaviorSanitizer. The CUPS backend is replaced with an in-memory double; no job is submitted and no printer, daemon, network service or root privilege is needed. Coverage includes packet fragmentation and rejection, payload lengths and destination bounds, status-record lengths, empty/whitespace device IDs, cancellation/deadline exits, raster limits, compressor output exhaustion, 80 compression/decompression round-trips and Swift progress parsing. The inherited decompressor is a test oracle, not part of the installed software.

Syntax checks, static analysis, PPD regeneration and installer policy tests run in CI. Sanitizer tests and an analyzer pass cannot prove absence of defects. [Hardware testing](HARDWARE-TESTING.md) remains a release gate.

## Generate the PPD

```sh
mkdir -p build/ppd
ppdc -d build/ppd captdriver/src/canon-lbp.drv
cmp ppd/CanonLBP-2900-3000.ppd build/ppd/CanonLBP-2900-3000.ppd
```

It should match byte for byte with the same CUPS generator. `cupstestppd` may report the filter missing until it is installed at its destination; do not install merely to silence that diagnostic. Paper-name warnings are inherited and do not indicate executable content.
