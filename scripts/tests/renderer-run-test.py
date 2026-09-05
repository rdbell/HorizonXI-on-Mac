#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "renderer_run", Path(__file__).parents[1] / "harness/renderer-run.py")
renderer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(renderer)


class RendererRunTests(unittest.TestCase):
    def test_launcher_candidate_replaces_named_executable_only_in_staged_app(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            installed = root / "installed.app"
            executable = installed / "Contents/MacOS/FFXI-on-Mac"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b"installed")
            (installed / "Contents/Info.plist").write_bytes(
                plistlib.dumps({"CFBundleExecutable": "FFXI-on-Mac"}))
            candidate = root / "HorizonXILauncher"
            candidate.write_bytes(b"candidate")
            options = SimpleNamespace(output=root / "run", renderer_bundle=None,
                                      converter=None, launcher_binary=candidate)
            def checked(argv, timeout=30):
                if argv[0] == "ditto":
                    shutil.copytree(argv[1], argv[2])
                return ""
            with patch.object(renderer.menu, "APP", installed), \
                 patch.object(renderer, "checked", checked):
                staged = renderer.stage_app(options)
            self.assertEqual((staged / "Contents/MacOS/FFXI-on-Mac").read_bytes(), b"candidate")
            self.assertEqual(executable.read_bytes(), b"installed")

    def test_menu_detection_accepts_footer_when_pointer_obscures_selection(self):
        observed = ("FINAL FANTASY XI\nSelectCgaracter\nCreate Character\n"
                    "Delete Character\nConfig\nBack\nSelect a character to log on with.")
        self.assertTrue(renderer.scene_text_matches("main menu", observed))
        self.assertTrue(renderer.scene_text_matches("main menu",
            "Select Character\nCreate Character\nDelete Character"))
        self.assertFalse(renderer.scene_text_matches("main menu",
            "Create Character\nDelete Character\nSelect a race."))
        self.assertFalse(renderer.scene_text_matches("main menu", "Select Character"))
        self.assertFalse(renderer.scene_text_matches("character list", observed))

    def test_background_override_preserves_other_settings_and_sections(self):
        original = ("[boot]\r\ncommand = private fixture\r\n0003 = 12\r\n"
                    "[ffxi.registry]\r\n0003 = 4096 ; width\r\n0004 = 4096\r\n"
                    "0018 = 2\r\n;0004 = 1\r\n[next]\r\n0004 = 7\r\n")
        changed = renderer.set_background(original, 2048)
        self.assertEqual(renderer.graphics_values(changed), {"0003": 2048, "0004": 2048, "0018": 2})
        self.assertEqual(changed, original.replace("4096", "2048"))
        for missing in ("[boot]\n0003=4096\n0004=4096\n", "[ffxi.registry]\n0003=4096\n"):
            with self.assertRaisesRegex(RuntimeError, "missing background"):
                renderer.set_background(missing, 2048)

    def test_frozen_window_cannot_satisfy_scene_detection(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "fps.csv"
            self.assertFalse(renderer.counter_is_advancing(path, 100))
            path.write_text("epoch,fps\n99,150\n")
            self.assertTrue(renderer.counter_is_advancing(path, 100))
            self.assertFalse(renderer.counter_is_advancing(path, 103))
            path.write_text("epoch,fps\n99,150\npartial")
            self.assertFalse(renderer.counter_is_advancing(path, 100))

    def test_match_graphics_keeps_local_connection_and_non_graphics_sections(self):
        local = ("[boot]\r\ncommand=local fixture\r\nscript=local.txt\r\n"
                 "[ffxi.registry]\r\n0001=1024\r\n0002=742\r\n0003=4096\r\n"
                 "0004=4096\r\n0021=0 ; setting\r\n[other]\r\n0021=7\r\n")
        source = ("[boot]\ncommand=public fixture\nscript=personal.txt\n"
                  "[ffxi.registry]\n0001=1882\n0002=1058\n0003=4096\n0004=4096\n0021=1\n")
        changed = renderer.match_graphics(local, source)
        self.assertEqual(changed, local.replace("0001=1024", "0001=1882")
                         .replace("0002=742", "0002=1058").replace("0021=0", "0021=1"))
        for invalid in ("", source + "0099=1\n"):
            with self.assertRaisesRegex(RuntimeError, "missing or incompatible"):
                renderer.match_graphics(local, invalid)

    def test_snapshot_restores_content_permissions_symlinks_and_absence(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            game = root / "game"
            (game / "config/boot").mkdir(parents=True)
            boot = game / "config/boot/lsb-docker.ini"
            boot.write_text("private boot fixture\n")
            boot.chmod(0o640)
            minimap = game / "config/minimap/minimap.ini"
            minimap.parent.mkdir()
            minimap.write_text("theme=circle\nopacity_map=1.0\n")
            minimap.chmod(0o600)
            (game / "config/empty").mkdir()
            (game / "config/link").symlink_to("minimap/minimap.ini")
            (game / "scripts").mkdir()
            original = game / "scripts/default.txt"
            original.write_text("/load Addons\n")
            (game / "bootloader").mkdir()
            shader_cache = game / "bootloader/mtld3d_shaders.bin"
            shader_cache.write_bytes(b"saved shaders")
            (game / "d3d8.dll").symlink_to("original.dll")
            prefix = root / "prefix"
            prefix.mkdir()
            system_dll = prefix / "drive_c/windows/syswow64/d3d9.dll"
            system_dll.parent.mkdir(parents=True)
            system_dll.write_bytes(b"original system renderer")
            output = root / "output"
            prefs = {"server.selected": "Example world", "account.remember": False,
                     "perf.settings": b'{"renderer":"mtld3d","msync":false}'}
            changes = []

            def checked(argv, timeout=30):
                if argv[1] == "export":
                    return plistlib.dumps(prefs).decode()
                changes.append(argv)
                return ""

            with patch.object(renderer.menu, "PREFIX", prefix), \
                 patch.object(renderer, "checked", checked), \
                 patch.object(renderer, "docker_state", return_value=[{"id": "same"}]), \
                 patch.object(renderer.menu, "matching", return_value=[]), \
                 patch.object(renderer.menu, "run"), \
                 patch.object(renderer.Path, "home", return_value=root):
                snapshot = renderer.Snapshot(output)
                snapshot.save(game)
                boot.write_text("changed")
                boot.chmod(0o600)
                minimap.unlink()
                (game / "config/empty").rmdir()
                (game / "config/link").unlink()
                created = game / "config/xiui/Hxitest/settings.lua"
                created.parent.mkdir(parents=True)
                created.write_text("test settings")
                original.write_text("changed")
                shader_cache.write_bytes(b"test shaders")
                (game / "d3d8.dll").unlink()
                (game / "d3d8.dll").write_text("candidate")
                (game / "d3d9.dll").write_text("new file")
                system_dll.write_bytes(b"candidate system renderer")
                snapshot.restore()
            self.assertEqual(boot.read_text(), "private boot fixture\n")
            self.assertEqual(boot.stat().st_mode & 0o777, 0o640)
            self.assertEqual(minimap.read_text(), "theme=circle\nopacity_map=1.0\n")
            self.assertEqual(minimap.stat().st_mode & 0o777, 0o600)
            self.assertTrue((game / "config/empty").is_dir())
            self.assertEqual(str((game / "config/link").readlink()), "minimap/minimap.ini")
            self.assertFalse((game / "config/xiui").exists())
            self.assertEqual(original.read_text(), "/load Addons\n")
            self.assertEqual(shader_cache.read_bytes(), b"saved shaders")
            self.assertEqual(str((game / "d3d8.dll").readlink()), "original.dll")
            self.assertFalse((game / "d3d9.dll").exists())
            self.assertEqual(system_dll.read_bytes(), b"original system renderer")
            self.assertTrue(json.loads((output / "restoration.json").read_text())["docker_unchanged"])
            self.assertEqual(snapshot.private.stat().st_mode & 0o777, 0o700)
            self.assertTrue(any(row[-2:] == ["-bool", "false"] for row in changes))
            self.assertTrue(any(row[-2:] == ["-data", prefs["perf.settings"].hex()] for row in changes))

    def test_restore_refuses_live_processes_before_writing(self):
        with patch.object(renderer.menu, "matching", return_value=[(1, "wine")]):
            with self.assertRaisesRegex(RuntimeError, "processes remain"):
                renderer.Snapshot(Path("/nonexistent")).restore()

    def test_damaged_configuration_backup_stops_before_any_restore(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            snapshot = renderer.Snapshot(root / "output")
            snapshot.private.mkdir(parents=True)
            backup = snapshot.private / "tree-0"
            backup.mkdir()
            (backup / "settings").write_text("original")
            live = root / "live"
            live.mkdir()
            (live / "settings").write_text("live state")
            snapshot.manifest.write_text(json.dumps([{
                "kind": "directory", "path": str(live), "backup": backup.name,
                "sha256": renderer.tree_digest(backup)}]))
            (backup / "settings").write_text("damaged")
            with patch.object(renderer.menu, "matching", return_value=[]):
                with self.assertRaisesRegex(RuntimeError, "configuration checksum mismatch"):
                    snapshot.restore()
            self.assertEqual((live / "settings").read_text(), "live state")

    def test_public_world_and_wrong_character_cannot_pin_account(self):
        with tempfile.TemporaryDirectory() as temp:
            game = Path(temp)
            (game / "config/boot").mkdir(parents=True)
            profile = game / "config/boot/lsb-docker.ini"
            for line in ("--user hxitest --pass fixture --server example.com",
                         "--user another --pass fixture --server 127.0.0.1"):
                profile.write_text(line)
                with patch.object(renderer, "checked") as commands:
                    with self.assertRaisesRegex(RuntimeError, "loopback"):
                        renderer.pin_local_account(game)
                    commands.assert_not_called()


if __name__ == "__main__":
    unittest.main()
