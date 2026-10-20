import Foundation

/// Standalone geometric checks; this does not exercise UIKit, an SDK build, or a device.
@main
enum SwipeDecoderChecks {
    static func main() throws {
        let rows = [("qwertyuiop", 0.0), ("asdfghjkl", 0.25), ("zxcvbnm", 0.75)]
        let keys = rows.enumerated().flatMap { rowIndex, row in
            row.0.enumerated().map { index, letter in
                SwipeKey(letter: String(letter), x: (Double(index) + row.1) * 40, y: Double(rowIndex) * 45)
            }
        }
        let centers = Dictionary(uniqueKeysWithValues: keys.map {
            ($0.letter, SwipePoint(x: $0.x, y: $0.y))
        })
        func path(_ text: String) -> [SwipePoint] {
            text.map { centers[String($0)]! }
        }
        let words = [
            SwipeWord(text: "hello", weight: 100), SwipeWord(text: "helo", weight: 1),
            SwipeWord(text: "world", weight: 90), SwipeWord(text: "help", weight: 100),
            SwipeWord(text: "wild", weight: 100), SwipeWord(text: "keyboard", weight: 30),
        ]
        try require(SwipePathDecoder.rank(path: path("helo"), keys: keys, words: words, limit: 3).first?.text == "hello", "repeated-letter English word")
        try require(SwipePathDecoder.rank(path: path("world"), keys: keys, words: words, limit: 3).first?.text == "world", "English path shape")
        let codePath = path("abcd")
        let codes = ["abcd", "abxd", "acbd", "zzzzz", "abcccd"]
        try require(SwipePathDecoder.rankCodes(path: codePath, keys: keys, codes: codes, limit: 3).first?.code == "abcd", "four-root Cangjie shape")
        let crossedPath = path("ad")
        try require(SwipePathDecoder.rankCodes(path: crossedPath, keys: keys, codes: ["ad", "asdfg", "zz"], limit: 3).first?.code == "ad", "crossed keys are not automatically input roots")
        let jitter = codePath.enumerated().map {
            SwipePoint(x: $0.element.x + ($0.offset.isMultiple(of: 2) ? 2 : -2), y: $0.element.y + 1)
        }
        try require(SwipePathDecoder.rankCodes(path: jitter, keys: keys, codes: codes, limit: 1).first?.code == "abcd", "small coordinate jitter")
        try require(SwipePathDecoder.rankCodes(path: path("aa"), keys: keys, codes: ["a", "aa"], limit: 3).count == 2, "stationary repeated roots remain candidates")
        try require(SwipePathDecoder.rank(path: path("helo"), keys: keys, words: [SwipeWord(text: "HELLO", weight: 20)], limit: 1).first?.text == "hello", "case normalization")
        try require(SwipePathDecoder.rank(path: path("helo"), keys: keys, words: words, limit: 0).isEmpty, "zero limit")
        try require(SwipePathDecoder.rankCodes(path: [], keys: keys, codes: codes, limit: 3).isEmpty, "empty path")
        try require(SwipePathDecoder.rankCodes(path: [SwipePoint(x: .nan, y: 0), centers["a"]!], keys: keys, codes: codes, limit: 3).isEmpty, "invalid coordinate")
        let loop = [centers["a"]!, SwipePoint(x: centers["a"]!.x + 5, y: centers["a"]!.y + 5), centers["a"]!]
        try require(SwipePathDecoder.rankCodes(path: loop, keys: keys, codes: ["aa", "a", "zz"], limit: 3).contains { $0.code == "aa" }, "repeated-root loop tolerance")
        let distant = [SwipePoint(x: -1_000, y: -1_000), SwipePoint(x: -900, y: -900)]
        try require(SwipePathDecoder.rank(path: distant, keys: keys, words: words, limit: 3).isEmpty, "distant path rejected")
        print("SwipePathDecoder: PASS (12 standalone geometric checks)")
    }

    private static func require(_ condition: Bool, _ description: String) throws {
        if !condition { throw CheckError.failed(description) }
    }

    private enum CheckError: Error {
        case failed(String)
    }
}
