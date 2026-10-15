# -*- coding: utf-8 -*-
"""Verified, read-only baseline preflight for legacy pre-manifest PVD/VTU.

No filename or field-name match alone establishes data provenance. A positive
preflight needs every PVD state to agree with an ODB-generated mesh and a
nonempty, finite, native result array (verified numerically).
"""
from __future__ import print_function
import os
import re
import mmap
import xml.etree.ElementTree as ET

from odb_export_inventory import _is_closed_vtu, scan_vtu_directory
from odb_export_state import state_key
from odb_vtu_incremental import _arrays, _compare_geometry, _mapping, _count_elements

FIELD_PREFERENCE = ('S', 'LE', 'U', 'RF', 'PEEQ', 'PEEQCP', 'SDV29', 'SDV78')


def collect_pvd_states(pvd, step_names, frame_count):
    """Return ordered (step, index, basename, disk path), or fail closed."""
    pvd = os.path.abspath(pvd)
    if not os.path.isfile(pvd) or not pvd.lower().endswith('.pvd'):
        raise RuntimeError('Legacy PVD is missing or not a .pvd file.')
    stem = os.path.splitext(os.path.basename(pvd))[0]
    frame_dir = os.path.join(os.path.dirname(pvd), stem + '_frames')
    if not os.path.isdir(frame_dir):
        raise RuntimeError('PVD companion VTU directory is absent: ' + frame_dir)
    root = ET.parse(pvd).getroot()
    if root.attrib.get('type') != 'Collection':
        raise RuntimeError('Input is not a VTK Collection PVD.')
    data = list(root.iter('DataSet'))
    if not data:
        raise RuntimeError('PVD contains no DataSet entries.')
    index, _, _, issues = scan_vtu_directory(frame_dir, stem, step_names,
                                               frame_count, pvd, {})
    if any('Cannot uniquely associate' in e for e in issues):
        # Unindexed extras do not matter; indexed files must still map below.
        pass
    lookup = {}
    for key, fn in index.items():
        if fn in lookup:
            raise RuntimeError('Multiple states refer to one indexed VTU.')
        lookup[fn] = key
    seen_files = set()
    seen_states = set()
    rows = []
    for item in data:
        ref = (item.get('file') or '').replace('\\', '/')
        parts = ref.split('/')
        if len(parts) != 2 or parts[0] != stem + '_frames' or not parts[1] or parts[1] in ('.', '..'):
            raise RuntimeError('Unsafe or unexpected legacy PVD reference: ' + ref)
        fn = parts[1]
        if fn in seen_files:
            raise RuntimeError('PVD repeats a filename: ' + fn)
        seen_files.add(fn)
        if fn not in lookup:
            raise RuntimeError('PVD file cannot be linked to one ODB Step/Frame: ' + fn)
        key = lookup[fn]
        if key in seen_states:
            raise RuntimeError('PVD repeats a Step/Frame: ' + key)
        seen_states.add(key)
        step, frame_index = key.rsplit('\t', 1)
        path = os.path.join(frame_dir, fn)
        if not os.path.isfile(path) or not _is_closed_vtu(path):
            raise RuntimeError('Missing/truncated original VTU: ' + fn)
        rows.append((step, int(frame_index), fn, path))
    return rows


def choose_witness(actual_point, actual_cell, odb_fields):
    common = (set(actual_point) | set(actual_cell)) & set(odb_fields)
    eligible = [name for name in common
                if re.match(r'^[A-Za-z][A-Za-z0-9_]*$', name)]
    if not eligible:
        raise RuntimeError('No shared native ODB field exists for numerical provenance verification.')
    return sorted(eligible, key=lambda x: ((FIELD_PREFERENCE.index(x) if x in FIELD_PREFERENCE else 99), x))[0]


def _numeric_array(mm, name, section):
    """Read one named ASCII array only, never load the whole VTU."""
    import numpy as np
    _, entries, _ = _arrays(mm, section)
    if name not in entries:
        return None
    a, b = entries[name]
    h = mm.find(b'>', a, b)
    close = mm.find(b'</DataArray>', h + 1, b)
    if h < 0 or close < 0:
        raise RuntimeError('Malformed DataArray: ' + name)
    header = mm[a:h + 1]
    if b'format="ascii"' not in header:
        raise RuntimeError('Only ASCII VTU numeric fields are supported: ' + name)
    typ = re.search(br'\btype="([^"]+)"', header)
    if typ is not None and typ.group(1) not in (b'Float64', b'Float32', b'Int32', b'Int64', b'UInt8'):
        raise RuntimeError('Unsupported numeric VTU array type: ' + name)
    comps = re.search(br'\bNumberOfComponents="(\d+)"', header)
    count = int(comps.group(1)) if comps else 1
    values = np.fromstring(mm[h + 1:close].decode('ascii'), sep=' ', dtype=np.float64)
    if not len(values) or len(values) % count:
        raise RuntimeError('Empty or invalid native VTU field: ' + name)
    return values, count


def validate_native_probe(old_vtu, probe_vtu, name, compare_values=True):
    """Validate exact mesh/field alignment; strict mode also checks native values."""
    import numpy as np
    old_f, old = _mapping(old_vtu)
    probe_f, probe = _mapping(probe_vtu)
    try:
        _compare_geometry(old, probe)
        locations = []
        for sec in ('PointData', 'CellData'):
            _, original, _ = _arrays(old, sec)
            _, generated, _ = _arrays(probe, sec)
            if name in original or name in generated:
                if name not in original or name not in generated:
                    raise RuntimeError('ODB/VTU field location differs: ' + name)
                locations.append(sec)
        if len(locations) != 1:
            raise RuntimeError('Witness missing or duplicated across point/cell data: ' + name)
        sec = locations[0]
        a, ca = _numeric_array(old, name, sec)
        b, cb = _numeric_array(probe, name, sec)
        if ca != cb or a.size != b.size:
            raise RuntimeError('Witness tuple/component count differs: ' + name)
        if not compare_values:
            # In fast mode the ODB-produced probe proves the physical point/cell
            # order and field array shape. This does NOT prove old numeric values.
            return {'witness': name, 'location': sec, 'components': ca,
                    'compared_values': 0, 'verification': 'geometry_and_shape_only',
                    'values_verified': False, 'tuples': int(a.size // ca)}
        mask = np.isfinite(a) & np.isfinite(b)
        if not np.any(mask):
            raise RuntimeError('Witness contains no comparable finite values: ' + name)
        # A single finite/NaN disagreement is a material data mismatch.
        if (not np.array_equal(np.isnan(a), np.isnan(b)) or
                not np.array_equal(np.isposinf(a), np.isposinf(b)) or
                not np.array_equal(np.isneginf(a), np.isneginf(b))):
            raise RuntimeError('Witness NaN/Inf pattern mismatch: ' + name)
        if not np.allclose(a[mask], b[mask], rtol=5e-6, atol=1e-10):
            raise RuntimeError('Witness values do not match the current ODB: ' + name)
        return {'witness': name, 'location': sec, 'components': ca,
                'compared_values': int(mask.sum()),
                'verification': 'numerical', 'values_verified': True,
                'tuples': int(a.size // ca)}
    finally:
        probe.close(); probe_f.close(); old.close(); old_f.close()


def select_representative_states(rows):
    """First state and first state of another step; otherwise final state.

    Selection is by the PVD Step identity, not incidental serial numbering.
    Returns indices, not Step/Frame keys, to prevent ambiguity.
    """
    if not rows:
        raise RuntimeError('No PVD frames are available for sampling.')
    if len(rows) == 1:
        return (0,)
    first_step = rows[0][0]
    second = next((i for i, r in enumerate(rows[1:], 1) if r[0] != first_step), len(rows) - 1)
    return (0, second)


def validate_legacy_lightweight(old_vtu, anchor_vtu):
    """Lightweight ALL-FRAME check against an ODB-verified VTU mesh.

    Does NOT compare historical numerical field values or generate an ODB
    probe. The mesh, point/cell ordering and topology are checked against
    the sampled witness; delta-merge independently checks geometry again.
    """
    af, a = _mapping(anchor_vtu)
    bf, b = _mapping(old_vtu)
    try:
        _compare_geometry(b, a)
        piece = _count_elements(b)
        match = re.findall(br'NumberOf(Points|Cells)="(\d+)"', piece)
        counts = {k.decode('ascii'): int(v) for k,v in match}
        if counts.get('Points', 0) <= 0 or counts.get('Cells', 0) <= 0:
            raise RuntimeError('Invalid mesh point/cell counts in legacy VTU.')
        _, point, _ = _arrays(b, 'PointData')
        _, cell, _ = _arrays(b, 'CellData')
        collision = set(point).intersection(cell)
        if collision:
            raise RuntimeError('Field appears in both PointData and CellData: %s' % sorted(collision))
        if not point and not cell:
            raise RuntimeError('VTU has no native or derived field arrays.')
        for section, records in [('PointData', point), ('CellData', cell)]:
            for name, (begin, end) in records.items():
                close = b.find(b'>', begin, end)
                if close < 0:
                    raise RuntimeError('Malformed DataArray header: ' + name)
                header = b[begin:close + 1]
                if b'format="ascii"' not in header:
                    raise RuntimeError('Unsupported VTU DataArray format: ' + name)
                component = re.search(br'NumberOfComponents="(\d+)"', header)
                if component and int(component.group(1)) < 1:
                    raise RuntimeError('Invalid DataArray component count: ' + name)
        return {'verification': 'geometry_and_headers_only',
                'values_verified': False, 'geometry_anchor': str(anchor_vtu),
                'points': counts['Points'], 'cells': counts['Cells'],
                'point_arrays': len(point), 'cell_arrays': len(cell)}
    finally:
        b.close(); bf.close(); a.close(); af.close()
