// SPDX-License-Identifier: GPL-3.0-or-later
// Opt-in localhost integration test. Caller creates/cancels its own held jobs.
// This program never submits, releases or cancels a job.
import Foundation
@main struct LiveMenuTest {
    static func main() throws {
        let expectedHeld = CommandLine.arguments.contains("--held")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lbp2900-menu-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let query = dir.appendingPathComponent("jobs.test")
        try Data(jobsQuery.utf8).write(to: query)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: query.path)
        for choice in DriverChoice.allCases {
            let result = systemQuery("/usr/bin/ipptool", ["-T", "5", "-tv", "ipp://localhost/printers/\(choice.queue)", query.path])
            guard result.status == 0 else { fatalError("\(choice.shortLabel): localhost query failed") }
            let job = parseProgress(result.output)
            if expectedHeld { assert(job?.held == true && job?.current == 0) }
            else { assert(job == nil) }
            assert(!queuePaused(result.output))
            print("\(choice.shortLabel): \(expectedHeld ? "held job, zero sheets" : "idle, no jobs") passed")
        }
        let missing = systemQuery("/usr/bin/ipptool", ["-T", "5", "-tv", "ipp://localhost/printers/LBP2900_Missing_Test_Queue", query.path])
        assert(missing.status != 0)
        print("Missing queue rejected")
    }
}
