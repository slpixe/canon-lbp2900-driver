import Foundation
@main struct Tests {
    static func main() {
        assert(parseProgress("no jobs") == nil)
        assert(parseProgress("job-id (integer) = 1\njob-media-sheets-completed (integer) = 2\njob-media-sheets (integer) = 5") == JobProgress(current: 2, total: 5))
        assert(parseProgress("job-id (integer) = 1\njob-media-sheets-completed (integer) = -3\njob-id (integer) = 2\njob-media-sheets-completed (integer) = 9") == JobProgress(current: 0, total: nil))
        assert(parseProgress("job-id (integer) = invalid") == nil)
        assert(parseProgress("job-id (integer) = 1\njob-state (enum) = pending-held\njob-media-sheets-completed (integer) = 0") == JobProgress(current: 0, total: nil, held: true))
        assert(parseProgress("job-id (integer) = 1\njob-impressions (integer) = 4")?.total == nil)
        assert(queuePaused("printer-state (enum) = stopped"))
        assert(!queuePaused("printer-state (enum) = idle"))
        assert(DriverChoice(rawValue: "unknown") == nil)
        assert(DriverChoice.c.queue != DriverChoice.rust.queue)
        let devices = discoverPrinters("direct usb://Other/Printer\ndirect usb://Canon/LBP2900?serial=test1234\ndirect usb://Canon/LBP2900?serial=test1234\nnetwork ipp://example.invalid\ndirect usb://Canon/LBP2900?serial=x extra")
        assert(devices.count == 1 && devices[0].label == "Canon LBP2900 · USB ending 1234")
        for bad in ["usb://Canon/LBP2900?serial=a\nmore", "usb://Canon/LBP2900B", "usb://Canon/LBP2900/other", "ipp://Canon/LBP2900", "usb://Canon/LBP2900?" + String(repeating: "a", count: 2048)] { assert(!validPrinterURI(bad)) }
        // Round-trip shell data with quotes, metacharacters and Unicode. No data
        // is executed; the fixed printf command receives exactly one argument.
        for value in ["simple", "a'b\"c", "$(printf unwanted)`printf unwanted`; & | < >", "printer name Ω"] {
            let task = Process(), output = Pipe()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "printf %s " + shellQuote(value)]
            task.standardOutput = output; try! task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
            assert(task.terminationStatus == 0 && String(data: data, encoding: .utf8) == value)
        }
        print("Menu progress, queue selection, discovery and argument quoting passed")
    }
}
