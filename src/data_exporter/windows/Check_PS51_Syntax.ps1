#Requires -Version 5.1
param([string]$MainScript = "")
$ErrorActionPreference = 'Stop'
$folder = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = @(Get-ChildItem -LiteralPath $folder -Filter '*.ps1' -File)
$failed = $false
foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) {
        Write-Host ('[ERROR] Missing UTF-8 BOM: ' + $f.Name) -ForegroundColor Red
        $failed = $true
        continue
    }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        Write-Host ('[ERROR] PowerShell parser error: ' + $f.Name) -ForegroundColor Red
        foreach ($err in $parseErrors) {
            Write-Host ('  line ' + $err.Extent.StartLineNumber + ': ' + $err.Message) -ForegroundColor Red
        }
        $failed = $true
    } else {
        Write-Host ('[OK] PowerShell 5.1 syntax: ' + $f.Name)
    }
}
if ($failed) { exit 3 }
Write-Host '[SUCCESS] All PowerShell scripts passed startup checks.' -ForegroundColor Green
exit 0
