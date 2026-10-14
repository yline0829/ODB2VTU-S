# -*- coding: utf-8 -*-
from __future__ import print_function

import hashlib
import json
import os
import re


MANIFEST_VERSION = 2


def file_stamp(path):
    if not path:
        return {"path": "", "size": None, "mtime": None}
    ap = os.path.abspath(path)
    out = {"path": ap, "size": None, "mtime": None}
    try:
        out["size"] = int(os.path.getsize(ap))
        out["mtime"] = float(os.path.getmtime(ap))
    except Exception:
        pass
    return out


def source_identity(odb_path, instance, element_set="", bbox=""):
    return {
        "odb_path": os.path.abspath(odb_path),
        "instance": str(instance or ""),
        "element_set": str(element_set or ""),
        "bbox": str(bbox or ""),
    }


def source_revision(odb_path):
    s = file_stamp(odb_path)
    return {"size": s.get("size"), "mtime": s.get("mtime")}


def make_output_spec(fields, mises=False, initial_ipf=False, inp_path="", ipf_dir="Z",
                     gnd_diff=False, gnd_dat="", gnd_diff_mode="slips",
                     gnd_slide_diff=False, gnd_slide_ref="sliding0",
                     delta_field="", ref_step="", ref_frame=-1):
    spec = {
        "native_fields": sorted(set(str(x) for x in (fields or []) if str(x))),
        "mises": bool(mises),
        "initial_ipf": None,
        "gnd_diff": None,
        "gnd_slide_diff": None,
        "delta": None,
    }
    if initial_ipf:
        spec["initial_ipf"] = {
            "inp": file_stamp(inp_path),
            "ipf_dir": str(ipf_dir or "Z"),
        }
    if gnd_diff:
        spec["gnd_diff"] = {
            "gnd_dat": file_stamp(gnd_dat),
            "mode": str(gnd_diff_mode or "slips"),
        }
    if gnd_slide_diff:
        spec["gnd_slide_diff"] = {
            "reference": str(gnd_slide_ref or "sliding0"),
        }
    if delta_field:
        spec["delta"] = {
            "field": str(delta_field),
            "ref_step": str(ref_step or ""),
            "ref_frame": int(ref_frame),
        }
    return spec


def normalize_output_spec(spec):
    spec = dict(spec or {})
    return {
        "native_fields": sorted(set(spec.get("native_fields") or [])),
        "mises": bool(spec.get("mises", False)),
        "initial_ipf": spec.get("initial_ipf"),
        "gnd_diff": spec.get("gnd_diff"),
        "gnd_slide_diff": spec.get("gnd_slide_diff"),
        "delta": spec.get("delta"),
    }


def merge_output_specs(old_spec, new_spec, policy):
    old_spec = old_spec or {}
    new_spec = new_spec or {}
    if str(policy).lower() == "sync":
        return normalize_output_spec(new_spec)

    out = normalize_output_spec(old_spec)
    newn = normalize_output_spec(new_spec)
    out["native_fields"] = sorted(set(out["native_fields"]) | set(newn["native_fields"]))
    if newn["mises"]:
        out["mises"] = True
    for key in ("initial_ipf", "gnd_diff", "gnd_slide_diff", "delta"):
        if newn.get(key) is not None:
            out[key] = newn[key]
    return out


def output_spec_equal(a, b):
    return normalize_output_spec(a) == normalize_output_spec(b)


def export_kwargs_from_spec(spec):
    s = normalize_output_spec(spec)
    ipf = s.get("initial_ipf") or {}
    gd = s.get("gnd_diff") or {}
    gs = s.get("gnd_slide_diff") or {}
    de = s.get("delta") or {}
    return {
        "fields": list(s["native_fields"]),
        "derived_mises": bool(s["mises"]),
        "initial_ipf": bool(s.get("initial_ipf")),
        "inp_path": (ipf.get("inp") or {}).get("path", ""),
        "ipf_dir": ipf.get("ipf_dir", "Z"),
        "gnd_diff": bool(s.get("gnd_diff")),
        "gnd_dat": (gd.get("gnd_dat") or {}).get("path", ""),
        "gnd_diff_mode": gd.get("mode", "slips"),
        "gnd_slide_diff": bool(s.get("gnd_slide_diff")),
        "gnd_slide_ref": gs.get("reference", "sliding0"),
        "delta_field": de.get("field", ""),
        "ref_step": de.get("ref_step", ""),
        "ref_frame": int(de.get("ref_frame", -1)),
    }


def state_key(step_name, frame_index):
    return "%s\t%d" % (str(step_name), int(frame_index))


def safe_step_name(step_name):
    return "".join(c if c.isalnum() or c in "_-" else "_" for c in str(step_name))


def stable_vtu_name(step_name, frame_index):
    raw = str(step_name)
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:8]
    return "%s__%s__f%06d.vtu" % (safe_step_name(raw), digest, int(frame_index))


def load_manifest(path):
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r") as f:
            data = json.load(f)
        if int(data.get("version", 0)) != MANIFEST_VERSION:
            return None
        if not isinstance(data.get("frames"), dict):
            data["frames"] = {}
        return data
    except Exception:
        return None


def new_manifest(source):
    return {
        "version": MANIFEST_VERSION,
        "source": dict(source),
        "frames": {},
    }


def atomic_write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    if os.path.exists(path):
        os.remove(path)
    os.rename(tmp, path)


def same_source_identity(manifest, source):
    return dict((manifest or {}).get("source") or {}) == dict(source or {})


def parse_vtu_field_names(path):
    if not path or not os.path.exists(path):
        return []
    rx = re.compile(r'<DataArray\b[^>]*\bName="([^"]+)"')
    names = []
    seen = set()
    with open(path, "r", errors="ignore") as f:
        for line in f:
            if "<DataArray" not in line or "Name=" not in line:
                continue
            m = rx.search(line)
            if m:
                name = m.group(1)
                if name not in seen:
                    seen.add(name)
                    names.append(name)
    return names


def atomic_replace(src, dst):
    if os.path.exists(dst):
        os.remove(dst)
    os.rename(src, dst)
