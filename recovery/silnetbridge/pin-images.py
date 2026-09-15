#!/usr/bin/env python3
"""Pin the six observed images in a generated Remnawave Compose file."""

import json
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: pin-images.py /opt/remnawave/docker-compose.yml", file=sys.stderr)
        return 2
    compose = Path(sys.argv[1])
    lock = json.loads((Path(__file__).parent / "lock.json").read_text())
    text = compose.read_text()
    for service, image in lock["images"].items():
        old = image["observed"]
        new = image["locked"]
        pattern = re.compile(r"(^\s*image:\s*['\"]?)" + re.escape(old) + r"(['\"]?\s*(?:#.*)?)$", re.MULTILINE)
        text, count = pattern.subn(lambda match: match.group(1) + new + match.group(2), text)
        if count != 1:
            print(f"expected exactly one image for {service}: {old}; found {count}", file=sys.stderr)
            return 1
    remaining = re.findall(r"^\s*image:\s*[^\n]+", text, re.MULTILINE)
    if len(remaining) != len(lock["images"]) or any("@sha256:" not in line for line in remaining):
        print("unlocked or unexpected Compose image remains", file=sys.stderr)
        return 1
    compose.write_text(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
