#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("effects_report",
    Path(__file__).parents[1] / "harness/effects-report.py")
effects = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(effects)


class EffectsReportTests(unittest.TestCase):
    def test_long_boundary_frame_is_counted_in_full(self):
        rows = [{"epoch": 0.01, "frame_ms": 20, "zone": 234},
                {"epoch": 0.12, "frame_ms": 110, "zone": 234}]
        result = effects.frame_summary(rows, 0, 0.1)
        self.assertTrue(result["valid"])
        self.assertEqual(result["count"], 2)
        self.assertEqual(result["max_ms"], 110)
        self.assertEqual(result["frames_over_100ms"], 1)
        self.assertEqual(result["measured_seconds"], 0.13)
        self.assertAlmostEqual(result["fps"], 2 / 0.13, places=3)

    def test_missing_frames_and_wrong_zone_cannot_pass(self):
        rows = [{"epoch": 0.01, "frame_ms": 20, "zone": 234},
                {"epoch": 0.12, "frame_ms": 10, "zone": 234}]
        self.assertFalse(effects.frame_summary(rows, 0, 0.1)["valid"])
        self.assertFalse(effects.frame_summary([{**r, "zone": 235} for r in rows], 0, 0.1)["valid"])

    def test_no_effect_or_duplicate_cast_does_not_count_as_success(self):
        responses = [{"epoch": 1, "label": "effect action", "category": 4,
                      "self_target": True, "action_id": spell, "message": 230, "animation": spell}
                     for spell in effects.SPELLS]
        self.assertTrue(effects.spell_results(responses, 0, 2)["all_six_buffs_applied"])
        failed = [{**r, "message": 75} if r["action_id"] == 54 else r for r in responses]
        result = effects.spell_results(failed, 0, 2)
        self.assertTrue(result["all_six_spells_completed"])
        self.assertFalse(result["all_six_buffs_applied"])
        for changed in (responses[:-1], responses + [responses[0]],
                        [{**r, "self_target": False} for r in responses]):
            self.assertFalse(effects.spell_results(changed, 0, 2)["all_six_spells_completed"])

    def test_readback_and_gpu_timings_keep_separate_clocks(self):
        rows = effects.timing_rows([
            "[2026-09-05T22:00:00Z TRACE mtld3d::readback] lockable_rt 16x16 flush_ms=3.5 read_ms=4.0 status=0x0",
            "[2026-09-05T22:00:00Z TRACE mtld3d::readback] metal_blit 16x16 encode_ms=0.1 wait_ms=3.9",
            "[2026-09-05T22:00:00Z TRACE mtld3d::gpu_time] submit_seq=128 gpu_ms=2.0 kernel_ms=0.05",
            "[2026-09-05T22:00:00Z INFO mtld3d::d3d9] shaders: 1 compiled in 25ms"])
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]["epoch"], rows[2]["epoch"])
        self.assertEqual(rows[0]["flush_ms"], 3.5)
        self.assertEqual(rows[1]["wait_ms"], 3.9)
        self.assertEqual(rows[2]["gpu_ms"], 2.0)

    def test_chainspell_must_apply_once_to_self(self):
        response = {"epoch": 1, "label": "effect action", "category": 6,
                    "self_target": True, "action_id": 20, "message": 100, "animation": 37}
        self.assertTrue(effects.spell_results([response], 0, 2)["chainspell_applied"])
        for changed in ([], [response, response], [{**response, "message": 0}],
                        [{**response, "self_target": False}], [{**response, "action_id": 21}]):
            self.assertFalse(effects.spell_results(changed, 0, 2)["chainspell_applied"])


if __name__ == "__main__":
    unittest.main()
