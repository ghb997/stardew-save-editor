#!/usr/bin/env python3
"""Compare a source delivery with its original ZIP and write SHA-256 evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path, PurePosixPath


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_archive_path(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name:
        raise ValueError(f"Unsafe ZIP entry: {name!r}")
    return path


def archive_inventory(path: Path) -> tuple[str, dict[str, bytes]]:
    archive_bytes = path.read_bytes()
    with zipfile.ZipFile(path) as archive:
        file_entries = [entry for entry in archive.infolist() if not entry.is_dir()]
        safe_paths = [safe_archive_path(entry.filename) for entry in file_entries]
        roots = {parts.parts[0] for parts in safe_paths if parts.parts}
        strip_root = len(roots) == 1 and all(len(parts.parts) > 1 for parts in safe_paths)

        files: dict[str, bytes] = {}
        for entry, safe_path in zip(file_entries, safe_paths, strict=True):
            parts = safe_path.parts[1:] if strip_root else safe_path.parts
            relative = PurePosixPath(*parts).as_posix()
            if relative in files:
                raise ValueError(f"Duplicate normalized ZIP entry: {relative}")
            files[relative] = archive.read(entry)
    return sha256(archive_bytes), files


def delivery_paths(root: Path) -> list[str]:
    try:
        result = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            cwd=root,
            check=True,
            capture_output=True,
        )
        return sorted(
            item.decode("utf-8")
            for item in result.stdout.split(b"\0")
            if item
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        excluded = {".git", "DerivedData", "build", "artifacts", "__pycache__"}
        return sorted(
            path.relative_to(root).as_posix()
            for path in root.rglob("*")
            if path.is_file() and not any(part in excluded for part in path.relative_to(root).parts)
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True, help="Original source ZIP")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--baseline-name", default="SheaflightAmberVault-source-v0.3.1-build5")
    parser.add_argument("--release", default="SheaflightAmberVault-source-v0.3.3-build7")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    root = args.root.resolve()
    output = (args.output or root / "validation" / "source-changes.json").resolve()
    output_relative = output.relative_to(root).as_posix()
    archive_hash, original = archive_inventory(args.baseline.resolve())

    delivery: dict[str, bytes] = {}
    for relative in delivery_paths(root):
        if relative == output_relative:
            continue
        delivery[relative] = (root / Path(relative)).read_bytes()

    changes = []
    counts = {"added": 0, "modified": 0, "removed": 0}
    for relative in sorted(original.keys() | delivery.keys()):
        before = original.get(relative)
        after = delivery.get(relative)
        if before == after:
            continue
        if before is None:
            kind = "added"
        elif after is None:
            kind = "removed"
        else:
            kind = "modified"
        counts[kind] += 1
        changes.append(
            {
                "file": relative,
                "change": kind,
                "original_sha256": sha256(before) if before is not None else None,
                "delivery_sha256": sha256(after) if after is not None else None,
            }
        )

    report = {
        "baseline": args.baseline_name,
        "baseline_archive": args.baseline.name,
        "baseline_archive_sha256": archive_hash,
        "release": args.release,
        "note": "Source/resource differences only; this report excludes itself and is not a build or test result.",
        "summary": counts,
        "changes": changes,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(output), "summary": counts}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
