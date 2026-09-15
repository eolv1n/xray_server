#!/usr/bin/env python3
"""Require operator-recorded non-secret evidence before DNS/router cutover."""

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-acceptance.py /private/evidence.json", file=sys.stderr)
        return 2
    contract_dir = Path(__file__).resolve().parent
    evidence_file = Path(sys.argv[1]).resolve()
    if contract_dir in evidence_file.parents:
        print("evidence belongs outside the Git checkout", file=sys.stderr)
        return 2
    requirements = json.loads((contract_dir / "acceptance.json").read_text())["required"]
    evidence = json.loads(evidence_file.read_text())
    if set(evidence) != set(requirements) or any(evidence[key] is not True for key in requirements):
        print("recovery acceptance failed or incomplete", file=sys.stderr)
        return 1
    print("recovery acceptance passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
