# Optional progress and printer setup app

Build with `./build.sh --menubar`; install the app with `./install.sh --menubar` and open `~/Applications/LBP2900Progress.app`. No administrator access is needed to build, install or run the app. Driver installation is a separate, explicit action requiring administrator authorization.

- Choose **Monitor C** or **Monitor Rust** to watch that version's queue. The selected version appears beside the printer icon. Selection is remembered; it does not change the default printer or release/move jobs.
- Counts use completed/total **sheets** (not impressions). If CUPS has no total, only the completed count is shown. Held jobs and paused queues have explicit labels. Only your own jobs are requested; no titles are requested.
- **Set Up Printer…** discovers connected LBP2900 USB devices. Select one, choose the driver, review the queue change and then authorize installation. The helper rechecks the exact connected URI and refuses installation/removal if either Canon queue reports outstanding jobs. It copies only the chosen filter/PPD and creates an unshared queue.
- **Start at Login** is off unless explicitly enabled through the menu. **Quit** stops monitoring; no helper restarts the app. During an administrator installation, finish/cancel it before quitting.

The app embeds a C filter built from the same checkout plus its PPD and the reviewed installer helper. It does not download driver code or compile as root. On `experiment/rust-driver`, `./build.sh --menubar --with-rust` explicitly builds and embeds the separate Rust payload too. A normal build removes any old Rust payload and disables Rust installation; it can still monitor an existing Rust queue.

For one-time setup without a menu process, run `./setup.sh` (or `./setup.sh --rust` on the Rust branch). Closing the setup-only window exits the app. The printer continues to work independently. GUI installation stages the selected local payload privately in `/private/tmp` before the macOS administrator dialog; the temporary files are removed after the attempt. Failed/interrupted installation may require rerunning setup.

Validation: the owner confirmed the C setup UI worked, and the installed filter matched the source build. Live localhost tests checked idle → held job (zero sheets) → cancelled/idle for both queues, plus a missing queue. These were held jobs, never released; no page was printed. Menu selection/formatting/discovery/argument quoting have automated checks. Visual switching, live physical sheet progression and login behavior are tracked in [issue #6](https://github.com/slpixe/canon-lbp2900-driver/issues/6).

The opt-in `tests/menu-live.swift` harness uses the same system query and parser as the app. It never creates, releases or cancels jobs, and expects both fixed queues to exist with no active jobs (or held jobs when invoked with `--held`). It is excluded from unattended CI.
