#!/usr/bin/env python3
"""Update only the promoted services in a Kustomize image list."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--services", nargs="+", required=True)
    args = parser.parse_args()

    path = Path(args.file)
    content = path.read_text(encoding="utf-8")
    for service in args.services:
        pattern = re.compile(
            rf"(\n\s*- name: .*\/{re.escape(service)}\n"
            rf"\s+newName: .*\/{re.escape(service)}\n"
            rf"\s+newTag:)\s*[^\n]+"
        )
        content, count = pattern.subn(rf"\g<1> {args.tag}", content, count=1)
        if count != 1:
            raise SystemExit(f"image entry not found or duplicated: {service}")
    path.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
