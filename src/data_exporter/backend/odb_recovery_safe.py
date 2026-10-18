# -*- coding: utf-8 -*-
"""Non-destructive ODB2VTU-S v0.2.1 reusable field recovery tool.

The original ODB, VTU, PVD, and Manifest are opened read-only. This tool does
NOT use the vulnerable generic Frame/Field Merge/Sync workflow.
Run under Abaqus Python, after completing the read-only preflight.
"""
from __future__ import print_function
import argparse
import copy
import json
import os
import re
import shutil
import sys
import time
import traceback
import xml.etree.ElementTree as ET

from odb_export_state import stable_vtu_name
from odb_vtu_incremental import (_mapping, _arrays, _compare_geometry,
                                 _copy_region, vtu_arrays)

MARKER = '_RECOVERY_TOOL_OWNER.json'
CHECKPOINT = '_RECOVERY_CHECKPOINT.json'
CHUNK = 1024 * 1024


def info(message):
    print(message)
    sys.stdout.flush()


def ensure(condition, message):
    if not condition:
        raise RuntimeError(message)


def atomic_json(path, value):
    temp = path + '.saving'
    with open(temp, 'w', encoding='utf-8') as f:
        json.dump(value, f, indent=2, ensure_ascii=False, sort_keys=True)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    os.replace(temp, path)


def metadata(path):
    return dict(size=int(os.path.getsize(path)), mtime=float(os.path.getmtime(path)))


def manifest_file_for(pvd):
    stem = os.path.splitext(os.path.basename(pvd))[0]
    d = os.path.join(os.path.dirname(pvd), stem + '_frames')
    return d, os.path.join(d, '_ODB2VTUS_manifest.json')


def inspect_vtu(path):
    f, mm = _mapping(path)
    try:
        psec, p, po = _arrays(mm, 'PointData')
        csec, c, co = _arrays(mm, 'CellData')
        ensure(not (set(p) & set(c)), 'Duplicate array name across PointData/CellData: ' + path)
        ensure(b'</VTKFile>' in mm[max(0, len(mm)-4096):], 'Incomplete VTU: ' + path)
        return set(p), set(c), len(p) + len(c)
    finally:
        mm.close()
        f.close()


def parse_project(pvd, requested_fields):
    pvd = os.path.abspath(pvd.strip().strip('"'))
    ensure(os.path.isfile(pvd), 'PVD file not found: ' + pvd)
    frame_dir, manifest_path = manifest_file_for(pvd)
    ensure(os.path.isfile(manifest_path), 'Manifest file not found: ' + manifest_path)
    with open(manifest_path, 'r', encoding='utf-8') as f:
        manifest = json.load(f)
    ensure(manifest.get('version') == 2, 'Only manifest version 2 is supported')
    source = manifest.get('source') or {}
    ensure(source.get('instance') and source.get('odb_path'), 'Incomplete manifest source identity')
    root = ET.parse(pvd).getroot()
    ensure(root.get('type') == 'Collection', 'PVD is not a VTK Collection')
    datasets = list(root.iter('DataSet'))
    ensure(len(datasets) > 0, 'PVD contains no frames')
    records = []
    visited_files = set()
    visited_keys = set()
    frames = manifest.get('frames', {})
    file_index = {}
    for key, entry in frames.items():
        if entry.get('active', True):
            name = entry.get('file')
            ensure(name and name not in file_index, 'Duplicate active Manifest filename: %r' % name)
            file_index[name] = (key, entry)
    ensure(len(file_index) == len(datasets), 'Active Manifest frame count differs from PVD')

    for ds in datasets:
        rel = (ds.get('file') or '').replace('\\', '/')
        parts = rel.split('/')
        ensure(len(parts) == 2 and parts[0] == os.path.basename(frame_dir),
               'Unexpected or unsafe PVD VTU path: ' + rel)
        fn = parts[1]
        ensure(fn.lower().endswith('.vtu') and fn not in ('', '.', '..')
               and os.path.basename(fn) == fn, 'Unsafe filename: ' + fn)
        ensure(fn in file_index, 'PVD filename absent from active Manifest: ' + fn)
        ensure(fn not in visited_files, 'Same VTU appears twice in PVD: ' + fn)
        visited_files.add(fn)
        key, ent = file_index[fn]
        ensure(key not in visited_keys, 'Same state repeated in PVD: ' + key)
        visited_keys.add(key)
        step = str(ent['step'])
        fi = int(ent['frame'])
        ensure(key == '%s\t%d' % (step, fi), 'Manifest key mismatches recorded frame: ' + key)
        suffix = '_' + re.sub(r'[^\w-]', '_', step) + '_f%06d.vtu' % fi
        ensure(fn.endswith(suffix) or fn == stable_vtu_name(step, fi),
               'VTU filename does not match expected Step/Frame: ' + fn)
        original = os.path.join(frame_dir, fn)
        ensure(os.path.isfile(original), 'PVD references nonexistent VTU: ' + original)
        pp, cc, count = inspect_vtu(original)
        present = pp | cc
        missing = tuple(field for field in requested_fields if field not in present)
        ensure(set(ent.get('output_spec', {}).get('native_fields', [])) <= present,
               'Native field listed in Manifest but missing from source VTU: ' + fn)
        ensure(count > 0, 'VTU has no field arrays: ' + fn)
        # Existing fields are never replaced; requested but absent fields are added.
        # Already complete frames are copied byte-identically to the recovery workspace.
        records.append(dict(key=key, step=step, frame=fi, filename=fn,
                            original=original, before_count=count,
                            old_metadata=metadata(original), missing=missing))
    ensure(set(file_index) == visited_files, 'Active Manifest states and PVD records differ')
    return pvd, frame_dir, manifest_path, manifest, source, records


def preflight(pvd, requested_fields, check_odb=True):
    pvd, frame_dir, manifest_path, manifest, src, records = parse_project(pvd, requested_fields)
    odbpath = os.path.abspath(src['odb_path'])
    ensure(os.path.isfile(odbpath), 'ODB missing at Manifest location: ' + odbpath)
    rev = records and (manifest['frames'][records[0]['key']].get('source_revision') or {})
    actual = metadata(odbpath)
    ensure(actual['size'] == rev.get('size'), 'ODB size changed since the export (unsafe)')
    ensure(abs(actual['mtime'] - float(rev.get('mtime', 0))) <= 2.0,
           'ODB modified time differs from Manifest (unsafe); stop and inspect')
    info('[OK] PVD: %s' % pvd)
    info('[OK] Current VTUs: %d published files' % len(records))
    info('[OK] Requested missing native fields: %s' % ', '.join(requested_fields))
    info('[OK] Original ODB: %s' % odbpath)
    info('[OK] No original file will be modified')
    if check_odb:
        try:
            from odbAccess import openOdb
        except ImportError:
            raise RuntimeError('Requires Abaqus Python (odbAccess unavailable)')
        odb = openOdb(odbpath, readOnly=True)
        try:
            ensure(src['instance'] in odb.rootAssembly.instances,
                   'Instance not found in ODB: ' + src['instance'])
            for n, r in enumerate(records, 1):
                ensure(r['step'] in odb.steps, 'ODB missing Step: '+r['step'])
                frames = odb.steps[r['step']].frames
                ensure(0 <= r['frame'] < len(frames), 'ODB frame index out of bounds')
                available = set(frames[r['frame']].fieldOutputs.keys())
                missing = set(r['missing']) - available
                ensure(not missing, 'ODB lacks %s in %s frame %d' %
                       (sorted(missing), r['step'], r['frame']))
                if n % 10 == 0 or n == len(records):
                    info('[CHECK] ODB frame variables: %d/%d' % (n, len(records)))
        finally:
            odb.close()
    total = sum(os.path.getsize(r['original']) for r in records)
    info('[OK] Read-only preflight PASSED; recovery source bytes: %.2f GiB' % (total / (1024**3)))
    return pvd, frame_dir, manifest_path, manifest, src, records


def _byte_equal(a, ap, b, bp, size):
    done = 0
    while done < size:
        n = min(CHUNK, size - done)
        if a[ap + done:ap + done + n] != b[bp + done:bp + done + n]:
            return False
        done += n
    return True


def append_missing_vtu(base_path, delta_path, stage_path, field_names):
    """Append ONLY new arrays. Existing VTU bytes and its metadata are retained."""
    of, orig = _mapping(base_path)
    nf, new = _mapping(delta_path)
    try:
        _compare_geometry(orig, new)
        op, old_p, _ = _arrays(orig, 'PointData')
        oc, old_c, _ = _arrays(orig, 'CellData')
        _, new_p, _ = _arrays(new, 'PointData')
        _, new_c, _ = _arrays(new, 'CellData')
        existing = set(old_p) | set(old_c)
        additions = set(field_names)
        ensure(not (additions & existing), 'Patch would replace existing original fields')
        ensure(additions == (set(new_p) | set(new_c)) - set(['GrainID']),
               'Unexpected or missing variables in ODB patch')
        ensure(len(additions) == len(field_names), 'Duplicate requested fields')
        # Keep the original GrainID, not the regenerated one. Optional
        # GrainID in delta is intentionally NOT copied.
        with open(stage_path, 'wb') as f:
            _copy_region(f, orig, 0, op[2])
            for name in field_names:
                if name in new_p:
                    f.write(b'\n')
                    _copy_region(f, new, *new_p[name])
            _copy_region(f, orig, op[2], oc[2])
            for name in field_names:
                if name in new_c:
                    f.write(b'\n')
                    _copy_region(f, new, *new_c[name])
            _copy_region(f, orig, oc[2], len(orig))
            f.flush()
            os.fsync(f.fileno())
    finally:
        new.close()
        nf.close()
        orig.close()
        of.close()


def verify_merged(original, restored, added_fields):
    af, aa = _mapping(original)
    bf, bb = _mapping(restored)
    try:
        _compare_geometry(aa, bb)
        _, ap, _ = _arrays(aa, 'PointData')
        _, ac, _ = _arrays(aa, 'CellData')
        _, bp, _ = _arrays(bb, 'PointData')
        _, bc, _ = _arrays(bb, 'CellData')
        ensure(set(bp) >= set(ap), 'Restored VTU has lost original PointData')
        ensure(set(bc) >= set(ac), 'Restored VTU has lost original CellData')
        ensure((set(bp) | set(bc)) == (set(ap) | set(ac) | set(added_fields)),
               'Restored VTU array name mismatch')
        ensure(b'</VTKFile>' in bb[max(0,len(bb)-4096):], 'Restored VTU incomplete')
        for an, aset, bset in (('PointData', ap, bp), ('CellData', ac, bc)):
            for name, (start, end) in aset.items():
                s, e = bset[name]
                ensure(e-s == end-start and _byte_equal(aa,start,bb,s,end-start),
                       'Existing %s array altered: %s' % (an, name))
        return len(bp) + len(bc)
    finally:
        bb.close()
        bf.close()
        aa.close()
        af.close()


def create_folder(dest, original_pvd, requested_fields):
    ensure(os.path.realpath(dest) != os.path.realpath(os.path.dirname(original_pvd)),
           'Recovery folder must differ from original PVD folder')
    original_frame_dir,_ = manifest_file_for(original_pvd)
    ensure(os.path.realpath(dest) != os.path.realpath(original_frame_dir),
           'Recovery folder must differ from original VTU folder')
    ensure(not os.path.realpath(dest).startswith(os.path.realpath(original_frame_dir)+os.sep),
           'Recovery folder cannot be inside original VTU folder')
    if not os.path.isdir(dest):
        os.makedirs(dest)
    marker = os.path.join(dest, MARKER)
    if os.path.exists(marker):
        with open(marker,'r', encoding='utf-8') as f:
            m=json.load(f)
        ensure(m.get('source_pvd') == original_pvd and m.get('tool') == 'ODB2VTUS-SAFE-RECOVERY-v0.2.1' and m.get('fields') == list(requested_fields),
               'Destination was created for another dataset')
    else:
        ensure(not os.listdir(dest), 'Target directory already exists and is not a recovery workspace')
        atomic_json(marker, dict(source_pvd=original_pvd,
                                 tool='ODB2VTUS-SAFE-RECOVERY-v0.2.1', fields=list(requested_fields),
                                 created=time.strftime('%Y-%m-%d %H:%M:%S')))


def restore(pvd, requested_fields, output_root=None):
    pvd, frame_dir, manifest_path, manifest, src, records = preflight(pvd, requested_fields, check_odb=True)
    rootdir = os.path.dirname(pvd)
    name = os.path.splitext(os.path.basename(pvd))[0]
    out_root = os.path.abspath(output_root) if output_root else os.path.join(rootdir, name + '_RECOVERED_SAFE')
    target_frame_dir = os.path.join(out_root, name + '_frames')
    out_pvd = os.path.join(out_root, os.path.basename(pvd))

    need_gib = sum(os.path.getsize(r['original']) for r in records) / 1024**3
    free_gib = shutil.disk_usage(rootdir).free / 1024**3
    ensure(free_gib > need_gib * 1.10 + 1.0,
           'Insufficient free space: %.2f GiB, recommend > %.2f GiB' %
           (free_gib, need_gib*1.10+1.0))
    info('[CHECK] Free %.2f GiB; estimated needed %.2f GiB' % (free_gib, need_gib*1.10+1.0))
    create_folder(out_root, pvd, requested_fields)
    if not os.path.isdir(target_frame_dir):
        os.makedirs(target_frame_dir)
    progress_file = os.path.join(out_root, CHECKPOINT)
    if os.path.isfile(progress_file):
        with open(progress_file,'r',encoding='utf-8') as f:
            checkpoint=json.load(f)
    else:
        checkpoint={}

    from odbAccess import openOdb
    from odb_export_vtu import export_frame, parse_bbox
    odb=openOdb(src['odb_path'], readOnly=True)
    mesh_cache=None
    try:
        for pos, r in enumerate(records, 1):
            dst=os.path.join(target_frame_dir,r['filename'])
            existing=checkpoint.get(r['key'])
            if os.path.isfile(dst) and existing is not None:
                ensure(existing.get('source_metadata') == r['old_metadata'] and
                       existing.get('output_size') == os.path.getsize(dst),
                       'Recovery checkpoint/source mismatch: '+r['filename'])
                orig_names=set().union(*vtu_arrays(r['original']))
                cnt=verify_merged(r['original'],dst,r['missing'])
                ensure(cnt==len(orig_names)+len(r['missing']), 'Recovered array count changed')
                info('[%d/%d] VERIFIED / SKIP: %s' % (pos,len(records),r['filename']))
                continue
            ensure(metadata(r['original']) == r['old_metadata'],
                   'Source VTU changed after preflight: ' + r['filename'])
            ensure(not os.path.exists(dst), 'Unrecognized target file (will not overwrite): '+dst)
            tmp_delta=os.path.join(target_frame_dir,'_WORK_DELTA.vtu')
            tmp_stage=dst+'.incomplete'
            for tp in (tmp_delta,tmp_stage):
                if os.path.isfile(tp):
                    os.remove(tp)  # Only inside marker-protected RECOVERY folder.
            info('[%d/%d] Recovering: %s / f%d' % (pos,len(records),r['step'],r['frame']))
            if not r['missing']:
                shutil.copyfile(r['original'], tmp_stage)
                result_count=verify_merged(r['original'],tmp_stage,[])
            else:
                cache_result=export_frame(
                odb,src['instance'],r['step'],r['frame'],tmp_delta,
                list(r['missing']),src.get('element_set',''),
                parse_bbox(src.get('bbox','')),mesh_cache=mesh_cache,
                derived_mises=False,initial_ipf=False,gnd_diff=False,
                gnd_slide_diff=False)
                mesh_cache=cache_result[0]
                append_missing_vtu(r['original'],tmp_delta,tmp_stage,r['missing'])
                result_count=verify_merged(r['original'],tmp_stage,r['missing'])
            prev_names=set().union(*vtu_arrays(r['original']))
            resulting_count=result_count
            ensure(resulting_count==len(prev_names)+len(r['missing']), 'Invalid restored array count')
            ensure(metadata(r['original']) == r['old_metadata'],
                   'Source VTU was modified during recovery: ' + r['filename'])
            os.replace(tmp_stage,dst)
            checkpoint[r['key']]=dict(source_metadata=r['old_metadata'],
                                     output_size=os.path.getsize(dst),
                                     array_count=resulting_count,
                                     completed=time.strftime('%Y-%m-%d %H:%M:%S'))
            atomic_json(progress_file,checkpoint)
            if os.path.isfile(tmp_delta):
                os.remove(tmp_delta)
            info('[%d/%d] VERIFIED + SAVED: %s / %d arrays' % (pos,len(records),r['filename'],resulting_count))
    finally:
        odb.close()

    ensure(len(checkpoint) == len(records), 'Not all frames have passed verification')
    ensure(all(metadata(r['original']) == r['old_metadata'] for r in records),
           'Original VTU changed during the recovery process; output was not published')
    ensure(metadata(src['odb_path'])['size'] == manifest['frames'][records[0]['key']]['source_revision']['size'],
           'ODB revision changed; output was not published')
    with open(pvd,'rb') as f:
        content=f.read()
    if os.path.exists(out_pvd):
        with open(out_pvd, 'rb') as f:
            ensure(f.read() == content, 'Existing recovered PVD differs: refusing overwrite')
        info('[INFO] Previously published recovery PVD verified (resume).')
    else:
        temp_pvd=out_pvd+'.incomplete'
        with open(temp_pvd,'wb') as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_pvd,out_pvd)
    new_manifest=copy.deepcopy(manifest)
    for key,ent in new_manifest['frames'].items():
        if not ent.get('active', True):
            continue
        if ent.get('output_spec') is None:
            ent['output_spec'] = {'native_fields': []}
        ns=set(ent['output_spec'].get('native_fields') or [])
        ns.update(requested_fields)
        ent['output_spec']['native_fields']=sorted(ns)
        ent['recovered_fields']=list(requested_fields)
    new_manifest['recovery_note']='Non-destructive copy; original PVD/VTU remain unchanged.\n'
    atomic_json(os.path.join(target_frame_dir, '_ODB2VTUS_manifest.json'),new_manifest)
    info('')
    info('SUCCESS: %d verified published frames; each input field array preserved' % len(records))
    info('Open this NEW PVD in ParaView: '+out_pvd)
    info('All original files remain untouched: '+pvd)
    return 0


def main():
    pa=argparse.ArgumentParser()
    pa.add_argument('--pvd',required=True)
    pa.add_argument('--mode',required=True,choices=['check','restore'])
    pa.add_argument('--fields',required=True,help='Comma-separated native ODB fields, e.g. U,UR,SDV27,SDV49')
    pa.add_argument('--output-root', default='', help='Optional NEW recovery folder (must be empty or tool-owned)')
    a=pa.parse_args()
    try:
        requested_fields=tuple(x.strip() for x in a.fields.split(',') if x.strip())
        ensure(requested_fields and len(set(requested_fields)) == len(requested_fields), 'Invalid/duplicate field list')
        ensure(all(re.match(r'^[A-Za-z][A-Za-z0-9_]*$', x) for x in requested_fields),
               'Only native field names consisting of letters/digits/underscores are accepted')
        if a.mode=='check':
            preflight(a.pvd,requested_fields,check_odb=True)
            info('PRECHECK COMPLETE: safe to begin restore if you wish.')
            return 0
        return restore(a.pvd,requested_fields,a.output_root or None)
    except Exception as e:
        info('[FAILED] '+str(e))
        traceback.print_exc()
        return 2


if __name__=='__main__':
    sys.exit(main())
