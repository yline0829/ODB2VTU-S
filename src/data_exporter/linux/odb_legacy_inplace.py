# -*- coding: utf-8 -*-
"""Adopt an old PVD/VTU collection IN MEMORY without copying its VTUs.

Fast: two numerical native witnesses, every other PVD state mesh/header check.
Strict: every PVD state numerical native witness.
Actual additions are separately checked by merge_vtu() against each frame.
"""
from __future__ import print_function
import os
import sys
import tempfile
from odb_export_vtu import export_frame
from odb_export_state import (source_identity, source_revision, new_manifest,
                              make_output_spec, state_key)
from odb_legacy_baseline import (collect_pvd_states, choose_witness,
                                 validate_native_probe, select_representative_states,
                                 validate_legacy_lightweight)
from odb_vtu_incremental import vtu_arrays


def adopt_in_memory(a, odb, bbox, mesh_cache, expected_revision):
    """Return a new manifest dict. Absolutely no output-file changes."""
    source_pvd = os.path.abspath(a.out_pvd)
    names = list(odb.steps.keys())
    rows = collect_pvd_states(source_pvd, names,
                              lambda s: len(odb.steps[s].frames))
    sampled = (set(select_representative_states(rows)) if a.compatibility_mode == 'fast'
               else set(range(len(rows))))
    manifest = new_manifest(source_identity(a.odb, a.instance,
                                            a.element_set, a.bbox))
    manifest['legacy_migration'] = {
        'mode': ('inplace_two_sample_numerical_plus_all_mesh'
                 if a.compatibility_mode == 'fast' else 'inplace_strict_numerical'),
        'source_pvd': source_pvd,
        'source_revision': expected_revision,
        'sampled_numerical_frames': len(sampled),
        'frame_count': len(rows),
        'native_values_verified_all_frames': a.compatibility_mode == 'strict',
        'original_derived_settings': 'unknown; actual old DataArrays retained',
        'write_mode': 'in_place'
    }
    original_pvd_stamp = (os.stat(source_pvd).st_size,
                          os.stat(source_pvd).st_mtime)
    inspected = []
    with tempfile.TemporaryDirectory(prefix='odb2vtus_inplace_probe_') as work:
        for i, (step, fi, filename, path) in enumerate(rows):
            if source_revision(a.odb) != expected_revision:
                raise RuntimeError('ODB changed during legacy preflight.')
            op, oc = vtu_arrays(path)
            frame = odb.steps[step].frames[fi]
            if i in sampled:
                witness = choose_witness(op, oc, frame.fieldOutputs.keys())
                probe = os.path.join(work, 'witness.vtu')
                try:
                    export_frame(odb, a.instance, step, fi, probe,
                                 [witness], a.element_set, bbox,
                                 mesh_cache=mesh_cache)
                    proof = validate_native_probe(path, probe, witness,
                                                  compare_values=True)
                finally:
                    if os.path.isfile(probe):
                        os.remove(probe)
            else:
                # All frames must agree with the sampled ODB-matched anchor.
                proof = validate_legacy_lightweight(path, rows[0][3])
            old_native = sorted((op | oc) & set(frame.fieldOutputs.keys()))
            manifest['frames'][state_key(step, fi)] = {
                'step': step, 'frame': fi, 'file': filename, 'active': True,
                'source_revision': expected_revision,
                'output_spec': make_output_spec(old_native),
                'adoption_verified': proof,
                'adoption_original_size': os.stat(path).st_size,
                'adoption_original_mtime': os.stat(path).st_mtime,
                'legacy_derived_settings': 'unknown; old arrays retained'
            }
            inspected.append((path, os.stat(path).st_size,
                              os.stat(path).st_mtime))
            print('[IN-PLACE PRECHECK %d/%d] %s / %d (%s)' %
                  (i + 1, len(rows), step, fi,
                   'NUMERICAL' if i in sampled else 'MESH/HEADER'))
            sys.stdout.flush()
    if source_revision(a.odb) != expected_revision:
        raise RuntimeError('ODB changed before in-place write.')
    if (os.stat(source_pvd).st_size, os.stat(source_pvd).st_mtime) != original_pvd_stamp:
        raise RuntimeError('PVD changed during preflight.')
    for path, size, stamp in inspected:
        st = os.stat(path)
        if st.st_size != size or st.st_mtime != stamp:
            raise RuntimeError('Existing VTU changed during preflight: ' + path)
    print('[IN-PLACE PRECHECK OK] %d states, %d numerical witnesses; no original modified.'
          % (len(rows), len(sampled)))
    return manifest
