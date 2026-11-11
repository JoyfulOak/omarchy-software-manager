#!/usr/bin/env python3
"""Small, shell-free package inventory and action backend for Software."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from typing import Any

PACKAGE_RE = re.compile(r"^[A-Za-z0-9@_+.-]{1,255}$")
FLATPAK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$")
UPDATE_RE = re.compile(r"^(\S+)\s+(\S+)\s+->\s+(\S+)\s*$")


def parse_pacman_inventory(installed: str, foreign: str) -> list[dict[str, str]]:
    foreign_ids = {line.split()[0] for line in foreign.splitlines() if line.split()}
    rows: list[dict[str, str]] = []
    for line in installed.splitlines():
        fields = line.split(maxsplit=1)
        if len(fields) != 2 or not PACKAGE_RE.fullmatch(fields[0]):
            continue
        package_id, version = fields
        is_foreign = package_id in foreign_ids
        rows.append(
            {
                "id": package_id,
                "name": package_id,
                "version": version,
                "type": "AUR / foreign" if is_foreign else "Arch",
                "source": "Foreign package" if is_foreign else "Official repositories",
                "location": "System",
            }
        )
    return rows


def parse_flatpak_inventory(output: str, default_scope: str) -> list[dict[str, str]]:
    if default_scope not in {"user", "system"}:
        raise ValueError("Flatpak scope must be user or system")
    rows: list[dict[str, str]] = []
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) < 5:
            continue
        app_id, name, version, origin, installation = (field.strip() for field in fields[:5])
        if not FLATPAK_ID_RE.fullmatch(app_id):
            continue
        scope = installation.lower() if installation.lower() in {"user", "system"} else default_scope
        rows.append(
            {
                "id": app_id,
                "name": name or app_id,
                "version": version or "Unknown",
                "type": "Flatpak",
                "source": origin or "Unknown remote",
                "location": "User installation" if scope == "user" else "System installation",
            }
        )
    return rows


def parse_updates(output: str, source: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for line in output.splitlines():
        match = UPDATE_RE.match(line.strip())
        if not match:
            continue
        package_id, current, available = match.groups()
        if PACKAGE_RE.fullmatch(package_id):
            rows.append(
                {"id": package_id, "type": source, "current": current, "available": available}
            )
    return rows


def build_uninstall_command(app: dict[str, Any]) -> list[str]:
    app_id = str(app.get("id", ""))
    app_type = app.get("type")
    if app_type in {"Arch", "AUR / foreign"}:
        if not PACKAGE_RE.fullmatch(app_id):
            raise ValueError("Invalid package name")
        # Leave dependencies and user data alone; the UI confirms the named package first.
        return ["pkexec", "pacman", "-R", "--noconfirm", "--", app_id]
    if app_type == "Flatpak":
        if not FLATPAK_ID_RE.fullmatch(app_id):
            raise ValueError("Invalid Flatpak application ID")
        location = app.get("location")
        if location == "User installation":
            return ["flatpak", "uninstall", "--user", "--noninteractive", "--", app_id]
        if location == "System installation":
            return ["pkexec", "flatpak", "uninstall", "--system", "--noninteractive", "--", app_id]
        raise ValueError("Unknown Flatpak installation location")
    raise ValueError("Unsupported application type")


def build_flatpak_update_command(location: str, app_id: str = "all") -> list[str]:
    if location == "User installation":
        prefix = ["flatpak", "update", "--user", "--noninteractive"]
    elif location == "System installation":
        prefix = ["pkexec", "flatpak", "update", "--system", "--noninteractive"]
    else:
        raise ValueError("Unknown Flatpak installation location")
    if app_id == "all":
        return prefix
    if not FLATPAK_ID_RE.fullmatch(app_id):
        raise ValueError("Invalid Flatpak application ID")
    return prefix + ["--", app_id]


def build_flatpak_update_commands(location: str, app_id: str = "all") -> list[list[str]]:
    if location == "All installations":
        if app_id != "all":
            raise ValueError("Choose one Flatpak installation for a single-app update")
        return [
            build_flatpak_update_command("System installation"),
            build_flatpak_update_command("User installation"),
        ]
    return [build_flatpak_update_command(location, app_id)]


def run(argv: list[str], timeout: int = 90) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)


def _capture(argv: list[str], errors: list[str], *, optional: bool = False) -> str:
    if shutil.which(argv[0]) is None:
        if not optional:
            errors.append(f"{argv[0]} is not installed")
        return ""
    try:
        result = run(argv)
    except (OSError, subprocess.TimeoutExpired) as error:
        errors.append(f"{argv[0]}: {error}")
        return ""
    if result.returncode != 0 and (result.stdout.strip() or result.stderr.strip()):
        errors.append(f"{argv[0]}: {(result.stderr or result.stdout).strip()[:300]}")
    return result.stdout


def inventory() -> dict[str, Any]:
    errors: list[str] = []
    installed = _capture(["pacman", "-Qe"], errors)
    foreign = _capture(["pacman", "-Qm"], errors)
    apps = parse_pacman_inventory(installed, foreign)
    flatpak = shutil.which("flatpak")
    if flatpak is not None:
        for scope in ("system", "user"):
            output = _capture(
                [flatpak, "list", "--app", f"--{scope}",
                 "--columns=application,name,version,origin,installation"],
                errors,
                optional=True,
            )
            apps.extend(parse_flatpak_inventory(output, scope))
    else:
        errors.append("flatpak is not installed")
    apps.sort(key=lambda app: (app["name"].casefold(), app["type"], app["location"]))
    return {"apps": apps, "errors": errors}


def updates() -> dict[str, Any]:
    errors: list[str] = []
    found: list[dict[str, str]] = []
    if shutil.which("checkupdates") is not None:
        try:
            result = run(["checkupdates", "--nocolor"], timeout=180)
            found.extend(parse_updates(result.stdout, "Arch"))
            if result.returncode not in (0, 2) and result.stderr.strip():
                errors.append(f"checkupdates: {result.stderr.strip()[:300]}")
        except (OSError, subprocess.TimeoutExpired) as error:
            errors.append(f"checkupdates: {error}")
    else:
        errors.append("checkupdates is unavailable; install pacman-contrib to check Arch updates")
    if shutil.which("yay") is not None:
        try:
            result = run(["yay", "-Qua", "--noconfirm"], timeout=180)
            found.extend(parse_updates(result.stdout, "AUR / foreign"))
            # yay uses a non-zero status when there are no foreign updates.
            if result.returncode not in (0, 1) and result.stderr.strip():
                errors.append(f"yay: {result.stderr.strip()[:300]}")
        except (OSError, subprocess.TimeoutExpired) as error:
            errors.append(f"yay: {error}")
    if shutil.which("flatpak") is not None:
        for scope in ("system", "user"):
            try:
                result = run(
                    ["flatpak", "remote-ls", "--updates", "--app", f"--{scope}",
                     "--columns=application,name,version,origin"],
                    timeout=180,
                )
                if result.returncode != 0:
                    errors.append(f"flatpak ({scope}): {(result.stderr or result.stdout).strip()[:300]}")
                    continue
                for line in result.stdout.splitlines():
                    fields = line.split("\t")
                    if not fields or not FLATPAK_ID_RE.fullmatch(fields[0].strip()):
                        continue
                    app_id = fields[0].strip()
                    found.append(
                        {"id": app_id, "type": "Flatpak", "current": "Installed",
                         "available": fields[2].strip() if len(fields) > 2 else "Update available",
                         "location": "User installation" if scope == "user" else "System installation"}
                    )
            except (OSError, subprocess.TimeoutExpired) as error:
                errors.append(f"flatpak ({scope}): {error}")
    unique: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in found:
        unique[(row["type"], row["id"], row.get("location", ""))] = row
    return {"updates": list(unique.values()), "errors": errors}


def main(argv: list[str]) -> int:
    if not argv or argv[0] == "inventory":
        result = inventory()
    elif argv[0] == "updates":
        result = updates()
    elif argv[0] == "upgrade-all":
        steps = []
        if shutil.which("yay"):
            steps.append(["yay", "-Syu"])
        elif shutil.which("pacman"):
            steps.append(["sudo", "pacman", "-Syu"])
        if shutil.which("flatpak"):
            steps.extend([["flatpak", "update", "--user"], ["flatpak", "update", "--system"]])
        for command in steps:
            print("\nRunning " + " ".join(command), flush=True)
            completed = subprocess.run(command, check=False)
            if completed.returncode != 0:
                print(f"{command[0]} exited with status {completed.returncode}; remaining sources were skipped.", flush=True)
                break
        input("Press Enter to close…")
        return 0
    elif argv[0] == "flatpak-update" and len(argv) == 3:
        try:
            outcomes = []
            for command in build_flatpak_update_commands(argv[1], argv[2]):
                completed = run(command, timeout=1800)
                outcomes.append({"ok": completed.returncode == 0,
                                 "message": (completed.stdout or completed.stderr).strip()[:600]})
            result = {"ok": all(item["ok"] for item in outcomes),
                      "message": "\n".join(item["message"] for item in outcomes if item["message"])}
        except (OSError, subprocess.TimeoutExpired, ValueError) as error:
            result = {"ok": False, "message": str(error)}
    elif argv[0] == "uninstall" and len(argv) == 4:
        app_type, app_id, location = argv[1:]
        try:
            command = build_uninstall_command({"type": app_type, "id": app_id, "location": location})
            completed = run(command, timeout=600)
            result = {"ok": completed.returncode == 0,
                      "message": (completed.stdout or completed.stderr).strip()[:1200]}
        except (OSError, subprocess.TimeoutExpired, ValueError) as error:
            result = {"ok": False, "message": str(error)}
    else:
        result = {"error": "Usage: software_manager.py [inventory|updates|flatpak-update LOCATION ID|uninstall TYPE ID LOCATION]"}
        print(json.dumps(result))
        return 2
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
