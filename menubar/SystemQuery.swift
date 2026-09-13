// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

struct CommandResult { let status: Int32; let output: String }
// Fixed system tools only. Call off the UI thread. Bound output and wall time;
// terminate then kill an unresponsive child instead of blocking Quit forever.
func systemQuery(_ executable: String, _ arguments: [String], timeout: Double = 8) -> CommandResult {
    let task = Process(), pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
    task.standardInput = FileHandle.nullDevice
    task.standardOutput = pipe; task.standardError = pipe
    do { try task.run() } catch { return CommandResult(status: -1, output: "Could not start the system printer tool.") }
    let watchdog = DispatchWorkItem { if task.isRunning { task.terminate() } }
    let hardStop = DispatchWorkItem { if task.isRunning { kill(task.processIdentifier, SIGKILL) } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1, execute: hardStop)
    defer { watchdog.cancel(); hardStop.cancel() }
    var data = Data()
    while let chunk = try? pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
        if data.count + chunk.count > 65536 {
            if task.isRunning { task.terminate() }
            try? pipe.fileHandleForReading.close(); task.waitUntilExit()
            return CommandResult(status: -1, output: "Printer tool output exceeded its limit.")
        }
        data.append(chunk)
    }
    task.waitUntilExit()
    return CommandResult(status: task.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
}
let jobsQuery = """
{ OPERATION Get-Printer-Attributes
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri $uri
  ATTR keyword requested-attributes printer-state
  STATUS successful-ok
}
{ OPERATION Get-Jobs
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri $uri
  ATTR name requesting-user-name $user
  ATTR boolean my-jobs true
  ATTR integer limit 1
  ATTR keyword which-jobs not-completed
  ATTR keyword requested-attributes job-id,job-state,job-media-sheets-completed,job-media-sheets
  STATUS successful-ok
}
"""
