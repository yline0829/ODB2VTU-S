# -*- coding: utf-8 -*-
from __future__ import print_function

import json, os, sys, argparse, traceback, time, shutil, datetime, uuid
from xml.sax.saxutils import escape
from odbAccess import openOdb

from odb_export_vtu import parse_bbox, selected_elements, export_frame
from odb_vtu_incremental import patch_spec, merge_vtu, vtu_arrays, expected_derived
from odb_export_legacy import _read_legacy_signature, _signature_spec
from odb_manifest_adoption import verify_original_manifest
from odb_legacy_migration import run as migrate_legacy
from odb_legacy_inplace import adopt_in_memory
from odb_inplace_transaction import InPlaceTransaction
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
                     spec, element_set, bbox, mesh_cache, cache_bank=None):
    """Reuse step-independent input/GND/IPF reference data across all frames."""
    k = export_kwargs_from_spec(spec)
    bank = cache_bank if cache_bank is not None else {}
    if "by_family" not in bank:
        bank["by_family"] = {}
    families = bank["by_family"]
    keys = {}
    for family in ("delta", "initial_ipf", "gnd_diff", "gnd_slide_diff"):
        val = spec.get(family)
        keys[family] = None if val is None else (
            family + ":" + json.dumps(val, sort_keys=True))
    def get_cache(family):
        key = keys[family]
        return None if key is None else families.get(key)

    result = export_frame(
        odb, instance_name, step_name, frame_index, out_path, k["fields"],
        element_set, bbox, k["delta_field"], k["ref_step"], k["ref_frame"],
        mesh_cache=mesh_cache, ref_cache=get_cache("delta"),
        derived_mises=k["derived_mises"],
        initial_ipf=k["initial_ipf"],
        inp_path=k["inp_path"], ipf_dir=k["ipf_dir"],
        ipf_cache=get_cache("initial_ipf"),
        gnd_diff=k["gnd_diff"], gnd_dat=k["gnd_dat"],
        gnd_diff_mode=k["gnd_diff_mode"], gnd_cache=get_cache("gnd_diff"),
        gnd_slide_diff=k["gnd_slide_diff"],
        gnd_slide_ref=k["gnd_slide_ref"],
        gnd_slide_cache=get_cache("gnd_slide_diff")
    )
    for family, value in zip(
            ("delta", "initial_ipf", "gnd_diff", "gnd_slide_diff"),
            result[1:]):
        if keys[family] is not None and value is not None:
            families[keys[family]] = value
    return result[0]


def _snapshot_existing(path, recovery_dir):
    """Preserve the previous version before any in-place replacement.

    Same-volume hard links cost almost no time or space, while os.replace on
    the original path leaves the linked old inode intact. On unsupported file
    systems fall back to a byte-for-byte copy, never silently skip protection.
    """
    if not os.path.isfile(path):
        return None
    if not os.path.isdir(recovery_dir):
        os.makedirs(recovery_dir)
    destination = os.path.join(recovery_dir, os.path.basename(path))
    if os.path.exists(destination):
        raise RuntimeError("Recovery backup filename collision: " + destination)
    try:
        os.link(path, destination)
        how = "hardlink"
    except (OSError, IOError):
        shutil.copy2(path, destination)
        how = "copy"
    print("RECOVERY BACKUP [%s]: %s" % (how, destination))
    return destination


def _required_arrays(spec):
    needed = set(spec.get("native_fields") or [])
    for group in expected_derived(spec).values():
        needed.update(group)
    return needed


def _assert_preservation(before_arrays, after_arrays, expected_arrays):
    missing = set(expected_arrays) - set(after_arrays)
    if missing:
        raise RuntimeError("VTU field validation failed; missing required arrays: %s" %
                           sorted(missing)[:20])
    removed = set(before_arrays) - set(after_arrays)
    if removed:
        raise RuntimeError("Field Merge would lose existing VTU arrays: %s" %
                           sorted(removed)[:20])


def prepare_compatibility_output(a):
    """On a pre-manifest PVD, make a separately verified/copying baseline.

    Never infer provenance or write to an existing legacy VTU. The returned
    PVD is under MIGRATED_SAFE, and the old collection is read-only.
    """
    target = os.path.abspath(a.out_pvd)
    if not os.path.isfile(target):
        return target
    stem = os.path.splitext(os.path.basename(target))[0]
    folder = os.path.join(os.path.dirname(target), stem + "_frames")
    metadata = load_manifest(os.path.join(folder, MANIFEST_NAME))
    if metadata is not None and metadata.get('frames'):
        return target
    if a.adopt_manifest_path:
        # Preserve explicit original-manifest import for restored datasets.
        return target
    if a.write_mode == 'in_place':
        return target  # No migration directory, adopt in memory below.
    if a.compatibility_mode == 'standard':
        return target  # Existing provenance guard remains in main().
    if a.frame_policy != 'merge' or a.field_policy != 'merge' or a.cleanup_removed_frames:
        raise RuntimeError('SAFETY STOP: legacy compatibility migration only '
                           'supports Frame Merge + Field Merge, without file deletion.')
    if not os.path.isdir(folder):
        raise RuntimeError('SAFETY STOP: legacy frame directory is missing: ' + folder)
    dest = os.path.join(os.path.dirname(target), stem + '_MIGRATED_SAFE',
                        os.path.basename(target))
    if os.path.exists(os.path.dirname(dest)):
        raise RuntimeError('SAFETY STOP: an earlier migration exists: %s. '
                           'Select its PVD directly to continue, or preserve '
                           'it and choose another source.' % dest)
    from argparse import Namespace
    request = Namespace(odb=a.odb, pvd=target, instance=a.instance,
                        element_set=a.element_set, bbox=a.bbox,
                        mode=a.compatibility_mode)
    print('[COMPATIBILITY] Old collection without Manifest; '
          'copying to independent MIGRATED_SAFE directory (mode=%s).' %
          a.compatibility_mode)
    sys.stdout.flush()
    migrate_legacy(request)  # raises if geometry, field or provenance fails
    if not os.path.isfile(dest):
        raise RuntimeError('Migration did not publish the expected PVD: ' + dest)
    print('[COMPATIBILITY] Migrated PVD: ' + dest)
    return dest


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--odb", required=True)
    p.add_argument("--instance", required=True)
    p.add_argument("--selection-file", required=True)
    p.add_argument("--out-pvd", required=True)
    p.add_argument("--write-mode", choices=("safe_copy", "in_place"), default="safe_copy",
                   help="Directly replace existing VTUs only after checked merge; no MIGRATED_SAFE copy.")
    p.add_argument("--compatibility-mode", default="standard",
                   choices=("standard", "fast", "strict"),
                   help="Manifest-backed standard update, automatic fast legacy copy, or strict numeric legacy copy.")
    p.add_argument("--adopt-manifest-path", default="",
                   help="Explicitly select a matching original Manifest for a restored dataset.")
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
    # Explicit confirmations, ideally supplied only after a GUI Yes/No prompt.
    p.add_argument("--confirm-frame-sync", type=int, default=0)
    p.add_argument("--confirm-field-sync", type=int, default=0)
    p.add_argument("--confirm-delete-files", type=int, default=0)
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

        # Migration is a one-way transaction on a NEW directory. Legacy originals
        # stay immutable even when a later SDV export fails. This check must
        # occur before making or opening any output dataset path.
        if a.write_mode == 'in_place':
            if a.frame_policy != 'merge' or a.field_policy != 'merge' or a.cleanup_removed_frames:
                raise RuntimeError('In-place mode requires Frame Merge + Field Merge without deletion.')
            if not os.path.isfile(a.out_pvd):
                raise RuntimeError('In-place mode requires an existing PVD; refusing first export.')
        a.out_pvd = prepare_compatibility_output(a)
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
        # Restored datasets may contain intact PVD/VTU files but lack the
        # v0.2 manifest. Never guess their provenance. A user-supplied
        # original manifest can be adopted only after EVERY published frame
        # and EVERY expected field passes a read-only verification.
        if a.adopt_manifest_path:
            if manifest is not None and manifest.get("frames"):
                raise RuntimeError(
                    "Current output directory already has a valid populated "
                    "Manifest; original-manifest adoption is unnecessary.")
            manifest, verified_count = verify_original_manifest(
                a.adopt_manifest_path, manifest_path, pvd, frame_dir,
                src_id, rev)
            print("VERIFIED ORIGINAL MANIFEST: %d PVD states and their VTU "
                  "fields validated; source metadata adopted IN MEMORY." %
                  verified_count)
            sys.stdout.flush()
        if (manifest is None and a.write_mode == 'in_place' and
                not a.adopt_manifest_path):
            if a.compatibility_mode == 'standard':
                raise RuntimeError('In-place legacy adoption requires Fast or Strict compatibility.')
            manifest = adopt_in_memory(a, odb, bbox, mesh_cache, rev)
        if manifest is None:
            manifest = new_manifest(src_id)
        frames = manifest.setdefault("frames", {})

        print("Scanning existing VTU directory before assigning filenames ...")
        found, names_on_disk, next_serial, inventory_issues = scan_vtu_directory(
            frame_dir, stem, step_names,
            lambda name: len(odb.steps[name].frames), pvd, frames)
        for issue in inventory_issues:
            print("VTU INVENTORY INFO:" if issue.startswith('PRESERVED UNREFERENCED') else "VTU INVENTORY WARNING:", issue)
        # A filename preference is not a data-preservation decision: same
        # Step/Frame may have two versions with DIFFERENT field arrays.
        # Never silently choose one, or overwrite the only rich-field copy.
        # If the published PVD is unambiguous, only its refs are eligible.
        # Duplicates in *unreferenced historical* VTUs are diagnostic notes,
        # never blockers. Real PVD duplicates fail in _published_pvd_states().
        duplicates = [issue for issue in inventory_issues
                      if issue.startswith("Duplicate files for one ODB Step/Frame:")]
        if duplicates:
            raise RuntimeError(
                "AMBIGUOUS EXISTING FRAMES: %d Step/Frame state(s) have multiple "
                "VTU files. No files or PVD were modified. Back up this folder "
                "and reconcile the duplicates before exporting. Examples: %s" %
                (len(duplicates), " | ".join(duplicates[:4])))
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
        ignored_orphans = []
        selected_keys = set(state_key(s, f) for s, f in selected)
        indexed_files = _pvd_filenames(pvd)
        for key, filename in found.items():
            old = frames.get(key)

            # A folder may contain complete VTUs from a previous interrupted
            # run which were never published in the PVD or manifest. They are
            # *not* proof of a reusable frame, but also must not block unrelated
            # selected frames. Leave them untouched and out of the PVD.
            if (key not in selected_keys and filename not in indexed_files and
                    old is None):
                ignored_orphans.append((key, filename))
                continue

            if old is not None and old.get("file") == filename:
                continue

            # If an old manifest points at a different file, its field
            # metadata cannot be transplanted to this discovered VTU.
            # The selected on-disk file must be independently verified.
            if old is not None:
                print("MANIFEST RECONCILIATION: %s ; recorded %s ; found %s" %
                      (key, old.get("file"), filename))

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
                "Expected metadata at: %s. For a restored/copied dataset, "
                "choose the ORIGINAL matching _ODB2VTUS_manifest.json via "
                "--adopt-manifest-path (the program verifies all PVD frames "
                "and actual VTU arrays before reuse); otherwise choose a "
                "fresh output dataset." %
                (len(unverified), ", ".join(unverified[:5]), manifest_path))

        if adopted:
            print("VTU INVENTORY: adopted %d legacy states; existing filenames kept." %
                  adopted)
        if ignored_orphans:
            print("VTU INVENTORY: ignoring %d unindexed, unselected extra VTU "
                  "state(s); files remain on disk." % len(ignored_orphans))
            for key, filename in ignored_orphans[:10]:
                print("  PRESERVED EXTRA (not imported): %s / %s" % (key, filename))
            if len(ignored_orphans) > 10:
                print("  ... and %d more." % (len(ignored_orphans) - 10))
        print("VTU INVENTORY: %d states ready for incremental export." % len(frames))

        previous_active = [k for k, ent in frames.items()
                           if ent.get("active", True)]
        removed_frame_keys = sorted(set(previous_active) - selected_keys)
        if a.frame_policy == "sync" and removed_frame_keys and not a.confirm_frame_sync:
            raise RuntimeError(
                "SAFETY STOP: Frame Sync would remove %d previously active "
                "Step/Frame(s) from the PVD (e.g. %s). Use Frame Merge to "
                "retain them, or explicitly confirm Frame Sync in the GUI." %
                (len(removed_frame_keys), ", ".join(removed_frame_keys[:3])))
        if a.cleanup_removed_frames and not a.confirm_delete_files:
            raise RuntimeError(
                "SAFETY STOP: deleting old VTU files requires a second explicit "
                "confirmation. Disable Delete removed VTUs to keep all originals.")
        if a.field_policy == "sync" and not a.confirm_field_sync:
            # Sync can remove fields, including when user accidentally selects
            # only a few new SDVs; ask once, before touching any existing file.
            needs_confirmation = any(
                frames.get(k, {}).get("output_spec") is not None
                for k in selected_keys)
            if needs_confirmation:
                raise RuntimeError(
                    "SAFETY STOP: Field Sync may remove existing SDVs, IPF and GND "
                    "fields. Use Field Merge to add SDVs, or explicitly confirm "
                    "Field Sync in the GUI.")

        # In-place mode uses same-directory zero-copy hard-link rollback aliases
        # plus a journal. No migration directory and no full-size backup copy.
        transaction = None
        recovery_dir = None
        if a.write_mode == 'in_place':
            transaction = InPlaceTransaction(frame_dir)
            transaction.start()
            transaction.protect(pvd)
            transaction.protect(manifest_path)
        else:
            recovery_dir = os.path.join(
                frame_dir, "_ODB2VTUS_recovery",
                datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:10])
            _snapshot_existing(pvd, recovery_dir)
            _snapshot_existing(manifest_path, recovery_dir)

        # Frame-level semantics:
        # merge: current selection is added/updated; omitted old frames remain active.
        # sync : omitted old frames become inactive in the PVD.
        if a.frame_policy == "sync":
            for ent in frames.values():
                ent["active"] = False

        changed = 0
        skipped = 0
        incremental = 0
        cache_bank = {}

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
            # Reject external mutations between legacy precheck and streaming
            # merge. A timestamp/size mismatch is not safe to overwrite.
            if (transaction is not None and 'adoption_original_size' in old and
                    os.path.isfile(vtu_path)):
                current_stat = os.stat(vtu_path)
                if (current_stat.st_size != old['adoption_original_size'] or
                        current_stat.st_mtime != old['adoption_original_mtime']):
                    raise RuntimeError('VTU was changed after in-place preflight: ' + vtu_path)
            old_revision = old.get("source_revision")
            same_revision = (old_revision == rev)
            reusable = (
                os.path.exists(vtu_path) and os.path.getsize(vtu_path) > 0 and
                old_spec is not None and output_spec_equal(old_spec, final_spec) and
                same_revision
            )

            if reusable:
                # The manifest is metadata, not proof that the corresponding
                # arrays survived an earlier interrupted or buggy export.
                actual = set().union(*vtu_arrays(vtu_path))
                missing = _required_arrays(final_spec) - actual
                if missing:
                    print("WARNING: manifest says unchanged but VTU lacks: %s" %
                          sorted(missing)[:20])
                    reusable = False
                else:
                    print("[%d/%d] unchanged -> %s / frame %d" %
                          (seq, len(selected), sname, fi))
                    skipped += 1
            if not reusable:
                t_start = time.time()
                valid_old = (old_spec is not None and same_revision and
                             os.path.isfile(vtu_path) and
                             os.path.getsize(vtu_path) > 0)
                tmp_vtu = vtu_path + ".tmp"
                patch_vtu = vtu_path + ".fields.tmp"
                for leftover in (tmp_vtu, patch_vtu):
                    if os.path.exists(leftover):
                        os.remove(leftover)

                # Never FULL-overwrite an existing VTU based on an incomplete
                # manifest or changed ODB: older fields might be irreplaceable.
                if os.path.isfile(vtu_path) and not valid_old:
                    raise RuntimeError(
                        "SAFETY STOP: existing VTU cannot be safely reused "
                        "(missing provenance or ODB revision changed): %s. "
                        "Original VTU/PVD remain intact; use a NEW output path "
                        "for a full re-export." % vtu_name)
                patched = False
                before_names = set()
                if valid_old:
                    try:
                        point_names, cell_names = vtu_arrays(vtu_path)
                        present = point_names | cell_names
                        before_names = set(present)
                        delta_spec, keep, need_delta = patch_spec(
                            old_spec, final_spec, present,
                            preserve_existing=(a.field_policy == "merge"))
                        # Existing fields are copied from the existing VTU;
                        # only missing/altered fields are extracted from ODB.
                        # ODB/geometry changes bypass this fast path entirely.
                        print("[%d/%d] INCREMENTAL %s / frame %d: %d existing array(s), "
                              "%d new native field(s), derived updates=%s" % (
                                  seq, len(selected), sname, fi, len(present),
                                  len(delta_spec["native_fields"]),
                                  ",".join(k for k in (
                                      "mises", "initial_ipf", "gnd_diff",
                                      "gnd_slide_diff", "delta")
                                      if delta_spec.get(k)) or "none"))
                        sys.stdout.flush()
                        if need_delta:
                            mesh_cache = export_with_spec(
                                odb, a.instance, sname, fi, patch_vtu,
                                delta_spec, a.element_set, bbox, mesh_cache,
                                cache_bank)
                        merge_vtu(vtu_path,
                                  patch_vtu if need_delta else None,
                                  tmp_vtu, keep)
                        actual_after = set().union(*vtu_arrays(tmp_vtu))
                        expected_after = _required_arrays(final_spec)
                        if a.field_policy == "merge":
                            _assert_preservation(before_names, actual_after, expected_after)
                        elif expected_after - actual_after:
                            raise RuntimeError("Field Sync output is missing required fields")
                        patched = True
                    except (RuntimeError, ValueError, IOError, OSError) as ex:
                        print("WARNING: incremental reuse unavailable: %s" % ex)
                        print("         No full overwrite is permitted for existing "
                              "VTUs. Preserving original output.")
                        for leftover in (tmp_vtu, patch_vtu):
                            if os.path.isfile(leftover):
                                os.remove(leftover)
                        raise RuntimeError(
                            "SAFETY STOP: incremental update failed for existing "
                            "%s; original VTU/PVD retained. Cause: %s" %
                            (vtu_name, ex))

                if not patched:
                    print("[%d/%d] FULL EXPORT %s / frame %d" %
                          (seq, len(selected), sname, fi))
                    sys.stdout.flush()
                    mesh_cache = export_with_spec(
                        odb, a.instance, sname, fi, tmp_vtu, final_spec,
                        a.element_set, bbox, mesh_cache, cache_bank)
                # Back up the previous VTU before atomic replacement.
                if transaction is not None:
                    transaction.protect(vtu_path)
                else:
                    _snapshot_existing(vtu_path, recovery_dir)
                # Merge and export both publish only complete replacement files.
                atomic_replace(tmp_vtu, vtu_path)
                if os.path.isfile(patch_vtu):
                    os.remove(patch_vtu)
                changed += 1
                if patched:
                    incremental += 1
                print("[%d/%d] completed: %s ; mode=%s ; seconds=%.2f" % (
                    seq, len(selected), vtu_name,
                    "INCREMENTAL" if patched else "FULL",
                    time.time() - t_start))
                sys.stdout.flush()

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

        # For a pure in-place Field Merge, keep the original PVD bytes and
        # timestamps intact if its file timeline has not changed.
        publish_pvd = True
        if transaction is not None and os.path.isfile(pvd):
            from xml.etree import ElementTree as ET
            current_refs = [(x.get('file') or '').replace('\\', '/')
                            for x in ET.parse(pvd).getroot().iter('DataSet')]
            new_refs = [rel.replace('\\', '/') for _, rel in datasets]
            publish_pvd = current_refs != new_refs
        if publish_pvd:
            write_pvd(pvd, datasets)
        else:
            print('[IN-PLACE] PVD reference order unchanged; preserving original PVD bytes.')
        atomic_write_json(manifest_path, manifest)

        if transaction is not None:
            transaction.commit()
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
                        # Physical deletion must also be reversible: snapshot
                        # the excluded VTU before deleting its directory entry.
                        _snapshot_existing(fpath, recovery_dir)
                        os.remove(fpath)
                        print("REMOVED unused VTU (recovery backup retained): %s" % fpath)
                except OSError as ex:
                    print("WARNING: cleanup failed for %s: %s" % (fpath, ex))

        print("")
        print("SUCCESS")
        print("PVD:", pvd)
        print("Frame folder:", frame_dir)
        print("Manifest:", manifest_path)
        print("Active states:", len(datasets))
        print("Changed/rebuilt states:", changed)
        print("Field-level incremental states:", incremental)
        print("Unchanged/skipped states:", skipped)
        print("Open only the .pvd file in ParaView.")
        return 0
    except Exception:
        if 'transaction' in locals() and transaction is not None and transaction.open:
            try:
                transaction.rollback()
                print('IN-PLACE ROLLBACK: original files restored.')
            except Exception as rollback_error:
                print('CRITICAL: rollback incomplete; keep the journal and hardlinks:',
                      rollback_error)
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
