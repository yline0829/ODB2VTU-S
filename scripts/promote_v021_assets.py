#!/usr/bin/env python3
"""One-time v0.2.1 source promotion from maintainer-staged release ZIP assets."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
WIN_HASH = "e255ccd2efa61c73683ea1c830f78ad84bc4857b4c3fb38ae38d3ed7a0633476"
LIN_HASH = "2d7b73db8ec2f366d34db28af56474c627b54305b10b2141fd3aef66cda62405"

def checked(path, sha):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != sha:
        raise RuntimeError("Release asset hash mismatch: " + str(path))
    return ZipFile(path)

def put(dst, data):
    file = ROOT / dst
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_bytes(data)
    print("Updated " + str(dst))

def stage(winpath, linpath):
    with checked(winpath, WIN_HASH) as win, checked(linpath, LIN_HASH) as lin:
        for name in win.namelist():
            if name.startswith("icons/"):
                continue  # existing asset SHA values were verified unchanged
            if name == "abaqus_postprocess_master.py":
                dest = "src/postprocess/backend/" + name
            elif name.startswith("odb_") and name.endswith(".py"):
                dest = "src/data_exporter/backend/" + name
            elif name.endswith((".ps1", ".cmd", ".vbs", ".json")):
                dest = "src/data_exporter/windows/" + name
            elif name == "Restore_Interrupted_InPlace_Windows.cmd":
                dest = "src/data_exporter/windows/" + name
            elif name.endswith(".py"):
                raise RuntimeError("Unrecognized Windows Python module: " + name)
            else:
                raise RuntimeError("Unrecognized Windows file: " + name)
            put(dest, win.read(name))
        for name in lin.namelist():
            if name.startswith("icons/") or name.startswith("odb_") and name.endswith(".py"):
                continue  # backends from Windows ZIP; hashes checked below
            if name == "abaqus_postprocess_master.py":
                continue
            if name in ("abaqus_data_exporter_gui.py", "abaqus_env_check.py", "ui_i18n.py", "launch.sh"):
                dest = "src/data_exporter/linux/" + name
            elif name in ("install_clickable.sh", "uninstall_clickable.sh"):
                dest = "packaging/linux/" + name
            elif name == "diagnose_output_readonly.py":
                dest = "scripts/" + name
            else:
                raise RuntimeError("Unrecognized Linux file: " + name)
            put(dest, lin.read(name))
        backends = [n for n in win.namelist() if n.startswith("odb_") and n.endswith(".py")]
        for name in backends:
            if name not in lin.namelist() or win.read(name) != lin.read(name):
                raise RuntimeError("Backend ZIPs disagree on " + name)

    put("VERSION", b"0.2.1\n")
    build = """#!/usr/bin/env python3
from pathlib import Path
import shutil, zipfile
ROOT=Path(__file__).resolve().parents[1]
VERSION=(ROOT/'VERSION').read_text().strip()
DIST=ROOT/'dist';DIST.mkdir(exist_ok=True)
for ps in (ROOT/'src/data_exporter/windows').glob('*.ps1'):
    b=ps.read_bytes()
    if not b.startswith(b'\\xef\\xbb\\xbf'):
        raise RuntimeError('Missing UTF-8 BOM: '+str(ps))
WORK=ROOT/'.build'
if WORK.exists():shutil.rmtree(WORK)
WORK.mkdir()
def cp(src,dst):
    shutil.copytree(src,dst,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
def zipout(src,name):
    with zipfile.ZipFile(DIST/name,'w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(src.rglob('*')):
            if p.is_file():z.write(p,p.relative_to(src).as_posix())
win=WORK/'ODB2VTU-S_Workbench_Windows_Portable';win.mkdir()
cp(ROOT/'src/data_exporter/windows',win)
cp(ROOT/'src/data_exporter/backend',win)
cp(ROOT/'src/postprocess/backend',win)
cp(ROOT/'assets/icons',win/'icons')
zipout(win,'ODB2VTU-S_Workbench_Windows_Portable_v%s.zip'%VERSION)
lin=WORK/'ODB2VTU-S_Workbench_Linux';lin.mkdir()
cp(ROOT/'src/data_exporter/linux',lin)
cp(ROOT/'src/data_exporter/backend',lin)
cp(ROOT/'src/postprocess/backend',lin)
shutil.copy2(ROOT/'scripts/diagnose_output_readonly.py',lin/'diagnose_output_readonly.py')
cp(ROOT/'assets/icons',lin/'icons')
for script in ('install_clickable.sh','uninstall_clickable.sh'):
    shutil.copy2(ROOT/'packaging/linux'/script,lin/script)
    (lin/script).chmod(0o755)
zipout(lin,'ODB2VTU-S_Workbench_Linux_v%s.zip'%VERSION)
"""
    put("scripts/build_release.py", build.encode("utf-8"))
    readme = ROOT / "README.md"
    old = readme.read_text(encoding="utf-8")
    heading = """## v0.2.1 — PVD-authoritative in-place incremental export

v0.2.1 is based on the user's validated rc10 workflow. For legacy PVD/VTU
datasets without Manifest or ADE signature, use Fast Compatibility,
Frame Merge + Field Merge, and the explicit In-place Update option.
Only PVD-referenced VTUs are eligible for reuse; extra historical VTUs are
preserved without causing false duplicate-frame errors.
Two representative states receive numerical ODB witness checks; other
states receive structural/mesh checks. Existing VTU DataArrays are retained.
Writes use adjacent temporary files, atomic replacement, hard-link rollback
aliases, and a transaction journal. Keep an independent data backup.
The release is independent of Dassault Systèmes; Abaqus is required to read ODBs.

"""
    if "## v0.2.1 —" not in old:
        pos = old.index("\n", old.index("# ODB2VTU-S")) + 1
        put("README.md", (old[:pos] + "\n" + heading + old[pos:]).encode("utf-8"))
    readme_cn = ROOT / "README.zh-CN.md"
    old_cn = readme_cn.read_text(encoding="utf-8")
    note_cn = """## v0.2.1 正式版 — PVD 权威帧映射与原位增量更新

以 rc10 的用户验证版为基准：只有 PVD 明确引用的 VTU 参与增量更新，未引用的历史 VTU 保留但忽略；无 Manifest、无旧版签名也可通过两帧抽样的快速兼容模式更新。
选择 Frame Merge + Field Merge 并勾选原位更新，可保留原字段和文件名，仅追加需要的 SDV。采用同目录临时文件、原子替换、NTFS 回滚硬链接和事务日志保护。首次使用请保留独立备份，真实 ODB 数值结果仍需用户验证。

"""
    if "## v0.2.1 正式版" not in old_cn:
        put("README.zh-CN.md", (note_cn + old_cn).encode("utf-8"))
    changelog = ROOT / "CHANGELOG.md"
    log = changelog.read_text(encoding="utf-8")
    if "## [0.2.1]" not in log:
        put("CHANGELOG.md", ("""## [0.2.1] - Stable
- PVD-authoritative Step/Frame reuse with unused historic VTUs preserved.
- In-place incremental SDV Field Merge; source filenames stay unchanged.
- Fast two-frame numerical witness or strict per-frame validation.
- Transaction journal with atomic replace and NTFS hard-link rollback.
- Chinese/English Windows workbench and integrated CPFEM post-processing.

""" + log).encode("utf-8"))
    put("RELEASE_NOTES.md", """# ODB2VTU-S v0.2.1 / 发布说明

**中文：** 修复重复 Step/Frame 误报；以 PVD 为权威帧映射。支持无 Manifest/签名旧数据的原位 SDV 增量更新，保留原变量与文件名。支持两帧抽样快速校验、严格逐帧验证、NTFS 回滚保护及中英文统一工作台。

**English:** PVD-authoritative Step/Frame mapping avoids false duplicates from unreferenced historic VTUs. In-place incremental SDV updates preserve existing arrays and filenames. Adds fast two-sample validation, strict validation, NTFS hard-link rollback, and a bilingual unified workbench.

**Safety:** Back up datasets before in-place updates. Automated tests do not certify every real-world ODB numerical field.
""".encode("utf-8"))
    # Retain obsolete v0.2.0 tests as reference, but do not execute
    # their now-inapplicable expectation that unreferenced VTUs must abort.
    legacy = ROOT / "tests/legacy_v020"
    legacy.mkdir(parents=True, exist_ok=True)
    for name in ("test_export_series_flow.py", "test_export_inventory.py"):
        old_file = ROOT / "tests" / name
        if old_file.is_file():
            shutil.move(str(old_file), str(legacy / name))
    print("STAGED: 0.2.1, all release modules and documentation.")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: promote_v021_assets.py WINDOWS.zip LINUX.zip")
    stage(Path(sys.argv[1]), Path(sys.argv[2]))
