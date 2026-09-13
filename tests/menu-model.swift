import Foundation
@main struct Tests {
    static func main() {
        assert(parseProgress("no jobs") == nil)
        assert(parseProgress("job-id (integer) = 1\njob-media-sheets-completed (integer) = 2\njob-impressions (integer) = 5") == JobProgress(current: 2, total: 5))
        assert(parseProgress("job-id (integer) = 1\njob-media-sheets-completed (integer) = -3\njob-id (integer) = 2\njob-media-sheets-completed (integer) = 9") == JobProgress(current: 0, total: nil))
        assert(parseProgress("job-id (integer) = invalid") == nil)
        print("Menu progress parsing passed")
    }
}
