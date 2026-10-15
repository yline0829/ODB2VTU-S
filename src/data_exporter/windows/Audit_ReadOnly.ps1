#Requires -Version 5.1
<################################################################################
  ODB2VTU-S v0.2.0 rescue diagnostics - READ ONLY
  Native Windows PowerShell 5.1 / .NET; no Python/Abaqus required.
  Never writes to the PVD, Manifest, or any VTU.
#################################################################################>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PvdPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Fatal([string]$Message) {
    Write-Host ('[ERROR] ' + $Message) -ForegroundColor Red
}

# Read DataArray opening tags in bounded 2 MiB blocks; numerical data remains on disk.
function Get-VtuInfo([string]$FilePath) {
    $blockSize = 2 * 1024 * 1024
    $buffer = New-Object byte[] $blockSize
    $seen = @{}
    $arrays = New-Object 'System.Collections.Generic.List[string]'
    $carry = ''
    $lastText = ''
    $stream = [System.IO.FileStream]::new(
        $FilePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite,
        $blockSize,
        [System.IO.FileOptions]::SequentialScan
    )
    try {
        do {
            $count = $stream.Read($buffer, 0, $buffer.Length)
            if ($count -le 0) { break }
            $chunk = $carry + [System.Text.Encoding]::ASCII.GetString($buffer, 0, $count)
            $lastText = $chunk.Substring([Math]::Max(0, $chunk.Length - 8192))
            $at = 0
            while ($at -lt $chunk.Length) {
                $start = $chunk.IndexOf('<DataArray', $at, [StringComparison]::Ordinal)
                if ($start -lt 0) { break }
                $end = $chunk.IndexOf('>', $start)
                if ($end -lt 0) { break }  # tag will be in next block's overlap
                if (($end - $start) -lt 8192) {
                    $tag = $chunk.Substring($start, $end - $start + 1)
                    $matchName = [regex]::Match($tag, 'Name\s*=\s*"([^"]+)"')
                    if ($matchName.Success) {
                        $name = $matchName.Groups[1].Value
                        if (($name -ne 'connectivity') -and ($name -ne 'offsets') -and ($name -ne 'types')) {
                            if (-not $seen.ContainsKey($name)) {
                                $seen[$name] = $true
                                [void]$arrays.Add($name)
                            }
                        }
                    }
                }
                $at = $end + 1
            }
            $carry = $chunk.Substring([Math]::Max(0, $chunk.Length - 1024))
        } while ($count -gt 0)
    }
    finally { $stream.Dispose() }
    return [pscustomobject]@{
        arrays = @($arrays.ToArray())
        array_count = $arrays.Count
        xml_end_marker_found = $lastText.Contains('</VTKFile>')
    }
}

try {
    $pvdClean = $PvdPath.Trim().Trim('"')
    if (-not $pvdClean.EndsWith('.pvd', [StringComparison]::OrdinalIgnoreCase)) {
        throw "The supplied path is not a .pvd file: $pvdClean"
    }
    if (-not (Test-Path -LiteralPath $pvdClean -PathType Leaf)) {
        throw "PVD file not found. Verify the DRIVE letter and full file path: $pvdClean"
    }
    $pvd = (Resolve-Path -LiteralPath $pvdClean).ProviderPath
    $parent = [System.IO.Path]::GetDirectoryName($pvd)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($pvd)
    $frameDir = Join-Path $parent ($stem + '_frames')
    if (-not (Test-Path -LiteralPath $frameDir -PathType Container)) {
        throw "Matching VTU directory does not exist: $frameDir"
    }
    $manifestPath = Join-Path $frameDir '_ODB2VTUS_manifest.json'
    Write-Host "[OK] PVD: $pvd" -ForegroundColor Green
    Write-Host "[OK] VTU directory: $frameDir" -ForegroundColor Green
    Write-Host '[INFO] Reading the PVD and manifest...' -ForegroundColor Cyan
    [xml]$pvdXml = [System.IO.File]::ReadAllText($pvd, [System.Text.Encoding]::UTF8)
    $pvdRefs = New-Object 'System.Collections.Generic.List[string]'
    $referenceSet = @{}
    foreach ($node in @($pvdXml.SelectNodes('//*[local-name()="DataSet"]'))) {
        $f = [string]$node.GetAttribute('file')
        $f = $f.Replace('/', '\')
        $name = [System.IO.Path]::GetFileName($f)
        if ($name) {
            [void]$pvdRefs.Add($name)
            $referenceSet[$name.ToLowerInvariant()] = $true
        }
    }

    $records = @{}
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if (($null -ne $manifest) -and ($null -ne $manifest.frames)) {
            foreach ($entry in $manifest.frames.PSObject.Properties) { $records[$entry.Name] = $entry.Value }
        }
    } else {
        Write-Host '[WARNING] Manifest not found. Scan will continue using filenames and PVD.' -ForegroundColor Yellow
    }

    $allFiles = @(Get-ChildItem -LiteralPath $frameDir -Filter '*.vtu' -File | Sort-Object -Property Name)
    if ($allFiles.Count -eq 0) { throw "No VTU files exist in: $frameDir" }
    $rx = [regex]::new('^' + [regex]::Escape($stem) + '_(\d{6,})_(.+)_f(\d{6,})\.vtu$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $fileItems = New-Object 'System.Collections.Generic.List[object]'
    $byState = @{}
    $fileLookup = @{}

    foreach ($file in $allFiles) {
        $matchFile = $rx.Match($file.Name)
        $state = $null
        $serial = $null
        if ($matchFile.Success) {
            $serial = [int64]$matchFile.Groups[1].Value
            $state = $matchFile.Groups[2].Value + "`t" + ([int]$matchFile.Groups[3].Value)
            if (-not $byState.ContainsKey($state)) { $byState[$state] = New-Object 'System.Collections.Generic.List[string]' }
            [void]$byState[$state].Add($file.Name)
        }
        $item = [ordered]@{
            file = $file.Name
            size_bytes = [int64]$file.Length
            modified = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            state_slug_and_index = $state
            serial_number = $serial
            in_pvd = $referenceSet.ContainsKey($file.Name.ToLowerInvariant())
            arrays = @()
            array_count = 0
            xml_end_marker_found = $false
            manifest_expected_native_missing = @()
            actual_native_unlisted_by_manifest = @()
        }
        [void]$fileItems.Add($item)
        $fileLookup[$file.Name.ToLowerInvariant()] = $true
    }

    $duplicateStates = [ordered]@{}
    foreach ($state in @($byState.Keys | Sort-Object)) {
        if ($byState[$state].Count -gt 1) { $duplicateStates[$state] = @($byState[$state].ToArray()) }
    }
    Write-Host ('[INFO] PVD references: ' + $pvdRefs.Count + '; VTUs on disk: ' + $allFiles.Count + '; duplicated states: ' + $duplicateStates.Count)
    Write-Host ('[INFO] Scanning DataArray names for ALL ' + $allFiles.Count + ' files; this does not modify the VTUs.') -ForegroundColor Cyan

    $i = 0
    foreach ($item in $fileItems) {
        $i++
        Write-Host ('[{0}/{1}] {2}' -f $i, $fileItems.Count, $item.file)
        try {
            $fpath = Join-Path $frameDir $item.file
            $vtu = Get-VtuInfo -FilePath $fpath
            $item.arrays = @($vtu.arrays)
            $item.array_count = [int]$vtu.array_count
            $item.xml_end_marker_found = [bool]$vtu.xml_end_marker_found
            if (($null -ne $item.state_slug_and_index) -and $records.ContainsKey([string]$item.state_slug_and_index)) {
                $old = $records[[string]$item.state_slug_and_index]
                $expected = @($old.output_spec.native_fields)
                $found = @{}
                foreach ($name in $item.arrays) { $found[[string]$name] = $true }
                $miss = New-Object 'System.Collections.Generic.List[string]'
                foreach ($name in $expected) {
                    if (($null -ne $name) -and (-not $found.ContainsKey([string]$name))) { [void]$miss.Add([string]$name) }
                }
                $wanted = @{}
                foreach ($name in $expected) { if ($null -ne $name) { $wanted[[string]$name] = $true } }
                $extra = New-Object 'System.Collections.Generic.List[string]'
                foreach ($name in $item.arrays) {
                    if (($name -match '^SDV\d+$|^(U|UR|S|LE|PEEQCP|E|PE|RF|CF)$') -and (-not $wanted.ContainsKey([string]$name))) {
                        [void]$extra.Add([string]$name)
                    }
                }
                $item.manifest_expected_native_missing = @($miss.ToArray())
                $item.actual_native_unlisted_by_manifest = @($extra.ToArray())
            }
        } catch {
            $item['scan_error'] = [string]$_.Exception.Message
            Write-Host ('  [WARNING] ' + $item.scan_error) -ForegroundColor Yellow
        }
    }

    $missing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $pvdRefs) {
        if (-not $fileLookup.ContainsKey($name.ToLowerInvariant())) { [void]$missing.Add($name) }
    }
    $manifestMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rec in @($records.Values)) {
        if (($null -ne $rec) -and ($null -ne $rec.file)) {
            if (-not $fileLookup.ContainsKey(([string]$rec.file).ToLowerInvariant())) { [void]$manifestMissing.Add([string]$rec.file) }
        }
    }
    $unref = @($fileItems | Where-Object { -not $_.in_pvd } | ForEach-Object { $_.file })
    $mismatch = @($fileItems | Where-Object { $_.manifest_expected_native_missing.Count -gt 0 -or $_.actual_native_unlisted_by_manifest.Count -gt 0 })
    $errors = @($fileItems | Where-Object { $_.Contains('scan_error') })
    $report = [ordered]@{
        report_version = 2
        tool = 'Read-only native Windows PowerShell field audit; does not need Python'
        created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        source_pvd = $pvd
        pvd_dataset_count = $pvdRefs.Count
        pvd_files = @($pvdRefs.ToArray())
        vtu_directory = $frameDir
        vtu_count = $allFiles.Count
        duplicate_step_frame_states = $duplicateStates
        manifest_frame_count = $records.Count
        manifest_files_absent = @($manifestMissing.ToArray())
        missing_referenced_files = @($missing.ToArray())
        unreferenced_vtu = @($unref)
        mismatch_count = $mismatch.Count
        mismatch_file_names = @($mismatch | ForEach-Object { $_.file })
        unreadable_vtu = @($errors | ForEach-Object { $_.file })
        vtu_files = @($fileItems.ToArray())
        warning = 'READ ONLY. Do not delete or overwrite any output file before restoring data from backups.'
    }
    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss_fff')
    $outFolder = $PSScriptRoot
    $reportPath = Join-Path $outFolder ('ODB2VTUS_audit_' + $timestamp + '.json')
    $textPath = Join-Path $outFolder ('ODB2VTUS_audit_' + $timestamp + '_SUMMARY.txt')
    $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    @(
        ('PVD file: ' + $pvd),
        ('PVD states: ' + $pvdRefs.Count),
        ('All VTUs: ' + $allFiles.Count),
        ('Duplicate Step/Frame states: ' + $duplicateStates.Count),
        ('PVD-referenced VTUs missing: ' + $missing.Count),
        ('Manifest frames: ' + $records.Count),
        ('Manifest-referenced VTUs missing: ' + $manifestMissing.Count),
        ('Files with native field mismatch: ' + $mismatch.Count),
        ('Unreadable files: ' + $errors.Count),
        ('REPORT: ' + $reportPath)
    ) | Set-Content -LiteralPath $textPath -Encoding UTF8
    Write-Host '-----------------------------------------------------------'
    Write-Host ('[SUCCESS] JSON report: ' + $reportPath) -ForegroundColor Green
    Write-Host ('[SUCCESS] Summary text: ' + $textPath) -ForegroundColor Green
    Write-Host ('[SUMMARY] Duplicate states = ' + $duplicateStates.Count + '; missing PVD files = ' + $missing.Count + '; field mismatches = ' + $mismatch.Count) -ForegroundColor Cyan
    exit 0
} catch {
    Write-Fatal ([string]$_.Exception.Message)
    Write-Host '[INFO] This script never modifies original PVD/VTU/Manifest files.'
    Write-Host '[INFO] Confirm .pvd path, matching *_frames directory, then send the error screenshot.'
    exit 3
}
