# -*- coding: utf-8 -*-
"""Optimization regression tests: derivation plan and frame-reference caching."""
from __future__ import print_function

import os
import sys
import types
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src", "data_exporter", "backend"))
if "odbAccess" not in sys.modules:
    stub = types.ModuleType("odbAccess")
    stub.openOdb = lambda *args, **kwargs: None
    sys.modules["odbAccess"] = stub

import odb_export_series as series
from odb_export_state import make_output_spec
from odb_vtu_incremental import patch_spec, expected_derived


class DeltaSpecTests(unittest.TestCase):
    def test_native_addition_does_not_recompute_existing_derivatives(self):
        old = make_output_spec(["SDV11"], mises=True,
                               gnd_slide_diff=True, gnd_slide_ref="sliding0")
        final = make_output_spec(["SDV11", "SDV66"], mises=True,
                                 gnd_slide_diff=True, gnd_slide_ref="sliding0")
        present = set(["SDV11", "Mises"]) | expected_derived(old)["gnd_slide_diff"]
        delta, keep, has_work = patch_spec(old, final, present)
        self.assertTrue(has_work)
        self.assertEqual(delta["native_fields"], ["SDV66"])
        self.assertFalse(delta["mises"])
        self.assertIsNone(delta["gnd_slide_diff"])
        self.assertIn("DGND_Slide_Total", keep)

    def test_changed_slide_reference_only_updates_that_group(self):
        old = make_output_spec(["SDV11"], gnd_slide_diff=True,
                               gnd_slide_ref="sliding0", initial_ipf=True,
                               inp_path="/tmp/pretend.inp")
        final = make_output_spec(["SDV11"], gnd_slide_diff=True,
                                 gnd_slide_ref="previous_last", initial_ipf=True,
                                 inp_path="/tmp/pretend.inp")
        present = set(["SDV11"])
        for family in expected_derived(old).values():
            present.update(family)
        delta, keep, has_work = patch_spec(old, final, present)
        self.assertTrue(has_work)
        self.assertEqual(delta["native_fields"], [])
        self.assertIsNotNone(delta["gnd_slide_diff"])
        self.assertIsNone(delta["initial_ipf"])

    def test_sync_only_removal_requires_no_odb_read(self):
        old = make_output_spec(["SDV11", "SDV29"])
        final = make_output_spec(["SDV29"])
        delta, keep, has_work = patch_spec(
            old, final, set(["SDV11", "SDV29"]))
        self.assertFalse(has_work)
        self.assertEqual(delta["native_fields"], [])
        self.assertIn("SDV29", keep)
        self.assertNotIn("SDV11", keep)

    def test_different_reference_cache_keys(self):
        original_export = series.export_frame
        try:
            seen = []
            def fake_export(*args, **kwargs):
                seen.append(dict(kwargs))
                return (args[9], {"REF": 1}, {"IPF": 2},
                        {"DAT": 3}, {"SLIDE": 4})
            series.export_frame = fake_export
            bank = {}
            spec = make_output_spec(
                ["SDV11"], initial_ipf=True, inp_path="/tmp/a.inp",
                gnd_diff=True, gnd_dat="/tmp/a.dat",
                gnd_slide_diff=True, gnd_slide_ref="sliding0",
                delta_field="SDV11", ref_step="A", ref_frame=0)
            mesh = ("mesh",)
            series.export_with_spec(None, "part", "A", 0, "tmp.vtu",
                                    spec, "", None, mesh, bank)
            series.export_with_spec(None, "part", "A", 1, "tmp.vtu",
                                    spec, "", None, mesh, bank)
            self.assertIsNone(seen[0]["ref_cache"])
            self.assertEqual(seen[1]["ref_cache"], {"REF": 1})
            self.assertEqual(seen[1]["ipf_cache"], {"IPF": 2})
            self.assertEqual(seen[1]["gnd_cache"], {"DAT": 3})
            self.assertEqual(seen[1]["gnd_slide_cache"], {"SLIDE": 4})
            changed = make_output_spec(
                ["SDV11"], initial_ipf=True, inp_path="/tmp/a.inp",
                gnd_diff=True, gnd_dat="/tmp/a.dat",
                gnd_slide_diff=True, gnd_slide_ref="previous_last",
                delta_field="SDV11", ref_step="A", ref_frame=0)
            series.export_with_spec(None, "part", "A", 2, "tmp.vtu",
                                    changed, "", None, mesh, bank)
            self.assertIsNone(seen[2]["gnd_slide_cache"])
            self.assertEqual(seen[2]["gnd_cache"], {"DAT": 3})
        finally:
            series.export_frame = original_export


if __name__ == "__main__":
    unittest.main()
