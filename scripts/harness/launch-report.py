#!/usr/bin/env python3
"""Summarize completed local renderer-run startup measurements without credentials."""

import argparse
import json
from pathlib import Path
import re


def summarize(directory: Path) -> dict:
    session = Path(json.loads((directory / "active.json").read_text())["session"])
    run = json.loads((session / "menu-run.json").read_text())
    restoration = json.loads((directory / "restoration.json").read_text())
    result = json.loads((directory / "result.json").read_text())
    window = run.get("first_window", {})
    phases = {}
    for line in (session / "launcher.log").read_text(errors="replace").splitlines():
        match = re.fullmatch(r"launch timing: (.+) elapsed=([\d.]+) epoch=([\d.]+)", line)
        if match:
            phases[match[1]] = {"elapsed": float(match[2]), "epoch": float(match[3])}
    requested = run.get("launch_requested_epoch")
    renderer = run.get("renderer_verified", {})
    renderer_ok = isinstance(renderer, dict) and all(
        isinstance(renderer.get(key), str) and re.fullmatch(r"[0-9a-f]{64}", renderer[key])
        for key in ("d3d8.dll", "d3d9.dll", "mtld3d.dll", "mtld3d.so"))
    valid = (result["exit_code"] == 0 and renderer_ok
             and bool(window) and restoration.get("preferences_restored") is True
             and restoration.get("docker_unchanged") is True
             and restoration.get("related_processes") == [])
    report = {
        "run": directory.name, "session": session.name, "valid": valid,
        "request_to_window_seconds": window.get("launch_seconds"),
        "window_poll_interval_seconds": window.get("poll_interval_seconds"),
        "preparation_seconds": phases.get("spawn", {}).get("elapsed"),
        "renderer_verified": {key: renderer[key] for key in (
            "d3d8.dll", "d3d9.dll", "mtld3d.dll", "mtld3d.so") if key in renderer}
            if isinstance(renderer, dict) else {},
        "restoration": {key: restoration.get(key) for key in (
            "files_restored", "preferences_restored", "docker_unchanged", "related_processes")},
        "boot_sha256": run.get("boot_sha256"),
        "graphics": run.get("graphics_at_launch"),
        "launcher_sha256": run.get("launcher_binary_sha256"),
        "wine_debug_requested": run.get("wine_debug_requested"),
        "native_samples_present": any(session.glob("sample-*.txt")),
        "world_entry_observed": "in_world_s" in run.get("phases", {}),
        "scenario_completed": "done_s" in run.get("phases", {}),
    }
    if requested and window and run.get("injector_spawn_epoch"):
        report["request_to_spawn_seconds"] = run["injector_spawn_epoch"] - requested
        report["spawn_to_window_seconds"] = window["epoch"] - run["injector_spawn_epoch"]
    if "prepare" in phases and window:
        report["prepare_to_window_seconds"] = window["epoch"] - phases["prepare"]["epoch"]
    if requested and run.get("prefix_update_epoch"):
        report["wine_prefix_updated_during_launch"] = run["prefix_update_epoch"] >= requested
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([summarize(path) for path in args.runs], indent=2))
