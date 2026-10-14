# -*- coding: utf-8 -*-
"""Incremental PVD flow tests against a minimal mocked Abaqus ODB."""
from __future__ import print_function
import contextlib
import io
import os
import sys
import tempfile
import time
import types
import unittest
from unittest import mock
import xml.etree.ElementTree as ET

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(BASE, "src", "data_exporter", "backend"))
if "odbAccess" not in sys.modules:
    mock_abaqus = types.ModuleType("odbAccess")
    mock_abaqus.openOdb = lambda *a, **k: None
    sys.modules["odbAccess"] = mock_abaqus
import odb_export_series as series


class DummyFrame(object):
    def __init__(self, t):
        self.frameValue = float(t)


class DummyStep(object):
    def __init__(self):
        self.frames = [DummyFrame(0), DummyFrame(1), DummyFrame(2)]


class DummyODB(object):
    def __init__(self):
        self.steps = {"Normal_Load": DummyStep()}
        self.rootAssembly = types.SimpleNamespace(
            instances={"PART-1-1": object()})

    def close(self):
        pass


class Element(object):
    label = 1
    connectivity = [1]


def complete_vtu(path, fields=None):
    """Emit a real, tiny ASCII VTK XML dataset for merge-integrity checks."""
    fields = ["SDV11"] if fields is None else fields
    with open(path, "w") as f:
        f.write('<?xml version="1.0"?>\n')
        f.write('<VTKFile type="UnstructuredGrid" version="0.1" byte_order="LittleEndian">\n')
        f.write('<UnstructuredGrid>\n')
        f.write('<Piece NumberOfPoints="1" NumberOfCells="1">\n')
        f.write('<Points><DataArray type="Float64" NumberOfComponents="3" format="ascii">')
        f.write(' 0 0 0</DataArray></Points>\n')
        f.write('<Cells>\n')
        f.write('<DataArray type="Int64" Name="connectivity" format="ascii"> 0</DataArray>')
        f.write('<DataArray type="Int64" Name="offsets" format="ascii"> 1</DataArray>')
        f.write('<DataArray type="UInt8" Name="types" format="ascii"> 1</DataArray>\n')
        f.write('</Cells>\n')
        f.write('<PointData>\n</PointData>\n')
        f.write('<CellData>\n')
        for name in fields:
            f.write('<DataArray type="Float64" Name="%s" NumberOfComponents="1" format="ascii"> %d</DataArray>\n'
                    % (name, int(name.replace("SDV", ""))))
        f.write('</CellData></Piece></UnstructuredGrid></VTKFile>\n')


class SeriesFlowTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.odb_path = os.path.join(self.tmp.name, "fake.odb")
        with open(self.odb_path, "wb") as f:
            f.write(b"FAKE_ODBDATA")
        moment = time.time()
        os.utime(self.odb_path, (moment - 600, moment - 600))
        self.pvd = os.path.join(self.tmp.name, "fake_series.pvd")
        self.folder = os.path.join(self.tmp.name, "fake_series_frames")
        os.mkdir(self.folder)
        self.legacy0 = "fake_series_000001_Normal_Load_f000000.vtu"
        self.legacy1 = "fake_series_000002_Normal_Load_f000001.vtu"
        complete_vtu(os.path.join(self.folder, self.legacy0))
        complete_vtu(os.path.join(self.folder, self.legacy1))
        with open(self.pvd, "w") as f:
            f.write('<VTKFile type="Collection"><Collection>\n')
            for name in (self.legacy0, self.legacy1):
                f.write('<DataSet timestep="0" file="fake_series_frames/%s"/>\n' % name)
            f.write('</Collection></VTKFile>\n')
        signature = [
            "fields=SDV11", "element_set=", "bbox=", "delta=", "ref=:-1",
            "mises=0", "initial_ipf=0", "inp=", "ipf_dir=Z",
            "gnd_diff=0", "gnd_dat=", "gnd_dat_size=", "gnd_dat_mtime=",
            "gnd_diff_mode=slips", "gnd_slide_diff=0", "gnd_slide_ref=sliding0",
        ]
        sig_path = os.path.join(self.folder, "_ADE_export_signature.txt")
        with open(sig_path, "w") as f:
            f.write("\n".join(signature) + "\n")
        os.utime(sig_path, (moment - 100, moment - 100))
        self.selection = os.path.join(self.tmp.name, "frames.txt")
        self.calls = []

    def tearDown(self):
        self.tmp.cleanup()

    def run_series(self, frames, fields="SDV11", field_policy="merge"):
        with open(self.selection, "w") as f:
            for fi in frames:
                f.write("Normal_Load\t%d\n" % fi)
        argv = [
            "odb_export_series.py",
            "--odb", self.odb_path, "--instance", "PART-1-1",
            "--selection-file", self.selection, "--out-pvd", self.pvd,
            "--fields", fields, "--frame-policy", "merge",
            "--field-policy", field_policy,
        ]
        def fake_export(odb, instance_name, step_name, frame_index,
                        out_path, spec, element_set, bbox, mesh_cache, cache_bank=None):
            self.calls.append((step_name, frame_index, tuple(spec["native_fields"])))
            complete_vtu(out_path, spec["native_fields"])
            return mesh_cache
        out = io.StringIO()
        with mock.patch.object(series, "openOdb", return_value=DummyODB()), \
             mock.patch.object(series, "selected_elements",
                               return_value=([Element()], {}, {})), \
             mock.patch.object(series, "export_with_spec", side_effect=fake_export), \
             mock.patch.object(sys, "argv", argv), contextlib.redirect_stdout(out):
            rc = series.main()
        self.assertEqual(rc, 0, out.getvalue())
        return out.getvalue()

    def pvd_names(self):
        return [os.path.basename(x.get("file"))
                for x in ET.parse(self.pvd).getroot().iter("DataSet")]

    def test_reuse_legacy_and_append_only_new_frames(self):
        first = self.run_series([0, 1])
        self.assertIn("VTU INVENTORY: adopted 2 legacy states", first)
        self.assertIn("Unchanged/skipped states: 2", first)
        self.assertEqual(self.calls, [])
        second = self.run_series([0, 1, 2])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0][:2], ("Normal_Load", 2))
        names = self.pvd_names()
        self.assertEqual(names[:2], [self.legacy0, self.legacy1])
        self.assertEqual(names[2], "fake_series_000003_Normal_Load_f000002.vtu")
        self.assertIn("Unchanged/skipped states: 2", second)

    def test_unindexed_unselected_extra_vtu_does_not_abort_52_frame_style_export(self):
        # Simulates the user's error: 52 selected states and 62 complete
        # VTUs on disk, with ten previously generated, unindexed extras.
        # A minimal ODB mock has only three frames; two selected/indexed and
        # one unindexed extra is sufficient to exercise the identical branch.
        extra = "fake_series_000062_Normal_Load_f000002.vtu"
        path = os.path.join(self.folder, extra)
        complete_vtu(path)
        earlier = os.path.getmtime(self.odb_path) + 30
        os.utime(path, (earlier, earlier))
        log = self.run_series([0, 1])
        self.assertIn("ignoring 1 unindexed, unselected extra VTU", log)
        self.assertIn("Unchanged/skipped states: 2", log)
        self.assertEqual(self.calls, [])
        self.assertEqual(self.pvd_names(), [self.legacy0, self.legacy1])
        self.assertTrue(os.path.exists(path))
        self.assertNotIn(extra, self.pvd_names())

    def test_unverified_extra_selected_for_export_is_not_silently_reused(self):
        extra = "fake_series_000062_Normal_Load_f000002.vtu"
        path = os.path.join(self.folder, extra)
        complete_vtu(path)
        earlier = os.path.getmtime(self.odb_path) + 30
        os.utime(path, (earlier, earlier))
        # An explicitly selected extra with no verifiable provenance
        # must still be refused, and the published PVD must stay intact.
        with open(self.selection, "w") as f:
            f.write("Normal_Load\\t2\\n")
        argv = [
            "odb_export_series.py",
            "--odb", self.odb_path, "--instance", "PART-1-1",
            "--selection-file", self.selection, "--out-pvd", self.pvd,
            "--fields", "SDV11", "--frame-policy", "merge",
            "--field-policy", "merge",
        ]
        out = io.StringIO()
        with mock.patch.object(series, "openOdb", return_value=DummyODB()), \\
             mock.patch.object(series, "selected_elements",
                               return_value=([Element()], {}, {})), \\
             mock.patch.object(sys, "argv", argv), contextlib.redirect_stdout(out):
            rc = series.main()
        self.assertEqual(rc, 99)
        self.assertIn("lack trustworthy export metadata", out.getvalue())
        self.assertEqual(self.pvd_names(), [self.legacy0, self.legacy1])
        self.assertTrue(os.path.exists(path))

    def test_new_field_reuses_old_native_field(self):
        self.run_series([0, 1])
        self.calls[:] = []
        log = self.run_series([0], "SDV29")
        self.assertEqual(self.calls, [("Normal_Load", 0, ("SDV29",))])
        self.assertEqual(self.pvd_names(), [self.legacy0, self.legacy1])
        self.assertIn("Changed/rebuilt states: 1", log)
        self.assertIn("Field-level incremental states: 1", log)
        fields = {
            node.get("Name"): node.text.strip()
            for node in ET.parse(os.path.join(self.folder, self.legacy0)).getroot().iter("DataArray")
            if node.get("Name") and node.get("Name").startswith("SDV")
        }
        self.assertEqual(fields, {"SDV11": "11", "SDV29": "29"})

    def test_field_sync_removes_only_unselected_fields(self):
        self.run_series([0, 1])
        self.run_series([0], "SDV29")
        self.calls[:] = []
        log = self.run_series([0], "SDV29", field_policy="sync")
        self.assertEqual(self.calls, [])  # deletion-only does not read ODB fields
        fields = {
            node.get("Name"): node.text.strip()
            for node in ET.parse(os.path.join(self.folder, self.legacy0)).getroot().iter("DataArray")
            if node.get("Name") and node.get("Name").startswith("SDV")
        }
        self.assertEqual(fields, {"SDV29": "29"})
        self.assertIn("Field-level incremental states: 1", log)


if __name__ == "__main__":
    unittest.main()
