import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('suite',Path(__file__).parents[1]/'harness/stress-suite.py')
s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)

class SuiteTests(unittest.TestCase):
    def test_command_keeps_bounds_cache_and_full_addons(self):
        a=argparse.Namespace(minimal=False,graphics_profile=None,background=None)
        cmd=s.command(Path('/tmp/suite'),'aga40',a)
        self.assertEqual(cmd[cmd.index('--limit')+1],'420')
        self.assertEqual(cmd[cmd.index('--capture-seconds')+1],'400')
        self.assertIn('--installed-mtld3d',cmd)
        self.assertIn('/tmp/suite/inputs/shaders.bin',cmd)
        self.assertIn('/tmp/suite/inputs/boot.txt',cmd)
        self.assertNotIn('--background',cmd)

    def test_fixture_refuses_existing_command(self):
        with tempfile.TemporaryDirectory() as root:
            fixture=s.Fixture(Path(root))
            with patch.object(s,'call',return_value=subprocess.CompletedProcess([],0,'abc\n')), \
                 patch.object(s.subprocess,'run',return_value=subprocess.CompletedProcess([],0)):
                with self.assertRaisesRegex(RuntimeError,'already exists'): fixture.stage()
                self.assertFalse(fixture.record.exists())

    def test_restore_refuses_changed_command(self):
        with tempfile.TemporaryDirectory() as root:
            fixture=s.Fixture(Path(root))
            fixture.record.write_text(json.dumps(dict(container='original-id',sha256='bad')))
            with patch.object(s.subprocess,'run',return_value=subprocess.CompletedProcess([],0)), \
                 patch.object(s,'call',return_value=subprocess.CompletedProcess([],0,b'changed')) as call:
                with self.assertRaisesRegex(RuntimeError,'changed'): fixture.restore()
                self.assertEqual(call.call_count,1)

    def test_restore_absent_is_idempotent(self):
        with tempfile.TemporaryDirectory() as root:
            fixture=s.Fixture(Path(root))
            fixture.record.write_text(json.dumps(dict(container='original-id',sha256='unused')))
            with patch.object(s.subprocess,'run',return_value=subprocess.CompletedProcess([],1)):
                fixture.restore();fixture.restore()
            self.assertTrue(json.loads((Path(root)/'fixture-restored.json').read_text())['removed'])

if __name__=='__main__': unittest.main()
