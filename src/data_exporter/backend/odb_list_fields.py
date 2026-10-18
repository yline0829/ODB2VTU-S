# -*- coding: utf-8 -*-
from __future__ import print_function
import sys, json, argparse, traceback
from odbAccess import openOdb

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--odb", required=True)
    p.add_argument("--step", required=True)
    p.add_argument("--frame", required=True, type=int)
    p.add_argument("--json", required=True)
    a = p.parse_args()

    odb = None
    try:
        print("Opening ODB (read-only):", a.odb)
        odb = openOdb(a.odb, readOnly=True)

        if a.step not in odb.steps:
            raise RuntimeError("Step not found: %s" % a.step)

        step = odb.steps[a.step]
        if a.frame < 0 or a.frame >= len(step.frames):
            raise RuntimeError("Frame out of range: %d" % a.frame)

        frame = step.frames[a.frame]
        out = []

        for name in sorted(frame.fieldOutputs.keys()):
            fo = frame.fieldOutputs[name]
            try:
                desc = str(fo.description)
            except Exception:
                desc = ""
            try:
                comps = list(fo.componentLabels)
            except Exception:
                comps = []
            positions = []
            try:
                for loc in fo.locations:
                    positions.append(str(loc.position))
            except Exception:
                positions = []
            out.append({
                "name": str(name),
                "description": desc,
                "components": comps,
                "positions": positions
            })

        with open(a.json, "w") as f:
            json.dump({
                "step": a.step,
                "frame": a.frame,
                "fields": out
            }, f, indent=2)

        print("Fields found:", len(out))
        print("Field list saved:", a.json)
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
