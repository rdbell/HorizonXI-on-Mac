#!/usr/bin/env python3
"""Package integrity checks without Wine, signing, downloads, or installed files."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('builder', Path(__file__).resolve().parents[1] / 'build-wine-native-host.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        (self.root / 'original').mkdir()
        for name in ['original/winemac.so', 'winemac.so', 'source.patch', 'COPYING.LIB']:
            (self.root / name).write_text(name)
        self.manifest = dict(runtime=builder.RUNTIME, source_commit=builder.base.SOURCE,
                             original=builder.base.digest(self.root / 'original/winemac.so'),
                             replacement=builder.base.digest(self.root / 'winemac.so'),
                             patch_sha256=builder.base.digest(self.root / 'source.patch'))
        self.save()

    def save(self):
        (self.root / 'build.json').write_text(json.dumps(self.manifest))

    def test_signing_requires_refresh_and_preserves_original(self):
        builder.verify(self.root)
        original = (self.root / 'original/winemac.so').read_bytes()
        (self.root / 'winemac.so').write_bytes(b'signed candidate')
        with self.assertRaises(ValueError):
            builder.verify(self.root)
        self.manifest['unsigned_replacement'] = self.manifest['replacement']
        self.manifest['replacement'] = builder.base.digest(self.root / 'winemac.so')
        self.save()
        builder.verify(self.root)
        self.assertEqual((self.root / 'original/winemac.so').read_bytes(), original)

    def test_missing_rollback_and_damaged_patch_are_rejected(self):
        rollback = self.root / 'original/winemac.so'
        original = rollback.read_bytes()
        rollback.unlink()
        with self.assertRaises(FileNotFoundError):
            builder.verify(self.root)
        rollback.write_bytes(original)
        (self.root / 'source.patch').write_text('wrong patch')
        with self.assertRaises(ValueError):
            builder.verify(self.root)

    def test_wrong_runtime_source_or_missing_license_is_rejected(self):
        for key in ['runtime', 'source_commit']:
            original = self.manifest[key]
            self.manifest[key] = 'different'
            self.save()
            with self.assertRaises(ValueError):
                builder.verify(self.root)
            self.manifest[key] = original
        self.save()
        (self.root / 'COPYING.LIB').unlink()
        with self.assertRaises(ValueError):
            builder.verify(self.root)


if __name__ == '__main__':
    unittest.main()
