#!/usr/bin/env python3
"""Apply a saved stack plan, adopting only exact-name diagnostic settings."""

import json
import subprocess
import sys
from pathlib import Path


def diagnostic_creates(plan: dict) -> list[dict]:
    return [
        change
        for change in plan.get("resource_changes", [])
        if change["type"] == "azurerm_monitor_diagnostic_setting"
        and change["change"]["actions"] == ["create"]
    ]


def import_arguments(plan_arguments: list[str]) -> list[str]:
    result = []
    index = 0
    while index < len(plan_arguments):
        argument = plan_arguments[index]
        if argument in ("-var", "-var-file"):
            result.extend(plan_arguments[index:index + 2])
            index += 2
        else:
            if argument.startswith(("-var=", "-var-file=")):
                result.append(argument)
            index += 1
    return result


def read_plan(directory: Path) -> dict:
    result = subprocess.run(
        ["terraform", f"-chdir={directory}", "show", "-json", "tfplan"],
        check=True, capture_output=True, text=True,
    )
    return json.loads(result.stdout)


def resource_missing(stderr: str) -> bool:
    codes = ("ResourceNotFound", "ParentResourceNotFound", "NotFound")
    if any(f"({code})" in stderr for code in codes):
        return True
    # az rest also formats ARM errors as "Not Found(<JSON error body>)".
    start = stderr.find("{")
    if start >= 0:
        try:
            body, _ = json.JSONDecoder().raw_decode(stderr[start:])
        except json.JSONDecodeError:
            return False
        if isinstance(body, dict):
            error = body.get("error", body)
            return isinstance(error, dict) and error.get("code") in codes
    return False


def adopt_diagnostics(directory: Path, plan: dict, arguments: list[str]) -> int:
    imported = 0
    for change in diagnostic_creates(plan):
        after = change["change"]["after"]
        unknown = change["change"].get("after_unknown", {})
        target = after.get("target_resource_id")
        name = after.get("name")
        if not target or not name or unknown.get("target_resource_id") or unknown.get("name"):
            continue

        resource_id = f"{target}/providers/Microsoft.Insights/diagnosticSettings/{name}"
        result = subprocess.run(
            ["az", "rest", "--method", "get", "--url",
             f"{resource_id}?api-version=2021-05-01-preview", "--output", "json"],
            capture_output=True, text=True,
        )
        if result.returncode:
            # Only a missing resource is expected; auth, throttling and network
            # failures must not be mistaken for "safe to create".
            if resource_missing(result.stderr):
                continue
            print(result.stderr, file=sys.stderr, end="")
            raise subprocess.CalledProcessError(result.returncode, result.args)

        setting = json.loads(result.stdout)
        if setting.get("id", "").lower() != resource_id.lower():
            raise ValueError(f"Azure returned an unexpected diagnostic setting for {resource_id}")

        print(f"Adopting exact-name diagnostic setting: {change['address']} <- {target}|{name}", flush=True)
        subprocess.run(
            ["terraform", f"-chdir={directory}", "import", "-input=false",
             *import_arguments(arguments), change["address"], f"{target}|{name}"],
            check=True,
        )
        imported += 1
    return imported


def replan(directory: Path, arguments: list[str]) -> None:
    subprocess.run(
        ["terraform", f"-chdir={directory}", "plan", "-input=false", "-out=tfplan", *arguments],
        check=True,
    )


def apply(directory: Path, arguments: list[str]) -> int:
    plan = read_plan(directory)
    if adopt_diagnostics(directory, plan, arguments):
        replan(directory, arguments)
        plan = read_plan(directory)

    result = subprocess.run(
        ["terraform", f"-chdir={directory}", "apply", "-input=false", "tfplan"],
    )
    if result.returncode == 0 or not diagnostic_creates(plan):
        return result.returncode

    # Targets may only become known after a partial first apply. Replan once,
    # import exact matches, then apply a fresh plan. Never retry a generic error
    # unless an orphaned diagnostic setting was actually recovered.
    print("Apply failed; checking for diagnostic settings created outside state.", flush=True)
    replan(directory, arguments)
    if not adopt_diagnostics(directory, read_plan(directory), arguments):
        print("No diagnostic setting recovered; not retrying the failed apply.", file=sys.stderr)
        return result.returncode
    replan(directory, arguments)
    return subprocess.run(
        ["terraform", f"-chdir={directory}", "apply", "-input=false", "tfplan"],
    ).returncode


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: apply-stack.py <stack-directory> [-- <original-plan-arguments>]", file=sys.stderr)
        return 2
    arguments = sys.argv[2:]
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    try:
        return apply(Path(sys.argv[1]).resolve(), arguments)
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr, file=sys.stderr, end="")
        print(f"Diagnostic recovery failed: {error}", file=sys.stderr)
        return error.returncode
    except (ValueError, OSError) as error:
        print(f"Diagnostic recovery failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
