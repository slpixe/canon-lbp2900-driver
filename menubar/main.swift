// SPDX-License-Identifier: GPL-3.0-or-later
import Cocoa
import ServiceManagement

final class ProgressWatcher: NSObject {
    private var choice = DriverChoice(rawValue: UserDefaults.standard.string(forKey: "monitoredDriver") ?? "") ?? .c
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "Checking printer…", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var choices: [NSMenuItem] = []
    private var timer: Timer?
    private var inFlight = false
    private var closing = false
    private var setup: SetupWindow?
    private let queryDirectory: URL
    private let queryFile: URL
    override init() {
        queryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("lbp2900-" + UUID().uuidString)
        queryFile = queryDirectory.appendingPathComponent("jobs.test")
        super.init()
        do {
            try FileManager.default.createDirectory(at: queryDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try Data(jobsQuery.utf8).write(to: queryFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: queryFile.path)
        } catch {
            let alert = NSAlert(); alert.messageText = "Cannot create a private printer query file"
            alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.terminate(nil); return
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Canon LBP2900", action: nil, keyEquivalent: ""))
        menu.addItem(statusLine); menu.addItem(.separator())
        for (index, driver) in DriverChoice.allCases.enumerated() {
            let item = NSMenuItem(title: "Monitor \(driver.label)", action: #selector(selectDriver(_:)), keyEquivalent: "")
            item.tag = index; item.target = self; menu.addItem(item); choices.append(item)
        }
        let configure = NSMenuItem(title: "Set Up Printer…", action: #selector(showSetup), keyEquivalent: "")
        configure.target = self; menu.addItem(configure); menu.addItem(.separator())
        loginItem.target = self; menu.addItem(loginItem); refreshLoginState()
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); statusItem.menu = menu
        updateSelection()
        timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        // Keep polling while a user has the menu open.
        RunLoop.main.add(timer!, forMode: .common)
        poll()
    }
    private func updateSelection() {
        for (i, item) in choices.enumerated() { item.state = DriverChoice.allCases[i] == choice ? .on : .off }
        statusItem.button?.title = "🖨 \(choice.shortLabel)"
        statusLine.title = "Checking \(choice.shortLabel) queue…"
        statusItem.button?.setAccessibilityLabel("Canon LBP2900 \(choice.shortLabel) progress")
    }
    @objc private func selectDriver(_ item: NSMenuItem) { choose(DriverChoice.allCases[item.tag]) }
    private func choose(_ selected: DriverChoice) {
        choice = selected; UserDefaults.standard.set(choice.rawValue, forKey: "monitoredDriver")
        updateSelection(); poll()
    }
    @objc private func showSetup() {
        if setup == nil { setup = SetupWindow { [weak self] choice in self?.choose(choice) } }
        setup?.show()
    }
    private func refreshLoginState() { loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Could not change login startup"
            alert.informativeText = "Install this app in Applications first. " + error.localizedDescription; alert.runModal()
        }
        refreshLoginState()
    }
    @objc private func quitApp() {
        guard setup?.isBusy != true else { return }
        closing = true; timer?.invalidate()
        try? FileManager.default.removeItem(at: queryDirectory)
        NSApp.terminate(nil)
    }
    @objc private func poll() {
        guard !inFlight && !closing else { return }
        inFlight = true
        let selected = choice
        DispatchQueue.global(qos: .utility).async {
            let result = systemQuery("/usr/bin/ipptool", ["-T", "5", "-tv", "ipp://localhost/printers/\(selected.queue)", self.queryFile.path])
            DispatchQueue.main.async {
                self.inFlight = false
                guard !self.closing else { return }
                guard self.choice == selected else { self.poll(); return }
                let prefix = "🖨 \(selected.shortLabel)"
                guard result.status == 0 else {
                    self.statusItem.button?.title = "\(prefix) ?"
                    self.statusLine.title = "\(selected.shortLabel) queue unavailable — use Set Up Printer…"; return
                }
                if queuePaused(result.output) {
                    self.statusItem.button?.title = "\(prefix) ⏸"
                    self.statusLine.title = "Queue paused — check macOS Print Center"; return
                }
                guard let job = parseProgress(result.output) else {
                    self.statusItem.button?.title = prefix
                    self.statusLine.title = "No active jobs for your account"; return
                }
                let count = job.total.map { "\(job.current)/\($0)" } ?? "\(job.current)"
                self.statusItem.button?.title = "\(prefix) \(count)"
                self.statusLine.title = (job.held ? "Job held — " : "") + "Sheets reported complete: \(count)"
            }
        }
    }
}
let application = NSApplication.shared
let setupOnly = CommandLine.arguments.contains("--setup-only")
application.setActivationPolicy(setupOnly ? .regular : .accessory)
var watcher: ProgressWatcher?
var setupWindow: SetupWindow?
if setupOnly { setupWindow = SetupWindow(quitOnClose: true) { _ in }; setupWindow?.show() }
else { watcher = ProgressWatcher() }
application.run()
