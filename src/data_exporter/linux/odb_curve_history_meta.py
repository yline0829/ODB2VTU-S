# -*- coding: utf-8 -*-
from __future__ import print_function
import sys, json, argparse, traceback
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

        out = {"steps": {}}

        for sname, step in odb.steps.items():
            sinfo = {"regions": {}}

            for rname, region in step.historyRegions.items():
                try:
                    desc = str(region.description)
                except Exception:
                    desc = ""

                variables = sorted([str(k) for k in region.historyOutputs.keys()])

                # Parse common Abaqus node-history names such as:
                #   Node PART-1-1.12345
                #   Node ASSEMBLY.12345
                node_label = None
                instance_name = ""
                rtxt = str(rname)

                try:
                    import re
                    m = re.search(r'Node\s+(.+?)\.(\d+)\s*$', rtxt, re.I)
                    if m:
                        instance_name = m.group(1)
                        node_label = int(m.group(2))
                except Exception:
                    pass

                sinfo["regions"][rtxt] = {
                    "name": rtxt,
                    "description": desc,
                    "variables": variables,
                    "node_label": node_label,
                    "instance_name": instance_name
                }

            out["steps"][str(sname)] = sinfo
            print("Step: %s ; history regions=%d" % (sname, len(sinfo["regions"])))

        with open(a.json, "w") as f:
            json.dump(out, f, indent=2)

        print("History metadata saved:", a.json)
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
