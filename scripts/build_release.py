#!/usr/bin/env python3
from pathlib import Path
import shutil, zipfile
ROOT=Path(__file__).resolve().parents[1]
VERSION=(ROOT/'VERSION').read_text().strip()
DIST=ROOT/'dist';DIST.mkdir(exist_ok=True)
for ps in (ROOT/'src/data_exporter/windows').glob('*.ps1'):
    b=ps.read_bytes()
    if not b.startswith(b'\xef\xbb\xbf'):
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
