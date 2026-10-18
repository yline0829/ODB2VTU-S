# ODB2VTU-S

**Selective Abaqus ODB → VTU/PVD export and CPFEM post-processing**

[English](README.md) | [简体中文](README.zh-CN.md) · [Releases](https://github.com/yline0829/ODB2VTU-S/releases) · [MIT License](LICENSE)

ODB2VTU-S is a Windows/Linux workbench for extracting selected results from large Abaqus ODB files and preparing ParaView visualizations and CPFEM analyses.

## Unified Workbench

The Windows interface follows a five-step workflow:

**1. Data Source → 2. Target States → 3. Field Variables → 4. Output → 5. Export**

The workspace provides a selection summary, output settings, execution logs, light/dark themes, and Chinese/English switching. Additional tools, including history curves, grain-level analysis, CPFEM processing, and safe recovery, are accessible from the menus.

![ODB2VTU-S exporter interface](docs/images/odb2vtu-s-exporter.png)

## Features

- **Selective export:** choose instances, element/grain sets, Steps, Frames, and fields; write ParaView-compatible VTU/PVD.
- **Incremental updates:** Frame/Field **Merge** preserves existing data by default; **Sync** explicitly aligns output with the current selection.
- **In-place mode:** optionally update existing VTUs in their original directory with validation and rollback protection.
- **Analysis:** GrainID, Mises stress, initial IPF, GND evolution, field differences, and grain ranking.
- **Post-processing:** history curves, friction-related outputs, PEEQCP reconstruction, and diagnostic/recovery tools.

## Download and requirements

**[Download v1.0.0](https://github.com/yline0829/ODB2VTU-S/releases/tag/v1.0.0)**

| Platform | Package | Requirements |
| --- | --- | --- |
| Windows | `ODB2VTU-S_Windows_v1.0.0.zip` | Windows, PowerShell/.NET, licensed Abaqus |
| Linux | `ODB2VTU-S_Workbench_Linux_v1.0.0.zip` or `.tar.gz` | Python 3 + Tkinter; designed for CentOS 7, SingularityCE, Abaqus 2024 |

The Windows package contains the original **user-tested EXE**; Linux installation, packaging, and syntax were checked independently. Running ODB operations requires your own licensed Abaqus installation with `odbAccess`. Back up important datasets before in-place updates or ODB write-back.

[Windows guide](docs/install-windows.md) · [Linux guide](docs/install-linux.md) · [Incremental export](docs/incremental-export.md) · [PEEQCP](docs/peeqcp.md) · [v1.0.0 provenance](docs/validated-v1.0.0.md)

*Independent project; not affiliated with Dassault Systèmes. No proprietary Abaqus components are distributed.*
