# -*- coding: utf-8 -*-
"""Low-memory VTU DataArray reuse for incremental Abaqus ODB exports.

Compatible with the ASCII VTK XML layout emitted by odb_export_vtu.py.
Uses memory-mapped, bounded-block copies rather than an in-memory XML DOM.
"""
from __future__ import print_function

import mmap
import os
import re

from odb_export_state import normalize_output_spec

_BLOCK_SIZE = 1024 * 1024
_NAME = re.compile(br'\bName="([^"]+)"')


def _copy_region(stream, mapping, start, end):
    while start < end:
        right = min(start + _BLOCK_SIZE, end)
        stream.write(mapping[start:right])
        start = right


def _find_section(mapping, section):
    name = section.encode("ascii")
    start = mapping.find(b"<" + name)
    if start < 0:
        raise RuntimeError("VTU missing XML section: " + section)
    open_end = mapping.find(b">", start)
    if open_end < 0:
        raise RuntimeError("VTU malformed XML section: " + section)
    closing = b"</" + name + b">"
    close_start = mapping.find(closing, open_end)
    if close_start < 0:
        raise RuntimeError("VTU missing section closing tag: " + section)
    return start, open_end + 1, close_start, close_start + len(closing)


def _arrays(mapping, section):
    start, inner_start, inner_end, end = _find_section(mapping, section)
    entries = {}
    order = []
    at = inner_start
    while True:
        i = mapping.find(b"<DataArray", at, inner_end)
        if i < 0:
            break
        h = mapping.find(b">", i, inner_end)
        if h < 0:
            raise RuntimeError("Malformed DataArray header in " + section)
        header = mapping[i:h + 1]
        m = _NAME.search(header)
        if m is None:
            raise RuntimeError("Unnamed DataArray in " + section)
        try:
            name = m.group(1).decode("utf-8")
        except UnicodeDecodeError:
            raise RuntimeError("Invalid DataArray name encoding")
        closer = mapping.find(b"</DataArray>", h + 1, inner_end)
        if closer < 0:
            raise RuntimeError("Unterminated DataArray: " + name)
        if name in entries:
            raise RuntimeError("Duplicate VTU array: " + name)
        entries[name] = (i, closer + len(b"</DataArray>"))
        order.append(name)
        at = entries[name][1]
    return (start, inner_start, inner_end, end), entries, order


def _count_elements(mapping):
    pos = mapping.find(b"<Piece")
    if pos < 0:
        raise RuntimeError("Missing VTU Piece")
    end = mapping.find(b">", pos)
    if end < 0:
        raise RuntimeError("Malformed VTU Piece")
    return mapping[pos:end + 1]


def _mapping(path):
    f = open(path, "rb")
    try:
        if os.fstat(f.fileno()).st_size == 0:
            raise RuntimeError("Empty VTU: " + path)
        mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        return f, mm
    except Exception:
        f.close()
        raise


def _numbers_in_section(mapping, section, name=None):
    """Read one geometry array by meaning, independent of ASCII formatting."""
    import numpy as np
    _, start, limit, _ = _find_section(mapping, section)
    pos = start
    while True:
        hstart = mapping.find(b'<DataArray', pos, limit)
        if hstart < 0: break
        hend = mapping.find(b'>', hstart, limit)
        if hend < 0: raise RuntimeError('Unterminated geometry array header in ' + section)
        header = mapping[hstart:hend + 1]
        close = mapping.find(b'</DataArray>', hend + 1, limit)
        if close < 0: raise RuntimeError('Unterminated geometry array in ' + section)
        m = _NAME.search(header)
        found = m.group(1).decode('utf-8') if m else None
        if name is None or name == found:
            if b'format="ascii"' not in header:
                raise RuntimeError('Legacy geometry uses unsupported VTU encoding')
            values = np.fromstring(mapping[hend + 1:close], dtype=np.float64, sep=' ')
            if values.size == 0: raise RuntimeError('Empty geometry array: ' + section)
            return values
        pos = close + len(b'</DataArray>')
    raise RuntimeError('Missing geometry array %s in %s' % (name, section))


def _semantic_geometry_compatible(old, delta):
    """Require numerically identical point ordering and exact cell topology."""
    import numpy as np
    def piece_counts(mm):
        header = _count_elements(mm)
        out = []
        for key in (b'NumberOfPoints', b'NumberOfCells'):
            m = re.search(key + br'="(\d+)"', header)
            if not m: raise RuntimeError('Missing Piece geometry count')
            out.append(int(m.group(1)))
        return out
    ca, cb = piece_counts(old), piece_counts(delta)
    if ca != cb: raise RuntimeError('VTU Piece point/cell counts differ')
    a = _numbers_in_section(old, 'Points')
    b = _numbers_in_section(delta, 'Points')
    if len(a) != len(b) or len(a) != ca[0] * 3:
        raise RuntimeError('VTU point coordinate count differs')
    if not np.allclose(a, b, rtol=1e-11, atol=1e-9, equal_nan=False):
        raise RuntimeError('VTU geometry point coordinates differ')
    for key in ('connectivity', 'offsets', 'types'):
        a = _numbers_in_section(old, 'Cells', key)
        b = _numbers_in_section(delta, 'Cells', key)
        if a.size != b.size or not np.array_equal(a, b):
            raise RuntimeError('VTU cell %s differs' % key)


def _compare_geometry(old, delta):
    """Fast byte comparison, otherwise semantic geometry verification."""
    old_start = _find_section(old, 'PointData')[0]
    new_start = _find_section(delta, 'PointData')[0]
    if old_start == new_start and _count_elements(old) == _count_elements(delta):
        identical = True
        i = 0
        while i < old_start:
            j = min(i + _BLOCK_SIZE, old_start)
            if old[i:j] != delta[i:j]:
                identical = False
                break
            i = j
        if identical: return
    _semantic_geometry_compatible(old, delta)


def vtu_arrays(path):
    """Discover named point/cell fields without reading full numeric arrays."""
    f, mm = _mapping(path)
    try:
        _, points, _ = _arrays(mm, "PointData")
        _, cells, _ = _arrays(mm, "CellData")
        return set(points), set(cells)
    finally:
        mm.close()
        f.close()


# Linux-only extension (v1.0.0): labels of the nine Burgers-direction
# increments. Must stay identical to GND_DIR_LABELS in odb_export_vtu.py.
GND_DIR_LABELS = (
    "11m20", "1m210", "2m1m10", "m2113", "m1m123",
    "1m213", "2m1m13", "11m23", "m12m13"
)


def expected_derived(spec):
    s = normalize_output_spec(spec)
    groups = {}
    if s["mises"]:
        groups["mises"] = set(["Mises"])
    if s["initial_ipf"] is not None:
        groups["initial_ipf"] = set([
            "Initial_IPF_RGB", "Initial_Euler_deg", "Initial_IPF_CrystalDir"])
    if s["gnd_diff"] is not None:
        gmode = str((s["gnd_diff"] or {}).get("mode", "slips") or "slips").lower()
        fields = set(["GND_Initial_Total", "GND_Current_Total",
                      "DGND_Total", "GND_DAT_Mask"])
        if gmode in ("slips", "all"):
            fields.update("DGND_Slip%02d_SDV%d" % (n, n + 10)
                          for n in range(1, 19))
        # Linux-only extension: nine Burgers-direction increments.
        if gmode in ("directions", "all"):
            fields.update("DGND_Dir%02d_%s" % (j + 1, lab)
                          for j, lab in enumerate(GND_DIR_LABELS))
        groups["gnd_diff"] = fields
    if s["gnd_slide_diff"] is not None:
        fields = set(["GND_SlideRef_Total", "GND_Current_Total",
                      "DGND_Slide_Total"])
        fields.update("DGND_Slide_Slip%02d_SDV%d" % (n, n + 10)
                      for n in range(1, 19))
        groups["gnd_slide_diff"] = fields
    if s["delta"] is not None:
        groups["delta"] = set(["DELTA_" + s["delta"]["field"]])
    return groups


def patch_spec(old_spec, final_spec, present_arrays, preserve_existing=False):
    """Return (patch_spec, final_array_names, has_work).

    Patch only newly requested or missing raw fields and altered derived groups.
    Unchanged derived groups are copied from the old VTU instead of recomputed.
    """
    old = normalize_output_spec(old_spec)
    final = normalize_output_spec(final_spec)
    selected = set(final["native_fields"])
    need_native = sorted(selected - set(old["native_fields"]) |
                         (selected - set(present_arrays)))
    patch = normalize_output_spec(None)
    patch["native_fields"] = need_native

    derived = expected_derived(final)
    for key, names in derived.items():
        if old.get(key) != final.get(key) or not names.issubset(present_arrays):
            patch[key] = final[key]
    keep = selected | set(["GrainID"])
    # Field Merge is non-destructive even when legacy/manifest field metadata
    # is incomplete. The *actual* old VTU arrays are authoritative.
    if preserve_existing:
        keep.update(present_arrays)
    for names in derived.values():
        keep.update(names)
    has_work = bool(need_native) or any(
        patch.get(k) is not None and (k != "mises" or patch["mises"])
        for k in ("initial_ipf", "gnd_diff", "gnd_slide_diff", "delta")
    ) or patch["mises"]
    return patch, keep, has_work


def merge_vtu(old_path, delta_path, output_path, keep_names):
    """Preserve the old mesh and old array bytes; add/replace selected arrays.

    `delta_path` can be None when the operation only removes old arrays.
    Only temporary output_path may be used: never overwrite old_path in place.
    """
    old_f, old = _mapping(old_path)
    new_f = new = None
    try:
        if delta_path is not None:
            new_f, new = _mapping(delta_path)
            _compare_geometry(old, new)
        op, op_arrays, op_order = _arrays(old, "PointData")
        oc, oc_arrays, oc_order = _arrays(old, "CellData")
        np_arrays, np_order = {}, []
        nc_arrays, nc_order = {}, []
        if new is not None:
            _, np_arrays, np_order = _arrays(new, "PointData")
            _, nc_arrays, nc_order = _arrays(new, "CellData")

        # Do not silently move an array between point- and cell-axes.
        if set(op_arrays).intersection(nc_arrays) or set(oc_arrays).intersection(np_arrays):
            raise RuntimeError("PointData/CellData location mismatch in VTU patch")

        keep = set(keep_names)
        replacements = set(np_arrays) | set(nc_arrays)
        if not replacements.issubset(keep):
            raise RuntimeError("Incremental patch contains unexpected arrays: %s" %
                               sorted(replacements - keep))

        with open(output_path, "wb") as f:
            # Original geometry and its metadata are retained byte-for-byte.
            _copy_region(f, old, 0, op[1])
            for name in op_order + [n for n in np_order if n not in op_arrays]:
                if name not in keep:
                    continue
                if name in np_arrays:
                    _copy_region(f, new, *np_arrays[name])
                else:
                    _copy_region(f, old, *op_arrays[name])
                f.write(b"\n")
            _copy_region(f, old, op[2], oc[0])
            # Keep the active Scalars attribute consistent when IPF is
            # introduced or removed via Field Merge/Sync.
            cell_header = old[oc[0]:oc[1]]
            cell_header = re.sub(br'\s+Scalars="[^"]*"', b"", cell_header)
            if "Initial_IPF_RGB" in keep:
                cell_header = cell_header.replace(
                    b">", b' Scalars="Initial_IPF_RGB">', 1)
            f.write(cell_header)
            for name in oc_order + [n for n in nc_order if n not in oc_arrays]:
                if name not in keep:
                    continue
                if name in nc_arrays:
                    _copy_region(f, new, *nc_arrays[name])
                else:
                    _copy_region(f, old, *oc_arrays[name])
                f.write(b"\n")
            _copy_region(f, old, oc[2], len(old))
        if os.path.getsize(output_path) <= 0:
            raise RuntimeError("Incremental merge produced empty VTU")
    finally:
        if new is not None:
            new.close()
        if new_f is not None:
            new_f.close()
        old.close()
        old_f.close()
