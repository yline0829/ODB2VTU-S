# Incremental export logic

ODB2VTU-S v0.2 introduces a two-level incremental state model for large ODB workflows.

## 1. Frame level

The frame policy controls which Step/Frame states remain active in the PVD timeline.

### Merge (default)

- Selected Step/Frame states are added or updated.
- Previously exported states that are not selected again remain active.
- Existing VTU files are never deleted implicitly.

### Sync

- The active PVD timeline is synchronized to the current Step/Frame selection.
- Previously active states that are omitted become inactive and are removed from the PVD.
- Their VTU files are retained by default.
- `Delete removed-frame VTU files` can be enabled to physically delete those files.

## 2. Field level

The field policy applies to every Step/Frame state selected in the current run.

### Merge (default)

- Previously exported native fields are preserved.
- Newly selected fields are added.
- A frame is skipped if its final field/configuration set is unchanged.
- When fields are added, the exporter attempts **field-level incremental reuse**: keep old VTU arrays, fetch only new native SDVs / changed derived families from ODB and safely rewrite the merged VTU. If reuse is unsafe, fall back to a full export.
- Not selecting an old field does **not** delete it.

Example:

```text
Existing frame: SDV11 SDV12 SDV29
Current request: SDV66 SDV88
Final frame:     SDV11 SDV12 SDV29 SDV66 SDV88
```

### Sync

- The selected frame is rebuilt to contain the current requested field/configuration set.
- Previously exported fields that are omitted from the current request are removed.
- This is the explicit variable-deletion operation.

Example:

```text
Existing frame: SDV11 SDV12 SDV29 SDV66
Current request: SDV11 SDV66
Final frame:     SDV11 SDV66
```

## 3. Two-level combinations

| Frame policy | Field policy | Meaning |
|---|---|---|
| Merge | Merge | Safest default. Add/update selected frames and add fields without deleting old frames or fields. |
| Merge | Sync | Keep all old frames, but synchronize the variables of the currently selected frames. |
| Sync | Merge | Synchronize the active frame list, while preserving existing variables within retained/selected frames. |
| Sync | Sync | Make both the active frame list and selected-frame variables match the current GUI selection. |

## 4. Manifest

Each PVD frame folder contains:

```text
_ODB2VTUS_manifest.json
```

The manifest records:

- ODB path
- instance
- element region / bounding box
- Step/Frame identity
- stable VTU filename
- active/inactive state
- native field set
- derived-field configuration
- ODB size/mtime revision

This replaces the old single export-signature mechanism.

## 5. VTU discovery and filename identity

Before generating any new VTU name, the exporter scans the target `*_frames` directory and reads existing PVD/manifest metadata. It matches files against **the exact ODB Step name and zero-based Frame index**.

- Previously exported files **keep their existing filename**, including older `<stem>_000001_<step>_f000020.vtu` names.
- The leading six-digit `000001` in a legacy name is an **export serial number**, NOT the Abaqus frame number. The final `f000020` encodes the actual Frame index in its Step.
- New Step/Frame states are assigned an unoccupied serial using the same naming convention; they cannot rename old files.
- Ambiguous/unverified selected old frames are not silently overwritten. Unselected, unindexed orphan VTUs remain on disk and are not automatically added to the PVD.

## Performance path for existing frames (v0.2.0 optimized build)

An unchanged Step/Frame is still skipped immediately.

When only some fields are new, the exporter reads the old VTU field headers, validates the stored ODB provenance and verifies that the source geometry is identical. It then:
1. extracts only newly requested fields or changed derived groups from ODB,
2. streams unchanged DataArray payloads directly from the previous VTU,
3. merges old and new arrays into a temporary complete VTU,
4. atomically replaces the old VTU only after the merge succeeds.

No full XML document or all existing array values are loaded into RAM. The mesh and VTU file format stay unchanged. An unsupported/invalid VTU is instead safely regenerated in full.

DAT GND, initial IPF and fixed sliding reference data are now cached across frames for a single export run. The same 18 SDV11–28 fields are shared when DAT and sliding GND differences are both requested.

### First-time export versus repeated export

| Mode in console | When used | Work performed |
|---|---|---|
| `unchanged` | No required difference in selected frame's recorded output | Skip VTU processing |
| `INCREMENTAL` | Existing compatible VTU, some new native fields / changed derived groups | Reuse unchanged arrays and compute only the delta |
| `FULL` | First export or unsafe/incompatible reuse | Read and write the complete target field set |

The same-run cache of GND DAT, Initial IPF and reference-frame data and the batched ASCII VTU writer benefit both `INCREMENTAL` (when recomputation is needed) and `FULL` paths.

**Observed case (2026-10-15):** a user-reported incremental export took ~45 s/frame after optimization versus ~242 s/frame previously (about 5.4× faster, ~81% less elapsed time). The user verified output data; **this does not establish the runtime for new `FULL` exports**.

### Repeated export: selecting only newly needed fields

With **Field Merge** enabled, an existing frame with `SDV11`, `SDV12`, `Initial IPF` and two GND difference families retains all those fields if a later request selects only `SDV66` and `SDV77`. Previously computed IPF/GND groups need **not** be rechecked, and their original INP/DAT inputs need not be provided when no recomputation is requested.

**Do not confuse omitting a checkbox with deleting its field:** omission is a no-op for existing fields under **Field Merge**; under **Field Sync** omission explicitly removes that native or derived field from selected frames. **Frame Sync** independently removes unselected frames from the *active PVD time series* (not physical VTU storage unless cleanup is separately enabled).


## 6. Atomic updates

- A changed VTU is first written to `*.tmp`.
- The old VTU is replaced only after the new file is complete.
- The PVD is rebuilt only after all selected frame updates succeed.
- The manifest is committed last.

Individual VTU replacements are atomic; the active PVD and manifest are updated at the end of a successful batch. **The manifest is not checkpointed after every frame**: interrupting a batch may leave already updated VTUs ahead of the last committed manifest, and a later run may have to validate/rebuild them. Back up the original dataset before large updates and do not run concurrent writers to the same output directory.

## 7. Single-frame VTU

Single-frame export uses the same field policy through a sidecar manifest:

```text
<output>.vtu.odb2vtus.json
```

- Merge preserves existing fields and adds new fields.
- Sync rebuilds the VTU to match the current requested field set.

## 8. Derived fields

Derived fields are managed by logical output family.

- Mises
- Initial IPF
- GND difference
- sliding-reference GND difference
- target-reference difference

In Merge mode, an unrequested existing derived family is preserved. If the same derived family is requested with changed parameters, that logical output is recomputed using the new configuration.
