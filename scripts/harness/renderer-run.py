#!/usr/bin/env python3
"""Compare renderers with the local Hxitest account and restore the saved installation.

Results and private rollback files go under --output, which must be outside Git. Use
--restore OUTPUT after an interrupted parent process. Never publish its private directory.
The installed launcher is copied before changing a renderer resource, since it reinstalls
those resources on every launch. Menu recognition and FPS measurement work across backends.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("menu_run", HERE / "menu-run.py")
menu = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(menu)
WORLD = "Local LSB (Docker)"
USER = "hxitest"
PREFERENCE_KEYS = ("server.selected", "account.user", "account.user." + WORLD, "account.remember")
OCR_TOOL = HERE / ".build/scene-ocr"


def checked(argv: list[str], timeout: float = 30) -> str:
    result = menu.run(argv, timeout=timeout)
    if result.returncode:
        # Boot and account errors can carry credentials. Do not echo command output.
        raise RuntimeError(f"{Path(argv[0]).name} failed with status {result.returncode}")
    return result.stdout


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def counter_is_advancing(path: Path, now: float) -> bool:
    try:
        with path.open() as handle:
            rows = list(csv.DictReader(handle))
        return bool(rows) and 0 <= now - float(rows[-1]["epoch"]) < 3
    except (OSError, ValueError, KeyError):
        return False


def graphics_values(text: str) -> dict[str, int]:
    """Read numeric graphics keys without retaining the boot command or credentials."""
    values = {}
    section = False
    for line in text.splitlines():
        clean = line.strip()
        if clean.startswith("["):
            section = clean.lower() == "[ffxi.registry]"
        match = re.fullmatch(r"(\d{4})\s*=\s*(\d+)\s*(?:;.*)?", clean) if section else None
        if match:
            values[match[1]] = int(match[2])
    return values


def set_background(text: str, size: int) -> str:
    """Change both background dimensions in the existing graphics section."""
    if not {"0003", "0004"} <= graphics_values(text).keys():
        raise RuntimeError("Local boot profile is missing background dimensions")
    lines = []
    section = False
    for line in text.splitlines(keepends=True):
        if line.strip().startswith("["):
            section = line.strip().lower() == "[ffxi.registry]"
        if section:
            line = re.sub(r"^(\s*000[34]\s*=\s*)\d+", lambda m: m[1] + str(size), line)
        lines.append(line)
    return "".join(lines)


def docker_state() -> list[dict]:
    ids = checked(["docker", "ps", "--filter", "name=lsb-local-", "-q"]).split()
    if len(ids) != 5:
        raise RuntimeError("Expected the five already-running lsb-local Docker containers")
    rows = json.loads(checked(["docker", "inspect", *ids]))
    return sorted([{"id": row["Id"], "name": row["Name"],
                    "started": row["State"]["StartedAt"], "running": row["State"]["Running"]}
                   for row in rows], key=lambda row: row["name"])


class Snapshot:
    def __init__(self, output: Path):
        self.output = output
        self.private = output / "private"
        self.manifest = self.private / "manifest.json"

    def save(self, game: Path) -> None:
        self.private.mkdir(mode=0o700, parents=True, exist_ok=False)
        paths = [game / "config/boot/lsb-docker.ini", game / "scripts/perfscene.txt",
                 game / "scripts/default.txt", game / "addons/perfscene/perfscene.lua",
                 Path.home() / "Library/Application Support/HorizonXI-on-Mac/accounts.json"]
        directories = (game, game / "bootloader", game / "SquareEnix/PlayOnlineViewer",
                       game / "SquareEnix/FINAL FANTASY XI")
        paths += [directory / name for directory in directories
                  for name in ("d3d8.dll", "d3d9.dll", "d3d8.ini", "dxvk.conf")]
        paths += [menu.PREFIX / name for name in ("user.reg", "system.reg", "userdef.reg")]
        paths += [menu.PREFIX / "drive_c/windows" / bits / "mtld3d.dll"
                  for bits in ("syswow64", "system32")]
        entries = []
        for index, path in enumerate(paths):
            entry = {"path": str(path)}
            if path.is_symlink():
                entry.update(kind="symlink", target=str(path.readlink()))
            elif path.is_file():
                backup = self.private / f"file-{index}"
                shutil.copy2(path, backup)
                entry.update(kind="file", backup=backup.name, sha256=digest(backup),
                             mode=stat.S_IMODE(path.stat().st_mode))
                backup.chmod(0o600)
            else:
                entry["kind"] = "absent"
            entries.append(entry)
        raw = checked(["defaults", "export", menu.APP_BUNDLE_ID, "-"])
        preferences = plistlib.loads(raw.encode())
        saved = {key: preferences[key] for key in PREFERENCE_KEYS if key in preferences}
        (self.private / "preferences.plist").write_bytes(plistlib.dumps(saved))
        self.manifest.write_text(json.dumps(entries, indent=2) + "\n")
        (self.output / "docker-before.json").write_text(json.dumps(docker_state(), indent=2) + "\n")

    def restore(self) -> None:
        if menu.matching(menu.RELATED_SUFFIXES):
            raise RuntimeError("Cannot restore files while game, launcher, or Wine processes remain")
        entries = json.loads(self.manifest.read_text())
        for entry in entries:
            if entry["kind"] == "file" and digest(self.private / entry["backup"]) != entry["sha256"]:
                raise RuntimeError("Rollback snapshot checksum mismatch")
        for entry in entries:
            path = Path(entry["path"])
            if entry["kind"] == "file":
                if path.is_symlink():
                    path.unlink()
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(self.private / entry["backup"], path)
                path.chmod(entry["mode"])
                if digest(path) != entry["sha256"]:
                    raise RuntimeError("Restored file checksum mismatch")
            else:
                path.unlink(missing_ok=True)
                if entry["kind"] == "symlink":
                    path.symlink_to(entry["target"])
        prefs = plistlib.loads((self.private / "preferences.plist").read_bytes())
        for key in PREFERENCE_KEYS:
            if key in prefs:
                value = prefs[key]
                checked(["defaults", "write", menu.APP_BUNDLE_ID, key,
                         "-bool" if isinstance(value, bool) else "-string",
                         str(value).lower() if isinstance(value, bool) else value])
            else:
                menu.run(["defaults", "delete", menu.APP_BUNDLE_ID, key])
        before = json.loads((self.output / "docker-before.json").read_text())
        unchanged = before == docker_state()
        (self.output / "restoration.json").write_text(json.dumps({
            "files_restored": len(entries), "preferences_restored": True,
            "docker_unchanged": unchanged, "related_processes": [],
        }, indent=2) + "\n")
        if not unchanged:
            raise RuntimeError("Docker identity or start time changed during benchmark")
        menu.log(f"restored {len(entries)} file states and launcher preferences")


def pin_local_account(game: Path) -> None:
    profile = (game / "config/boot/lsb-docker.ini").read_text()
    user = re.search(r"--user\s+(\S+)", profile)
    password = re.search(r"--pass\s+(\S+)", profile)
    host = re.search(r"--server\s+(\S+)", profile)
    if not user or user[1].lower() != USER or not password or not host or host[1] not in ("127.0.0.1", "localhost"):
        raise RuntimeError("The saved local boot profile must identify hxitest on loopback")
    path = Path.home() / "Library/Application Support/HorizonXI-on-Mac/accounts.json"
    accounts = json.loads(path.read_text())
    accounts[WORLD + "|" + USER] = password[1]
    path.write_text(json.dumps(accounts, indent=2) + "\n")
    path.chmod(0o600)
    for key, value in (("server.selected", WORLD), ("account.user", USER),
                       ("account.user." + WORLD, USER)):
        checked(["defaults", "write", menu.APP_BUNDLE_ID, key, "-string", value])
    checked(["defaults", "write", menu.APP_BUNDLE_ID, "account.remember", "-bool", "true"])


def stage_app(options: argparse.Namespace) -> Path:
    if not options.renderer_bundle and not options.converter:
        return menu.APP
    app = options.output / "candidate.app"
    checked(["ditto", str(menu.APP), str(app)], timeout=120)
    resources = app / "Contents/Resources"
    if options.renderer_bundle:
        shutil.copy2(options.renderer_bundle / "native/i386-windows/d3d9.dll",
                     resources / "dxvk-1.10.3-x32-d3d9-horizonxi.dll")
    if options.converter:
        shutil.copy2(options.converter, resources / "d3d8to9.dll")
    checked(["codesign", "--force", "--deep", "--sign", "-", str(app)], timeout=60)
    checked(["codesign", "--verify", "--deep", "--strict", str(app)])
    return app


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--restore", type=Path)
    parser.add_argument("--renderer-bundle", type=Path)
    parser.add_argument("--renderer-config", default="color.hdr.enable=false;render.scale=1;present.maxFps=0",
                        help="mtld3d configuration overrides for this run")
    parser.add_argument("--renderer-log", default="mtld3d=info",
                        help="mtld3d RUST_LOG filter, recorded with the run")
    parser.add_argument("--converter", type=Path)
    parser.add_argument("--boot-file", type=Path, help="frozen full boot script; otherwise minimal")
    parser.add_argument("--load-plugin", action="append", default=[])
    parser.add_argument("--load-addon", action="append", default=[])
    parser.add_argument("--background", type=int, choices=(512, 1024, 2048, 4096),
                        help="temporary square background dimensions; keeps other quality settings")
    parser.add_argument("--menu-sample", type=float, default=15)
    parser.add_argument("--dump", action="store_true", help="F12 dump at character selection")
    parser.add_argument("--dump-scene", help="F12 dump at a named scene screenshot, such as city-settled")
    options, forwarded = parser.parse_known_args()
    if options.restore:
        Snapshot(options.restore.resolve()).restore()
        return 0
    if not options.output:
        parser.error("--output is required")
    options.output = options.output.expanduser().resolve()
    if menu.matching(menu.RELATED_SUFFIXES):
        parser.error("close the game, Wine, and launcher before starting")
    if menu.run(["git", "-C", str(options.output.parent), "rev-parse", "--show-toplevel"]).returncode == 0:
        parser.error("--output must be outside a Git checkout because it contains private backups")
    if options.menu_sample < 0 or options.menu_sample > 60:
        parser.error("--menu-sample must be between 0 and 60 seconds")
    for name in options.load_plugin + options.load_addon:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            parser.error("plugin and addon names must be plain identifiers")
    options.output.mkdir(parents=True, exist_ok=False)
    OCR_TOOL.parent.mkdir(parents=True, exist_ok=True)
    if not OCR_TOOL.is_file() or OCR_TOOL.stat().st_mtime < (HERE / "scene-ocr.swift").stat().st_mtime:
        checked(["xcrun", "swiftc", "-O", "-o", str(OCR_TOOL), str(HERE / "scene-ocr.swift")], timeout=120)
    menu.OVERRIDE_PREFIXES += ("MTLD3D_", "WINEDLLPATH", "RUST_LOG")
    original_class = menu.MenuRun

    class RendererRun(original_class):
        def preflight(self) -> bool:
            if not 0 < self.args.limit <= 420 or not 0 < self.args.capture_seconds <= 420:
                raise RuntimeError("Renderer capture and game limits must be within 420 seconds")
            if self.args.world != WORLD or self.args.game_dir != menu.DEFAULT_GAME or self.args.profile != "lsb-docker.ini":
                raise RuntimeError("Renderer runs are restricted to the installed local Hxitest profile")
            pin_local_account(self.game_dir)
            profile = self.game_dir / "config/boot/lsb-docker.ini"
            if options.background:
                profile.write_text(set_background(profile.read_text(), options.background))
            self.record["graphics_requested"] = graphics_values(profile.read_text())
            if not super().preflight():
                return False
            if not self.args.scenario and not self.install_addon():
                return False
            if options.renderer_bundle:
                for bits in ("syswow64", "system32"):
                    shutil.copy2(options.renderer_bundle / "prefix-markers" / bits / "mtld3d.dll",
                                 menu.PREFIX / "drive_c/windows" / bits / "mtld3d.dll")
            return True

        def install_addon(self) -> bool:
            if not super().install_addon():
                return False
            boot = options.boot_file.read_text() if options.boot_file else (
                "/load Addons\n" + "".join(f"/load {name}\n" for name in options.load_plugin)
                + "".join(f"/addon load {name}\n" for name in ("fps", "drawdistance", *options.load_addon)))
            if "/addon load perfscene" not in boot:
                boot = boot.rstrip() + "\n/addon load perfscene\n"
            (self.game_dir / "scripts/perfscene.txt").write_text(boot)
            self.record["boot_sha256"] = hashlib.sha256(boot.encode()).hexdigest()
            self.record["minimal_plugins"] = options.boot_file is None
            return True

        def arm_recorder(self) -> bool:
            ok = super().arm_recorder()
            if ok:
                (options.output / "active.json").write_text(json.dumps({"session": str(self.session_dir)}) + "\n")
            return ok

        def launch(self) -> bool:
            ok = super().launch()
            self.record["graphics_at_launch"] = graphics_values(
                (self.game_dir / "config/boot/lsb-docker.ini").read_text())
            (options.output / "active.json").write_text(json.dumps({"session": str(self.session_dir), "pid": self.game_pid}) + "\n")
            return ok

        def collect_profile(self) -> None:
            if self.session_dir and self.game_pid:
                paths = sorted((self.game_dir / "bootloader/mtld3d-logs").glob(f"*-{self.game_pid}.log"))
                for path in paths:
                    shutil.copy2(path, self.session_dir / path.name)
                self.record["renderer_logs"] = [path.name for path in paths]
            super().collect_profile()

        def wait_for_scene(self, scene, timeout):
            label = scene[0]
            expected = {"rules": ("accept", "decline", "rules of conduct"),
                        "main menu": ("select character", "create character", "delete character"),
                        "character list": ("hxitest", "no. of characters registered: 1", "play.")}[label]
            deadline = min(time.monotonic() + timeout, self.started + self.args.limit)
            matches = 0
            while time.monotonic() < deadline and menu.process_exists(self.game_pid):
                menu.read_available(self.recorder, self.recorder_lines)
                try:
                    window = json.loads(checked([str(self.window_tool), "find", str(self.game_pid)]))
                    screen = self.session_dir / ("ocr-" + label.replace(" ", "-") + ".png")
                    checked(["screencapture", "-x", "-l", str(window["window_id"]), str(screen)], timeout=10)
                    seen = re.sub(r"\s+", " ", checked([str(OCR_TOOL), str(screen)], timeout=10).lower())
                    active = counter_is_advancing(self.session_dir / "common-fps.csv", time.time())
                    matches = matches + 1 if active and all(text in seen for text in expected) else 0
                    if matches >= 2:
                        self.event("scene confirmed by OCR", scene=label)
                        return True
                except (RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired):
                    matches = 0
                time.sleep(2)
            self.screenshot("timeout-" + label.replace(" ", "-"))
            return False

        def screenshot(self, label):
            super().screenshot(label)
            if label == options.dump_scene:
                checked([str(self.window_tool), "f12", str(self.game_pid)])
                self.event("renderer F12 dump requested", scene=label)
            if label not in ("rules", "main-menu", "characters"):
                return
            if options.menu_sample > 0:
                time.sleep(5)
                self.event("menu sample start", scene=label, epoch=time.time())
                until = time.monotonic() + options.menu_sample
                while time.monotonic() < until and menu.process_exists(self.game_pid):
                    menu.read_available(self.recorder, self.recorder_lines)
                    time.sleep(0.5)
                self.event("menu sample end", scene=label, epoch=time.time())
                super().screenshot("measured-" + label)
            if not counter_is_advancing(self.session_dir / "common-fps.csv", time.time()):
                raise RuntimeError("Frame counter stopped during the menu sample")
            if label == "characters":
                loaded = checked(["lsof", "-p", str(self.game_pid), "-Fn"])
                paths = sorted({line[1:] for line in loaded.splitlines() if line.startswith("n")
                                and Path(line[1:]).name.lower() in
                                ("d3d8.dll", "d3d9.dll", "mtld3d.dll", "mtld3d.so", "libmoltenvk.dylib")})
                identities = [{"path": path, "sha256": digest(Path(path)) if Path(path).is_file() else None}
                              for path in paths]
                (self.session_dir / "renderer-loaded-files.json").write_text(json.dumps(identities, indent=2) + "\n")
                resources = menu.APP / "Contents/Resources"
                expected = {"d3d8.dll": digest(resources / "d3d8to9.dll"),
                            "d3d9.dll": digest(resources / "dxvk-1.10.3-x32-d3d9-horizonxi.dll")}
                if options.renderer_bundle:
                    expected.update({"mtld3d.dll": digest(options.renderer_bundle / "wine/i386-windows/mtld3d.dll"),
                                     "mtld3d.so": digest(options.renderer_bundle / "wine/x86_64-unix/mtld3d.so")})
                for name, expected_hash in expected.items():
                    if not any(Path(row["path"]).name == name and row["sha256"] == expected_hash
                               for row in identities):
                        raise RuntimeError(f"Loaded {name} does not match the staged renderer")
                self.record["renderer_verified"] = expected
                self.record["renderer_config"] = options.renderer_config if options.renderer_bundle else None
                self.record["renderer_log"] = options.renderer_log if options.renderer_bundle else None
                if options.dump:
                    checked([str(self.window_tool), "f12", str(self.game_pid)])
                    self.event("renderer F12 dump requested")

    menu.MenuRun = RendererRun
    snapshot = Snapshot(options.output)
    snapshot.save(menu.DEFAULT_GAME)
    try:
        menu.APP = stage_app(options)
        sys.argv = [sys.argv[0], "--world", WORLD, "--characters", "--limit", "300",
                    "--capture-seconds", "280", "--hold", "5",
                    "--env", "PERFSCENE_FPS={session}\\common-fps.csv",
                    "--env", "PERFSCENE_MARKERS={session}\\perfscene-markers.jsonl",
                    "--env", "PERFSCENE_MENU_UNCAP=1", *forwarded]
        if options.renderer_bundle:
            sys.argv += ["--env", "WINEDLLPATH=" + str(options.renderer_bundle.resolve() / "wine"),
                         "--env", "MTLD3D_CONFIG=" + options.renderer_config,
                         "--env", "RUST_LOG=" + options.renderer_log]
        result = menu.main()
        (options.output / "result.json").write_text(json.dumps({"exit_code": result}) + "\n")
        return result
    finally:
        snapshot.restore()


if __name__ == "__main__":
    raise SystemExit(main())
