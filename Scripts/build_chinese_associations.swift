#!/usr/bin/env swift

import Foundation

private let maximumCandidates = 10
private let maximumWordLength = 8
private let maximumCompletionLength = 4

private func usage() -> Never {
    FileHandle.standardError.write(
        Data("Usage: build_chinese_associations.swift INPUT OUTPUT\n".utf8)
    )
    exit(2)
}

private func isChinese(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
        switch scalar.value {
        case 0x3007,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2FA1F,
             0x30000...0x323AF:
            true
        default:
            false
        }
    }
}

guard CommandLine.arguments.count == 3 else {
    usage()
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let contents = try String(contentsOf: inputURL, encoding: .utf8)

var scores: [String: [String: Int]] = [:]

for line in contents.split(whereSeparator: \.isNewline) {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
    guard
        fields.count >= 2,
        let weight = Int(fields[1]),
        weight > 0
    else {
        continue
    }

    let characters = Array(fields[0])
    guard
        (2...maximumWordLength).contains(characters.count),
        characters.allSatisfy(isChinese)
    else {
        continue
    }

    for prefixLength in 1..<characters.count {
        let completionLength = characters.count - prefixLength
        guard completionLength <= maximumCompletionLength else { continue }

        let key = String(characters.prefix(prefixLength))
        let completion = String(characters.dropFirst(prefixLength))
        scores[key, default: [:]][completion, default: 0] += weight
    }
}

var output = """
# Generated from Rime Essay. Do not edit manually.
# context<TAB>completion<TAB>weight...
"""
output.append("\n")

for key in scores.keys.sorted() {
    let candidates = scores[key]!
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
print("Generated \(scores.count) Chinese association keys.")
