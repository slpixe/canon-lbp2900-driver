# Canon LBP2900 driver for Apple Silicon

A source-first, security-hardened fork of the community CAPT driver for Canon LBP2900 / LBP2900B printers. Build it yourself, install only the driver, and add the menu-bar progress app only if you want it.

**Source-build preview: single-page printing confirmed in both C and Rust.** On 2026-09-13, an LBP2900 printed one A4, single-sided, 600 dpi page with each implementation on an Apple M1 Pro running macOS 26.6.2. The owner confirmed good C text/border and visually equivalent Rust output. Broader everyday-use and recovery results are tracked in [validation issues](docs/HARDWARE-TESTING.md). This is unofficial software, not endorsed or certified by Canon or Apple. Do not treat the word “hardened” as a guarantee of safety.

Target: **Apple Silicon (M1 and later), macOS 15 Sequoia or later**. Compilation targets macOS 15.0. Physical testing used macOS 26.6.2; printing on Sequoia 15.7.4 remains unverified (macOS 15 CI covers builds and offline tests). Intel distribution is not currently supported.

## Choose C or Rust

| Version | Branch | How to build/install | Status |
| --- | --- | --- | --- |
| **C — default for normal use** | `main` | Follow the commands below | Hardware transfer fix merged in [PR #2](https://github.com/slpixe/canon-lbp2900-driver/pull/2); one physical page confirmed |
| **Rust — optional experiment** | `experiment/rust-driver` | [Rust build and separate queue instructions](https://github.com/slpixe/canon-lbp2900-driver/blob/experiment/rust-driver/docs/RUST.md) | Equivalent fix included; one physical page confirmed; [PR #1](https://github.com/slpixe/canon-lbp2900-driver/pull/1) remains experimental |

**Checking out the Rust branch does not select Rust automatically.** The ordinary `build.sh` / `install.sh --driver` still select C on either branch. Use `./setup.sh --rust` on the Rust branch for an explicit C/Rust installation choice, or its documented manual build/install path. Keep the C queue available and do not send jobs to both queues simultaneously: they share one USB printer.

Choose current `main` source for C. The older `v2.0.0-alpha.1` development artifacts predate the transfer fix; they are not the hardware-validated build. Neither implementation currently has a signed, notarized end-user release.

## Choose what you need

| Component | Purpose | Administrator access | Background behavior |
| --- | --- | --- | --- |
| Driver + printer definition | Lets CUPS produce CAPT printer data | Yes, for installation only | Runs for print jobs; no added root service |
| Printer queue | Connects this driver to one explicitly selected USB device | Yes | Normal macOS print queue, unshared by the CLI installer |
| Menu-bar app | Shows completion counts for your own jobs | No; installs in your Applications folder | Open when needed; Start at Login is off until you choose it |

There is no automatic updater or “self-healing” daemon. No kernel extension, Rosetta, reduced boot security, SIP change, or quarantine removal is part of the installation. Quit really quits the menu app; optional login startup applies at the next login.

## Build and inspect

1. Install Apple's Xcode Command Line Tools using `xcode-select --install` if needed. Homebrew is not required for the normal build.
2. Clone this repository and inspect the source and scripts. Record the commit you are building; `main` can change.

```sh
git clone --branch main https://github.com/slpixe/canon-lbp2900-driver.git
cd canon-lbp2900-driver
git rev-parse HEAD
./build.sh --driver
./install.sh --driver --dry-run
```

Builds run as your normal account. **Never run the build with sudo.** The script compiles source using Apple's installed tools and system CUPS; it does not download dependencies or fall back to a supplied executable. No prebuilt executable is tracked in the current source tree. Older binaries remain in upstream Git history for provenance.

For the optional app, use `./build.sh --menubar` (includes a freshly compiled C payload for opt-in setup; building the app installs nothing). To build both, use `./build.sh --all`. Detailed compiler commands, tests, output inspection and limitations are in [BUILD.md](docs/BUILD.md).

## Install with the printer-selection window

From your reviewed source checkout, run:

```sh
./setup.sh
```

This builds locally and opens **Set up Canon LBP2900**. Click **Search for printers**, select your connected USB printer, choose **C — recommended**, and click **Review installation…**. The review names the queue to create/update. Only **Install driver** requests administrator authorization. Click **Done** afterward; the driver works without the app running. Searching or cancelling installs nothing. The default printer, sharing and login startup are not changed.

The same window is available under **Set Up Printer…** in the optional menu app. To include Rust installation, use the experimental branch and `./setup.sh --rust`; this explicitly builds both payloads using the pinned Rust toolchain. Without that option, Rust installation is disabled, but monitoring an already installed Rust queue still works.

## Install the driver from the command line

Connect and power on the printer. List available device URIs:

```sh
/usr/sbin/lpinfo -v
```

Copy the **exact** `usb://Canon/LBP2900...` URI for your printer and use it below; the quoted text is a placeholder:

```sh
./install.sh --driver --uri 'PASTE_THE_EXACT_USB_URI_HERE'
```

This rebuilds the filter locally, then requests your administrator password for the narrow file-copy and queue-creation step. It refuses a non-Canon URI or an address not reported by the currently connected devices. The queue is named `Canon_LBP2900_Slpixe`; select **Canon LBP2900 (community driver)** in print dialogs. A failed job stops the queue rather than silently being treated as printed.

To install only driver files, without creating a queue:

```sh
./install.sh --driver
```

You can later rerun with the explicit URI. Alternatively, use System Settings → Printers & Scanners → Add Printer → select the USB printer → Use → Other, then choose `/Library/Printers/PPDs/Contents/Resources/CanonLBP2900-Slpixe.ppd`. Give the printer the name `Canon_LBP2900_Slpixe` if you want the progress app to find this queue. Keep printer sharing disabled. This GUI route has not yet been verified on a physical Sequoia setup.

Only these driver files are installed:

- `/usr/libexec/cups/filter/rastertocapt-lbp2900` (root:wheel, 0755)
- `/Library/Printers/PPDs/Contents/Resources/CanonLBP2900-Slpixe.ppd` (root:wheel, 0644)

A major OS update may remove the filter. Rebuild and reinstall deliberately afterward; this fork does not restore code automatically at boot.

## Optional menu-bar app

```sh
./install.sh --menubar
```

Open `~/Applications/LBP2900Progress.app` when you need it. Use **Start at Login** in its menu to opt in or out through macOS ServiceManagement. Login registration needs testing on the target Mac, particularly for locally signed builds. An existing application is not overwritten while it might be running: quit and move it to Trash before reinstalling.

Choose **Monitor C** or **Monitor Rust** in the app menu. It watches the corresponding fixed queue (`Canon_LBP2900_Slpixe` or `Canon_LBP2900_Rust_Experiment`) and remembers your choice. Switching monitoring does not install a driver, move jobs or change your default printer. Menu validation is tracked in [issue #6](https://github.com/slpixe/canon-lbp2900-driver/issues/6). The app queries only localhost, requests only your jobs and does not request document titles. It uses a private temporary query file, bounded output, a helper timeout and one query at a time. Held jobs and paused queues are distinguished from idle queues. Counts compare completed sheets to total sheets when the total is available, otherwise show only the completed count. Counts reflect the driver's completion report; they are not a guarantee that every physical sheet ejected correctly.

## Releases and trust

See [RELEASES.md](docs/RELEASES.md). CI can produce a driver-only `.pkg`, a separate menu-app `.zip`, SHA-256 checksums, build metadata and GitHub artifact attestations. Release publication starts as a **draft prerelease** and requires maintainer review. Development packages are named `UNSIGNED` and must not be presented as trusted click-to-install releases.

For ordinary end-user distribution, the maintainer must provide Developer ID signing, notarization and physical printer test results. This repository cannot supply an Apple identity or assert notarization simply by creating a package. No instructions to disable or work around macOS security checks are provided.

## Tests, known limits and removal

```sh
./scripts/test.sh       # offline ASan/UBSan tests; requires Python 3
./scripts/doctor.sh     # read-only diagnostics, no document titles
./uninstall.sh --driver --dry-run
./uninstall.sh --driver
./uninstall.sh --menubar
```

Disable Start at Login in the app before removing it, then Quit and move the application to Trash. The CLI uninstaller removes only this fork's queue/files and package receipt. It does not delete another driver or print queue.

If you installed the original project, read [MIGRATION.md](docs/MIGRATION.md); its old daemon/app are not automatically removed. Use the [hardware results and open checklists](docs/HARDWARE-TESTING.md) to report normal real-world use; extra test pages are not required to contribute. See [SECURITY.md](SECURITY.md) for the threat model, changes and remaining risks, and [LANGUAGE.md](docs/LANGUAGE.md) for the Rust/Go assessment.

## Credits and license

Derived from [duy12i1i7/canon-LBP2900-for-macOS](https://github.com/duy12i1i7/canon-LBP2900-for-macOS), itself based on [mounaiban/captdriver](https://github.com/mounaiban/captdriver). Original CAPT reverse engineering and authorship remain credited in [AUTHORS](captdriver/AUTHORS) and the source headers. GPLv3; see [LICENSE](LICENSE). Source files marked “or later” retain that permission. [PROVENANCE.md](docs/PROVENANCE.md) records the starting commits and fork changes.
