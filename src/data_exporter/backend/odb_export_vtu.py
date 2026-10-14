# -*- coding: utf-8 -*-
from __future__ import print_function
import os, sys, argparse, traceback, math, re
from collections import defaultdict
from odbAccess import openOdb
from odb_export_state import (
    atomic_replace, atomic_write_json, export_kwargs_from_spec,
    load_manifest, make_output_spec, merge_output_specs, new_manifest,
    output_spec_equal, same_source_identity, source_identity, source_revision,
    state_key
)

VTK_CELL_TYPES = {
    4: 10,   # tetra
    5: 14,   # pyramid
    6: 13,   # wedge
    8: 12,   # hexa
    10: 24,  # quadratic tetra
    15: 26,  # quadratic wedge
    20: 25,  # quadratic hexa
}


def parse_bbox(s):
    if not s:
        return None
    vals = [float(x.strip()) for x in s.split(",")]
    if len(vals) != 6:
        raise ValueError("bbox must be xmin,xmax,ymin,ymax,zmin,zmax")
    return vals


def centroid(elem, node_map):
    pts = [node_map[n].coordinates for n in elem.connectivity]
    nn = float(len(pts))
    return (
        sum(p[0] for p in pts) / nn,
        sum(p[1] for p in pts) / nn,
        sum(p[2] for p in pts) / nn
    )


def inside(c, bbox):
    if bbox is None:
        return True
    x,y,z = c
    xmin,xmax,ymin,ymax,zmin,zmax = bbox
    return xmin <= x <= xmax and ymin <= y <= ymax and zmin <= z <= zmax


def grain_id_from_name(name, fallback):
    s = str(name).upper()
    m = re.match(r'^GRAIN[_-]?(\d+)(?:[_-]?SET)?$', s)
    if m:
        return int(m.group(1))
    m = re.search(r'GRAIN[_-]?(\d+).*$', s)
    return int(m.group(1)) if m else int(fallback)


def is_grain_set_name(name):
    s = str(name).upper()
    return (
        re.match(r'^GRAIN[_-]?\d+(?:[_-]?SET)?$', s) is not None
        or (s.startswith("GRAIN") and s.endswith("_SET"))
    )


def selected_elements(inst, element_set_name, bbox):
    node_map = dict((n.label, n) for n in inst.nodes)
    grain_ids = {}

    if element_set_name == "__ALL_GRAINS__":
        grain_names = sorted([
            name for name in inst.elementSets.keys()
            if is_grain_set_name(name)
        ])
        if not grain_names:
            raise RuntimeError("No grain element sets found in selected instance.")

        print("Recognized grain sets: %d" % len(grain_names))
        elem_by_label = {}
        for i, gname in enumerate(grain_names, 1):
            gid = grain_id_from_name(gname, i)
            for e in inst.elementSets[gname].elements:
                elem_by_label[int(e.label)] = e
                grain_ids[int(e.label)] = gid
        elems = [elem_by_label[k] for k in sorted(elem_by_label.keys())]
        print("Elements carrying GrainID: %d" % len(grain_ids))

    elif element_set_name:
        if element_set_name not in inst.elementSets:
            raise RuntimeError("Element set not found: %s" % element_set_name)
        elems = list(inst.elementSets[element_set_name].elements)

    else:
        elems = list(inst.elements)

    if bbox is not None:
        elems = [e for e in elems if inside(centroid(e, node_map), bbox)]

    if grain_ids:
        keep = set(int(e.label) for e in elems)
        grain_ids = dict((k,v) for k,v in grain_ids.items() if k in keep)

    return elems, node_map, grain_ids


def normalize_data(data):
    try:
        return [float(data)]
    except Exception:
        pass
    try:
        return [float(x) for x in data]
    except Exception:
        return None


def average_rows(rows, ncomp):
    if not rows:
        return [float("nan")] * ncomp
    out = [0.0] * ncomp
    for r in rows:
        for j in range(ncomp):
            out[j] += r[j]
    den = float(len(rows))
    return [x/den for x in out]


def extract_field(frame, field_name, inst, elem_labels, node_labels):
    if field_name not in frame.fieldOutputs:
        return None

    fld = frame.fieldOutputs[field_name].getSubset(region=inst)
    point_acc = defaultdict(list)
    cell_acc = defaultdict(list)
    ncomp = None

    for v in fld.values:
        arr = normalize_data(v.data)
        if arr is None:
            continue
        if ncomp is None:
            ncomp = len(arr)

        nlab = getattr(v, "nodeLabel", None)
        elab = getattr(v, "elementLabel", None)

        if nlab is not None and int(nlab) in node_labels:
            point_acc[int(nlab)].append(arr)
        elif elab is not None and int(elab) in elem_labels:
            cell_acc[int(elab)].append(arr)

    if ncomp is None:
        return None

    if point_acc:
        vals = {}
        for lab in node_labels:
            vals[int(lab)] = average_rows(point_acc.get(int(lab), []), ncomp)
        return ("point", ncomp, vals)

    vals = {}
    for lab in elem_labels:
        vals[int(lab)] = average_rows(cell_acc.get(int(lab), []), ncomp)
    return ("cell", ncomp, vals)


def mises_from_components(arr):
    if arr is None or len(arr) < 6:
        return float("nan")
    s11,s22,s33,s12,s13,s23 = [float(x) for x in arr[:6]]
    q = 0.5*((s11-s22)**2 + (s22-s33)**2 + (s33-s11)**2)
    q += 3.0*(s12*s12 + s13*s13 + s23*s23)
    return math.sqrt(max(q, 0.0))


def extract_mises(frame, inst, elem_labels):
    if "S" not in frame.fieldOutputs:
        return None
    fld = frame.fieldOutputs["S"].getSubset(region=inst)
    acc = defaultdict(list)
    for v in fld.values:
        elab = getattr(v, "elementLabel", None)
        if elab is None or int(elab) not in elem_labels:
            continue
        vm = None
        try:
            vm = float(v.mises)
            if not math.isfinite(vm):
                vm = None
        except Exception:
            vm = None
        if vm is None:
            vm = mises_from_components(normalize_data(v.data))
        if math.isfinite(vm):
            acc[int(elab)].append([vm])

    vals = {}
    for lab in elem_labels:
        vals[int(lab)] = average_rows(acc.get(int(lab), []), 1)
    return ("cell", 1, vals)


# -----------------------------------------------------------------------------
# Initial HCP IPF from INP material Euler angles (PROPS 1:3).
# -----------------------------------------------------------------------------
def keyword_params(line):
    out = {}
    for part in str(line).strip().split(",")[1:]:
        p = part.strip()
        if not p:
            continue
        if "=" in p:
            k,v = p.split("=",1)
            out[k.strip().upper()] = v.strip().strip('"').strip("'")
        else:
            out[p.upper()] = True
    return out


def iter_inp_lines(path, seen=None):
    if seen is None:
        seen = set()
    ap = os.path.abspath(path)
    if ap in seen:
        return
    seen.add(ap)
    base = os.path.dirname(ap)
    with open(ap, "r", errors="ignore") as f:
        for raw in f:
            s = raw.strip()
            if s.upper().startswith("*INCLUDE"):
                prm = keyword_params(s)
                inc = prm.get("INPUT", prm.get("FILE", ""))
                if inc:
                    ip = inc if os.path.isabs(inc) else os.path.join(base, inc)
                    if os.path.exists(ip):
                        for x in iter_inp_lines(ip, seen):
                            yield x
                        continue
            yield raw


def parse_number_tokens(line):
    out = []
    for p in str(line).replace("\t", ",").split(","):
        s = p.strip()
        if not s:
            continue
        try:
            out.append(float(s.replace("D","E").replace("d","e")))
        except Exception:
            pass
    return out


def parse_inp_initial_orientations(inp_path):
    if not inp_path or not os.path.exists(inp_path):
        raise RuntimeError("INP file not found: %s" % inp_path)

    section_to_material = {}
    material_euler = {}
    current_material = None
    collecting = False
    constants_needed = 0
    values = []

    def finish_material_values():
        if current_material and len(values) >= 3:
            material_euler[current_material] = (float(values[0]), float(values[1]), float(values[2]))

    for raw in iter_inp_lines(inp_path):
        s = raw.strip()
        if not s or s.startswith("**"):
            continue

        if s.startswith("*"):
            if collecting:
                finish_material_values()
                collecting = False
                values = []
                constants_needed = 0

            u = s.upper()
            prm = keyword_params(s)
            if u.startswith("*MATERIAL"):
                current_material = str(prm.get("NAME", "")).upper()
            elif u.startswith("*SOLID SECTION"):
                es = str(prm.get("ELSET", "")).upper()
                ma = str(prm.get("MATERIAL", "")).upper()
                if es and ma:
                    section_to_material[es] = ma
            elif u.startswith("*USER MATERIAL") and current_material:
                try:
                    constants_needed = int(float(prm.get("CONSTANTS", 0)))
                except Exception:
                    constants_needed = 0
                collecting = True
                values = []
            continue

        if collecting:
            values.extend(parse_number_tokens(s))
            if constants_needed > 0 and len(values) >= constants_needed:
                finish_material_values()
                collecting = False
                values = []
                constants_needed = 0

    if collecting:
        finish_material_values()

    print("INP grain sections mapped to materials: %d" % len(section_to_material))
    print("INP materials with Euler angles: %d" % len(material_euler))
    return section_to_material, material_euler


def bunge_matrix(phi1_deg, Phi_deg, phi2_deg):
    p1 = math.radians(float(phi1_deg))
    P = math.radians(float(Phi_deg))
    p2 = math.radians(float(phi2_deg))
    c1,s1 = math.cos(p1), math.sin(p1)
    c,s = math.cos(P), math.sin(P)
    c2,s2 = math.cos(p2), math.sin(p2)
    return (
        ( c1*c2 - s1*s2*c,  s1*c2 + c1*s2*c, s2*s),
        (-c1*s2 - s1*c2*c, -s1*s2 + c1*c2*c, c2*s),
        ( s1*s,               -c1*s,            c)
    )


def matvec(A, v):
    return (
        A[0][0]*v[0] + A[0][1]*v[1] + A[0][2]*v[2],
        A[1][0]*v[0] + A[1][1]*v[1] + A[1][2]*v[2],
        A[2][0]*v[0] + A[2][1]*v[1] + A[2][2]*v[2]
    )


def norm3(v):
    n = math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
    if n <= 0.0:
        return (0.0,0.0,1.0)
    return (v[0]/n, v[1]/n, v[2]/n)


def hcp_ipf_rgb(euler_deg, sample_dir="Z"):
    # The UMAT uses the standard Bunge matrix g that maps sample directions
    # into crystal coordinates.  Reduce the crystal direction by 6/mmm
    # direction symmetry to 0<=azimuth<=30 deg and z>=0.
    d = {"X":(1.0,0.0,0.0), "Y":(0.0,1.0,0.0), "Z":(0.0,0.0,1.0)}.get(str(sample_dir).upper(), (0.0,0.0,1.0))
    g = bunge_matrix(euler_deg[0], euler_deg[1], euler_deg[2])
    dc = norm3(matvec(g, d))
    x,y,z = dc
    if z < 0.0:
        x,y,z = -x,-y,-z
    azi = math.degrees(math.atan2(y,x)) % 60.0
    if azi > 30.0:
        azi = 60.0 - azi
    polar = math.atan2(math.sqrt(x*x+y*y), max(z,0.0))
    t = min(1.0, max(0.0, math.tan(0.5*polar)))
    a = min(1.0, max(0.0, azi/30.0))

    # HCP IPF key used by this exporter:
    # <0001> = red, basal 0 deg = green, basal 30 deg = blue.
    r = max(0.0, 1.0-t)
    gcol = max(0.0, t*(1.0-a))
    b = max(0.0, t*a)
    # Brighten/interpolate while keeping the three vertices pure.
    r,gcol,b = math.sqrt(r), math.sqrt(gcol), math.sqrt(b)
    mx = max(r,gcol,b,1.0e-30)
    r,gcol,b = r/mx, gcol/mx, b/mx
    rgb = [int(round(255.0*max(0.0,min(1.0,q)))) for q in (r,gcol,b)]
    return rgb, [float(dc[0]),float(dc[1]),float(dc[2])]


def build_initial_ipf_arrays(inp_path, inst, elem_labels, ipf_dir="Z"):
    section_to_material, material_euler = parse_inp_initial_orientations(inp_path)
    rgb_vals = {}
    euler_vals = {}
    dir_vals = {}
    mapped_sets = 0
    mapped_elements = 0

    for i, gname in enumerate(sorted(inst.elementSets.keys()), 1):
        if not is_grain_set_name(gname):
            continue
        gu = str(gname).upper()
        gid = grain_id_from_name(gname, i)
        mat = section_to_material.get(gu, "")
        if not mat:
            fallback = "GRAIN_MAT%d" % int(gid)
            if fallback in material_euler:
                mat = fallback
        eul = material_euler.get(mat)
        if eul is None:
            continue
        rgb, cdir = hcp_ipf_rgb(eul, ipf_dir)
        hit = False
        for e in inst.elementSets[gname].elements:
            lab = int(e.label)
            if lab not in elem_labels:
                continue
            rgb_vals[lab] = list(rgb)
            euler_vals[lab] = [float(eul[0]),float(eul[1]),float(eul[2])]
            dir_vals[lab] = list(cdir)
            mapped_elements += 1
            hit = True
        if hit:
            mapped_sets += 1

    print("Initial IPF mapped grain sets: %d" % mapped_sets)
    print("Initial IPF mapped elements: %d" % mapped_elements)
    if mapped_elements == 0:
        raise RuntimeError(
            "Initial IPF mapping produced zero elements. Check the INP file, grain set names, and material mapping."
        )

    nan3 = [float("nan")]*3
    for lab in elem_labels:
        rgb_vals.setdefault(int(lab), [0,0,0])
        euler_vals.setdefault(int(lab), list(nan3))
        dir_vals.setdefault(int(lab), list(nan3))

    return {
        "Initial_IPF_RGB": ("cell", 3, rgb_vals, "UInt8"),
        "Initial_Euler_deg": ("cell", 3, euler_vals, "Float64"),
        "Initial_IPF_CrystalDir": ("cell", 3, dir_vals, "Float64")
    }



# -----------------------------------------------------------------------------
# GND evolution from external gnd_field.dat versus current SDV11..SDV28.
# The mapping mirrors get_initial_rho_from_gnd() in the user's UMAT exactly.
# DAT columns 2..10 are nine Burgers-direction densities. Each direction is
# divided equally between the two slip systems that share that Burgers vector.
# -----------------------------------------------------------------------------
GND_DIR_SLIP_PAIRS = (
    (3, 6),   # DAT col 2:  [11-20]   -> SDV13 / SDV16
    (1, 5),   # DAT col 3:  [1-210]   -> SDV11 / SDV15
    (2, 4),   # DAT col 4:  [2-1-10]  -> SDV12 / SDV14
    (7, 17),  # DAT col 5:  [-2113]   -> SDV17 / SDV27
    (8, 10),  # DAT col 6:  [-1-123]  -> SDV18 / SDV20
    (9, 11),  # DAT col 7:  [1-213]   -> SDV19 / SDV21
    (12, 14), # DAT col 8:  [2-1-13]  -> SDV22 / SDV24
    (13, 15), # DAT col 9:  [11-23]   -> SDV23 / SDV25
    (16, 18), # DAT col 10: [-12-13]  -> SDV26 / SDV28
)
GND_DIR_LABELS = (
    "11m20", "1m210", "2m1m10", "m2113", "m1m123",
    "1m213", "2m1m13", "11m23", "m12m13"
)


def load_gnd_dat(path):
    if not path or not os.path.exists(path):
        raise RuntimeError("gnd_field.dat not found: %s" % path)
    db = {}
    with open(path, "r") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("**"):
                continue
            parts = line.replace(",", " ").split()
            if len(parts) < 10:
                raise RuntimeError("Invalid gnd_field.dat row %d: expected element label + 9 values." % lineno)
            try:
                elab = int(float(parts[0]))
                rho = tuple(float(x.replace("D","E").replace("d","e")) for x in parts[1:10])
            except Exception:
                raise RuntimeError("Invalid numeric data in gnd_field.dat row %d." % lineno)
            if elab in db:
                raise RuntimeError("Duplicate element label %d in gnd_field.dat." % elab)
            if any((not math.isfinite(x)) or x <= 0.0 for x in rho):
                raise RuntimeError("Non-positive/non-finite GND value at element %d (row %d)." % (elab, lineno))
            db[elab] = rho
    if not db:
        raise RuntimeError("gnd_field.dat is empty.")
    print("GND DAT records loaded: %d" % len(db))
    return db


def gnd_initial_slips(rho_dir):
    vals = [float("nan")] * 18
    for j, pair in enumerate(GND_DIR_SLIP_PAIRS):
        half = 0.5 * float(rho_dir[j])
        vals[pair[0]-1] = half
        vals[pair[1]-1] = half
    return vals


def extract_gnd_difference_arrays(frame, inst, elem_labels, dat_db, mode, existing_arrays=None):
    mode = str(mode or "slips").lower()
    if mode not in ("slips",):
        raise RuntimeError("Unknown GND difference mode: %s (only 'slips' is supported in this build)" % mode)

    current = []
    for slip in range(1, 19):
        fname = "SDV%d" % (10 + slip)
        arr = None
        if existing_arrays is not None and fname in existing_arrays:
            cand = existing_arrays[fname]
            if cand[0] == "cell" and cand[1] == 1:
                arr = cand
        if arr is None:
            arr = extract_field(frame, fname, inst, elem_labels, set())
        if arr is None or arr[0] != "cell" or arr[1] != 1:
            raise RuntimeError("GND difference requires %s in the selected frame." % fname)
        current.append(arr[2])

    init_total = {}
    curr_total = {}
    delta_total = {}
    dir_delta = [dict() for _ in range(9)] if mode in ("directions", "all") else []
    slip_delta = [dict() for _ in range(18)]
    coverage = {}
    missing = 0

    for lab in elem_labels:
        lab = int(lab)
        rho_dir = dat_db.get(lab)
        if rho_dir is None:
            missing += 1
            coverage[lab] = [0.0]
            init_total[lab] = [float("nan")]
            curr_total[lab] = [float("nan")]
            delta_total[lab] = [float("nan")]
            for d in dir_delta: d[lab] = [float("nan")]
            for d in slip_delta: d[lab] = [float("nan")]
            continue

        coverage[lab] = [1.0]
        ini = gnd_initial_slips(rho_dir)
        cur = []
        for slip in range(18):
            try:
                v = float(current[slip].get(lab, [float("nan")])[0])
            except Exception:
                v = float("nan")
            cur.append(v)

        if any(not math.isfinite(v) for v in cur):
            init_total[lab] = [sum(float(x) for x in rho_dir)]
            curr_total[lab] = [float("nan")]
            delta_total[lab] = [float("nan")]
        else:
            it = sum(float(x) for x in rho_dir)
            ct = sum(cur)
            init_total[lab] = [it]
            curr_total[lab] = [ct]
            delta_total[lab] = [ct - it]

        if dir_delta:
            for j, pair in enumerate(GND_DIR_SLIP_PAIRS):
                a,b = pair[0]-1, pair[1]-1
                if math.isfinite(cur[a]) and math.isfinite(cur[b]):
                    dir_delta[j][lab] = [cur[a] + cur[b] - float(rho_dir[j])]
                else:
                    dir_delta[j][lab] = [float("nan")]

        for slip in range(18):
            slip_delta[slip][lab] = [cur[slip] - ini[slip]] if math.isfinite(cur[slip]) else [float("nan")]

    if missing:
        print("WARNING: selected elements missing from gnd_field.dat: %d" % missing)
        print("         Their GND-difference fields are written as NaN.")

    arrays = {
        "GND_Initial_Total": ("cell", 1, init_total),
        "GND_Current_Total": ("cell", 1, curr_total),
        "DGND_Total": ("cell", 1, delta_total),
        "GND_DAT_Mask": ("cell", 1, coverage),
    }
    if mode in ("directions", "all"):
        for j in range(9):
            arrays["DGND_Dir%02d_%s" % (j+1, GND_DIR_LABELS[j])] = ("cell", 1, dir_delta[j])
    if mode in ("slips", "all"):
        for slip in range(18):
            arrays["DGND_Slip%02d_SDV%d" % (slip+1, 11+slip)] = ("cell", 1, slip_delta[slip])
    return arrays


def _gnd_slip_state(frame, inst, elem_labels, existing_arrays=None):
    """Return 18 element-scalar GND states corresponding to SDV11..SDV28."""
    current = []
    for slip in range(1, 19):
        fname = "SDV%d" % (10 + slip)
        arr = None
        if existing_arrays is not None and fname in existing_arrays:
            cand = existing_arrays[fname]
            if cand[0] == "cell" and cand[1] == 1:
                arr = cand
        if arr is None:
            arr = extract_field(frame, fname, inst, elem_labels, set())
        if arr is None or arr[0] != "cell" or arr[1] != 1:
            raise RuntimeError("Sliding-start GND difference requires %s in the selected/reference frame." % fname)
        current.append(arr[2])
    return current


def resolve_gnd_slide_reference(odb, reference_mode):
    """Resolve the fixed baseline used for sliding-stage GND increments."""
    mode = str(reference_mode or "sliding0").lower()
    step_names = list(odb.steps.keys())
    slide_index = None
    for i, name in enumerate(step_names):
        up = str(name).upper()
        if "SLID" in up:
            slide_index = i
            break
    if slide_index is None:
        raise RuntimeError("Cannot find a sliding Step automatically (expected a Step name containing 'Slid').")

    slide_name = step_names[slide_index]
    if mode == "sliding0":
        if len(odb.steps[slide_name].frames) < 1:
            raise RuntimeError("First sliding Step has no frames: %s" % slide_name)
        return slide_name, 0
    if mode == "previous_last":
        if slide_index <= 0:
            raise RuntimeError("No Step exists before the first sliding Step.")
        prev_name = step_names[slide_index - 1]
        prev = odb.steps[prev_name]
        if len(prev.frames) < 1:
            raise RuntimeError("Step before sliding has no frames: %s" % prev_name)
        return prev_name, len(prev.frames) - 1
    raise RuntimeError("Unknown sliding GND reference mode: %s" % reference_mode)


def build_gnd_slide_reference_cache(odb, inst, elem_labels, reference_mode):
    ref_step, ref_frame = resolve_gnd_slide_reference(odb, reference_mode)
    frame = odb.steps[ref_step].frames[ref_frame]
    slips = _gnd_slip_state(frame, inst, elem_labels, None)
    print("Sliding-start GND reference: %s / frame %d" % (ref_step, ref_frame))
    return {"step": ref_step, "frame": ref_frame, "slips": slips}


def extract_gnd_slide_difference_arrays(frame, inst, elem_labels, ref_cache, existing_arrays=None):
    current = _gnd_slip_state(frame, inst, elem_labels, existing_arrays)
    reference = ref_cache["slips"]

    ref_total = {}
    curr_total = {}
    delta_total = {}
    slip_delta = [dict() for _ in range(18)]

    for lab in elem_labels:
        lab = int(lab)
        cur_vals = []
        ref_vals = []
        for slip in range(18):
            try:
                cv = float(current[slip].get(lab, [float("nan")])[0])
            except Exception:
                cv = float("nan")
            try:
                rv = float(reference[slip].get(lab, [float("nan")])[0])
            except Exception:
                rv = float("nan")
            cur_vals.append(cv)
            ref_vals.append(rv)
            if math.isfinite(cv) and math.isfinite(rv):
                slip_delta[slip][lab] = [cv - rv]
            else:
                slip_delta[slip][lab] = [float("nan")]

        if all(math.isfinite(v) for v in cur_vals) and all(math.isfinite(v) for v in ref_vals):
            rt = sum(ref_vals)
            ct = sum(cur_vals)
            ref_total[lab] = [rt]
            curr_total[lab] = [ct]
            delta_total[lab] = [ct - rt]
        else:
            ref_total[lab] = [float("nan")]
            curr_total[lab] = [float("nan")]
            delta_total[lab] = [float("nan")]

    arrays = {
        "GND_SlideRef_Total": ("cell", 1, ref_total),
        "GND_Current_Total": ("cell", 1, curr_total),
        "DGND_Slide_Total": ("cell", 1, delta_total),
    }
    for slip in range(18):
        arrays["DGND_Slide_Slip%02d_SDV%d" % (slip+1, 11+slip)] = ("cell", 1, slip_delta[slip])
    return arrays


def vtk_type(elem):
    nn = len(elem.connectivity)
    if nn in VTK_CELL_TYPES:
        return VTK_CELL_TYPES[nn]
    raise RuntimeError("Unsupported element topology: %s (%d nodes)" % (elem.type, nn))


def unpack_array_spec(spec):
    if len(spec) >= 4:
        return spec[0], spec[1], spec[2], spec[3]
    return spec[0], spec[1], spec[2], "Float64"


def write_array(f, name, ncomp, order, values, vtk_data_type="Float64"):
    """Batch formatted values to avoid millions of small Python write calls."""
    f.write('        <DataArray type="%s" Name="%s" NumberOfComponents="%d" format="ascii">\n' %
            (vtk_data_type, name, ncomp))
    default = [0] * ncomp if vtk_data_type == "UInt8" else [float("nan")] * ncomp
    parts = []
    batch = 8192
    for key in order:
        arr = values.get(int(key), default)
        for x in arr:
            if vtk_data_type == "UInt8":
                try:
                    xv = int(round(float(x)))
                    xv = max(0, min(255, xv))
                except Exception:
                    xv = 0
                parts.append(" %d" % xv)
            else:
                parts.append(" %.12g" % float(x))
            if len(parts) >= batch:
                f.write("".join(parts))
                parts = []
    if parts:
        f.write("".join(parts))
    f.write('\n        </DataArray>\n')


def write_vtu(path, elems, node_map, arrays, grain_ids=None):
    used_nodes = sorted(set(n for e in elems for n in e.connectivity))
    pindex = dict((lab, i) for i, lab in enumerate(used_nodes))

    conn, offsets, types = [], [], []
    off = 0
    for e in elems:
        c = [pindex[n] for n in e.connectivity]
        conn.extend(c)
        off += len(c)
        offsets.append(off)
        types.append(vtk_type(e))

    cell_order = [int(e.label) for e in elems]

    with open(path, "w") as f:
        f.write('<?xml version="1.0"?>\n')
        f.write('<VTKFile type="UnstructuredGrid" version="0.1" byte_order="LittleEndian">\n')
        f.write('  <UnstructuredGrid>\n')
        f.write('    <Piece NumberOfPoints="%d" NumberOfCells="%d">\n' % (len(used_nodes), len(elems)))

        f.write('      <Points>\n')
        f.write('        <DataArray type="Float64" NumberOfComponents="3" format="ascii">\n')
        point_lines = []
        for lab in used_nodes:
            x,y,z = node_map[lab].coordinates
            point_lines.append(" %.12g %.12g %.12g" % (x,y,z))
            if len(point_lines) >= 2048:
                f.write("".join(point_lines))
                point_lines = []
        if point_lines:
            f.write("".join(point_lines))
        f.write('\n        </DataArray>\n')
        f.write('      </Points>\n')

        f.write('      <Cells>\n')
        f.write('        <DataArray type="Int64" Name="connectivity" format="ascii">\n')
        f.write(" " + " ".join(str(x) for x in conn) + "\n")
        f.write('        </DataArray>\n')
        f.write('        <DataArray type="Int64" Name="offsets" format="ascii">\n')
        f.write(" " + " ".join(str(x) for x in offsets) + "\n")
        f.write('        </DataArray>\n')
        f.write('        <DataArray type="UInt8" Name="types" format="ascii">\n')
        f.write(" " + " ".join(str(x) for x in types) + "\n")
        f.write('        </DataArray>\n')
        f.write('      </Cells>\n')

        point_arrays = [(n,v) for n,v in arrays.items() if v[0] == "point"]
        cell_arrays = [(n,v) for n,v in arrays.items() if v[0] == "cell"]

        f.write('      <PointData>\n')
        for name, spec in point_arrays:
            _,ncomp,vals,dt = unpack_array_spec(spec)
            write_array(f, name, ncomp, used_nodes, vals, dt)
        f.write('      </PointData>\n')

        cell_attr = ' Scalars="Initial_IPF_RGB"' if "Initial_IPF_RGB" in arrays else ""
        f.write('      <CellData%s>\n' % cell_attr)
        if grain_ids:
            vals = dict((lab, [float(grain_ids.get(lab, float("nan")))]) for lab in cell_order)
            write_array(f, "GrainID", 1, cell_order, vals)
        for name, spec in cell_arrays:
            _,ncomp,vals,dt = unpack_array_spec(spec)
            write_array(f, name, ncomp, cell_order, vals, dt)
        f.write('      </CellData>\n')

        f.write('    </Piece>\n')
        f.write('  </UnstructuredGrid>\n')
        f.write('</VTKFile>\n')


def export_frame(odb, instance_name, step_name, frame_index, out_path,
                 fields, element_set="", bbox=None, delta_field="",
                 ref_step="", ref_frame=-1, mesh_cache=None, ref_cache=None,
                 derived_mises=False, initial_ipf=False, inp_path="",
                 ipf_dir="Z", ipf_cache=None, gnd_diff=False, gnd_dat="",
                 gnd_diff_mode="slips", gnd_cache=None,
                 gnd_slide_diff=False, gnd_slide_ref="sliding0", gnd_slide_cache=None):

    if instance_name not in odb.rootAssembly.instances:
        raise RuntimeError("Instance not found: %s" % instance_name)
    inst = odb.rootAssembly.instances[instance_name]

    if step_name not in odb.steps:
        raise RuntimeError("Step not found: %s" % step_name)
    step = odb.steps[step_name]
    if frame_index < 0 or frame_index >= len(step.frames):
        raise RuntimeError("Frame out of range: %d" % frame_index)
    frame = step.frames[frame_index]

    if mesh_cache is None:
        elems, node_map, grain_ids = selected_elements(inst, element_set, bbox)
        elem_labels = set(int(e.label) for e in elems)
        node_labels = set(n for e in elems for n in e.connectivity)
        mesh_cache = (elems, node_map, grain_ids, elem_labels, node_labels)
    else:
        elems, node_map, grain_ids, elem_labels, node_labels = mesh_cache

    if not elems:
        raise RuntimeError("No elements selected for export.")

    arrays = {}

    print("  Reading %d native field(s) for %s / frame %d ..." %
          (len(fields), step_name, frame_index))
    sys.stdout.flush()
    for field_no, name in enumerate(fields, 1):
        if field_no == 1 or field_no == len(fields) or field_no % 5 == 0:
            print("  Field [%d/%d]: %s" % (field_no, len(fields), name))
            sys.stdout.flush()
        arr = extract_field(frame, name, inst, elem_labels, node_labels)
        if arr is not None:
            arrays[name] = arr
        else:
            arrays[name] = ("cell", 1, dict((lab,[float("nan")]) for lab in elem_labels))

    if derived_mises:
        arr = extract_mises(frame, inst, elem_labels)
        if arr is None:
            arrays["Mises"] = ("cell", 1, dict((lab,[float("nan")]) for lab in elem_labels))
            print("WARNING: S is missing in this frame; Mises written as NaN.")
        else:
            arrays["Mises"] = arr

    if initial_ipf:
        if ipf_cache is None:
            ipf_cache = build_initial_ipf_arrays(inp_path, inst, elem_labels, ipf_dir)
        for name,spec in ipf_cache.items():
            arrays[name] = spec

    # The two GND difference families require the same 18 SDV current states.
    # Extract each missing SDV only once, even if it is not in output fields.
    gnd_inputs = arrays
    if gnd_diff or gnd_slide_diff:
        gnd_inputs = dict(arrays)
        missing = ["SDV%d" % n for n in range(11, 29)
                   if "SDV%d" % n not in gnd_inputs]
        if missing:
            print("  Preparing %d shared GND source SDV(s) ..." % len(missing))
            sys.stdout.flush()
        for name in missing:
            arr = extract_field(frame, name, inst, elem_labels, set())
            if arr is None or arr[0] != "cell" or arr[1] != 1:
                raise RuntimeError("GND requires scalar %s in the selected frame." % name)
            gnd_inputs[name] = arr

    if gnd_diff:
        if gnd_cache is None:
            gnd_cache = load_gnd_dat(gnd_dat)
        gd = extract_gnd_difference_arrays(frame, inst, elem_labels, gnd_cache, gnd_diff_mode, gnd_inputs)
        for name,spec in gd.items():
            arrays[name] = spec

    if gnd_slide_diff:
        if gnd_slide_cache is None:
            gnd_slide_cache = build_gnd_slide_reference_cache(odb, inst, elem_labels, gnd_slide_ref)
        gd_slide = extract_gnd_slide_difference_arrays(frame, inst, elem_labels, gnd_slide_cache, gnd_inputs)
        for name,spec in gd_slide.items():
            arrays[name] = spec

    if delta_field:
        target = extract_field(frame, delta_field, inst, elem_labels, node_labels)
        if target is None or target[0] != "cell" or target[1] != 1:
            raise RuntimeError("Difference field must be an element scalar field: %s" % delta_field)

        if ref_cache is None:
            if ref_step not in odb.steps:
                raise RuntimeError("Reference step not found: %s" % ref_step)
            rs = odb.steps[ref_step]
            if ref_frame < 0 or ref_frame >= len(rs.frames):
                raise RuntimeError("Reference frame out of range: %d" % ref_frame)
            ref = extract_field(rs.frames[ref_frame], delta_field, inst, elem_labels, node_labels)
            if ref is None or ref[0] != "cell" or ref[1] != 1:
                raise RuntimeError("Reference difference field must be element scalar.")
            ref_cache = ref

        _, _, tv = target[:3]
        _, _, rv = ref_cache[:3]
        dv = {}
        for lab in elem_labels:
            dv[lab] = [tv[lab][0] - rv[lab][0]]
        arrays["DELTA_" + delta_field] = ("cell", 1, dv)

    print("  Writing VTU: %s ; fields: %d ; elements: %d" %
          (os.path.basename(out_path), len(arrays), len(elems)))
    sys.stdout.flush()
    write_vtu(out_path, elems, node_map, arrays, grain_ids)
    print("  VTU write complete.")
    sys.stdout.flush()
    return mesh_cache, ref_cache, ipf_cache, gnd_cache, gnd_slide_cache


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--odb", required=True)
    p.add_argument("--instance", required=True)
    p.add_argument("--step", required=True)
    p.add_argument("--frame", required=True, type=int)
    p.add_argument("--out", required=True)
    p.add_argument("--fields", default="")
    p.add_argument("--element-set", default="")
    p.add_argument("--bbox", default="")
    p.add_argument("--delta-field", default="")
    p.add_argument("--ref-step", default="")
    p.add_argument("--ref-frame", type=int, default=-1)
    p.add_argument("--mises", type=int, default=0)
    p.add_argument("--initial-ipf", type=int, default=0)
    p.add_argument("--inp", default="")
    p.add_argument("--ipf-dir", default="Z", choices=["X","Y","Z"])
    p.add_argument("--gnd-diff", type=int, default=0)
    p.add_argument("--gnd-dat", default="")
    p.add_argument("--gnd-diff-mode", default="slips", choices=["slips"])
    p.add_argument("--gnd-slide-diff", type=int, default=0)
    p.add_argument("--gnd-slide-ref", default="sliding0", choices=["sliding0","previous_last"])
    p.add_argument("--field-policy", default="merge", choices=["merge","sync"])
    a = p.parse_args()

    odb = None
    try:
        bbox = parse_bbox(a.bbox)
        fields = [x.strip() for x in a.fields.split(",") if x.strip()]
        if a.initial_ipf and (not a.inp or not os.path.exists(a.inp)):
            raise RuntimeError("Initial IPF requires a valid INP file.")
        if a.gnd_diff and (not a.gnd_dat or not os.path.exists(a.gnd_dat)):
            raise RuntimeError("GND difference requires a valid gnd_field.dat file.")
        out_path = os.path.abspath(a.out)
        manifest_path = out_path + ".odb2vtus.json"
        src_id = source_identity(a.odb, a.instance, a.element_set, a.bbox)
        manifest = load_manifest(manifest_path)
        if manifest is not None and not same_source_identity(manifest, src_id):
            raise RuntimeError(
                "Existing single-frame manifest belongs to a different ODB/instance/region. "
                "Choose another output VTU or remove the old sidecar intentionally."
            )
        if manifest is None:
            manifest = new_manifest(src_id)
            if os.path.exists(out_path):
                print("NOTE: legacy VTU detected without a v2 manifest; current request will rebuild it.")

        requested_spec = make_output_spec(
            fields,
            mises=bool(a.mises),
            initial_ipf=bool(a.initial_ipf),
            inp_path=a.inp,
            ipf_dir=a.ipf_dir,
            gnd_diff=bool(a.gnd_diff),
            gnd_dat=a.gnd_dat,
            gnd_diff_mode=a.gnd_diff_mode,
            gnd_slide_diff=bool(a.gnd_slide_diff),
            gnd_slide_ref=a.gnd_slide_ref,
            delta_field=a.delta_field,
            ref_step=a.ref_step,
            ref_frame=a.ref_frame
        )

        key = state_key(a.step, a.frame)
        old = manifest.setdefault("frames", {}).get(key) or {}
        final_spec = merge_output_specs(old.get("output_spec"), requested_spec, a.field_policy)
        rev = source_revision(a.odb)
        reusable = (
            os.path.exists(out_path) and os.path.getsize(out_path) > 0 and
            old.get("output_spec") is not None and
            output_spec_equal(old.get("output_spec"), final_spec) and
            old.get("source_revision") == rev
        )

        odb = openOdb(a.odb, readOnly=True)
        if reusable:
            print("UNCHANGED: same frame and output fields already exist; skipping rebuild.")
        else:
            k = export_kwargs_from_spec(final_spec)
            tmp_out = out_path + ".tmp"
            if os.path.exists(tmp_out):
                os.remove(tmp_out)
            export_frame(
                odb, a.instance, a.step, a.frame, tmp_out, k["fields"],
                a.element_set, bbox, k["delta_field"], k["ref_step"], k["ref_frame"],
                derived_mises=k["derived_mises"], initial_ipf=k["initial_ipf"],
                inp_path=k["inp_path"], ipf_dir=k["ipf_dir"],
                gnd_diff=k["gnd_diff"], gnd_dat=k["gnd_dat"], gnd_diff_mode=k["gnd_diff_mode"],
                gnd_slide_diff=k["gnd_slide_diff"], gnd_slide_ref=k["gnd_slide_ref"]
            )
            atomic_replace(tmp_out, out_path)

        manifest["frames"] = {
            key: {
                "step": a.step,
                "frame": int(a.frame),
                "file": os.path.basename(out_path),
                "active": True,
                "output_spec": final_spec,
                "source_revision": rev,
            }
        }
        atomic_write_json(manifest_path, manifest)

        print("SUCCESS")
        print("Output:", out_path)
        print("Manifest:", manifest_path)
        print("Field policy:", a.field_policy)
        return 0
    except Exception:
        print("FATAL EXCEPTION:")
        print(traceback.format_exc())
        return 99
    finally:
        try:
            if odb is not None:
                odb.close()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
