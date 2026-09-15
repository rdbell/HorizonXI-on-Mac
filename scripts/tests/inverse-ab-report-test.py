import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'inverse_ab', Path(__file__).parents[1] / 'harness/inverse-ab-report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class InverseABTests(unittest.TestCase):
    def line(self, block, seconds, enabled):
        return f'[2026-09-13T00:00:{seconds:02}Z INFO mtld3d::d3d9] inverse_ab block={block} optimized={enabled}'

    def test_abba_schedule(self):
        rows = report.parse_switches([self.line(i, i * 8, mode)
                                     for i, mode in enumerate(('false', 'true', 'true', 'false'))])
        self.assertEqual([r['fused'] for r in rows], [False, True, True, False])

    def test_wrong_mode_and_missing_boundary_rejected(self):
        for lines in ([self.line(0, 0, 'true')],
                      [self.line(0, 0, 'false'), self.line(2, 16, 'true')],
                      [self.line(0, 0, 'false'), self.line(0, 8, 'false')]):
            with self.assertRaises(ValueError):
                report.parse_switches(lines)

    def test_switch_crossing_long_frame_is_excluded(self):
        switches = [{'epoch': float(i * 8), 'block': i, 'fused': i % 4 in (1, 2)} for i in range(13)]
        frames = [dict(epoch=i/20, frame_ms=50) for i in range(1, 1921)]
        frames.append(dict(epoch=11, frame_ms=4000))
        phase = report.windows.compare(frames, [dict(name='mixed-32', start=0, end=96)], switches)[0]
        self.assertTrue(phase['valid'])
        for mode in phase['modes'].values():
            self.assertEqual(mode['fps'], 20)
            self.assertEqual(mode['p99_ms'], 50)


if __name__ == '__main__':
    unittest.main()
