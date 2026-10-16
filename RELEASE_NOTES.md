# ODB2VTU-S v0.2.2 / 发布说明

**中文：** 针对 CentOS 7 / GNOME / Nautilus 桌面图标显示问题重做 Linux 安装机制：采用标准 per-user hicolor 图标主题，同时写入 GIO custom-icon 与 trusted 元数据；移除旧图标 SHA 锁定。重新安装会原地覆盖现有 Workbench，不创建迁移目录，也不触碰用户 ODB/VTU/PVD/INP 数据。

**English:** Reworked Linux desktop icon installation for CentOS 7 / GNOME / Nautilus using the standard per-user hicolor icon theme plus GIO custom-icon and trusted metadata. Removed the obsolete hard-coded icon SHA check. Reinstallation replaces the existing Workbench in place and does not create migration directories or touch user ODB/VTU/PVD/INP data.

**Safety:** Back up datasets before in-place updates. Automated tests do not certify every real-world ODB numerical field.
