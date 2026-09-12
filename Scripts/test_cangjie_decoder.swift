import Foundation

@main
enum CangjieDecoderTest {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestError.failed("database path is required")
        }

        let lexicon = StaticLexicon(
            databaseURL: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let decoder = CangjieDecoder(lexicon: lexicon)

        let eCandidates = decoder.candidates(for: "e", limit: .max)
        try require(
            eCandidates.first == CangjieCandidate(text: "水", code: "e")
                && eCandidates.count > 10,
            "unlimited one-root prefix candidates"
        )

        let ebCandidates = decoder.candidates(for: "eb", limit: 10)
        try require(
            ebCandidates.first == CangjieCandidate(text: "㳉", code: "eb")
                && ebCandidates.count == 10,
            "bounded two-root prefix candidates"
        )
        try require(
            decoder.candidates(for: "eb", limit: .max).contains(
                    CangjieCandidate(text: "測", code: "ebcn")
                ),
            "unlimited prefix candidates preserve full codes"
        )

        try require(
            decoder.candidates(for: "ebc", limit: .max).count == 8
                && decoder.candidates(for: "ebcn", limit: .max)
                    == [CangjieCandidate(text: "測", code: "ebcn")],
            "three- and four-root prefix candidates"
        )

        print("CangjieDecoder: PASS")
    }

    private static func require(_ condition: Bool, _ name: String) throws {
        if !condition {
            throw TestError.failed(name)
        }
    }

    private enum TestError: Error {
        case failed(String)
    }
}
