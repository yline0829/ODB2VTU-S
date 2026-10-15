#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""READ-ONLY diagnosis of an ODB2VTU-S PVD/VTU directory.

Usage: python diagnose_output_readonly.py /path/to/name_series.pvd
Outputs a JSON report beside this script's current working directory.
Never opens an ODB or changes a PVD, Manifest, or VTU.
"""
import argparse
import collections
import datetime
import json
import mmap
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

RX_NAME = re.compile(br'\bName="([^\"]+)"')
RX_HEADER = re.compile(br'<DataArray\b[^>]*>')


def field_names(path):
    """Inspect an existing VTU through memory mapping; never load its numeric arrays."""
    f = open(path, 'rb')
    try:
        with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as data:
            names = []
            offset = 0
            while True:
                begin = data.find(b'<DataArray', offset)
                if begin < 0:
                    break
                end = data.find(b'>', begin, begin + 16384)
                if end < 0:
                    break
                m = RX_NAME.search(data[begin:end + 1])
                if m:
                    name = m.group(1).decode('utf-8', errors='replace')
                    if name not in ('connectivity', 'offsets', 'types'):
                        names.append(name)
                close = data.find(b'</DataArray>', end + 1)
                if close < 0:
                    break
                offset = close + len(b'</DataArray>')
            return names
    finally:
        f.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pvd', help='Full path to existing .pvd file')
    parser.add_argument('--max-scan', type=int, default=24,
                        help='Max existing VTUs for field-name audit (default 24)')
    parser.add_argument('--report', help='JSON output report path')
    args = parser.parse_args()
    pvd = Path(args.pvd).resolve()
    if not pvd.is_file():
        parser.error('PVD file does not exist: %s' % pvd)
    folder = pvd.parent / (pvd.stem + '_frames')
    if not folder.is_dir():
        parser.error('VTU folder does not exist: %s' % folder)
    root = ET.parse(str(pvd)).getroot()
    pvd_refs = [Path((e.get('file') or '').replace('\\', '/')).name
                for e in root.iter('DataSet')]
    manifest_path = folder / '_ODB2VTUS_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {}
    records = manifest.get('frames') or {}
    named = {}
    by_state = collections.defaultdict(list)
    rx = re.compile(r'^' + re.escape(pvd.stem) + r'_(\d{6,})_(.+)_f(\d{6,})\.vtu$', re.I)
    for path in sorted(folder.glob('*.vtu')):
        stat = path.stat()
        m = rx.match(path.name)
        state = (m.group(2) + '\t' + str(int(m.group(3)))) if m else None
        item = {
            'file': path.name, 'size_bytes': stat.st_size,
            'modified': datetime.datetime.fromtimestamp(stat.st_mtime).isoformat(timespec='seconds'),
            'in_pvd': path.name in pvd_refs,
            'state_slug_and_index': state,
        }
        if state:
            by_state[state].append(path.name)
        named[path.name] = item
    duplicate_states = {key: value for key, value in by_state.items() if len(value) > 1}
    manifest_names = {entry.get('file') for entry in records.values() if isinstance(entry, dict)}
    scan_names = set()
    for files in duplicate_states.values():
        scan_names.update(files)
    scan_names.update(n for n in pvd_refs if n in named)
    scan_names = sorted(scan_names, key=lambda n: (n not in {v for vs in duplicate_states.values() for v in vs}, n))
    max_scan = max(0, args.max_scan)
    for filename in scan_names[:max_scan]:
        try:
            arrays = field_names(folder / filename)
            named[filename]['array_count'] = len(arrays)
            named[filename]['arrays'] = arrays
        except Exception as exc:
            named[filename]['scan_error'] = str(exc)
    report = {
        'report_version': 1,
        'created': datetime.datetime.now().isoformat(timespec='seconds'),
        'source_pvd': str(pvd),
        'pvd_dataset_count': len(pvd_refs),
        'pvd_files': pvd_refs,
        'missing_referenced_files': [n for n in pvd_refs if n not in named],
        'manifest_frame_count': len(records),
        'manifest_source': manifest.get('source'),
        'manifest_states': records,
        'manifest_files_absent': sorted(n for n in manifest_names if n and n not in named),
        'duplicate_step_frame_states': duplicate_states,
        'unreferenced_vtu': sorted(set(named) - set(pvd_refs)),
        'vtu_count': len(named),
        'vtu_files': list(named.values()),
        'fields_inspected': min(len(scan_names), max_scan),
        'warning': 'READ-ONLY report; duplicate variants may contain different fields. Do not delete or overwrite source data.',
    }
    out = Path(args.report) if args.report else (Path.cwd() / ('ODB2VTUS_diagnostic_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '.json'))
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Read-only report:', out)
    print('VTU files:', len(named), 'PVD references:', len(pvd_refs), 'duplicate states:', len(duplicate_states))
    print('Missing referenced:', len(report['missing_referenced_files']))
    print('Upload this JSON together with the original PVD and Manifest if you want exact recovery guidance.')


if __name__ == '__main__':
    main()
