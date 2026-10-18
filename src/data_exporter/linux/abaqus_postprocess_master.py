# -*- coding: utf-8 -*-
from __future__ import print_function

import os
import sys
import csv
import traceback
import argparse
import numpy as np
from odb_export_state import safe_step_name as sanitize

# When launched from the Linux Tk GUI, stdout is a pipe rather than a terminal.
# Force line buffering so long-running Abaqus/odbAccess progress is visible live.
try:
    sys.stdout.reconfigure(line_buffering=True)
except Exception:
    pass

from odbAccess import openOdb

try:
    from abaqusConstants import SCALAR, INTEGRATION_POINT
except Exception:
    SCALAR = None
    INTEGRATION_POINT = None


# ============================================================
# Generic helpers
# ============================================================

WANTED_HISTORY = ["U1", "U2", "CF1", "CF2", "RF1", "RF2"]
DET_TOL = 1.0e-14
CHECKPOINT_EVERY = 25


def clean_tag(odb_path):
    stem = os.path.splitext(os.path.basename(odb_path))[0]
    low = stem.lower()
    for suffix in ["_final", "-final", " final"]:
        if low.endswith(suffix):
            stem = stem[:-len(suffix)]
            break
    return stem


def ensure_dir(path):
    if not os.path.exists(path):
        os.makedirs(path)


def log_print(logf, msg=""):
    print(msg)
    try:
        sys.stdout.flush()
    except Exception:
        pass
    if logf is not None:
        logf.write(str(msg) + "\n")
        logf.flush()


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--operation", required=True,
                   choices=["history", "peeq_export", "peeq_inject", "peeq_check"])
    p.add_argument("--odb", required=True)
    p.add_argument("--outroot", required=True)
    p.add_argument("--instance", default="")
    return p.parse_args()


# ============================================================
# RP history extraction
# ============================================================

def find_rp_region(step):
    candidates = []
    for name, reg in step.historyRegions.items():
        keys = set(str(k).upper() for k in reg.historyOutputs.keys())
        desc = str(getattr(reg, "description", ""))
        text = (str(name) + " " + desc).upper()

        score = 0
        if "SPHERE_RP" in text:
            score += 1000
        if "RIGID-SPHERE-1" in text or "RIGID_SPHERE-1" in text:
            score += 900
        elif "RIGID-SPHERE" in text or "RIGID_SPHERE" in text:
            score += 600
        if "REFERENCE POINT" in text or "ASSEMBLY" in text:
            score += 30

        for var in WANTED_HISTORY:
            if var in keys:
                score += 25

        if score > 0:
            candidates.append((score, str(name), reg))

    if not candidates:
        return None

    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0]


def read_history_series(reg, var):
    if var not in reg.historyOutputs:
        return {}
    raw = reg.historyOutputs[var].data
    if raw is None:
        return {}
    d = {}
    for item in raw:
        if item is None or len(item) < 2:
            continue
        t, v = item[0], item[1]
        if t is None or v is None:
            continue
        d[round(float(t), 14)] = float(v)
    return d


def write_csv(path, rows, fields):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)


def export_history(odb_path, outroot):
    tag = clean_tag(odb_path)
    outdir = os.path.join(outroot, tag + "_RP_EXPORT")
    ensure_dir(outdir)

    log_path = os.path.join(outdir, tag + "_RP_EXPORT.log")
    logf = open(log_path, "w")
    odb = None

    try:
        log_print(logf, "=" * 78)
        log_print(logf, "Universal RP history exporter")
        log_print(logf, "ODB: %s" % odb_path)
        log_print(logf, "OUT: %s" % outdir)
        log_print(logf, "=" * 78)

        odb = openOdb(odb_path, readOnly=True)

        all_rows = []
        diag_rows = []
        time_offset = 0.0

        for step_name, step in odb.steps.items():
            nframes = len(step.frames)
            hit = find_rp_region(step)

            if hit is None:
                diag_rows.append({
                    "Step": step_name, "Frames": nframes, "Region": "",
                    "U1_n": 0, "U2_n": 0, "CF1_n": 0, "CF2_n": 0,
                    "RF1_n": 0, "RF2_n": 0, "Times_n": 0,
                    "Status": "NO_RP_REGION"
                })
                try:
                    time_offset += float(step.frames[-1].frameValue)
                except Exception:
                    pass
                continue

            _, region_name, reg = hit
            series = {}
            all_times = set()

            for var in WANTED_HISTORY:
                series[var] = read_history_series(reg, var)
                all_times.update(series[var].keys())

            times = sorted(all_times)

            diag_rows.append({
                "Step": step_name, "Frames": nframes, "Region": region_name,
                "U1_n": len(series["U1"]), "U2_n": len(series["U2"]),
                "CF1_n": len(series["CF1"]), "CF2_n": len(series["CF2"]),
                "RF1_n": len(series["RF1"]), "RF2_n": len(series["RF2"]),
                "Times_n": len(times),
                "Status": "OK" if times else "NO_HISTORY_RECORDS"
            })

            for idx, tk in enumerate(times):
                if all_rows and abs(float(tk)) < 1.0e-15:
                    continue

                u1 = series["U1"].get(tk, "")
                u2 = series["U2"].get(tk, "")
                cf1 = series["CF1"].get(tk, "")
                cf2 = series["CF2"].get(tk, "")
                rf1 = series["RF1"].get(tk, "")
                rf2 = series["RF2"].get(tk, "")

                if isinstance(cf2, float):
                    normal_load = abs(cf2)
                    normal_source = "CF2"
                elif isinstance(rf2, float):
                    normal_load = abs(rf2)
                    normal_source = "RF2"
                else:
                    normal_load = ""
                    normal_source = ""

                if isinstance(rf1, float):
                    tang_force = abs(rf1)
                    tang_source = "RF1"
                elif isinstance(cf1, float):
                    tang_force = abs(cf1)
                    tang_source = "CF1"
                else:
                    tang_force = ""
                    tang_source = ""

                cof = ""
                if isinstance(normal_load, float) and normal_load > 1.0e-30 and isinstance(tang_force, float):
                    cof = tang_force / normal_load

                all_rows.append({
                    "Step": step_name,
                    "LocalIndex": idx,
                    "StepTime": float(tk),
                    "TotalTime": time_offset + float(tk),
                    "U1": u1, "U2": u2,
                    "CF1": cf1, "CF2": cf2,
                    "RF1": rf1, "RF2": rf2,
                    "NormalLoad_abs": normal_load,
                    "NormalLoad_source": normal_source,
                    "TangentialForce_abs": tang_force,
                    "TangentialForce_source": tang_source,
                    "COF_abs": cof
                })

            try:
                time_offset += float(step.frames[-1].frameValue)
            except Exception:
                pass

        diag_csv = os.path.join(outdir, tag + "_STEP_DIAGNOSTIC.csv")
        all_csv = os.path.join(outdir, tag + "_sphere_ALL_v3.csv")
        normal_csv = os.path.join(outdir, tag + "_NORMAL_U2_CF2_v3.csv")
        tang_csv = os.path.join(outdir, tag + "_TANGENTIAL_U1_RF1_v3.csv")

        write_csv(
            diag_csv, diag_rows,
            ["Step","Frames","Region","U1_n","U2_n","CF1_n","CF2_n",
             "RF1_n","RF2_n","Times_n","Status"]
        )

        write_csv(
            all_csv, all_rows,
            ["Step","LocalIndex","StepTime","TotalTime","U1","U2","CF1","CF2","RF1","RF2",
             "NormalLoad_abs","NormalLoad_source",
             "TangentialForce_abs","TangentialForce_source","COF_abs"]
        )

        normal_rows = [{
            "Step": r["Step"], "StepTime": r["StepTime"], "TotalTime": r["TotalTime"],
            "U2_mm": r["U2"], "CF2_raw": r["CF2"], "RF2_raw": r["RF2"],
            "NormalLoad_abs": r["NormalLoad_abs"], "LoadSource": r["NormalLoad_source"]
        } for r in all_rows]

        tang_rows = [{
            "Step": r["Step"], "StepTime": r["StepTime"], "TotalTime": r["TotalTime"],
            "U1_mm": r["U1"], "RF1_raw": r["RF1"], "CF1_raw": r["CF1"],
            "TangentialForce_abs": r["TangentialForce_abs"],
            "ForceSource": r["TangentialForce_source"], "COF_abs": r["COF_abs"]
        } for r in all_rows]

        write_csv(
            normal_csv, normal_rows,
            ["Step","StepTime","TotalTime","U2_mm","CF2_raw","RF2_raw",
             "NormalLoad_abs","LoadSource"]
        )

        write_csv(
            tang_csv, tang_rows,
            ["Step","StepTime","TotalTime","U1_mm","RF1_raw","CF1_raw",
             "TangentialForce_abs","ForceSource","COF_abs"]
        )

        log_print(logf, "SUCCESS")
        log_print(logf, "ALL: %s" % all_csv)
        log_print(logf, "NORMAL: %s" % normal_csv)
        log_print(logf, "TANGENTIAL: %s" % tang_csv)
        log_print(logf, "DIAGNOSTIC: %s" % diag_csv)
        return 0

    except Exception:
        log_print(logf, "FATAL EXCEPTION:")
        log_print(logf, traceback.format_exc())
        return 99

    finally:
        try:
            if odb is not None:
                odb.close()
        except Exception:
            pass
        logf.close()


# ============================================================
# Matched target-frame schedule
# ============================================================

Q5_FRACTIONS = (0.0, 0.25, 0.50, 0.75, 1.0)
Q5_LABELS = ("T0", "T25", "T50", "T75", "T100")


def is_sliding_step_name(step_name):
    """Recognize friction/sliding cycle steps from the ODB step name."""
    u = str(step_name).upper()
    return ("SLIDING" in u) or ("FRICTION" in u and "CYCLE" in u)


def nearest_frame_index_by_time(step, target_time):
    """Return the actual frame whose StepTime is nearest to target_time.

    ODB frameValue is monotonic inside a Step, so use binary search instead of
    scanning every frame. This is important for very large ODBs because each
    step.frames[i] access may trigger ODB I/O.

    Abaqus OdbSequence supports integer indexing but not Python slicing.
    """
    nframes = len(step.frames)
    if nframes <= 0:
        return None
    if nframes == 1:
        return 0

    target_time = float(target_time)

    t_first = float(step.frames[0].frameValue)
    t_last = float(step.frames[nframes - 1].frameValue)

    if target_time <= t_first:
        return 0
    if target_time >= t_last:
        return nframes - 1

    lo = 0
    hi = nframes - 1

    # Find neighboring frames bracketing target_time.
    while hi - lo > 1:
        mid = (lo + hi) // 2
        tm = float(step.frames[mid].frameValue)
        if tm < target_time:
            lo = mid
        else:
            hi = mid

    t_lo = float(step.frames[lo].frameValue)
    t_hi = float(step.frames[hi].frameValue)

    if abs(t_lo - target_time) <= abs(t_hi - target_time):
        return lo
    return hi


def build_matched_frame_schedule(odb):
    """
    Selection rule used to match the ParaView/VTU workflow:
      1) Normal indentation step: first + last frame.
      2) Every sliding cycle: StepTime fractions 0, 1/4, 1/2, 3/4, 1.
         For each target time, use the nearest actual ODB frame.

    The indentation step is the step immediately before the first sliding step.
    If no sliding step is found, the first ODB step is treated as indentation.
    """
    step_names = list(odb.steps.keys())
    if not step_names:
        return []

    sliding_indices = [i for i, n in enumerate(step_names) if is_sliding_step_name(n)]
    if sliding_indices:
        press_index = max(0, sliding_indices[0] - 1)
    else:
        press_index = 0

    rows = []

    # Indentation / normal-load step: first and last frame.
    press_name = step_names[press_index]
    press_step = odb.steps[press_name]
    if len(press_step.frames) > 0:
        for state, fi in (("PRESS_START", 0), ("PRESS_END", len(press_step.frames)-1)):
            fr = press_step.frames[fi]
            rows.append({
                "StepOrder": press_index,
                "Step": press_name,
                "State": state,
                "TargetFraction": 0.0 if state == "PRESS_START" else 1.0,
                "TargetStepTime": float(fr.frameValue),
                "FrameIndex": int(fi),
                "ActualStepTime": float(fr.frameValue),
                "TimeError": 0.0,
            })

    # Every sliding/friction cycle: five equal StepTime positions.
    for si in sliding_indices:
        step_name = step_names[si]
        step = odb.steps[step_name]
        if len(step.frames) <= 0:
            continue
        t0 = float(step.frames[0].frameValue)
        t1 = float(step.frames[-1].frameValue)
        duration = t1 - t0
        for label, frac in zip(Q5_LABELS, Q5_FRACTIONS):
            tt = t0 + frac * duration
            fi = nearest_frame_index_by_time(step, tt)
            fr = step.frames[fi]
            at = float(fr.frameValue)
            rows.append({
                "StepOrder": si,
                "Step": step_name,
                "State": label,
                "TargetFraction": float(frac),
                "TargetStepTime": float(tt),
                "FrameIndex": int(fi),
                "ActualStepTime": at,
                "TimeError": at - float(tt),
            })

    return rows


def selected_frame_paths(odb_path, outroot):
    tag = clean_tag(odb_path)
    outdir = os.path.join(outroot, tag + "_PEEQCP_EXPORT")
    selected_dir = os.path.join(outdir, "selected_frames")
    ensure_dir(outdir)
    ensure_dir(selected_dir)
    return {
        "outdir": outdir,
        "selected_dir": selected_dir,
        "manifest": os.path.join(outdir, tag + "_PEEQCP_SELECTED_FRAMES.csv"),
        "summary": os.path.join(outdir, tag + "_PEEQCP_SELECTED_SUMMARY.csv"),
    }


def snapshot_filename(row):
    return "PEEQCP_S%02d_%s_F%05d.npz" % (
        int(row["StepOrder"]), sanitize(row["Step"]), int(row["FrameIndex"])
    )


def write_selected_manifest(path, schedule):
    fields = [
        "StepOrder", "Step", "State", "TargetFraction", "TargetStepTime",
        "FrameIndex", "ActualStepTime", "TimeError", "SnapshotFile"
    ]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in schedule:
            rr = dict(r)
            rr["SnapshotFile"] = snapshot_filename(r)
            w.writerow(rr)


def update_selected_summary(path, row):
    fields = [
        "StepOrder", "Step", "State", "TargetFraction", "TargetStepTime",
        "FrameIndex", "ActualStepTime", "TimeError",
        "PEEQCP_mean", "PEEQCP_median", "PEEQCP_p95", "PEEQCP_p99", "PEEQCP_max"
    ]
    key = (str(row["Step"]), int(row["FrameIndex"]))
    rows = {}
    if os.path.exists(path):
        try:
            with open(path, "r", newline="") as f:
                rd = csv.DictReader(f)
                for r in rd:
                    if r.get("Step") != "" and r.get("FrameIndex") != "":
                        rows[(str(r["Step"]), int(r["FrameIndex"]))] = r
        except Exception:
            rows = {}
    rows[key] = row
    ordered = sorted(rows.values(), key=lambda r: (int(r["StepOrder"]), int(r["FrameIndex"])))
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in ordered:
            w.writerow(r)


def save_selected_snapshot(row, selected_paths, element_labels, ips, peeq, instance_name):
    p = os.path.join(selected_paths["selected_dir"], snapshot_filename(row))
    np.savez(
        p,
        element_labels=element_labels,
        integration_points=ips,
        peeq=peeq,
        instance_name=np.asarray([instance_name]),
        step_name=np.asarray([str(row["Step"])]),
        frame_index=np.asarray([int(row["FrameIndex"])], dtype=np.int64),
        actual_step_time=np.asarray([float(row["ActualStepTime"])], dtype=np.float64),
    )

    finite = peeq[np.isfinite(peeq)]
    if finite.size == 0:
        stats = dict(PEEQCP_mean=np.nan, PEEQCP_median=np.nan,
                     PEEQCP_p95=np.nan, PEEQCP_p99=np.nan, PEEQCP_max=np.nan)
    else:
        stats = {
            "PEEQCP_mean": float(np.mean(finite)),
            "PEEQCP_median": float(np.median(finite)),
            "PEEQCP_p95": float(np.percentile(finite, 95)),
            "PEEQCP_p99": float(np.percentile(finite, 99)),
            "PEEQCP_max": float(np.max(finite)),
        }
    sr = dict(row)
    sr.update(stats)
    update_selected_summary(selected_paths["summary"], sr)
    return p


def read_selected_manifest(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, "r", newline="") as f:
        rd = csv.DictReader(f)
        for r in rd:
            rows.append({
                "StepOrder": int(r["StepOrder"]),
                "Step": r["Step"],
                "State": r["State"],
                "TargetFraction": float(r["TargetFraction"]),
                "TargetStepTime": float(r["TargetStepTime"]),
                "FrameIndex": int(r["FrameIndex"]),
                "ActualStepTime": float(r["ActualStepTime"]),
                "TimeError": float(r["TimeError"]),
                "SnapshotFile": r["SnapshotFile"],
            })
    return rows


# ============================================================
# PEEQCP
# ============================================================

def detect_cp_instance(odb, requested=""):
    if requested:
        if requested in odb.rootAssembly.instances:
            return requested
        raise RuntimeError("Requested instance not found: %s" % requested)

    step_names = list(odb.steps.keys())
    if not step_names:
        raise RuntimeError("No steps in ODB.")

    frame = odb.steps[step_names[0]].frames[0]

    required = ["SDV%d" % k for k in range(1, 10)]
    for name in required:
        if name not in frame.fieldOutputs:
            raise RuntimeError("Missing %s in first frame." % name)

    best = None
    best_n = -1

    for inst_name, inst in odb.rootAssembly.instances.items():
        try:
            vals = frame.fieldOutputs["SDV1"].getSubset(region=inst).values
            n = len(vals)
            if n > best_n:
                best = inst_name
                best_n = n
        except Exception:
            pass

    if best is None or best_n <= 0:
        raise RuntimeError("Could not auto-detect an instance containing SDV1.")

    return best


def build_keys(frame, instance):
    vals = frame.fieldOutputs["SDV1"].getSubset(region=instance).values
    keys = []
    for v in vals:
        lab = int(v.elementLabel)
        ip = int(getattr(v, "integrationPoint", 1))
        keys.append((lab, ip))

    keys = sorted(keys)

    if len(keys) != len(set(keys)):
        raise RuntimeError("Duplicate (element, integration point) keys in SDV1.")

    return keys


def scalar_field_by_keys(frame, field_name, instance, keys):
    if field_name not in frame.fieldOutputs:
        return None

    vals = frame.fieldOutputs[field_name].getSubset(region=instance).values
    mp = {}
    for v in vals:
        lab = int(v.elementLabel)
        ip = int(getattr(v, "integrationPoint", 1))
        mp[(lab, ip)] = float(v.data)

    arr = np.full(len(keys), np.nan, dtype=np.float64)
    for i, k in enumerate(keys):
        if k in mp:
            arr[i] = mp[k]

    return arr


def read_fp(frame, instance, keys):
    x = []
    for k in range(1, 10):
        a = scalar_field_by_keys(frame, "SDV%d" % k, instance, keys)
        if a is None:
            return None
        x.append(a)

    fp = np.empty((len(keys), 3, 3), dtype=np.float64)

    # Fortran column-major mapping from the UMAT:
    # 1 Fp11, 2 Fp21, 3 Fp31,
    # 4 Fp12, 5 Fp22, 6 Fp32,
    # 7 Fp13, 8 Fp23, 9 Fp33.
    fp[:,0,0] = x[0]
    fp[:,1,0] = x[1]
    fp[:,2,0] = x[2]

    fp[:,0,1] = x[3]
    fp[:,1,1] = x[4]
    fp[:,2,1] = x[5]

    fp[:,0,2] = x[6]
    fp[:,1,2] = x[7]
    fp[:,2,2] = x[8]

    return fp


def batch_inv3(m):
    a,b,c = m[:,0,0],m[:,0,1],m[:,0,2]
    d,e,f = m[:,1,0],m[:,1,1],m[:,1,2]
    g,h,i = m[:,2,0],m[:,2,1],m[:,2,2]

    det = a*(e*i-f*h) - b*(d*i-f*g) + c*(d*h-e*g)
    sd = det.copy()
    sd[np.abs(sd) < DET_TOL] = np.nan

    inv = np.empty_like(m, dtype=np.float64)

    inv[:,0,0]=(e*i-f*h)/sd
    inv[:,0,1]=-(b*i-c*h)/sd
    inv[:,0,2]=(b*f-c*e)/sd

    inv[:,1,0]=-(d*i-f*g)/sd
    inv[:,1,1]=(a*i-c*g)/sd
    inv[:,1,2]=-(a*f-c*d)/sd

    inv[:,2,0]=(d*h-e*g)/sd
    inv[:,2,1]=-(a*h-b*g)/sd
    inv[:,2,2]=(a*e-b*d)/sd

    return inv, det


def peeq_increment(fp0, fp1):
    inv0, det0 = batch_inv3(fp0)

    valid = np.isfinite(fp0).all(axis=(1,2))
    valid &= np.isfinite(fp1).all(axis=(1,2))
    valid &= np.isfinite(det0)
    valid &= np.abs(det0) > DET_TOL

    A = np.einsum("nij,njk->nik", fp1-fp0, inv0)
    D = 0.5 * (A + np.transpose(A, (0,2,1)))

    tr3 = (D[:,0,0] + D[:,1,1] + D[:,2,2]) / 3.0

    dev = D.copy()
    dev[:,0,0] -= tr3
    dev[:,1,1] -= tr3
    dev[:,2,2] -= tr3

    q = np.sqrt(
        np.maximum(
            (2.0/3.0) * np.einsum("nij,nij->n", dev, dev),
            0.0
        )
    )

    valid &= np.isfinite(q)
    q[~valid] = 0.0
    return q


def peeq_paths(odb_path, outroot):
    tag = clean_tag(odb_path)
    outdir = os.path.join(outroot, tag + "_PEEQCP_EXPORT")
    ensure_dir(outdir)

    return {
        "tag": tag,
        "outdir": outdir,
        "checkpoint": os.path.join(outdir, "checkpoint_peeqcp_q5frames.npz"),
        "summary": os.path.join(outdir, tag + "_PEEQCP_cycle_summary.csv"),
        "final": os.path.join(outdir, tag + "_PEEQCP_final_map.csv"),
        "log": os.path.join(outdir, tag + "_PEEQCP_export.log")
    }


def save_checkpoint(path, element_labels, ips, peeq, prev_fp,
                    next_step, next_frame, processed, instance_name):
    tmp = path + ".tmp.npz"
    np.savez(
        tmp,
        element_labels=element_labels,
        integration_points=ips,
        peeq=peeq,
        prev_fp=prev_fp,
        next_step=np.asarray([next_step], dtype=np.int64),
        next_frame=np.asarray([next_frame], dtype=np.int64),
        processed=np.asarray([processed], dtype=np.int64),
        instance_name=np.asarray([instance_name])
    )
    os.replace(tmp, path)


def update_summary_csv(path, row):
    fields = ["Step","PEEQCP_mean","PEEQCP_median",
              "PEEQCP_p95","PEEQCP_p99","PEEQCP_max"]

    rows = {}
    if os.path.exists(path):
        try:
            with open(path, "r", newline="") as f:
                rd = csv.DictReader(f)
                for r in rd:
                    if r.get("Step"):
                        rows[r["Step"]] = r
        except Exception:
            rows = {}

    rows[row["Step"]] = row

    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for step_name in rows:
            w.writerow(rows[step_name])


def export_peeq(odb_path, outroot, requested_instance=""):
    paths = peeq_paths(odb_path, outroot)
    selected_paths = selected_frame_paths(odb_path, outroot)
    outdir = paths["outdir"]
    logf = open(paths["log"], "a")
    odb = None

    try:
        log_print(logf, "=" * 78)
        log_print(logf, "Universal PEEQCP exporter - matched Q5 frame schedule")
        log_print(logf, "ODB: %s" % odb_path)
        log_print(logf, "OUT: %s" % outdir)
        log_print(logf, "Rule: indentation first/last; sliding cycles T0/T25/T50/T75/T100 by StepTime")
        log_print(logf, "IMPORTANT: all ODB frames are still traversed for accurate accumulation.")
        log_print(logf, "=" * 78)

        odb = openOdb(odb_path, readOnly=True)
        instance_name = detect_cp_instance(odb, requested_instance)
        inst = odb.rootAssembly.instances[instance_name]
        log_print(logf, "CP instance: %s" % instance_name)

        step_names = list(odb.steps.keys())
        if not step_names:
            raise RuntimeError("No steps in ODB.")

        log_print(logf, "Building matched target-frame schedule (binary StepTime search)...")
        schedule = build_matched_frame_schedule(odb)
        if not schedule:
            raise RuntimeError("Could not build target-frame schedule.")
        write_selected_manifest(selected_paths["manifest"], schedule)
        log_print(logf, "Target-frame schedule built.")

        targets_by_key = {}
        for r in schedule:
            key = (int(r["StepOrder"]), int(r["FrameIndex"]))
            targets_by_key.setdefault(key, []).append(r)

        log_print(logf, "Target states: %d" % len(schedule))
        for r in schedule:
            log_print(logf, "  [%02d] %s / %s : target_t=%.12g -> frame=%d actual_t=%.12g" % (
                r["StepOrder"], r["Step"], r["State"], r["TargetStepTime"],
                r["FrameIndex"], r["ActualStepTime"]))

        if os.path.exists(paths["checkpoint"]):
            z = np.load(paths["checkpoint"], allow_pickle=True)
            element_labels = z["element_labels"].astype(np.int64)
            ips = z["integration_points"].astype(np.int64)
            peeq = z["peeq"].astype(np.float64)
            prev_fp = z["prev_fp"].astype(np.float64)
            start_step = int(z["next_step"][0])
            start_frame = int(z["next_frame"][0])
            processed = int(z["processed"][0])
            checkpoint_instance = str(z["instance_name"][0])
            if checkpoint_instance != instance_name:
                raise RuntimeError("Checkpoint instance mismatch: %s vs %s" %
                                   (checkpoint_instance, instance_name))
            keys = list(zip(element_labels.tolist(), ips.tolist()))
            log_print(logf, "RESUME: step=%d frame=%d processed=%d" %
                      (start_step, start_frame, processed))
        else:
            fr0 = odb.steps[step_names[0]].frames[0]
            log_print(logf, "Initializing element/integration-point keys from first frame...")
            keys = build_keys(fr0, inst)
            log_print(logf, "Element/IP keys built: %d" % len(keys))
            element_labels = np.asarray([k[0] for k in keys], dtype=np.int64)
            ips = np.asarray([k[1] for k in keys], dtype=np.int64)
            log_print(logf, "Reading initial Fp (SDV1-SDV9)...")
            prev_fp = read_fp(fr0, inst, keys)
            if prev_fp is None:
                raise RuntimeError("Could not read SDV1-SDV9 from first frame.")
            peeq = np.zeros(len(keys), dtype=np.float64)
            start_step = 0
            start_frame = 1
            processed = 1

            # Save first ODB frame immediately if it is a requested state.
            first_key = (0, 0)
            if first_key in targets_by_key:
                p = save_selected_snapshot(targets_by_key[first_key][0], selected_paths,
                                           element_labels, ips, peeq, instance_name)
                log_print(logf, "  SAVED target snapshot: %s" % p)

            save_checkpoint(paths["checkpoint"], element_labels, ips, peeq, prev_fp,
                            start_step, start_frame, processed, instance_name)
            log_print(logf, "Fresh start. Element/IP records: %d" % len(keys))

        for si in range(start_step, len(step_names)):
            step_name = step_names[si]
            step = odb.steps[step_name]
            nframes = len(step.frames)
            fi0 = start_frame if si == start_step else 0
            since_checkpoint = 0

            log_print(logf, "[%02d/%02d] %s ; frames=%d ; start=%d" %
                      (si+1, len(step_names), step_name, nframes, fi0))

            for fi in range(fi0, nframes):
                fr = step.frames[fi]
                fp = read_fp(fr, inst, keys)
                if fp is None:
                    continue

                peeq += peeq_increment(prev_fp, fp)
                good = np.isfinite(fp).all(axis=(1,2))
                prev_fp[good,:,:] = fp[good,:,:]
                processed += 1
                since_checkpoint += 1

                target_key = (si, fi)
                if target_key in targets_by_key:
                    # One physical frame may correspond to more than one target fraction
                    # if output is extremely sparse. Save the map once; all manifest rows
                    # point to the same frame-based snapshot file.
                    p = save_selected_snapshot(targets_by_key[target_key][0], selected_paths,
                                               element_labels, ips, peeq.copy(), instance_name)
                    log_print(logf, "  SAVED target: %s / frame %d / t=%.12g -> %s" %
                              (step_name, fi, float(fr.frameValue), p))

                if processed % 10 == 0:
                    log_print(logf, "  processed=%d frame=%d/%d max=%.8g" %
                              (processed, fi, nframes-1, np.nanmax(peeq)))

                if since_checkpoint >= CHECKPOINT_EVERY:
                    nsi, nfi = si, fi+1
                    if nfi >= nframes:
                        nsi, nfi = si+1, 0
                    save_checkpoint(paths["checkpoint"], element_labels, ips, peeq, prev_fp,
                                    nsi, nfi, processed, instance_name)
                    since_checkpoint = 0

            # Keep the original step-end NPZ for backward compatibility.
            map_path = os.path.join(outdir, "PEEQCP_%s.npz" % sanitize(step_name))
            np.savez(map_path, element_labels=element_labels, integration_points=ips,
                     peeq=peeq, instance_name=np.asarray([instance_name]))

            finite = peeq[np.isfinite(peeq)]
            row = {
                "Step": step_name,
                "PEEQCP_mean": float(np.mean(finite)),
                "PEEQCP_median": float(np.median(finite)),
                "PEEQCP_p95": float(np.percentile(finite, 95)),
                "PEEQCP_p99": float(np.percentile(finite, 99)),
                "PEEQCP_max": float(np.max(finite))
            }
            update_summary_csv(paths["summary"], row)

            save_checkpoint(paths["checkpoint"], element_labels, ips, peeq, prev_fp,
                            si+1, 0, processed, instance_name)
            start_frame = 0

        with open(paths["final"], "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["ElementLabel","IntegrationPoint","PEEQCP"])
            for lab, ip, val in zip(element_labels, ips, peeq):
                w.writerow([int(lab), int(ip), float(val)])

        log_print(logf, "CALCULATION COMPLETE")
        log_print(logf, "Selected-frame manifest: %s" % selected_paths["manifest"])
        log_print(logf, "Selected-frame summary:  %s" % selected_paths["summary"])
        return 0

    except Exception:
        log_print(logf, "FATAL EXCEPTION:")
        log_print(logf, traceback.format_exc())
        return 99

    finally:
        try:
            if odb is not None:
                odb.close()
        except Exception:
            pass
        logf.close()


def inject_peeq(odb_path, outroot, requested_instance=""):
    paths = peeq_paths(odb_path, outroot)
    selected_paths = selected_frame_paths(odb_path, outroot)
    odb = None

    try:
        lck = os.path.splitext(odb_path)[0] + ".lck"
        if os.path.exists(lck):
            print("ERROR: ODB lock exists.")
            print("Close Abaqus/Viewer first:")
            print(lck)
            return 3

        manifest = read_selected_manifest(selected_paths["manifest"])
        if not manifest:
            raise RuntimeError("Selected-frame manifest is missing. Run PEEQCP calculation first: %s" %
                               selected_paths["manifest"])

        odb = openOdb(odb_path, readOnly=False)
        instance_name = detect_cp_instance(odb, requested_instance)
        inst = odb.rootAssembly.instances[instance_name]

        wrote = 0
        skipped = 0
        visited = set()

        for r in manifest:
            step_name = r["Step"]
            fi = int(r["FrameIndex"])
            key = (step_name, fi)
            if key in visited:
                continue
            visited.add(key)

            if step_name not in odb.steps:
                print("SKIP missing step: %s" % step_name)
                skipped += 1
                continue
            step = odb.steps[step_name]
            if fi < 0 or fi >= len(step.frames):
                print("SKIP invalid frame: %s / %d" % (step_name, fi))
                skipped += 1
                continue

            map_path = os.path.join(selected_paths["selected_dir"], r["SnapshotFile"])
            if not os.path.exists(map_path):
                print("SKIP missing snapshot: %s" % map_path)
                skipped += 1
                continue

            z = np.load(map_path, allow_pickle=True)
            labels = z["element_labels"].astype(np.int64)
            ips = z["integration_points"].astype(np.int64)
            peeq = z["peeq"].astype(np.float64)

            if len(labels) != len(np.unique(labels)):
                raise RuntimeError(
                    "This ODB contains multiple integration points per element. "
                    "The selected-frame calculation/NPZ export is valid, but the current "
                    "injector intentionally stops rather than write ambiguous integration-point data."
                )

            frame = step.frames[fi]
            if "PEEQCP" in frame.fieldOutputs:
                print("SKIP existing PEEQCP: %s / frame %d" % (step_name, fi))
                skipped += 1
                continue

            fld = frame.FieldOutput(
                name="PEEQCP",
                description="Accumulated J2-equivalent plastic strain from CP Fp increments; matched target frame",
                type=SCALAR
            )
            fld.addData(
                position=INTEGRATION_POINT,
                instance=inst,
                labels=tuple(int(x) for x in labels.tolist()),
                data=tuple((float(x),) for x in peeq.tolist())
            )
            wrote += 1
            print("WROTE %s / frame %d / t=%.12g : %d values" %
                  (step_name, fi, float(frame.frameValue), len(labels)))

        odb.save()
        print("DONE. Selected-frame fields written: %d ; skipped: %d" % (wrote, skipped))
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


def check_peeq(odb_path, outroot):
    tag = clean_tag(odb_path)
    out_path = os.path.join(outroot, tag + "_PEEQCP_CHECK.txt")
    selected_paths = selected_frame_paths(odb_path, outroot)
    odb = None

    try:
        odb = openOdb(odb_path, readOnly=True)
        manifest = read_selected_manifest(selected_paths["manifest"])

        with open(out_path, "w") as f:
            if not manifest:
                f.write("Selected-frame manifest missing: %s\n" % selected_paths["manifest"])
                print("Selected-frame manifest missing. Run calculation first.")
                return 4

            seen = set()
            for r in manifest:
                step_name = r["Step"]
                fi = int(r["FrameIndex"])
                key = (step_name, fi)
                if key in seen:
                    continue
                seen.add(key)

                if step_name not in odb.steps or fi >= len(odb.steps[step_name].frames):
                    line = "%s / frame=%d : INVALID" % (step_name, fi)
                    print(line); f.write(line + "\n")
                    continue

                frame = odb.steps[step_name].frames[fi]
                has = "PEEQCP" in frame.fieldOutputs
                line = "%s / frame=%d / StepTime=%.12g / target=%s : PEEQCP=%s" % (
                    step_name, fi, float(frame.frameValue), r["State"], "YES" if has else "NO")
                print(line)
                f.write(line + "\n")
                if has:
                    n = len(frame.fieldOutputs["PEEQCP"].values)
                    f.write("    values=%d\n" % n)

        print("Saved: %s" % out_path)
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


def main():
    args = parse_args()

    odb_path = os.path.abspath(args.odb)
    outroot = os.path.abspath(args.outroot)

    if not os.path.exists(odb_path):
        print("ERROR: ODB does not exist:")
        print(odb_path)
        return 2

    ensure_dir(outroot)

    if args.operation == "history":
        return export_history(odb_path, outroot)

    if args.operation == "peeq_export":
        return export_peeq(odb_path, outroot, args.instance)

    if args.operation == "peeq_inject":
        return inject_peeq(odb_path, outroot, args.instance)

    if args.operation == "peeq_check":
        return check_peeq(odb_path, outroot)

    return 1


if __name__ == "__main__":
    sys.exit(main())
