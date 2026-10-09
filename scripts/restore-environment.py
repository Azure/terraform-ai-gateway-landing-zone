#!/usr/bin/env python3
"""Restore ignored environment inputs from a GitHub environment secret."""

import json
import os
import re
import sys
from pathlib import Path


STACKS = (
    "bootstrap", "identity", "network", "app-hosting", "platform",
    "gateway-config", "llm-backend-onboarding",
)


def restore(environment: str, files: dict[str, str], root: Path) -> None:
    if not re.fullmatch(r"[a-z0-9]{2,10}", environment):
        raise ValueError("Environment must be 2-10 lowercase letters or digits.")
    allowed = {"common.tfvars", "backend.hcl", *(f"{stack}.tfvars" for stack in STACKS)}
    if not isinstance(files, dict) or not {"common.tfvars", "backend.hcl"} <= files.keys():
        raise ValueError("Environment config must contain common.tfvars and backend.hcl.")
    for name, content in files.items():
        if (
            not isinstance(name, str)
            or (name not in allowed and not re.fullmatch(r"access-contracts/[a-zA-Z0-9_-]+\.tfvars", name))
            or not isinstance(content, str)
        ):
            raise ValueError("Environment config contains an unsupported file name or non-text value.")
    destination = root.resolve() / "environments" / environment
    for name, content in files.items():
        path = destination / name
        if path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
            raise ValueError("Environment config cannot be restored through a symbolic link.")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def main() -> int:
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: restore-environment.py <environment>")
        config = os.environ.get("ENVIRONMENT_CONFIG_JSON")
        if not config:
            raise ValueError("Set ENVIRONMENT_CONFIG_JSON on the GitHub environment; local environment files are gitignored.")
        restore(sys.argv[1], json.loads(config), Path.cwd())
    except (ValueError, OSError) as error:
        print(f"Environment restore failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
