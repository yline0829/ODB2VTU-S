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


def complete_vtu(path):
    with open(path, "wb") as f:
        f.write(b'<VTKFile type="UnstructuredGrid">\n')
        f.write(b'<UnstructuredGrid><Piece NumberOfCells="1">\n')
        f.write(b'X' * 128)
        f.write(b'</Piece></UnstructuredGrid></VTKFile>\n')


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
                        out_path, spec, element_set, bbox, mesh_cache):
            self.calls.append((step_name, frame_index, tuple(spec["native_fields"])))
            complete_vtu(out_path)
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

    def test_new_field_rebuilds_same_existing_filename(self):
        self.run_series([0, 1])
        self.calls[:] = []
        log = self.run_series([0], "SDV29")
        self.assertEqual(self.calls, [("Normal_Load", 0, ("SDV11", "SDV29"))])
        self.assertEqual(self.pvd_names(), [self.legacy0, self.legacy1])
        self.assertIn("Changed/rebuilt states: 1", log)


if __name__ == "__main__":
    unittest.main()
