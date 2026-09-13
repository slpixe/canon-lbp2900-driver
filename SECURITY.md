# Security policy and remaining risk

This is an experimental hardening fork, not security-certified software. No claim of “safe source code” can replace code review, testing, platform updates and maintenance. Stable end-user release status requires the checks in `docs/HARDWARE-TESTING.md` and `docs/RELEASES.md`.

## What changed

- Reply capacities are initialized at every job-start call. The receive API counts payload bytes separately from the four-byte CAPT header and rejects undersized destinations.
- CAPT reads handle fragmentation, zero-progress and invalid lengths with a transaction deadline. CUPS int lengths no longer alias size_t storage. Basic and extended status fields are validated before use.
- Whitespace-only device identification no longer lets trimming move the end pointer before the start; model names are bounded.
- Raster format, dimensions, band size and allocation arithmetic are bounded before allocation/compression. Strings are explicitly terminated. Compression reports output exhaustion instead of silently returning a truncated stream; unnecessary aligned padding was fixed.
- Cancellation handlers only set a sig_atomic_t flag. Normal control flow checks it. Printer status waits have monotonic deadlines and failures stop the job, instead of pretending a timed-out page completed. Retries are limited. Page accounting moves after the completion handshake.
- Raw CAPT/raster payload dumps are removed. The menu app requests no job titles and only the current user's jobs.
- No checked-in executables in the current tree, root build, quarantine removal, self-healing daemon, automatic login app, network updater or arbitrary USB fallback.
- The privileged installer validates root-controlled destination ancestry and rejects symlinks, uses explicit source ownership checks and atomically replaces individual files. It does not interpret shell code from device URIs.
- GitHub Actions are pinned to commit hashes. Release jobs can attest artifacts; hashes alone are not publisher authentication.

## Threat model and limitations

The filter consumes CUPS raster input and printer/backend replies. Those inputs are treated as untrusted. CUPS normally runs filters as an unprivileged account and applies a macOS sandbox. This fork does not change that sandbox, install a kernel extension, or need SIP disabled. The small system installer runs as root once. The optional menu app runs as the user.

C remains memory-unsafe and relies on the reviewed bounds, platform libraries, compiler mitigations and tests. Sanitizers are used in tests, not shipped as a replacement for correct code. Apple CUPS, the SDK/compiler, GitHub Actions and the maintainer account remain dependencies. Source builds reduce dependence on supplied executables but preserve source defects and compiler trust.

Deadlines bound protocol/status retry loops. A CUPS call may consume the remainder of its individual I/O timeout before an outer deadline is noticed; this is not a real-time guarantee for every OS operation. Backend writes and OS scheduling remain platform responsibilities. Cancellation exits without trying to perform blocking protocol I/O inside a signal handler; a cancelled job can still require a printer power cycle. Paper-out/user recovery and shortened failure paths require physical tests. The legacy protocol's ambiguous binary/BCD length compatibility remains inherited and needs real-device coverage.

The source installer assumes the invoking user trusts and controls their checkout. It is not a privilege boundary against that same user replacing code they ask sudo to install. System directories must be root-owned and not writable by other users. If interrupted between the two file replacements or queue creation, installation may be partial; rerun the reviewed installer rather than changing system protections.

No network printer service or sharing is enabled by the CLI. Configuring sharing separately expands exposure. Uninstalling the fork does not clean up original-upstream services. The menu app uses local IPP via a system helper; its subprocess watchdog and output limits reduce resource consumption but do not prove the underlying helper bug-free.

## Reporting

Use this repository's GitHub **Report a vulnerability** feature if private reporting is available. Otherwise, contact the repository owner through a private channel you already trust; do not post sensitive exploit details or print documents in public issues. Public issues are suitable for nonsensitive crashes, build failures and proposed hardening changes. Include the source commit, macOS version, CPU and sanitized diagnostics; omit document contents, names, printer serial numbers and authentication material. No fixed response-time SLA is promised.

## References

- [CUPS filter security and sandbox model](https://openprinting.github.io/cups/doc/api-filter.html)
- [Apple Gatekeeper and runtime protections](https://support.apple.com/guide/security/sec5599b66df/web)
- [GitHub artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)
