#!/usr/bin/env python3
"""Emit a GitHub Actions matrix for independently changed Bank of Anthos services."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path


SERVICES = [
    {"name": "frontend", "path": "src/frontend", "language": "python"},
    {"name": "userservice", "path": "src/accounts/userservice", "language": "python"},
    {"name": "contacts", "path": "src/accounts/contacts", "language": "python"},
    {"name": "balancereader", "path": "src/ledger/balancereader", "language": "java"},
    {"name": "ledgerwriter", "path": "src/ledger/ledgerwriter", "language": "java"},
    {"name": "transactionhistory", "path": "src/ledger/transactionhistory", "language": "java"},
]

SHARED_PREFIXES = (".github/", "pom.xml", "mvnw", ".mvn/")


def changed_paths(base: str, head: str) -> list[str]:
    if not base or set(base) == {"0"}:
        return ["__all__"]
    result = subprocess.run(
        ["git", "diff", "--name-only", base, head],
        check=True,
        text=True,
        capture_output=True,
    )
    return [line.strip().replace("\\", "/") for line in result.stdout.splitlines() if line.strip()]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()

    paths = ["__all__"] if args.all else changed_paths(args.base, args.head)
    build_all = "__all__" in paths or any(
        path.startswith(SHARED_PREFIXES) for path in paths
    )
    selected = [
        service
        for service in SERVICES
        if build_all or any(path.startswith(f"{service['path']}/") for path in paths)
    ]

    matrix = json.dumps({"include": selected}, separators=(",", ":"))
    has_changes = str(bool(selected)).lower()
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with Path(output).open("a", encoding="utf-8") as stream:
            stream.write(f"matrix={matrix}\n")
            stream.write(f"has_changes={has_changes}\n")
    print(matrix)


if __name__ == "__main__":
    main()
