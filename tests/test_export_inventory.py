# -*- coding: utf-8 -*-
"""Disk-inventory regression tests. No Abaqus license or ODB required."""
from __future__ import print_function
import hashlib
import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src", "data_exporter", "backend"))

from odb_export_inventory import scan_vtu_directory, allocate_vtu_name
from odb_export_state import state_key


def write_vtu(path, closed=True):
    with open(path, "wb") as f:
        f.write(b'<VTKFile type="UnstructuredGrid"><UnstructuredGrid>\n')
        f.write(b'<Piece NumberOfPoints="10" NumberOfCells="1">\n')
        f.write(b' ' * 128)
        if closed:
            f.write(b'</Piece></UnstructuredGrid></VTKFile>\n')


def write_pvd(path, names):
    with open(path, "w") as f:
        f.write('<VTKFile type="Collection"><Collection>\n')
        for name in names:
            f.write('<DataSet timestep="0" file="series_frames/%s"/>\n' % name)
        f.write('</Collection></VTKFile>')


class InventoryTest(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.TemporaryDirectory()
        self.folder = os.path.join(self.t.name, "myodb_series_frames")
        os.mkdir(self.folder)
        self.pvd = os.path.join(self.t.name, "myodb_series.pvd")
        self.stem = "myodb_series"
        self.steps = ["Normal_Load", "Sliding_Cycle_01"]
        self.count = lambda step: 100

    def tearDown(self):
        self.t.cleanup()

    def scan(self, manifest=None):
        return scan_vtu_directory(
            self.folder, self.stem, self.steps, self.count, self.pvd,
            existing_frames=manifest)

    def test_existing_legacy_frames_reused_by_step_and_frame(self):
        a = "myodb_series_000001_Normal_Load_f000020.vtu"
        b = "myodb_series_000002_Sliding_Cycle_01_f000000.vtu"
        write_vtu(os.path.join(self.folder, a))
        write_vtu(os.path.join(self.folder, b))
        write_pvd(self.pvd, [a, b])
        index, filenames, serial, issues = self.scan()
        self.assertEqual(index[state_key("Normal_Load", 20)], a)
        self.assertEqual(index[state_key("Sliding_Cycle_01", 0)], b)
        self.assertEqual(serial, 2)
        self.assertEqual(issues, [])
        self.assertEqual(len(filenames), 2)

    def test_add_new_frame_does_not_renumber_existing(self):
        a = "myodb_series_000008_Normal_Load_f000020.vtu"
        write_vtu(os.path.join(self.folder, a))
        write_pvd(self.pvd, [a])
        index, names, serial, issues = self.scan()
        new_name, serial = allocate_vtu_name(
            self.stem, "Normal_Load", 30, names, serial)
        self.assertEqual(new_name, "myodb_series_000009_Normal_Load_f000030.vtu")
        self.assertEqual(index[state_key("Normal_Load", 20)], a)
        self.assertFalse(issues)

    def test_existing_pvd_reference_wins_over_stale_manifest(self):
        older = "myodb_series_000001_Normal_Load_f000020.vtu"
        digest = hashlib.sha1(b"Normal_Load").hexdigest()[:8]
        newer = "Normal_Load__%s__f000020.vtu" % digest
        for name in (older, newer):
            write_vtu(os.path.join(self.folder, name))
        write_pvd(self.pvd, [older])
        manifest = {state_key("Normal_Load", 20): {"file": newer}}
        index, _, _, issues = self.scan(manifest)
        self.assertEqual(index[state_key("Normal_Load", 20)], older)
        self.assertTrue(any("Duplicate" in x for x in issues))

    def test_incomplete_vtu_is_not_reusable(self):
        filename = "myodb_series_000001_Normal_Load_f000020.vtu"
        write_vtu(os.path.join(self.folder, filename), closed=False)
        index, names, serial, issues = self.scan()
        self.assertNotIn(state_key("Normal_Load", 20), index)
        self.assertIn(filename, names)
        self.assertEqual(serial, 1)
        self.assertTrue(any("Incomplete" in x for x in issues))

    def test_frame_identity_uses_original_step_not_serial(self):
        names = [
            "myodb_series_000200_Normal_Load_f000020.vtu",
            "myodb_series_000003_Normal_Load_f000022.vtu",
        ]
        for name in names:
            write_vtu(os.path.join(self.folder, name))
        index, _, serial, issues = self.scan()
        self.assertEqual(serial, 200)
        self.assertEqual(index[state_key("Normal_Load", 20)], names[0])
        self.assertEqual(index[state_key("Normal_Load", 22)], names[1])
        self.assertFalse(issues)

    def test_unknown_step_not_claimed_by_another_step(self):
        f = "myodb_series_000005_UnknownStep_f000020.vtu"
        write_vtu(os.path.join(self.folder, f))
        index, names, serial, issues = self.scan()
        self.assertEqual(index, {})
        self.assertIn(f, names)
        self.assertTrue(issues)


if __name__ == "__main__":
    unittest.main()
