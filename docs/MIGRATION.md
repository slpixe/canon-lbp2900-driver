# Migrating from the original macOS project

This fork uses distinct filter and PPD names and the queue `Canon_LBP2900_Slpixe`. It does not overwrite the original `rastertocapt` filter or silently remove another package's services.

The original project may have installed:

- `/Library/LaunchDaemons/com.lbp2900.heal.plist` and `/Library/Application Support/CanonLBP2900/`
- `~/Library/LaunchAgents/com.lbp2900.progress.plist` and its user application directory
- The original `Canon_LBP2900` queue and `rastertocapt` filter

Remove the original system driver and its user app using the **reviewed uninstall scripts from the exact original version you installed**, or have an administrator remove those known components. The original system uninstaller requires administrator access; its user-app uninstaller does not. Inspect those scripts first. Merely removing its queue leaves its boot-time restoration service able to recreate it.

This fork does not automate removal of those paths, because they may have been modified or be managed by someone else. `scripts/doctor.sh` reports whether the old service files remain. Do not run both menu apps or mistake an old working queue for successful testing of this fork.

For this fork, uninstall with `./uninstall.sh --driver`. To remove its optional app, first switch off Start at Login in the menu, then Quit and move the app to Trash.
