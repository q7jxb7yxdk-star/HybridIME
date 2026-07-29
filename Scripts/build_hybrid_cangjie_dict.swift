#!/usr/bin/env swift

import Foundation

private func usage() -> Never {
    FileHandle.standardError.write(
        Data(
            """
            Usage: build_hybrid_cangjie_dict.swift BASE EXTENDED OUTPUT
            """.utf8
        )
    )
    exit(2)
}

private func isValidCode(_ code: String) -> Bool {
    !code.isEmpty && code.allSatisfy { $0.isASCII && $0.isLowercase }
}

private func append(
    _ candidate: String,
    to code: String,
    in table: inout [String: [String]],
    seenByCode: inout [String: Set<String>]
) {
    guard candidate.count == 1, isValidCode(code) else { return }
    if seenByCode[code, default: []].insert(candidate).inserted {
        table[code, default: []].append(candidate)
    }
}

private func loadRimeDict(
    at url: URL,
    into table: inout [String: [String]],
    seenByCode: inout [String: Set<String>]
) throws {
    let contents = try String(contentsOf: url, encoding: .utf8)
    for line in contents.split(whereSeparator: \.isNewline) {
        guard
            !line.isEmpty,
            line.first != "#",
            let tabIndex = line.firstIndex(of: "\t")
        else {
            continue
        }

        let candidate = String(line[..<tabIndex])
        let codeStart = line.index(after: tabIndex)
        let code = line[codeStart...]
            .prefix(while: { $0 != "\t" })
            .lowercased()

        append(
            candidate,
            to: String(code),
            in: &table,
            seenByCode: &seenByCode
        )
    }
}

guard CommandLine.arguments.count == 4 else {
    usage()
}

let baseURL = URL(fileURLWithPath: CommandLine.arguments[1])
let extendedURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

var table: [String: [String]] = [:]
var seenByCode: [String: Set<String>] = [:]

try loadRimeDict(
    at: baseURL,
    into: &table,
    seenByCode: &seenByCode
)
try loadRimeDict(
    at: extendedURL,
    into: &table,
    seenByCode: &seenByCode
)

var output = """
# Generated from Rime Cangjie 5 base + extended dictionaries.
# Local HybridIME edits should be made directly in this TSV.
# Do not edit source Rime dictionaries for HybridIME runtime behavior.
# code<TAB>candidate...

"""

for code in table.keys.sorted() {
    guard let candidates = table[code], !candidates.isEmpty else { continue }
    output.append("\(code)\t\(candidates.joined(separator: "\t"))\n")
}

try output.write(to: outputURL, atomically: true, encoding: .utf8)

let populatedCodeCount = table.values.filter { !$0.isEmpty }.count
let candidateCount = table.values.reduce(0) { $0 + $1.count }
print(
    "Generated \(populatedCodeCount) Cangjie codes and "
        + "\(candidateCount) candidates."
)
