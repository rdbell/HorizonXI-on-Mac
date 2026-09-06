import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).parents[1] / 'harness/readback-ab-report.py'
spec = importlib.util.spec_from_file_location('readback_ab_report', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ComparisonTests(unittest.TestCase):
    def test_excludes_boundary_crossing_frames_and_keeps_modes_separate(self):
        switches = [{'epoch': n * 8, 'block': n, 'fused': bool(n % 2)} for n in range(5)]
        frames = [{'epoch': t / 100, 'frame_ms': 10.0} for t in range(3200)]
        frames += [{'epoch': 2.01, 'frame_ms': 1000.0}, {'epoch': 8.1, 'frame_ms': 1000.0}]
        result = module.compare(frames, [{'name': 'crowd', 'start': 0, 'end': 32}], switches)[0]
        self.assertTrue(result['valid'])
        for mode in result['modes'].values():
            self.assertEqual(len(mode['windows']), 2)
            self.assertEqual(mode['p99_ms'], 10.0)
            self.assertAlmostEqual(mode['fps'], 100.0)
        self.assertAlmostEqual(result['fps_change_percent'], 0.0)

    def test_does_not_extrapolate_final_switch_or_missing_mode(self):
        result = module.compare([{'epoch': 3, 'frame_ms': 10}],
                                [{'name': 'crowd', 'start': 0, 'end': 32}],
                                [{'epoch': 0, 'block': 0, 'fused': False}])[0]
        self.assertFalse(result['valid'])
        self.assertIsNone(result['fps_change_percent'])
