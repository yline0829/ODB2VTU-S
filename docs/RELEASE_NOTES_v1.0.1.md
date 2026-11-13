# ODB2VTU-S v1.0.1 — Workbench UI Refresh / 工作台界面小版本更新

## 中文

本次 v1.0.1 主要更新 Windows 和 Linux 工作台的界面与交互布局，保留已有大型 ODB 有限元结果文件的选择性提取、VTU/PVD 转换、帧/变量增量更新与数据分析功能。

### 主要变化

- **Windows 新界面**：更新浅色与深色主题、绿色强调色、侧栏导航、分组面板及控件样式。
- **工作区导航**：提供 Data Export、Curve Data、Field Analysis、Friction CPFEM、Audit & Recovery 五个功能入口。
- **数据导出**：保留 Source → State → Fields → Output → Export 五步流程及选择摘要、输出消息和增量更新设置。
- **Linux 界面优化**：调整页面布局、侧栏与中英文标签，并更新安装版本信息。
- **功能延续**：已核对新版 Windows EXE 内嵌的 30 个非 GUI 资源与此前 v1.0.0 基准一致；不对核心数值处理代码进行未经验证的重构。

### 发布文件及校验

- `odb2vtu.exe`：Windows 可执行程序，SHA-256：`0e5a225c337c01a0a198ec1b5d11681c4c088eb5ee9d57cacf0b2a93778b4036`。
- `linux.zip`：Linux 工作台程序包，SHA-256：`8df6a132095d7444f99698ae3af92f6a961194ed16d6bf3db976d6bf74920968`。

以上校验值对应**本次用户上传的原始文件**。如修改了 Release 附件文件内容，需重新计算校验值。

**验证范围：** 已完成源码、资源与静态检查。Linux GUI 的语法及界面启动检查已完成；本次未在真实大型 ODB 数据环境独立复测 Windows 新版界面及全部数值处理流程。新 EXE 截图底部仍可显示历史内部版本标识 `v1.0.0`；`v1.0.1` 为本次 GitHub 发布版本号。

## English

v1.0.1 refreshes the Windows and Linux Workbench interfaces while preserving the established selective ODB-to-VTU/PVD export and post-processing workflows.

### Changes

- **Windows:** refreshed light/dark palettes, green accent colors, left workspace navigation, reorganized export panels and controls.
- **Workspace:** Data Export, Curve Data, Field Analysis, Friction CPFEM, and Audit & Recovery.
- **Data export:** retains the five-stage Source → State → Fields → Output → Export workflow, selection summary, output messages, and incremental-update controls.
- **Linux:** revised navigation, page layout, bilingual UI labels, and installer version strings.
- **Backend:** the 30 non-GUI resources embedded in the new Windows EXE match the prior v1.0.0 validated baseline.

### Release assets

- `odb2vtu.exe` — Windows executable; SHA-256: `0e5a225c337c01a0a198ec1b5d11681c4c088eb5ee9d57cacf0b2a93778b4036`
- `linux.zip` — Linux Workbench; SHA-256: `8df6a132095d7444f99698ae3af92f6a961194ed16d6bf3db976d6bf74920968`

**Validation scope:** Source, package, and static checks were performed; full Windows ODB numerical regression tests were not independently rerun in this release review. The Windows screenshot can still display historical internal version text `v1.0.0`; the GitHub Release version is `v1.0.1`.

The project requires a separate compatible, licensed environment capable of reading ODB files.
