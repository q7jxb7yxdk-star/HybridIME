import Foundation

struct SwipePoint: Sendable, Equatable {
    let x: Double
    let y: Double
}

struct SwipeKey: Sendable, Equatable {
    let letter: String
    let x: Double
    let y: Double
}

struct SwipeWord: Sendable, Equatable {
    let text: String
    let weight: Int
}

struct SwipeCodeMatch: Sendable, Equatable {
    let code: String
    /// Lower scores indicate a closer geometric match, in key-spacing units.
    let score: Double
}

/// A bounded, offline geometric matcher shared by English words and Cangjie codes.
/// Repeated letters share a key center. Without timing or explicit separators,
/// collinear roots and repeated roots can be ambiguous; candidates retain that ambiguity.
struct SwipePathDecoder {
    private struct Geometry {
        let points: [SwipePoint]
        let keys: [String: SwipePoint]
        let spacing: Double
        let length: Double
    }

    private struct Template {
        let text: String
        let points: [SwipePoint]
        let length: Double
        let endpointScore: Double
        let weight: Int
    }

    private static let sampleCount = 24
    private static let maximumTemplates = 768

    static func rank(
        path: [SwipePoint],
        keys: [SwipeKey],
        words: [SwipeWord],
        limit: Int
    ) -> [SwipeWord] {
        guard limit > 0, let geometry = geometry(path: path, keys: keys) else { return [] }
        var weights: [String: Int] = [:]
        for word in words {
            let text = word.text.lowercased()
            guard isLetters(text), text.count <= 24 else { continue }
            weights[text] = max(weights[text] ?? 0, max(0, word.weight))
        }
        let templates = shortlist(
            weights.map { ($0.key, $0.value) }, geometry: geometry
        )
        let matches = templates.compactMap { template -> (SwipeWord, Double)? in
            let score = score(template, geometry: geometry)
            guard score <= 2.4 else { return nil }
            // Frequency breaks close geometric ties without overpowering path shape.
            let prior = min(log1p(Double(template.weight)), 12) * 0.018
            return (SwipeWord(text: template.text, weight: template.weight), score - prior)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.0.text < $1.0.text
        }
        return Array(matches.prefix(min(limit, maximumTemplates)).map(\.0))
    }

    static func rankCodes(
        path: [SwipePoint],
        keys: [SwipeKey],
        codes: [String],
        limit: Int
    ) -> [SwipeCodeMatch] {
        guard limit > 0, let geometry = geometry(path: path, keys: keys) else { return [] }
        let normalized = Set(codes.lazy.map { $0.lowercased() }.filter {
            isLetters($0) && $0.count <= 5
        })
        return Array(shortlist(normalized.map { ($0, 0) }, geometry: geometry)
            .compactMap { template -> SwipeCodeMatch? in
                let matchScore = score(template, geometry: geometry)
                guard matchScore <= 1.8 else { return nil }
                return SwipeCodeMatch(code: template.text, score: matchScore)
            }.sorted {
                if $0.score != $1.score { return $0.score < $1.score }
                return $0.code < $1.code
            }.prefix(min(limit, maximumTemplates)))
    }

    private static func geometry(path: [SwipePoint], keys: [SwipeKey]) -> Geometry? {
        guard path.count >= 2, path.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }
        var keyPoints: [String: SwipePoint] = [:]
        for key in keys where key.x.isFinite && key.y.isFinite {
            let letter = key.letter.lowercased()
            guard letter.count == 1, isLetters(letter) else { continue }
            keyPoints[letter] = SwipePoint(x: key.x, y: key.y)
        }
        guard keyPoints.count >= 2 else { return nil }
        let positions = Array(keyPoints.values)
        let nearestDistances = positions.compactMap { point in
            positions.map { distance(point, $0) }.filter { $0 > 0.001 }.min()
        }.sorted()
        guard !nearestDistances.isEmpty else { return nil }
        let spacing = nearestDistances[nearestDistances.count / 2]
        guard spacing > 0.001 else { return nil }
        // Bound work for an unusually long touch stream while retaining both endpoints.
        let bounded = path.count <= 256 ? path : (0..<256).map {
            path[$0 * (path.count - 1) / 255]
        }
        let length = pathLength(bounded)
        guard length.isFinite else { return nil }
        return Geometry(
            points: resample(bounded), keys: keyPoints, spacing: spacing, length: length
        )
    }

    private static func shortlist(_ entries: [(String, Int)], geometry: Geometry) -> [Template] {
        guard let start = geometry.points.first, let end = geometry.points.last else { return [] }
        var templates: [Template] = []
        for (text, weight) in entries {
            guard let first = text.first, let last = text.last,
                  let firstPoint = geometry.keys[String(first)],
                  let lastPoint = geometry.keys[String(last)]
            else { continue }
            let startDistance = distance(start, firstPoint) / geometry.spacing
            let endDistance = distance(end, lastPoint) / geometry.spacing
            // Reject distant endpoints before constructing or resampling a template.
            guard startDistance <= 1.25, endDistance <= 1.25 else { continue }
            var points: [SwipePoint] = []
            var valid = true
            for letter in text {
                guard let point = geometry.keys[String(letter)] else {
                    valid = false
                    break
                }
                if points.last != point { points.append(point) }
            }
            guard valid else { continue }
            let length = pathLength(points)
            let endpointScore = (startDistance + endDistance) * 0.5
            templates.append(Template(
                text: text, points: points, length: length,
                endpointScore: endpointScore, weight: weight
            ))
        }
        // A cheap lower-cost approximation bounds the more expensive shape comparison.
        templates.sort {
            let lhs = $0.endpointScore + abs($0.length - geometry.length) / geometry.spacing * 0.04
            let rhs = $1.endpointScore + abs($1.length - geometry.length) / geometry.spacing * 0.04
            if lhs != rhs { return lhs < rhs }
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.text < $1.text
        }
        return Array(templates.prefix(maximumTemplates))
    }

    private static func score(_ template: Template, geometry: Geometry) -> Double {
        let ideal = resample(template.points)
        var shapeError = 0.0
        for (observed, expected) in zip(geometry.points, ideal) {
            shapeError += distance(observed, expected) / geometry.spacing
        }
        shapeError /= Double(sampleCount)
        // A modest length penalty tolerates small loops around repeated-letter keys.
        let lengthError = abs(template.length - geometry.length)
            / max(geometry.spacing, max(template.length, geometry.length))
        return shapeError + template.endpointScore * 0.65 + lengthError * 0.2
    }

    private static func resample(_ points: [SwipePoint]) -> [SwipePoint] {
        guard let first = points.first else { return [] }
        let length = pathLength(points)
        guard length > 0.001 else { return Array(repeating: first, count: sampleCount) }
        let step = length / Double(sampleCount - 1)
        var result = [first]
        var segment = 1
        var previousDistance = 0.0
        var segmentLength = distance(points[0], points[1])
        for index in 1..<(sampleCount - 1) {
            let target = Double(index) * step
            while segment < points.count - 1 && previousDistance + segmentLength < target {
                previousDistance += segmentLength
                segment += 1
                segmentLength = distance(points[segment - 1], points[segment])
            }
            let fraction = segmentLength > 0 ? min(1, max(0, (target - previousDistance) / segmentLength)) : 0
            let a = points[segment - 1]
            let b = points[segment]
            result.append(SwipePoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction))
        }
        result.append(points[points.count - 1])
        return result
    }

    private static func pathLength(_ points: [SwipePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func distance(_ a: SwipePoint, _ b: SwipePoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func isLetters(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (97...122).contains($0) }
    }
}
