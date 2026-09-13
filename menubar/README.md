# Optional progress app

Build: `./build.sh --menubar` from the repository root.

Install: `./install.sh --menubar`, then open `~/Applications/LBP2900Progress.app`. No administrator privileges are needed. Nothing is added to login startup until you select **Start at Login** in the app menu. Quit does not cause automatic restart. Disable login startup before removing the app.

This app watches only your jobs on `Canon_LBP2900_Slpixe`, using localhost IPP. It does not request document titles. It does not monitor `Canon_LBP2900_Rust_Experiment` or arbitrary queue names. [Issue #6](https://github.com/slpixe/canon-lbp2900-driver/issues/6) tracks normal-use progress and login/Quit checks. It is optional; the printer driver works independently. See the root README and `docs/RELEASES.md` for source-build and signing information.
