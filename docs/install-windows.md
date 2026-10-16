# ODB2VTU-S — Windows installation

## Recommended: Windows EXE bundle

The Windows EXE build contains:

```text
ODB2VTU-S_Exporter.exe
+ Python/Abaqus backend files
+ Windows helper modules
+ supplied ODB2VTU-S Exporter icon
```

Start the application by double-clicking:

```text
ODB2VTU-S_Exporter.exe
```

The EXE is the GUI host. The backend Python files intentionally remain beside the EXE rather than being embedded into it. This keeps startup work small and allows future updates to replace the EXE or individual backend files in place.

### Runtime requirements

- Windows 10/11 x64.
- Abaqus with `odbAccess`.
- The `abaqus` command must be callable from Command Prompt.

You do **not** need to install PS2EXE on the user's computer. PS2EXE is only a build-time dependency. The generated executable is a Windows .NET executable; ODB processing still depends on Abaqus/odbAccess.

### Build environment

The reproducible build is defined by:

```text
Windows PowerShell 5.1
.NET Framework 4.x
PS2EXE 1.0.18
```

The repository provides:

```text
packaging/windows/build_exe.ps1
```

The GitHub Actions workflow builds the EXE automatically on a Windows runner.

## Legacy launcher

The previous launcher remains available for compatibility:

```text
Launch_ODB2VTU-S_Exporter.vbs
```

It is useful for debugging the original PowerShell GUI path. The normal EXE distribution should use `ODB2VTU-S_Exporter.exe`.

## CPFEM Postprocessor

Launch:

```text
Launch_ODB2VTU-S_CPFEM_Postprocessor.bat
```

The GUI calls `abaqus python abaqus_postprocess_master.py ...`.

## Notes

- Keep the EXE, GUI/backend scripts, and Abaqus backend files in the same folder.
- Close Abaqus/Viewer before writing PEEQCP back to an ODB.
- Do not keep a generated PVD open in ParaView while replacing that same file on Windows.
- The supplied ODB2VTU-S Exporter icon is used for the EXE; no alternative icon is generated.
