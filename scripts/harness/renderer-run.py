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
REPORT_SPEC = importlib.util.spec_from_file_location("renderer_report", HERE / "renderer-report.py")
reporting = importlib.util.module_from_spec(REPORT_SPEC)
assert REPORT_SPEC.loader is not None
REPORT_SPEC.loader.exec_module(reporting)
WORLD = "Local LSB (Docker)"
USER = "hxitest"
PREFERENCE_KEYS = ("server.selected", "account.user", "account.user." + WORLD, "account.remember",
                   "perf.settings")
OCR_TOOL = HERE / ".build/scene-ocr"


def checked(argv: list[str], timeout: float = 30) -> str:
    result = menu.run(argv, timeout=timeout)
    if result.returncode:
        # Boot and account errors can carry credentials. Do not echo command output.
        raise RuntimeError(f"{Path(argv[0]).name} failed with status {result.returncode}")
    return result.stdout


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_digest(root: Path) -> str:
    """Include file bytes, modes, empty directories and symlink targets in rollback checks."""
    entries = []
    for path in [root, *sorted(root.rglob("*"))]:
        entry = [str(path.relative_to(root)), stat.S_IMODE(path.lstat().st_mode)]
        if path.is_symlink():
            entry += ["symlink", str(path.readlink())]
        elif path.is_file():
            entry += ["file", digest(path)]
        elif path.is_dir():
            entry += ["directory"]
        else:
            raise RuntimeError("Unsupported file type in configuration backup")
        entries.append(entry)
    return hashlib.sha256(json.dumps(entries).encode()).hexdigest()


def counter_is_advancing(path: Path, now: float) -> bool:
    try:
        with path.open() as handle:
            rows = list(csv.DictReader(handle))
        return bool(rows) and 0 <= now - float(rows[-1]["epoch"]) < 3
    except (OSError, ValueError, KeyError):
        return False


def scene_text_matches(label: str, text: str) -> bool:
    seen = re.sub(r"\s+", " ", text).lower()
    expected = {"rules": ("accept", "decline", "rules of conduct"),
                "main menu": ("create character", "delete character"),
                "character list": ("hxitest", "no. of characters registered: 1", "play.")}[label]
    if not all(word in seen for word in expected):
        return False
    # The mouse can obscure the highlighted button. Its footer identifies the
    # same selection without requiring OCR to read through the pointer.
    return label != "main menu" or any(word in seen for word in
        ("select character", "select a character to log on with"))


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


def match_graphics(text: str, source: str) -> str:
    """Copy only numeric graphics settings, preserving the local login and boot script."""
    values = graphics_values(source)
    if not {"0001", "0002", "0003", "0004"} <= values.keys() or not values.keys() <= graphics_values(text).keys():
        raise RuntimeError("Graphics profiles have missing or incompatible numeric keys")
    section = False
    lines = []
    for line in text.splitlines(keepends=True):
        if line.strip().startswith("["):
            section = line.strip().lower() == "[ffxi.registry]"
        match = re.match(r"^(\s*(\d{4})\s*=\s*)\d+", line) if section else None
        if match and match[2] in values:
            line = match[1] + str(values[match[2]]) + line[match.end():]
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
        paths = [game / "config", game / "scripts/perfscene.txt",
                 game / "scripts/default.txt", game / "addons/perfscene/perfscene.lua",
                 game / "bootloader/mtld3d_shaders.bin",
                 Path.home() / "Library/Application Support/HorizonXI-on-Mac/accounts.json"]
        directories = (game, game / "bootloader", game / "SquareEnix/PlayOnlineViewer",
                       game / "SquareEnix/FINAL FANTASY XI",
                       menu.PREFIX / "drive_c/windows/syswow64")
        paths += [directory / name for directory in directories
                  for name in ("d3d8.dll", "d3d9.dll", "d3d8.ini", "dxvk.conf", "dgVoodoo.conf")]
        paths += [menu.PREFIX / name for name in ("user.reg", "system.reg", "userdef.reg")]
        paths += [menu.PREFIX / "drive_c/windows" / bits / "mtld3d.dll"
                  for bits in ("syswow64", "system32")]
        paths += [menu.PREFIX / "drive_c/windows" / bits / name
                  for bits in ("syswow64", "system32")
                  for name in ("d3d11.dll", "d3d10core.dll", "dxgi.dll", "winemetal.dll")]
        entries = []
        for index, path in enumerate(paths):
            entry = {"path": str(path)}
            if path.is_symlink():
                entry.update(kind="symlink", target=str(path.readlink()))
            elif path.is_dir():
                backup = self.private / f"tree-{index}"
                shutil.copytree(path, backup, symlinks=True)
                entry.update(kind="directory", backup=backup.name, sha256=tree_digest(backup))
                if tree_digest(path) != entry["sha256"]:
                    raise RuntimeError("Configuration changed during backup")
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
            if entry["kind"] == "directory" and tree_digest(self.private / entry["backup"]) != entry["sha256"]:
                raise RuntimeError("Rollback configuration checksum mismatch")
        for entry in entries:
            path = Path(entry["path"])
            if entry["kind"] == "directory":
                if path.is_symlink() or path.is_file():
                    path.unlink()
                elif path.exists():
                    shutil.rmtree(path)
                shutil.copytree(self.private / entry["backup"], path, symlinks=True)
                if tree_digest(path) != entry["sha256"]:
                    raise RuntimeError("Restored configuration checksum mismatch")
            elif entry["kind"] == "file":
                if path.is_symlink():
                    path.unlink()
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(self.private / entry["backup"], path)
                path.chmod(entry["mode"])
                if digest(path) != entry["sha256"]:
                    raise RuntimeError("Restored file checksum mismatch")
            else:
                if path.is_dir() and not path.is_symlink():
                    shutil.rmtree(path)
                else:
                    path.unlink(missing_ok=True)
                if entry["kind"] == "symlink":
                    path.symlink_to(entry["target"])
        prefs = plistlib.loads((self.private / "preferences.plist").read_bytes())
        for key in PREFERENCE_KEYS:
            if key in prefs:
                value = prefs[key]
                if isinstance(value, bytes):
                    checked(["defaults", "write", menu.APP_BUNDLE_ID, key, "-data", value.hex()])
                else:
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
    if not options.renderer_bundle and not options.converter and not options.launcher_binary:
        return menu.APP
    app = options.output / "candidate.app"
    checked(["ditto", str(menu.APP), str(app)], timeout=120)
    resources = app / "Contents/Resources"
    if options.launcher_binary:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        shutil.copy2(options.launcher_binary, app / "Contents/MacOS" / info["CFBundleExecutable"])
    if options.renderer_bundle:
        shutil.copy2(options.renderer_bundle / "native/i386-windows/d3d9.dll",
                     resources / "dxvk-1.10.3-x32-d3d9-horizonxi.dll")
    if options.converter:
        shutil.copy2(options.converter, resources / "d3d8to9.dll")
    checked(["codesign", "--force", "--sign", "-", str(app)], timeout=60)
    checked(["codesign", "--verify", "--deep", "--strict", str(app)])
    return app


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--restore", type=Path)
    parser.add_argument("--renderer-bundle", type=Path)
    parser.add_argument("--launcher-binary", type=Path,
                        help="test a built launcher in a staged app copy")
    parser.add_argument("--shader-cache", type=Path,
                        help="seed mtld3d with a frozen shader cache for a matched comparison")
    parser.add_argument("--installed-mtld3d", action="store_true",
                        help="verify the installed app's mtld3d selection without renderer overrides")
    parser.add_argument("--dxmt-bundle", type=Path, help="DXMT release directory containing i386-windows and x86_64-unix")
    parser.add_argument("--dgvoodoo-config", type=Path, help="dgVoodoo configuration for the supplied D3D8 converter")
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
    parser.add_argument("--graphics-profile", type=Path,
                        help="match a saved profile's numeric graphics settings in the local profile")
    parser.add_argument("--draw-distance", type=float, default=20,
                        help="world and entity distance for the scenario, default stress setting 20")
    parser.add_argument("--menu-sample", type=float, default=15)
    parser.add_argument("--dump", action="store_true", help="F12 dump at character selection")
    parser.add_argument("--dump-scene", help="F12 dump at a named scene screenshot, such as city-settled")
    options, forwarded = parser.parse_known_args()
    if options.installed_mtld3d and (options.renderer_bundle or options.converter or options.dxmt_bundle
                                   or options.launcher_binary):
        parser.error("--installed-mtld3d cannot replace renderer resources")
    if options.installed_mtld3d and any(any(key in arg for key in
            ("WINEDLLPATH", "WINEDLLOVERRIDES", "MTLD3D_", "RUST_LOG")) for arg in forwarded):
        parser.error("--installed-mtld3d cannot inject renderer environment overrides")
    if not 0 < options.draw_distance <= 20:
        parser.error("--draw-distance must be greater than 0 and at most 20")
    if options.dxmt_bundle and (options.renderer_bundle or not options.converter or not options.dgvoodoo_config):
        parser.error("DXMT requires --converter and --dgvoodoo-config and excludes --renderer-bundle")
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
    menu.OVERRIDE_PREFIXES += ("MTLD3D_", "DXMT_", "WINEDLLPATH", "WINEDLLOVERRIDES", "RUST_LOG")
    original_class = menu.MenuRun

    class RendererRun(original_class):
        def preflight(self) -> bool:
            if not 0 < self.args.limit <= 420 or not 0 < self.args.capture_seconds <= 420:
                raise RuntimeError("Renderer capture and game limits must be within 420 seconds")
            if self.args.world != WORLD or self.args.game_dir != menu.DEFAULT_GAME or self.args.profile != "lsb-docker.ini":
                raise RuntimeError("Renderer runs are restricted to the installed local Hxitest profile")
            pin_local_account(self.game_dir)
            if options.launcher_binary:
                self.record["launcher_binary_sha256"] = digest(options.launcher_binary)
            if options.shader_cache:
                shutil.copy2(options.shader_cache, self.game_dir / "bootloader/mtld3d_shaders.bin")
                self.record["shader_cache_seed_sha256"] = digest(options.shader_cache)
            prefs = plistlib.loads(checked(["defaults", "export", menu.APP_BUNDLE_ID, "-"]).encode())
            perf = json.loads(prefs.get("perf.settings", b"{}"))
            if options.installed_mtld3d:
                if perf.get("renderer") != "mtld3d":
                    raise RuntimeError("Select mtld3d in the installed launcher before validation")
                for key in ("WINEDLLPATH", "WINEDLLOVERRIDES", "MTLD3D_CONFIG", "RUST_LOG"):
                    if menu.launchctl_get(key) or any(line.partition("=")[0].strip() == key
                            for line in perf.get("extraEnv", "").splitlines()):
                        raise RuntimeError(f"Clear the experimental {key} override before installed validation")
            else:
                # Staged experiments replace the DXVK resource. A saved mtld3d choice would
                # otherwise bypass that candidate and invalidate the comparison.
                perf["renderer"] = "metal"
                checked(["defaults", "write", menu.APP_BUNDLE_ID, "perf.settings", "-data",
                         json.dumps(perf).encode().hex()])
            profile = self.game_dir / "config/boot/lsb-docker.ini"
            if options.graphics_profile:
                profile.write_text(match_graphics(profile.read_text(), options.graphics_profile.read_text()))
            if options.background:
                profile.write_text(set_background(profile.read_text(), options.background))
            self.record["graphics_requested"] = graphics_values(profile.read_text())
            self.record["clock_requested_hour"] = 12
            if not super().preflight():
                return False
            if not self.args.scenario and not self.install_addon():
                return False
            if options.renderer_bundle:
                for bits in ("syswow64", "system32"):
                    shutil.copy2(options.renderer_bundle / "prefix-markers" / bits / "mtld3d.dll",
                                 menu.PREFIX / "drive_c/windows" / bits / "mtld3d.dll")
            if options.dxmt_bundle:
                for arch, bits in (("i386-windows", "syswow64"), ("x86_64-windows", "system32")):
                    for name in ("d3d11.dll", "d3d10core.dll", "dxgi.dll", "winemetal.dll"):
                        shutil.copy2(options.dxmt_bundle / arch / name,
                                     menu.PREFIX / "drive_c/windows" / bits / name)
                for directory in (self.game_dir, self.game_dir / "bootloader",
                                  self.game_dir / "SquareEnix/PlayOnlineViewer",
                                  self.game_dir / "SquareEnix/FINAL FANTASY XI"):
                    shutil.copy2(options.dgvoodoo_config, directory / "dgVoodoo.conf")
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
            launched_at = time.time()
            ok = super().launch()
            if ok and options.installed_mtld3d:
                spawn = Path.home() / "Library/Application Support/HorizonXI-on-Mac/last-spawn.txt"
                if spawn.stat().st_mtime < launched_at:
                    raise RuntimeError("No fresh launcher environment record")
                keys = ("WINEDLLPATH", "MTLD3D_CONFIG", "RUST_LOG")
                environment = {key: value for line in spawn.read_text().splitlines()
                               for key, sep, value in [line.partition("=")] if sep and key in keys}
                installed_wine = menu.APP / "Contents/Resources/mtld3d/wine"
                if environment.get("WINEDLLPATH") != str(installed_wine):
                    raise RuntimeError("Normal launcher did not select the bundled Wine shim")
                config = dict(part.split("=", 1) for part in environment.get("MTLD3D_CONFIG", "").split(";") if "=" in part)
                if any(config.get(key) != value for key, value in {
                    "color.hdr.enable": "false", "render.scale": "1", "present.maxFps": "0",
                    "render.mergePasses": "true", "render.submitDraws": "0"}.items()):
                    raise RuntimeError("Normal launcher did not select the tested mtld3d configuration")
                self.record["installed_renderer_environment"] = environment
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
                cache = self.game_dir / "bootloader/mtld3d_shaders.bin"
                if cache.is_file():
                    shutil.copy2(cache, self.session_dir / "mtld3d_shaders.bin")
            super().collect_profile()

        def wait_for_scene(self, scene, timeout):
            label = scene[0]
            deadline = min(time.monotonic() + timeout, self.started + self.args.limit)
            matches = 0
            while time.monotonic() < deadline and menu.process_exists(self.game_pid):
                menu.read_available(self.recorder, self.recorder_lines)
                try:
                    window = json.loads(checked([str(self.window_tool), "find", str(self.game_pid)]))
                    screen = self.session_dir / ("ocr-" + label.replace(" ", "-") + ".png")
                    checked(["screencapture", "-x", "-l", str(window["window_id"]), str(screen)], timeout=10)
                    ocr_args = [str(OCR_TOOL), str(screen)]
                    if label == "character list":
                        ocr_args.append("--character-list")
                    seen = re.sub(r"\s+", " ", checked(ocr_args, timeout=10).lower())
                    active = counter_is_advancing(self.session_dir / "common-fps.csv", time.time())
                    matches = matches + 1 if active and scene_text_matches(label, seen) else 0
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
            if label.replace("-", " ") in reporting.SETTLED_ZONES:
                markers = [json.loads(line) for line in self.markers_path().read_text().splitlines()]
                marker = next(row for row in reversed(markers) if row["label"] == label.replace("-", " "))
                clock_epoch = next((row["epoch"] for row in markers
                                    if row["label"] == "clock pinned to noon"), None)
                problem = reporting.world_scene_problem(marker, options.draw_distance, clock_epoch)
                if clock_epoch is None or problem:
                    raise RuntimeError(problem or "Clock setup marker is missing")
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
                                ("d3d8.dll", "d3d9.dll", "mtld3d.dll", "mtld3d.so", "libmoltenvk.dylib",
                                 "d3d11.dll", "dxgi.dll", "winemetal.dll", "winemetal.so")})
                identities = [{"path": path, "sha256": digest(Path(path)) if Path(path).is_file() else None}
                              for path in paths]
                (self.session_dir / "renderer-loaded-files.json").write_text(json.dumps(identities, indent=2) + "\n")
                resources = menu.APP / "Contents/Resources"
                expected = {"d3d8.dll": digest(resources / "d3d8to9.dll"),
                            "d3d9.dll": digest(resources / "dxvk-1.10.3-x32-d3d9-horizonxi.dll")}
                if options.installed_mtld3d:
                    installed_bundle = resources / "mtld3d"
                    manifest = json.loads((installed_bundle / "build.json").read_text())
                    for name, checksum in manifest["files"].items():
                        if digest(installed_bundle / name) != checksum:
                            raise RuntimeError(f"Installed mtld3d checksum mismatch: {name}")
                    expected.update({Path(name).name: checksum for name, checksum in manifest["files"].items()
                                     if name.startswith(("native/", "wine/"))})
                if options.renderer_bundle:
                    expected.update({"mtld3d.dll": digest(options.renderer_bundle / "wine/i386-windows/mtld3d.dll"),
                                     "mtld3d.so": digest(options.renderer_bundle / "wine/x86_64-unix/mtld3d.so")})
                if options.dxmt_bundle:
                    expected.pop("d3d9.dll")
                    expected.update({name: digest(options.dxmt_bundle / "i386-windows" / name)
                                     for name in ("d3d11.dll", "dxgi.dll", "winemetal.dll")})
                    expected["winemetal.so"] = digest(options.dxmt_bundle / "x86_64-unix/winemetal.so")
                for name, expected_hash in expected.items():
                    if not any(Path(row["path"]).name == name and row["sha256"] == expected_hash
                               for row in identities):
                        raise RuntimeError(f"Loaded {name} does not match the staged renderer")
                self.record["renderer_verified"] = expected
                self.record["installed_mtld3d"] = options.installed_mtld3d
                self.record["renderer_config"] = (self.record["installed_renderer_environment"]["MTLD3D_CONFIG"]
                    if options.installed_mtld3d else options.renderer_config if options.renderer_bundle else None)
                self.record["renderer_log"] = options.renderer_log if options.renderer_bundle else None
                self.record["draw_distance_requested"] = options.draw_distance
                if options.dxmt_bundle:
                    self.record["dgvoodoo_config_sha256"] = digest(options.dgvoodoo_config)
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
                    "--env", "PERFSCENE_MENU_UNCAP=1",
                    "--env", "PERFSCENE_DRAW_DISTANCE=" + str(options.draw_distance), *forwarded]
        if options.renderer_bundle:
            sys.argv += ["--env", "WINEDLLPATH=" + str(options.renderer_bundle.resolve() / "wine"),
                         "--env", "MTLD3D_CONFIG=" + options.renderer_config,
                         "--env", "RUST_LOG=" + options.renderer_log]
        if options.dxmt_bundle:
            sys.argv += ["--env", "WINEDLLPATH=" + str(options.dxmt_bundle.resolve()),
                         "--env", "WINEDLLOVERRIDES=d3d11,dxgi,d3d10core,winemetal=b",
                         "--env", "DXMT_LOG_PATH={session}",
                         "--env", "DXMT_CONFIG=dxgi.forceSDR=True;d3d11.preferredMaxFrameRate=0"]
        result = menu.main()
        (options.output / "result.json").write_text(json.dumps({"exit_code": result}) + "\n")
        return result
    finally:
        snapshot.restore()


if __name__ == "__main__":
    raise SystemExit(main())
