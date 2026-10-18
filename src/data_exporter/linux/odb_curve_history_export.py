# -*- coding: utf-8 -*-
from __future__ import print_function
import os, sys, csv, argparse, traceback
from odbAccess import openOdb

COF_NAME = "COF=|RF1|/|CF2|"

def read_steps(path):
    rows = []
    with open(path, "r", encoding="utf-8-sig") as f:
        for line in f:
            s = line.strip()
            if s and not s.startswith("#"):
                rows.append(s)
    return rows

def series_dict(region, var):
    if var not in region.historyOutputs:
        raise RuntimeError("History variable not found: %s" % var)

    d = {}
    for t, v in region.historyOutputs[var].data:
        d[round(float(t), 12)] = float(v)
    return d

def global_offsets(odb):
    offsets = {}
    t = 0.0
    for sname, step in odb.steps.items():
        offsets[sname] = t
        if len(step.frames):
            t += float(step.frames[-1].frameValue)
    return offsets

def source_required_vars(src):
    if src in ("StepTime", "GlobalTime"):
        return []
    if src == COF_NAME:
        return ["RF1", "CF2"]
    return [src]

def compute_source(src, t, values, global_t):
    if src == "StepTime":
        return float(t)
    if src == "GlobalTime":
        return float(global_t)
    if src == COF_NAME:
        den = abs(values["CF2"])
        if den <= 1.0e-30:
            return float("nan")
        return abs(values["RF1"]) / den
    return float(values[src])

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--odb", required=True)
    p.add_argument("--steps-file", required=True)
    p.add_argument("--region", required=True)
    p.add_argument("--xsource", required=True)
    p.add_argument("--ysource", required=True)
    p.add_argument("--out", required=True)

    p.add_argument("--x-abs", type=int, default=0)
    p.add_argument("--y-abs", type=int, default=0)
    p.add_argument("--x-scale", type=float, default=1.0)
    p.add_argument("--y-scale", type=float, default=1.0)
    p.add_argument("--x-offset", type=float, default=0.0)
    p.add_argument("--y-offset", type=float, default=0.0)
    p.add_argument("--dedupe-boundary", type=int, default=1)
    a = p.parse_args()

    odb = None

    try:
        steps = read_steps(a.steps_file)
        if not steps:
            raise RuntimeError("No Steps selected.")

        print("Opening ODB (read-only):", a.odb)
        odb = openOdb(a.odb, readOnly=True)
        print("ODB opened.")

        offsets = global_offsets(odb)
        odb_step_names = list(odb.steps.keys())
        order = dict((name, i) for i, name in enumerate(odb_step_names))

        for s in steps:
            if s not in odb.steps:
                raise RuntimeError("Step not found: %s" % s)

        steps = sorted(set(steps), key=lambda x: order[x])

        required = []
        for src in (a.xsource, a.ysource):
            for v in source_required_vars(src):
                if v not in required:
                    required.append(v)

        rows = []
        prev_global_t = None

        for step_index, sname in enumerate(steps):
            step = odb.steps[sname]

            if a.region not in step.historyRegions:
                raise RuntimeError(
                    "History region '%s' not found in Step '%s'."
                    % (a.region, sname)
                )

            region = step.historyRegions[a.region]

            # Build variable time dictionaries.
            maps = {}
            for var in required:
                maps[var] = series_dict(region, var)

            # Candidate times:
            # if variables are required, use their exact common time keys;
            # if both sources are time-only, use frame times.
            if maps:
                key_sets = [set(d.keys()) for d in maps.values()]
                common = set.intersection(*key_sets) if key_sets else set()
                times = sorted(common)
            else:
                times = sorted(set(round(float(fr.frameValue), 12) for fr in step.frames))

            print("Step: %s ; aligned points=%d" % (sname, len(times)))

            for point_index, tkey in enumerate(times):
                t = float(tkey)
                gt = offsets[sname] + t

                if (
                    a.dedupe_boundary
                    and prev_global_t is not None
                    and abs(gt - prev_global_t) <= 1.0e-12
                ):
                    continue

                vals = dict((var, maps[var][tkey]) for var in required)

                xraw = compute_source(a.xsource, t, vals, gt)
                yraw = compute_source(a.ysource, t, vals, gt)

                x = abs(xraw) if a.x_abs else xraw
                y = abs(yraw) if a.y_abs else yraw

                x = x * a.x_scale + a.x_offset
                y = y * a.y_scale + a.y_offset

                row = {
                    "Step": sname,
                    "StepOrder": order[sname],
                    "PointIndex": point_index,
                    "StepTime": t,
                    "GlobalTime": gt,
                    "XSource": a.xsource,
                    "YSource": a.ysource,
                    "XRaw": xraw,
                    "YRaw": yraw,
                    "X": x,
                    "Y": y
                }

                for var in required:
                    row[var] = vals[var]

                rows.append(row)
                prev_global_t = gt

        outdir = os.path.dirname(os.path.abspath(a.out))
        if outdir and not os.path.exists(outdir):
            os.makedirs(outdir)

        base_cols = [
            "Step","StepOrder","PointIndex","StepTime","GlobalTime",
            "XSource","YSource","XRaw","YRaw","X","Y"
        ]
        extra_cols = [v for v in required if v not in base_cols]
        cols = base_cols + extra_cols

        with open(a.out, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            for r in rows:
                w.writerow(r)

        print("")
        print("SUCCESS")
        print("Rows:", len(rows))
        print("CSV:", a.out)
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
