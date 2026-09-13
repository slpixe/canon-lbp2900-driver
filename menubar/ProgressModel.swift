// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct JobProgress: Equatable {
    let current: Int
    let total: Int?
    var held: Bool = false
}
// Compare sheets to sheets, not impressions (which differ with duplex/copies).
// Select the first current-user job. Document names are never requested.
func parseProgress(_ text: String) -> JobProgress? {
    var found = false, held = false
    var current = 0
    var total: Int?
    for line in text.split(separator: "\n") {
        let fields = line.components(separatedBy: " = ")
        guard fields.count == 2 else { continue }
        let attribute = fields[0].trimmingCharacters(in: .whitespaces)
        let raw = fields[1].trimmingCharacters(in: .whitespaces)
        if found && attribute == "job-state (enum)" { held = raw == "4" || raw == "pending-held"; continue }
        guard let value = Int(raw) else { continue }
        if attribute == "job-id (integer)" {
            if found { break }
            found = value > 0
        } else if found && attribute == "job-media-sheets-completed (integer)" { current = max(0, value) }
        else if found && attribute == "job-media-sheets (integer)" && value > 0 { total = value }
        else if found && attribute == "job-state (enum)" { held = value == 4 }
    }
    return found ? JobProgress(current: current, total: total, held: held) : nil
}
func queuePaused(_ text: String) -> Bool {
    text.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "printer-state (enum) = stopped" || $0.trimmingCharacters(in: .whitespaces) == "printer-state (enum) = 5" }
}
