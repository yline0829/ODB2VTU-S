# ODB2VTU-S v1.0.1 — Linux Interface Refresh / Linux 界面小版本更新

## 中文

本次小版本更新主要针对 Linux 工作台图形界面，改进侧栏导航、页面布局和中英文显示内容。原有大型 ODB 结果文件的选择性转换、帧/变量增量更新、场变量分析及 CPFEM 后处理后端保持不变。

- 优化 Linux 工作台导航栏与页面布局。
- 完善中英文 UI 标签和切换显示。
- 将 Linux 图形界面与安装脚本的版本提示统一为 v1.0.1。
- 保留原始 ODB → VTU 图标及原有的数据保护流程。
- Windows 上传的 `odb2vtu.exe` 与已验证 v1.0.0 程序二进制完全相同：SHA-256 `bab33ff40ee8a7201628367f9b020b5736fbe880c703ca24f277fe1c55236c98`。因此 Windows 包仍使用同一已验证程序，不宣称本次重新编译了 Windows EXE。

检查情况：22 个 Linux Python 文件通过 Python 3.6 语法检查；5 个 Shell 脚本通过 Bash 语法检查；Linux Tkinter GUI 在虚拟显示环境启动成功。未在真实 ODB 模型环境重新执行完整数值结果验证。

## English

This minor update refreshes the Linux Workbench's navigation layout and bilingual labels, without modifying the validated ODB/VTU numerical backends. The original user-tested Windows executable is retained byte-for-byte; no new Windows executable build is claimed. Python, shell, and virtual-display GUI startup checks passed; numerical validation remains separate.

## Release packages

- `ODB2VTU-S_Workbench_Linux_v1.0.1.zip` — Linux application
- `ODB2VTU-S_Windows_Validated_v1.0.1.zip` — unchanged, validated Windows EXE with checksum file
