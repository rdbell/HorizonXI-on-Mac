#!/usr/bin/env python3
"""Summarize complete FPS windows inside confirmed menu and settled world scenes.

Pass renderer-run output directories. This reads no private rollback files. Frame-time
percentiles remain explicitly per-window; the CSV cannot supply pooled percentiles.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import statistics


SETTLED_ZONES = {"city settled": 235, "mines settled": 234, "field settled": 106,
                 "weather settled": 106, "crowd settled": 106, "city after crowd": 235,
                 "mines plaza settled": 234}


def summarize(rows: list[dict], start: float, end: float, zone: int) -> dict:
    selected = [r for r in rows if r["epoch"] - r["seconds"] >= start
                and r["epoch"] <= end and r["zone"] == zone]
    if not selected:
        return {"valid": False, "reason": "no complete windows in the expected zone"}
    elapsed = sum(r["seconds"] for r in selected)
    gaps = [right["epoch"] - right["seconds"] - left["epoch"]
            for left, right in zip(selected, selected[1:])]
    missing = max(0, selected[0]["epoch"] - selected[0]["seconds"] - start - 1.1,
                  end - selected[-1]["epoch"] - 1.1, *gaps)
    valid = elapsed >= 10 and missing < 0.1
    return {"valid": valid, "windows": len(selected), "seconds": round(elapsed, 3),
            "fps": round(sum(r["frames"] for r in selected) / elapsed, 3),
            "median_window_fps": round(statistics.median(r["fps"] for r in selected), 3),
            "minimum_window_fps": round(min(r["fps"] for r in selected), 3),
            "percent_time_below_120": round(100 * sum(r["seconds"] for r in selected
                if r["fps"] < 120) / elapsed, 2),
            "worst_window_p99_ms": round(max(r["p99_ms"] for r in selected), 3),
            "maximum_frame_ms": round(max(r["max_ms"] for r in selected), 3),
            "jit_enabled": sorted({int(r["jit_enabled"]) for r in selected}),
            "unaccounted_seconds": round(missing, 3),
            "reason": None if valid else "short sample or missing frame-counter windows"}


def intervals(record: dict, markers: list[dict]) -> list[dict]:
    result = []
    starts = {}
    for event in record.get("events", []):
        if event["label"] == "menu sample start":
            starts[event["scene"]] = event["epoch"]
        elif event["label"] == "menu sample end" and event["scene"] in starts:
            start = starts.pop(event["scene"])
            if event["epoch"] - start < 1:
                continue
            result.append({"name": event["scene"], "zone": 0,
                           "start": start, "end": event["epoch"]})
    for index, marker in enumerate(markers[:-1]):
        if marker["label"] in SETTLED_ZONES:
            result.append({"name": marker["label"], "zone": SETTLED_ZONES[marker["label"]],
                           "start": marker["epoch"] + 2, "end": markers[index + 1]["epoch"],
                           "position": {key: marker.get(key) for key in ("x", "y", "z", "yaw")},
                           "draw_distance": {key: marker.get(key) for key in
                                             ("world_distance", "entity_distance")}})
    return result


def report(output: Path) -> dict:
    session = Path(json.loads((output / "active.json").read_text())["session"])
    record = json.loads((session / "menu-run.json").read_text())
    result = {"run": output.name, "session": session.name, "problems": [], "scenes": [],
              "boot_sha256": record.get("boot_sha256"),
              "renderer_sha256": record.get("renderer_verified"),
              "graphics": record.get("graphics_at_launch"),
              "renderer_config": record.get("renderer_config"),
              "draw_distance_requested": record.get("draw_distance_requested"),
              "rendering_review_required": True}
    for name, key, value in [("result.json", "exit_code", 0),
                             ("restoration.json", "docker_unchanged", True),
                             ("restoration.json", "preferences_restored", True)]:
        try:
            if json.loads((output / name).read_text()).get(key) != value:
                result["problems"].append(f"{name}: {key} did not confirm success")
        except (OSError, ValueError):
            result["problems"].append(f"{name}: missing or invalid")
    if not record.get("renderer_verified") or record.get("leftover_processes") != []:
        result["problems"].append("renderer identity or process cleanup is unconfirmed")
    if record.get("graphics_requested") != record.get("graphics_at_launch"):
        result["problems"].append("graphics settings changed between preparation and launch")
    counters = session / "common-fps.csv"
    if not counters.is_file():
        result["problems"].append("common-fps.csv: no frame-counter data was captured")
        return result
    with counters.open() as handle:
        rows = [{key: float(value) for key, value in row.items()} for row in csv.DictReader(handle)]
    if any(not math.isfinite(v) for row in rows for v in row.values()):
        raise ValueError("frame counters contain non-finite values")
    if any(r["seconds"] <= 0 or r["frames"] <= 0 for r in rows):
        raise ValueError("frame counters contain non-positive intervals")
    markers_path = session / "perfscene-markers.jsonl"
    markers = [json.loads(line) for line in markers_path.read_text().splitlines()] if markers_path.exists() else []
    for phase in intervals(record, markers):
        summary = summarize(rows, phase["start"], phase["end"], phase["zone"])
        requested = record.get("draw_distance_requested")
        if phase["zone"] and requested is not None:
            if any(value is None or abs(value - requested) > 0.001
                   for value in phase["draw_distance"].values()):
                summary.update(valid=False, reason="effective draw distance differs from the request")
        result["scenes"].append({**phase, **summary})
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([report(path) for path in args.runs], indent=2))


if __name__ == "__main__":
    main()
