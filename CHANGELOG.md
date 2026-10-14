# Changelog

All notable changes will be documented in this file.

### Performance optimization (same v0.2.0 test version)
- Changed-frame Field Merge now uses the existing VTU arrays and reads only newly requested SDV/derived families from the ODB, provided that source identity, ODB revision, mesh and field provenance are compatible.
- Old VTU arrays are transferred into the new file by bounded-memory, memory-mapped streaming; unchanged arrays are not recomputed from the ODB.
- Reused the parsed GND DAT, Initial IPF, scalar-difference reference and sliding GND reference across frames during one series run.
- When both GND difference modes are enabled, SDV11–28 is read once per frame and shared.
- Reduced ASCII VTU output overhead by batching writes; removed unused GND direction maps in slips-only mode.
- Added per-frame INCREMENTAL/FULL completion timing and derived/cache regression tests.
- The final VTU is still safely replaced as one file after successful generation; unchanged frames are skipped entirely.
- If geometry or existing VTU data cannot be validated, the exporter falls back to the original safe full-frame export.

## [0.2.0] - 2026-10-14

### Bug fix — extra VTU inventory (2026-10-15)
- Fixed an overly strict validation that aborted an otherwise valid 52-frame export when the output folder held 10 additional, unindexed VTU states without trusted export metadata.
- Unindexed and unselected extra VTUs are now preserved on disk but excluded from the active PVD and current manifest.
- Selected frames and PVD-indexed files still require trustworthy provenance; no automatic deletion or unsafe overwrite.
- Added regression tests for both the non-blocking extra-VTU case and fail-safe rejection of a selected unverified VTU.

### Fixed (folder inventory and Windows progress)
- Scan existing VTU filenames in the output frame folder before generating any new names.
- Identify existing frames by original ODB Step name and Frame index, not by the six-digit export-list sequence.
- Keep existing VTU names and allocate collision-free sequential numbers only for genuinely new frames.
- Prefer already indexed PVD files over stale Manifest filename records; refuse ambiguous/unverified legacy datasets rather than silently overwriting them.
- Add Windows CMD startup banner, running reminder, field-read/write progress, and explicit success/failure status to prevent mistaking long ODB processing for a frozen application.
- Add mocked-ODB regression tests for incremental skip, added frames, field merge, duplicates and invalid files.

### Fixed (legacy compatibility)
- **Legacy VTU adoption:** v0.1.x exports listed under the original PVD and backed by a matching export signature are recognized as existing Step/Frame states without copying or renaming the VTU files.
- Existing frames preserve their legacy filenames during skip or field updates; stable v0.2 naming is used only for newly exported frames.
- Invalid/unverified legacy files do not silently overwrite an existing PVD.
- VTU and manifest replacements now use `os.replace` to avoid unlink-before-rename loss.
- Physical cleanup of removed frames runs only after a successful PVD/manifest update.

### Added
- Two-level incremental export model for **frames** and **fields**.
- Frame policy:
  - **Merge**: add/update selected frames while retaining previously active frames.
  - **Sync**: synchronize the active PVD timeline to the current Step/Frame selection.
- Field policy:
  - **Merge**: preserve existing variables and add newly selected variables.
  - **Sync**: rebuild selected frames to match the current variable selection, enabling explicit field deletion.
- Per-export JSON manifest for PVD time series: `_ODB2VTUS_manifest.json`.
- Single-frame sidecar manifest: `<output>.vtu.odb2vtus.json`.
- Stable, collision-resistant VTU filenames based on Step identity + Frame index.
- Optional physical cleanup of VTU files removed by Frame Sync.
- Linux and Windows GUI controls for Frame/Field Merge/Sync policies.

### Changed
- PVD files are rebuilt only after all selected frame updates succeed.
- Changed VTUs are written through a temporary file and atomically replace the previous VTU.
- Repeated exports now use manifest state rather than a single global export signature.
- Default behavior is non-destructive: omitted old frames/fields are preserved unless Sync is explicitly selected.

### Fixed
- Adding a variable to an already exported frame no longer removes variables exported previously.
- Adding/removing frames no longer depends on selection-order sequence numbers in VTU filenames.
- Reordering or inserting selected frames no longer creates a cascade of duplicate frame files.


## [0.1.2] - 2026-10-07

### Added
- Dedicated application icons for **ODB2VTU-S Exporter** and **ODB2VTU-S CPFEM Postprocessor**.
- Linux Exporter vertical scrolling and mouse-wheel support for smaller displays.

### Changed
- Linux installer now installs and assigns separate desktop icons to the two applications.
- Release builder now includes application icon assets in Windows and Linux packages.


## [0.1.1] - 2026-10-07

### Changed
- Project branding standardized as **ODB2VTU-S** (`S = Selective`).
- Application names standardized as **ODB2VTU-S Exporter** and **ODB2VTU-S CPFEM Postprocessor**.
- Automatic output directory renamed from `ADE_Output` to `ODB2VTU_Output`.
- Windows launchers, Linux desktop entries, installer paths, and release asset names aligned with the ODB2VTU-S naming scheme.
- Repository links updated after the repository was renamed to `yline0829/ODB2VTU-S`.

### Fixed
- Mouse-wheel page scrolling no longer hijacks Listbox/Text/Combobox/Entry controls in the Linux GUI; interactive selection widgets now retain their own wheel behavior.

### Added
- Linux Exporter now includes a dedicated **Selection Summary** panel showing ODB, instance/region, selected Step/Frame states, fields, derived fields, and output path.
- Linux Exporter now includes a dedicated **Output Messages** panel with clear-log control.
- Real-time Linux backend logging via `PYTHONUNBUFFERED=1`.
- Explicit success/failure dialogs for VTU/PVD export, Curve Data export, and Field Analysis.
- Scrollable Linux panels for smaller displays (ODB → VTU/PVD, Curve Data, and Field Analysis).
- Dedicated desktop icons: ODB→VTU visualization for **Exporter** and a curve-analysis icon for **CPFEM Postprocessor**.

## [0.1.0] - 2026-10-06

### Added
- First public source release.
- Cross-platform ODB2VTU-S Exporter (original v0.1.0 name: Abaqus Data Exporter).
- Selective VTU/PVD export and large-ODB frame selection.
- GrainID, Mises, Initial HCP-Ti IPF, and field-extremum analysis.
- 18-slip-system GND differences from DAT initial state and sliding-start reference state.
- Cross-platform RP history and PEEQCP postprocessor.
- Q5 StepTime target schedule: indentation first/last; sliding T0/T25/T50/T75/T100.
- PEEQCP target-frame write-back and validation.
- Linux live progress logging.
