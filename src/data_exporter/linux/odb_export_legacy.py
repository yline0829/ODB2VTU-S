# -*- coding: utf-8 -*-
"""Conservatively adopt v0.1.x PVD/VTU files without renaming or rereading ODB arrays."""
from __future__ import print_function
import ast
import os
import re
import xml.etree.ElementTree as ET

from odb_export_state import make_output_spec, new_manifest, safe_step_name, state_key


def _read_legacy_signature(path):
    if not os.path.isfile(path):
        return None
    out = {}
    with open(path, 'r') as f:
        for line in f:
            if '=' in line:
                k, v = line.rstrip('\r\n').split('=', 1)
                out[k] = v
    required = ('fields', 'element_set', 'bbox', 'delta', 'ref', 'mises',
                'initial_ipf', 'inp', 'ipf_dir', 'gnd_diff', 'gnd_dat',
                'gnd_diff_mode', 'gnd_slide_diff', 'gnd_slide_ref')
    if not all(k in out for k in required):
        return None
    return out


def _as_bool(value):
    return str(value).strip() == '1'


def _signature_spec(sig):
    raw_fields = sig['fields'].strip()
    if raw_fields.startswith('['):
        try:
            fields = ast.literal_eval(raw_fields)
        except (SyntaxError, ValueError):
            return None
        if not isinstance(fields, (list, tuple)):
            return None
        fields = [str(x) for x in fields]
    else:
        # Old make_signature saved a CLI comma-separated string, not a list.
        fields = [x.strip() for x in raw_fields.split(',') if x.strip()]
    reference = sig['ref'].rsplit(':', 1)
    if len(reference) != 2:
        return None
    try:
        ref_frame = int(reference[1])
    except ValueError:
        return None
    inp = sig['inp'] if _as_bool(sig['initial_ipf']) else ''
    gnd_dat = sig['gnd_dat'] if _as_bool(sig['gnd_diff']) else ''
    spec = make_output_spec(
        fields, mises=_as_bool(sig['mises']),
        initial_ipf=_as_bool(sig['initial_ipf']),
        inp_path=inp, ipf_dir=sig['ipf_dir'],
        gnd_diff=_as_bool(sig['gnd_diff']), gnd_dat=gnd_dat,
        gnd_diff_mode=sig['gnd_diff_mode'],
        gnd_slide_diff=_as_bool(sig['gnd_slide_diff']),
        gnd_slide_ref=sig['gnd_slide_ref'],
        delta_field=sig['delta'], ref_step=reference[0],
        ref_frame=ref_frame)
    if sig['gnd_diff'] == '1':
        stamp = spec['gnd_diff']['gnd_dat']
        try:
            stamp['size'] = int(sig['gnd_dat_size'])
            stamp['mtime'] = float(sig['gnd_dat_mtime'])
        except (KeyError, ValueError):
            return None
    return spec


def _closed_vtu(path):
    """Read the small XML footer, not hundreds of MB of numerical payload."""
    try:
        with open(path, 'rb') as f:
            f.seek(0, os.SEEK_END)
            if f.tell() < 128:
                return False
            f.seek(-min(512, f.tell()), os.SEEK_END)
            return b'</VTKFile>' in f.read()
    except (IOError, OSError):
        return False


def _read_indexed_pvd_files(pvd):
    if not os.path.isfile(pvd):
        return set()
    try:
        root = ET.parse(pvd).getroot()
        if root.attrib.get('type') != 'Collection':
            return set()
        names = set()
        for ds in root.iter('DataSet'):
            name = ds.attrib.get('file') or ''
            names.add(os.path.basename(name.replace('\\', '/')))
        return names
    except (IOError, OSError, ET.ParseError):
        return set()


def adopt_legacy_frames(pvd, frame_dir, stem, source, revision, odb_step_names,
                        odb_frame_count, existing_manifest=None):
    """Return (manifest, adopted_count, reason). Preserve all old VTU filenames."""
    sig_path = os.path.join(frame_dir, '_ADE_export_signature.txt')
    sig = _read_legacy_signature(sig_path)
    if sig is None:
        return existing_manifest, 0, 'no matching legacy signature'
    if sig['element_set'] != source['element_set'] or sig['bbox'] != source['bbox']:
        return existing_manifest, 0, 'legacy region differs from current region'

    # Old signatures lacked ODB path. Enforce its conventional output stem.
    odb_stem = os.path.splitext(os.path.basename(source['odb_path']))[0]
    if not (stem == odb_stem or stem.startswith(odb_stem + '_')):
        return existing_manifest, 0, 'legacy output name cannot be matched to this ODB'
    spec = _signature_spec(sig)
    if spec is None:
        return existing_manifest, 0, 'legacy signature cannot be safely parsed'
    try:
        signature_mtime = os.path.getmtime(sig_path)
        odb_mtime = float(revision['mtime'])
    except (ValueError, KeyError, TypeError, OSError):
        return existing_manifest, 0, 'missing source/signature timestamps'

    steps_by_slug = {}
    for step in odb_step_names:
        steps_by_slug.setdefault(safe_step_name(step), []).append(step)
    rx = re.compile(r'^' + re.escape(stem) + r'_\d{6}_(.+)_f(\d{6})\.vtu$', re.IGNORECASE)
    listed = _read_indexed_pvd_files(pvd)
    candidates = []
    for fn in sorted(os.listdir(frame_dir)):
        m = rx.match(fn)
        if not m:
            continue
        matches = steps_by_slug.get(m.group(1), ())
        if len(matches) != 1:
            continue
        step = matches[0]
        fi = int(m.group(2))
        if fi < 0 or fi >= int(odb_frame_count(step)):
            continue
        path = os.path.join(frame_dir, fn)
        if not os.path.isfile(path) or not _closed_vtu(path):
            continue
        vt = os.path.getmtime(path)
        # Do not reuse a legacy VTU that predates the latest signature or ODB.
        if vt + 2.0 < signature_mtime or vt + 2.0 < odb_mtime:
            continue
        candidates.append((step, fi, fn, fn in listed))

    if not candidates:
        return existing_manifest, 0, 'no complete compatible legacy VTUs found'
    eligible_names = set(item[2] for item in candidates)
    unresolved = [name for name in listed if rx.match(name) and name not in eligible_names]
    if unresolved:
        return existing_manifest, 0, ('legacy PVD references %d unverified VTUs; '
                                     'keeping existing PVD untouched' % len(unresolved))
    manifest = existing_manifest if existing_manifest is not None else new_manifest(source)
    frames = manifest.setdefault('frames', {})
    candidates.sort(key=lambda x: (not x[3], x[2]))
    added = 0
    for step, fi, filename, indexed in candidates:
        key = state_key(step, fi)
        if key in frames:
            continue
        frames[key] = {
            'step': step, 'frame': fi, 'file': filename,
            'active': True, 'output_spec': spec,
            'source_revision': revision,
            'legacy_adopted': True,
        }
        added += 1
    return manifest, added, 'adopted %d complete legacy VTU files without renaming' % added
