import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('stable', Path(__file__).parents[1] / 'harness/stable-phase-report.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class StableTests(unittest.TestCase):
    def test_fixed_rate_and_transition_exclusion(self):
        frames = [dict(epoch=i / 100, frame_ms=10) for i in range(1, 1200)]
        # A frame ending inside the window but beginning before it must be excluded.
        frames.append(dict(epoch=3.5, frame_ms=2000))
        result = m.summarize(frames, dict(start=0, end=11, name='scene', valid=True))
        self.assertTrue(result['valid'])
        self.assertAlmostEqual(result['fps'], 100)
        self.assertEqual(result['p99_ms'], 10)
        self.assertEqual(result['frames_over_500ms'], 0)

    def test_missing_frames_and_invalid_workload_do_not_pass(self):
        phase = dict(start=0, end=11, name='scene', valid=True)
        frames = [dict(epoch=i / 100, frame_ms=10) for i in range(400, 500)]
        self.assertFalse(m.summarize(frames, phase)['valid'])
        self.assertFalse(m.summarize([], phase)['valid'])
        phase['valid'] = False
        self.assertFalse(m.summarize(frames, phase)['valid'])


if __name__ == '__main__':
    unittest.main()
