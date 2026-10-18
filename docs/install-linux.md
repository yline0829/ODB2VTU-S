# ODB2VTU-S — Linux 安装与 Abaqus 环境

ODB2VTU-S v1.0.0 Linux 版采用系统 Python 3 + Tkinter 作为 GUI，ODB 读写后端通过用户本机的 Abaqus Python 执行。

## 适配环境

当前提供的 Linux 安装包针对已经验证的环境：

- CentOS 7
- SingularityCE
- Abaqus 2024
- Abaqus 容器：`/home/soft/abaqus2024.sif`
- 容器内启动包装器：`/opt/run_abaqus.sh`

默认 Abaqus 启动命令固定为：

```bash
singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh
```

SingularityCE 的 `exec` 语法本身就是“容器 + 要执行的命令”，因此 ODB2VTU-S 会在这个前缀后自动追加：

```text
python <backend.py> ...
```

不需要手动加入 `cae -mesa`。

## 原位增量更新

Linux 工作台与 Windows 版统一支持 **In-place update**。在 **PVD 时间序列**模式下勾选“原位增量更新已有 VTU / In-place update existing VTUs”后，程序不会创建 `MIGRATED_SAFE` 数据目录，而是在原有 `PVD + *_frames/*.vtu` 路径上执行经过预检查的增量更新。

使用原位更新时固定要求：

- Frame policy = **Merge**
- Field policy = **Merge**
- 不启用删除已移除 VTU
- 已有 PVD；首次导出不能使用原位更新
- 无 Manifest 的历史数据使用 **Fast** 或 **Strict** 兼容模式

实际写入仍采用同目录临时文件 → 完整校验 → 原子替换，并保留回滚硬链接和事务日志；因此“原位”表示**不新建数据目录、最终替换原 VTU 路径**，并不表示直接修改半写入的 XML 文件。

## 启动

解压用户提供的正式 Linux TAR（`ODB2VTU-S_Workbench_Linux_v1.0.0.tar.gz`）后：

```bash
tar -xzf ODB2VTU-S_Workbench_Linux_v1.0.0.tar.gz
cd ODB2VTU-S_Workbench_Linux_v1.0.0
```

或者使用 **v1.0.0 正式 Linux ZIP**（与用户提供的 TAR 32 个原始文件逐字节一致）：

```bash
unzip -q ODB2VTU-S_Workbench_Linux_v1.0.0.zip
cd ODB2VTU-S_Workbench_Linux_v1.0.0
```

正式 ZIP SHA-256：`6b61076701047d274ec516f8e6492c8c85e1ac789e180ba6e464e0b0d7b4f1d2`。解压包自带原始 128/256px 图标；ZIP 已保存 Shell 脚本的 Unix 可执行权限。若使用的解压工具不恢复权限，可执行 `chmod +x ./*.sh`。

进入安装目录后：

```bash
chmod +x install_clickable.sh
./install_clickable.sh
```

安装器会：

1. 安装完整统一 Workbench 到 `~/.local/share/odb2vtu-s/workbench`
2. 安装原 ODB2VTU-S Exporter 图标
3. 创建应用菜单项
4. 在用户实际 Desktop 目录创建 **ODB2VTU-S Workbench** 图标
5. 刷新用户应用数据库（系统存在 `update-desktop-database` 时）
6. 在 GNOME/GIO 可用时标记桌面启动器为可信

Linux 桌面目录通过 `xdg-user-dir DESKTOP` 获取，因此不会假定用户一定使用英文的 `~/Desktop`。

## 卸载

```bash
./uninstall_clickable.sh
```

只删除 ODB2VTU-S 安装根目录、图标和快捷方式；**请勿将用户的 ODB、VTU、PVD、Manifest、INP 数据存放在 `~/.local/share/odb2vtu-s/workbench` 安装根目录内**，因为卸载程序会删除整个安装根目录。请将项目数据保存在独立目录。

## 修改 Abaqus 命令

默认配置就是上述 CentOS 7 + Singularity + Abaqus 2024 命令。

如果以后服务器上的 Abaqus 容器路径改变，不需要修改 Python 源码，可以在启动前覆盖：

```bash
ABAQUS_CMD='singularity exec /new/path/abaqus2024.sif /opt/run_abaqus.sh' ./launch.sh
```

GUI 顶部的 **Abaqus command** 也会显示并使用该启动前缀。

## 桌面图标为什么采用这种安装方式

桌面入口使用标准 `.desktop` 文件；其 `Icon` 可以使用绝对路径指向 PNG，因此不依赖系统是否已经建立对应的图标主题缓存。

同时安装器还把图标复制到用户级 hicolor 图标目录，便于 GNOME/其他兼容桌面环境通过图标名解析。


## v1.0.0 发布基线与测试边界

用户上传的正式 Linux TAR SHA-256：`5f6287b12a5ad26245f5ebb6a0242c6c45626252545135b1f0d12bd22899aa23`。共 32 个文件；源码部署目录为 `src/data_exporter/linux/`。安装、卸载、打包和源代码语法已做静态及隔离检查，但本次尚未在真实 CentOS 7 + Abaqus 2024 容器完成 ODB 数值输出验证。

提示：正式 ZIP/TAR 和当前 GitHub `main` 均包含用户提供的原始 256×256 图标 `src/data_exporter/linux/icons/odb2vtu-s-exporter-256.png`（SHA-256：`120ba8f404b9adb08eda957b77cf2791f0543cca46c58eb5a5f0897b86412ef6`）。现有正式安装包保持不变；不要用自动回退到 128×128 图标的其他构建代替。
