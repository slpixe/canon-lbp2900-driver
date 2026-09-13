# Provenance

Starting macOS fork: `duy12i1i7/canon-LBP2900-for-macOS`, commit `12953b00c791ad115f3649c6e2efb7e58d413b3d` (7 July 2026).

Its vendored core matched `mounaiban/captdriver`, commit `62719249ac34633338be54bc74beddd0e7003d38` (October 2022), with the supplied `patches/lbp2900-macos.patch` applied. Only `std.h`, `capt-status.c`, `prn_lbp2900.c`, and `rastertocapt.c` differed from that core before patching; upstream's `.gitignore` was omitted.

This fork retains Git history, GPL license text, original author credits and source copyright headers. The patch in `patches/` is a historical record of the starting macOS port, not an instruction to reconstruct the hardened tree. Build the current full source tree.

The original tracked executables were removed from the current branch. They remain in historical commits and tags. Neither their ad hoc signatures nor the inherited unsigned tags supply a verified publisher identity. New release artifacts must identify their exact source commit and build environment and must not be confused with those original artifacts.

See `SECURITY.md` and the commit history for this fork's hardening changes. A known commit identifies content, not necessarily the identity or trustworthiness of its author.
