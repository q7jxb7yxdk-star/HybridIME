#!/usr/bin/env swift

import Foundation

private let maximumCandidates = 10
private let maximumInputWords = 40

private func usage() -> Never {
    FileHandle.standardError.write(
        Data("Usage: build_english_associations.swift INPUT OUTPUT\n".utf8)
    )
    exit(2)
}

private func words(in sentence: String) -> [String] {
    sentence.lowercased()
        .split { !$0.isASCII || (!$0.isLetter && $0 != "'") }
        .map(String.init)
        .filter {
            !$0.isEmpty
                && $0.first?.isLetter == true
                && $0.last?.isLetter == true
                && $0.count <= 24
        }
}

guard CommandLine.arguments.count == 3 else {
    usage()
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let contents = try String(contentsOf: inputURL, encoding: .utf8)

var counts: [String: [String: Int]] = [:]

for line in contents.split(whereSeparator: \.isNewline) {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
    guard fields.count >= 3 else { continue }

    let sentenceWords = words(in: String(fields[2]))
    guard sentenceWords.count <= maximumInputWords else { continue }

    for index in 0..<(max(0, sentenceWords.count - 1)) {
        let current = sentenceWords[index]
        let next = sentenceWords[index + 1]
        guard current != next else { continue }
        counts[current, default: [:]][next, default: 0] += 1
    }
}

var output = """
# Generated from Tatoeba English CC0 sentences. Do not edit manually.
# context<TAB>completion<TAB>count...
"""
output.append("\n")

for key in counts.keys.sorted() {
    let candidates = counts[key]!
        .sorted {
            if $0.value != $1.value {
                return $0.value > $1.value
            }
            return $0.key < $1.key
        }
        .prefix(maximumCandidates)

    output.append(key)
    for candidate in candidates {
        output.append("\t\(candidate.key)\t\(candidate.value)")
    }
    output.append("\n")
}

try output.write(to: outputURL, atomically: true, encoding: .utf8)
print("Generated \(counts.count) English association keys.")
