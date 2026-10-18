# -*- coding: utf-8 -*-
"""One-way safe adoption of a verified pre-manifest PVD/VTU collection.

Abaqus Python required. Original ODB/PVD/VTU remain READ ONLY. This command
NEVER enables direct in-place migration and never invents historic derived
settings. Strict mode verifies every frame numerically. Fast mode verifies two
representative frames numerically and checks all other frames against
the sampled mesh, without loading all historical field values.
"""
from __future__ import print_function
import argparse
import os
import shutil
import sys
import tempfile
import traceback
import uuid

from odbAccess import openOdb
from odb_export_vtu import parse_bbox, selected_elements, export_frame
from odb_export_state import (source_identity, source_revision, new_manifest,
                              make_output_spec, atomic_write_json, state_key)
from odb_legacy_baseline import (collect_pvd_states, choose_witness,
                                 validate_native_probe, select_representative_states,
                                 validate_legacy_lightweight)
from odb_vtu_incremental import vtu_arrays


def run(a):
    verification = 'fast' if a.mode == 'fast' else 'strict'
    if not a.odb or not os.path.isfile(a.odb):
        raise RuntimeError('Original ODB not found: ' + a.odb)
    source_pvd = os.path.abspath(a.pvd)
    stem = os.path.splitext(os.path.basename(source_pvd))[0]
    output = os.path.join(os.path.dirname(source_pvd), stem + '_MIGRATED_SAFE')
    target_pvd = os.path.join(output, os.path.basename(source_pvd))
    frame_target_dir = os.path.join(output, stem + '_frames')
    if os.path.exists(output):
        raise RuntimeError('Migration destination already exists: ' + output +
                           '. Nothing was modified; choose a new source or move the completed destination.')
    old_dir = os.path.join(os.path.dirname(source_pvd), stem + '_frames')
    if os.path.exists(os.path.join(old_dir, '_ODB2VTUS_manifest.json')):
        raise RuntimeError('Original dataset already has a manifest. Use normal Field Merge.')
    pvd_stamp = (os.path.getsize(source_pvd), os.path.getmtime(source_pvd))
    print('[CHECK] Opening ODB read-only: ' + a.odb)
    sys.stdout.flush()
    odb = openOdb(a.odb, readOnly=True)
    try:
        if a.instance not in odb.rootAssembly.instances:
            raise RuntimeError('ODB instance not found: ' + a.instance)
        inst = odb.rootAssembly.instances[a.instance]
        bbox = parse_bbox(a.bbox)
        elems, node_map, grain_ids = selected_elements(inst, a.element_set, bbox)
        if not elems:
            raise RuntimeError('The selected ODB element scope is empty.')
        elabels = set(int(e.label) for e in elems)
        nlabels = set(n for e in elems for n in e.connectivity)
        mesh_cache = (elems, node_map, grain_ids, elabels, nlabels)
        rows = collect_pvd_states(source_pvd, list(odb.steps.keys()),
                                  lambda s: len(odb.steps[s].frames))
        print('[CHECK] PVD states: %d; ODB selected cells: %d' % (len(rows), len(elems)))
        print('[CHECK] Verification mode: ' + verification)
        samples = (set(select_representative_states(rows)) if verification == 'fast'
                   else set(range(len(rows))))
        print('[CHECK] Sampled numerical ODB witnesses: %d/%d; non-sampled frames use mesh/header checks.'
              % (len(samples), len(rows))) if verification == 'fast' else print(
                  '[CHECK] Strict numerical ODB witness for every frame.')
        sys.stdout.flush()
        rev = source_revision(a.odb)
        manifest = new_manifest(source_identity(a.odb, a.instance, a.element_set, a.bbox))
        manifest['legacy_migration'] = {'mode': ('two_sample_numerical_plus_all_mesh' if verification == 'fast' else 'numerically_verified'),
                'source_pvd': source_pvd, 'source_revision': rev,
                'verified_all_frames': True, 'native_values_verified': verification == 'strict',
                'sampled_numerical_frames': len(samples), 'frame_count': len(rows),
                'original_derived_settings': 'unknown'}
        inspected = []
        # Probes live in the system temp folder, not alongside the legacy files.
        with tempfile.TemporaryDirectory(prefix='odb2vtus_legacy_verify_') as work:
            for num, (sname, frame_i, fn, path) in enumerate(rows, 1):
                now = source_revision(a.odb)
                if now != rev:
                    raise RuntimeError('ODB changed during verification; nothing was migrated.')
                frame = odb.steps[sname].frames[frame_i]
                op, oc = vtu_arrays(path)
                if num - 1 in samples:
                    witness = choose_witness(op, oc, frame.fieldOutputs.keys())
                    probe = os.path.join(work, 'probe.vtu')
                    try:
                        export_frame(odb, a.instance, sname, frame_i, probe,
                                     [witness], a.element_set, bbox,
                                     mesh_cache=mesh_cache)
                        proof = validate_native_probe(path, probe, witness,
                                                      compare_values=True)
                    finally:
                        if os.path.isfile(probe):
                            os.remove(probe)
                else:
                    # The sampled original VTU has already been verified against
                    # the ODB. No ODB probe is exported for these frames.
                    proof = validate_legacy_lightweight(path, rows[0][3])
                native = sorted((op | oc) & set(frame.fieldOutputs.keys()))
                spec = make_output_spec(native)
                key = state_key(sname, frame_i)
                manifest['frames'][key] = {
                    'step': sname, 'frame': frame_i, 'file': fn, 'active': True,
                    'source_revision': rev, 'output_spec': spec,
                    'migration_verified': proof,
                    'legacy_derived_settings': 'unknown; existing DataArrays preserved'
                }
                inspected.append((fn, path, os.path.getsize(path), os.path.getmtime(path)))
                print('[%d/%d] %s %s frame %d (%s)' % (
                    num, len(rows), 'SAMPLED' if num - 1 in samples else 'LIGHT CHECK',
                    sname, frame_i, proof['verification']))
                sys.stdout.flush()
        if source_revision(a.odb) != rev:
            raise RuntimeError('ODB changed during verification; nothing was migrated.')
        if (os.path.getsize(source_pvd), os.path.getmtime(source_pvd)) != pvd_stamp:
            raise RuntimeError('PVD changed during precheck; migration refused.')
        for fn, src_path, nbytes, stamp in inspected:
            if os.path.getsize(src_path) != nbytes or os.path.getmtime(src_path) != stamp:
                raise RuntimeError('VTU changed during precheck; migration refused: ' + fn)
        print('[PRECHECK COMPLETE] %d frames checked, %d numerical witness(es). Original files unchanged.'
              % (len(rows), len(samples)))
        print('[TARGET] %s' % target_pvd)
        if a.mode == 'check':
            return 0
        needed = sum(s for _,_,s,_ in inspected) + os.path.getsize(source_pvd) + 20000000
        space = shutil.disk_usage(os.path.dirname(source_pvd)).free
        if needed > space:
            raise RuntimeError('Not enough free disk space for independent copies. '
                               'Need %d bytes, available %d bytes.' % (needed, space))
        tmp = output + '.INCOMPLETE_' + uuid.uuid4().hex[:10]
        os.makedirs(os.path.join(tmp, stem + '_frames'))
        try:
            for num, (fn, path, size, stamp) in enumerate(inspected, 1):
                if os.path.getsize(path) != size or os.path.getmtime(path) != stamp:
                    raise RuntimeError('Original VTU changed after verification: ' + fn)
                dest = os.path.join(tmp, stem + '_frames', fn)
                shutil.copy2(path, dest)  # independent data bytes; no hardlinks
                if os.path.getsize(dest) != size:
                    raise RuntimeError('Copied VTU size differs: ' + fn)
                if os.path.getsize(path) != size or os.path.getmtime(path) != stamp:
                    raise RuntimeError('Source VTU changed during copy: ' + fn)
                print('[COPY %d/%d] %s' % (num, len(inspected), fn))
                sys.stdout.flush()
            if source_revision(a.odb) != rev:
                raise RuntimeError('ODB changed during copying; refusing to publish.')
            if (os.path.getsize(source_pvd), os.path.getmtime(source_pvd)) != pvd_stamp:
                raise RuntimeError('PVD changed during copying.')
            shutil.copy2(source_pvd, os.path.join(tmp, os.path.basename(source_pvd)))
            if os.path.exists(output):
                raise RuntimeError('Destination name collision: ' + output)
            manifest_file = os.path.join(tmp, stem + '_frames', '_ODB2VTUS_manifest.json')
            atomic_write_json(manifest_file, manifest)
            # Publication only after all frame copies and metadata exist.
            if os.path.exists(output):
                raise RuntimeError('Destination created by another process: ' + output)
            os.rename(tmp, output)
            print('[MIGRATION SUCCESS] %s' % target_pvd)
            print('Select this NEW PVD for subsequent Frame/Field Merge.')
        except Exception:
            shutil.rmtree(tmp, ignore_errors=True)
            raise
        return 0
    finally:
        odb.close()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--mode', required=True, choices=('check','migrate','fast','strict'))
    p.add_argument('--odb', required=True)
    p.add_argument('--pvd', required=True)
    p.add_argument('--instance', required=True)
    p.add_argument('--element-set', default='')
    p.add_argument('--bbox', default='')
    args = p.parse_args()
    try:
        return run(args)
    except Exception:
        print('[SAFETY STOP] Legacy migration failed; original results were not changed.')
        print(traceback.format_exc())
        return 99

if __name__ == '__main__':
    sys.exit(main())
