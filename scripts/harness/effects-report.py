#!/usr/bin/env python3
"""Report repeated self-buff casts from a bounded local effects scenario.

Uses individual frame durations, server action responses and the existing renderer-run
identity/rollback checks. It reads no private backups or credentials.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
from datetime import datetime
import importlib.util
import json
import math
from pathlib import Path
import re

SPEC = importlib.util.spec_from_file_location("renderer_report", Path(__file__).with_name("renderer-report.py"))
renderer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(renderer)
SPELLS = {249: "Blaze Spikes", 250: "Ice Spikes", 251: "Shock Spikes",
          54: "Stoneskin", 53: "Blink", 55: "Aquaveil"}


def durations(values: list[float]) -> dict:
    if not values:
        return {"count": 0}
    ordered = sorted(values)
    return {"count": len(values), **{name: round(ordered[math.ceil(len(values) * p) - 1], 3)
            for name, p in (("p50_ms", 0.5), ("p95_ms", 0.95), ("p99_ms", 0.99), ("max_ms", 1))}}


def frame_summary(rows: list[dict], start: float, end: float, zone: int = 234) -> dict:
    # Keep boundary frames whole, including a long frame crossing the final marker.
    selected = [r for r in rows if r["zone"] == zone and r["epoch"] > start
                and r["epoch"] - r["frame_ms"] / 1000 < end]
    values = [r["frame_ms"] for r in selected]
    result = durations(values)
    if not selected:
        return {**result, "valid": False}
    seconds = sum(values) / 1000
    gaps = [right["epoch"] - right["frame_ms"] / 1000 - left["epoch"]
            for left, right in zip(selected, selected[1:])]
    covered = (selected[0]["epoch"] - selected[0]["frame_ms"] / 1000 <= start + 0.01
               and selected[-1]["epoch"] >= end - 0.01 and max((abs(gap) for gap in gaps), default=0) < 0.001)
    return {**result, "valid": covered, "fps": round(len(values) / seconds, 3),
            "measured_seconds": round(seconds, 3),
            "frames_over_50ms": sum(v > 50 for v in values),
            "frames_over_100ms": sum(v > 100 for v in values),
            "frames_over_500ms": sum(v > 500 for v in values)}


def timing_rows(lines: list[str]) -> list[dict]:
    result = []
    for line in lines:
        match = re.match(r"\[(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ).*?\] (.*)", line)
        if not match or not any(tag in match[2] for tag in ("lockable_rt ", "metal_blit ", "gpu_ms=")):
            continue
        fields = {key: float(value) for key, value in re.findall(r"(\w+_ms)=([0-9.]+)", match[2])}
        result.append({"epoch": datetime.fromisoformat(match[1]).timestamp(), **fields})
    return result


def spell_results(markers: list[dict], start: float, end: float) -> dict:
    responses = [m for m in markers if start <= m["epoch"] <= end and m["label"] == "effect action"]
    casts = [m for m in responses if m.get("category") == 4 and m.get("self_target")]
    counts = Counter(m["action_id"] for m in casts)
    chainspell = [m for m in responses if m.get("category") == 6 and m.get("action_id") == 20
                  and m.get("self_target")]
    return {"chainspell_applied": len(chainspell) == 1 and chainspell[0].get("message") == 100,
            "all_six_spells_completed": counts == Counter({key: 1 for key in SPELLS}),
            "all_six_buffs_applied": counts == Counter({key: 1 for key in SPELLS})
                                     and all(m["message"] == 230 for m in casts),
            "spells": [{"name": name, "completions": counts[spell],
                        "messages": [m["message"] for m in casts if m["action_id"] == spell],
                        "animations": [m["animation"] for m in casts if m["action_id"] == spell]}
                       for spell, name in SPELLS.items()],
            "ability_responses": [{key: m[key] for key in ("category", "action_id", "animation", "message")}
                                  for m in responses if m.get("category") in (6, 14, 15)]}


def report(output: Path) -> dict:
    base = renderer.report(output)
    session = Path(json.loads((output / "active.json").read_text())["session"])
    result = {"run": output.name, "renderer": base, "phases": [],
              "frame_boundary_note": "Whole frames overlapping each phase are included.",
              "timing_boundary_note": "Renderer log timestamps have one-second resolution."}
    frames_path = session / "frame-times.csv"
    if not frames_path.is_file():
        result["problem"] = "No individual frame durations were captured"
        return result
    with frames_path.open() as handle:
        frames = [{key: float(value) for key, value in row.items()} for row in csv.DictReader(handle)]
    if any(not math.isfinite(v) for row in frames for v in row.values()) or any(r["frame_ms"] <= 0 for r in frames):
        raise ValueError("Invalid frame durations")
    markers = [json.loads(line) for line in (session / "perfscene-markers.jsonl").read_text().splitlines()]
    timings = timing_rows([line for path in session.glob("horizon-loader-*.log")
                          for line in path.read_text().splitlines()])
    labels = {m["label"]: m for m in markers}
    phases = [("idle", "effects idle settled", "effects idle end")]
    phases += [(f"round {n}", f"effects round {n} start", f"effects round {n} end") for n in range(1, 4)]
    for name, first, last in phases:
        if first not in labels or last not in labels:
            result["phases"].append({"name": name, "valid": False, "reason": "phase markers missing"})
            continue
        start, end = labels[first]["epoch"], labels[last]["epoch"]
        summary = frame_summary(frames, start, end)
        if name != "idle":
            summary["casts"] = spell_results(markers, start, end)
            summary["valid"] = (summary["valid"] and summary["casts"]["all_six_buffs_applied"]
                                and summary["casts"]["chainspell_applied"])
        selected = [row for row in timings if start <= row["epoch"] < end]
        summary["renderer_timings"] = {field: durations([row[field] for row in selected if field in row])
                                       for field in ("flush_ms", "read_ms", "wait_ms", "gpu_ms")}
        result["phases"].append({"name": name, "start": start, "end": end, **summary})
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    args = parser.parse_args()
    print(json.dumps(report(args.run), indent=2))
