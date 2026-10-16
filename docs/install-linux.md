# ODB2VTU-S — Linux 安装与 Abaqus 环境

ODB2VTU-S v0.2.1 Linux 版采用系统 Python 3 + Tkinter 作为 GUI，ODB 读写后端通过用户本机的 Abaqus Python 执行。

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

不需要手动加入 `cae -mesa`。citeturn2search0

## 启动

解压 Linux Workbench ZIP 后：

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

Linux 桌面目录通过 `xdg-user-dir DESKTOP` 获取，因此不会假定用户一定使用英文的 `~/Desktop`。citeturn3search0

## 卸载

```bash
./uninstall_clickable.sh
```

只删除 ODB2VTU-S 程序、图标和快捷方式，不删除用户的 ODB、VTU、PVD、Manifest、INP 等结果文件。

## 修改 Abaqus 命令

默认配置就是上述 CentOS 7 + Singularity + Abaqus 2024 命令。

如果以后服务器上的 Abaqus 容器路径改变，不需要修改 Python 源码，可以在启动前覆盖：

```bash
ABAQUS_CMD='singularity exec /new/path/abaqus2024.sif /opt/run_abaqus.sh' ./launch.sh
```

GUI 顶部的 **Abaqus command** 也会显示并使用该启动前缀。

## 桌面图标为什么采用这种安装方式

桌面入口使用标准 `.desktop` 文件；其 `Icon` 可以使用绝对路径指向 PNG，因此不依赖系统是否已经建立对应的图标主题缓存。citeturn0search0

同时安装器还把图标复制到用户级 hicolor 图标目录，便于 GNOME/其他兼容桌面环境通过图标名解析。

