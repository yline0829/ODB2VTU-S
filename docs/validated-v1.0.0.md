# ODB2VTU-S v1.0.0 — Validated Windows EXE baseline

**Validation provenance:** user-tested executable `odb2vtu.exe` (507,904 bytes), SHA-256 `bab33ff40ee8a7201628367f9b020b5736fbe880c703ca24f277fe1c55236c98`. The release baseline is defined by this exact binary plus the 31 resources extracted from its .NET managed resource section.

## Release scope

- Windows primary baseline: exact, unchanged `odb2vtu.exe` with its original self-extracting .NET launcher and 31 embedded resources. User reports successful real-world execution.
- The Windows PowerShell GUI and Abaqus Python backend in `src/data_exporter/` and `src/postprocess/backend/abaqus_postprocess_master.py` come from the validated EXE's embedded files, byte-for-byte. `Launch_Workbench.ps1` is included.
- Windows `AppInfo.json` is intentionally retained byte-for-byte with its original `0.2.1-rc10` internal version. The original executable file version remains `0.0.0.0`. Both are historical *embedded metadata*, not newly built 1.0.0 binaries.
- The existing Linux implementation has **not** been replaced or validated against this Windows EXE. Linux assets are not claimed to be independently validated at v1.0.0.
- `.NET` self-extractor original C#/IL source is not available as source; the executable is the canonical launcher binary. The old `packaging/windows/build_exe.ps1` builds a **different** PS2EXE launcher and is not a reproducible build of the validated EXE.

## Integrity and distribution

1. Verify the exact EXE SHA-256 equals `bab33ff40ee8a7201628367f9b020b5736fbe880c703ca24f277fe1c55236c98`.
2. Preserve the launcher executable without edits; do not rename older PS2EXE builds as a reproduction.
3. All 31 extracted resources are recorded with SHA-256 in `docs/validated-v1.0.0-manifest.json`. Extracted code is for auditing and future development.
4. The user has verified its Windows functionality. No new Windows or Abaqus runtime test has been carried out for the GitHub source revision.
5. Tag v1.0.0 and create its release after checking that the branch source matches this manifest; attach the original executable and the source distribution, not a PS2EXE rebuild.
