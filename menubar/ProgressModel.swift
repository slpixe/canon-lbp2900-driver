// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct JobProgress: Equatable {
    let current: Int
    let total: Int?
}

// Select the first job only. Document names are deliberately not requested.
func parseProgress(_ text: String) -> JobProgress? {
    var found = false
    var current = 0
    var total: Int?
    for line in text.split(separator: "\n") {
        let fields = line.components(separatedBy: " = ")
        guard fields.count == 2 else { continue }
        let attribute = fields[0].trimmingCharacters(in: .whitespaces)
        guard let value = Int(fields[1].trimmingCharacters(in: .whitespaces)) else { continue }
        if attribute == "job-id (integer)" {
            if found { break }
            found = value > 0
        } else if found && attribute == "job-media-sheets-completed (integer)" {
            current = max(0, value)
        } else if found && attribute == "job-impressions (integer)" && value > 0 {
            total = value
        }
    }
    return found ? JobProgress(current: current, total: total) : nil
}
