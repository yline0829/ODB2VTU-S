# ODB2VTU-S v1.0.0 — Release Notes / 发布说明

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
