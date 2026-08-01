#!/usr/bin/env python3
"""Validate that a copied tree matches the source: file set + byte sizes.

Usage: validate_copy.py <source_dir> <target_dir>
Exits non-zero (and prints the first mismatches) if anything differs.
Ignores nested .git directories on both sides.
"""
import os
import sys
from pathlib import Path


def inventory(root: Path) -> dict:
    files = {}
    for current, directories, names in os.walk(root):
        directories[:] = [d for d in directories if d != ".git"]
        for name in names:
            path = Path(current) / name
            files[str(path.relative_to(root))] = path.stat().st_size
    return files


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_copy.py <source_dir> <target_dir>", file=sys.stderr)
        return 2
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])

    left = inventory(source)
    right = inventory(destination)
    missing = sorted(set(left) - set(right))
    extra = sorted(set(right) - set(left))
    mismatch = sorted(p for p in set(left) & set(right) if left[p] != right[p])

    print(f"  source_files={len(left)} source_bytes={sum(left.values())}")
    print(f"  target_files={len(right)} target_bytes={sum(right.values())}")
    print(f"  missing={len(missing)} extra={len(extra)} size_mismatch={len(mismatch)}")
    if missing or extra or mismatch:
        if missing:
            print("  missing:", *missing[:10], sep="\n    ")
        if extra:
            print("  extra:", *extra[:10], sep="\n    ")
        if mismatch:
            print("  size mismatch:", *mismatch[:10], sep="\n    ")
        print("COPY VALIDATION FAILED", file=sys.stderr)
        return 1
    print("  COPY OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
