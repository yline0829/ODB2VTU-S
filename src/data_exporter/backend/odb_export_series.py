# -*- coding: utf-8 -*-
from __future__ import print_function

import os, sys, argparse, traceback
from xml.sax.saxutils import escape
from odbAccess import openOdb

from odb_export_vtu import parse_bbox, selected_elements, export_frame
from odb_export_legacy import _read_legacy_signature, _signature_spec
from odb_export_inventory import scan_vtu_directory, allocate_vtu_name, _pvd_filenames
from odb_export_state import (
    atomic_replace, atomic_write_json, export_kwargs_from_spec,
    load_manifest, make_output_spec, merge_output_specs, new_manifest,
    output_spec_equal, same_source_identity, source_identity, source_revision,
    stable_vtu_name, state_key
)


MANIFEST_NAME = "_ODB2VTUS_manifest.json"


def read_selection_file(path):
    rows = []
    with open(path, "r", encoding="utf-8-sig") as f:
        for lineno, line in enumerate(f, 1):
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            parts = s.split("\t")
            if len(parts) != 2:
                raise RuntimeError("Invalid selection line %d. Expected StepName<TAB>FrameIndex." % lineno)
            rows.append((parts[0], int(parts[1])))
    return rows


def write_pvd(path, datasets):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write('<?xml version="1.0"?>\n')
        f.write('<VTKFile type="Collection" version="0.1" byte_order="LittleEndian">\n')
        f.write('  <Collection>\n')
        for t, rel in datasets:
            f.write('    <DataSet timestep="%.16g" group="" part="0" file="%s"/>\n' %
                    (float(t), escape(rel.replace("\\", "/"))))
        f.write('  </Collection>\n')
        f.write('</VTKFile>\n')
    atomic_replace(tmp, path)


def step_offsets(odb, step_names):
    offsets = {}
    t = 0.0
    for name in step_names:
        offsets[name] = t
        st = odb.steps[name]
        if len(st.frames):
            t += float(st.frames[-1].frameValue)
    return offsets


def current_output_spec(a, fields):
    return make_output_spec(
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


def export_with_spec(odb, instance_name, step_name, frame_index, out_path,
                     spec, element_set, bbox, mesh_cache):
    k = export_kwargs_from_spec(spec)
    return export_frame(
        odb, instance_name, step_name, frame_index, out_path, k["fields"],
        element_set, bbox, k["delta_field"], k["ref_step"], k["ref_frame"],
        mesh_cache=mesh_cache, ref_cache=None,
        derived_mises=k["derived_mises"],
        initial_ipf=k["initial_ipf"],
        inp_path=k["inp_path"], ipf_dir=k["ipf_dir"], ipf_cache=None,
        gnd_diff=k["gnd_diff"], gnd_dat=k["gnd_dat"],
        gnd_diff_mode=k["gnd_diff_mode"], gnd_cache=None,
        gnd_slide_diff=k["gnd_slide_diff"],
        gnd_slide_ref=k["gnd_slide_ref"], gnd_slide_cache=None
    )[0]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--odb", required=True)
    p.add_argument("--instance", required=True)
    p.add_argument("--selection-file", required=True)
    p.add_argument("--out-pvd", required=True)
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

    # v0.2 state-management policies.
    # merge = non-destructive; sync = make selected scope match the current request.
    p.add_argument("--frame-policy", default="merge", choices=["merge","sync"])
    p.add_argument("--field-policy", default="merge", choices=["merge","sync"])
    p.add_argument("--cleanup-removed-frames", type=int, default=0)
    a = p.parse_args()

    odb = None
    try:
        bbox = parse_bbox(a.bbox)
        fields = [x.strip() for x in a.fields.split(",") if x.strip()]
        if a.initial_ipf and (not a.inp or not os.path.exists(a.inp)):
            raise RuntimeError("Initial IPF requires a valid INP file.")
        if a.gnd_diff and (not a.gnd_dat or not os.path.exists(a.gnd_dat)):
            raise RuntimeError("GND difference requires a valid gnd_field.dat file.")

        raw = read_selection_file(a.selection_file)
        if not raw:
            raise RuntimeError("No Step/Frame states were selected.")

        pvd = os.path.abspath(a.out_pvd)
        pdir = os.path.dirname(pvd) or os.getcwd()
        if not os.path.exists(pdir):
            os.makedirs(pdir)
        stem = os.path.splitext(os.path.basename(pvd))[0]
        frame_dir = os.path.join(pdir, stem + "_frames")
        if not os.path.exists(frame_dir):
            os.makedirs(frame_dir)

        manifest_path = os.path.join(frame_dir, MANIFEST_NAME)
        src_id = source_identity(a.odb, a.instance, a.element_set, a.bbox)
        manifest = load_manifest(manifest_path)
        if manifest is not None and not same_source_identity(manifest, src_id):
            raise RuntimeError(
                "Existing export manifest belongs to a different ODB/instance/region. "
                "Choose a different output PVD or remove the old manifest intentionally."
            )

        print("Opening ODB (read-only):", a.odb)
        sys.stdout.flush()
        odb = openOdb(a.odb, readOnly=True)
        print("ODB opened.")
        sys.stdout.flush()

        step_names = list(odb.steps.keys())
        step_index = dict((name, i) for i, name in enumerate(step_names))
        offsets = step_offsets(odb, step_names)

        unique = set()
        selected = []
        for sname, fi in raw:
            if sname not in odb.steps:
                raise RuntimeError("Selected Step not found: %s" % sname)
            st = odb.steps[sname]
            if fi < 0 or fi >= len(st.frames):
                raise RuntimeError("Selected frame out of range: %s / %d (frames=%d)" %
                                   (sname, fi, len(st.frames)))
            key = (sname, fi)
            if key not in unique:
                unique.add(key)
                selected.append(key)
        selected.sort(key=lambda x: (step_index[x[0]], x[1]))

        print("Selected states:", len(selected))
        print("Frame policy:", a.frame_policy)
        print("Field policy:", a.field_policy)

        if a.instance not in odb.rootAssembly.instances:
            raise RuntimeError("Instance not found: %s" % a.instance)
        inst = odb.rootAssembly.instances[a.instance]

        elems, node_map, grain_ids = selected_elements(inst, a.element_set, bbox)
        if not elems:
            raise RuntimeError("No elements selected.")
        elem_labels = set(int(e.label) for e in elems)
        node_labels = set(n for e in elems for n in e.connectivity)
        mesh_cache = (elems, node_map, grain_ids, elem_labels, node_labels)

        requested_spec = current_output_spec(a, fields)
        rev = source_revision(a.odb)
        if manifest is None:
            manifest = new_manifest(src_id)
        frames = manifest.setdefault("frames", {})

        print("Scanning existing VTU directory before assigning filenames ...")
        found, names_on_disk, next_serial, inventory_issues = scan_vtu_directory(
            frame_dir, stem, step_names,
            lambda name: len(odb.steps[name].frames), pvd, frames)
        for issue in inventory_issues:
            print("VTU INVENTORY WARNING:", issue)
        print("VTU files found: %d ; matched ODB frames: %d ; highest serial: %d" %
              (len(names_on_disk), len(found), next_serial))

        # The legacy signature is only valid for the same output collection
        # and element scope; it cannot prove an arbitrary renamed ODB matches.
        legacy_sig_path = os.path.join(frame_dir, "_ADE_export_signature.txt")
        legacy_sig = _read_legacy_signature(legacy_sig_path)
        legacy_spec = None
        legacy_stamp = None
        original_odb_stem = os.path.splitext(os.path.basename(a.odb))[0]
        matching_output_stem = (stem == original_odb_stem or
                                stem.startswith(original_odb_stem + "_"))
        if legacy_sig is not None and matching_output_stem:
            if (legacy_sig.get("element_set") == str(a.element_set) and
                    legacy_sig.get("bbox") == str(a.bbox)):
                legacy_spec = _signature_spec(legacy_sig)
                legacy_stamp = os.path.getmtime(legacy_sig_path)

        adopted = 0
        unverified = []
        indexed_files = _pvd_filenames(pvd)
        for key, filename in found.items():
            old = frames.get(key)
            if old is not None and old.get("file") == filename:
                continue

            # A manifest created by an earlier v0.2 build may point to a
            # missing file. Recover by scanning, not by inventing a new name.
            if old is not None and old.get("output_spec") is not None:
                old["file"] = filename
                old["active"] = True
                print("RECOVERED MANIFEST FILE: %s -> %s" % (key, filename))
                continue

            path = os.path.join(frame_dir, filename)
            # A legacy signature may have been updated by a failed export.
            # It is safe to assign its field configuration only to files
            # written no earlier than that signature and the source ODB.
            trustworthy_legacy = (
                legacy_spec is not None and legacy_stamp is not None and
                os.path.getmtime(path) + 2.0 >= legacy_stamp and
                rev.get("mtime") is not None and
                os.path.getmtime(path) + 2.0 >= float(rev["mtime"])
            )
            step_name, frame_num = key.rsplit("\t", 1)
            frames[key] = {
                "step": step_name, "frame": int(frame_num),
                "file": filename, "active": True,
                "output_spec": legacy_spec if trustworthy_legacy else None,
                "source_revision": rev if trustworthy_legacy else None,
                "inventory_discovered": True
            }
            if trustworthy_legacy:
                adopted += 1
            else:
                unverified.append(key)

        # Never silently remove unknown files from an existing PVD timeline.
        unrecognized_refs = indexed_files - set(found.values())
        if unrecognized_refs:
            raise RuntimeError(
                "Existing PVD references %d unrecognized/incomplete VTU files. "
                "The old PVD and VTU files were not changed. "
                "Examples: %s" %
                (len(unrecognized_refs), ", ".join(sorted(unrecognized_refs)[:5])))
        if unverified:
            raise RuntimeError(
                "%d existing VTU states lack trustworthy export metadata; "
                "refusing to overwrite or silently skip them. "
                "Original VTU/PVD remain untouched. Examples: %s. "
                "Use the matching original _ADE_export_signature.txt, "
                "or choose a fresh output dataset." %
                (len(unverified), ", ".join(unverified[:5])))

        if adopted:
            print("VTU INVENTORY: adopted %d legacy states; existing filenames kept." %
                  adopted)
        print("VTU INVENTORY: %d states ready for incremental export." % len(frames))
        selected_keys = set(state_key(s, f) for s, f in selected)

        # Frame-level semantics:
        # merge: current selection is added/updated; omitted old frames remain active.
        # sync : omitted old frames become inactive in the PVD.
        if a.frame_policy == "sync":
            for ent in frames.values():
                ent["active"] = False

        changed = 0
        skipped = 0

        for seq, (sname, fi) in enumerate(selected, 1):
            key = state_key(sname, fi)
            old = frames.get(key) or {}
            old_spec = old.get("output_spec")
            final_spec = merge_output_specs(old_spec, requested_spec, a.field_policy)

            # Always use the scanned on-disk name for an existing state.
            # Only genuinely new states receive an unoccupied serial.
            vtu_name = old.get("file") or found.get(key)
            if not vtu_name:
                vtu_name, next_serial = allocate_vtu_name(
                    stem, sname, fi, names_on_disk, next_serial)
                print("NEW VTU NAME:", vtu_name)
            if os.path.basename(vtu_name) != vtu_name:
                raise RuntimeError("Unsafe frame filename in export manifest: %s" % vtu_name)
            vtu_path = os.path.join(frame_dir, vtu_name)
            old_revision = old.get("source_revision")
            same_revision = (old_revision == rev)
            reusable = (
                os.path.exists(vtu_path) and os.path.getsize(vtu_path) > 0 and
                old_spec is not None and output_spec_equal(old_spec, final_spec) and
                same_revision
            )

            if reusable:
                print("[%d/%d] unchanged -> %s / frame %d" %
                      (seq, len(selected), sname, fi))
                skipped += 1
            else:
                reason = []
                if not os.path.exists(vtu_path):
                    reason.append("new frame")
                if old_spec is not None and not output_spec_equal(old_spec, final_spec):
                    reason.append("field set/config changed")
                if old_revision is not None and not same_revision:
                    reason.append("ODB revision changed")
                print("[%d/%d] exporting %s / frame %d%s" %
                      (seq, len(selected), sname, fi,
                       (" ; " + ", ".join(reason)) if reason else ""))

                tmp_vtu = vtu_path + ".tmp"
                if os.path.exists(tmp_vtu):
                    os.remove(tmp_vtu)
                sys.stdout.flush()
                mesh_cache = export_with_spec(
                    odb, a.instance, sname, fi, tmp_vtu, final_spec,
                    a.element_set, bbox, mesh_cache
                )
                atomic_replace(tmp_vtu, vtu_path)
                print("[%d/%d] completed: %s" % (seq, len(selected), vtu_name))
                sys.stdout.flush()
                changed += 1

            frame = odb.steps[sname].frames[fi]
            frames[key] = {
                "step": sname,
                "frame": int(fi),
                "frame_value": float(frame.frameValue),
                "file": vtu_name,
                "active": True,
                "output_spec": final_spec,
                "source_revision": rev,
            }

        # Rebuild the active timeline once, atomically, after all selected VTUs succeed.
        active = []
        for key, ent in frames.items():
            if not ent.get("active", True):
                continue
            sname = ent.get("step")
            fi = int(ent.get("frame", -1))
            if sname not in odb.steps or fi < 0 or fi >= len(odb.steps[sname].frames):
                print("WARNING: inactive-invalid manifest state omitted from PVD:", key)
                continue
            fpath = os.path.join(frame_dir, ent.get("file", ""))
            if not os.path.exists(fpath):
                print("WARNING: manifest VTU missing; omitted from PVD:", fpath)
                continue
            active.append((sname, fi, ent))

        active.sort(key=lambda x: (step_index[x[0]], x[1]))
        datasets = []
        last_time = None
        for sname, fi, ent in active:
            frame = odb.steps[sname].frames[fi]
            global_t = offsets[sname] + float(frame.frameValue)
            if last_time is not None and global_t <= last_time:
                eps = max(1.0e-12, abs(last_time) * 1.0e-12)
                global_t = last_time + eps
            rel = os.path.relpath(os.path.join(frame_dir, ent["file"]), pdir)
            datasets.append((global_t, rel))
            last_time = global_t

        write_pvd(pvd, datasets)
        atomic_write_json(manifest_path, manifest)

        # Explicit cleanup is attempted only after publishing PVD/manifest.
        # Failed exports can therefore never delete old referenced VTUs.
        if a.frame_policy == "sync" and bool(a.cleanup_removed_frames):
            for key in list(frames.keys()):
                ent = frames[key]
                if ent.get("active", True):
                    continue
                name = ent.get("file", "")
                if not name or os.path.basename(name) != name:
                    print("WARNING: refusing unsafe cleanup path: %s" % name)
                    continue
                fpath = os.path.join(frame_dir, name)
                try:
                    if os.path.exists(fpath):
                        os.remove(fpath)
                        print("REMOVED unused VTU: %s" % fpath)
                except OSError as ex:
                    print("WARNING: cleanup failed for %s: %s" % (fpath, ex))

        print("")
        print("SUCCESS")
        print("PVD:", pvd)
        print("Frame folder:", frame_dir)
        print("Manifest:", manifest_path)
        print("Active states:", len(datasets))
        print("Changed/rebuilt states:", changed)
        print("Unchanged/skipped states:", skipped)
        print("Open only the .pvd file in ParaView.")
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
