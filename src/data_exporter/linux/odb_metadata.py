# -*- coding: utf-8 -*-
from __future__ import print_function
import os, sys, json, argparse, traceback, re
from odbAccess import openOdb

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--odb", required=True)
    p.add_argument("--json", required=True)
    a = p.parse_args()
    odb = None
    try:
        print("Opening ODB (read-only):", a.odb)
        odb = openOdb(a.odb, readOnly=True)
        print("ODB opened.")

        info = {"odb": os.path.abspath(a.odb), "instances": {}, "steps": {}}

        for iname, inst in odb.rootAssembly.instances.items():
            try:
                sets = sorted(list(inst.elementSets.keys()))
            except Exception:
                sets = []
            grain_sets = [
                s for s in sets
                if re.match(r"^GRAIN[_-]?\d+(?:[_-]?SET)?$", str(s).upper())
                or (str(s).upper().startswith("GRAIN") and str(s).upper().endswith("_SET"))
            ]
            info["instances"][iname] = {
                "nodes": len(inst.nodes),
                "elements": len(inst.elements),
                "element_sets": sets,
                "grain_set_count": len(grain_sets)
            }

        for sname, step in odb.steps.items():
            info["steps"][sname] = {"nframes": len(step.frames)}
            print("Step: %s ; frames=%d" % (sname, len(step.frames)))

        with open(a.json, "w") as f:
            json.dump(info, f, indent=2)

        print("Metadata saved:", a.json)
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
