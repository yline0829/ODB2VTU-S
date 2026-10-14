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


def scan_vtu_directory(frame_dir, stem, step_names, odb_frame_count, pvd_path,
                       existing_frames=None):
    """Discover old and new filenames, but never infer frame identity from seq.

    Returns (index, names_on_disk, largest_global_number, notices).
    Key is original ODB Step name + zero-based Abaqus Frame index.
    Existing PVD references and verified manifest paths take precedence.
    """
    existing_frames = existing_frames or {}
    steps = {}
    for step in step_names:
        steps.setdefault(safe_step_name(step), []).append(step)
    indexed = _pvd_filenames(pvd_path)
    file_names = set()
    candidates = {}
    issues = []
    largest = 0

    rx_legacy = re.compile(
        r"^" + re.escape(stem) + r"_(\d{6,})_(.+)_f(\d{6,})\.vtu$",
        re.IGNORECASE)
    rx_stable = re.compile(r"^(.+)__([a-f0-9]{8})__f(\d{6,})\.vtu$",
                           re.IGNORECASE)
    for name in os.listdir(frame_dir):
        if not name.lower().endswith(".vtu"):
            continue
        file_names.add(name)
        match = rx_legacy.match(name)
        if match:
            num, slug, fi = int(match.group(1)), match.group(2), int(match.group(3))
            largest = max(largest, num)
        else:
            match = rx_stable.match(name)
            if not match:
                continue
            slug, sha, fi = match.group(1), match.group(2), int(match.group(3))
        possible = list(steps.get(slug, []))
        if match and not rx_legacy.match(name):
            possible = [step for step in possible
                        if hashlib.sha1(step.encode("utf-8")).hexdigest()[:8].lower()
                        == sha.lower()]
        if len(possible) != 1:
            issues.append("Cannot uniquely associate VTU with ODB Step: " + name)
            continue
        step = possible[0]
        if fi < 0 or fi >= int(odb_frame_count(step)):
            issues.append("VTU frame index outside current ODB: " + name)
            continue
        path = os.path.join(frame_dir, name)
        if not _is_closed_vtu(path):
            issues.append("Incomplete VTU is not reusable: " + name)
            continue
        key = state_key(step, fi)
        current = existing_frames.get(key) or {}
        priority = (0 if name == current.get("file") else
                    1 if name in indexed else
                    2 if rx_legacy.match(name) else 3)
        candidates.setdefault(key, []).append((priority, name))

    result = {}
    for key, choices in candidates.items():
        choices.sort(key=lambda p: (p[0], p[1]))
        result[key] = choices[0][1]
        if len(choices) > 1:
            issues.append("Duplicate files for one ODB Step/Frame: %s; using %s; "
                          "other files preserved" % (key, result[key]))
    return result, file_names, largest, issues


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
