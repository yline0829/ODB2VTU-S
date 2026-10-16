#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepositoryRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $RepositoryRoot = (Resolve-Path $RepositoryRoot).Path
}

if ($PSVersionTable.PSEdition -ne "Desktop" -or $PSVersionTable.PSVersion.Major -lt 5) {
    throw "This build must run under Windows PowerShell 5.1 Desktop."
}

$version = (Get-Content -LiteralPath (Join-Path $RepositoryRoot "VERSION") -Raw).Trim()
if ($version -notmatch "^\d+\.\d+\.\d+$") {
    throw "Unsupported VERSION value: $version"
}
$version4 = "$version.0"

$windowsSource = Join-Path $RepositoryRoot "src\data_exporter\windows"
$backendSource = Join-Path $RepositoryRoot "src\data_exporter\backend"
$postprocessSource = Join-Path $RepositoryRoot "src\postprocess\backend"
$iconSource = Join-Path $RepositoryRoot "assets\icons\odb2vtu-s-exporter.ico"

foreach ($required in @(
    (Join-Path $windowsSource "ODB2VTU-S_Exporter.ps1"),
    (Join-Path $windowsSource "AppInfo.json"),
    (Join-Path $backendSource "odb_metadata.py"),
    (Join-Path $backendSource "odb_list_fields.py"),
    (Join-Path $backendSource "odb_export_vtu.py"),
    (Join-Path $backendSource "odb_export_series.py"),
    (Join-Path $postprocessSource "abaqus_postprocess_master.py"),
    $iconSource
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required build input is missing: $required"
    }
}

$guiSource = Join-Path $windowsSource "ODB2VTU-S_Exporter.ps1"
[void][scriptblock]::Create((Get-Content -LiteralPath $guiSource -Raw -Encoding UTF8))

$module = Get-Module -ListAvailable -Name ps2exe |
    Where-Object { $_.Version -eq [version]"1.0.18" } |
    Select-Object -First 1

if (-not $module) {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force
    }

    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Default
    }

    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name ps2exe -Repository PSGallery -RequiredVersion 1.0.18 -Scope CurrentUser -Force -AllowClobber -Confirm:$false
}

Import-Module ps2exe -RequiredVersion 1.0.18 -Force
$installed = Get-Module ps2exe
if ($installed.Version -ne [version]"1.0.18") {
    throw "Expected PS2EXE 1.0.18, got $($installed.Version)"
}

$dist = Join-Path $RepositoryRoot "dist"
$stage = Join-Path $RepositoryRoot ".build\ODB2VTU-S_Workbench_Windows_EXE_v$version"
New-Item -ItemType Directory -Path $dist -Force | Out-Null
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$exe = Join-Path $stage "ODB2VTU-S_Exporter.exe"

Write-Host "Building ODB2VTU-S Exporter $version with PS2EXE 1.0.18..."
$compileParams = @{
    inputFile = $guiSource
    outputFile = $exe
    x64 = $true
    STA = $true
    noConsole = $true
    DPIAware = $true
    supportOS = $true
    iconFile = $iconSource
    title = "ODB2VTU-S Exporter"
    description = "Selective Abaqus ODB to VTU/PVD exporter and postprocessing workbench."
    company = "ODB2VTU-S"
    product = "ODB2VTU-S Workbench"
    copyright = "ODB2VTU-S"
    version = $version4
}
Invoke-ps2exe @compileParams

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "PS2EXE did not produce the expected executable: $exe"
}

$exeBytes = [IO.File]::ReadAllBytes($exe)
if ($exeBytes.Length -lt 2 -or $exeBytes[0] -ne 0x4D -or $exeBytes[1] -ne 0x5A) {
    throw "Generated file is not a valid PE executable: $exe"
}

Add-Type -AssemblyName System.Drawing
$associatedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
if ($null -eq $associatedIcon) {
    throw "Generated EXE has no readable associated icon."
}
$associatedIcon.Dispose()

$probe = Join-Path $stage "_compiled_source_probe.ps1"
$extractArgument = '-extract:"' + $probe + '"'
$extractProcess = Start-Process -FilePath $exe -ArgumentList $extractArgument -Wait -PassThru -WindowStyle Hidden
if ($extractProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $probe -PathType Leaf)) {
    throw "Compiled EXE failed its PS2EXE self-extraction smoke test."
}
$probeText = Get-Content -LiteralPath $probe -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($probeText) -or $probeText -notmatch "ODB2VTU-S Exporter") {
    throw "Compiled EXE extraction smoke test returned an unexpected script payload."
}
[void][scriptblock]::Create($probeText)
Remove-Item -LiteralPath $probe -Force

Copy-Item -Path (Join-Path $windowsSource "*") -Destination $stage -Recurse -Force
Copy-Item -Path (Join-Path $backendSource "*.py") -Destination $stage -Force
Copy-Item -Path (Join-Path $postprocessSource "*.py") -Destination $stage -Force
New-Item -ItemType Directory -Path (Join-Path $stage "icons") -Force | Out-Null
Copy-Item -Path (Join-Path $RepositoryRoot "assets\icons\*") -Destination (Join-Path $stage "icons") -Force

$readme = @"
ODB2VTU-S Workbench - Windows EXE build $version

Start:
  ODB2VTU-S_Exporter.exe

Runtime requirements:
  - Windows 10/11 x64
  - Abaqus with odbAccess
  - The "abaqus" command must be available from Command Prompt

The EXE is the GUI host. The Python/Abaqus backend files in this folder are
intentionally kept external so future updates can replace files in place without
extracting an embedded payload at every startup.

Legacy fallback:
  Launch_ODB2VTU-S_Exporter.vbs

This build uses PS2EXE 1.0.18 and the supplied ODB2VTU-S Exporter icon.
"@
Set-Content -LiteralPath (Join-Path $stage "README_Windows_EXE.txt") -Value $readme -Encoding UTF8

$exeDist = Join-Path $dist "ODB2VTU-S_Exporter_v$version.exe"
$zipDist = Join-Path $dist "ODB2VTU-S_Workbench_Windows_EXE_v$version.zip"
Copy-Item -LiteralPath $exe -Destination $exeDist -Force
if (Test-Path -LiteralPath $zipDist) {
    Remove-Item -LiteralPath $zipDist -Force
}
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipDist -CompressionLevel Fastest

$hash = Get-FileHash -LiteralPath $exeDist -Algorithm SHA256
$hashText = @"
ODB2VTU-S_Exporter_v$version.exe
SHA256: $($hash.Hash)
"@
Set-Content -LiteralPath (Join-Path $dist "ODB2VTU-S_Exporter_v$version.sha256.txt") -Value $hashText -Encoding ASCII

Write-Host ""
Write-Host "Build complete:"
Write-Host "  EXE : $exeDist"
Write-Host "  ZIP : $zipDist"
Write-Host "  SHA : $($hash.Hash)"
