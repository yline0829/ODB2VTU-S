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


def _compare_geometry(old, delta):
    """Assert point coordinates, cell connectivity, offsets and types match.

    The exporter emits identical geometry for an unchanged ODB/instance/region.
    Exact comparison is intentional: any mismatch forces a safe full export.
    """
    old_point_start = _find_section(old, "PointData")[0]
    new_point_start = _find_section(delta, "PointData")[0]
    if _count_elements(old) != _count_elements(delta):
        raise RuntimeError("VTU geometry Piece counts differ")
    if old_point_start != new_point_start:
        raise RuntimeError("VTU geometry block sizes differ")
    i = 0
    while i < old_point_start:
        j = min(i + _BLOCK_SIZE, old_point_start)
        if old[i:j] != delta[i:j]:
            raise RuntimeError("VTU points/cells differ; cannot reuse old arrays")
        i = j


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


def expected_derived(spec):
    s = normalize_output_spec(spec)
    groups = {}
    if s["mises"]:
        groups["mises"] = set(["Mises"])
    if s["initial_ipf"] is not None:
        groups["initial_ipf"] = set([
            "Initial_IPF_RGB", "Initial_Euler_deg", "Initial_IPF_CrystalDir"])
    if s["gnd_diff"] is not None:
        fields = set(["GND_Initial_Total", "GND_Current_Total",
                      "DGND_Total", "GND_DAT_Mask"])
        fields.update("DGND_Slip%02d_SDV%d" % (n, n + 10)
                      for n in range(1, 19))
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


def patch_spec(old_spec, final_spec, present_arrays):
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
