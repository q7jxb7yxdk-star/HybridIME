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
        let roots = SwipePathDecoder.rankCodes(path: path("duiop"), keys: keys, codes: ["dup", "dip", "dop"], limit: 3)
        try require(roots.first?.code == "dup", "intermediate keys retain the dup root path")
        let dipScore = SwipePathDecoder.geometricScore(path: path("duiop"), keys: keys, text: "dip")
        try require(SwipePathDecoder.prefersCangjie(chineseScore: roots[0].score, englishScore: dipScore), "dup wins over a nearby real English word")
        try require(SwipePathDecoder.lettersCrossed(path: path("dup"), keys: keys) == "duiop", "sparse path retains collinear crossed letters")
        try require(SwipePathDecoder.lettersCrossed(path: path("duiop"), keys: keys) == "duiop", "dense path retains the same literal letters")
        let rawJitter = path("duiop").map { SwipePoint(x: $0.x + 2, y: $0.y + 1) }
        try require(SwipePathDecoder.lettersCrossed(path: rawJitter, keys: keys) == "duiop", "literal key-center tolerance")
        try require(SwipePathDecoder.lettersCrossed(path: path("poud"), keys: keys) == "poiud", "literal crossing order follows reverse movement")
        try require(SwipePathDecoder.lettersCrossed(path: path("aaa"), keys: keys) == "a", "literal stationary samples do not duplicate keys")
        try require(SwipePathDecoder.lettersCrossed(path: path("aba"), keys: keys).hasSuffix("a"), "returning to a key retains its later occurrence")
        try require(SwipePathDecoder.lettersCrossed(path: [], keys: keys).isEmpty, "empty literal path")
        try require(SwipePathDecoder.lettersCrossed(path: [SwipePoint(x: .nan, y: 0), centers["a"]!], keys: keys).isEmpty, "invalid literal path")
        try require(SwipePathDecoder.lettersCrossed(path: distant, keys: keys).isEmpty, "distant path does not invent literal letters")
        try require(SwipePathDecoder.geometricScore(path: path("keyboard"), keys: keys, text: "keyboard") == 0, "English scoring supports more than five letters")
        try require(SwipePathDecoder.geometricScore(path: path("helo"), keys: keys, text: "hello") == 0, "English scoring preserves repeated letters")
        try require(SwipePathDecoder.geometricScore(path: [], keys: keys, text: "hi") == nil, "invalid English comparison")
        try require(!SwipePathDecoder.prefersCangjie(chineseScore: 0, englishScore: 0), "equal English path stays English")
        try require(!SwipePathDecoder.prefersCangjie(chineseScore: 0, englishScore: 0.03), "nearly equal English path stays English")
        try require(SwipePathDecoder.prefersCangjie(chineseScore: 0.2, englishScore: 0.4), "less exact Chinese path still needs a clear lead")
        try require(!SwipePathDecoder.prefersCangjie(chineseScore: 0.2, englishScore: 0.28), "ambiguous Chinese path does not override English")
        try require(!SwipePathDecoder.prefersCangjie(chineseScore: 0.51, englishScore: nil), "poor Chinese match is rejected even without English")
        try require(!SwipePathDecoder.prefersCangjie(chineseScore: .nan, englishScore: nil), "invalid Chinese score is rejected")
        var regressionChecks = 0
        // Previously a two-point vertical miss at u already fell back to dip.
        // Cover compact and taller key rows, not just ideal key-center paths.
        for rowHeight in [20.0, 30, 45, 60] {
            let layoutKeys = rows.enumerated().flatMap { rowIndex, row in
                row.0.enumerated().map { index, letter in
                    SwipeKey(letter: String(letter), x: (Double(index) + row.1) * 40, y: Double(rowIndex) * rowHeight)
                }
            }
            let layoutCenters = Dictionary(uniqueKeysWithValues: layoutKeys.map {
                ($0.letter, SwipePoint(x: $0.x, y: $0.y))
            })
            for horizontalMiss in [0.0, 2, 4, 6, 8, 10] {
                var observed = "duiop".map { layoutCenters[String($0)]! }
                observed[1] = SwipePoint(x: observed[1].x + horizontalMiss, y: observed[1].y + 2)
                let dupScore = SwipePathDecoder.geometricScore(path: observed, keys: layoutKeys, text: "dup")!
                let dipScore = SwipePathDecoder.geometricScore(path: observed, keys: layoutKeys, text: "dip")!
                try require(SwipePathDecoder.prefersCangjie(chineseScore: dupScore, englishScore: dipScore), "bend near u still means dup across key-row proportions")
                regressionChecks += 1
            }
        }
        let realDip = path("dip")
        let competingDup = SwipePathDecoder.geometricScore(path: realDip, keys: keys, text: "dup")!
        try require(!SwipePathDecoder.prefersCangjie(chineseScore: competingDup, englishScore: 0), "actual dip bend remains English")
        print("SwipePathDecoder: PASS (\(33 + regressionChecks) standalone geometry and routing checks)")
    }

    private static func require(_ condition: Bool, _ description: String) throws {
        if !condition { throw CheckError.failed(description) }
    }

    private enum CheckError: Error {
        case failed(String)
    }
}
