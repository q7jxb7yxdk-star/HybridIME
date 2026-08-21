#!/usr/bin/env python3
"""Build the compact read-only lexicon used by the iOS keyboard extension."""

from __future__ import annotations

import argparse
import shutil
import sqlite3
from pathlib import Path


def tsv_rows(path: Path):
    with path.open("r", encoding="utf-8") as source:
        for raw_line in source:
            line = raw_line.rstrip("\n\r")
            if not line or line.startswith("#"):
                continue
            yield line.split("\t")


def unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def build_database(project_root: Path, output: Path) -> None:
    source_root = project_root / "HybridIME"
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()

    connection = sqlite3.connect(output)
    try:
        connection.executescript(
            """
            PRAGMA journal_mode = OFF;
            PRAGMA synchronous = OFF;
            PRAGMA temp_store = MEMORY;
            PRAGMA page_size = 4096;

            CREATE TABLE bilingual (
                direction INTEGER NOT NULL,
                key TEXT NOT NULL,
                candidates TEXT NOT NULL,
                PRIMARY KEY (direction, key)
            ) WITHOUT ROWID;

            CREATE TABLE association (
                language INTEGER NOT NULL,
                key TEXT NOT NULL,
                candidates TEXT NOT NULL,
                PRIMARY KEY (language, key)
            ) WITHOUT ROWID;
            """
        )

        bilingual_path = source_root / "DictionaryData" / "cedict-index.tsv"
        bilingual_rows = []
        for fields in tsv_rows(bilingual_path):
            if len(fields) < 3 or fields[0] not in {"e", "z"}:
                continue
            direction = 0 if fields[0] == "e" else 1
            key = fields[1].lower() if direction == 0 else fields[1]
            bilingual_rows.append((direction, key, "\t".join(unique(fields[2:]))))
        connection.executemany(
            "INSERT INTO bilingual(direction, key, candidates) VALUES (?, ?, ?)",
            bilingual_rows,
        )

        overrides_path = source_root / "DictionaryData" / "dictionary-overrides.tsv"
        for fields in tsv_rows(overrides_path):
            if len(fields) < 3:
                continue
            operation, key, *new_candidates = fields
            if operation not in {"add-e", "add-z", "replace-e", "replace-z"}:
                continue
            direction = 0 if operation.endswith("e") else 1
            if direction == 0:
                key = key.lower()
            existing_row = connection.execute(
                "SELECT candidates FROM bilingual WHERE direction = ? AND key = ?",
                (direction, key),
            ).fetchone()
            existing = existing_row[0].split("\t") if existing_row else []
            if operation.startswith("replace"):
                candidates = unique(new_candidates)
            else:
                candidates = unique(new_candidates + existing)
            connection.execute(
                """
                INSERT INTO bilingual(direction, key, candidates) VALUES (?, ?, ?)
                ON CONFLICT(direction, key) DO UPDATE SET candidates = excluded.candidates
                """,
                (direction, key, "\t".join(candidates)),
            )

        association_sources = (
            (0, source_root / "AssociationData" / "chinese-associations.tsv"),
            (1, source_root / "AssociationData" / "english-associations.tsv"),
        )
        for language, path in association_sources:
            rows = []
            for fields in tsv_rows(path):
                if len(fields) < 3 or len(fields) % 2 == 0:
                    continue
                rows.append((language, fields[0], "\t".join(fields[1:])))
            connection.executemany(
                "INSERT INTO association(language, key, candidates) VALUES (?, ?, ?)",
                rows,
            )

        connection.execute("PRAGMA user_version = 1")
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()

    notice_paths = (
        source_root / "DictionaryData" / "LICENSE-CC-CEDICT.txt",
        source_root / "DictionaryData" / "NOTICE-CC-CEDICT.txt",
        source_root / "AssociationData" / "LICENSE-Rime-Essay.txt",
        source_root / "AssociationData" / "NOTICE-Rime-Essay.txt",
        source_root / "AssociationData" / "NOTICE-Tatoeba-CC0.txt",
    )
    for notice_path in notice_paths:
        shutil.copyfile(notice_path, output.parent / notice_path.name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("HybridIMEKeyboard/LexiconData/hybridime-lexicon.sqlite3"),
    )
    arguments = parser.parse_args()
    project_root = arguments.project_root.resolve()
    output = arguments.output
    if not output.is_absolute():
        output = project_root / output
    build_database(project_root, output)
    print(output)


if __name__ == "__main__":
    main()
