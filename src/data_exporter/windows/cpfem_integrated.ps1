param([string]$InitialODB = "", [ValidateSet("zh","en")][string]$Language = "zh")
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = $PSScriptRoot
$masterPy = Join-Path $scriptDir "abaqus_postprocess_master.py"

$form = New-Object System.Windows.Forms.Form
$form.Text = "ODB2VTU-S | 摩擦 CPFEM 后处理"
$form.Size = New-Object System.Drawing.Size(760, 450)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

# ODB
$lblOdb = New-Object System.Windows.Forms.Label
$lblOdb.Text = "ODB 文件："
$lblOdb.Location = New-Object System.Drawing.Point(20, 30)
$lblOdb.Size = New-Object System.Drawing.Size(100, 28)
$lblOdb.Font = $font
$form.Controls.Add($lblOdb)

$txtOdb = New-Object System.Windows.Forms.TextBox
$txtOdb.Location = New-Object System.Drawing.Point(120, 28)
$txtOdb.Size = New-Object System.Drawing.Size(460, 28)
$txtOdb.Font = $font
$form.Controls.Add($txtOdb)

$btnOdb = New-Object System.Windows.Forms.Button
$btnOdb.Text = "选择 ODB"
$btnOdb.Location = New-Object System.Drawing.Point(590, 26)
$btnOdb.Size = New-Object System.Drawing.Size(95, 32)
$btnOdb.Font = $font
$form.Controls.Add($btnOdb)

# Output root
$lblOut = New-Object System.Windows.Forms.Label
$lblOut.Text = "输出目录："
$lblOut.Location = New-Object System.Drawing.Point(20, 82)
$lblOut.Size = New-Object System.Drawing.Size(100, 28)
$lblOut.Font = $font
$form.Controls.Add($lblOut)

$txtOut = New-Object System.Windows.Forms.TextBox
$txtOut.Location = New-Object System.Drawing.Point(120, 80)
$txtOut.Size = New-Object System.Drawing.Size(460, 28)
$txtOut.Font = $font
$form.Controls.Add($txtOut)

$btnOut = New-Object System.Windows.Forms.Button
$btnOut.Text = "选择目录"
$btnOut.Location = New-Object System.Drawing.Point(590, 78)
$btnOut.Size = New-Object System.Drawing.Size(95, 32)
$btnOut.Font = $font
$form.Controls.Add($btnOut)

# Info
$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = "PEEQCP目标帧：下压首/末帧；每个摩擦循环按StepTime取 0、1/4、1/2、3/4、1（最近实际帧）。计算仍遍历全部帧。"
$lblInfo.Location = New-Object System.Drawing.Point(20, 128)
$lblInfo.Size = New-Object System.Drawing.Size(710, 48)
$lblInfo.Font = $font
$form.Controls.Add($lblInfo)

# In the unified workbench, inherit the currently loaded ODB if available.
if ($InitialODB -and (Test-Path -LiteralPath $InitialODB -PathType Leaf)) {
    $txtOdb.Text = $InitialODB
    $txtOut.Text = Split-Path -Parent $InitialODB
}

# Buttons
# Friction History export has moved to Edit -> Curve Data.

$btnPEEQ = New-Object System.Windows.Forms.Button
$btnPEEQ.Text = "① 计算 PEEQCP（全帧累积/目标帧保存）"
$btnPEEQ.Location = New-Object System.Drawing.Point(35, 195)
$btnPEEQ.Size = New-Object System.Drawing.Size(310, 45)
$btnPEEQ.Font = $font
$form.Controls.Add($btnPEEQ)

$btnInject = New-Object System.Windows.Forms.Button
$btnInject.Text = "② 写回 PEEQCP 到目标帧"
$btnInject.Location = New-Object System.Drawing.Point(395, 195)
$btnInject.Size = New-Object System.Drawing.Size(310, 45)
$btnInject.Font = $font
$form.Controls.Add($btnInject)

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = "③ 检查目标帧 PEEQCP"
$btnCheck.Location = New-Object System.Drawing.Point(35, 260)
$btnCheck.Size = New-Object System.Drawing.Size(310, 45)
$btnCheck.Font = $font
$form.Controls.Add($btnCheck)

$status = New-Object System.Windows.Forms.Label
$status.Text = "状态：等待选择"
$status.Location = New-Object System.Drawing.Point(20, 335)
$status.Size = New-Object System.Drawing.Size(710, 48)
$status.Font = $font
$form.Controls.Add($status)

$btnOdb.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Abaqus ODB (*.odb)|*.odb|All files (*.*)|*.*"
    $dlg.Title = "选择 Abaqus ODB"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOdb.Text = $dlg.FileName
        if ([string]::IsNullOrWhiteSpace($txtOut.Text)) {
            $txtOut.Text = Split-Path -Parent $dlg.FileName
        }
        $status.Text = "状态：已选择 ODB"
    }
})

$btnOut.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "选择输出根目录"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOut.Text = $dlg.SelectedPath
        $status.Text = "状态：已选择输出目录"
    }
})

function Validate-Inputs {
    if ([string]::IsNullOrWhiteSpace($txtOdb.Text) -or -not (Test-Path $txtOdb.Text)) {
        [System.Windows.Forms.MessageBox]::Show("请先选择有效的 ODB 文件。","提示")
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($txtOut.Text)) {
        [System.Windows.Forms.MessageBox]::Show("请先选择输出目录。","提示")
        return $false
    }
    if (-not (Test-Path $txtOut.Text)) {
        New-Item -ItemType Directory -Path $txtOut.Text -Force | Out-Null
    }
    if (-not (Test-Path $masterPy)) {
        [System.Windows.Forms.MessageBox]::Show("找不到 abaqus_postprocess_master.py。请核查统一软件安装目录中的后端文件。","错误")
        return $false
    }
    return $true
}

$script:currentProcess = $null
$script:currentOperation = ""
$script:currentTitle = ""

function Set-OperationButtonsEnabled([bool]$enabled) {
    $btnPEEQ.Enabled = $enabled
    $btnInject.Enabled = $enabled
    $btnCheck.Enabled = $enabled
}

$script:opTimer = New-Object System.Windows.Forms.Timer
$script:opTimer.Interval = 500
$script:opTimer.Add_Tick({
    if ($script:currentProcess -eq $null) { return }

    if ($script:currentProcess.HasExited) {
        $rc = $script:currentProcess.ExitCode
        $op = $script:currentOperation
        $title = $script:currentTitle

        $script:opTimer.Stop()
        Set-OperationButtonsEnabled $true

        if ($rc -eq 0) {
            $status.Text = "状态：$title 完成"

            if ($op -eq "peeq_export") {
                [System.Windows.Forms.MessageBox]::Show(
                    "PEEQCP 计算完成。`n`n已完成全帧累积，并保存下压首/末帧以及每个摩擦循环 T0/T25/T50/T75/T100 的目标帧结果。`n`n可以继续执行：③ 写回 PEEQCP 到目标帧。",
                    "PEEQCP 计算完成",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
            elseif ($op -eq "peeq_inject") {
                [System.Windows.Forms.MessageBox]::Show(
                    "PEEQCP 已成功写回 ODB 的目标帧。`n`n请重新打开 Abaqus/Viewer，或点击 ④ 检查目标帧 PEEQCP。",
                    "PEEQCP 写回完成",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
        }
        else {
            $status.Text = "状态：$title 失败，返回码 $rc"
            [System.Windows.Forms.MessageBox]::Show(
                "$title 未正常完成。`n返回码：$rc`n`n请查看刚才的命令行输出和输出目录中的日志文件。",
                "运行失败",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }

        try { $script:currentProcess.Dispose() } catch {}
        $script:currentProcess = $null
        $script:currentOperation = ""
        $script:currentTitle = ""
    }
})

function Run-AbaqusOperation([string]$operation, [string]$title) {
    if (-not (Validate-Inputs)) { return }

    if ($script:currentProcess -ne $null -and -not $script:currentProcess.HasExited) {
        [System.Windows.Forms.MessageBox]::Show("已有一个后处理任务正在运行，请等待它完成。","提示") | Out-Null
        return
    }

    $odb = $txtOdb.Text
    $outroot = $txtOut.Text

    $status.Text = "状态：正在运行 $title ..."

    $cmd = "abaqus python `"$masterPy`" --operation $operation --odb `"$odb`" --outroot `"$outroot`""

    # /c keeps the console visible while Abaqus Python runs, then closes it when finished.
    # The GUI polls the cmd process and shows a completion/failure popup automatically.
    $script:currentOperation = $operation
    $script:currentTitle = $title
    Set-OperationButtonsEnabled $false

    try {
        $script:currentProcess = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $cmd) -PassThru
        $script:opTimer.Start()
    }
    catch {
        Set-OperationButtonsEnabled $true
        $script:currentProcess = $null
        $status.Text = "状态：启动失败"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,"启动失败") | Out-Null
    }
}

$btnPEEQ.Add_Click({
    Run-AbaqusOperation "peeq_export" "PEEQCP 目标帧计算"
})

$btnInject.Add_Click({
    if (-not (Validate-Inputs)) { return }

    $ans = [System.Windows.Forms.MessageBox]::Show(
        "写回 PEEQCP 前必须关闭 Abaqus/Viewer，否则 ODB 可能被锁定。`n`n确认继续？",
        "写回确认",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
        Run-AbaqusOperation "peeq_inject" "PEEQCP 目标帧写回"
    }
})

$btnCheck.Add_Click({
    Run-AbaqusOperation "peeq_check" "PEEQCP 目标帧检查"
})

if($Language -eq 'en') {
    $form.Text='ODB2VTU-S | Edit - Friction CPFEM (PEEQCP)'
    $lblOdb.Text='ODB file:'; $btnOdb.Text='Browse ODB'
    $lblOut.Text='Output folder:'; $btnOut.Text='Browse...'
    $lblInfo.Text='Accumulate PEEQCP over all frames. Target frames: first/last normal loading frame and T0/T25/T50/T75/T100 per sliding cycle.'
    $btnPEEQ.Text='1. Compute PEEQCP (all frames)'
    $btnInject.Text='2. Write PEEQCP into ODB'
    $btnCheck.Text='3. Check PEEQCP in target frames'
    $status.Text='Status: waiting'
} else {
    $form.Text='ODB2VTU-S | 摩擦 CPFEM 后处理（PEEQCP）'
    $lblInfo.Text='逐帧累积 PEEQCP，下压首/末帧和摩擦循环 T0/T25/T50/T75/T100 为目标帧。'
}
[void]$form.ShowDialog()
