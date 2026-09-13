# Hardware results and real-world validation

Both implementations have passed a physical single-page smoke test. This establishes basic printing on the tested host; it does not establish every supported setting or recovery path. C on `main` is the default source-build choice. Rust on `experiment/rust-driver` remains opt-in while broader use and review accumulate.

## Confirmed results — 2026-09-13

Printer: Canon LBP2900 via USB. Host: Apple M1 Pro, macOS 26.6.2. Each job was one A4, single-sided, 600 dpi page, one copy.

| Implementation | Exact tested source | Result |
| --- | --- | --- |
| C | `cb24b6c4746fa0e671c1d591b5e3ac8ba92c02ff` | CUPS completed, one sheet; owner confirmed good border and text |
| Rust | `3ae59529d1b872b33790995b5c70b0b5176707b7` | CUPS completed, one sheet; owner confirmed visually equivalent output |

The original C job stopped at the periodic data-transfer status poll. [PR #2](https://github.com/slpixe/canon-lbp2900-driver/pull/2), now merged into `main`, keeps LBP2900 transfer polling on extended status, matching its job/page setup. Rust contains the equivalent change. Length/capacity validation was retained. Regression checks cover the 16th-chunk boundary; automated CI passed for both tested branches.

Builds target arm64 macOS 15.0+. The intended M1 MacBook / Sequoia 15.7.4 installation is still awaiting a real-user result. CI on macOS 15 is not physical printing evidence. LBP2900B and other host/model combinations must not be inferred from the LBP2900 result; the Rust filter currently accepts only LBP2900 identification.

## Contribute during normal use

No more dedicated pages are required now. Install the C version, optionally add the menu app, and use the printer for ordinary work. Experimental users may choose the separate Rust queue. Do not submit to both queues at once. Comment on the relevant issue when a scenario occurs; maintainers can update its checklist from the report. Leave untried items unchecked.

- [#3 Everyday printing, multiple pages/copies and output options](https://github.com/slpixe/canon-lbp2900-driver/issues/3)
- [#4 Cancellation and printer recovery](https://github.com/slpixe/canon-lbp2900-driver/issues/4)
- [#5 Sequoia installation, updates and removal](https://github.com/slpixe/canon-lbp2900-driver/issues/5)
- [#6 Optional menu app, progress, login startup and Quit](https://github.com/slpixe/canon-lbp2900-driver/issues/6)

Maintainer follow-ups: [#7 deterministic reply-length fix](https://github.com/slpixe/canon-lbp2900-driver/issues/7) and [#8 signed releases / Rust adoption review](https://github.com/slpixe/canon-lbp2900-driver/issues/8). These do not undo the proven transfer fix or require holding it out of `main`.

Suggested report:

```text
Implementation and source commit:
Printer model (omit serial):
Apple chip and macOS version:
Install method / relevant print settings:
Scenario during normal use:
Expected result / observed result:
Pass, fail, or not tried:
```

Do not post private document titles/content, usernames, printer serial numbers or raw unredacted logs. Do not deliberately cause a jam. The driver-only path needs no menu app, login item or new background service. Hardware success is not a security certification; see SECURITY.md and the release-verification instructions.

## Setup and menu follow-up — 2026-09-13

The owner reported the new graphical setup worked. The installed C filter was byte-compared with the local build containing the deterministic reply-length fix, and strict signature verification passed. This confirms installation, not a further physical print.

The menu's exact IPP query/parser passed idle, held-job (zero completed sheets), missing-queue and return-to-idle tests for both C and Rust queues. Both test jobs were cancelled without release. The UI now supports explicit C/Rust selection; visual menu switching and physical progress remain separate checks in issue #6.

The issue #7 regression failed against both old receivers using the same published LBP2900 device fixture and passed after both fixes. See [protocol policy and compatibility limits](PROTOCOL-LENGTHS.md). The prior single-page print results above must not be read as a hardware retest of the new framing policy.
