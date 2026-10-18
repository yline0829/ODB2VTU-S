# -*- coding: utf-8 -*-
"""In-place VTU transaction without creating a second data directory.

Uses same-directory NTFS hard links as zero-copy rollback aliases.  Adjacent
.tmp VTU creation remains necessary for atomic file replacement. If a crash
occurs, the journal + hardlinks are retained for explicit recovery; new export
is blocked until recovery. Never silently discard rollback data.
"""
from __future__ import print_function
import os
import json
import uuid
import sys
from odb_export_state import atomic_write_json


class InPlaceTransaction(object):
    def __init__(self, frame_dir):
        self.frame_dir = os.path.abspath(frame_dir)
        self.journal_path = os.path.join(self.frame_dir, '_ODB2VTUS_INPLACE_JOURNAL.json')
        if os.path.exists(self.journal_path):
            raise RuntimeError('IN-PLACE RECOVERY/CLEANUP REQUIRED: transaction journal exists: ' +
                               self.journal_path + '. Do not start a new export.')
        self.token = uuid.uuid4().hex[:12]
        self.entries = []
        self.created = []
        self.open = False

    def _save(self):
        atomic_write_json(self.journal_path, {'version': 1, 'status': 'active',
                        'token': self.token, 'entries': self.entries,
                        'created': self.created})

    def start(self):
        self._save()
        self.open = True

    def protect(self, path):
        """Create rollback alias and journal it BEFORE source is replaced."""
        path = os.path.abspath(path)
        for entry in self.entries:
            if entry['path'] == path:
                return
        if os.path.isfile(path):
            alias = path + '.odb2vtus_rollback_' + self.token
            try:
                os.link(path, alias)
            except (OSError, IOError) as ex:
                raise RuntimeError('Cannot create NTFS hard-link rollback in same directory '
                                   '(no full copy attempted): %s : %s' % (path, ex))
            self.entries.append({'path': path, 'rollback': alias})
        else:
            self.created.append(path)
        self._save()

    def rollback(self):
        """Restore previous inodes and remove new outputs. Never delete failed backups."""
        errors = []
        for entry in reversed(self.entries):
            try:
                if os.path.isfile(entry['rollback']):
                    os.replace(entry['rollback'], entry['path'])
                else:
                    errors.append('Missing rollback alias: ' + entry['rollback'])
            except Exception as ex:
                errors.append('%s: %s' % (entry['path'], ex))
        for path in reversed(self.created):
            try:
                if os.path.isfile(path):
                    os.remove(path)
            except Exception as ex:
                errors.append('%s: %s' % (path, ex))
        if not errors:
            if os.path.isfile(self.journal_path):
                os.remove(self.journal_path)
            self.open = False
        else:
            raise RuntimeError('Rollback incomplete. Keep journal and remaining links: %s' % errors)

    def commit(self):
        """Publish commit marker before deleting old-file rollback aliases."""
        atomic_write_json(self.journal_path, {'version': 1, 'status': 'published',
                          'token': self.token, 'entries': self.entries,
                          'created': self.created})
        self.open = False   # Past this point, do not roll back a valid publication.
        for entry in self.entries:
            if os.path.isfile(entry['rollback']):
                os.remove(entry['rollback'])
        if os.path.isfile(self.journal_path):
            os.remove(self.journal_path)


def restore_unfinished(journal_path):
    if not os.path.isfile(journal_path):
        raise RuntimeError('No interrupted export journal at: ' + journal_path)
    with open(journal_path, 'r') as f:
        info = json.load(f)
    if info.get('version') != 1:
        raise RuntimeError('Unknown journal version; no changes made.')
    if info.get('status') == 'published':
        # Outputs have been committed. Only clean up links; NEVER roll back.
        for entry in info.get('entries', []):
            if os.path.isfile(entry['rollback']):
                os.remove(entry['rollback'])
        os.remove(journal_path)
        print('[CLEANED] Completed in-place update journal: ' + journal_path)
        return
    if info.get('status') != 'active':
        raise RuntimeError('Unknown journal state; no changes made.')
    for entry in info.get('entries', []):
        if not os.path.isfile(entry['rollback']):
            raise RuntimeError('Rollback copy missing; cannot safely restore: ' + entry['rollback'])
    for entry in reversed(info.get('entries', [])):
        os.replace(entry['rollback'], entry['path'])
    for path in info.get('created', []):
        if os.path.isfile(path):
            os.remove(path)
    os.remove(journal_path)
    print('[RESTORED] Interrupted in-place update rolled back: ' + journal_path)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--restore':
        restore_unfinished(sys.argv[2])
    else:
        print('Usage: abaqus python odb_inplace_transaction.py --restore FULL_JOURNAL_PATH')
        sys.exit(2)
