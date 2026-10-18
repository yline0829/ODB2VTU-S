"""Protect the original user-supplied 256px Linux Workbench artwork.

The original PNG is a release asset. Do not regenerate or restyle it.
"""
import hashlib
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ICON = ROOT / 'src/data_exporter/linux/icons/odb2vtu-s-exporter-256.png'
EXPECTED_SHA256 = '120ba8f404b9adb08eda957b77cf2791f0543cca46c58eb5a5f0897b86412ef6'


class LinuxIconIntegrityTests(unittest.TestCase):
    def test_canonical_high_resolution_png_is_unchanged(self):
        self.assertTrue(ICON.is_file(), 'Original 256px icon missing')
        data = ICON.read_bytes()
        self.assertTrue(data.startswith(b'\x89PNG\r\n\x1a\n'))
        self.assertEqual(struct.unpack('>II', data[16:24]), (256, 256))
        self.assertEqual(hashlib.sha256(data).hexdigest(), EXPECTED_SHA256)


if __name__ == '__main__':
    unittest.main()
