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
- A frame is rebuilt atomically if new fields or updated derived-field settings are required.
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

## 5. Stable VTU names

Frame VTU files no longer depend on their position in the current selection list.

A Step/Frame state always maps to a stable name containing:

- sanitized Step name
- short SHA-1 identity
- frame index

Therefore adding a frame before an existing state does not rename or duplicate every later VTU.

## 6. Atomic updates

- A changed VTU is first written to `*.tmp`.
- The old VTU is replaced only after the new file is complete.
- The PVD is rebuilt only after all selected frame updates succeed.
- The manifest is committed last.

This prevents a failed second export from destroying a previously valid PVD/VTU set.

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
