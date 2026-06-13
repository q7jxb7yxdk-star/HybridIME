#!/usr/bin/env swift

import Foundation

private let maximumCandidates = 10
private let removablePrefixes = ["to ", "a ", "an ", "the "]

private func usage() -> Never {
    FileHandle.standardError.write(
        Data("Usage: build_cedict_index.swift INPUT OUTPUT\n".utf8)
    )
    exit(2)
}

private func normalizedEnglishTerms(
    from definition: String
) -> (lookupKeys: [String], displayTerm: String)? {
    var text = definition.lowercased()
    text = text.replacingOccurrences(
        of: #"\([^)]*\)"#,
        with: "",
        options: .regularExpression
    )
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard
        !text.isEmpty,
        text.count <= 48,
        text.range(
            of: #"^[a-z][a-z' -]*[a-z]$|^[a-z]$"#,
            options: .regularExpression
        ) != nil
    else {
        return nil
    }

    text = text
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    guard text.split(separator: " ").count <= 4 else {
        return nil
    }

    var keys = [text]
    var displayTerm = text
    for prefix in removablePrefixes where text.hasPrefix(prefix) {
        let stripped = String(text.dropFirst(prefix.count))
        if !stripped.isEmpty {
            keys.append(stripped)
            displayTerm = stripped
        }
        break
    }
    return (keys, displayTerm)
}

private func appendUnique(
    _ value: String,
    to key: String,
    in table: inout [String: [String]]
) {
    guard table[key, default: []].count < maximumCandidates else { return }
    if !table[key, default: []].contains(value) {
        table[key, default: []].append(value)
    }
}

guard CommandLine.arguments.count == 3 else {
    usage()
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let contents = try String(contentsOf: inputURL, encoding: .utf8)

var englishToChinese: [String: [String]] = [:]
var chineseToEnglish: [String: [String]] = [:]

for line in contents.split(whereSeparator: \.isNewline) {
    guard line.first != "#", let bracket = line.firstIndex(of: "[") else {
        continue
    }

    let head = line[..<bracket].split(separator: " ")
    guard
        let traditional = head.first.map(String.init),
        traditional.unicodeScalars.contains(where: {
            (0x3400...0x4DBF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
                || (0xF900...0xFAFF).contains($0.value)
                || (0x20000...0x323AF).contains($0.value)
        }),
        traditional.count <= 12,
        let firstSlash = line.firstIndex(of: "/"),
        line.last == "/"
    else {
        continue
    }

    let definitions = line[line.index(after: firstSlash)..<line.index(before: line.endIndex)]
        .split(separator: "/", omittingEmptySubsequences: true)

    for definition in definitions {
        guard let english = normalizedEnglishTerms(
            from: String(definition)
        ) else {
            continue
        }
        for key in english.lookupKeys {
            appendUnique(traditional, to: key, in: &englishToChinese)
        }
        appendUnique(
            english.displayTerm,
            to: traditional,
            in: &chineseToEnglish
        )
    }
}

var output = """
# Generated from CC-CEDICT. Do not edit manually.
# direction<TAB>key<TAB>candidate...
"""
output.append("\n")

for key in englishToChinese.keys.sorted() {
    output.append("e\t\(key)\t\(englishToChinese[key]!.joined(separator: "\t"))\n")
}
for key in chineseToEnglish.keys.sorted() {
    output.append("z\t\(key)\t\(chineseToEnglish[key]!.joined(separator: "\t"))\n")
}

try output.write(to: outputURL, atomically: true, encoding: .utf8)
print(
    "Generated \(englishToChinese.count) English keys and "
        + "\(chineseToEnglish.count) Chinese keys."
)
