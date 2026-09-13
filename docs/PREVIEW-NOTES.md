This draft contains development artifacts from the hardened source fork. **Check the exact source commit against docs/HARDWARE-TESTING.md: the original v2.0.0-alpha.1 artifacts predate the transfer-status fix.** Current C and experimental Rust source each have one physical page confirmed on macOS 26.6.2. Sequoia execution and end-user package installation remain unverified; a source result does not validate older packages.

The packages are explicitly UNSIGNED for distribution (executables may have only local ad hoc signatures). They are not Apple-notarized click-to-install releases. Do not disable macOS security protections to install them. Build the reviewed source locally for development, or wait for a signed, notarized and hardware-tested release.

The driver-only package and optional menu-app ZIP are separate. No root restoration service or automatic login agent is installed. Build metadata records the source commit and toolchain; SHA256SUMS and GitHub artifact attestations identify these exact bytes. These checks do not certify that the code is bug-free.

See the repository's README, SECURITY.md, docs/BUILD.md, docs/RELEASES.md and docs/HARDWARE-TESTING.md. Source is available in the release archive under GPLv3.
