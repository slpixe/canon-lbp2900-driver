// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum DriverChoice: String, CaseIterable {
    case c, rust
    var label: String { self == .c ? "C — recommended" : "Rust — experimental" }
    var shortLabel: String { self == .c ? "C" : "Rust" }
    var queue: String { self == .c ? "Canon_LBP2900_Slpixe" : "Canon_LBP2900_Rust_Experiment" }
    var filter: String { self == .c ? "rastertocapt-lbp2900" : "rastertocapt-lbp2900-rust" }
    var ppd: String { self == .c ? "CanonLBP2900-Slpixe.ppd" : "CanonLBP2900-Rust-Experimental.ppd" }
}
struct USBPrinter: Equatable {
    let uri: String
    var label: String {
        let serial = URLComponents(string: uri)?.queryItems?.first(where: { $0.name == "serial" })?.value
        return "Canon LBP2900" + (serial.map { " · USB ending \($0.suffix(4))" } ?? " · USB")
    }
}
func validPrinterURI(_ value: String) -> Bool {
    guard value.utf8.count <= 2048,
          !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { return false }
    return value == "usb://Canon/LBP2900" || value.hasPrefix("usb://Canon/LBP2900?") || value.hasPrefix("usb://Canon/LBP%202900?")
}
func discoverPrinters(_ text: String) -> [USBPrinter] {
    var seen = Set<String>()
    return text.split(separator: "\n").compactMap { line in
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2, parts[0] == "direct", validPrinterURI(String(parts[1])), seen.insert(String(parts[1])).inserted else { return nil }
        return USBPrinter(uri: String(parts[1]))
    }.sorted { $0.uri < $1.uri }
}
// Quote data for the one reviewed administrator shell command. Never interpolate
// URIs, paths or file contents as shell/AppleScript source without quoting.
func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func appleScriptString(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
}
