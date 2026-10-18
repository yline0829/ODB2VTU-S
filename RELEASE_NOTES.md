# ODB2VTU-S v1.0.0 — Release Notes / 发布说明

## v1.0.0 正式发布附件 / Release ZIP assets

| 平台 / Platform | 发布文件 / Release file | SHA-256 (ZIP) |
| --- | --- | --- |
| Windows | `ODB2VTU-S_Windows_v1.0.0.zip` | `4fd5d2a00e13b3277f9a52e063c692f98d69f6967488472a2d0520ce3ead6359` |
| Linux | `ODB2VTU-S_Workbench_Linux_v1.0.0.zip` | `6b61076701047d274ec516f8e6492c8c85e1ac789e180ba6e464e0b0d7b4f1d2` |

Windows 包含原始已验证 `odb2vtu.exe`（EXE SHA-256：`bab33ff40ee8a7201628367f9b020b5736fbe880c703ca24f277fe1c55236c98`）。Linux ZIP 由用户原始 TAR （SHA-256：`5f6287b12a5ad26245f5ebb6a0242c6c45626252545135b1f0d12bd22899aa23`）无损转换，32 个文件逐字节一致，保留 Shell 可执行权限。

The Windows package contains the unchanged, user-tested executable. The Linux ZIP faithfully reproduces the 32 files in the original user-provided TAR (including the original high-resolution icon). Neither ZIP is interchangeable with a legacy PS2EXE build or the auto-generated source archive. All three original archives have been published as GitHub v1.0.0 Release assets; GitHub's recorded asset digests match the verified SHA-256 values.

## 中文

v1.0.0 整合两个平台各自的程序基准，避免以 Windows 已验证源码覆盖 Linux 新实现。

- **Windows**：使用用户实际验证通过的原始 `odb2vtu.exe`，原件不重新编译，不修改历史内置版本信息。
- Windows EXE SHA-256：`bab33ff40ee8a7201628367f9b020b5736fbe880c703ca24f277fe1c55236c98`。
- **Linux**：采用本次提供的全新 `ODB2VTU-S_Workbench_Linux_v1.0.0.tar.gz`，面向 CentOS 7 + SingularityCE + Abaqus 2024。
- Linux TAR SHA-256：`5f6287b12a5ad26245f5ebb6a0242c6c45626252545135b1f0d12bd22899aa23`。
- Linux 包含 28 个源码/说明文件及 4 个图标；22 个 Python 文件通过 Python 3.6 语法核查，5 个 Shell 脚本通过语法核查，隔离安装/卸载检查通过。
- 两个平台的 GUI 与后端分开维护；Linux 原位更新、增量导出及 CPFEM 工作流保留原提交实现，不对数值逻辑进行未验证重写。

**验证范围**：Windows EXE 由用户实际运行验证。Linux 本次只完成静态检查、打包一致性及隔离安装/卸载测试，未在真实 Abaqus 环境执行数值计算。需要用户合法安装 Abaqus 及对应容器。

## English

v1.0.0 preserves two distinct platform baselines rather than replacing the Linux backend with the user-validated Windows backend.

- **Windows:** Original, user-tested `odb2vtu.exe` retained without recompilation (SHA-256 `bab33ff40ee8a7201628367f9b020b5736fbe880c703ca24f277fe1c55236c98`).
- **Linux:** New user-supplied `ODB2VTU-S_Workbench_Linux_v1.0.0.tar.gz` for CentOS 7, SingularityCE and Abaqus 2024 (SHA-256 `5f6287b12a5ad26245f5ebb6a0242c6c45626252545135b1f0d12bd22899aa23`).
- Linux contains 28 source/documentation and 4 icon files. Static Python 3.6 and Bash syntax validation and isolated install/uninstall tests passed.
- Windows and Linux backend source trees remain separate; numerical workflows are not silently replaced or refactored.

**Validation limits:** Windows functionality was verified by the user. This integration did not execute numerical ODB workflows in a real CentOS 7 / Abaqus installation.

## 发布状态 / Release status

- **Published:** [v1.0.0 Release](https://github.com/yline0829/ODB2VTU-S/releases/tag/v1.0.0), with verified Windows ZIP, Linux ZIP, and Linux TAR.GZ assets.
- **Source:** the exact original 256px Linux icon is now restored to the repository, with a hash integrity test.
- **Historical tag:** the published `v1.0.0` Git tag remains unchanged. Subsequent `main` updates to README screenshots and icon assets do not alter already published binaries or retroactively change the tagged source snapshot.
