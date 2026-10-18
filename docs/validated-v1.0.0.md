# ODB2VTU-S v1.0.0 — Validated Windows EXE baseline

**Validation provenance:** user-tested executable `odb2vtu.exe` (507,904 bytes), SHA-256 `bab33ff40ee8a7201628367f9b020b5736fbe880c703ca24f277fe1c55236c98`. The release baseline is defined by this exact binary plus the 31 resources extracted from its .NET managed resource section.

## Release scope

- Windows primary baseline: exact, unchanged `odb2vtu.exe` with its original self-extracting .NET launcher and 31 embedded resources. User reports successful real-world execution.
- The Windows PowerShell GUI and Abaqus Python backend in `src/data_exporter/` and `src/postprocess/backend/abaqus_postprocess_master.py` come from the validated EXE's embedded files, byte-for-byte. `Launch_Workbench.ps1` is included.
- Windows `AppInfo.json` is intentionally retained byte-for-byte with its original `0.2.1-rc10` internal version. The original executable file version remains `0.0.0.0`. Both are historical *embedded metadata*, not newly built 1.0.0 binaries.
- The v1.0.0 Linux implementation is independent, provided by the user as a complete Linux archive. It is not claimed to have been validated by the Windows EXE. Static/packaging/install-uninstall checks passed; a real Abaqus numeric run was not performed in this session.
- `.NET` self-extractor original C#/IL source is not available as source; the executable is the canonical launcher binary. The old `packaging/windows/build_exe.ps1` builds a **different** PS2EXE launcher and is not a reproducible build of the validated EXE.

## Integrity and distribution

1. Verify the exact EXE SHA-256 equals `bab33ff40ee8a7201628367f9b020b5736fbe880c703ca24f277fe1c55236c98`.
2. Preserve the launcher executable without edits; do not rename older PS2EXE builds as a reproduction.
3. All 31 extracted resources are recorded with SHA-256 in `docs/validated-v1.0.0-manifest.json`. Extracted code is for auditing and future development.
4. The user has verified its Windows functionality. No new Windows or Abaqus runtime test has been carried out for the GitHub source revision.
5. Tag v1.0.0 and create its release after checking that the branch source matches this manifest; attach the original executable and the source distribution, not a PS2EXE rebuild.

## Linux v1.0.0 source provenance

- Uploaded canonical distribution: `ODB2VTU-S_Workbench_Linux_v1.0.0.tar.gz` (SHA-256 `5f6287b12a5ad26245f5ebb6a0242c6c45626252545135b1f0d12bd22899aa23`).
- The tarball contains 28 standalone source/documentation files and 4 icon resources. The 28 source/documentation files are stored independently under `src/data_exporter/linux/`, rather than overwriting shared Windows backend files.
- The original Linux binary resources include `icons/odb2vtu-s-exporter-256.png`; preserve and distribute the original Linux TAR if a source-based build lacks this exact high-resolution icon file.
- Linux Python 3.6 syntax checks: 22/22; Bash syntax checks: 5/5. In an isolated HOME, install/uninstall retained a dataset sentinel outside the application installation directory.
- The packaged Linux code is a separate implementation from the Windows self-extracting executable. Numerical behavior in a real CentOS 7, SingularityCE, Abaqus 2024 environment must be validated independently.

## v1.0.0 canonical downloadable ZIPs

The exact prepared release assets are:

- Windows: `ODB2VTU-S_Windows_Validated_v1.0.0.zip` — SHA-256 `4fd5d2a00e13b3277f9a52e063c692f98d69f6967488472a2d0520ce3ead6359`.
- Linux: `ODB2VTU-S_Workbench_Linux_v1.0.0.zip` — SHA-256 `6b61076701047d274ec516f8e6492c8c85e1ac789e180ba6e464e0b0d7b4f1d2`.

Both are program packages, not generated source archives. The Linux archive contains the complete 32-file user-provided payload. For a bit-for-bit reproducible Linux repository package, commit the original high-resolution PNG at `src/data_exporter/linux/icons/odb2vtu-s-exporter-256.png` (SHA-256 `120ba8f404b9adb08eda957b77cf2791f0543cca46c58eb5a5f0897b86412ef6`). The user-tested Windows EXE must remain unchanged and must not be replaced by a PS2EXE rebuild.
