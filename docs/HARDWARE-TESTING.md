# Physical printer release gate

Current status: **not tested with a physical printer**. Compiler and offline tests are not substitutes. Record results against the exact commit/build and macOS version. The initial requested target is an M1 MacBook running Sequoia 15.7.4.

Before changing the preview label or recommending this to ordinary printer owners, test:

- Driver-only installation from source on a clean account; ownership and permissions; explicit URI selection; refusal of unrelated devices.
- A4 and Letter, small and large multi-page documents, blank pages, fine text and dense/random images; no shifted, truncated or missing output.
- Paper/media options and manual duplex; verify that new raster limits accept legitimate output from macOS PrintCore.
- Paper-out, resume after reload, cover-open/jam, slow warm-up, cancellation and retry, unplug/replug, sleep/wake and power cycle.
- Physical sheet completion against CUPS accounting; timeout paths must report failure and stop the queue rather than discard pages as successful.
- Menu app installed alone, queue missing, multiple jobs, another user's jobs, local CUPS unavailable, Start at Login on/off and Quit.
- Source and signed/notarized package installation on clean Sequoia and later macOS targets, updates and removal. Verify that no old daemon or stale original queue is mistaken for this driver.
- Installation interrupted between file copies, queue creation failure and clean recovery by rerunning; OS-update behavior without an automatic restoration service.

Use nonsensitive test documents. Store sanitized expected results and environment notes; do not publish document titles, contents or printer serial numbers. A confirmed hardware result should be its own reviewed change, with date, printer model, OS version and exact artifact/source identity.
