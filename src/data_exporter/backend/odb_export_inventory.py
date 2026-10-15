# -*- coding: utf-8 -*-
"""On-disk VTU inventory. Frame identity comes from the ODB, never list order."""
from __future__ import print_function
import hashlib
import os
import re
import xml.etree.ElementTree as ET
from odb_export_state import safe_step_name, state_key


def _is_closed_vtu(path):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            if size < 100:
                return False
            f.seek(-min(size, 4096), os.SEEK_END)
            return b"</VTKFile>" in f.read()
    except (IOError, OSError):
        return False


def _pvd_filenames(path):
    if not os.path.isfile(path):
        return set()
    try:
        root = ET.parse(path).getroot()
        if root.get("type") != "Collection":
            return set()
        return set(os.path.basename((x.get("file") or "").replace("\\", "/"))
                   for x in root.iter("DataSet"))
    except (ET.ParseError, IOError, OSError):
        return set()


def _parsed_state(name, stem, steps, odb_frame_count):
    """Parse identity from the original ODB step and _fNNNNNN suffix."""
    rx_legacy = re.compile(r"^" + re.escape(stem) + r"_(\d{6,})_(.+)_f(\d{6,})\.vtu$", re.IGNORECASE)
    rx_stable = re.compile(r"^(.+)__([a-f0-9]{8})__f(\d{6,})\.vtu$", re.IGNORECASE)
    m = rx_legacy.match(name)
    serial = int(m.group(1)) if m else None
    if m:
        slug, fi = m.group(2), int(m.group(3))
        possible = list(steps.get(slug, []))
    else:
        m = rx_stable.match(name)
        if not m:
            return None, serial
        slug, sha, fi = m.group(1), m.group(2), int(m.group(3))
        possible = [step for step in steps.get(slug, []) if
                    hashlib.sha1(step.encode('utf-8')).hexdigest()[:8].lower() == sha.lower()]
    if len(possible) != 1:
        return None, serial
    step = possible[0]
    if fi < 0 or fi >= int(odb_frame_count(step)):
        return None, serial
    return state_key(step, fi), serial


def _published_pvd_states(pvd_path, frame_dir, stem, steps, odb_frame_count):
    """Use exact PVD DataSet references; never resolve published states by guessing.

    A PVD with multiple files for the same Step/Frame is a REAL conflict and
    must still be rejected. Unreferenced on-disk historical files are *not*.
    """
    if not os.path.isfile(pvd_path):
        return None
    try:
        root = ET.parse(pvd_path).getroot()
    except (ET.ParseError, IOError, OSError) as ex:
        raise RuntimeError('Invalid existing PVD XML: %s' % ex)
    if root.get('type') != 'Collection':
        raise RuntimeError('Existing PVD is not a VTK Collection: ' + pvd_path)
    index = {}
    used = set()
    references = list(root.iter('DataSet'))
    for dataset in references:
        ref = (dataset.get('file') or '').replace('\\','/')
        if not ref:
            raise RuntimeError('PVD DataSet has an empty file reference')
        components = ref.split('/')
        if (len(components) != 2 or components[0] != stem + '_frames' or
                not components[1] or components[1] in ('.','..')):
            raise RuntimeError('Unexpected or unsafe PVD reference: ' + ref)
        name = components[1]
        if name in used:
            raise RuntimeError('PVD references the same VTU twice: ' + name)
        used.add(name)
        key, _ = _parsed_state(name, stem, steps, odb_frame_count)
        if key is None:
            raise RuntimeError('PVD file cannot be mapped to a unique ODB Step/Frame: ' + name)
        if key in index:
            raise RuntimeError('PVD itself contains multiple files for ODB Step/Frame %s: %s / %s' %
                               (key, index[key], name))
        path = os.path.join(frame_dir, name)
        if not _is_closed_vtu(path):
            raise RuntimeError('Published PVD references a missing/incomplete VTU: ' + name)
        index[key] = name
    return index


def scan_vtu_directory(frame_dir, stem, step_names, odb_frame_count, pvd_path,
                       existing_frames=None):
    """Inventory VTU files with PVD authoritative when already published.

    Returns (index, ALL names on disk, largest_serial, notices).  An existing
    nonempty PVD selects exactly its published files, regardless of how many
    valid but unreferenced older files share the same Step/Frame identity.
    """
    existing_frames = existing_frames or {}
    steps = {}
    for step in step_names:
        steps.setdefault(safe_step_name(step), []).append(step)
    names_on_disk = set()
    largest = 0
    for name in os.listdir(frame_dir):
        if not name.lower().endswith('.vtu'):
            continue
        names_on_disk.add(name)
        _, serial = _parsed_state(name, stem, steps, odb_frame_count)
        # Retain the highest serial even on a corrupt/obsolete file for safe
        # new filename allocation and avoid collisions with existing names.
        if serial is None:
            m = re.match(r'^' + re.escape(stem) + r'_(\d{6,})_', name, re.IGNORECASE)
            serial = int(m.group(1)) if m else None
        if serial is not None:
            largest = max(largest, serial)
    published = _published_pvd_states(pvd_path, frame_dir, stem, steps, odb_frame_count)
    if published:
        extras = names_on_disk - set(published.values())
        issues = []
        if extras:
            issues.append('PRESERVED UNREFERENCED VTU: %d file(s) outside published PVD; ignored for state selection and NEVER modified' % len(extras))
        return published, names_on_disk, largest, issues
    if published is not None:  # PVD exists but currently contains zero frames.
        return {}, names_on_disk, largest, []

    # No published PVD: retain the legacy discovery path but never silently
    # choose a Step/Frame if multiple candidates exist without a PVD authority.
    candidates = {}
    issues = []
    for name in names_on_disk:
        key, _ = _parsed_state(name, stem, steps, odb_frame_count)
        if key is None:
            issues.append('Cannot uniquely associate VTU with ODB Step/Frame: ' + name)
            continue
        if not _is_closed_vtu(os.path.join(frame_dir, name)):
            issues.append('Incomplete VTU is not reusable: ' + name)
            continue
        candidates.setdefault(key, []).append(name)
    found = {}
    for key, choices in candidates.items():
        if len(choices) > 1:
            issues.append('Duplicate files for one ODB Step/Frame: %s; no PVD authority, refusing to choose: %s' %
                          (key, ', '.join(sorted(choices)[:5])))
        else:
            found[key] = choices[0]
    return found, names_on_disk, largest, issues


def allocate_vtu_name(stem, step_name, frame_index, names, next_number):
    """Append a new serial to the existing v0.1 numbering convention.

    The numeric serial is an output-file ID. Abaqus frame identity is the
    final _fNNNNNN suffix coupled with the original Step name.
    """
    safe = safe_step_name(step_name)
    while True:
        next_number += 1
        name = "%s_%06d_%s_f%06d.vtu" % (
            stem, next_number, safe, int(frame_index))
        if name not in names:
            names.add(name)
            return name, next_number
