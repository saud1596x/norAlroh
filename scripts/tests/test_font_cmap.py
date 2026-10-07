"""Regression for ITMS-90853 without redistributing licensed font binaries."""
import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('qcf', Path(__file__).resolve().parents[1] / 'prepare-qcf-v2.py')
qcf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qcf)

def fixture(mac=b'\x00\x06\x00\x06\x00\x00'):
    # A real format-4 sentinel plus the upstream's six-byte legacy subtable.
    unicode = struct.pack('>12H', 4, 24, 0, 2, 2, 0, 0, 65535, 0, 65535, 1, 0)
    cmap = struct.pack('>HH', 0, 3)
    cmap += struct.pack('>HHI', 0, 3, 28)
    cmap += struct.pack('>HHI', 1, 0, 52)
    cmap += struct.pack('>HHI', 3, 1, 28)
    cmap += unicode + mac
    head = bytes(54)
    font = struct.pack('>I4H', 0x10000, 2, 32, 1, 0)
    font += struct.pack('>4sIII', b'cmap', qcf.checksum(cmap), 44, len(cmap))
    font += struct.pack('>4sIII', b'head', 0, 108, len(head))
    return font + cmap + bytes(108 - 44 - len(cmap)) + head

class CmapRepairTests(unittest.TestCase):
    def test_preserves_unicode_offsets_and_every_non_cmap_byte_except_adjustment(self):
        original = fixture()
        repaired, changed = qcf.sanitize_cmap(original)
        self.assertTrue(changed)
        self.assertEqual(len(repaired), len(original))
        self.assertEqual(repaired[72:96], original[72:96])
        self.assertEqual(struct.unpack_from('>H', repaired, 46)[0], 2)
        self.assertEqual(struct.unpack_from('>HHI', repaired, 48), (0, 3, 28))
        self.assertEqual(struct.unpack_from('>HHI', repaired, 56), (3, 1, 28))
        self.assertEqual(qcf.checksum(repaired), 0xb1b0afba)
        self.assertEqual(qcf.sanitize_cmap(repaired), (repaired, False))
        self.assertEqual(repaired[108:116], original[108:116])
        self.assertEqual(repaired[120:], original[120:])

    def test_valid_legacy_table_is_retained(self):
        original = fixture(struct.pack('>5H', 6, 10, 0, 0, 0))
        self.assertEqual(qcf.sanitize_cmap(original), (original, False))

    def test_unrecognized_truncation_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Invalid cmap length'):
            qcf.sanitize_cmap(fixture(struct.pack('>3H', 6, 8, 0)))

if __name__ == '__main__':
    unittest.main()
