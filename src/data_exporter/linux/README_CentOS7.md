# ODB2VTU-S Workbench v1.0.0 — CentOS 7 安装与使用说明

面向 **CentOS 7 + SingularityCE + Abaqus 2024 容器** 的 Linux 版本。
一个 Tkinter 图形界面（用系统 `python3` 运行）+ 一组 Abaqus Python 后端脚本（在 Abaqus 容器里用 `odbAccess` 运行，负责读 ODB / 导 VTU / 场分析 / CPFEM 后处理 / 安全恢复）。

```
   你的操作 ──▶ 系统 python3 + Tkinter 的 GUI（abaqus_data_exporter_gui.py）
                        │  调用：$ABAQUS_CMD python <后端脚本> <参数>
                        ▼
              Abaqus 容器（singularity exec .../abaqus2024.sif /opt/run_abaqus.sh）
                        │  odbAccess 读 ODB（只读）
                        ▼
                   VTU / PVD / CSV / 分析报告
```

---

## 1. 系统要求

| 项目 | 要求 | 自检命令 |
| --- | --- | --- |
| 操作系统 | CentOS 7.x（x86_64） | `cat /etc/redhat-release` |
| GUI 解释器 | Python **3.6+** | `python3 -V` |
| GUI 图形库 | **Tkinter**（Tk 8.5 及以上） | `python3 -c "import tkinter;print(tkinter.TkVersion)"` |
| 显示 | X11 会话（本机桌面，或 `ssh -X`） | `echo $DISPLAY` |
| 中文字体 | 文泉驿等 CJK 字体 | `fc-list :lang=zh \| head` |
| Abaqus | SingularityCE + Abaqus 2024 镜像 + 包装脚本 | `singularity --version`、`ls -l /home/soft/abaqus2024.sif` |

> GUI 只用 Python 标准库（`tkinter/pathlib/json/shlex/subprocess/threading/queue`），**不需要 numpy**；
> numpy 等只在 Abaqus 容器内的 Python 里使用。

## 2. 安装依赖（一次性，需要 root）

```bash
# CentOS 7.7 及以上（基础源已自带 python3.6）
sudo yum install -y python3 python3-tkinter

# 中文显示（不装的话界面中文会变成方框）
sudo yum install -y wqy-microhei-fonts dejavu-sans-fonts
```

更早的 CentOS 7 / 只想用 EPEL 的 python3.6：

```bash
sudo yum install -y epel-release
sudo yum install -y python36 python36-tkinter
# 之后用 PYTHON_BIN=/usr/bin/python3.6 启动（见第 5 节）
```

使用 SCL 的 python38：

```bash
sudo yum install -y centos-release-scl
sudo yum install -y rh-python38 rh-python38-python-tkinter
PYTHON_BIN=/opt/rh/rh-python38/root/usr/bin/python3 ./launch.sh
```

> 代码已按 **Python 3.6 语法**做过逐文件校验（无 f-string 以外的新语法、无 `dataclasses`/`:=`/`capture_output` 等 3.7+ 用法），3.6 及以上都能跑。

## 3. 解包与自检

```bash
tar xzf ODB2VTU-S_Workbench_Linux_v1.0.0.tar.gz
cd ODB2VTU-S_Workbench_Linux_v1.0.0
chmod +x *.sh

# 快速自检（不启动 Abaqus）
./check_env_centos7.sh

# 完整自检：额外把 abaqus_env_check.py 真的送进容器跑一遍（约 1 分钟）
./check_env_centos7.sh --deep
```

自检脚本只读、不改任何东西，逐项检查：系统、python3/tkinter 版本、DISPLAY 能否真正开窗口、CJK 字体与 UTF-8 locale、Abaqus 启动命令与镜像路径、包内文件完整性、**行尾是否 LF**、可执行位、桌面集成工具、家目录剩余空间。
退出码 `0` 表示无阻塞问题（有 WARN 也能跑），`1` 表示有 `[FAIL]` 必须先修。

**Abaqus 命令的默认值是**：`singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh`
（GUI 会调用成 `singularity exec ... /opt/run_abaqus.sh python <脚本> <参数>`）。
路径不同就用环境变量覆盖，或在 GUI 顶部的「Abaqus 命令」输入框里直接改。

## 4. 安装桌面图标与菜单项

```bash
./install_clickable.sh
```

安装位置：

| 内容 | 路径 |
| --- | --- |
| 程序本体 | `~/.local/share/odb2vtu-s/workbench/` |
| 菜单项 | `~/.local/share/applications/odb2vtu-s-workbench.desktop` |
| 图标 | `~/.local/share/icons/hicolor/{128x128,256x256}/apps/odb2vtu-s-exporter.png` |
| 桌面快捷方式 | `~/桌面/ODB2VTU-S Workbench.desktop`（或 `~/Desktop/`，脚本会自动判断） |

图标异常（显示成通用图标、任务栏出现重复图标）时执行：

```bash
./fix_desktop_icon.sh
```

卸载（**只删程序本体与启动器，不动你的 ODB/VTU/PVD/manifest/INP 文件**）：

```bash
./uninstall_clickable.sh
```

## 5. 运行

```bash
# 方式一：桌面 / 应用菜单图标
# 方式二：命令行
./launch.sh

# 指定 GUI 解释器
PYTHON_BIN=/usr/bin/python3.6 ./launch.sh

# 覆盖 Abaqus 启动命令（路径与默认不同时）
ABAQUS_CMD='singularity exec /your/path/abaqus2024.sif /your/run_abaqus.sh' ./launch.sh
```

界面要点：

- 顶部「Abaqus 命令」框 = 实际执行的后端启动命令，可临时改；
- 点「环境检查」= 等价于 `check_env_centos7.sh --deep` 只测 Abaqus 那一半；
- 每选一个 ODB，先用「读取元数据 / 读取场变量」把 Step/Frame/实例/集合列出来，再导出；
- 同一时刻只允许一个后台任务（再点会提示"已有后台任务正在运行"），日志实时滚动。

## 6. 无图形界面 / 批处理用法

后端脚本本身不需要 DISPLAY，可以直接在命令行或作业脚本里调用：

```bash
export ABAQUS_CMD='singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh'

# 1) ODB 概览（实例、单元集、Step/Frame 数）
$ABAQUS_CMD python odb_metadata.py --odb /data/model.odb --json /tmp/meta.json

# 2) 某帧的场变量清单
$ABAQUS_CMD python odb_list_fields.py --odb /data/model.odb --step Step-1 --frame -1 --json /tmp/fields.json

# 3) 单帧导出 VTU
$ABAQUS_CMD python odb_export_vtu.py --odb /data/model.odb --step Step-1 --frame -1 \
    --instance PART-1-1 --out /data/out/model_S1_f0.vtu --fields U,S

# 4) 多帧序列导出（生成 PVD + manifest）
$ABAQUS_CMD python odb_export_series.py --odb /data/model.odb --instance PART-1-1 \
    --out /data/out/model.pvd --states-file states.txt
```

各脚本的参数以 `--help` 为准（`$ABAQUS_CMD python odb_export_vtu.py --help`）。

## 7. 文件说明

| 文件 | 作用 |
| --- | --- |
| `launch.sh` | 启动器：设置 `ABAQUS_CMD` 默认值 → 用 `python3` 打开 GUI |
| `abaqus_data_exporter_gui.py` | Tkinter 图形界面（导出 / 曲线 / 场分析 / CPFEM / 安全恢复五个标签页） |
| `ui_i18n.py` | 界面中英文词条 |
| `check_env_centos7.sh` | 本次新增：环境自检 |
| `install_clickable.sh` / `fix_desktop_icon.sh` / `uninstall_clickable.sh` | 桌面图标与菜单项的安装/修复/卸载 |
| `odb_metadata.py` / `odb_list_fields.py` | 读取 ODB 元数据、场变量清单 |
| `odb_export_vtu.py` / `odb_export_series.py` | 单帧 / 多帧 VTU + PVD 导出（含 Mises、初始 IPF、GND 差值（可选 18 滑移系与/或 9 个 Burgers 方向）、滑动起点差值） |
| `odb_curve_history_meta.py` / `odb_curve_history_export.py` | 历史输出（力-位移等）曲线导出 |
| `odb_field_analysis.py` | 场变量统计分析 + 按晶粒拆分导出 |
| `abaqus_postprocess_master.py` | CPFEM 后处理主控（history / peeq 导出注入检查） |
| `diagnose_output_readonly.py` | 只读数据诊断与审计报告 |
| `odb_recovery_safe.py` | 非破坏式字段恢复（原始 ODB/VTU/PVD 一律不动） |
| `odb_legacy_migration.py` / `odb_legacy_baseline.py` / `odb_legacy_inplace.py` / `odb_manifest_adoption.py` / `odb_inplace_transaction.py` | 旧版无 manifest 数据的核对与迁移 |
| `odb_export_state.py` / `odb_export_inventory.py` / `odb_vtu_incremental.py` / `odb_export_legacy.py` | 状态清单、目录清点、增量合并等被上面脚本引用的模块 |
| `icons/` | 图标源文件（`odb2vtu-s-exporter.png` 128×128 为原件，`-256.png` 为派生件） |

## 8. 运行期文件写在哪里

GUI 的临时状态文件在 **`~/.cache/odb2vtu-s/`**（`XDG_CACHE_HOME` 优先）：
`metadata.json`、`fields.json`、`curve_metadata.json`、`selected_states.txt`、`curve_steps.txt`、`ODB2VTUS_full_audit.json`。
如果该目录不可写，会自动回退到程序目录下的 `.ade_runtime/`。
**所有导出结果（VTU/PVD/CSV/报告）只写在你指定的输出目录。**

## 9. 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| 双击图标没反应 | 文件没有可执行位：`chmod +x *.sh`；或在终端跑 `./launch.sh` 看报错 |
| 界面中文是方框 | 没装 CJK 字体：`sudo yum install -y wqy-microhei-fonts`，然后重新登录 |
| `ModuleNotFoundError: No module named 'tkinter'` | `sudo yum install -y python3-tkinter`（老源：`python36-tkinter`） |
| `bad interpreter: /usr/bin/env: bash^M` | 文件被 Windows 工具转成了 CRLF：请用 `tar` 解包（不要先在 Windows 解压再拷过去）；`check_env_centos7.sh` 会检测并报出来 |
| `python3: command not found` | 装 python3，或 `PYTHON_BIN=/usr/bin/python3.6 ./launch.sh` |
| `singularity: command not found` / 找不到镜像 | 用 `ABAQUS_CMD='...' ./launch.sh` 覆盖，或在 GUI 里改「Abaqus 命令」 |
| 环境检查里 `odbAccess: FAILED` | 容器内 Abaqus Python 不可用，或包装脚本不接受 `python <脚本>` 这种调用；先在终端手工验证：`singularity exec .../abaqus2024.sif /opt/run_abaqus.sh python abaqus_env_check.py` |
| 任务栏出现两个图标 / 图标是通用图标 | 执行 `./fix_desktop_icon.sh`；必要时 `xprop WM_CLASS` 确认为 `odb2vtu-s-workbench` |
| 桌面图标在 GNOME 里显示"不受信任" | 重新执行 `./install_clickable.sh`（脚本会设置 `metadata::trusted`）；或在图标上右键 → 允许启动 |
| 大 ODB 导出很慢 / 内存紧张 | 按 Step/Frame 分批导出，或用序列导出（会复用清单、增量合并，避免整库重算） |
| 想确认行尾/可执行位/字体等一切就绪 | `./check_env_centos7.sh` |

## 10. 版本与改动记录

### v1.0.0（本版）

1. **Linux 专属扩展：GND 的 9 个 Burgers 方向增量数组**（Windows 版没有此功能）。
   - 「GND 增量」的 DAT 差值新增输出模式：`仅18滑移系`（默认，与 Windows 一致）或 `18滑移系+9方向`；
   - 选 `18滑移系+9方向` 时后端以 `--gnd-diff-mode all` 运行，除 18 个 `DGND_Slip01-18_SDV11-28` 外，再输出 `DGND_Dir01_11m20` … `DGND_Dir09_m12m13` 共 9 个数组：
     每个方向 = 共享该 Burgers 向量的两个滑移系 SDV 之和 − `gnd_field.dat` 对应列（第 2–10 列）的初始值；
   - 增量/序列/清单校验已同步扩展（`odb_vtu_incremental.expected_derived`），因此**序列导出、增量合并、字段同步、安全恢复**都能正确处理这 9 个数组，不会把它们当成「多余数组」而报错；
   - 注意：该扩展使 `odb_export_vtu.py`、`odb_vtu_incremental.py` 与 Windows 版**不再逐字节相同**（这是有意的；其余后端文件仍逐字节一致）；
   - 滑动起点差值（`--gnd-slide-diff`）仍固定只输出 18 个滑移系。
2. 版本号统一为 **v1.0.0**（GUI 标题、安装/修复脚本提示、本说明、tar 包名与目录名）。

### v0.2.2

1. **后端脚本与 Windows 版逐字节对齐**（11 个文件），此后两端功能一致：
   - GND 模式当时统一为「18 滑移系」（该限制已在 v1.0.0 的 Linux 专属扩展中放开）：非法模式（`directions`/`all`）会**明确报错**，不再静默少输出字段（GUI 里本来也只有这一项，且界面文案早已注明不输出 9 个 Burgers 方向）；
   - 序列导出缓存 Step 对象，大模型扫描更快；
   - VTU 写盘改为分批写出 + 1 MiB 缓冲，输出字节完全不变；
   - `odb_metadata.py` 晶粒集合正则里的 `\\d` 修正为 `\d`（修正前该分支实际上永不匹配 `GRAIN_1_SET` 这类名字）；
   - 清理死代码与冗余 import（`parse_vtu_field_names`、`finite()`、未用的 `math/os/mmap/hashlib/json`）。
2. GUI 标题版本号统一为 v1.0.0；窗口 `WM_CLASS=odb2vtu-s-workbench`，`.desktop` 增加 `StartupWMClass`（避免 GNOME 任务栏出现重复/通用图标）。
3. 新增 256×256 图标（由 128×128 原件派生），使 hicolor 声明的尺寸与实际文件一致。
4. GUI 运行期文件改到 `~/.cache/odb2vtu-s/`，程序目录可只读/共享安装。
5. 新增本说明与 `check_env_centos7.sh`。

> 说明：`odb_recovery_safe.py` 内部写入恢复工作区的标记字符串 `ODB2VTUS-SAFE-RECOVERY-v0.2.1` **有意保留**，改动会导致已有恢复工作区无法续跑。

## 11. 已知限制

- GND 的 9 个 Burgers 方向增量数组是 **Linux 专属扩展**：Windows 版不输出，两端同一输出目录的清单/数组集合因此可能不同，跨平台复用同一结果目录时请重新导出。
- Tk 8.5 不能直接读 PNG，所以窗口自身不设图标，任务栏图标由 `.desktop`/`WM_CLASS` 提供。
- 同一时刻只允许一个后台任务；长任务请让终端/GUI 保持运行。
- 程序不含 Abaqus 本身；所有 ODB 读取都在你的 `$ABAQUS_CMD` 指定的环境里以**只读**方式打开。
