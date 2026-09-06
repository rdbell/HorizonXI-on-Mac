#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import json
from unittest.mock import patch
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('guest_scene_report',
    Path(__file__).parents[1] / 'harness/guest-scene-report.py')
guest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guest)


class GuestSceneReportTests(unittest.TestCase):
    def test_restored_dll_cannot_supply_symbols_for_captured_renderer(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            installed = root / 'd3d9.dll'
            installed.write_bytes(b'restored renderer')
            bundle = root / 'bundle'
            bundle.mkdir()
            frozen = bundle / 'd3d9.dll'
            frozen.write_bytes(b'captured renderer')
            identities = [{'path': str(installed), 'sha256': guest.capture.sha256(frozen)}]
            module = {'path': str(installed), 'kind': 'pe', 'base': 100, 'size': 100}
            records = [{'modules': [module]}]
            guest.resolve_renderer_symbols(records, identities, None)
            self.assertIsNone(module['symbol_path'])
            self.assertEqual(guest.capture.module_location(110, [module])['location'], 'd3d9.dll+0xa')
            guest.resolve_renderer_symbols(records, identities, bundle)
            self.assertEqual(module['symbol_path'], str(frozen))

    def test_stress_phases_retain_validation_and_boundaries(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'active.json').write_text(json.dumps({'session': str(root)}))
            (root / 'perfscene-markers.jsonl').write_text(json.dumps({'label': 'stress phase start'}))
            phase = {'name': 'mixed-32', 'start': 10, 'end': 40, 'fps': 16, 'valid': False}
            with patch.object(guest, 'load') as load, patch.object(guest.renderer, 'report') as old:
                load.return_value.report.return_value = {'phases': [phase], 'problems': ['incomplete fixture']}
                result = guest.phase_report(root)
                self.assertEqual(result, {'scenes': [phase], 'problems': ['incomplete fixture']})
                old.assert_not_called()

    def test_scene_excludes_windows_crossing_either_boundary(self):
        records = [{'header': {'window_start_s': a, 'window_end_s': b}}
                   for a, b in [(0, 10), (10, 20), (20, 30)]]
        self.assertEqual(guest.complete_windows(records, 100, 105, 125), records[1:2])


if __name__ == '__main__':
    unittest.main()
