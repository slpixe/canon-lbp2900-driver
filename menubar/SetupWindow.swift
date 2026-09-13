// SPDX-License-Identifier: GPL-3.0-or-later
import Cocoa

final class SetupWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private let printer = NSPopUpButton(), driver = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "Connect your printer by USB and turn it on, then search.")
    private let detail = NSTextField(wrappingLabelWithString: "No printer selected")
    private let search = NSButton(title: "Search for printers", target: nil, action: nil)
    private let install = NSButton(title: "Review installation…", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private var printers: [USBPrinter] = []
    private var busy = false
    var isBusy: Bool { busy }
    private let onInstalled: (DriverChoice) -> Void
    private let quitOnClose: Bool
    private var resources: URL { Bundle.main.resourceURL!.appendingPathComponent("DriverPayload") }
    init(quitOnClose: Bool = false, onInstalled: @escaping (DriverChoice) -> Void) {
        self.quitOnClose = quitOnClose; self.onInstalled = onInstalled
        super.init()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 490), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Set up Canon LBP2900"; window.delegate = self; window.isReleasedWhenClosed = false
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28), root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28), root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 26)])
        let title = NSTextField(labelWithString: "Your printer. Your choice.")
        title.font = .systemFont(ofSize: 25, weight: .semibold); root.addArrangedSubview(title)
        let intro = NSTextField(wrappingLabelWithString: "Choose a connected LBP2900 and the driver you want to use. The progress app is optional after setup.")
        intro.textColor = .secondaryLabelColor; root.addArrangedSubview(intro)
        root.addArrangedSubview(NSTextField(labelWithString: "Printer"))
        printer.addItem(withTitle: "Select a printer after searching"); printer.isEnabled = false
        printer.target = self; printer.action = #selector(selectionChanged)
        search.target = self; search.action = #selector(scan)
        let row = NSStackView(views: [printer, search]); row.spacing = 12; root.addArrangedSubview(row)
        printer.widthAnchor.constraint(equalToConstant: 320).isActive = true
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor; detail.isSelectable = true
        root.addArrangedSubview(detail)
        root.addArrangedSubview(NSTextField(labelWithString: "Driver"))
        for choice in DriverChoice.allCases { driver.addItem(withTitle: choice.label) }
        driver.autoenablesItems = false
        if !FileManager.default.fileExists(atPath: resources.appendingPathComponent(DriverChoice.rust.filter).path) {
            driver.item(at: 1)?.isEnabled = false
            driver.item(at: 1)?.title = "Rust — not included in this build"
        }
        driver.target = self; driver.action = #selector(selectionChanged); root.addArrangedSubview(driver)
        let note = NSTextField(wrappingLabelWithString: "C is the default. Rust is an opt-in experiment with a separate print queue. Both use the same USB printer; print through one queue at a time.")
        note.textColor = .secondaryLabelColor; root.addArrangedSubview(note)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let progress = NSStackView(views: [spinner, status]); progress.spacing = 8; root.addArrangedSubview(progress)
        install.target = self; install.action = #selector(review); install.isEnabled = false
        root.addArrangedSubview(install)
        for view in [intro, detail, note, status] { view.preferredMaxLayoutWidth = 550 }
    }
    func show() { window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !busy }
    func windowWillClose(_ notification: Notification) { if quitOnClose { NSApp.terminate(nil) } }
    private var choice: DriverChoice { driver.indexOfSelectedItem == 1 ? .rust : .c }
    private var selected: USBPrinter? { let i = printer.indexOfSelectedItem - 1; return printers.indices.contains(i) ? printers[i] : nil }
    private func working(_ value: Bool) {
        busy = value; search.isEnabled = !value; driver.isEnabled = !value
        printer.isEnabled = !value && !printers.isEmpty
        install.isEnabled = !value && selected != nil
        if value { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
    @objc private func finish() { window.close() }
    @objc private func selectionChanged() {
        install.title = "Review installation…"; install.action = #selector(review)
        detail.stringValue = selected?.uri ?? "No printer selected"
        install.isEnabled = !busy && selected != nil
    }
    @objc private func scan() {
        install.title = "Review installation…"; install.action = #selector(review)
        working(true); status.stringValue = "Searching connected USB printers…"
        printers = []; printer.removeAllItems(); printer.addItem(withTitle: "Select your printer"); detail.stringValue = "No printer selected"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = systemQuery("/usr/sbin/lpinfo", ["--include-schemes", "usb", "--timeout", "5", "-v"], timeout: 15)
            DispatchQueue.main.async {
                self.printers = result.status == 0 ? discoverPrinters(result.output) : []
                for device in self.printers { self.printer.addItem(withTitle: device.label) }
                self.status.stringValue = result.status != 0 ? "Search failed. Check the printer connection and try again." : self.printers.isEmpty ? "No supported printer found. Turn on your LBP2900, check the USB cable and search again." : "Select your printer above. Nothing has been installed."
                self.working(false)
            }
        }
    }
    @objc private func review() {
        guard let device = selected, validPrinterURI(device.uri), !busy else { return }
        let selectedDriver = choice
        let alert = NSAlert(); alert.messageText = "Install \(selectedDriver.shortLabel) driver for this printer?"
        alert.informativeText = "\(device.label)\n\nThis copies the locally built filter and printer definition into system printer folders, and creates or updates the queue \(selectedDriver.queue). macOS will ask for administrator authorization.\n\nSharing stays off. Your default printer and login startup are unchanged."
        alert.addButton(withTitle: "Install driver"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { self.performInstall(device, selectedDriver) }
        }
    }
    private func performInstall(_ device: USBPrinter, _ choice: DriverChoice) {
        working(true); status.stringValue = "Preparing installation…"
        DispatchQueue.global(qos: .userInitiated).async {
            var message = "Installation failed. No success was confirmed."
            var success = false
            // Private staging outside Documents avoids root/TCC access to a
            // checkout. The authenticated user explicitly trusts this local build.
            let staging = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("lbp2900-install-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                for file in [choice.filter, choice.ppd, "install-driver.sh"] {
                    let source = self.resources.appendingPathComponent(file), target = staging.appendingPathComponent(file)
                    let attrs = try fm.attributesOfItem(atPath: source.path)
                    guard attrs[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileReadInvalidFileName) }
                    try fm.copyItem(at: source, to: target)
                    try fm.setAttributes([.posixPermissions: file == choice.ppd ? 0o400 : 0o500], ofItemAtPath: target.path)
                }
                let verify = systemQuery("/usr/bin/codesign", ["--verify", "--strict", staging.appendingPathComponent(choice.filter).path])
                guard verify.status == 0 else { throw CocoaError(.fileReadCorruptFile) }
                let args = ["/usr/bin/env", "SUDO_UID=\(getuid())", "/bin/bash", staging.appendingPathComponent("install-driver.sh").path] + (choice == .rust ? ["--rust"] : []) + ["install", staging.appendingPathComponent(choice.filter).path, staging.appendingPathComponent(choice.ppd).path, device.uri]
                let source = "do shell script " + appleScriptString(args.map(shellQuote).joined(separator: " ")) + " with administrator privileges"
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                let reply = script?.executeAndReturnError(&error)
                if error == nil && reply != nil {
                    let check = systemQuery("/usr/bin/lpstat", ["-p", choice.queue])
                    success = check.status == 0
                    message = success ? "Installed. Select \(choice.queue) in your print dialog. You can close this window; the menu app is optional." : "Files copied, but the queue could not be verified. Reconnect the printer and try setup again."
                } else if (error?[NSAppleScript.errorNumber] as? Int) == -128 { message = "Installation cancelled. You can try again when ready." }
                else { message = "Installation stopped. Check that both Canon queues have no active jobs and the printer is connected, then try again. If macOS rejected the build, use the repository’s build and signature checks." }
            } catch { message = "The driver payload is missing or invalid. Rebuild this app from the reviewed source before installing." }
            DispatchQueue.main.async {
                self.status.stringValue = message; self.working(false)
                if success {
                    self.install.title = "Done"; self.install.action = #selector(self.finish)
                    self.onInstalled(choice)
                }
            }
        }
    }
}
