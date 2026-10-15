# ODB2VTU-S v0.2.1 / 发布说明

**中文：** 修复重复 Step/Frame 误报；以 PVD 为权威帧映射。支持无 Manifest/签名旧数据的原位 SDV 增量更新，保留原变量与文件名。支持两帧抽样快速校验、严格逐帧验证、NTFS 回滚保护及中英文统一工作台。

**English:** PVD-authoritative Step/Frame mapping avoids false duplicates from unreferenced historic VTUs. In-place incremental SDV updates preserve existing arrays and filenames. Adds fast two-sample validation, strict validation, NTFS hard-link rollback, and a bilingual unified workbench.

**Safety:** Back up datasets before in-place updates. Automated tests do not certify every real-world ODB numerical field.
