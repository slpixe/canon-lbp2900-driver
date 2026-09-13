// SPDX-License-Identifier: GPL-3.0-or-later
import Cocoa
import ServiceManagement

final class ProgressWatcher: NSObject {
    private let queue = "Canon_LBP2900_Slpixe"
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "Checking printer…", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var timer: Timer?
    private var inFlight = false // accessed only on the main queue
    private let queryDirectory: URL
    private let queryFile: URL

    override init() {
        queryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("lbp2900-" + UUID().uuidString)
        queryFile = queryDirectory.appendingPathComponent("jobs.test")
        super.init()
        do {
            try FileManager.default.createDirectory(at: queryDirectory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let query = """
            { OPERATION Get-Jobs
              GROUP operation-attributes-tag
              ATTR charset attributes-charset utf-8
              ATTR naturalLanguage attributes-natural-language en
              ATTR uri printer-uri $uri
              ATTR name requesting-user-name $user
              ATTR boolean my-jobs true
              ATTR integer limit 1
              ATTR keyword which-jobs not-completed
              ATTR keyword requested-attributes job-id,job-media-sheets-completed,job-impressions
            }
            """
            try Data(query.utf8).write(to: queryFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: queryFile.path)
        } catch {
            let alert = NSAlert(); alert.messageText = "Cannot create a private printer query file"
            alert.informativeText = error.localizedDescription; alert.runModal()
            NSApp.terminate(nil); return
        }
        statusItem.button?.title = "🖨"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Canon LBP2900", action: nil, keyEquivalent: ""))
        menu.addItem(statusLine)
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        refreshLoginState()
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        poll()
    }
    private func refreshLoginState() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Could not change login startup"
            alert.informativeText = "Install this app in Applications first. " + error.localizedDescription
            alert.runModal()
        }
        refreshLoginState()
    }
    @objc private func quitApp() {
        timer?.invalidate()
        try? FileManager.default.removeItem(at: queryDirectory)
        NSApp.terminate(nil)
    }
    private func query() -> (Bool, JobProgress?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ipptool")
        // ipptool applies its own I/O timeout. Only one query can be in flight.
        task.arguments = ["-T", "5", "-tv", "ipp://localhost/printers/\(queue)", queryFile.path]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return (false, nil) }
        // A separate watchdog also stops a helper that fails to honor its timeout.
        let watchdog = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        defer { watchdog.cancel() }
        var data = Data()
        while true {
            guard let chunk = try? output.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty else { break }
            if data.count + chunk.count > 65536 {
                task.terminate(); try? output.fileHandleForReading.close()
                task.waitUntilExit(); return (false, nil)
            }
            data.append(chunk)
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return (false, nil) }
        return (true, parseProgress(text))
    }
    @objc private func poll() {
        guard !inFlight else { return }
        inFlight = true
        DispatchQueue.global(qos: .utility).async {
            let (available, job) = self.query()
            DispatchQueue.main.async {
                self.inFlight = false
                guard available else {
                    self.statusItem.button?.title = "🖨 ?"
                    self.statusLine.title = "Queue unavailable — install the driver and add the printer"
                    return
                }
                guard let job = job else {
                    self.statusItem.button?.title = "🖨"
                    self.statusLine.title = "No active jobs for your account"
                    return
                }
                let count = job.total.map { "\(job.current)/\($0)" } ?? "\(job.current)"
                self.statusItem.button?.title = "🖨 \(count)"
                self.statusLine.title = "Pages reported complete: \(count)"
            }
        }
    }
}
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let watcher = ProgressWatcher()
application.run()
