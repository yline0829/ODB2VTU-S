#Requires -Version 5.1
# ---------------------------------------------------------------------------
# Single-process launcher for the ODB2VTU-S Workbench.
#
# Startup used to cost two powershell.exe processes (one for the BOM/syntax
# validation, one for the GUI). This script performs the same validation and
# then runs the GUI in the very same process, so only one interpreter is paid
# for.
#
# The validation itself is not duplicated: Check_PS51_Syntax.ps1 is dot-sourced
# with -NoExit (so it reports through $failed instead of exiting), inside a
# child scope so that its $ErrorActionPreference = 'Stop' cannot leak into the
# GUI. Check_PS51_Syntax.ps1 stays usable stand-alone (exit codes) for manual
# runs, the debug launcher and CI.
#
# On validation failure the error dialog is shown from here instead of from the
# C# launcher (that is the trade-off of merging the processes).
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Continue'

$wbRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$wbCheck = Join-Path $wbRoot 'Check_PS51_Syntax.ps1'
$wbMain  = Join-Path $wbRoot 'ODB2VTU-S_Exporter.ps1'

$script:wbCheckFailed = $false
& {
    . $wbCheck -NoExit
    $script:wbCheckFailed = [bool]$failed
}

if ($script:wbCheckFailed) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $wbLog = Join-Path $env:LOCALAPPDATA 'ODB2VTU-S\launcher.log'
        [void][System.Windows.Forms.MessageBox]::Show(
            "启动校验失败（退出码 3）。`n`n" +
            "请用调试模式查看详细错误：`n" +
            "   在命令行运行  odb2vtu.exe --debug`n`n" +
            "日志文件：`n$wbLog",
            'ODB2VTU-S 启动校验',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch { }
    exit 3
}

& $wbMain
