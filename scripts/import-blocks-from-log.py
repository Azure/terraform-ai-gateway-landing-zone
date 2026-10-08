#!/usr/bin/env python3
"""Turn "already exists" errors from a `terraform apply` log into import {} blocks.

Prints the blocks; it changes nothing. Paste them into an imports.tf next to
the configuration, run plan (the plan shows each import), apply, then delete
the blocks. See docs/operations/adopting-existing-resources.md.

    python3 scripts/import-blocks-from-log.py <apply-log>
"""
import re
import sys

ID_RE = re.compile(r'"(/subscriptions/[^"]+)"\s+already exists', re.I)
ROLE_RE = re.compile(r'existing role assignment is\s+([0-9a-f-]{36})', re.I)
ADDR_RE = re.compile(r'^\s*with\s+(\S+),\s*$')
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
BORDER = re.compile(r'^[\s\u2502\u2577\u2575\u250c\u2514\u2500]+')  # drop the "│ ╷ ╵" frame


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    raw = open(sys.argv[1], "rb").read()
    # PowerShell 5.1 Tee-Object writes UTF-16.
    text = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8", errors="replace")
    lines = [BORDER.sub("", ANSI.sub("", l)) for l in text.splitlines()]

    blocks, seen = [], set()
    starts = [i for i, l in enumerate(lines) if l.startswith("Error:")] + [len(lines)]
    for a, b in zip(starts, starts[1:]):
        chunk = lines[a:b]
        text = "\n".join(chunk)
        addr = next((m.group(1) for m in map(ADDR_RE.match, chunk) if m), None)
        if not addr or addr in seen:
            continue
        if m := ID_RE.search(text):
            rid = m.group(1)
        elif m := ROLE_RE.search(text):
            rid = f"<scope>/providers/Microsoft.Authorization/roleAssignments/{m.group(1)}"
        else:
            continue
        seen.add(addr)
        blocks.append(f'import {{\n  to = {addr}\n  id = "{rid}"\n}}\n')

    if not blocks:
        print("# No 'already exists' errors with a resource address were found.")
        return 1
    print("# import {} blocks for the objects that already exist in Azure.")
    print("# Role assignments: replace <scope> with the assignment scope shown in the plan.")
    print("\n".join(blocks))
    return 0


if __name__ == "__main__":
    sys.exit(main())
