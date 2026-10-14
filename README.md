# ODB2VTU-S

### Selective Abaqus ODB to ParaView & CPFEM Post-Processing Toolkit

**English** | [简体中文](README.zh-CN.md)

[![Latest Release](https://img.shields.io/github/v/release/yline0829/ODB2VTU-S?display_name=tag&sort=semver)](https://github.com/yline0829/ODB2VTU-S/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Windows](https://img.shields.io/badge/Windows-supported-0078D6?logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-supported-FCC624?logo=linux&logoColor=black)

**Selective post-processing for large Abaqus ODB files.** Cross-platform tools for **Abaqus/CPFEM**, focused on selective ODB extraction, ParaView visualization, grain-resolved field analysis, GND evolution, tribological history data, and PEEQCP reconstruction.

> This project is independent of Dassault Systèmes. Abaqus is required to read/write ODB files; no Abaqus libraries or binaries are distributed here.

## Download

For most users, the recommended entry point is the **latest GitHub Release**:

**[Download the latest release](https://github.com/yline0829/ODB2VTU-S/releases/latest)**

Current release packages use the **ODB2VTU-S** naming scheme:

- **Windows — ODB2VTU-S Exporter**
- **Windows — ODB2VTU-S CPFEM Postprocessor**
- **Linux — Combined Tools**

The repository itself is the maintainable source tree. The latest development ZIPs can be obtained from a successful **GitHub Actions → Build packages** run; tagged release assets are distributed via **Releases**.

## Overview

The toolkit currently contains two complementary applications. The **S** in **ODB2VTU-S** stands for **Selective**, emphasizing selective access to large ODB databases:

| Application | Main purpose |
|---|---|
| **ODB2VTU-S Exporter** | Large-ODB selective ODB → VTU/PVD export, arbitrary Step/Frame field comparison, ParaView-ready fields, GrainID, Initial IPF, Mises, GND differences, grain-level extrema, and History/Curve data |
| **ODB2VTU-S CPFEM Postprocessor** | RP history extraction and frame-by-frame PEEQCP reconstruction/write-back using a physically matched StepTime sampling schedule |

## Key capabilities

### Selective ODB → VTU/PVD instead of full-database conversion

ODB2VTU-S Exporter is designed for large Abaqus ODB files. Users can select the **instance, grain/element region, Step, Frame, and Field Output** that are actually needed, then export only those states to ParaView-compatible VTU/PVD files. This avoids converting an entire multi-GB or multi-hundred-GB ODB when only a small set of physical states is required.

### Arbitrary Step/Frame time-series construction

A ParaView time series can be assembled from **arbitrary Step/Frame combinations**, not only consecutive frames. Multiple Steps can be selected together and specific frames can be added to the export schedule, which is useful for comparing equivalent physical positions across repeated friction cycles.

### Generic SDV / scalar-field difference comparison

For scalar element fields, including user-defined **SDV variables**, the exporter can calculate a target-reference difference between arbitrary stored states:

```text
DELTA_Field = Field(target Step/Frame) - Field(reference Step/Frame)
```

The reference Step and reference Frame are user-selectable. This makes it possible to compare, for example, `SDV29`, `SDV66`, `SDV104`, or another scalar element variable between selected loading/friction states and visualize the resulting difference directly in ParaView.

### Grain-aware post-processing

The toolkit reconstructs `GrainID`, supports an `<All Grains>` virtual region, correlates field extrema with grains, ranks Top-N grains, and can export only the selected extreme grains so unrelated grains are completely absent from the ParaView geometry.

### CPFEM-derived fields beyond native Abaqus output

Current model-specific derived capabilities include **Mises stress**, **Initial HCP-Ti IPF**, **18-slip-system GND evolution**, sliding-reference GND increments, and reconstructed **PEEQCP** from `Fp = SDV1–SDV9`.

### Physically matched sampling for cyclic friction

For PEEQCP comparison, the postprocessor traverses all stored frames for accumulation while saving:
- indentation/normal loading: first + last frame
- each sliding cycle: **T0 / T25 / T50 / T75 / T100 by StepTime**

If a target time is not stored exactly, the nearest actual ODB frame is selected.

> Note: the current generic field-comparison feature is a **stored-frame difference**, not continuous temporal interpolation between two frames. True time interpolation of arbitrary fields can be added as a future feature.

## Incremental frame / field updates

ODB2VTU-S v0.2 uses a two-level export policy:

- **Frame Merge** (default): selected Step/Frame states are added or updated; previously exported states remain active.
- **Frame Sync**: the active PVD timeline is synchronized to the current Step/Frame selection.
- **Field Merge** (default): existing variables in a frame are preserved and newly selected variables are added.
- **Field Sync**: selected frames are rebuilt to match the current variable selection, which is the explicit variable-deletion operation.

The safe default is therefore **Merge + Merge**: repeated export does not silently delete old frames or fields.

See [Incremental export logic](docs/incremental-export.md) for the complete state-management rules.

### Performance-optimized field updates (v0.2.0)

The current **v0.2.0 source** includes a real **field-level incremental export** path, in addition to frame-level skipping:

- `unchanged`: the selected Step/Frame has the same recorded source revision and output configuration; **no VTU rewrite**.
- `INCREMENTAL`: reuse unchanged field arrays from the existing ASCII VTU (bounded-memory streaming), read only new native SDVs or changed derived-field groups from the ODB, and safely replace the complete VTU.
- `FULL`: a brand-new frame or a frame whose existing data cannot be safely reused is exported in full. It still benefits from per-run GND/IPF/reference caching, shared GND SDV reads and batched ASCII writing.

Existing names are discovered from the output folder and matched by **ODB Step name + zero-based Frame index**; existing names remain unchanged. The leading six-digit serial in a legacy filename is an *export-file number*, not the ODB frame index. New frames receive an unused serial.

For **subsequent SDV additions**, use **Frame Merge + Field Merge**, select the target frames and **only the new SDVs**. Previously exported native fields, Initial IPF and GND differences remain in the VTU even if they are **not selected again**. If a derived-field family is explicitly requested with changed parameters, that family is recomputed. **Field Sync** instead removes previously exported fields/derived families that are not currently selected. **Frame Sync** narrows the active PVD timeline to only the selected frames, independent of the field policy.

**Measured incremental case (user validation, 2026-10-15):** approximately **242 s/frame before optimization** versus **45 s/frame after optimization** for a previously exported friction/CPFEM model while adding SDVs (about **5.4× faster**, **81% less elapsed time**). Output fields were checked by the user. These are workload-specific, **not a benchmark for the first-time `FULL` export**, whose performance has not been measured here.

The exporter still writes complete VTU files safely; it does **not** modify the interior of an existing VTU in place. Large new exports remain dependent on ODB data volume, field counts and disk performance. Do not run two exporters against the same PVD concurrently. Back up existing VTU/PVD/manifest outputs before testing a new build.

See [incremental export implementation and limitations](docs/incremental-export.md).

## Screenshots

### 1. ODB2VTU-S Exporter

Select an ODB, instance, grain region, analysis steps, frames, and output variables. Multi-step ParaView time-series export supports arbitrary Step/Frame states without converting the entire ODB.

<p align="center">
  <img src="docs/images/odb2vtu-s-exporter.png" width="95%" alt="ODB2VTU-S Exporter">
</p>

### 2. ODB2VTU-S CPFEM Postprocessor

The CPFEM utility handles RP history data and PEEQCP reconstruction. PEEQCP is accumulated through all stored frames while selected physical states are retained for comparison and optional write-back.

<p align="center">
  <img src="docs/images/odb2vtu-s-cpfem-postprocessor.png" width="72%" alt="ODB2VTU-S CPFEM Postprocessor">
</p>

### 3. ParaView — reconstructed PEEQCP

Exported PVD/VTU data can be opened directly in ParaView. The example below shows the reconstructed PEEQCP field in a friction/CPFEM model.

<p align="center">
  <img src="docs/images/paraview-peeqcp.png" width="95%" alt="ParaView PEEQCP visualization">
</p>

### 4. ParaView — initial crystallographic orientation

ODB2VTU-S Exporter can reconstruct the initial grain orientation from per-grain material Euler angles in the INP and export an HCP-Ti IPF-related field for ParaView visualization.

<p align="center">
  <img src="docs/images/paraview-initial-ipf.png" width="95%" alt="ParaView initial IPF visualization">
</p>

## Applications

### ODB2VTU-S Exporter

- Selective ODB → **VTU/PVD** export for ParaView
- Large-ODB workflow: read only selected instances, sets, steps, frames, and fields
- `GrainID` reconstruction and `<All Grains>` selection
- Derived **von Mises stress**
- **Initial HCP-Ti IPF** from per-grain material Euler angles in the INP
- Field extrema / grain correlation analysis
- Top-N / extreme-band grain-only VTU export
- History/curve CSV export
- 18-slip-system GND evolution from `gnd_field.dat` vs. `SDV11–SDV28`
- Sliding-start GND increment using the first sliding frame or the previous step's last frame as reference

### ODB2VTU-S CPFEM Postprocessor

- RP history extraction: `U1/U2`, `RF1/RF2`, `CF1/CF2`, COF
- Frame-by-frame PEEQCP reconstruction from `Fp = SDV1–SDV9`
- Target-state saving:
  - indentation/normal-loading step: first + last frame
  - each sliding cycle: **T0/T25/T50/T75/T100 by StepTime**
- Nearest actual ODB frame is selected when a target StepTime is not stored exactly
- PEEQCP can be written back to those selected ODB frames
- Linux live progress logging and completion notifications

## Repository layout

```text
src/
  data_exporter/
    backend/     # Abaqus-Python ODB backends
    windows/     # PowerShell/WPF GUI
    linux/       # Python/Tk GUI
  postprocess/
    backend/     # history + PEEQCP backend
    windows/     # PowerShell GUI
    linux/       # Python/Tk GUI
packaging/linux/ # desktop installer/uninstaller
scripts/         # release builder
docs/            # methods and installation notes
examples/        # small, non-proprietary examples
```

## Requirements

- A licensed Abaqus installation providing `odbAccess`
- An Abaqus command such as `abaqus` or `abq2024`
- ParaView for VTU/PVD visualization
- Windows: Windows PowerShell / WPF
- Linux GUI: Python 3 + Tkinter

For containerized Abaqus on Linux, set the GUI's **Abaqus command** to the full prefix, for example:

```bash
singularity exec /path/to/abaqus2024.sif /opt/run_abaqus.sh
```

The application appends `python <backend.py> ...` automatically.

## Important model assumptions

Some CPFEM-derived functions are model-specific. In particular, the current GND mapping assumes:

- `SDV11–SDV28` are the 18 slip-system GND densities
- `gnd_field.dat` column 1 is Abaqus element label
- columns 2–10 are nine initial GND/Burgers-direction densities
- each direction is split equally between its paired slip systems

See [docs/gnd_mapping.md](docs/gnd_mapping.md) before using the GND tools with another UMAT.

PEEQCP reconstruction assumes `SDV1–SDV9` contain `Fp` in the documented Fortran column-major mapping. See [docs/peeqcp.md](docs/peeqcp.md).

## Installation

- [Windows](docs/install-windows.md)
- [Linux](docs/install-linux.md)

For normal users, downloading a packaged asset from **Releases** is recommended.

## Build release packages

From a normal Python 3 environment:

```bash
python scripts/build_release.py
```

Generated ZIP files are written to `dist/` and are intentionally ignored by Git.

## Development status

The current development source is **v0.2.0** (frame/field Merge/Sync, on-disk VTU inventory, field-level incremental updates and reference-data caching). GitHub Release assets may lag behind the development source; verify the asset version before downloading. The legacy **v0.1.2** release added desktop icons and Linux usability improvements. Please report model/version compatibility issues through GitHub Issues.

## License

MIT License. See [LICENSE](LICENSE).
