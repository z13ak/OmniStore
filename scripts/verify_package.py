#!/usr/bin/env python3
"""Validate that an OmniStore Wally archive has the intended release boundary."""

from __future__ import annotations

import pathlib
import sys
import tarfile
import zipfile


REQUIRED = {"src/init.lua", "default.project.json", "wally.toml", "LICENSE"}
FORBIDDEN_ROOTS = {"build", "dist", "tests", "DevPackages", "Packages"}


def normalize(name: str) -> str:
    return name.replace("\\", "/").removeprefix("./").rstrip("/")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_package.py <package-archive>", file=sys.stderr)
        return 2

    archive = pathlib.Path(sys.argv[1])
    if not archive.is_file():
        print(f"archive does not exist: {archive}", file=sys.stderr)
        return 2

    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as package:
            names = {normalize(name) for name in package.namelist()}
    elif tarfile.is_tarfile(archive):
        with tarfile.open(archive, mode="r:*") as package:
            names = {normalize(member.name) for member in package.getmembers()}
    else:
        print(f"unsupported or corrupt package archive: {archive}", file=sys.stderr)
        return 2

    missing = sorted(REQUIRED - names)
    forbidden = sorted(
        name for name in names if name and name.split("/", maxsplit=1)[0] in FORBIDDEN_ROOTS
    )
    if missing:
        print(f"Wally archive is missing required files: {', '.join(missing)}", file=sys.stderr)
        return 1
    if forbidden:
        print(
            f"Wally archive contains development-only files: {', '.join(forbidden)}",
            file=sys.stderr,
        )
        return 1

    print(f"Validated {archive} ({len(names)} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
