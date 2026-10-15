# -*- coding: utf-8 -*-
"""Validate an original v0.2 manifest before reusing a restored PVD/VTU series.

No data is written here. In particular, matching filenames or matching DataArray
names are *not* sufficient provenance without a compatible original manifest.
"""
from __future__ import print_function
import os

from odb_export_inventory import _pvd_filenames, _is_closed_vtu
from odb_export_state import load_manifest, same_source_identity, state_key
from odb_vtu_incremental import expected_derived, vtu_arrays


def verify_original_manifest(candidate_path, target_manifest_path, pvd_path,
                             frame_dir, source, revision):
    """Return a verified source-manifest dict; fail closed before any export.

    The user must explicitly select the original manifest. The manifest must
    describe exactly the files in the currently published PVD and the same
    ODB / instance / region / ODB size+mtime. Existing extra VTU arrays are
    legitimate and will be preserved by Field Merge.
    """
    if candidate_path and os.path.normcase(os.path.abspath(candidate_path)) == os.path.normcase(os.path.abspath(target_manifest_path)):
        raise RuntimeError('Selected metadata path is the current manifest. '
                           'A valid original copy from the earlier export is required.')
    if not candidate_path or not os.path.isfile(candidate_path):
        raise RuntimeError('Original manifest not found: %s' % candidate_path)
    source_manifest = load_manifest(candidate_path)
    if source_manifest is None:
        raise RuntimeError('Original manifest is unreadable or has an unsupported format.')
    if not same_source_identity(source_manifest, source):
        raise RuntimeError('Original manifest ODB / instance / element-set / bbox differs '
                           'from this export request; adoption refused.')
    indexed = _pvd_filenames(pvd_path)
    if not indexed:
        raise RuntimeError('Published PVD is absent or contains no valid VTU references.')
    entries = source_manifest.get('frames') or {}
    names = {}
    for key, entry in entries.items():
        if not isinstance(entry, dict) or not entry.get('active', True):
            continue
        fn = entry.get('file') or ''
        if not fn or fn != os.path.basename(fn) or '/' in fn or '\\' in fn:
            raise RuntimeError('Unsafe filename in original manifest: %s' % fn)
        if fn in names:
            raise RuntimeError('Manifest lists multiple states for VTU: ' + fn)
        if key != state_key(entry.get('step', ''), entry.get('frame', -1)):
            raise RuntimeError('Step/Frame metadata mismatch for ' + fn)
        if entry.get('source_revision') != revision:
            raise RuntimeError('ODB file size/mtime differs from the original manifest: ' + fn)
        spec = entry.get('output_spec')
        if not isinstance(spec, dict) or not spec.get('native_fields'):
            raise RuntimeError('Original manifest lacks recorded native fields: ' + fn)
        names[fn] = spec
    if indexed != set(names):
        missing = indexed - set(names)
        extra = set(names) - indexed
        raise RuntimeError('Original manifest does not match the published PVD. '
                           'PVD-only=%d, manifest-only=%d. Example: %s' % (
                               len(missing), len(extra), list(missing or extra)[:3]))
    for fn, spec in names.items():
        path = os.path.join(frame_dir, fn)
        if not os.path.isfile(path) or not _is_closed_vtu(path):
            raise RuntimeError('Missing/incomplete VTU: ' + fn)
        point, cell = vtu_arrays(path)
        arrays = point | cell
        expected = set(spec['native_fields'])
        for group in expected_derived(spec).values():
            expected.update(group)
        missing = expected - arrays
        if missing:
            raise RuntimeError('Original manifest expects absent fields in %s: %s' % (
                fn, sorted(missing)[:12]))
    return source_manifest, len(names)
