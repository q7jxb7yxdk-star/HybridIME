#!/usr/bin/env python3
"""Verify every generated static-lexicon row against its TSV sources."""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path


def tsv_rows(path: Path):
    with path.open("r", encoding="utf-8") as source:
        for raw_line in source:
            line = raw_line.rstrip("\n\r")
            if line and not line.startswith("#"):
                yield line.split("\t")


def unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def expected_bilingual(source_root: Path) -> dict[tuple[int, str], str]:
    result: dict[tuple[int, str], str] = {}
    path = source_root / "DictionaryData" / "cedict-index.tsv"
    for fields in tsv_rows(path):
        if len(fields) < 3 or fields[0] not in {"e", "z"}:
            continue
        direction = 0 if fields[0] == "e" else 1
        key = fields[1].lower() if direction == 0 else fields[1]
        result[(direction, key)] = "\t".join(unique(fields[2:]))

    overrides = source_root / "DictionaryData" / "dictionary-overrides.tsv"
    for operation, key, *new_candidates in tsv_rows(overrides):
        direction = 0 if operation.endswith("e") else 1
        if direction == 0:
            key = key.lower()
        existing = result.get((direction, key), "").split("\t")
        if existing == [""]:
            existing = []
        candidates = (
            unique(new_candidates)
            if operation.startswith("replace")
            else unique(new_candidates + existing)
        )
        result[(direction, key)] = "\t".join(candidates)
    return result


def expected_associations(source_root: Path) -> dict[tuple[int, str], str]:
    result: dict[tuple[int, str], str] = {}
    sources = (
        (0, source_root / "AssociationData" / "chinese-associations.tsv"),
        (1, source_root / "AssociationData" / "english-associations.tsv"),
    )
    for language, path in sources:
        for fields in tsv_rows(path):
            if len(fields) >= 3 and len(fields) % 2 == 1:
                result[(language, fields[0])] = "\t".join(fields[1:])
    return result


def database_rows(
    connection: sqlite3.Connection,
    table: str,
    kind_column: str,
) -> dict[tuple[int, str], str]:
    return {
        (kind, key): candidates
        for kind, key, candidates in connection.execute(
            f"SELECT {kind_column}, key, candidates FROM {table}"
        )
    }


def compare(name: str, expected: dict, actual: dict) -> None:
    if expected == actual:
        print(f"{name}: PASS ({len(actual)} rows)")
        return
    missing = list(expected.keys() - actual.keys())[:5]
    extra = list(actual.keys() - expected.keys())[:5]
    changed = [key for key in expected.keys() & actual.keys() if expected[key] != actual[key]][:5]
    raise SystemExit(
        f"{name}: FAIL missing={missing} extra={extra} changed={changed}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=Path("HybridIMEKeyboard/LexiconData/hybridime-lexicon.sqlite3"),
    )
    arguments = parser.parse_args()
    project_root = arguments.project_root.resolve()
    database = arguments.database
    if not database.is_absolute():
        database = project_root / database

    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise SystemExit(f"integrity_check: FAIL ({integrity})")
        print("integrity_check: PASS")
        source_root = project_root / "HybridIME"
        compare(
            "bilingual",
            expected_bilingual(source_root),
            database_rows(connection, "bilingual", "direction"),
        )
        compare(
            "association",
            expected_associations(source_root),
            database_rows(connection, "association", "language"),
        )
    finally:
        connection.close()


if __name__ == "__main__":
    main()
